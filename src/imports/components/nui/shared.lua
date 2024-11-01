local native = {
    send_nui_message = SendNuiMessage,
    set_nui_focus = SetNuiFocus,
    is_nui_focused = IsNuiFocused,
    register_nui_callback = RegisterNuiCallback,
}

local meta_index = {}
local is_nui_ready = false
local on_ready = lib.delegate()

function meta_index.emit(name, ...)
    lib.validate.type.assert(name, "string")

    local payload = {
        action = name,
        args = { ... },
    }
    local json_payload = json.encode(payload)

    if (is_nui_ready) then
        native.send_nui_message(json_payload)
        return
    end

    on_ready:add(function()
        native.send_nui_message(json_payload)
    end)
end

function meta_index.on(name, listener)
    lib.validate.type.assert(name, "string")
    lib.validate.type.assert(listener, "function")

    native.register_nui_callback(name, function(data, cb)
        data = data or {}
        cb(listener(table.unpack(data)) or 1)
    end)
end

function meta_index.on_ready(listener)
    lib.validate.type.assert(listener, "function")

    if (is_nui_ready) then
        listener()
        return
    end

    on_ready:add(listener)
end

function meta_index.focus(has_focus, has_cursor)
    native.set_nui_focus(has_focus, has_cursor)
end

function meta_index.set_ready()
    is_nui_ready = true
    on_ready:broadcast()
end

local nui = setmetatable({}, {
    __index = function(_, k)
        if (k == "is_ready") then
            return is_nui_ready
        end

        if (k == "is_focus") then
            return native.is_nui_focused()
        end

        if (k == "is_focused") then
            return native.is_nui_focused()
        end

        return meta_index[k]
    end,
})

lib_module = nui
