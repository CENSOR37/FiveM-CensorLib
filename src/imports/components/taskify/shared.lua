local table_unpack = table.unpack
local table_pack = table.pack
local create_thread_now = Citizen.CreateThreadNow
local citizen_await = Citizen.Await

local alias_fields = {
    ["done"] = "after",
    ["then"] = "after", -- i wish i could use this, but it's a reserved keyword
}

local function taskify(fn_handler)
    local is_used = false

    return setmetatable({}, {
        __call = function(_, ...)
            local args = { ... }
            local dispatcher = lib.delegate()
            local return_packed = nil

            create_thread_now(function()
                return_packed = table_pack(fn_handler(table_unpack(args)))
                dispatcher:broadcast(table_unpack(return_packed))
            end)

            return setmetatable({
                after = function(callback)
                    assert(not is_used, "taskify can only be used once")

                    is_used = true

                    lib.validate.type.assert(callback, "function")

                    if (return_packed) then
                        callback(table_unpack(return_packed))
                        return
                    end

                    dispatcher:add(callback)
                end,

                await = function()
                    assert(not is_used, "taskify can only be used once")

                    is_used = true

                    if (return_packed) then
                        return table_unpack(return_packed)
                    end

                    local p = promise.new()

                    dispatcher:add(function(...)
                        p:resolve({ params = { ... } })
                    end)

                    return table_unpack(citizen_await(p).params)
                end,
            }, {
                __index = function(self, key)
                    local alias = alias_fields[key]

                    if alias then
                        return self[alias]
                    end

                    return rawget(self, key)
                end,
            })
        end,
    })
end

lib_module = taskify
