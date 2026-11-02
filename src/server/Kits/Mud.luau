-- 59 Mud — Adhesion and terrain viscosity
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local MUD = Color3.fromRGB(100, 75, 45)

-- Passive: Caked Soles — two Mud hits within 5 s apply Caked (dash distance -20%) for 3 s
local function cake(f, t)
	K.debuff(f, t, "Caked", { duration = 3, category = "slow", label = "Caked" })
end
function Kit.passive.dealt(f, target, info)
	if info.kind ~= "direct" or target.isSummon then
		return
	end
	local last = target.state.mudHitAt
	if last and K.now() - last <= 5 then
		cake(f, target)
		target.state.mudHitAt = nil
	else
		target.state.mudHitAt = K.now()
	end
end

local function puddle(c, pos, radius, dur)
	local water = K.partner(c, "Water", 20)
	return K.zone(c, {
		pos = pos,
		radius = water and radius * 1.3 or radius,
		duration = dur,
		tick = 0.25,
		immediate = true,
		slow = { water and 0.1 or 0.2, 0.4 },
		slowName = "Mud",
		color = MUD,
		transparency = 0.3,
		tags = { mud = true },
	})
end

-- 1 Silt Bomb
Kit[1] = function(c)
	local hit = false
	K.lob(c, {
		range = 18,
		speed = 18,
		width = 0.7,
		color = MUD,
		hit = function(t)
			hit = true
			K.dmg(c, t, 75, { projectile = true })
		end,
		land = function(pos)
			if not hit then
				for _, t in ipairs(K.enemiesIn(c, pos, 1.2)) do
					K.dmg(c, t, 75)
					break
				end
			end
			puddle(c, K.ground(pos), c.p60 and 3 or 2, 4)
		end,
	})
end

-- 2 Quagmire Grip
Kit[2] = function(c)
	local pos = c:aimPoint(14)
	K.telegraph(c, pos, 1.5, 0.7, MUD)
	task.wait(0.7)
	K.FX.beam(pos, pos + Vector3.new(0, K.m(2), 0), K.m(1.2), MUD, 0.4)
	for _, t in ipairs(K.enemiesIn(c, pos, 1.5, { above = 2 })) do
		K.dmg(c, t, 100, { fromPos = pos })
		K.root(c, t, 0.5)
		if c.p60 then
			cake(c.f, t)
		end
	end
end

-- 3 Mudslide
Kit[3] = function(c)
	local f = c.f
	local struck = {}
	if c.p60 then
		for _, o in ipairs(K.objects(c, f.root.Position, 3)) do
			if o.owner == nil and not o.tags.cover and o.hp < 150 then
				S.Objects.remove(o, "carried")
				K.shield(c, f, 40, 3, "Mudslide")
				break
			end
		end
	end
	local dir = c:dir()
	K.dash(c, dir, 8, 0.45, {
		passWidth = 2,
		onPass = function(t)
			if not struck[t] then
				struck[t] = true
				K.dmg(c, t, 80, { melee = true })
				K.push(c, t, dir, 2)
			end
		end,
	})
end

-- 4 Buried Engine
Kit.requires = {
	[4] = function(c)
		local pos = c:aimPoint(12)
		for _, o in ipairs(K.enemyObjects(c, pos, 3)) do
			if not o.isUlt and not o.tags.cover then
				return true
			end
		end
		for _, t in ipairs(K.enemies(c.f, 12)) do
			if t.isSummon and K.flatDist(t, pos) < 3 then
				return true
			end
		end
		return false, "No ground construct there"
	end,
}
Kit[4] = function(c)
	local pos = c:aimPoint(12)
	local target
	for _, o in ipairs(K.enemyObjects(c, pos, 3)) do
		if not o.isUlt and not o.tags.cover then
			target = o
			break
		end
	end
	if target then
		local casing = K.object(c, { name = "MudCasing", cf = target.part.CFrame, size = target.part.Size / K.M + Vector3.new(0.4, 0.4, 0.4), hp = 160, duration = 4, solid = false, color = MUD, material = Enum.Material.Mud, transparency = 0.2 })
		target.data.pausedUntil = K.now() + 4
		target.invulnerable = true
		casing.cleanup = function()
			if target.alive then
				target.invulnerable = nil
				target.data.pausedUntil = nil
			end
		end
		if c.p60 then
			S.Objects.stripLayer(target)
		end
		return
	end
	for _, t in ipairs(K.enemies(c.f, 12)) do
		if t.isSummon and K.flatDist(t, pos) < 3 then
			K.Status.apply(t, "stun", { duration = 4, source = c.f, category = "control", label = "Buried" })
			break
		end
	end
end

-- 5 World Without Footing (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	K.zone(c, {
		pos = center,
		radius = 8,
		duration = 7,
		tick = 0.25,
		immediate = true,
		color = MUD,
		transparency = 0.45,
		tickFn = function(_, list)
			for _, t in ipairs(list) do
				if K.isEnemy(f, t) and t.humanoid and t.humanoid.FloorMaterial ~= Enum.Material.Air then
					K.slow(c, t, 0.25, 0.4, "Basin")
				end
			end
		end,
	})
	local holes = {}
	for i = 0, 2 do
		local a = math.rad(i * 120 + 30)
		holes[i + 1] = K.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(4))
		K.FX.disc(holes[i + 1], K.m(2), Color3.fromRGB(60, 40, 25), 7, 0.2)
	end
	for _, h in ipairs(holes) do
		task.wait(1.2)
		K.telegraph(c, h, 2, 0.6, MUD)
		task.wait(0.6)
		K.circle(c, h, 2, { dmg = 90, color = MUD })
	end
	if c.unstable then
		task.wait(1.6)
		-- Deep Mire: the firm paths flood for 2 s, catching the caster too
		K.zone(c, {
			pos = center,
			radius = 8,
			duration = 2,
			tick = 0.25,
			immediate = true,
			targets = "all",
			color = Color3.fromRGB(80, 55, 30),
			transparency = 0.3,
			tickFn = function(_, list)
				for _, t in ipairs(list) do
					K.slow(c, t, 0.25, 0.4, "Flood")
				end
			end,
		})
		for _, t in ipairs(K.Hit.cylinder(center, K.m(8), function()
			return true
		end)) do
			K.Combat.damage(f, t, 100, { cast = c, isUlt = true, fromPos = center, element = "Mud" })
		end
	end
end

return Kit
