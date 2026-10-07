local lib = require "src.imports._lib.shared"
local module_warp = require "src.imports._module_warp.shared"

local tag_container = lib.class.extends(lib.map.class)

function tag_container:constructor(tags)
    self:super()

    if (tags) then
        for i = 1, #tags do
            local tag = tags[i]
            self:add(tag)
        end
    end
end

function tag_container:add(tag)
    local count = self:get(tag) or 0
    self:set(tag, count + 1)
end

function tag_container:remove(tag)
    local count = self:get(tag) or 0
    if count > 1 then
        self:set(tag, count - 1)
    else
        self:delete(tag)
    end
end

-- WE ALREADY HAVE THIS METHOD INHERITED FROM MAP
-- function gameplay_tag_container:has(tag)
--     return self:has(tag)
-- end

function tag_container:has_all(tags)
    local tag_count = #tags

    if (tag_count > 0) then
        for i = 1, tag_count do
            local tag = tags[i]
            if not (self:has(tag)) then
                return false
            end
        end
    end

    return true
end

function tag_container:has_any(tags)
    local tag_count = #tags

    if (tag_count > 0) then
        for i = 1, tag_count do
            local tag = tags[i]
            if self:has(tag) then
                return true
            end
        end
    end

    return false
end

function tag_container:get_tags()
    local tags = {}
    for i = 1, self.size, 1 do
        local entry = self.data[i]
        tags[i] = entry.key
    end
    return tags
end

function tag_container:add_from(other, cb)
    for i = 1, other.size, 1 do
        local entry = other.data[i]
        self:add(entry.key)

        if (cb) then
            cb(entry.key)
        end
    end
end

function tag_container:remove_from(other, cb)
    for i = 1, other.size, 1 do
        local entry = other.data[i]
        self:remove(entry.key)

        if (cb) then
            cb(entry.key)
        end
    end
end

function tag_container:has_any_from(other)
    return self:has_any(other:get_tags())
end

function tag_container:has_all_from(other)
    return self:has_all(other:get_tags())
end

return module_warp.module_class_warp(tag_container)