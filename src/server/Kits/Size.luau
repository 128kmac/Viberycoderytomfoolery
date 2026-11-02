-- 80 Size — Changing body dimensions with real tradeoffs (health never changes with scale)
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local PEACH = Color3.fromRGB(255, 160, 120)
local SIZES = {
	Small = { scale = 0.7, speed = 1.1, reach = 0.8 },
	Standard = { scale = 1, speed = 1, reach = 1 },
	Large = { scale = 1.4, speed = 0.9, reach = 1.2 },
	Colossal = { scale = 1.8, speed = 0.8, reach = 1.2 },
}
local CYCLE = { "Standard", "Large", "Small" }

local function setSize(f, name, force)
	local spec = SIZES[name]
	if not force and spec.scale > (SIZES[f.state.size or "Standard"].scale) then
		-- fails without cost if there is insufficient space
		if not K.Hit.spaceFree(f.root.Position + Vector3.new(0, (spec.scale - 1) * 2, 0), spec.scale) then
			return false
		end
	end
	f.state.size = name
	f.state.sizeChangedAt = K.now()
	f.hitScale = spec.scale
	f.speedMult = spec.speed
	pcall(function()
		f.model:ScaleTo(spec.scale)
	end)
	K.res(f, "Size", name, nil, 1)
	return true
end

-- Passive: Mass Budget
function Kit.passive.init(f)
	f.state.size = "Standard"
	K.res(f, "Size", "Standard", nil, 1)
end
function Kit.passive.cleanup(f)
	f.hitScale = 1
	f.speedMult = 1
	pcall(function()
		f.model:ScaleTo(1)
	end)
end
function Kit.basic(f)
	local spec = SIZES[f.state.size or "Standard"]
	if f.state.size == "Colossal" then
		f.basicInterval = 0.9
		S.Fighter.defaultBasic(f, 90, 5)
		return
	end
	f.basicInterval = nil
	S.Fighter.defaultBasic(f, 60, 2.5 * spec.reach)
end

-- 1 Scale Shift
Kit[1] = function(c)
	local f = c.f
	local i = table.find(CYCLE, f.state.size) or 1
	local nextSize = CYCLE[(c.mod and (i - 2) or i) % 3 + 1]
	if setSize(f, nextSize) then
		if c.p60 then
			K.shield(c, f, 35, 2, "ScaleShift")
		end
	else
		K.notify(f, "Not enough space")
	end
end

-- 2 Measured Blow
Kit[2] = function(c)
	local f = c.f
	local size = f.state.size
	local dmg = size == "Small" and 65 or (size == "Standard" and 80 or 105)
	if c.p60 and f.state.sizeChangedAt and K.now() - f.state.sizeChangedAt <= 2 then
		dmg += 15
	end
	K.melee(c, { range = 4 * (SIZES[size] and SIZES[size].reach or 1), arc = 90, dmg = dmg, color = PEACH })
	if size == "Small" then
		c.recovery = 0.2
	elseif size == "Large" or size == "Colossal" then
		c.recovery = 0.55
	end
end

-- 3 Pocket Passage
Kit[3] = function(c)
	local f = c.f
	local previous = f.state.size
	setSize(f, "Small", true)
	K.dash(c, c:dir(), c.p60 and 6 or 5, 0.25)
	if previous ~= "Small" then
		K.every(0.2, 6, function()
			if setSize(f, previous) then
				return false
			end
			return true
		end)
	end
end

-- 4 Giant's Reach
Kit[4] = function(c)
	local radius = c.p60 and 2.5 or 2
	local pos = c:aimPoint(8)
	K.telegraph(c, pos, radius, 0.3, PEACH)
	K.FX.beam(c:chest(), pos + Vector3.new(0, K.m(1.5), 0), K.m(0.8), PEACH, 0.4, 0.2)
	task.wait(0.3)
	K.circle(c, pos, radius, { dmg = 100, color = PEACH })
end

-- 5 Colossal Interval (ultimate)
Kit[5] = function(c)
	local f = c.f
	local previous = f.state.size
	setSize(f, "Colossal", true)
	K.shield(c, f, 180, 7, "Colossal")
	c:form(7, {
		onEnd = function()
			if c.unstable and K.alive(f) then
				K.Combat.removeShield(f, "Colossal")
				K.telegraph(c, c:feet(), 6, 1, PEACH)
				task.wait(1)
				K.circle(c, c:feet(), 6, { dmg = 150, color = PEACH })
			end
			f.basicInterval = nil
			-- Return to Scale at the nearest legal standing space
			if not setSize(f, previous or "Standard") then
				setSize(f, "Standard", true)
			end
		end,
	})
end

return Kit
