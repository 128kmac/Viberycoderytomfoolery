-- 25 Dragon — Heavy aerial pressure and breath management
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local RED = Color3.fromRGB(220, 60, 30)
local FIRE = Color3.fromRGB(255, 140, 40)

local function setBreath(f, v)
	f.state.breath = math.clamp(v, 0, 100)
	K.res(f, "Breath", math.floor(f.state.breath), 100, 1)
	if f.state.breath <= 0 and f.state.hover then
		f.state.hover.stop() -- wings fold
		f.state.hover = nil
	end
end
local function spendBreath(f, n)
	if (f.state.breath or 0) < n then
		return false
	end
	setBreath(f, f.state.breath - n)
	return true
end

-- Passive: Breath Reservoir
function Kit.passive.init(f)
	setBreath(f, 100)
end
function Kit.passive.tick(f, dt)
	local hum = f.humanoid
	if hum and hum.FloorMaterial ~= Enum.Material.Air and hum.MoveDirection.Magnitude > 0.1 and f.state.breath < 100 then
		setBreath(f, f.state.breath + 12 * dt)
	end
end

local function breathHit(c, t)
	-- lodged scales burst when breath touches them
	if K.has(t, "LodgedScale") then
		K.unmark(t, "LodgedScale")
		K.circle(c, K.feet(t), 2, { dmg = 35, color = FIRE })
	end
end
local function breathObjects(c, pos, rM)
	for _, o in ipairs(K.objects(c, pos, rM)) do
		if o.data.lodgedScale and o.data.lodgedScale > K.now() then
			o.data.lodgedScale = nil
			K.circle(c, K.ground(o.part.Position), 2, { dmg = 35, color = FIRE })
		end
	end
end

Kit.requires = {
	[2] = function(c)
		if c.f.state.noFlight and c.f.state.noFlight > K.now() then
			return false, "Flight removed"
		end
		if (c.f.state.breath or 0) >= 20 then
			return true
		end
		return false, "Need 20 Breath"
	end,
	[3] = function(c)
		if (c.f.state.breath or 0) >= 40 then
			return true
		end
		return false, "Need 40 Breath"
	end,
}

-- 1 Scale Lance
Kit[1] = function(c)
	local pierced = false
	K.proj(c, {
		range = 22,
		width = 0.4,
		shape = "Block",
		size = Vector3.new(0.6, 0.2, 1.4),
		color = RED,
		kind = "physical",
		hit = function(t)
			local hadShield = K.totalShield(t) > 0
			K.dmg(c, t, 80, { projectile = true })
			if hadShield then
				K.mark(c, t, "LodgedScale", 4, { label = "Lodged Scale", color = RED })
			end
		end,
		wall = function(_, _, obj)
			if obj then
				if c.p60 and not pierced and obj.hp <= 50 then
					pierced = true
					S.Objects.destroy(obj, c.f)
					return "pass"
				end
				obj.data.lodgedScale = K.now() + 4
			end
			return nil
		end,
	})
end

-- 2 Wingbeat Ascent
Kit[2] = function(c)
	local f = c.f
	spendBreath(f, 20)
	K.circle(c, c:feet(), 3, { dmg = 60, color = RED })
	local dur = 3 + (K.partner(c, "Wind", 15) and 1 or 0)
	f.state.hover = K.hover(f, 5, dur, 0.5)
	f.noDodge = true -- hovering grants no dodge invulnerability
	K.after(dur, function()
		f.noDodge = nil
	end)
	if c.p60 then
		c:recast(dur, function(c2)
			K.dash(c2, c2:dir(), 3, 0.15)
		end)
	end
end

-- 3 Furnace Breath
Kit[3] = function(c)
	local f = c.f
	spendBreath(f, 40)
	local dir = c:dir()
	local angle = c.p60 and 75 or 60
	local ticks = 0
	c:channel(1.5, {
		halfSpeed = true,
		stationary = false,
		tick = 0.3,
		onTick = function()
			-- turning is capped at 35 degrees per second
			local want = c:dir()
			local cur = math.deg(math.atan2(dir.Z, dir.X))
			local tgt = math.deg(math.atan2(want.Z, want.X))
			local delta = ((tgt - cur + 540) % 360) - 180
			delta = math.clamp(delta, -35 * 0.3, 35 * 0.3)
			local a = math.rad(cur + delta)
			dir = Vector3.new(math.cos(a), 0, math.sin(a))
			c:face(dir)
			ticks += 1
			K.cone(c, { range = 12, angle = angle, dmg = 25, dir = dir, color = FIRE, hit = function(t)
				breathHit(c, t)
			end })
			breathObjects(c, f.root.Position + dir * K.m(6), 6)
		end,
	})
end

-- 4 Tail Tribunal
Kit[4] = function(c)
	local f = c.f
	local fwd = K.flat(f.root.CFrame.LookVector)
	K.FX.ring(c:feet(), K.m(6), RED, 0.35, K.m(1))
	for _, t in ipairs(K.enemiesIn(c, f.root.Position, 6)) do
		local to = K.flat(t.root.Position - f.root.Position)
		if to:Dot(fwd) < math.cos(math.rad(30)) then
			K.dmg(c, t, 115, { melee = true })
			K.knock(c, t, f.root.Position, 3)
			if c.p60 then
				K.after(0.25, function()
					for _, o in ipairs(K.enemyObjects(c, t.root.Position, 1.5)) do
						K.objDmg(c, o, 40)
					end
				end)
			end
		end
	end
end

-- 5 Elder Descent (ultimate)
Kit[5] = function(c)
	local f = c.f
	local target = c:aimPoint(24)
	local start = f.root.Position
	local apex = start:Lerp(K.Hit.standAt(target), 0.4) + Vector3.new(0, K.m(8), 0)
	K.telegraph(c, target, 5, 1.4, RED)
	K.path(c, function(a)
		return start:Lerp(apex, a)
	end, 0.6)
	task.wait(0.4) -- landing point locked
	local stand = K.Hit.standAt(target)
	K.path(c, function(a)
		return apex:Lerp(stand, a * a)
	end, 0.4)
	K.circle(c, target, 5, { dmg = 220, color = RED })
	breathObjects(c, target, 5)
	local taken = {}
	for i = 0, 2 do
		local d = K.rotate(c:dir(), i * 120)
		K.line(c, target, d, 9, 1.5, {
			color = FIRE,
			fx = true,
			hit = function(t)
				if (taken[t] or 0) < 2 then
					taken[t] = (taken[t] or 0) + 1
					K.dmg(c, t, 40)
					breathHit(c, t)
				end
			end,
		})
	end
	if K.partner(c, "Lava", 20) then
		K.zone(c, { shape = "rect", pos = target, dir = c:dir(), width = 1.5, length = 9, duration = 3, dmg = 20, color = FIRE })
	end
	if c.unstable then
		task.wait(0.4)
		K.cone(c, { range = 8, angle = 120, dmg = 120, color = FIRE })
		setBreath(f, 0)
		f.state.noFlight = K.now() + 8
	end
end

return Kit
