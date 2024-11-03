local native = {
    does_anim_dict_exist = DoesAnimDictExist,
    has_anim_dict_loaded = HasAnimDictLoaded,
    request_anim_dict = RequestAnimDict,
    remove_anim_dict = RemoveAnimDict,
    is_model_valid = IsModelValid,
    has_model_loaded = HasModelLoaded,
    request_model = RequestModel,
    set_model_as_no_longer_needed = SetModelAsNoLongerNeeded,
    citizen_wait = Citizen.Wait,
}

local function request_animdict(in_animdict)
    lib.validate.type.assert(in_animdict, "string")

    if (not native.does_anim_dict_exist(in_animdict)) then
        error(("animdict \"%s\" was not exist"):format(in_animdict))
    end

    if (native.has_anim_dict_loaded(in_animdict)) then
        return true
    end

    native.request_anim_dict(in_animdict)
    while native.has_anim_dict_loaded(in_animdict) do
        native.citizen_wait(0)
    end

    return true
end

local function request_model(in_model)
    lib.validate.type.assert(in_model, "string", "number")

    local model_hash = type(in_model) == "number" and in_model or joaat(in_model)

    if (not native.is_model_valid(model_hash)) then
        error(("model \"%s\" is not valid"):format(in_model))
    end

    if (native.has_model_loaded(model_hash)) then
        return true
    end

    native.request_model(model_hash)
    while native.has_model_loaded(model_hash) do
        native.citizen_wait(0)
    end

    return true
end

lib_module.animdict = {
    request = setmetatable({}, {
        __call = function(_, ...)
            return lib.taskify(request_animdict)(...)
        end,
    }),
    clear = native.remove_anim_dict,
    has_loaded = native.has_anim_dict_loaded,
    is_valid = native.does_anim_dict_exist,
}

lib_module.model = {
    request = setmetatable({}, {
        __call = function(_, ...)
            return lib.taskify(request_model)(...)
        end,
    }),
    clear = native.set_model_as_no_longer_needed,
    has_loaded = native.has_model_loaded,
    is_valid = native.is_model_valid,
}
