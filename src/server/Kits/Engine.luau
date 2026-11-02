-- 33 Engine — Gear shifting and acceleration lanes
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local GREY = Color3.fromRGB(150, 150, 150)
local FLAME = Color3.fromRGB(255, 150, 60)

local function setGear(f, n)
	f.state.gear = math.clamp(n, 0, 3)
	if f.state.gear > 0 then
		K.buff(f, "Gears", { duration = 999, speed = 0.04 * f.state.gear, label = false })
	else
		K.Status.remove(f, "Gears")
	end
	K.res(f, "Gear", f.state.gear, 3, 1)
end
local function setTorque(f, v)
	f.state.torque = math.clamp(v, 0, 100)
	K.res(f, "Torque", math.floor(f.state.torque), 100, 2)
end
local function spendTorque(f, n)
	if (f.state.torque or 0) >= n then
		setTorque(f, f.state.torque - n)
		return true
	end
	return false
end

-- Passive: Three Gears
function Kit.passive.init(f)
	f.state.fwd = 0
	setGear(f, 0)
	setTorque(f, 0)
end
function Kit.passive.tick(f, dt)
	local hum = f.humanoid
	if not hum then
		return
	end
	local md = hum.MoveDirection
	if md.Magnitude > 0.1 then
		local last = f.state.lastDir
		if last and last:Dot(md.Unit) < 0 then
			setGear(f, f.state.gear - 1) -- turning over 90 degrees
			f.state.fwd = 0
		end
		f.state.lastDir = md.Unit
		f.state.fwd += dt
		if f.state.fwd >= 1.5 then
			f.state.fwd = 0
			setGear(f, f.state.gear + 1)
		end
	else
		if f.state.gear > 0 and (f.state.stopT or 0) > 0.3 then
			setGear(f, f.state.gear - 1)
			f.state.stopT = 0
		end
		f.state.stopT = (f.state.stopT or 0) + dt
		f.state.fwd = 0
	end
	if md.Magnitude > 0.1 then
		f.state.stopT = 0
	end
	if f.state.gear > 0 then
		setTorque(f, (f.state.torque or 0) + 5 * f.state.gear * dt)
	end
	-- external torque deposits (e.g. Energy relays)
	if f.state.torque and f.state.torque ~= f.state.lastTorqueShown then
		f.state.lastTorqueShown = f.state.torque
	end
end

local function flywheel(f)
	local fw = f.state.flywheel
	if fw and fw.expires > K.now() then
		f.state.flywheel = nil
		K.clearRes(f, "Flywheel")
		return fw.amount
	end
	return 0
end

-- 1 Piston Jab
Kit[1] = function(c)
	local f = c.f
	local bonus = flywheel(f)
	if not c.p60 then
		setGear(f, f.state.gear - 1)
	end
	local hits = K.melee(c, { range = 4, arc = 80, dmg = 75 + bonus, color = GREY })
	if c.mod and spendTorque(f, 15) then
		task.wait(0.25)
		K.melee(c, { range = 4, arc = 80, dmg = 30, color = FLAME })
	end
	local _ = hits
end

-- 2 Turbo Lane
Kit.requires = {
	[2] = function(c)
		if (c.f.state.torque or 0) >= 25 then
			return true
		end
		return false, "Need 25 Torque"
	end,
}
Kit[2] = function(c)
	local f = c.f
	spendTorque(f, 25)
	local bonus = flywheel(f)
	local dist = 12 + (K.partner(c, "Ice", 20) and 2 or 0)
	local dir = c:dir()
	if c.p60 then
		for _, o in ipairs(K.enemyObjects(c, f.root.Position + dir * K.m(3), 3)) do
			if o.hp <= 100 then
				S.Objects.destroy(o, f)
			end
		end
	end
	local struck = false
	local traveled = K.dash(c, dir, dist, 0.45, {
		passWidth = 1.8,
		onPass = function(t)
			if not struck then
				struck = true
				K.dmg(c, t, 115 + bonus, { melee = true })
			end
		end,
	})
	if traveled < dist - 1 then
		c.recovery = 0.7 -- wall collision
	end
end

-- 3 Emergency Brake
Kit[3] = function(c)
	local f = c.f
	local lv = f.root:FindFirstChild("EBDisplace")
	if lv then
		lv:Destroy()
	end
	f.root.AssemblyLinearVelocity = Vector3.zero
	local back = -c:dir()
	K.cone(c, { dir = back, range = 4, angle = 70, dmg = 60, color = FLAME, hit = function(t)
		K.push(c, t, back, 2)
	end })
	setGear(f, 0)
	f.heat = math.max(0, f.heat - 15)
	if c.p60 then
		K.zone(c, { pos = K.feet(f) + back * K.m(2), radius = 2, duration = 1, slow = { 0.2, 1 }, tick = 0.25, immediate = true, color = GREY })
	end
end

-- 4 Flywheel Bank
Kit[4] = function(c)
	local f = c.f
	local amount = math.min(50, f.state.torque or 0)
	if not c.p60 then
		setGear(f, f.state.gear - 1)
	end
	setTorque(f, f.state.torque - amount)
	f.state.flywheel = { amount = amount, expires = K.now() + 5 }
	K.res(f, "Flywheel", math.floor(amount), nil, 3)
	local rm
	rm = K.hook(f, "controlled", function(_, kind)
		if kind ~= "root" and f.state.flywheel then
			f.state.flywheel.amount /= 2
			K.res(f, "Flywheel", math.floor(f.state.flywheel.amount), nil, 3)
			rm()
		end
	end, 5)
	K.after(5, function()
		K.clearRes(f, "Flywheel")
	end)
end

-- 5 Redline Express (ultimate)
Kit[5] = function(c)
	local f = c.f
	local totals = {}
	local segments = c.unstable and 3 or 2
	local dir = c:dir()
	for seg = 1, segments do
		local hit = {}
		local traveled = K.dash(c, dir, 12, 0.4, {
			passWidth = 2,
			onPass = function(t)
				if not hit[t] then
					hit[t] = true
					local d = math.min(140, 250 - (totals[t] or 0))
					if d > 0 then
						totals[t] = (totals[t] or 0) + d
						K.dmg(c, t, d, { melee = true })
					end
				end
			end,
		})
		if traveled < 10 and c.unstable then
			-- Runaway Engine: collision causes 120 self-damage and Burnout
			K.Combat.damage(nil, f, 120, { kind = "true", tag = "collision" })
			f.rupturePending = true
			return
		end
		if seg < segments then
			local braking = not (c.unstable and seg == segments - 1)
			if braking then
				task.wait(0.5)
				local want = c:dir()
				local ang = math.deg(math.acos(math.clamp(dir:Dot(want), -1, 1)))
				if ang > 45 then
					local sign = dir:Cross(want).Y >= 0 and 1 or -1
					want = K.rotate(dir, -45 * sign)
				end
				dir = want
			end
		end
	end
end

return Kit
