local data = require "data.collect"
local curves = data.curves
local collect_effect = cslib.class()
local active = {}
local tick_timer

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function start_tick()
    if (tick_timer) then return end

    -- One timer for the entire burst, including effects that are still loading.
    tick_timer = cslib.on_tick(function()
        local now = GetGameTimer()
        for effect in pairs(active) do
            if (effect.time_start) then effect:on_tick(now) end
        end

        if (not next(active)) then
            tick_timer:destroy()
            tick_timer = nil
        end
    end)
end

function collect_effect:constructor(model, start_pos, parent, duration, start_heading)
    duration = duration or data.duration
    assert(type(duration) == "number" and duration > 0 and duration < math.huge, "duration must be a positive finite number")
    assert(DoesEntityExist(parent), "collect effect requires an existing parent entity")

    self.parent = parent
    self.duration = duration
    self.start_heading = start_heading or 0
    self.destroyed = false
    self.entity = cslib.entity.object.new(model or data.model, start_pos, vec3(0, 0, 0))
    active[self] = true

    self.entity:on_created(function()
        if (self.destroyed) then return end
        local handle = self.entity.handle
        if (not DoesEntityExist(handle) or not DoesEntityExist(self.parent)) then
            self:destroy()
            return
        end

        PlaceObjectOnGroundProperly(handle)
        SetCanAutoVaultOnEntity(handle, false)
        SetCanClimbOnEntity(handle, false)
        FreezeEntityPosition(handle, true)
        SetEntityCollision(handle, false, false)

        self.start_pos = GetEntityCoords(handle)
        local target = GetPedBoneCoords(self.parent, 24818, 0.0, 0.0, 0.0)
        local dx, dy = target.x - self.start_pos.x, target.y - self.start_pos.y
        local length = math.sqrt(dx * dx + dy * dy)
        self.side = length > 0.001 and vec3(-dy / length, dx / length, 0) or vec3(1, 0, 0)
        -- Loading time must not consume the animation's duration.
        self.time_start = GetGameTimer()
        self:on_tick(self.time_start)
        start_tick()
    end)
end

function collect_effect:on_tick(now)
    if (self.destroyed) then return end
    local handle = self.entity.handle
    if (not DoesEntityExist(handle) or not DoesEntityExist(self.parent)) then
        self:destroy()
        return
    end

    local progress = clamp((now - self.time_start) / self.duration, 0, 1)
    if (progress >= 1) then
        self:destroy()
        return
    end

    local target = GetPedBoneCoords(self.parent, 24818, 0.0, 0.0, 0.0)
    local pull = clamp(curves.pull:evaluate(progress), 0, 1)
    local position = self.start_pos + (target - self.start_pos) * pull
        + self.side * curves.sway:evaluate(progress)
        + vec3(0, 0, curves.lift:evaluate(progress))
    local scale = clamp(curves.scale:evaluate(progress), 0.01, 1.4)
    local heading = math.rad(self.start_heading + curves.spin:evaluate(progress))
    local sine, cosine = math.sin(heading), math.cos(heading)

    -- Build fresh unit axes: scale is absolute, never multiplied into last frame's scale.
    SetEntityMatrix(handle,
        -sine * scale, cosine * scale, 0.0,
        cosine * scale, sine * scale, 0.0,
        0.0, 0.0, scale,
        position.x, position.y, position.z)

    DrawLightWithRange(position.x, position.y, position.z, 255, 190, 65,
        1.5, math.max(0, curves.glow:evaluate(progress)))
end

function collect_effect:destroy()
    if (self.destroyed) then return end
    self.destroyed = true
    active[self] = nil
    if (self.entity) then self.entity:destroy() end
end

cslib.resource.on_stop(function()
    for effect in pairs(active) do effect:destroy() end
    if (tick_timer) then
        tick_timer:destroy()
        tick_timer = nil
    end
end)

-- Same argument order as gc_collect_effect.new in the supplied reference.
return {
    new = function(model, start_pos, parent, duration, start_heading)
        return collect_effect:new(model, start_pos, parent, duration, start_heading)
    end,
}
