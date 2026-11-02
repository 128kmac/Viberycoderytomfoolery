-- 68 Plant — Root networks and living architecture
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local GREEN = Color3.fromRGB(80, 200, 80)
local WOOD = Color3.fromRGB(110, 80, 50)

local function structures(f)
	local out = {}
	for _, o in ipairs(K.owned(f)) do
		if o.data.plant and not o.isUlt then
			table.insert(out, o)
		end
	end
	table.sort(out, function(a, b)
		return a.created < b.created
	end)
	return out
end

local function grow(c, opts)
	local f = c.f
	local list = structures(f)
	if #list >= 4 and not opts.isUlt then
		S.Objects.remove(list[1], "withered")
	end
	opts.noCap = true
	local o = K.object(c, opts)
	o.data.plant = true
	return o
end

-- Passive: Root Network (structures within 6 m connect; connected placements grow 0.2 s faster)
local function connectedNear(f, pos)
	for _, o in ipairs(structures(f)) do
		if K.flatDist(o.part.Position, pos) <= 6 then
			return true
		end
	end
	return false
end
function Kit.passive.tick(f)
	K.res(f, "Structures", #structures(f), 4, 1)
end

-- 1 Vine Lash (terrain hit anchors; recast pulls you up to 5 m toward it)
Kit[1] = function(c)
	local f = c.f
	local endPos, struck, res = K.beam(c, { length = 10, width = 0.5, dmg = 80, color = GREEN, dur = 0.3 })
	if #struck == 0 and res then
		local anchor = endPos
		local dur = c.p60 and 5 or 3
		local vis = K.FX.beam(f.root.Position, anchor, 0.2, GREEN, dur, 0.3)
		local _ = vis
		c:recast(dur, function(c2)
			local d = anchor - f.root.Position
			K.dash(c2, d.Unit, math.min(5, d.Magnitude / K.M - 1), 0.25, { allowY = true })
		end)
	end
end

-- 2 Root Lattice
Kit[2] = function(c)
	local f = c.f
	local center = c:aimPoint(14)
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local delay = connectedNear(f, center) and 0 or 0.2
	task.wait(delay)
	local roots = {}
	for i = -1, 1 do
		local p = K.ground(center + dir * K.m(i * 2))
		local r = grow(c, { name = "LatticeRoot", cf = CFrame.lookAt(p + Vector3.new(0, K.m(0.2), 0), p + Vector3.new(0, K.m(0.2), 0) + side), size = Vector3.new(0.5, 0.4, 5), hp = 90 + ((c.p60 and i == 0) and 30 or 0), duration = 7, solid = false, queryable = true, color = WOOD, material = Enum.Material.Wood })
		r.data.hit = {}
		table.insert(roots, r)
	end
	K.every(0.1, 7, function()
		for _, r in ipairs(roots) do
			if r.alive then
				for _, t in ipairs(K.Hit.box(r.part.CFrame, r.part.Size + Vector3.new(0, 2, 0), K.enemyFilter(c))) do
					if not r.data.hit[t] then
						r.data.hit[t] = true
						K.dmg(c, t, 25, { kind = "field" })
						K.slow(c, t, 0.2, 1, "Roots")
					end
				end
			end
		end
		return true
	end)
end

-- 3 Living Trellis (a climbable frame; openings let narrow shots through)
Kit[3] = function(c)
	local f = c.f
	local pos = c:aimPoint(12)
	local t = grow(c, { name = "Trellis", class = "TrussPart", cf = CFrame.new(pos + Vector3.new(0, K.m(2), 0)), size = Vector3.new(2 / 3, 4, 2 / 3), hp = 220, duration = 8, blocks = false, queryable = true, color = GREEN, material = Enum.Material.Wood })
	local _ = t
	-- allies climb 20% faster near the trellis
	K.zone(c, { pos = pos, radius = 1.5, duration = 8, targets = "allies", includeOwner = true, noVisual = true, tickFn = function(_, list)
		for _, a in ipairs(list) do
			K.speed(a, 0.2, 1.1, "Trellis")
		end
	end })
	if c.p60 then
		grow(c, { name = "TrellisBridge", cf = CFrame.lookAt(pos + Vector3.new(0, K.m(4), 0), pos + Vector3.new(0, K.m(4), 0) + c:dir()) * CFrame.new(0, 0, -K.m(2)), size = Vector3.new(1.2, 0.3, 4), hp = 100, duration = 8, color = WOOD, material = Enum.Material.Wood })
	end
	local __ = f
end

-- 4 Grafting Hand
Kit.requires = {
	[4] = function(c)
		if #structures(c.f) >= 2 then
			return true
		end
		return false, "Needs two Plant structures"
	end,
}
Kit[4] = function(c)
	local f = c.f
	local list = structures(f)
	local aim = c:aimPoint(12)
	table.sort(list, function(a, b)
		return (a.part.Position - f.root.Position).Magnitude < (b.part.Position - f.root.Position).Magnitude
	end)
	local donor = list[1]
	local recipient
	local bd
	for _, o in ipairs(list) do
		if o ~= donor then
			local d = (o.part.Position - aim).Magnitude
			if not bd or d < bd then
				recipient, bd = o, d
			end
		end
	end
	if not recipient then
		return
	end
	local wait = c.p60 and 0 or 0.8
	local t0 = K.now()
	while K.now() - t0 < wait do
		if not (donor.alive and recipient.alive) or not K.Hit.los(donor.part.Position, recipient.part.Position) then
			return
		end
		K.FX.beam(donor.part.Position, recipient.part.Position, 0.25, GREEN, 0.1)
		task.wait(0.1)
	end
	local amount = math.min(120, donor.hp - 1)
	donor.hp -= amount
	S.Objects.damage(donor, 0.001, f)
	recipient.maxHp += amount
	S.Objects.heal(recipient, amount)
end

-- 5 City of Roots (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(18)
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local arches = {}
	for i = -2, 2 do
		local p = K.ground(center + side * K.m(i * 1.8) + dir * K.m((i % 2) * 1.5))
		K.telegraph(c, p, 1.5, 0.7, GREEN)
		task.wait(0.7)
		K.circle(c, p, 1.5, { dmg = 60, color = GREEN })
		local arch = grow(c, { name = "RootArch", cf = CFrame.lookAt(p + Vector3.new(0, K.m(0.8), 0), p + Vector3.new(0, K.m(0.8), 0) + dir) * CFrame.Angles(math.rad(20), 0, 0), size = Vector3.new(1.6, 0.6, 4), hp = 160, duration = 8, isUlt = true, color = WOOD, material = Enum.Material.Wood })
		table.insert(arches, arch)
	end
	if c.unstable then
		local uprooted = 0
		c:recast(8, function(c2)
			local aim = c2:aimPoint(30)
			local best, bd
			for _, a in ipairs(arches) do
				if a.alive then
					local d = (a.part.Position - aim).Magnitude
					if not bd or d < bd then
						best, bd = a, d
					end
				end
			end
			if best then
				local from = best.part.Position
				S.Objects.remove(best, "uprooted")
				K.proj(c2, { origin = from, dir = c2:dir(), range = 12, speed = 14, width = 1.6, ground = true, color = WOOD, size = Vector3.new(2, 2, 2), pierce = true, hit = function(t)
					K.dmg(c2, t, 90)
					return "continue"
				end })
				uprooted += 1
			end
			if uprooted < 2 then
				return "keep"
			end
			return nil
		end)
	end
	local _ = f
end

return Kit
