-- 42 Glass — Fragile precision and shard geometry
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local GLASS = Color3.fromRGB(200, 240, 240)

local function panes(f)
	return K.owned(f, "Pane")
end

-- Passive: Stress Lines — panes crack at half durability; deliberate breaking yields three 15-damage shards
local function makePane(c, cf, size, duration, opts)
	opts = opts or {}
	local o = K.object(c, {
		name = "Pane",
		cf = cf,
		size = size or Vector3.new(2.5, 2.5, 0.2),
		hp = 90,
		duration = duration or 6,
		color = GLASS,
		material = Enum.Material.Glass,
		transparency = 0.45,
		isUlt = opts.isUlt,
		onDamage = function(obj, amt)
			if obj.hp <= 45 and not obj.data.cracked then
				obj.data.cracked = true
				obj.part.Color = Color3.fromRGB(170, 200, 210)
			end
			if opts.heavyBreak and amt >= 80 then
				S.Objects.destroy(obj, nil)
			end
		end,
	})
	o.data.pane = true
	return o
end

local function shards(c, o, dir, budget)
	if o.data.shardsUsed then
		return
	end
	o.data.shardsUsed = true
	local pos = o.part.Position
	for _, t in ipairs(K.enemiesCone(c, 3, 60, pos, dir, false)) do
		for _ = 1, 3 do
			if budget then
				local d = math.min(15, budget.cap - (budget[t] or 0))
				if d > 0 then
					budget[t] = (budget[t] or 0) + d
					K.dmg(c, t, d, { fromPos = pos })
				end
			else
				K.dmg(c, t, 15, { fromPos = pos })
			end
		end
	end
	K.FX.cone(pos, dir, K.m(3), 60, GLASS, 0.2)
end

local function breakPane(c, o, dir, budget)
	if not o.alive then
		return
	end
	shards(c, o, dir, budget)
	S.Objects.remove(o, "shattered")
end

-- 1 Glass Needle
Kit[1] = function(c)
	local f = c.f
	local pierced = 0
	local maxPierce = c.p60 and 2 or 1
	local bonus = 0
	K.proj(c, {
		range = 24,
		speed = 34,
		width = 0.2,
		shape = "Block",
		size = Vector3.new(0.2, 0.2, 1.8),
		color = GLASS,
		transparency = 0.6,
		hit = function(t)
			K.dmg(c, t, math.min(120, 80 + bonus), { projectile = true })
		end,
		wall = function(_, _, obj, p)
			if obj and obj.owner == f and obj.data.pane and pierced < maxPierce then
				pierced += 1
				bonus += 20
				breakPane(c, obj, p.vel.Unit)
				return "pass"
			end
			return nil
		end,
	})
	K.FX.sound(f.root, "ping", 0.3)
end

-- 2 Window Step
Kit[2] = function(c)
	local f = c.f
	local feet = c:feet()
	makePane(c, CFrame.new(feet + Vector3.new(0, 0.6, 0)), Vector3.new(2.5, 1.2, 0.3), 4)
	local dest = K.ground(feet + c:dir() * K.m(5))
	local land = K.leap(c, dest, 0.4, 3)
	if c.p60 and K.Hit.spaceFree(K.Hit.standAt(land) + Vector3.new(0, 3, 0)) then
		makePane(c, CFrame.new(land + Vector3.new(0, 0.6, 0)), Vector3.new(2.5, 1.2, 0.3), 4)
	end
end

-- 3 Cutting Gallery
Kit[3] = function(c)
	local f = c.f
	local center = c:aimPoint(16)
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local list = {}
	for i = -1, 1 do
		local p = K.ground(center + side * K.m(i * 2.5)) + Vector3.new(0, K.m(1.25), 0)
		local facing = (c.p60 and c.mod) and K.rotate(dir, i * 30) or dir
		table.insert(list, makePane(c, CFrame.lookAt(p, p + facing), Vector3.new(2, 2.5, 0.2), 6, { heavyBreak = true }))
	end
	local last = {}
	K.every(0.1, 6, function()
		for _, o in ipairs(list) do
			if o.alive then
				for _, t in ipairs(K.enemiesIn(f, K.ground(o.part.Position), 1.4)) do
					if not last[t] or K.now() - last[t] >= 1 then
						last[t] = K.now()
						K.dmg(c, t, 35, { kind = "field" })
					end
				end
			end
		end
		return true
	end)
end

-- 4 Stress Release
Kit.requires = {
	[4] = function(c)
		if #panes(c.f) > 0 then
			return true
		end
		return false, "No panes"
	end,
}
Kit[4] = function(c)
	local f = c.f
	local aim = c:aimPoint(18)
	local list = panes(f)
	table.sort(list, function(a, b)
		return (a.part.Position - aim).Magnitude < (b.part.Position - aim).Magnitude
	end)
	local budget = { cap = 180 }
	for i = 1, math.min(3, #list) do
		local o = list[i]
		local function go()
			if not o.alive then
				return
			end
			local pos = o.part.Position
			local dir = K.flat(aim - pos)
			for _, t in ipairs(K.enemiesCone(c, 5, 70, pos, dir, false)) do
				local d = math.min(70, budget.cap - (budget[t] or 0))
				if d > 0 then
					budget[t] = (budget[t] or 0) + d
					K.dmg(c, t, d, { fromPos = pos })
				end
			end
			K.FX.cone(pos, dir, K.m(5), 70, GLASS, 0.25)
			breakPane(c, o, dir, budget)
		end
		if c.p60 and i == 1 and c.mod then
			K.after(0.5, go)
		else
			go()
		end
	end
end

-- 5 Cathedral Shatter (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	local list = {}
	for i = 0, 5 do
		local a = math.rad(i * 60)
		local p = K.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(7)) + Vector3.new(0, K.m(1.5), 0)
		list[i + 1] = makePane(c, CFrame.lookAt(p, Vector3.new(center.X, p.Y, center.Z)), Vector3.new(2.5, 3, 0.25), 8, { isUlt = true })
	end
	task.wait(1.5)
	local totals = {}
	local cap = c.unstable and 330 or 280
	local function lane(o)
		if not o.alive then
			return
		end
		local from = o.part.Position
		local to = Vector3.new(center.X, from.Y, center.Z) + K.flat(Vector3.new(center.X, from.Y, center.Z) - from) * K.m(7)
		K.FX.beam(from, to, 1, GLASS, 0.3)
		local filter = c.unstable and function()
			return true
		end or K.enemyFilter(c)
		for _, h in ipairs(K.Hit.segment(from, to, K.m(0.8), filter)) do
			local t = h.f
			local d = math.min(70, cap - (totals[t] or 0))
			if d > 0 then
				totals[t] = (totals[t] or 0) + d
				K.Combat.damage(f, t, d, { cast = c, isUlt = true, fromPos = from, element = "Glass" })
			end
		end
		S.Objects.remove(o, "fractured")
	end
	if c.unstable then
		for _, o in ipairs(list) do
			lane(o)
		end
	else
		for _, o in ipairs(list) do
			lane(o)
			task.wait(0.3)
		end
	end
end

return Kit
