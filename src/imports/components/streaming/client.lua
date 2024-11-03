local native = {
    citizen_wait = Citizen.Wait,
    -- anim_dict
    does_anim_dict_exist = DoesAnimDictExist,
    has_anim_dict_loaded = HasAnimDictLoaded,
    request_anim_dict = RequestAnimDict,
    remove_anim_dict = RemoveAnimDict,
    -- model
    is_model_valid = IsModelValid,
    has_model_loaded = HasModelLoaded,
    request_model = RequestModel,
    set_model_as_no_longer_needed = SetModelAsNoLongerNeeded,
    -- anim_set
    has_anim_set_loaded = HasAnimSetLoaded,
    remove_anim_set = RemoveAnimSet,
    request_anim_set = RequestAnimSet,
    -- streamed_texture_dict
    has_streamed_texture_dict_loaded = HasStreamedTextureDictLoaded,
    request_streamed_texture_dict = RequestStreamedTextureDict,
    set_streamed_texture_dict_as_no_longer_needed = SetStreamedTextureDictAsNoLongerNeeded,
    -- named_ptfx_asset
    has_named_ptfx_asset_loaded = HasNamedPtfxAssetLoaded,
    request_named_ptfx_asset = RequestNamedPtfxAsset,
    remove_named_ptfx_asset = RemoveNamedPtfxAsset,
    -- scaleform
    has_scaleform_movie_loaded = HasScaleformMovieLoaded,
    request_scaleform_movie = RequestScaleformMovie,
    set_scaleform_movie_as_no_longer_needed = SetScaleformMovieAsNoLongerNeeded,
    -- weapon_asset
    has_weapon_asset_loaded = HasWeaponAssetLoaded,
    request_weapon_asset = RequestWeaponAsset,
    remove_weapon_asset = RemoveWeaponAsset,
}

local function warpper(request_fn, clear, has_loaded, is_valid)
    return {
        request = setmetatable({}, {
            __call = function(_, ...)
                return lib.taskify(request_fn)(...)
            end,
        }),
        clear = clear,
        has_loaded = has_loaded,
        is_valid = is_valid and is_valid or function() error("not implemented") end,
    }
end

local function request_streaming(has_loaded, request, ...)
    if (has_loaded(...)) then
        return true
    end

    request(...)

    while not has_loaded(...) do
        native.citizen_wait(0)
    end

    return true
end

local function request_anim_dict(in_animdict)
    lib.validate.type.assert(in_animdict, "string")

    if (not native.does_anim_dict_exist(in_animdict)) then
        error(("animdict \"%s\" was not exist"):format(in_animdict))
    end

    return request_streaming(native.has_anim_dict_loaded, native.request_anim_dict, in_animdict)
end

local function request_model(in_model)
    lib.validate.type.assert(in_model, "string", "number")

    local model_hash = type(in_model) == "number" and in_model or joaat(in_model)

    if (not native.is_model_valid(model_hash)) then
        error(("model \"%s\" is not valid"):format(in_model))
    end

    return request_streaming(native.has_model_loaded, native.request_model, model_hash)
end

local function request_anim_set(in_animset)
    lib.validate.type.assert(in_animset, "string")

    return request_streaming(native.has_anim_set_loaded, native.request_anim_set, in_animset)
end

local function request_streamed_texture_dict(in_streamed_texture_dict)
    lib.validate.type.assert(in_streamed_texture_dict, "string")

    return request_streaming(native.has_streamed_texture_dict_loaded, native.request_streamed_texture_dict, in_streamed_texture_dict)
end

local function request_named_ptfx_asset(in_named_ptfx_asset)
    lib.validate.type.assert(in_named_ptfx_asset, "string")

    return request_streaming(native.has_named_ptfx_asset_loaded, native.request_named_ptfx_asset, in_named_ptfx_asset)
end

local function request_scaleform_movie(in_scaleform)
    lib.validate.type.assert(in_scaleform, "string")

    return request_streaming(native.has_scaleform_movie_loaded, native.request_scaleform_movie, in_scaleform)
end

local function request_weapon_asset(in_weapon)
    lib.validate.type.assert(in_weapon, "number")

    return request_streaming(native.has_weapon_asset_loaded, native.request_weapon_asset, in_weapon)
end

lib_module.anim_dict = warpper(request_anim_dict, native.remove_anim_dict, native.has_anim_dict_loaded, native.does_anim_dict_exist)
lib_module.model = warpper(request_model, native.set_model_as_no_longer_needed, native.has_model_loaded, native.is_model_valid)
lib_module.anim_set = warpper(request_anim_set, native.remove_anim_set, native.has_anim_set_loaded)
lib_module.streamed_texture_dict = warpper(request_streamed_texture_dict, native.set_streamed_texture_dict_as_no_longer_needed, native.has_streamed_texture_dict_loaded)
lib_module.named_ptfx_asset = warpper(request_named_ptfx_asset, native.remove_named_ptfx_asset, native.has_named_ptfx_asset_loaded)
lib_module.scaleform_movie = warpper(request_scaleform_movie, native.set_scaleform_movie_as_no_longer_needed, native.has_scaleform_movie_loaded)
lib_module.weapon_asset = warpper(request_weapon_asset, native.remove_weapon_asset, native.has_weapon_asset_loaded)
