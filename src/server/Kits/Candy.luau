-- 11 Candy — Sticky traps and brittle confectionery
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local PINK = Color3.fromRGB(255, 130, 200)
local HARD = Color3.fromRGB(255, 90, 120)
local KIND = { "soft", "hard", "soft", "hard", "hard" }

local function setTemper(f, n)
	f.state.temper = math.clamp(n, 0, 2)
	K.res(f, "Temper", f.state.temper, 2, 1)
end
local function temperBonus(f)
	if (f.state.temper or 0) > 0 then
		setTemper(f, f.state.temper - 1)
		return 40
	end
	return 0
end

-- Passive: Sugar Temper
function Kit.passive.init(f)
	setTemper(f, 0)
end
function Kit.passive.cast(f, c)
	local kind = KIND[c.slot]
	if f.state.lastKind and f.state.lastKind ~= kind and c.slot ~= 5 then
		setTemper(f, f.state.temper + 1)
	end
	f.state.lastKind = kind
end

-- 1 Taffy Snare
Kit[1] = function(c)
	local f = c.f
	local dir = c:dir()
	K.proj(c, {
		range = 16,
		width = 0.4,
		color = PINK,
		dmg = 55,
		hit = function(t)
			K.slow(c, t, 0.25, 2, "Taffy")
		end,
		wall = function(pos)
			local width = c.p60 and 5 or 3
			local side = K.flat(dir:Cross(Vector3.yAxis))
			local base = K.ground(pos - dir * K.m(0.5))
			local wire = K.object(c, {
				name = "Tripwire",
				cf = CFrame.lookAt(base + Vector3.new(0, 0.3, 0), base + Vector3.new(0, 0.3, 0) + side),
				size = Vector3.new(0.15, 0.15, width),
				hp = 40 + temperBonus(f),
				duration = 4,
				solid = false,
				blocks = true,
				color = PINK,
				material = Enum.Material.Neon,
			})
			K.every(0.1, 4, function()
				if not wire.alive then
					return false
				end
				for _, t in ipairs(K.enemiesLine(c, base - side * K.m(width / 2), side, width, 0.8, 1)) do
					K.dmg(c, t, 55, { kind = "field" })
					K.slow(c, t, 0.25, 2, "Taffy")
					S.Objects.remove(wire, "tripped")
					return false
				end
				return true
			end)
		end,
	})
end

-- 2 Jawbreaker Ricochet (rebounds from two walls, -20 damage per rebound, never hits a player twice)
Kit[2] = function(c)
	local f = c.f
	local dmg = 90
	local bounces = 0
	K.proj(c, {
		dir = c:dir(),
		origin = f.root.Position - Vector3.new(0, 1.2, 0),
		range = 40,
		speed = 22,
		width = 0.9,
		ground = true,
		color = HARD,
		data = { keepHits = true },
		hit = function(t)
			K.dmg(c, t, dmg, { projectile = true })
			return "continue"
		end,
		wall = function(pos, normal, obj, p)
			if obj then
				K.objDmg(c, obj, dmg)
			end
			if bounces >= 2 then
				return nil
			end
			local n = Vector3.new(normal.X, 0, normal.Z)
			if n.Magnitude < 0.1 then
				return nil
			end
			n = n.Unit
			bounces += 1
			dmg -= 20
			local v = p.vel
			p.vel = v - 2 * v:Dot(n) * n
			if c.p60 then
				K.zone(c, { pos = K.ground(pos), radius = 1.5, duration = 1, slow = { 0.25, 1 }, color = PINK, tick = 0.25, immediate = true })
			end
			return "bounce"
		end,
	})
end

-- 3 Cotton Cloud
Kit[3] = function(c)
	local f = c.f
	local pos = c:aimPoint(10)
	local cloud = K.object(c, {
		name = "CottonCloud",
		pos = pos,
		size = Vector3.new(3, 1.6, 3),
		shape = "Ball",
		hp = 120 + temperBonus(f),
		duration = 5,
		solid = false,
		blocks = true,
		color = Color3.fromRGB(255, 220, 240),
		material = Enum.Material.SmoothPlastic,
		transparency = 0.25,
	})
	if K.partner(c, "Ice", 15) then
		cloud.maxHp, cloud.hp = 160, 160
		cloud.part.Material = Enum.Material.Ice
		return
	end
	local bounces = c.p60 and 2 or 1
	local used = {}
	K.every(0.1, 5, function()
		if not cloud.alive or bounces <= 0 then
			return false
		end
		for _, a in ipairs(K.alliesIn(f, pos, 1.6, true)) do
			if not used[a] and a.humanoid then
				used[a] = true
				bounces -= 1
				S.Fighter.displace(a, Vector3.new(0, 1, 0), K.m(4), 0.3)
				if bounces <= 0 then
					return false
				end
			end
		end
		return true
	end)
end

-- 4 Caramel Lock
Kit[4] = function(c)
	local f = c.f
	local pos = c:aimPoint(12)
	local delay = (c.p60 and c.mod) and 2 or 1
	K.zone(c, { pos = pos, radius = 3, duration = delay, color = Color3.fromRGB(200, 120, 40), slow = { 0.15, 0.5 }, tick = 0.25 })
	K.delayed(c, pos, 3, delay, function()
		K.circle(c, pos, 3, {
			dmg = 100,
			color = Color3.fromRGB(200, 120, 40),
			hit = function(t)
				K.root(c, t, 0.6)
			end,
		})
		K.object(c, {
			name = "HardCaramel",
			pos = pos,
			size = Vector3.new(4, 1, 4),
			hp = 160 + temperBonus(f),
			duration = 6,
			color = Color3.fromRGB(190, 110, 40),
			material = Enum.Material.Glass,
			transparency = 0.2,
		})
	end, Color3.fromRGB(200, 120, 40))
end

-- 5 Sugar Palace (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(18)
	local walls = {}
	local bonus = temperBonus(f)
	for i = 0, 3 do
		local a = math.rad(i * 90)
		local d = Vector3.new(math.cos(a), 0, math.sin(a))
		walls[i + 1] = K.wall(c, {
			name = "SugarWall",
			pos = K.ground(center + d * K.m(6)),
			dir = d,
			width = 8,
			height = 3,
			thick = 0.6,
			hp = 160 + bonus,
			duration = 6,
			isUlt = true,
			color = HARD,
			material = Enum.Material.Glass,
			transparency = 0.3,
		})
	end
	local function shatter()
		local count = 0
		for _, w in ipairs(walls) do
			if w.alive then
				count += 1
				S.Objects.remove(w, "shattered")
				K.FX.burst(w.part.Position, K.m(2), HARD, 0.3)
			end
		end
		if count == 0 then
			return
		end
		local dmg = math.min(210, 70 * count)
		local targets
		if c.unstable then
			targets = K.Hit.cylinder(center, K.m(6.5), function()
				return true
			end)
		else
			targets = K.enemiesIn(c, center, 6.5)
		end
		for _, t in ipairs(targets) do
			K.Combat.damage(f, t, dmg, { cast = c, isUlt = true, fromPos = center, element = "Candy" })
			if c.unstable then
				K.slow(c, t, 0.3, 2, "Syrup Shards")
			end
		end
	end
	c:recast(6, function()
		shatter()
	end)
end

return Kit
