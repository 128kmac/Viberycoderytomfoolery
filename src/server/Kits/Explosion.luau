-- 34 Explosion — Placed charges and blast timing
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local ORANGE = Color3.fromRGB(255, 140, 30)

local function charges(f, kind)
	local out = {}
	for _, o in ipairs(K.owned(f)) do
		if o.data.charge and (kind == nil or o.data.charge == kind) then
			table.insert(out, o)
		end
	end
	table.sort(out, function(a, b)
		return a.created < b.created
	end)
	return out
end
local function show(f)
	K.res(f, "Charges", #charges(f, "pop"), 3, 1)
end

local function armed(o)
	return K.now() >= o.data.armedAt
end

local detonate
detonate = function(c, o, opts)
	opts = opts or {}
	if not o.alive or not armed(o) then
		return false
	end
	local f = c.f
	local pos = o.part.Position
	local refund = not opts.chain and K.now() - o.data.armedAt >= 1
	S.Objects.remove(o, "detonated")
	if o.data.charge == "breach" then
		K.cone(c, { origin = pos, dir = o.data.dir, range = 6, angle = 60, dmg = 140, color = ORANGE })
		for _, ob in ipairs(K.enemyObjects(c, pos + o.data.dir * K.m(3), 3)) do
			K.objDmg(c, ob, 260)
		end
	else
		local dmg = opts.dmg or 85
		local list = opts.everyone and K.Hit.cylinder(pos, K.m(2.5), function()
			return true
		end) or K.enemiesIn(c, pos, 2.5)
		K.FX.burst(pos, K.m(2.5), ORANGE, 0.35)
		for _, t in ipairs(list) do
			if opts.totals then
				local d = math.min(dmg, opts.cap - (opts.totals[t] or 0))
				if d > 0 then
					opts.totals[t] = (opts.totals[t] or 0) + d
					K.Combat.damage(f, t, d, { cast = c, isUlt = c.isUlt, fromPos = pos, element = "Explosion" })
				end
			else
				K.dmg(c, t, dmg, { fromPos = pos })
			end
			if o.data.push then
				K.knock(c, t, pos, o.data.push)
			end
		end
		for _, ob in ipairs(K.enemyObjects(c, pos, 2.5)) do
			K.objDmg(c, ob, dmg)
		end
	end
	if refund then
		K.addEnergy(f, 5)
	end
	-- linked sympathy: the partner detonates 0.7 s later
	local link = o.data.link
	if link and link.alive and not opts.chain then
		K.telegraph(c, K.ground(link.part.Position), 2.5, 0.7, ORANGE)
		link.data.pendingChain = true
		K.after(0.7, function()
			if link.alive and link.data.pendingChain then
				detonate(c, link, { chain = true })
			end
		end)
	end
	show(f)
	return true
end

local function placeCharge(c, pos, kind, extra)
	local f = c.f
	if kind == "pop" then
		local list = charges(f, "pop")
		if #list >= 3 then
			S.Objects.remove(list[1], "replaced")
		end
	end
	local o = K.object(c, {
		name = "Charge",
		pos = pos,
		size = Vector3.new(0.8, 0.5, 0.8),
		hp = (extra and extra.hp) or 40,
		duration = 8,
		solid = false,
		color = ORANGE,
		material = Enum.Material.Neon,
		isUlt = extra and extra.isUlt,
		noCap = true,
	})
	o.data.charge = kind
	o.data.armedAt = K.now() + 0.6
	if extra then
		for k, v in pairs(extra) do
			o.data[k] = v
		end
	end
	show(f)
	return o
end

-- Passive: Fuse Discipline
function Kit.passive.init(f)
	show(f)
end

-- 1 Pop Charge (recast detonates armed charges)
Kit[1] = function(c)
	K.lob(c, {
		range = 18,
		speed = 20,
		width = 0.5,
		color = ORANGE,
		land = function(pos)
			placeCharge(c, pos, "pop", { push = c.p60 and 2 or 1 })
		end,
	})
	c:recast(8, function(c2)
		local any = false
		for _, o in ipairs(charges(c.f, "pop")) do
			if armed(o) then
				any = detonate(c2, o) or any
			end
		end
		if not any then
			return "keep"
		end
		return nil
	end)
end

-- 2 Blast Hop
Kit[2] = function(c)
	local f = c.f
	K.circle(c, c:feet(), 2, { dmg = 55, color = ORANGE })
	local dir = Vector3.yAxis
	if c.p60 then
		dir = (Vector3.yAxis + c:dir() * math.tan(math.rad(30))).Unit
	end
	S.Fighter.displace(f, dir, K.m(5), 0.35)
	c.recovery = 0.2
end

-- 3 Shaped Breach
Kit[3] = function(c)
	local pos = c:aimPoint(12)
	local dir = c:dir()
	local o = placeCharge(c, pos, "breach", { dir = dir, hp = 60 })
	o.expires = K.now() + 6
	local tele = K.FX.cone(pos + Vector3.new(0, 0.3, 0), dir, K.m(6), 60, ORANGE, 0.6)
	local _ = tele
	c:recast(6, function(c2)
		if not o.alive then
			return nil
		end
		if c2.p60 and c2.mod and not o.data.rotated then
			o.data.rotated = true
			o.data.dir = c2:dir()
			K.FX.cone(pos + Vector3.new(0, 0.3, 0), o.data.dir, K.m(6), 60, ORANGE, 0.4)
			return "keep"
		end
		if not detonate(c2, o) then
			return "keep"
		end
		return nil
	end)
end

-- 4 Delayed Sympathy
Kit.requires = {
	[4] = function(c)
		local free = 0
		for _, o in ipairs(charges(c.f)) do
			if not o.data.link then
				free += 1
			end
		end
		if free >= 2 then
			return true
		end
		return false, "Needs two unlinked charges"
	end,
}
Kit[4] = function(c)
	local aim = c:aimPoint(20)
	local list = {}
	for _, o in ipairs(charges(c.f)) do
		if not o.data.link then
			table.insert(list, o)
		end
	end
	table.sort(list, function(a, b)
		return (a.part.Position - aim).Magnitude < (b.part.Position - aim).Magnitude
	end)
	local a, b = list[1], list[2]
	if not (a and b) then
		return
	end
	a.data.link, b.data.link = b, a
	K.FX.beam(a.part.Position, b.part.Position, 0.2, ORANGE, 1.5)
	if c.p60 then
		c:recast(8, function()
			for _, o in ipairs({ a, b }) do
				if o.alive then
					o.data.pendingChain = false
				end
			end
		end)
	end
end

-- 5 Demolition Symphony (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(22)
	local ring = {}
	for i = 0, 5 do
		local a = math.rad(i * 60)
		ring[i + 1] = placeCharge(c, K.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(8)), "sym", { hp = 70, isUlt = true })
		ring[i + 1].data.armedAt = K.now()
	end
	local totals = {}
	if c.unstable then
		task.wait(1)
		for _, o in ipairs(ring) do
			if o.alive then
				K.telegraph(c, K.ground(o.part.Position), 2.5, 0.6, Color3.fromRGB(255, 60, 40))
			end
		end
		task.wait(0.6)
		for _, o in ipairs(ring) do
			detonate(c, o, { chain = true, dmg = 80, everyone = true, totals = totals, cap = 360 })
		end
		return
	end
	-- three pairs over 4 seconds; the pair nearest the aim fires first
	local order = { { 1, 4 }, { 2, 5 }, { 3, 6 } }
	local aim = c:aimPoint(30)
	table.sort(order, function(p, q)
		local dp = math.min((ring[p[1]].part.Position - aim).Magnitude, (ring[p[2]].part.Position - aim).Magnitude)
		local dq = math.min((ring[q[1]].part.Position - aim).Magnitude, (ring[q[2]].part.Position - aim).Magnitude)
		return dp < dq
	end)
	for _, pair in ipairs(order) do
		for _, i in ipairs(pair) do
			if ring[i].alive then
				K.telegraph(c, K.ground(ring[i].part.Position), 2.5, 0.5, ORANGE)
			end
		end
		task.wait(0.5)
		for _, i in ipairs(pair) do
			detonate(c, ring[i], { chain = true, dmg = 80, totals = totals, cap = 300 })
		end
		task.wait(0.8)
	end
	local _ = f
end

return Kit
