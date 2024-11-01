local default_lang = "en"
local dictionary = {}

local string_gsub = string.gsub
local locale

local native = {
    load_resource_file = LoadResourceFile,
}

local function load_dict(lang)
    lib.validate.type.assert(lang, "string")

    local locales = json.decode(native.load_resource_file(lib.resource.name, ("locales/%s.json"):format(lang)))
    local dict = {}

    if (locales) then
        for locale_id, locale in pairs(locales) do
            if (type(locale_id) == "string" and type(locale) == "string") then
                dict[locale_id] = locale
            else
                print(("invalid locale string for %s: %s"):format(lang, locale_id))
            end
        end
    else
        print(("'locales/%s.json' was not exist"):format(lang))
    end

    dictionary[lang] = dict
end

locale = function(string, vars, lang)
    lang = lib.coalesce(lang, default_lang)

    local lang_dict = dictionary[lang]
    if not (lang_dict) then
        load_dict(lang)
        return locale(string, vars, lang)
    end

    local locale_string = lang_dict[string]
    if not (locale_string) then
        return ("\"%s\" was not found in the \"%s\" dictionary"):format(string, lang)
    end

    if (vars) then
        locale_string = string_gsub(locale_string, "%${([%w_]+)}", vars)
    end

    return locale_string
end

local function set_language(lang)
    lib.validate.type.assert(lang, "string")

    default_lang = lang
end

lib_module = setmetatable({
    set_language = set_language,
    set_lang = set_language,
    loc = locale,
}, {
    __call = function(_, ...)
        return locale(...)
    end,
})
