local lib = require "src.imports._lib.shared"

local is_server = lib.is_server
local resource_name = (GetCurrentResourceName and GetCurrentResourceName()) or "censorlib"
local table_unpack = table.unpack
local table_pack = table.pack
local table_insert = table.insert
local table_remove = table.remove
local create_thread_now = (Citizen and Citizen.CreateThreadNow) or function(fn) coroutine.wrap(fn)() end
local citizen_await = (Citizen and Citizen.Await) or function(p) return p end

local log_error = (lib.print and lib.print.error) or function(...) print("[ERROR]", ...) end
local log_warn = (lib.print and lib.print.warn) or function(...) print("[WARN]", ...) end

local msg_net_event = ("cslib.bus:%s:msg"):format(resource_name)
local req_net_event = ("cslib.bus:%s:req"):format(resource_name)
local rep_net_event = ("cslib.bus:%s:rep"):format(resource_name)

-----------------------------------------------------------------------------------------------
-- Pattern compilation & wildcard matching
-----------------------------------------------------------------------------------------------

local pattern_cache = {}

local function compile_pattern(pattern_str)
    local cached = pattern_cache[pattern_str]
    if cached ~= nil then return cached end

    if not pattern_str:find("[%*%?]") then
        pattern_cache[pattern_str] = false
        return false
    end

    if pattern_str == "**" or pattern_str == "*" then
        local compiled = ".*"
        pattern_cache[pattern_str] = compiled
        return compiled
    end

    -- Escape Lua magic characters except * and ?
    local s = pattern_str:gsub("%%", "%%%%")
    s = s:gsub("([%^%$%(%)%[%]%+%.%-])", "%%%1")

    -- Replace ** with multi-segment token
    s = s:gsub("%*%*", "\1")
    -- Replace * with single-segment pattern (delimited by : . /)
    s = s:gsub("%*", "([^%%.:/]+)")
    -- Replace token with multi-segment pattern
    s = s:gsub("\1", "(.-)")
    -- Replace ? with single character pattern
    s = s:gsub("%?", "([^%%.:/])")

    local compiled = "^" .. s .. "$"
    pattern_cache[pattern_str] = compiled
    return compiled
end

-----------------------------------------------------------------------------------------------
-- Helper: Insert sorted by priority (descending), stable FIFO for equal priority
-----------------------------------------------------------------------------------------------

local function insert_sorted(list, item)
    local n = #list
    local insert_idx = n + 1
    for i = 1, n do
        local curr = list[i]
        if item.priority > curr.priority then
            insert_idx = i
            break
        end
    end
    table_insert(list, insert_idx, item)
end

-----------------------------------------------------------------------------------------------
-- Bus Class & Instances Registry
-----------------------------------------------------------------------------------------------

local bus_class = {}
bus_class.__index = bus_class

local bus_instances = {}
local auto_bus_seq = 0
local default_bus = nil

local function resolve_bus(self_or_topic)
    if type(self_or_topic) == "table" and self_or_topic._is_bus then
        return self_or_topic, true
    end
    return default_bus, false
end

local function extract_args(self_or_topic, ...)
    if type(self_or_topic) == "table" and self_or_topic._is_bus then
        return self_or_topic, ...
    end
    return default_bus, self_or_topic, ...
end

function bus_class.new(options)
    local opts = type(options) == "table" and options or { id = options }
    auto_bus_seq = auto_bus_seq + 1
    local id = opts.id or opts.name or ("bus_%d"):format(auto_bus_seq)

    local self = setmetatable({}, bus_class)
    self.id = tostring(id)
    self._is_bus = true
    self._next_id = 0
    self._next_seq = 0
    self._next_req_id = 0

    -- Local pub/sub tables
    self._exact = {}
    self._wildcards = {}
    self._responders = {}

    -- Remote pub/sub tables
    self._remote_exact = {}
    self._remote_wildcards = {}
    self._remote_responders = {}

    -- Middlewares & Requests
    self._middlewares = {}
    self._pending_requests = {}

    -- Re-entrancy & cleanup
    self._pending_removals = nil
    self._locked = 0
    self._timeout = opts.timeout or 5000
    self._destroyed = false

    bus_instances[self.id] = self
    return self
end

function bus_class:_next_seq_id()
    self._next_seq = self._next_seq + 1
    return self._next_seq
end

function bus_class:_next_listener_id()
    self._next_id = self._next_id + 1
    return self._next_id
end

function bus_class:_next_request_id()
    self._next_req_id = self._next_req_id + 1
    return ("%s:%s:%d"):format(resource_name, self.id, self._next_req_id)
end

function bus_class:set_timeout(timeout_ms)
    assert(type(timeout_ms) == "number" and timeout_ms > 0, "timeout must be a positive number in milliseconds")
    self._timeout = timeout_ms
end

-----------------------------------------------------------------------------------------------
-- Removal & Flush Helpers
-----------------------------------------------------------------------------------------------

function bus_class:_delete_entry(entry, is_remote)
    entry.removed = true
    if is_remote then
        if entry.is_pattern then
            for i = #self._remote_wildcards, 1, -1 do
                if self._remote_wildcards[i] == entry then
                    table_remove(self._remote_wildcards, i)
                    break
                end
            end
        else
            local list = self._remote_exact[entry.topic]
            if list then
                for i = #list, 1, -1 do
                    if list[i] == entry then
                        table_remove(list, i)
                        break
                    end
                end
                if #list == 0 then
                    self._remote_exact[entry.topic] = nil
                end
            end
        end
    else
        if entry.is_pattern then
            for i = #self._wildcards, 1, -1 do
                if self._wildcards[i] == entry then
                    table_remove(self._wildcards, i)
                    break
                end
            end
        else
            local list = self._exact[entry.topic]
            if list then
                for i = #list, 1, -1 do
                    if list[i] == entry then
                        table_remove(list, i)
                        break
                    end
                end
                if #list == 0 then
                    self._exact[entry.topic] = nil
                end
            end
        end
    end
end

function bus_class:_remove_entry(entry, is_remote)
    entry.removed = true
    if self._locked > 0 then
        self._pending_removals = self._pending_removals or {}
        self._pending_removals[entry.id] = { entry = entry, is_remote = is_remote }
        return
    end
    self:_delete_entry(entry, is_remote)
end

function bus_class:_flush_pending_removals()
    if self._locked == 0 and self._pending_removals then
        local pending = self._pending_removals
        self._pending_removals = nil
        for _, item in pairs(pending) do
            self:_delete_entry(item.entry, item.is_remote)
        end
    end
end

-----------------------------------------------------------------------------------------------
-- Local Pub/Sub
-----------------------------------------------------------------------------------------------

function bus_class.on(self_or_topic, ...)
    local self, topic, handler, priority_or_opts = extract_args(self_or_topic, ...)
    assert(type(topic) == "string" and topic ~= "", "topic must be a non-empty string")
    assert(type(handler) == "function", "handler must be a function")

    local priority = 0
    local once = false
    local pass_topic = false

    if type(priority_or_opts) == "number" then
        priority = priority_or_opts
    elseif type(priority_or_opts) == "table" then
        priority = priority_or_opts.priority or 0
        once = priority_or_opts.once or false
        pass_topic = priority_or_opts.pass_topic or false
    end

    local pattern = compile_pattern(topic)
    local is_pattern = (pattern ~= false)

    local entry = {
        id = self:_next_listener_id(),
        seq = self:_next_seq_id(),
        topic = topic,
        handler = handler,
        priority = priority,
        once = once,
        pass_topic = pass_topic,
        is_pattern = is_pattern,
        pattern = pattern,
        bus = self,
        removed = false,
    }

    if is_pattern then
        insert_sorted(self._wildcards, entry)
    else
        local list = self._exact[topic]
        if not list then
            list = {}
            self._exact[topic] = list
        end
        insert_sorted(list, entry)
    end

    local unsubscribed = false
    return function()
        if unsubscribed then return end
        unsubscribed = true
        self:_remove_entry(entry, false)
    end
end

bus_class.subscribe = bus_class.on
bus_class.listen = bus_class.on

function bus_class.once(self_or_topic, ...)
    local self, topic, handler, priority_or_opts = extract_args(self_or_topic, ...)
    local opts = type(priority_or_opts) == "table" and priority_or_opts or { priority = priority_or_opts or 0 }
    opts.once = true
    return self:on(topic, handler, opts)
end

function bus_class.off(self_or_topic, ...)
    local self, topic, id_or_handler = extract_args(self_or_topic, ...)
    assert(type(topic) == "string", "topic must be a string")

    local pattern = compile_pattern(topic)
    local is_pattern = (pattern ~= false)
    local list = is_pattern and self._wildcards or self._exact[topic]
    if not list then return end

    for i = #list, 1, -1 do
        local entry = list[i]
        if entry.topic == topic then
            if not id_or_handler or entry.handler == id_or_handler or entry.id == id_or_handler then
                self:_remove_entry(entry, false)
            end
        end
    end
end

bus_class.unsubscribe = bus_class.off

function bus_class.has(self_or_topic, ...)
    local self, topic = extract_args(self_or_topic, ...)
    if self._exact[topic] and #self._exact[topic] > 0 then
        return true
    end
    for i = 1, #self._wildcards do
        if not self._wildcards[i].removed and topic:match(self._wildcards[i].pattern) then
            return true
        end
    end
    return false
end

function bus_class.listener_count(self_or_topic, ...)
    local self, topic = extract_args(self_or_topic, ...)
    local count = 0
    if self._exact[topic] then
        count = count + #self._exact[topic]
    end
    for i = 1, #self._wildcards do
        if not self._wildcards[i].removed and topic:match(self._wildcards[i].pattern) then
            count = count + 1
        end
    end
    return count
end

function bus_class.clear(self_or_topic, ...)
    local self, topic = extract_args(self_or_topic, ...)
    if topic then
        self:off(topic)
    else
        self._exact = {}
        self._wildcards = {}
    end
end

-----------------------------------------------------------------------------------------------
-- Middleware
-----------------------------------------------------------------------------------------------

function bus_class.use(self_or_topic, ...)
    local self, topic_or_fn, maybe_fn = extract_args(self_or_topic, ...)
    local topic, fn
    if type(topic_or_fn) == "function" then
        topic = "*"
        fn = topic_or_fn
    else
        topic = topic_or_fn
        fn = maybe_fn
    end

    assert(type(fn) == "function", "middleware must be a function")
    local pattern = compile_pattern(topic)

    local mw = {
        topic = topic,
        pattern = pattern,
        fn = fn,
    }
    table_insert(self._middlewares, mw)

    return function()
        for i = #self._middlewares, 1, -1 do
            if self._middlewares[i] == mw then
                table_remove(self._middlewares, i)
                break
            end
        end
    end
end

-----------------------------------------------------------------------------------------------
-- Local Emission
-----------------------------------------------------------------------------------------------

function bus_class:_emit_internal(topic, ...)
    if self._destroyed then return false end

    -- Run middlewares
    if #self._middlewares > 0 then
        for i = 1, #self._middlewares do
            local mw = self._middlewares[i]
            if mw.topic == "*" or mw.topic == topic or (mw.pattern and topic:match(mw.pattern)) then
                local ok, pass = xpcall(mw.fn, debug.traceback, topic, ...)
                if not ok then
                    log_error(("^1[bus] error in middleware for topic '%s': %s^7"):format(topic, tostring(pass)))
                elseif pass == false then
                    return false
                end
            end
        end
    end

    local exact_list = self._exact[topic]
    local wildcard_list = self._wildcards

    local matching_wildcards = nil
    if #wildcard_list > 0 then
        for i = 1, #wildcard_list do
            local w = wildcard_list[i]
            if not w.removed and topic:match(w.pattern) then
                matching_wildcards = matching_wildcards or {}
                matching_wildcards[#matching_wildcards + 1] = w
            end
        end
    end

    local listeners_to_run = nil
    if not matching_wildcards or #matching_wildcards == 0 then
        if not exact_list or #exact_list == 0 then
            return true
        end
        listeners_to_run = exact_list
    elseif not exact_list or #exact_list == 0 then
        listeners_to_run = matching_wildcards
    else
        local merged = {}
        local i, j = 1, 1
        local n1, n2 = #exact_list, #matching_wildcards
        while i <= n1 and j <= n2 do
            local a, b = exact_list[i], matching_wildcards[j]
            if a.priority >= b.priority then
                merged[#merged + 1] = a
                i = i + 1
            else
                merged[#merged + 1] = b
                j = j + 1
            end
        end
        while i <= n1 do
            merged[#merged + 1] = exact_list[i]
            i = i + 1
        end
        while j <= n2 do
            merged[#merged + 1] = matching_wildcards[j]
            j = j + 1
        end
        listeners_to_run = merged
    end

    self._locked = self._locked + 1
    local prev_topic = self.current_topic
    self.current_topic = topic

    local stopped = false
    local n = #listeners_to_run
    for i = 1, n do
        local entry = listeners_to_run[i]
        if not entry.removed and not (self._pending_removals and self._pending_removals[entry.id]) then
            if entry.once then
                self:_remove_entry(entry, false)
            end

            local ok, result
            if entry.pass_topic then
                ok, result = xpcall(entry.handler, debug.traceback, topic, ...)
            else
                ok, result = xpcall(entry.handler, debug.traceback, ...)
            end

            if not ok then
                log_error(("^1[bus] error in listener for topic '%s': %s^7"):format(topic, tostring(result)))
            elseif result == false then
                stopped = true
                break
            end
        end
    end

    self.current_topic = prev_topic
    self._locked = self._locked - 1
    self:_flush_pending_removals()

    return not stopped
end

function bus_class.emit(self_or_topic, ...)
    local bus_inst, is_method = resolve_bus(self_or_topic)
    local topic, args
    if is_method then
        topic = ...
        args = table_pack(select(2, ...))
    else
        topic = self_or_topic
        args = table_pack(...)
    end
    assert(type(topic) == "string", "topic must be a string")
    return bus_inst:_emit_internal(topic, table_unpack(args, 1, args.n))
end

bus_class.publish = bus_class.emit
bus_class.dispatch = bus_class.emit

-----------------------------------------------------------------------------------------------
-- Local Request / Reply
-----------------------------------------------------------------------------------------------

function bus_class.reply(self_or_topic, ...)
    local self, topic, handler = extract_args(self_or_topic, ...)
    assert(type(topic) == "string", "topic must be a string")
    assert(type(handler) == "function", "handler must be a function")
    assert(not self._responders[topic], ("Responder for topic '%s' is already registered on bus '%s'"):format(topic, self.id))

    self._responders[topic] = handler

    return function()
        if self._responders[topic] == handler then
            self._responders[topic] = nil
        end
    end
end

bus_class.respond = bus_class.reply

function bus_class.unreply(self_or_topic, ...)
    local self, topic = extract_args(self_or_topic, ...)
    assert(type(topic) == "string", "topic must be a string")
    self._responders[topic] = nil
end

bus_class.unrespond = bus_class.unreply

local function execute_local_request(self, topic, timeout, ...)
    local responder = self._responders[topic]
    if not responder then
        return nil, ("no responder registered for topic: %s"):format(topic)
    end

    local p = promise.new()
    local timer = lib.set_timeout(function()
        p:resolve({ success = false, error = "timeout" })
    end, timeout)

    local args = table_pack(...)
    create_thread_now(function()
        local ok, results = pcall(function()
            return table_pack(responder(table_unpack(args, 1, args.n)))
        end)
        lib.clear_timer(timer)
        if ok then
            p:resolve({ success = true, values = results })
        else
            log_error(("^1[bus] error in reply handler for '%s': %s^7"):format(topic, tostring(results)))
            p:resolve({ success = false, error = tostring(results) })
        end
    end)

    local outcome = citizen_await(p)
    if outcome.success then
        return table_unpack(outcome.values, 1, outcome.values.n)
    else
        return nil, outcome.error
    end
end

function bus_class.request(self_or_topic, ...)
    local bus_inst, is_method = resolve_bus(self_or_topic)
    local topic, opts, args

    if is_method then
        local first = ...
        if type(first) == "table" and first.topic then
            topic = first.topic
            opts = first
            args = table_pack(select(2, ...))
        else
            topic = first
            local second = select(2, ...)
            if type(second) == "table" and (second.target ~= nil or second.timeout ~= nil) then
                opts = second
                args = table_pack(select(3, ...))
            else
                opts = {}
                args = table_pack(select(2, ...))
            end
        end
    else
        local first = self_or_topic
        if type(first) == "table" and first.topic then
            topic = first.topic
            opts = first
            args = table_pack(...)
        else
            topic = first
            local second = ...
            if type(second) == "table" and (second.target ~= nil or second.timeout ~= nil) then
                opts = second
                args = table_pack(select(2, ...))
            else
                opts = {}
                args = table_pack(...)
            end
        end
    end

    assert(type(topic) == "string", "topic must be a string")
    local timeout = opts.timeout or bus_inst._timeout or 5000
    local target = opts.target

    if target ~= nil then
        if is_server then
            return bus_inst:request_client(topic, target, table_unpack(args, 1, args.n))
        else
            return bus_inst:request_server(topic, table_unpack(args, 1, args.n))
        end
    end

    return lib.async(function()
        return execute_local_request(bus_inst, topic, timeout, table_unpack(args, 1, args.n))
    end)()
end

function bus_class.request_await(self_or_topic, ...)
    local async_handle = bus_class.request(self_or_topic, ...)
    return async_handle:await()
end

-----------------------------------------------------------------------------------------------
-- Remote / Network Pub/Sub
-----------------------------------------------------------------------------------------------

local net_handlers_initialized = false

local function ensure_net_handlers()
    if net_handlers_initialized then return end
    net_handlers_initialized = true

    if is_server then
        if lib.on_client then
            -- 1. Net messages from clients
            lib.on_client(msg_net_event, function(bus_id, topic, ...)
                local src = source
                local bus_inst = bus_instances[bus_id] or (bus_id == "default" and default_bus)
                if not bus_inst then return end
                bus_inst:_dispatch_remote(topic, src, ...)
            end)

            -- 2. Net requests from clients
            lib.on_client(req_net_event, function(bus_id, topic, req_id, ...)
                local src = source
                local bus_inst = bus_instances[bus_id] or (bus_id == "default" and default_bus)
                if not bus_inst then
                    if lib.emit_client_adaptive then
                        lib.emit_client_adaptive(rep_net_event, src, req_id, false, "bus instance not found: " .. tostring(bus_id))
                    end
                    return
                end

                local responder = bus_inst._remote_responders[topic]
                if not responder then
                    if lib.emit_client_adaptive then
                        lib.emit_client_adaptive(rep_net_event, src, req_id, false, "no remote responder registered for: " .. tostring(topic))
                    end
                    return
                end

                local args = table_pack(...)
                create_thread_now(function()
                    local ok, res = pcall(function()
                        return table_pack(responder(src, table_unpack(args, 1, args.n)))
                    end)
                    if ok then
                        if lib.emit_client_adaptive then
                            lib.emit_client_adaptive(rep_net_event, src, req_id, true, res)
                        end
                    else
                        log_error(("^1[bus] error in reply_client for '%s': %s^7"):format(topic, tostring(res)))
                        if lib.emit_client_adaptive then
                            lib.emit_client_adaptive(rep_net_event, src, req_id, false, tostring(res))
                        end
                    end
                end)
            end)

            -- 3. Net replies from clients
            lib.on_client(rep_net_event, function(req_id, ok, results)
                for _, bus_inst in pairs(bus_instances) do
                    local p = bus_inst._pending_requests[req_id]
                    if p then
                        bus_inst._pending_requests[req_id] = nil
                        if ok then
                            p:resolve({ success = true, values = results })
                        else
                            p:resolve({ success = false, error = results })
                        end
                        return
                    end
                end
            end)
        end
    else
        if lib.on_server then
            -- 1. Net messages from server
            lib.on_server(msg_net_event, function(bus_id, topic, ...)
                local bus_inst = bus_instances[bus_id] or (bus_id == "default" and default_bus)
                if not bus_inst then return end
                bus_inst:_dispatch_remote(topic, ...)
            end)

            -- 2. Net requests from server
            lib.on_server(req_net_event, function(bus_id, topic, req_id, ...)
                local bus_inst = bus_instances[bus_id] or (bus_id == "default" and default_bus)
                if not bus_inst then
                    if lib.emit_server_adaptive then
                        lib.emit_server_adaptive(rep_net_event, req_id, false, "bus instance not found: " .. tostring(bus_id))
                    end
                    return
                end

                local responder = bus_inst._remote_responders[topic]
                if not responder then
                    if lib.emit_server_adaptive then
                        lib.emit_server_adaptive(rep_net_event, req_id, false, "no remote responder registered for: " .. tostring(topic))
                    end
                    return
                end

                local args = table_pack(...)
                create_thread_now(function()
                    local ok, res = pcall(function()
                        return table_pack(responder(table_unpack(args, 1, args.n)))
                    end)
                    if ok then
                        if lib.emit_server_adaptive then
                            lib.emit_server_adaptive(rep_net_event, req_id, true, res)
                        end
                    else
                        log_error(("^1[bus] error in reply_server for '%s': %s^7"):format(topic, tostring(res)))
                        if lib.emit_server_adaptive then
                            lib.emit_server_adaptive(rep_net_event, req_id, false, tostring(res))
                        end
                    end
                end)
            end)

            -- 3. Net replies from server
            lib.on_server(rep_net_event, function(req_id, ok, results)
                for _, bus_inst in pairs(bus_instances) do
                    local p = bus_inst._pending_requests[req_id]
                    if p then
                        bus_inst._pending_requests[req_id] = nil
                        if ok then
                            p:resolve({ success = true, values = results })
                        else
                            p:resolve({ success = false, error = results })
                        end
                        return
                    end
                end
            end)
        end
    end
end

function bus_class:_dispatch_remote(topic, ...)
    local exact_list = self._remote_exact[topic]
    local wildcard_list = self._remote_wildcards

    local matching_wildcards = nil
    if #wildcard_list > 0 then
        for i = 1, #wildcard_list do
            local w = wildcard_list[i]
            if not w.removed and topic:match(w.pattern) then
                matching_wildcards = matching_wildcards or {}
                matching_wildcards[#matching_wildcards + 1] = w
            end
        end
    end

    local listeners_to_run = nil
    if not matching_wildcards or #matching_wildcards == 0 then
        if not exact_list or #exact_list == 0 then
            return true
        end
        listeners_to_run = exact_list
    elseif not exact_list or #exact_list == 0 then
        listeners_to_run = matching_wildcards
    else
        local merged = {}
        local i, j = 1, 1
        local n1, n2 = #exact_list, #matching_wildcards
        while i <= n1 and j <= n2 do
            local a, b = exact_list[i], matching_wildcards[j]
            if a.priority >= b.priority then
                merged[#merged + 1] = a
                i = i + 1
            else
                merged[#merged + 1] = b
                j = j + 1
            end
        end
        while i <= n1 do
            merged[#merged + 1] = exact_list[i]
            i = i + 1
        end
        while j <= n2 do
            merged[#merged + 1] = matching_wildcards[j]
            j = j + 1
        end
        listeners_to_run = merged
    end

    self._locked = self._locked + 1
    local prev_topic = self.current_topic
    self.current_topic = topic

    local stopped = false
    local n = #listeners_to_run
    for i = 1, n do
        local entry = listeners_to_run[i]
        if not entry.removed and not (self._pending_removals and self._pending_removals[entry.id]) then
            if entry.once then
                self:_remove_entry(entry, true)
            end

            local ok, result
            if entry.pass_topic then
                ok, result = xpcall(entry.handler, debug.traceback, topic, ...)
            else
                ok, result = xpcall(entry.handler, debug.traceback, ...)
            end

            if not ok then
                log_error(("^1[bus] error in remote listener for topic '%s': %s^7"):format(topic, tostring(result)))
            elseif result == false then
                stopped = true
                break
            end
        end
    end

    self.current_topic = prev_topic
    self._locked = self._locked - 1
    self:_flush_pending_removals()

    return not stopped
end

-----------------------------------------------------------------------------------------------
-- Remote Subscribing (on_remote, on_server, on_client)
-----------------------------------------------------------------------------------------------

local function add_remote_listener(self, topic, handler, priority_or_opts)
    ensure_net_handlers()
    assert(type(topic) == "string" and topic ~= "", "topic must be a non-empty string")
    assert(type(handler) == "function", "handler must be a function")

    local priority = 0
    local once = false
    local pass_topic = false

    if type(priority_or_opts) == "number" then
        priority = priority_or_opts
    elseif type(priority_or_opts) == "table" then
        priority = priority_or_opts.priority or 0
        once = priority_or_opts.once or false
        pass_topic = priority_or_opts.pass_topic or false
    end

    local pattern = compile_pattern(topic)
    local is_pattern = (pattern ~= false)

    local entry = {
        id = self:_next_listener_id(),
        seq = self:_next_seq_id(),
        topic = topic,
        handler = handler,
        priority = priority,
        once = once,
        pass_topic = pass_topic,
        is_pattern = is_pattern,
        pattern = pattern,
        bus = self,
        removed = false,
    }

    if is_pattern then
        insert_sorted(self._remote_wildcards, entry)
    else
        local list = self._remote_exact[topic]
        if not list then
            list = {}
            self._remote_exact[topic] = list
        end
        insert_sorted(list, entry)
    end

    local unsubscribed = false
    return function()
        if unsubscribed then return end
        unsubscribed = true
        self:_remove_entry(entry, true)
    end
end

function bus_class.on_remote(self_or_topic, ...)
    local self, topic, handler, priority_or_opts = extract_args(self_or_topic, ...)
    return add_remote_listener(self, topic, handler, priority_or_opts)
end

function bus_class.once_remote(self_or_topic, ...)
    local self, topic, handler, priority_or_opts = extract_args(self_or_topic, ...)
    local opts = type(priority_or_opts) == "table" and priority_or_opts or { priority = priority_or_opts or 0 }
    opts.once = true
    return add_remote_listener(self, topic, handler, opts)
end

function bus_class.on_client(self_or_topic, ...)
    assert(is_server, "bus:on_client can only be registered on the server")
    return bus_class.on_remote(self_or_topic, ...)
end

function bus_class.once_client(self_or_topic, ...)
    assert(is_server, "bus:once_client can only be registered on the server")
    return bus_class.once_remote(self_or_topic, ...)
end

function bus_class.on_server(self_or_topic, ...)
    assert(not is_server, "bus:on_server can only be registered on the client")
    return bus_class.on_remote(self_or_topic, ...)
end

function bus_class.once_server(self_or_topic, ...)
    assert(not is_server, "bus:once_server can only be registered on the client")
    return bus_class.once_remote(self_or_topic, ...)
end

function bus_class.off_remote(self_or_topic, ...)
    local self, topic, id_or_handler = extract_args(self_or_topic, ...)
    assert(type(topic) == "string", "topic must be a string")

    local pattern = compile_pattern(topic)
    local is_pattern = (pattern ~= false)
    local list = is_pattern and self._remote_wildcards or self._remote_exact[topic]
    if not list then return end

    for i = #list, 1, -1 do
        local entry = list[i]
        if entry.topic == topic then
            if not id_or_handler or entry.handler == id_or_handler or entry.id == id_or_handler then
                self:_remove_entry(entry, true)
            end
        end
    end
end

-----------------------------------------------------------------------------------------------
-- Remote Publishing (emit_server, emit_client, emit_all_clients, broadcast)
-----------------------------------------------------------------------------------------------

function bus_class.emit_server(self_or_topic, ...)
    assert(not is_server, "bus:emit_server can only be called from the client")
    ensure_net_handlers()
    local bus_inst, is_method = resolve_bus(self_or_topic)
    local topic, args
    if is_method then
        topic = ...
        args = table_pack(select(2, ...))
    else
        topic = self_or_topic
        args = table_pack(...)
    end
    assert(type(topic) == "string", "topic must be a string")
    lib.emit_server_adaptive(msg_net_event, bus_inst.id, topic, table_unpack(args, 1, args.n))
end

bus_class.publish_server = bus_class.emit_server

function bus_class.emit_client(self_or_topic, ...)
    assert(is_server, "bus:emit_client can only be called from the server")
    ensure_net_handlers()
    local bus_inst, is_method = resolve_bus(self_or_topic)
    local topic, target, args
    if is_method then
        topic = ...
        target = select(2, ...)
        args = table_pack(select(3, ...))
    else
        topic = self_or_topic
        target = ...
        args = table_pack(select(2, ...))
    end
    assert(type(topic) == "string", "topic must be a string")
    assert(type(target) == "number" or (type(target) == "string" and tonumber(target)), "target must be a valid client ID")
    lib.emit_client_adaptive(msg_net_event, tonumber(target), bus_inst.id, topic, table_unpack(args, 1, args.n))
end

bus_class.publish_client = bus_class.emit_client

function bus_class.emit_all_clients(self_or_topic, ...)
    assert(is_server, "bus:emit_all_clients can only be called from the server")
    ensure_net_handlers()
    local bus_inst, is_method = resolve_bus(self_or_topic)
    local topic, args
    if is_method then
        topic = ...
        args = table_pack(select(2, ...))
    else
        topic = self_or_topic
        args = table_pack(...)
    end
    assert(type(topic) == "string", "topic must be a string")
    lib.emit_all_clients_adaptive(msg_net_event, bus_inst.id, topic, table_unpack(args, 1, args.n))
end

bus_class.publish_all_clients = bus_class.emit_all_clients

function bus_class.emit_clients(self_or_topic, ...)
    assert(is_server, "bus:emit_clients can only be called from the server")
    ensure_net_handlers()
    local bus_inst, is_method = resolve_bus(self_or_topic)
    local topic, clients, args
    if is_method then
        topic = ...
        clients = select(2, ...)
        args = table_pack(select(3, ...))
    else
        topic = self_or_topic
        clients = ...
        args = table_pack(select(2, ...))
    end
    assert(type(topic) == "string", "topic must be a string")
    assert(type(clients) == "table", "clients must be a table array of client IDs")
    lib.emit_clients_adaptive(msg_net_event, clients, bus_inst.id, topic, table_unpack(args, 1, args.n))
end

function bus_class.emit_remote(self_or_topic, ...)
    local bus_inst, is_method = resolve_bus(self_or_topic)
    local topic, first_arg, args
    if is_method then
        topic = ...
        first_arg = select(2, ...)
        args = table_pack(select(3, ...))
    else
        topic = self_or_topic
        first_arg = ...
        args = table_pack(select(2, ...))
    end
    assert(type(topic) == "string", "topic must be a string")

    if not is_server then
        if first_arg ~= nil then
            return bus_inst:emit_server(topic, first_arg, table_unpack(args, 1, args.n))
        else
            return bus_inst:emit_server(topic)
        end
    end

    if type(first_arg) == "number" or (type(first_arg) == "string" and tonumber(first_arg)) then
        local target = tonumber(first_arg)
        if target == -1 then
            return bus_inst:emit_all_clients(topic, table_unpack(args, 1, args.n))
        else
            return bus_inst:emit_client(topic, target, table_unpack(args, 1, args.n))
        end
    elseif type(first_arg) == "table" then
        return bus_inst:emit_clients(topic, first_arg, table_unpack(args, 1, args.n))
    else
        if first_arg ~= nil then
            return bus_inst:emit_all_clients(topic, first_arg, table_unpack(args, 1, args.n))
        else
            return bus_inst:emit_all_clients(topic)
        end
    end
end

bus_class.publish_remote = bus_class.emit_remote

function bus_class.broadcast(self_or_topic, ...)
    local bus_inst, is_method = resolve_bus(self_or_topic)
    local topic, args
    if is_method then
        topic = ...
        args = table_pack(select(2, ...))
    else
        topic = self_or_topic
        args = table_pack(...)
    end
    assert(type(topic) == "string", "topic must be a string")

    -- 1. Emit locally
    bus_inst:_emit_internal(topic, table_unpack(args, 1, args.n))

    -- 2. Emit across network
    if is_server then
        bus_inst:emit_all_clients(topic, table_unpack(args, 1, args.n))
    else
        bus_inst:emit_server(topic, table_unpack(args, 1, args.n))
    end
end

-----------------------------------------------------------------------------------------------
-- Remote Request / Reply
-----------------------------------------------------------------------------------------------

function bus_class.reply_remote(self_or_topic, ...)
    ensure_net_handlers()
    local self, topic, handler = extract_args(self_or_topic, ...)
    assert(type(topic) == "string", "topic must be a string")
    assert(type(handler) == "function", "handler must be a function")
    assert(not self._remote_responders[topic], ("Remote responder for topic '%s' is already registered on bus '%s'"):format(topic, self.id))

    self._remote_responders[topic] = handler

    return function()
        if self._remote_responders[topic] == handler then
            self._remote_responders[topic] = nil
        end
    end
end

bus_class.respond_remote = bus_class.reply_remote

function bus_class.unreply_remote(self_or_topic, ...)
    local self, topic = extract_args(self_or_topic, ...)
    assert(type(topic) == "string", "topic must be a string")
    self._remote_responders[topic] = nil
end

bus_class.unrespond_remote = bus_class.unreply_remote

function bus_class.reply_client(self_or_topic, ...)
    assert(is_server, "bus:reply_client can only be registered on the server")
    return bus_class.reply_remote(self_or_topic, ...)
end

function bus_class.reply_server(self_or_topic, ...)
    assert(not is_server, "bus:reply_server can only be registered on the client")
    return bus_class.reply_remote(self_or_topic, ...)
end

function bus_class.request_server(self_or_topic, ...)
    assert(not is_server, "bus:request_server can only be called from the client")
    ensure_net_handlers()
    local bus_inst, is_method = resolve_bus(self_or_topic)
    local topic, args
    if is_method then
        topic = ...
        args = table_pack(select(2, ...))
    else
        topic = self_or_topic
        args = table_pack(...)
    end
    assert(type(topic) == "string", "topic must be a string")
    local timeout = bus_inst._timeout or 5000

    return lib.async(function()
        local req_id = bus_inst:_next_request_id()
        local p = promise.new()
        bus_inst._pending_requests[req_id] = p

        local timer = lib.set_timeout(function()
            if bus_inst._pending_requests[req_id] then
                bus_inst._pending_requests[req_id] = nil
                p:resolve({ success = false, error = "timeout" })
            end
        end, timeout)

        lib.emit_server_adaptive(req_net_event, bus_inst.id, topic, req_id, table_unpack(args, 1, args.n))
        local outcome = citizen_await(p)
        lib.clear_timer(timer)

        if outcome.success then
            return table_unpack(outcome.values, 1, outcome.values.n)
        else
            return nil, outcome.error
        end
    end)()
end

function bus_class.request_client(self_or_topic, ...)
    assert(is_server, "bus:request_client can only be called from the server")
    ensure_net_handlers()
    local bus_inst, is_method = resolve_bus(self_or_topic)
    local topic, target, args
    if is_method then
        topic = ...
        target = select(2, ...)
        args = table_pack(select(3, ...))
    else
        topic = self_or_topic
        target = ...
        args = table_pack(select(2, ...))
    end
    assert(type(topic) == "string", "topic must be a string")
    assert(type(target) == "number" or (type(target) == "string" and tonumber(target)), "target must be a valid client ID")
    local timeout = bus_inst._timeout or 5000

    return lib.async(function()
        local req_id = bus_inst:_next_request_id()
        local p = promise.new()
        bus_inst._pending_requests[req_id] = p

        local timer = lib.set_timeout(function()
            if bus_inst._pending_requests[req_id] then
                bus_inst._pending_requests[req_id] = nil
                p:resolve({ success = false, error = "timeout" })
            end
        end, timeout)

        lib.emit_client_adaptive(req_net_event, tonumber(target), bus_inst.id, topic, req_id, table_unpack(args, 1, args.n))
        local outcome = citizen_await(p)
        lib.clear_timer(timer)

        if outcome.success then
            return table_unpack(outcome.values, 1, outcome.values.n)
        else
            return nil, outcome.error
        end
    end)()
end

function bus_class.request_remote(self_or_topic, ...)
    local bus_inst, is_method = resolve_bus(self_or_topic)
    local topic, args
    if is_method then
        topic = ...
        args = table_pack(select(2, ...))
    else
        topic = self_or_topic
        args = table_pack(...)
    end

    if is_server then
        local target = args[1]
        local sliced = {}
        for i = 2, args.n do sliced[#sliced + 1] = args[i] end
        return bus_inst:request_client(topic, target, table_unpack(sliced))
    else
        return bus_inst:request_server(topic, table_unpack(args, 1, args.n))
    end
end


-----------------------------------------------------------------------------------------------
-- Destroy
-----------------------------------------------------------------------------------------------

function bus_class:destroy()
    if self._destroyed then return end
    self._destroyed = true

    self:clear()
    self._remote_exact = {}
    self._remote_wildcards = {}
    self._responders = {}
    self._remote_responders = {}
    self._middlewares = {}

    for req_id, p in pairs(self._pending_requests) do
        p:resolve({ success = false, error = "bus destroyed" })
    end
    self._pending_requests = {}

    if self.id ~= "default" then
        bus_instances[self.id] = nil
    end
end

-----------------------------------------------------------------------------------------------
-- Default Bus Instance Setup & Export
-----------------------------------------------------------------------------------------------

default_bus = bus_class.new({ id = "default", name = "default" })
default_bus.new = bus_class.new

local default_bus_mt = {
    __index = bus_class,
    __call = function(_, ...)
        return bus_class.new(...)
    end,
}
setmetatable(default_bus, default_bus_mt)

return default_bus
