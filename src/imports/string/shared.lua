---@class csstring : stringlib
local string = string
local string_gsub = string.gsub

function string.substitute(str, vars)
    return string_gsub(str, "%${([%w_]+)}", function(key)
        local val = vars[key]
        if (val ~= nil) then
            return tostring(val)
        end
    end)
end

return string
