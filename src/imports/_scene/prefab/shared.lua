local function traceback(err)
    return debug.traceback(tostring(err), 2)
end

local function array_length(value, label)
    assert(type(value) == "table" and getmetatable(value) == nil, label .. " must be a plain array")
    local count = 0
    for key in pairs(value) do
        assert(type(key) == "number" and key >= 1 and key % 1 == 0, label .. " must be a dense array")
        count = count + 1
    end
    for i = 1, count do assert(value[i] ~= nil, label .. " must be a dense array") end
    return count
end

local function copy_data(value, seen)
    if (type(value) ~= "table") then return value end
    assert(getmetatable(value) == nil, "prefab arguments must contain plain data tables")
    if (seen[value]) then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[copy_data(key, seen)] = copy_data(item, seen) end
    return result
end

local function compile(definition)
    local records, visiting, copied = {}, {}, {}
    local function visit(def, parent_index)
        assert(type(def) == "table" and getmetatable(def) == nil, "prefab node must be a plain table")
        assert(not visiting[def], "prefab children contain a cycle")
        assert(type(def.name) == "string" and def.name ~= "", "prefab node requires a non-empty name")
        visiting[def] = true

        local index = #records + 1
        local record = { name = def.name, parent_index = parent_index, components = {} }
        records[index] = record
        local components = def.components or {}
        local names = {}
        for i = 1, array_length(components, "prefab components") do
            local spec = components[i]
            assert(type(spec) == "table", "prefab component must be a table")
            assert(type(spec.name) == "string" and spec.name ~= "", "prefab component requires a name")
            assert(not names[spec.name], "duplicate prefab component name: " .. spec.name)
            names[spec.name] = true
            assert(type(spec.class) == "table" and type(spec.class.new) == "function"
                and type(spec.class.destroy) == "function", "prefab component requires a class with destroy()")
            local args = copy_data(spec.args or {}, copied)
            local count = args.n
            if (count == nil) then
                count = array_length(args, "prefab args")
            else
                assert(type(count) == "number" and count >= 0 and count < math.huge and count % 1 == 0,
                    "prefab args.n must be a non-negative integer")
                for key in pairs(args) do
                    assert(key == "n" or (type(key) == "number" and key >= 1 and key <= count and key % 1 == 0),
                        "prefab args must be an array or table.pack result")
                end
            end
            record.components[i] = { name = spec.name, class = spec.class, args = args, count = count }
        end
        local children = def.children or {}
        for i = 1, array_length(children, "prefab children") do visit(children[i], index) end
        visiting[def] = nil
    end
    visit(definition)
    return records
end

local function instantiate(scene, definition, parent)
    assert(not scene.destroyed, "scene is destroyed")
    if (parent ~= nil) then scene:_assert_live_node(parent) end
    local records = compile(definition)
    local created = {}
    local ok, err = xpcall(function()
        -- Make the full hierarchy available before running component constructors.
        for i, record in ipairs(records) do
            local owner = record.parent_index and created[record.parent_index] or parent
            created[i] = scene:create_node(record.name, owner)
        end
        for i, record in ipairs(records) do
            for _, spec in ipairs(record.components) do
                created[i]:add_component(spec.name, spec.class, table.unpack(spec.args, 1, spec.count))
            end
        end
        for _, current in ipairs(created) do scene:_assert_live_node(current) end
    end, traceback)

    if (not ok) then
        local errors = { err }
        -- Track every created node, including ones moved by constructors.
        for _, current in ipairs(created) do
            current._closing = true
            for _, descendant in ipairs(current:find_descendants()) do descendant._closing = true end
        end
        for i = #created, 1, -1 do
            local cleaned, cleanup_err = xpcall(created[i].destroy, traceback, created[i])
            if (not cleaned) then errors[#errors + 1] = cleanup_err end
        end
        error(table.concat(errors, "\n"), 0)
    end
    return created[1]
end

return instantiate
