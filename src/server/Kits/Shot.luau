-- 78 Shot — Projectile marksmanship and deliberate aim
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local BRASS = Color3.fromRGB(255, 210, 120)

-- Passive: Steady Sight
function Kit.passive.tick(f, dt)
	local hum = f.humanoid
	local steady = hum and hum.FloorMaterial ~= Enum.Material.Air and not f.root:FindFirstChild("EBDisplace")
	if steady then
		f.state.steadyT = (f.state.steadyT or 0) + dt
	else
		f.state.steadyT = 0
	end
	K.res(f, "Steady", (f.state.steadyT or 0) >= 0.7 and "yes" or "no", nil, 1)
end
local function spreadMult(f)
	return (f.state.steadyT or 0) >= 0.7 and 0.75 or 1
end
function Kit.passive.dealt(f, target, info)
	if info.kind ~= "direct" or not info.opts.cast then
		return
	end
	f.state.hits = f.state.hits or {}
	local last = f.state.hits[target]
	if last and K.now() - last <= 4 and K.los(f, target) then
		K.mark(f, target, "Marked", 2, { label = "Marked", color = BRASS })
		K.reveal(f, target, 2)
	end
	f.state.hits[target] = K.now()
end

-- 1 Pinpoint Round (hold 0.5 s for +15 damage)
Kit[1] = function(c)
	local f = c.f
	f.speedMult = 0.8
	local held = c:hold(0.5)
	f.speedMult = 1
	local full = held >= 0.45
	if full then
		K.FX.sphere(c:chest() + c:dir3() * 2, 0.5, Color3.fromRGB(255, 255, 255), 0.15, 0)
	end
	K.proj(c, {
		range = 28,
		speed = 42,
		width = 0.3,
		shape = "Block",
		size = Vector3.new(0.3, 0.3, 1.4),
		color = BRASS,
		kind = "physical",
		dmg = full and 95 or 80,
		guardDmg = (full and c.p60) and 20 or 0,
	})
end

-- 2 Bank Shot (ricochet preview; P60 second ricochet at 60)
Kit[2] = function(c)
	local origin = c:chest()
	local dir = c:dir3()
	local res = K.Hit.raycast(origin, dir * K.m(24))
	if res then
		local r = dir - 2 * dir:Dot(res.Normal) * res.Normal
		K.FX.beam(origin, res.Position, 0.06, BRASS, 0.5, 0.5)
		K.FX.beam(res.Position, res.Position + r * K.m(6), 0.06, BRASS, 0.5, 0.5)
	end
	local bounces = 0
	local dmg = 75
	K.proj(c, {
		range = 40,
		speed = 38,
		width = 0.3,
		color = BRASS,
		kind = "physical",
		data = { keepHits = false },
		hit = function(t)
			K.dmg(c, t, dmg, { projectile = true })
		end,
		wall = function(pos, normal, obj, p)
			local maxB = c.p60 and 2 or 1
			if obj or bounces >= maxB then
				return nil
			end
			local v = p.vel
			local r = v - 2 * v:Dot(normal) * normal
			-- an angle that would trap it in geometry dissipates the round
			if K.Hit.raycast(pos + normal * 0.5, r.Unit * 2) then
				return nil
			end
			bounces += 1
			if bounces == 2 then
				dmg = 60
			end
			p.vel = r
			return "bounce"
		end,
	})
end

-- 3 Covering Burst (recast stops early; P60 + modifier narrows the fan)
Kit[3] = function(c)
	local f = c.f
	local fan = ((c.p60 and c.mod) and 15 or 30) * spreadMult(f)
	local stop = false
	c:recast(0.8, function()
		stop = true
	end)
	local base = c:dir3()
	for i = 1, 5 do
		if stop or not c:valid() then
			break
		end
		local a = -fan / 2 + fan * (i - 1) / 4
		K.proj(c, { dir = K.rotate(base, a), range = 22, speed = 34, width = 0.3, color = BRASS, kind = "physical", dmg = 25 })
		task.wait(0.15)
	end
	c:closeRecast()
end

-- 4 Tactical Reload
Kit[4] = function(c)
	local f = c.f
	local hitDuring = false
	local rm = K.hook(f, "taken", function(_, info)
		if info.kind == "direct" then
			hitDuring = true
			c.endChannel = true
		end
	end, 1.1)
	local ok = c:channel(1, { stationary = not c.p60, halfSpeed = c.p60 })
	rm()
	if ok and not hitDuring then
		K.reduceCd(f, 1, 3)
		K.reduceCd(f, 2, 3)
		K.announce(f, "RELOADED", BRASS, 0.8)
	end
end

-- 5 One Clear Lane (ultimate)
Kit[5] = function(c)
	local f = c.f
	local laneDir = c:dir()
	local laneOrigin = c:feet()
	K.telegraphLine(c, laneOrigin, laneDir, 32, 4, 6, Color3.fromRGB(255, 230, 160))
	local rounds = 3
	local function fire(c2, dmg, pierceDmg, warn)
		K.FX.sphere(c2:chest() + laneDir * 2, 0.6, Color3.fromRGB(255, 255, 255), warn, 0)
		task.wait(warn)
		-- aim is constrained to the announced lane
		local want = c2:dir3()
		local flat = K.flat(want)
		local ang = math.deg(math.acos(math.clamp(flat:Dot(laneDir), -1, 1)))
		local dir = ang <= 6 and want or (laneDir + Vector3.new(0, want.Y, 0)).Unit
		local count = 0
		K.proj(c2, {
			dir = dir,
			range = 32,
			speed = 60,
			width = 0.5,
			color = BRASS,
			kind = "ultimate",
			pierce = pierceDmg and 1 or 0,
			hit = function(t)
				count += 1
				K.dmg(c2, t, count == 1 and dmg or pierceDmg)
			end,
		})
	end
	if c.unstable then
		c:recast(6, function(c2)
			-- Last Round: merged shot, no pierce
			fire(c2, math.min(330, 110 * rounds), nil, 1.2)
			rounds = 0
		end)
		return
	end
	c:recast(6, function(c2)
		rounds -= 1
		fire(c2, 110, 55, 0.5)
		if rounds > 0 then
			return "keep"
		end
		return nil
	end)
	local _ = f
end

return Kit
