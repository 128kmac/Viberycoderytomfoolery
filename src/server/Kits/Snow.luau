-- 83 Snow — Accumulating powder and soft concealment
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local SNOW = Color3.fromRGB(240, 250, 255)

local function powder(f, t, n)
	if t.isSummon then
		return
	end
	local cur = K.stacks(t, "Powder")
	local nextN = math.min(3, cur + (n or 1))
	K.debuff(f, t, "Powder", { duration = 2, setStacks = nextN, max = 3, category = "slow", label = "Powder" })
	if nextN >= 3 then
		K.Status.remove(t, "Powder")
		K.debuff(f, t, "Powdered", { duration = 6, label = "Next dash -15%" })
	end
end

local function snowZone(c, opts)
	opts.tags = opts.tags or {}
	opts.tags.snow = true
	opts.color = opts.color or SNOW
	opts.transparency = opts.transparency or 0.4
	return K.zone(c, opts)
end

-- Passive: Powder Layer — one Powder each second in your snow; leaving for 2 s removes it
function Kit.passive.init(f)
	f.state.inSnow = {}
end
function Kit.passive.tick(f, dt)
	local inside = {}
	for _, z in ipairs(K.ownedZones(f, "snow")) do
		for t in pairs(z.inside) do
			if K.isEnemy(f, t) then
				inside[t] = true
			end
		end
	end
	for t in pairs(inside) do
		f.state.inSnow[t] = (f.state.inSnow[t] or 0) + dt
		if f.state.inSnow[t] >= 1 then
			f.state.inSnow[t] = 0
			powder(f, t, 1)
		end
	end
	for t in pairs(f.state.inSnow) do
		if not inside[t] then
			f.state.inSnow[t] = nil
		end
	end
end
local function onSnow(f)
	for _, z in ipairs(K.ownedZones(f, "snow")) do
		if z:contains(f) then
			return true
		end
	end
	return false
end

-- 1 Packed Snowball
Kit[1] = function(c)
	local hit = false
	K.lob(c, {
		range = 18,
		speed = 22,
		gravityM = 10,
		width = 0.6,
		color = SNOW,
		hit = function(t)
			hit = true
			K.dmg(c, t, 65, { projectile = true })
			powder(c.f, t, 1)
		end,
		land = function(pos, reason)
			if not hit and c.p60 and reason ~= "hit" then
				snowZone(c, { pos = K.ground(pos), radius = 1, duration = 3 })
			end
		end,
	})
end

-- 2 Powder Bank
Kit[2] = function(c)
	local f = c.f
	local pos = c:aimPoint(12)
	local dir = c:dir()
	local bank = K.wall(c, { name = "PowderBank", pos = pos, dir = dir, width = 4, height = 2, thick = 1.5, hp = 150, duration = 7, color = SNOW, material = Enum.Material.Snow, transparency = 0 })
	if K.partner(c, "Ice", 15) then
		bank.maxHp, bank.hp = 220, 220
		bank.part.Material = Enum.Material.Ice
		return
	end
	local crossed = {}
	K.every(0.1, 7, function()
		if not bank.alive then
			return false
		end
		local top = bank.part.Position + Vector3.new(0, bank.part.Size.Y / 2, 0)
		for _, t in ipairs(K.Hit.box(CFrame.new(top + Vector3.new(0, 3, 0)) * bank.part.CFrame.Rotation, Vector3.new(bank.part.Size.X, 6, bank.part.Size.Z + 2), function()
			return true
		end)) do
			if not crossed[t] then
				crossed[t] = true
				if K.isEnemy(f, t) then
					powder(f, t, 1)
				elseif c.p60 and not t.isSummon then
					K.shield(c, t, 30, 3, "PowderBank")
				end
			end
		end
		return true
	end)
end

-- 3 Silent Ski
Kit[3] = function(c)
	local f = c.f
	local dist = onSnow(f) and 10 or 8
	local start = c:feet()
	local dir = c:dir()
	if c.p60 and c.mod then
		local d1 = K.dash(c, dir, dist / 2, 0.2)
		local side = (c:aimPoint(20) - f.root.Position):Dot(K.flat(dir:Cross(Vector3.yAxis))) >= 0 and -20 or 20
		K.dash(c, K.rotate(dir, side), dist / 2, 0.2)
		local _ = d1
	else
		K.dash(c, dir, dist, 0.4)
	end
	K.FX.rect(CFrame.lookAt(start + dir * K.m(dist / 2) + Vector3.new(0, 0.1, 0), start + dir * K.m(dist)), K.m(0.6), K.m(dist), 3, SNOW, 0.3)
end

-- 4 Snow Veil
Kit[4] = function(c)
	local pos = c:aimPoint(16)
	local moved = false
	local vis = K.FX.sphere(pos + Vector3.new(0, K.m(2), 0), K.m(5), SNOW, 5, 0.65)
	local z = snowZone(c, {
		pos = pos,
		radius = 5,
		duration = 5,
		targets = "all",
		transparency = 0.7,
		enter = function(_, t)
			t.untargetable += 1
		end,
		exit = function(_, t)
			t.untargetable = math.max(0, t.untargetable - 1)
		end,
		finish = function(zz)
			for t in pairs(zz.inside) do
				t.untargetable = math.max(0, t.untargetable - 1)
			end
		end,
	})
	if c.p60 then
		c:recast(5, function(c2)
			if z.alive and not moved then
				moved = true
				local np = z.pos + K.flat(c2:aimPoint(30) - z.pos) * K.m(2)
				z:move(np)
				vis.Position = np + Vector3.new(0, K.m(2), 0)
			end
		end)
	end
end

-- 5 Avalanche Curtain (ultimate)
Kit[5] = function(c)
	local f = c.f
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local start = c:feet() + dir * K.m(2)
	local struck = {}
	local function curtain(offset, width, dmg)
		local center0 = start + side * K.m(offset)
		local wall = K.FX.base({ size = Vector3.new(K.m(width), K.m(3), K.m(1.5)), cf = CFrame.lookAt(center0, center0 + dir), color = SNOW, transparency = 0.1, material = Enum.Material.Snow })
		local traveled = 0
		while traveled < 12 do
			local p = center0 + dir * K.m(traveled) + Vector3.new(0, K.m(1.5), 0)
			if workspace:Raycast(p, dir * K.m(1), K.Hit.arenaParams) then
				break -- stops at major solid terrain
			end
			wall.CFrame = CFrame.lookAt(p, p + dir)
			for _, t in ipairs(K.Hit.box(wall.CFrame, wall.Size, K.enemyFilter(c))) do
				if not struck[t] then
					struck[t] = true -- one enemy can be hit by only one curtain
					K.dmg(c, t, dmg, { fromPos = p })
					K.push(c, t, dir, 3)
				end
			end
			traveled += 0.5
			task.wait(3 / 24)
		end
		wall:Destroy()
		snowZone(c, { shape = "rect", pos = center0, dir = dir, width = width, length = math.max(1, traveled), duration = 5 })
	end
	if c.unstable then
		K.spawn(curtain, -2.5, 4, 130)
		curtain(2.5, 4, 130)
	else
		curtain(0, 10, 170)
	end
	local _ = f
end

return Kit
