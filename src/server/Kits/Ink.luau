-- 48 Ink — Drawn marks and limited animation
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local INK = Color3.fromRGB(25, 25, 40)

local function marks(f)
	local out = {}
	for _, o in ipairs(K.owned(f, "InkMark")) do
		table.insert(out, o)
	end
	table.sort(out, function(a, b)
		return a.created < b.created
	end)
	return out
end
local function dry(o)
	return K.now() >= o.data.dryAt
end
local function dryMarks(f)
	local out = {}
	for _, o in ipairs(marks(f)) do
		if dry(o) and not o.data.used then
			table.insert(out, o)
		end
	end
	return out
end
local function show(f)
	K.res(f, "Marks", #marks(f), 4, 1)
	K.res(f, "Dry", #dryMarks(f), nil, 2)
end

-- Passive: Wet Script — four marks, wet for 2 s, dry marks have 60 durability and one command
local function addMark(c, pos, duration)
	local f = c.f
	local list = marks(f)
	if #list >= 4 then
		S.Objects.remove(list[1], "replaced")
	end
	local o = K.object(c, { name = "InkMark", pos = pos, size = Vector3.new(1.6, 0.1, 1.6), hp = 60, duration = duration or 8, solid = false, queryable = true, color = INK, material = Enum.Material.SmoothPlastic, noCap = true })
	o.data.dryAt = K.now() + 2
	o.beforeDamage = function(obj, info)
		if not dry(obj) then
			info.amount = obj.hp + 1 -- wet ink washes away easily
		end
		if info.src and info.src.kitName == "Water" then
			info.amount += 40
		end
	end
	show(f)
	return o
end
function Kit.passive.tick(f)
	show(f)
end

-- 1 Brush Lance
Kit[1] = function(c)
	local f = c.f
	K.proj(c, {
		range = 18,
		width = 0.4,
		color = INK,
		dmg = 70,
		hit = function(t)
			K.mark(c, t, "Stain", 4, { label = "Ink Stain", color = INK })
			addMark(c, K.feet(t), 8)
		end,
		finish = function(pos, reason)
			if reason ~= "hit" then
				addMark(c, K.ground(pos), 8)
			end
		end,
		step = function(p)
			if c.p60 and not p.data.turned then
				for _, o in ipairs(dryMarks(f)) do
					if K.flatDist(o.part.Position, p.pos) < 1.2 then
						p.data.turned = true
						local t = K.nearestEnemy(f, 18, p.pos)
						if t then
							p.vel = (t.root.Position - p.pos).Unit * p.speed
						end
						break
					end
				end
			end
		end,
	})
end

-- 2 Underline (recast slides the caster along it)
Kit[2] = function(c)
	local f = c.f
	local start = c:feet()
	local dir = c:dir()
	local struck = {}
	local mid = K.object(c, { name = "UnderlineMid", pos = start + dir * K.m(4), size = Vector3.new(0.8, 0.1, 2.5), hp = 60, duration = 5, solid = false, queryable = true, color = INK, noLabel = true })
	K.zone(c, {
		shape = "rect",
		pos = start,
		dir = dir,
		width = 1,
		length = 8,
		duration = 5,
		color = INK,
		transparency = 0.2,
		enter = function(_, t)
			if K.isEnemy(f, t) and not struck[t] then
				struck[t] = true
				K.dmg(c, t, 45, { kind = "field" })
			end
		end,
	})
	c:recast(5, function(c2)
		local from = f.root.Position
		local to = K.Hit.standAt(start + dir * K.m(8))
		-- a broken middle segment stops travel
		if not mid.alive then
			to = K.Hit.standAt(start + dir * K.m(3.5))
		end
		local dist = (to - from).Magnitude
		K.path(c2, function(a)
			return from:Lerp(to, a)
		end, math.max(0.1, dist / K.m(12)))
	end)
end

-- 3 Drawn Beast
Kit.requires = {
	[3] = function(c)
		if #dryMarks(c.f) >= 2 then
			return true
		end
		return false, "Needs two dry marks"
	end,
}
Kit[3] = function(c)
	local f = c.f
	local ds = dryMarks(f)
	local spawnAt = ds[1].part.Position
	for i = 1, 2 do
		ds[i].data.used = true
		S.Objects.remove(ds[i], "animated")
	end
	local wolf = K.summon(c, { name = "InkWolf", pos = spawnAt + Vector3.new(0, 1.5, 0), hp = 140, duration = 5, speed = 0, size = Vector3.new(1.2, 1.2, 2.2), shape = "Block", color = INK, ai = "none" })
	local pounced = false
	local function pounce(target)
		if pounced or not K.alive(wolf) then
			return
		end
		pounced = true
		local from = wolf.root.Position
		local to = K.Hit.standAt(target)
		for s = 1, 10 do
			local p = from:Lerp(to, s / 10) + Vector3.new(0, math.sin(s / 10 * math.pi) * 3, 0)
			wolf.root.CFrame = CFrame.new(p)
			task.wait(0.03)
		end
		K.circle(c, target, 1.8, { dmg = 120, color = INK })
		S.Summons.remove(wolf, "dissolved")
	end
	c:recast(4.5, function(c2)
		if c2.p60 and c2.mod and not pounced then
			pounced = true
			S.Summons.remove(wolf, "recalled")
			addMark(c2, c2:feet(), 8)
			return
		end
		pounce(c2:aimPoint(12))
	end, {
		onExpire = function()
			pounce(c:aimPoint(12))
		end,
	})
end

-- 4 Redaction
Kit[4] = function(c)
	local f = c.f
	local t = c:target(16)
	if t then
		K.dmg(c, t, 90)
		K.cleanse(f, "reveal", 1)
	else
		local pos = c:aimPoint(16)
		local done = false
		for _, o in ipairs(K.enemyObjects(c, pos, 3)) do
			if o.hp < 150 and not o.isUlt then
				o.data.pausedUntil = K.now() + 1
				K.FX.beam(o.part.Position + Vector3.new(-1, 0.5, -1), o.part.Position + Vector3.new(1, 0.5, 1), 0.3, INK, 1)
				K.after(1, function()
					if o.alive then
						S.Objects.remove(o, "redacted")
					end
				end)
				done = true
				break
			end
		end
		if not done then
			for _, z in ipairs(K.zonesNear(pos, 3)) do
				if z.owner and K.isEnemy(f, z.owner) then
					K.after(1, function()
						z:remove("redacted")
					end)
					break
				end
			end
		end
	end
	if c.p60 then
		addMark(c, c:aimPoint(16), 4)
	end
end

-- 5 Black Manuscript (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local symbols = {
		{ kind = "Line", pos = K.ground(center - side * K.m(3.5)) },
		{ kind = "Fang", pos = center },
		{ kind = "Circle", pos = K.ground(center + side * K.m(3.5)) },
	}
	for _, s in ipairs(symbols) do
		s.obj = K.object(c, { name = "Symbol" .. s.kind, pos = s.pos, size = Vector3.new(3, 0.2, 3), hp = 120, duration = 7, isUlt = true, solid = false, queryable = true, color = INK })
		K.FX.text(s.pos + Vector3.new(0, 1, 0), s.kind, Color3.fromRGB(255, 255, 255), 7, 28)
	end
	local function activate(s, half)
		if not s.obj.alive then
			return
		end
		K.telegraph(c, s.pos, 3, 0.7, INK)
		task.wait(0.7)
		if not s.obj.alive then
			return
		end
		for _, t in ipairs(K.enemiesIn(c, s.pos, 3)) do
			if s.kind == "Line" then
				K.push(c, t, dir, 3)
			elseif s.kind == "Fang" then
				K.dmg(c, t, half and 65 or 130, { fromPos = s.pos })
			else
				K.root(c, t, 0.5)
			end
		end
		K.FX.burst(s.pos, K.m(3), INK, 0.3)
	end
	local fired = {}
	local function nextSymbol(chosen)
		local s = chosen
		if not s or fired[s] then
			for _, x in ipairs(symbols) do
				if not fired[x] then
					s = x
					break
				end
			end
		end
		if not s then
			return
		end
		fired[s] = true
		activate(s, false)
	end
	c:recast(4, function(c2)
		local aim = c2:aimPoint(30)
		local best, bd
		for _, s in ipairs(symbols) do
			if not fired[s] then
				local d = (s.pos - aim).Magnitude
				if not bd or d < bd then
					best, bd = s, d
				end
			end
		end
		nextSymbol(best)
		for _, s in ipairs(symbols) do
			if not fired[s] then
				return "keep"
			end
		end
		return nil
	end)
	task.wait(4)
	for _, s in ipairs(symbols) do
		if not fired[s] then
			nextSymbol(s)
		end
	end
	if c.unstable then
		for _, s in ipairs(symbols) do
			activate(s, true)
		end
		for _, o in ipairs(marks(f)) do
			S.Objects.remove(o, "washed")
		end
	end
end

return Kit
