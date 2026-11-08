-- 46 Ice — Brittleness and constrained freezing
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local ICE = Color3.fromRGB(160, 220, 255)

local function frozen(t)
	return K.has(t, "Frozen")
end

-- Passive: Chill Threshold — at three Chill the next Ice hit freezes for 0.6 s
function Kit.passive.dealt(f, target, info)
	if info.kind ~= "direct" or target.isSummon then
		return
	end
	if K.stacks(target, "Chill") >= 3 and not (target.state.freezeImmune and target.state.freezeImmune > K.now()) then
		K.unmark(target, "Chill")
		target.state.freezeImmune = K.now() + 3.6
		local applied = K.Combat.control(target, "stun", 0.6, f)
		if applied > 0 then
			K.mark(f, target, "Frozen", applied, { label = "Frozen", color = ICE })
		end
	elseif info.opts.cast then
		K.debuff(f, target, "Chill", { duration = 5, stacks = 1, max = 3, category = "slow", slow = 0.05 * (K.stacks(target, "Chill") + 1), label = "Chill" })
	end
end

local function slick(c, pos, dir, len, dur)
	return K.zone(c, { shape = "rect", pos = pos, dir = dir, width = 1.6, length = len, duration = dur or 3, targets = "all", color = Color3.fromRGB(220, 245, 255), transparency = 0.5 })
end

-- 1 Rime Lance
Kit[1] = function(c)
	local f = c.f
	local pierced = false
	K.proj(c, {
		range = 22,
		width = 0.4,
		shape = "Block",
		size = Vector3.new(0.4, 0.4, 2.4),
		color = ICE,
		dmg = 80,
		wall = function(pos, normal, obj)
			if obj and obj.owner == f and obj.name == "IceShard" and c.p60 and not pierced then
				pierced = true
				return "pass"
			end
			K.object(c, { name = "IceShard", cf = CFrame.lookAt(pos, pos + normal) * CFrame.new(0, 0, -0.5), size = Vector3.new(0.6, 0.6, 1.6), hp = 80, duration = 5, color = ICE, material = Enum.Material.Ice })
			return nil
		end,
	})
end

-- 2 Skate Cut
Kit[2] = function(c)
	local start = c:feet()
	local dir = c:dir()
	local struck = {}
	local function pass(t)
		if not struck[t] then
			struck[t] = true
			K.dmg(c, t, 70, { melee = true })
		end
	end
	if c.p60 and c.mod then
		local d1 = K.dash(c, dir, 3.5, 0.15, { passWidth = 1.6, onPass = pass })
		local side = K.flat(dir:Cross(Vector3.yAxis))
		local rel = (c:aimPoint(16) - c.f.root.Position):Dot(side)
		local dir2 = K.rotate(dir, rel >= 0 and -45 or 45)
		K.dash(c, dir2, 3.5, 0.15, { passWidth = 1.6, onPass = pass })
		slick(c, start, dir, d1)
	else
		local d = K.dash(c, dir, 7, 0.3, { passWidth = 1.6, onPass = pass })
		slick(c, start, dir, math.max(1, d))
	end
end

-- 3 Cryo Bastion (recast breaks it into a harmless slick)
Kit[3] = function(c)
	local pos = c:aimPoint(12)
	local dir = c:dir()
	local wall = K.wall(c, { name = "CryoBastion", pos = pos, dir = dir, width = 4, height = 3, thick = 0.8, hp = 220, duration = 7, color = ICE, material = Enum.Material.Ice, transparency = 0.2 })
	wall.beforeDamage = function(_, info)
		if info.src and info.src.kitName == "Fire" then
			info.amount += 50
		end
	end
	if c.p60 and c.mod then
		wall.part.Size -= Vector3.new(0, K.m(0.5), 0)
	end
	c:recast(7, function(c2)
		if wall.alive then
			S.Objects.remove(wall, "broken")
			slick(c2, pos - K.flat(dir:Cross(Vector3.yAxis)) * K.m(2), K.flat(dir:Cross(Vector3.yAxis)), 4, 3)
		end
	end)
end

-- 4 Brittle Verdict
Kit[4] = function(c)
	local f = c.f
	local pos = c:aimPoint(14)
	local radius = 3
	if c.p60 then
		for _, o in ipairs(K.owned(f, "IceShard")) do
			if K.flatDist(o.part.Position, pos) <= 5 then
				S.Objects.remove(o, "consumed")
				radius = 4
			end
		end
	end
	K.telegraph(c, pos, radius, 0.8, ICE)
	task.wait(0.8)
	K.circle(c, pos, radius, {
		color = ICE,
		hit = function(t)
			local wasFrozen = frozen(t)
			K.dmg(c, t, wasFrozen and 150 or 120, { fromPos = pos })
			if wasFrozen then
				K.unmark(t, "Frozen")
				K.Status.remove(t, "stun", "released")
			end
		end,
	})
end

-- 5 Winter Cathedral (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	local pillars = {}
	for i = 0, 5 do
		local a = math.rad(i * 60)
		pillars[i + 1] = K.object(c, {
			name = "WinterPillar",
			pos = K.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(7)),
			size = Vector3.new(1, 3.5, 1),
			hp = 120,
			duration = 7,
			isUlt = true,
			color = ICE,
			material = Enum.Material.Ice,
		})
	end
	K.phase(c, "begin", { p = center, r = K.m(7) })
	for lane = 1, 3 do
		local a, b = pillars[lane], pillars[lane + 3]
		local pa, pb = (a.part.Position), (b.part.Position)
		local open = not (a.alive and b.alive)
		K.FX.beam(pa, pb, K.m(1.5), open and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 80, 80), 0.7, 0.6)
		K.phase(c, "warn", { a = pa, b = pb, open = open or nil })
		task.wait(0.7)
		if not open then
			K.phase(c, "strike", { a = pa, b = pb })
			K.FX.beam(pa, pb, K.m(1.5), ICE, 0.3)
			for _, h in ipairs(K.Hit.segment(pa, pb, K.m(0.9), K.enemyFilter(c))) do
				K.dmg(c, h.f, 80, { fromPos = pa })
				local applied = K.Combat.control(h.f, "stun", 0.5, f)
				if applied > 0 then
					K.mark(c, h.f, "Frozen", applied, { label = "Frozen", color = ICE })
				end
			end
		end
		task.wait(0.4)
	end
	K.phase(c, "finish", { p = center })
	if c.unstable then
		K.phase(c, "shatter", { p = center })
		local any = false
		for _, p in ipairs(pillars) do
			if p.alive then
				any = true
				S.Objects.remove(p, "shattered")
				K.FX.burst(p.part.Position, K.m(2), ICE, 0.3)
			end
		end
		if any then
			for _, t in ipairs(K.Hit.cylinder(center, K.m(7.5), function()
				return true
			end)) do
				K.Combat.damage(f, t, 140, { cast = c, isUlt = true, fromPos = center, element = "Ice" })
			end
		end
		for _, z in ipairs(K.ownedZones(f)) do
			z:remove("black ice")
		end
	end
end

return Kit
