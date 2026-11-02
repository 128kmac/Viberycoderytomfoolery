-- 18 Creation — Limited construction and resource allocation
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local GOLD = Color3.fromRGB(255, 220, 120)
local SHAPES = { "wall", "ramp", "platform" }

local function built(f)
	local out = {}
	for _, o in ipairs(K.owned(f)) do
		if o.data.creation then
			table.insert(out, o)
		end
	end
	table.sort(out, function(a, b)
		return a.created < b.created
	end)
	return out
end

local function liveDurability(f)
	local sum = 0
	for _, o in ipairs(built(f)) do
		sum += o.hp
	end
	return sum
end

local function cap(f)
	return f.state.capOverride or 300
end

local function show(f)
	K.res(f, "Blueprint", math.floor(f.state.reserve), cap(f), 1)
end

local function spend(f, amount)
	local avail = f.state.reserve
	local take = math.min(avail, amount)
	f.state.reserve -= take
	f.state.lastBuild = K.now()
	show(f)
	return take
end

local function shapeCF(kind, pos, dir)
	local d = K.flat(dir)
	if kind == "ramp" then
		local base = CFrame.lookAt(pos, pos + d) * CFrame.new(0, K.m(0.6), 0) * CFrame.Angles(math.rad(22), 0, 0)
		return base, Vector3.new(3, 0.4, 3.2)
	elseif kind == "platform" then
		return CFrame.lookAt(pos + Vector3.new(0, K.m(1.2), 0), pos + Vector3.new(0, K.m(1.2), 0) + d), Vector3.new(3, 0.4, 3)
	end
	return CFrame.lookAt(pos + Vector3.new(0, K.m(0.75), 0), pos + Vector3.new(0, K.m(0.75), 0) + d), Vector3.new(3, 1.5, 0.5)
end

local function build(c, kind, pos, dir, hp, duration, opts)
	local f = c.f or c
	opts = opts or {}
	local list = built(f)
	if #list >= 3 and not opts.ult then
		S.Objects.remove(list[1], "replaced")
	end
	local got = opts.free and hp or spend(f, hp)
	if got <= 0 then
		K.notify(f, "Blueprint reserve empty")
		return nil
	end
	local cf, size = shapeCF(kind, pos, dir)
	-- formation pushes players gently aside; it never traps anyone inside geometry
	for _, t in ipairs(K.Hit.box(cf, size * K.M + Vector3.new(0, 6, 0), function()
		return true
	end)) do
		K.push(c, t, K.flat(t.root.Position - pos), 1.5)
	end
	local o = K.object(c, {
		name = "Creation",
		cf = cf,
		size = size,
		hp = got,
		duration = duration,
		color = GOLD,
		material = Enum.Material.Marble,
		isUlt = opts.ult,
		noCap = true,
	})
	o.data.creation = true
	o.data.kind = kind
	o.data.dir = K.flat(dir)
	o.data.base = pos
	if K.partner(c, "Steel", 12) then
		S.Objects.reinforce(o, 60)
	end
	return o
end

-- Passive: Blueprint Budget
function Kit.passive.init(f)
	f.state.reserve = 300
	f.state.lastBuild = 0
	show(f)
end
function Kit.passive.tick(f, dt)
	local now = K.now()
	if now - f.state.lastBuild >= 2 and not (f.state.lockedUntil and f.state.lockedUntil > now) then
		local unused = cap(f) - liveDurability(f) - (f.state.locked or 0)
		if f.state.reserve < unused then
			f.state.reserve = math.min(unused, f.state.reserve + 25 * dt)
			show(f)
		end
	end
	if f.state.reserve > cap(f) - liveDurability(f) then
		f.state.reserve = math.max(0, cap(f) - liveDurability(f))
		show(f)
	end
end
-- V: dismiss the construct nearest the aim, refunding half its remaining durability
function Kit.action(f)
	local aim = f.aim and f.aim.hit or f.root.Position
	local best, bd
	for _, o in ipairs(built(f)) do
		local d = (o.part.Position - aim).Magnitude
		if not bd or d < bd then
			best, bd = o, d
		end
	end
	if best then
		f.state.reserve += best.hp * 0.5
		S.Objects.remove(best, "dismissed")
		show(f)
	end
end

-- 1 First Brick
Kit[1] = function(c)
	local pos = c:aimPoint(12)
	local kind = (c.p60 and c.mod) and "ramp" or "wall"
	build(c, kind, pos, c:dir(), 100, 8)
end

-- 2 Sculptor's Mallet
Kit[2] = function(c)
	local f = c.f
	local dir = c:dir()
	local front = f.root.Position + dir * K.m(2)
	for _, o in ipairs(built(f)) do
		if (o.part.Position - front).Magnitude < K.m(2.5) and o.hp > 40 then
			-- spend real durability for a launched chunk
			o.hp -= 40
			K.S.Objects.damage(o, 0.01, f)
			local from = o.part.Position + Vector3.new(0, 1, 0)
			K.proj(c, {
				origin = from,
				dir = c:dir3(),
				range = 14,
				speed = 26,
				width = 0.8,
				shape = "Block",
				size = Vector3.new(1.5, 1.5, 1.5),
				color = GOLD,
				dmg = 75,
				finish = function(pos)
					if c.p60 then
						local cv = K.object(c, { name = "Chunk", pos = K.ground(pos), size = 1.2, hp = 40, duration = 6, color = GOLD, material = Enum.Material.Marble })
						local _ = cv
					end
				end,
			})
			return
		end
	end
	K.melee(c, { range = 4, arc = 100, dmg = 85, color = GOLD })
end

-- 3 Revision
Kit.requires = {
	[3] = function(c)
		if #built(c.f) > 0 then
			return true
		end
		return false, "No construct to revise"
	end,
}
Kit[3] = function(c)
	local f = c.f
	local aim = c:aimPoint(14)
	local best, bd
	for _, o in ipairs(built(f)) do
		local d = (o.part.Position - aim).Magnitude
		if not bd or d < bd then
			best, bd = o, d
		end
	end
	if not best then
		return
	end
	K.FX.highlight(best.part, GOLD, 0.5, 0.4)
	task.wait(0.5)
	if not best.alive then
		return
	end
	local idx = table.find(SHAPES, best.data.kind) or 1
	local nextKind = SHAPES[idx % 3 + 1]
	local dir = best.data.dir
	if c.p60 and c.mod then
		dir = K.rotate(dir, 90)
	end
	local cf, size = shapeCF(nextKind, best.data.base, dir)
	for _, t in ipairs(K.Hit.box(cf, size * K.M + Vector3.new(0, 6, 0), function()
		return true
	end)) do
		K.push(c, t, K.flat(t.root.Position - best.data.base), 1.5)
	end
	best.part.Size = size * K.M
	best.part.CFrame = cf
	best.data.kind = nextKind
	best.data.dir = dir
end

-- 4 Emergency Prototype
Kit[4] = function(c)
	local f = c.f
	local borrowed = math.min(180, f.state.reserve)
	if borrowed <= 0 then
		K.notify(f, "No unused blueprint durability")
		return
	end
	spend(f, borrowed)
	local shield = K.object(c, {
		name = "Prototype",
		size = Vector3.new(3, 2.5, 0.4),
		hp = borrowed,
		duration = 2,
		color = GOLD,
		material = Enum.Material.ForceField,
		transparency = 0.3,
		noCap = true,
	})
	K.every(0.03, 2, function()
		if not shield.alive or not K.alive(f) then
			return false
		end
		local d = K.flat(f.root.CFrame.LookVector)
		local p = f.root.Position + d * K.m(1.2)
		shield.part.CFrame = CFrame.lookAt(p, p + d)
		return true
	end)
	f.state.locked = borrowed
	f.state.lockedUntil = K.now() + 8
	K.after(8, function()
		f.state.locked = 0
	end)
	if c.p60 then
		for _, a in ipairs(K.alliesIn(c, f.root.Position, 8, false)) do
			if a.humanoid and a.humanoid.FloorMaterial == Enum.Material.Air then
				K.object(c, { name = "Platform", cf = CFrame.new(a.root.Position - Vector3.new(0, 3.2, 0)), size = Vector3.new(2, 0.3, 2), hp = 60, duration = 3, color = GOLD })
				break
			end
		end
	end
end

-- 5 Genesis Workshop (ultimate)
Kit[5] = function(c)
	local f = c.f
	f.state.capOverride = 700
	f.state.reserve = math.max(f.state.reserve, 400)
	local center = c:aimPoint(20)
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local structs = {
		build(c, "wall", K.ground(center + dir * K.m(3)), dir, 200, 8, { ult = true, free = true }),
		build(c, "ramp", K.ground(center - side * K.m(4)), side, 200, 8, { ult = true, free = true }),
		build(c, "platform", K.ground(center + side * K.m(4)), -side, 200, 8, { ult = true, free = true }),
	}
	local shoves = c.unstable and 3 or 2
	local function shove(o, aim)
		if not o or not o.alive then
			return
		end
		local from = o.part.Position
		local to = Vector3.new(aim.X, from.Y, aim.Z)
		local d = K.flat(to - from)
		local hit = {}
		for i = 1, 10 do
			local p = from + d * K.m(8) * (i / 10)
			o.part.CFrame = CFrame.lookAt(p, p + d)
			for _, t in ipairs(K.enemiesIn(c, K.ground(p), 2)) do
				if not hit[t] then
					hit[t] = true
					K.dmg(c, t, 180, { fromPos = p })
					K.push(c, t, d, 3)
				end
			end
			task.wait(0.03)
		end
		S.Objects.remove(o, "consumed")
	end
	c:recast(8, function(c2)
		local aim = c2:aimPoint(30)
		local best, bd
		for _, o in ipairs(structs) do
			if o and o.alive then
				local d = (o.part.Position - aim).Magnitude
				if not bd or d < bd then
					best, bd = o, d
				end
			end
		end
		shove(best, aim)
		shoves -= 1
		if shoves > 0 then
			return "keep"
		end
		return nil
	end)
	K.after(8, function()
		f.state.capOverride = nil
		for _, o in ipairs(structs) do
			if o and o.alive then
				S.Objects.remove(o, "crumbled")
			end
		end
	end)
end

return Kit
