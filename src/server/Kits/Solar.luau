-- 84 Solar — Exposure and a moving point of daylight
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local SUN = Color3.fromRGB(255, 180, 0)

local function setExposure(f, n)
	f.state.exposure = math.clamp(n, 0, 4)
	K.res(f, "Exposure", f.state.exposure, 4, 1)
end
local function spend(f, n)
	local take = math.min(n, f.state.exposure or 0)
	setExposure(f, f.state.exposure - take)
	return take
end
local function sunspot(f)
	local s = f.state.sunspot
	if s and s.obj.alive then
		return s
	end
	return nil
end

-- Passive: Solar Exposure — each second inside your Sunspot's 5 m zone grants Exposure (lasts 6 s after leaving)
function Kit.passive.init(f)
	setExposure(f, 0)
	f.state.lit = 0
	f.state.leftAt = 0
end
function Kit.passive.tick(f, dt, now)
	local s = sunspot(f)
	if s and K.flatDist(f, s.ground) <= 5 then
		f.state.leftAt = now
		f.state.lit += dt
		if f.state.lit >= 1 then
			f.state.lit = 0
			setExposure(f, f.state.exposure + 1)
		end
	else
		f.state.lit = 0
		if f.state.exposure > 0 and now - f.state.leftAt > 6 then
			setExposure(f, 0)
		end
	end
end

-- 1 Sunlance
Kit[1] = function(c)
	local f = c.f
	local empowered = spend(f, 1) > 0
	local pierced = false
	K.proj(c, {
		range = 24,
		speed = 30,
		width = empowered and 0.6 or 0.45,
		shape = "Block",
		size = Vector3.new(0.5, 0.5, 2.4),
		color = empowered and Color3.fromRGB(255, 240, 160) or SUN,
		dmg = empowered and 100 or 80,
		wall = function(_, _, obj)
			if c.p60 and empowered and obj and obj.hp < 50 and not pierced then
				pierced = true
				S.Objects.destroy(obj, f)
				return "pass"
			end
			return nil
		end,
	})
end

-- 2 Sunspot
Kit[2] = function(c)
	local f = c.f
	local old = sunspot(f)
	if old then
		S.Objects.remove(old.obj, "replaced")
	end
	local ground = c:aimPoint(14)
	local obj = K.object(c, { name = "Sunspot", cf = CFrame.new(ground + Vector3.new(0, K.m(3), 0)), size = 1.2, shape = "Ball", hp = 120, duration = 8, solid = false, color = SUN, material = Enum.Material.Neon })
	local disc = K.FX.disc(ground, K.m(5), Color3.fromRGB(255, 230, 150), 8, 0.8)
	f.state.sunspot = { obj = obj, ground = ground, disc = disc }
	obj.cleanup = function()
		if disc.Parent then
			disc:Destroy()
		end
	end
	if c.p60 then
		c:recast(8, function(c2)
			local s = sunspot(f)
			if s then
				local np = K.ground(s.ground + K.flat(c2:aimPoint(30) - s.ground) * K.m(3))
				s.ground = np
				s.obj.part.CFrame = CFrame.new(np + Vector3.new(0, K.m(3), 0))
				s.disc.CFrame = CFrame.new(np + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
			end
		end)
	end
end

-- 3 Helios Guard
Kit[3] = function(c)
	local f = c.f
	local extra = spend(f, 2)
	K.shield(c, f, 90 + 30 * extra, 4, "Helios")
	K.after(3.95, function()
		local survived = false
		for _, sh in ipairs(f.shields) do
			if sh.name == "Helios" then
				survived = true
			end
		end
		-- harmless flare marks your location
		K.FX.burst(f.root.Position, K.m(3), Color3.fromRGB(255, 240, 180), 0.4)
		K.reveal(f, f, 1)
		if c.p60 and survived then
			setExposure(f, f.state.exposure + 1)
		end
	end)
end

-- 4 Noon Arc
Kit[4] = function(c)
	local f = c.f
	local afterglow = (f.state.exposure or 0) >= 2
	if afterglow then
		spend(f, 2)
	end
	local base = c:dir3()
	local sign = (c.p60 and c.mod) and -1 or 1
	local hit = {}
	local lastEnd
	c:channel(0.8, {
		stationary = false,
		halfSpeed = true,
		tick = 0.1,
		onTick = function(elapsed)
			local a = (-30 + 60 * math.min(1, elapsed / 0.8)) * sign
			local dir = K.rotate(base, a)
			lastEnd = K.beam(c, {
				dir = dir,
				length = 12,
				width = 0.4,
				color = SUN,
				dur = 0.12,
				pierce = true,
				filter = function(t)
					return K.isEnemy(f, t) and not hit[t]
				end,
				hit = function(t)
					hit[t] = true
					K.dmg(c, t, 100, { beam = true })
				end,
			})
		end,
	})
	if afterglow and lastEnd then
		local at = K.ground(lastEnd)
		K.delayed(c, at, 2, 0.6, function(p)
			K.circle(c, p, 2, { dmg = 30, color = SUN })
		end, SUN)
	end
end

-- 5 High Sun Ascendant (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(18)
	local sun = K.object(c, { name = "HighSun", cf = CFrame.new(center + Vector3.new(0, K.m(4), 0)), size = 2.4, shape = "Ball", hp = 300, duration = 7.5, isUlt = true, color = SUN, material = Enum.Material.Neon })
	local totals = {}
	local revolutions = c.unstable and 2 or 3
	for rev = 1, revolutions do
		local hitThisRev = {}
		local t0 = K.now()
		while K.now() - t0 < 2 and sun.alive do
			local rot = (K.now() - t0) / 2 * 360
			for i = 0, 2 do
				local d = K.rotate(Vector3.new(1, 0, 0), rot + i * 120)
				local from = center + Vector3.new(0, K.m(1), 0)
				K.FX.beam(from, from + d * K.m(8), 0.6, SUN, 0.1, 0.25)
				for _, h in ipairs(K.Hit.segment(from, from + d * K.m(8), K.m(0.6), K.enemyFilter(c))) do
					local t = h.f
					if not hitThisRev[t] and (totals[t] or 0) < 3 then
						hitThisRev[t] = true
						totals[t] = (totals[t] or 0) + 1
						K.dmg(c, t, 65, { fromPos = from })
					end
				end
			end
			task.wait(0.08)
		end
		local _ = rev
	end
	if c.unstable and sun.alive then
		-- After Noon: the final revolution concentrates into a single aimed 180-damage ray
		local d = K.flat(c:aimPoint(30) - center)
		local from = center + Vector3.new(0, K.m(1), 0)
		K.telegraphLine(c, center, d, 10, 1.5, 1, SUN)
		task.wait(1)
		K.beam(c, { origin = from, dir = d, length = 10, width = 1.5, dmg = 180, color = Color3.fromRGB(255, 255, 220), pierce = true, throughWalls = false })
		S.Objects.remove(sun, "spent")
	end
end

return Kit
