-- 28 Earth — Terrain shaping and grounded control
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local BROWN = Color3.fromRGB(130, 100, 60)

-- Passive: Ground Sense
function Kit.passive.tick(f, dt)
	local hum = f.humanoid
	if not hum then
		return
	end
	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	if grounded and hum.MoveDirection.Magnitude < 0.05 and not S.Cast.isBusy(f) then
		f.state.still = (f.state.still or 0) + dt
		if f.state.still >= 0.6 then
			for _, t in ipairs(K.enemies(f, 8)) do
				local th = t.humanoid
				if th and th.FloorMaterial ~= Enum.Material.Air and th.MoveDirection.Magnitude > 0.1 then
					K.reveal(f, t, 2)
					K.FX.ring(K.feet(t), 2, BROWN, 0.4, 0.3)
				end
			end
			f.state.still = 0
		end
	else
		f.state.still = 0
	end
end
function Kit.passive.cast(f)
	f.state.still = 0
end

local function ridge(c, pos, len, dir, dur)
	return K.object(c, {
		name = "EarthRidge",
		cf = CFrame.lookAt(pos + Vector3.new(0, K.m(0.4), 0), pos + Vector3.new(0, K.m(0.4), 0) + dir),
		size = Vector3.new(1, 0.8, len),
		hp = 120,
		duration = dur or 5,
		color = BROWN,
		material = Enum.Material.Rock,
	})
end

-- 1 Fault Jab
Kit[1] = function(c)
	local f = c.f
	K.proj(c, {
		origin = c:feet() + Vector3.new(0, 0.6, 0),
		dir = c:dir(),
		range = 14,
		speed = 18,
		width = 0.8,
		ground = true,
		shape = "Block",
		size = Vector3.new(1.2, 1.4, 1.6),
		color = BROWN,
		dmg = 80,
		step = function(p)
			if not K.Hit.ground(p.pos + Vector3.new(0, 2, 0), 6) then
				S.Proj.stop(p, "gap")
			end
			if c.p60 and not p.data.turned then
				for _, o in ipairs(K.owned(f, "EarthRidge")) do
					if (o.part.Position - p.pos).Magnitude < K.m(1.5) then
						p.data.turned = true
						local t = K.nearestEnemy(f, 16, p.pos)
						if t then
							p.vel = K.flat(t.root.Position - p.pos) * p.speed
						end
						break
					end
				end
			end
		end,
	})
end

-- 2 Rampart Rise
Kit[2] = function(c)
	local pos = c:aimPoint(12)
	local dir = c:dir()
	for _, t in ipairs(K.Hit.box(CFrame.lookAt(pos, pos + dir), Vector3.new(K.m(4), K.m(6), K.m(1.2)), function()
		return true
	end)) do
		K.push(c, t, K.flat(t.root.Position - pos), 1.5)
	end
	K.wall(c, { name = "Rampart", pos = pos, dir = dir, width = 4, height = 3, thick = 0.8, hp = 240, duration = 8, color = BROWN, material = Enum.Material.Rock, transparency = 0 })
	if c.p60 and c.mod then
		local rampPos = pos - dir * K.m(1.6)
		K.object(c, {
			name = "RampartRamp",
			cf = CFrame.lookAt(rampPos + Vector3.new(0, K.m(1.2), 0), rampPos + Vector3.new(0, K.m(1.2), 0) + dir) * CFrame.Angles(math.rad(38), 0, 0),
			size = Vector3.new(3.5, 0.4, 4),
			hp = 120,
			duration = 8,
			color = BROWN,
			material = Enum.Material.Rock,
		})
	end
	if K.partner(c, "Plant", 15) then
		local walls = K.owned(c.f, "Rampart")
		if walls[#walls] then
			S.Objects.reinforce(walls[#walls], 50)
		end
	end
end

-- 3 Burrow Lane
Kit[3] = function(c)
	local f = c.f
	local start = f.root.Position
	local dir = c:dir()
	local dest = K.Hit.clearPath(start, dir, K.m(8), 1.2)
	local restore = K.conceal(f, 1.1, 0.95)
	local mound = K.FX.base({ shape = Enum.PartType.Ball, size = Vector3.new(4, 2, 4), cf = CFrame.new(K.feet(f)), color = BROWN, transparency = 0.1, material = Enum.Material.Ground })
	local early = false
	c:recast(1, function()
		early = true
	end)
	local t0 = K.now()
	K.path(c, function(a)
		if early then
			return f.root.Position
		end
		local p = start:Lerp(dest, a)
		mound.Position = K.ground(p)
		return p
	end, 1)
	local _ = t0
	mound:Destroy()
	restore()
	c:closeRecast()
	K.circle(c, c:feet(), 2, { dmg = 75, color = BROWN })
end

-- 4 Seismic Fold
Kit[4] = function(c)
	local center = c:aimPoint(16)
	local dir = c:dir()
	if c.p60 and c.mod then
		dir = K.rotate(dir, 45)
	end
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local strips = {}
	for _, s in ipairs({ -1, 1 }) do
		local mid = center + side * K.m(2.25 * s)
		table.insert(strips, mid)
		K.FX.rect(CFrame.lookAt(mid + Vector3.new(0, 0.2, 0), mid + Vector3.new(0, 0.2, 0) + dir), K.m(3), K.m(8), 0.8, BROWN, 0.4)
	end
	K.FX.rect(CFrame.lookAt(center + Vector3.new(0, 0.25, 0), center + Vector3.new(0, 0.25, 0) + dir), K.m(1.5), K.m(8), 0.8, Color3.fromRGB(120, 255, 140), 0.6)
	task.wait(0.8)
	local hit = {}
	for _, mid in ipairs(strips) do
		for _, t in ipairs(K.Hit.box(CFrame.lookAt(mid, mid + dir), Vector3.new(K.m(3), K.m(5), K.m(8)), K.enemyFilter(c))) do
			if not hit[t] then
				hit[t] = true
				K.dmg(c, t, 130, { fromPos = mid })
				K.stun(c, t, 0.6)
			end
		end
		ridge(c, mid - dir * K.m(4), 8, dir, 5)
	end
end

-- 5 Continental Verdict (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(22)
	local totals = {}
	local terraces = {}
	K.phase(c, "begin", { p = center, r = K.m(9) })
	for q = 0, 3 do
		local a0 = q * 90
		K.arcFX(center, 4.5, a0, a0 + 90, Color3.fromRGB(255, 160, 60), 1, 9)
		K.phase(c, "warn", { p = center, r = K.m(9), a0 = a0, q = q })
		task.wait(1)
		K.phase(c, "rise", { p = center, r = K.m(9), a0 = a0, q = q })
		local a = math.rad(a0 + 45)
		local mid = center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(3.2)
		for _, t in ipairs(K.enemiesIn(c, center, 9)) do
			if K.inSector(K.angleOf(center, t.root.Position), a0, 90) then
				local d = math.min(75, 250 - (totals[t] or 0))
				if d > 0 then
					totals[t] = (totals[t] or 0) + d
					K.dmg(c, t, d, { fromPos = mid })
					K.lift(c, t, 0.3, 1)
				end
			end
		end
		terraces[q + 1] = K.object(c, {
			name = "Terrace",
			cf = CFrame.new(mid + Vector3.new(0, K.m(0.5 + q * 0.4), 0)),
			size = Vector3.new(4.2, 1 + q * 0.8, 4.2),
			hp = 300,
			duration = 8,
			isUlt = true,
			color = BROWN,
			material = Enum.Material.Rock,
		})
	end
	K.phase(c, "finish", { p = center })
	if c.unstable then
		task.wait(0.5)
		K.phase(c, "drop", { p = center, r = K.m(9) })
		K.telegraph(c, center, 9, 0.6, Color3.fromRGB(255, 80, 40))
		task.wait(0.6)
		for _, o in ipairs(terraces) do
			S.Objects.remove(o, "dropped")
		end
		for _, t in ipairs(K.Hit.cylinder(center, K.m(9), function()
			return true
		end)) do
			K.Combat.damage(f, t, 140, { cast = c, isUlt = true, fromPos = center, element = "Earth" })
		end
		K.FX.burst(center, K.m(9), BROWN, 0.4)
	end
end

return Kit
