-- 89 Storm — Moving weather fronts and charged transitions
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local STORM = Color3.fromRGB(90, 100, 160)
local BOLT = Color3.fromRGB(230, 240, 255)

local function forecast(f, t)
	K.mark(f, t, "Forecast", 3, { label = "Forecast", color = BOLT })
end

-- Passive: Weather Front — enemies inside your storm for 1 s become Forecast
function Kit.passive.init(f)
	f.state.exposure = {}
end
function Kit.passive.tick(f, dt)
	local inside = {}
	for _, z in ipairs(K.ownedZones(f, "storm")) do
		for t in pairs(z.inside) do
			if K.isEnemy(f, t) then
				inside[t] = true
			end
		end
	end
	for t in pairs(inside) do
		f.state.exposure[t] = (f.state.exposure[t] or 0) + dt
		if f.state.exposure[t] >= 1 then
			f.state.exposure[t] = 0
			forecast(f, t)
		end
	end
	for t in pairs(f.state.exposure) do
		if not inside[t] then
			f.state.exposure[t] = nil
		end
	end
end

-- 1 Squall Gust
Kit[1] = function(c)
	local f = c.f
	local dir = c:dir()
	local width = 1
	for _, z in ipairs(K.ownedZones(f, "storm")) do
		if K.Hit.pointSeg(z.pos, f.root.Position, f.root.Position + dir * K.m(12)) < z.radius then
			width = 1.5
		end
	end
	K.line(c, f.root.Position, dir, 12, width, {
		dmg = 70,
		color = Color3.fromRGB(190, 220, 255),
		hit = function(t)
			local extra = (c.p60 and K.has(t, "Forecast")) and 1 or 0
			K.push(c, t, dir, 1.5 + extra)
		end,
	})
end

-- 2 Rolling Front
Kit[2] = function(c)
	local f = c.f
	for _, z in ipairs(K.ownedZones(f, "storm")) do
		if not z.tags.ult then
			z:remove("replaced")
		end
	end
	local pos = c:aimPoint(16)
	local dir = c:dir()
	K.telegraphLine(c, pos, dir, 12, 1, 1, STORM)
	local cloud = K.FX.sphere(pos + Vector3.new(0, K.m(4), 0), K.m(5), STORM, 6, 0.4)
	local turned = false
	local lifetime = 6 + (K.partner(c, "Cloud", 20) and 1 or 0)
	local z = K.zone(c, {
		pos = pos,
		radius = 5,
		duration = lifetime,
		tick = 0.25,
		immediate = true,
		color = STORM,
		transparency = 0.7,
		tags = { storm = true },
		slow = { 0.1, 0.4 },
	})
	K.every(0.05, lifetime, function()
		if not z.alive then
			return false
		end
		local np = K.ground(z.pos + dir * K.m(2) * 0.05)
		z:move(np)
		cloud.Position = np + Vector3.new(0, K.m(4), 0)
		return true
	end)
	if c.p60 then
		c:recast(lifetime, function(c2)
			if not turned then
				turned = true
				local want = c2:dir()
				local sign = dir:Cross(want).Y >= 0 and -1 or 1
				dir = K.rotate(dir, 30 * sign)
				K.telegraphLine(c2, z.pos, dir, 6, 1, 0.6, STORM)
			end
		end)
	end
end

-- 3 Forecast Bolt
Kit.requires = {
	[3] = function(c)
		if c:target(18) then
			return true
		end
		return false, "No visible enemy"
	end,
}
Kit[3] = function(c)
	local t = c:target(18)
	if not t then
		return
	end
	local marker = K.feet(t)
	K.telegraph(c, marker, 1.4, 0.9, BOLT)
	task.wait(0.3)
	marker = K.feet(t) -- locks after 0.3 s
	K.telegraph(c, marker, 1.4, 0.6, Color3.fromRGB(255, 255, 120))
	task.wait(0.6)
	K.FX.beam(marker + Vector3.new(0, K.m(12), 0), marker, 1, BOLT, 0.2)
	local hits = K.enemiesIn(c, marker, 1.4, { above = 6 })
	for _, v in ipairs(hits) do
		local bonus = K.has(v, "Forecast") and 30 or 0
		if bonus > 0 then
			K.unmark(v, "Forecast")
		end
		K.dmg(c, v, 100 + bonus, { fromPos = marker + Vector3.new(0, 12, 0) })
	end
	if #hits == 0 and c.p60 then
		K.zone(c, { pos = marker, radius = 1.4, duration = 1.05, dmg = 25, tick = 1, color = BOLT })
	end
end

-- 4 Eye of Calm
Kit[4] = function(c)
	local f = c.f
	local given = {}
	K.zone(c, {
		pos = c:feet(),
		radius = 3,
		duration = 4,
		follow = f,
		targets = "allies",
		includeOwner = true,
		color = Color3.fromRGB(200, 230, 255),
		transparency = 0.7,
		enter = function(_, a)
			if not given[a] and not a.isSummon then
				given[a] = true
				K.shield(c, a, 60, 4, "EyeOfCalm")
				if c.p60 then
					K.cleanse(a, "slow", 1)
				end
			end
		end,
	})
end

-- 5 Supercell Procession (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local eye = center
	local cloud = K.FX.sphere(center + Vector3.new(0, K.m(5), 0), K.m(9), STORM, 7, 0.5)
	local totals = {}
	local z = K.zone(c, { pos = center, radius = 9, duration = 7, color = STORM, transparency = 0.8, tags = { storm = true, ult = true } })
	local t0 = K.now()
	local lanes = 0
	while K.now() - t0 < 7 and lanes < 4 do
		local progress = (K.now() - t0) / 7
		local moved = center + dir * K.m(8) * progress
		if c.unstable and lanes == 2 and not z.data.eyeMoved then
			z.data.eyeMoved = true
			local newEye = moved + side * K.m(3)
			K.telegraph(c, K.ground(newEye), 2, 1, Color3.fromRGB(120, 255, 140))
			task.wait(1)
			eye = newEye - (moved - center)
		end
		local cur = center + dir * K.m(8) * ((K.now() - t0) / 7)
		z:move(K.ground(cur))
		cloud.Position = cur + Vector3.new(0, K.m(5), 0)
		local eyeNow = cur + (eye - center)
		lanes += 1
		local laneDir = K.rotate(dir, lanes * 45)
		K.telegraphLine(c, cur - laneDir * K.m(9), laneDir, 18, 1.5, 0.8, BOLT)
		K.FX.ring(K.ground(eyeNow), K.m(2), Color3.fromRGB(120, 255, 140), 0.8, 0.25)
		task.wait(0.8)
		for _, t in ipairs(K.enemiesLine(c, cur - laneDir * K.m(9), laneDir, 18, 1.5)) do
			if K.flatDist(t, eyeNow) > 2 and (totals[t] or 0) < 3 then
				totals[t] = (totals[t] or 0) + 1
				K.dmg(c, t, 80, { fromPos = cur + Vector3.new(0, 10, 0) })
			end
		end
		K.line(c, cur - laneDir * K.m(9), laneDir, 18, 1.5, { color = BOLT })
		task.wait(0.4)
	end
	local _ = f
end

return Kit
