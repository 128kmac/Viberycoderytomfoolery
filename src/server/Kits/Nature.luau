-- 62 Nature — Local ecosystems and cooperative territory
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local GREEN = Color3.fromRGB(60, 170, 60)
local WATER = Color3.fromRGB(80, 170, 255)

-- Passive: Living Balance — canopy, stream and wildlife each grant allies inside 3% resistance (max 9%)
local function components(f)
	local n = 0
	local canopy = f.state.canopy
	if canopy and canopy.alive then
		n += 1
	end
	if f.state.stream and f.state.stream.alive then
		n += 1
	end
	local deer = false
	for _, d in ipairs(K.summons(f, "Deer")) do
		if K.alive(d) then
			deer = true
		end
	end
	if deer then
		n += 1
	end
	return n
end
local function groveCenter(f)
	local c = f.state.canopy
	if c and c.alive then
		return c.part.Position
	end
	return f.root.Position
end
function Kit.passive.tick(f)
	local n = components(f)
	K.res(f, "Grove", n, 3, 1)
	if n > 0 then
		for _, a in ipairs(K.alliesIn(f, groveCenter(f), 8, true)) do
			K.dr(a, 0.03 * n, 0.3, "Living Balance")
		end
	end
end

-- 1 Canopy Seed
Kit[1] = function(c)
	local f = c.f
	local pos = c:aimPoint(15)
	local trunk = K.object(c, { name = "Canopy", pos = pos, size = Vector3.new(0.8, 3.5, 0.8), hp = 160, duration = 10, color = Color3.fromRGB(110, 80, 50), material = Enum.Material.Wood })
	f.state.canopy = trunk
	task.wait(1)
	if not trunk.alive then
		return
	end
	local leaves = K.object(c, { name = "CanopyLeaves", cf = CFrame.new(pos + Vector3.new(0, K.m(3.6), 0)), size = Vector3.new(8, 0.6, 8), shape = "Cylinder", hp = 160, duration = 9, solid = false, color = GREEN, material = Enum.Material.Grass, transparency = 0.2, noCap = true })
	leaves.part.CFrame = CFrame.new(pos + Vector3.new(0, K.m(3.6), 0)) * CFrame.Angles(0, 0, math.rad(90))
	leaves.part.Size = Vector3.new(K.m(0.6), K.m(8), K.m(8))
	trunk.cleanup = function()
		if leaves.alive then
			S.Objects.remove(leaves, "trunk gone")
		end
	end
	if c.p60 then
		local given = {}
		K.zone(c, { pos = pos, radius = 4, duration = 9, targets = "allies", includeOwner = true, noVisual = true, enter = function(_, a)
			if not given[a] and not a.isSummon then
				given[a] = true
				K.shield(c, a, 40, 3, "Canopy")
			end
		end })
	end
end

-- 2 Spring Run
Kit[2] = function(c)
	local f = c.f
	local start = c:feet()
	local dir = c:dir()
	local cleansed = false
	local z = K.zone(c, {
		shape = "rect",
		pos = start,
		dir = dir,
		width = 2.5,
		length = 8,
		duration = 7,
		tick = 0.25,
		immediate = true,
		targets = "all",
		color = WATER,
		transparency = 0.5,
		tickFn = function(zz, list)
			for _, t in ipairs(list) do
				local md = t.humanoid and t.humanoid.MoveDirection or Vector3.zero
				if md.Magnitude > 0.1 then
					local along = md:Dot(zz.dir)
					if K.isAlly(f, t) and along > 0.3 then
						K.speed(t, 0.12, 0.4, "Downstream")
					elseif K.isEnemy(f, t) and along < -0.3 then
						K.slow(c, t, 0.15, 0.4, "Upstream")
					end
				end
			end
		end,
		enter = function(_, t)
			if c.p60 and not cleansed and K.isAlly(f, t) then
				if K.cleanse(t, "burn", 1) > 0 then
					cleansed = true
				end
			end
		end,
	})
	f.state.stream = z
end

-- 3 Guardian Wildlife
Kit[3] = function(c)
	local f = c.f
	local center = c:aimPoint(14)
	local deer = {}
	for i = 1, 2 do
		local d = K.summon(c, { name = "Deer", pos = center + Vector3.new(i == 1 and 3 or -3, 2, 0), hp = 70, duration = 6, speed = 5, size = Vector3.new(0.9, 1.6, 1.6), shape = "Block", color = Color3.fromRGB(190, 230, 190), material = Enum.Material.ForceField, ai = "none" })
		d.data.blocked = false
		table.insert(deer, d)
	end
	K.every(0.03, 6, function(i)
		for n, d in ipairs(deer) do
			if K.alive(d) then
				local a = i * 0.03 + n * math.pi
				local p = center + Vector3.new(math.cos(a) * K.m(3), 2, math.sin(a) * K.m(3))
				d.root.CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a)))
				for _, pr in ipairs(K.enemyProj(c, p, 1.5)) do
					if pr.kind ~= "ultimate" then
						S.Proj.stop(pr, "intercepted")
						S.Summons.remove(d, "intercepted")
						break
					end
				end
			end
		end
		return true
	end)
	if c.p60 then
		K.after(5.9, function()
			for _, d in ipairs(deer) do
				if K.alive(d) then
					local hurt
					for _, a in ipairs(K.alliesIn(c, center, 10, true)) do
						if not hurt or a.health < hurt.health then
							hurt = a
						end
					end
					if hurt then
						K.heal(c, hurt, 40)
					end
					break
				end
			end
		end)
	end
end

-- 4 Season Turn (modifier = autumn, otherwise spring; P60 allows one change by recasting)
Kit[4] = function(c)
	local f = c.f
	local season = c.mod and "autumn" or "spring"
	local screen
	local function apply()
		K.announce(f, string.upper(season), season == "spring" and GREEN or Color3.fromRGB(220, 140, 60), 1)
		if screen then
			screen:Destroy()
			screen = nil
		end
		if season == "autumn" then
			screen = K.FX.ring(c:feet(), K.m(8), Color3.fromRGB(220, 140, 60), 5, K.m(0.6))
		end
	end
	apply()
	local inside = {}
	K.every(1, 5, function()
		if season == "spring" then
			for _, a in ipairs(K.alliesIn(c, f.root.Position, 8, true)) do
				K.heal(c, a, 15)
			end
		else
			for _, t in ipairs(K.enemies(f, 30)) do
				if K.dist(t, f) > 8 then
					-- enemies outside the leaf screen cannot lock onto allies inside
					for _, a in ipairs(K.alliesIn(c, f.root.Position, 8, true)) do
						if not inside[a] then
							inside[a] = true
							K.untargetable(a, 1)
							K.after(1, function()
								inside[a] = nil
							end)
						end
					end
					break
				end
			end
		end
		return true
	end)
	if c.p60 then
		c:recast(5, function()
			season = season == "spring" and "autumn" or "spring"
			apply()
		end)
	end
end

-- 5 Ancient Sanctuary (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(18)
	local tree = K.object(c, { name = "AncientTree", pos = center, size = Vector3.new(2.5, 7, 2.5), hp = 400, duration = 8, isUlt = true, color = Color3.fromRGB(100, 70, 45), material = Enum.Material.Wood })
	K.FX.sphere(center + Vector3.new(0, K.m(7), 0), K.m(4), GREEN, 8, 0.2)
	local roots = {}
	local function growRoots()
		for i = 0, 2 do
			local a = math.rad(i * 120)
			local d = Vector3.new(math.cos(a), 0, math.sin(a))
			roots[i + 1] = K.wall(c, { name = "SanctuaryRoot", pos = K.ground(center + d * K.m(5)), dir = d, width = 3, height = 1.5, hp = 100, duration = 8, isUlt = true, color = Color3.fromRGB(90, 60, 40), material = Enum.Material.Wood, transparency = 0 })
			roots[i + 1].data.dir = d
		end
	end
	growRoots()
	K.zone(c, {
		pos = center,
		radius = 9,
		duration = 8,
		heal = c.unstable and 10 or 20,
		targets = "allies",
		includeOwner = true,
		color = GREEN,
		transparency = 0.85,
		tickFn = function(z)
			if not tree.alive then
				z:remove("tree destroyed")
			end
		end,
	})
	local function release()
		for _, r in ipairs(roots) do
			if r.alive then
				local from = K.ground(r.part.Position)
				K.cone(c, { origin = from, dir = r.data.dir, range = 5, angle = 70, dmg = 70, color = GREEN })
				S.Objects.remove(r, "released")
			end
		end
	end
	if c.unstable then
		task.wait(3)
		release()
		growRoots() -- regrown roots inherit the original expiry time
		for _, r in ipairs(roots) do
			r.expires = K.now() + 5
		end
	end
	task.wait(c.unstable and 5 or 8)
	release()
end

return Kit
