local select = select

local function coalesce(...)
    for i = 1, select("#", ...), 1 do
        local value = select(i, ...)

        if (value ~= nil) then
            return value
        end
    end

    return nil
end

return { coalesce = coalesce }
