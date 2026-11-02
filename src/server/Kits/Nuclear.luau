-- 65 Nuclear — Fictional reactor management and delayed zones (no lasting contamination)
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local GLOW = Color3.fromRGB(120, 255, 0)

local function openRings(f)
	local now = K.now()
	local n = 0
	for i = #f.state.rings, 1, -1 do
		if f.state.rings[i] > now then
			n += 1
		else
			table.remove(f.state.rings, i)
		end
	end
	return n
end

-- Passive: Containment Rings
function Kit.passive.init(f)
	f.state.rings = {}
end
function Kit.passive.tick(f)
	local n = openRings(f)
	K.res(f, "Rings open", n, 3, 1)
	f.model:SetAttribute("ReactorRings", n)
end
function Kit.passive.cast(f, c)
	if openRings(f) >= 3 then
		c.data.overload = true
		f.state.rings = {}
		K.addHeat(f, 8)
		K.announce(f, "OVERLOAD", GLOW, 1)
	end
end
function Kit.passive.beforeDeal(f, target, info)
	local c = info.opts.cast
	if c and c.data.overload and info.kind ~= "dot" then
		info.amount += 20
	end
end
function Kit.passive.dealt(f, target, info)
	local c = info.opts.cast
	if c and not c.data.overload and not c.data.ringOpened then
		c.data.ringOpened = true
		if #f.state.rings < 3 then
			table.insert(f.state.rings, K.now() + 6)
		end
	end
end

-- 1 Fission Spark
Kit[1] = function(c)
	local f = c.f
	local struck = {}
	K.proj(c, {
		range = 24,
		speed = 14,
		width = 0.8,
		color = Color3.fromRGB(220, 255, 200),
		hit = function(t)
			struck[t] = true
			K.dmg(c, t, 90, { projectile = true })
		end,
		finish = function(pos, reason)
			if reason ~= "wall" then
				return
			end
			local base = c.p60 and c:dir() or -c:dir()
			for _, a in ipairs({ -45, 45 }) do
				K.proj(c, {
					origin = pos + Vector3.new(0, 0.5, 0),
					dir = K.rotate(base, a),
					range = 8,
					speed = 20,
					width = 0.4,
					color = GLOW,
					filter = function(t)
						return K.isEnemy(f, t) and not struck[t]
					end,
					hit = function(t)
						struck[t] = true
						K.dmg(c, t, 25)
					end,
				})
			end
		end,
	})
end

-- 2 Containment Vessel
Kit[2] = function(c)
	local f = c.f
	local pos = c:aimPoint(14)
	local vessel = K.object(c, { name = "ContainmentVessel", pos = pos, size = Vector3.new(1.2, 2, 1.2), shape = "Cylinder", hp = 180, duration = 8, color = GLOW, material = Enum.Material.Glass })
	vessel.part.CFrame = CFrame.new(pos + Vector3.new(0, K.m(1), 0)) * CFrame.Angles(0, 0, math.rad(90))
	vessel.part.Size = Vector3.new(K.m(2), K.m(1.2), K.m(1.2))
	local absorbed = 0
	local cracked = false
	K.FX.ring(pos, K.m(3), GLOW, 8, 0.2)
	K.every(0.03, 8, function()
		if not vessel.alive or cracked then
			return false
		end
		for _, p in ipairs(K.enemyProj(c, pos + Vector3.new(0, 2, 0), 3)) do
			local d = p.dmg or 50
			absorbed += d
			S.Proj.stop(p, "contained")
			if absorbed >= 120 then
				cracked = true
				vessel.part.Color = Color3.fromRGB(90, 110, 80)
				K.FX.burst(pos, K.m(3), Color3.fromRGB(255, 255, 255), 0.2) -- harmless warning flash
				return false
			end
		end
		return true
	end)
	if c.p60 then
		c:recast(8, function()
			if vessel.alive and vessel.hp >= vessel.maxHp and absorbed == 0 then
				S.Objects.remove(vessel, "reclaimed")
				K.addEnergy(f, 10)
			end
		end)
	end
end

-- 3 Fallout Mark
Kit[3] = function(c)
	local pos = c:aimPoint(18)
	K.telegraph(c, pos, 4, 1, GLOW)
	local drifted = false
	task.wait(1)
	local z = K.zone(c, { pos = pos, radius = 4, duration = 5, dmg = 20, color = GLOW, transparency = 0.6 })
	if c.p60 then
		c:recast(5, function(c2)
			if z.alive and not drifted then
				drifted = true
				z:move(z.pos + K.flat(c2:aimPoint(30) - z.pos) * K.m(2))
			end
		end)
	end
end

-- 4 Controlled Vent
Kit[4] = function(c)
	local f = c.f
	local hit = { {}, {}, {} }
	local gap = c.p60 and 40 or 25
	local cooled = 0
	c:channel(1.2, {
		tick = 0.1,
		onTick = function(elapsed)
			if cooled < 30 then
				local d = math.min(2.5, 30 - cooled)
				cooled += d
				f.heat = math.max(0, f.heat - d)
			end
			for j = 1, 3 do
				local ang = elapsed * 200 + j * 120
				local dir = Vector3.new(math.cos(math.rad(ang)), 0, math.sin(math.rad(ang)))
				K.FX.beam(f.root.Position, f.root.Position + dir * K.m(5), 0.3, Color3.fromRGB(230, 255, 230), 0.1, 0.4)
				for _, t in ipairs(K.enemiesCone(c, 5, 60 - gap, f.root.Position, dir, false)) do
					if not hit[j][t] then
						hit[j][t] = true
						K.dmg(c, t, 25)
					end
				end
			end
		end,
	})
end

-- 5 Sun in a Cage (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	local reactor = K.object(c, { name = "CagedSun", pos = center, size = 2, shape = "Ball", hp = 300, duration = 5, isUlt = true, color = GLOW, material = Enum.Material.Neon })
	K.FX.ring(center, K.m(7), GLOW, 4.5, 0.4)
	K.telegraph(c, center, 7, 2, GLOW)
	task.wait(2)
	if not reactor.alive then
		return
	end
	K.circle(c, center, 7, { dmg = 180, color = GLOW })
	if c.unstable then
		K.telegraph(c, center, 7, 1, Color3.fromRGB(255, 255, 255))
		task.wait(1)
		if not reactor.alive then
			return
		end
		-- Containment Failure: the inward collapse can damage the caster and does not pull
		for _, t in ipairs(K.Hit.cylinder(center, K.m(7), function()
			return true
		end)) do
			K.Combat.damage(f, t, 200, { cast = c, isUlt = true, fromPos = center, element = "Nuclear" })
		end
		K.FX.burst(center, K.m(7), Color3.fromRGB(255, 255, 255), 0.4)
	else
		task.wait(1.2)
		if not reactor.alive then
			return
		end
		K.circle(c, center, 7, { dmg = 120, color = GLOW })
	end
	if reactor.alive then
		S.Objects.remove(reactor, "spent")
	end
end

return Kit
