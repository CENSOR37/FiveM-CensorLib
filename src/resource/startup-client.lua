require "src.resource.startup-shared"
require "src.resource.cache.client"

local function SHOULD_USE_NATIVE_COLSHAPE()
    local functions = {
        "CreateColshapeCircle",
        "CreateColshapeCuboid",
        "CreateColshapeCylinder",
        "CreateColshapePolygon",
        "CreateColshapeRectangle",
        "CreateColshapeSphere",
        "DeleteColshape",
        "DoesColshapeExist",
        "GetColshapeCircleData",
        "GetColshapeCuboidData",
        "GetColshapeCylinderData",
        "GetColshapePolygonData",
        "GetColshapeRectangleData",
        "GetColshapeSphereData",
        "IsColshapeCircle",
        "IsColshapeCuboid",
        "IsColshapeCylinder",
        "IsColshapeEntityTypeSet",
        "IsColshapePolygon",
        "IsColshapeRectangle",
        "IsColshapeSphere",
        "IsPointInsideColshape",
        "SetColshapeEntityType",
    }

    for _, func in ipairs(functions) do
        if not _G[func] then
            return false
        end
    end

    return true
end

if (SHOULD_USE_NATIVE_COLSHAPE()) then
    require "src.resource.zone-native.client"
else
    require "src.resource.zone.client"
end
