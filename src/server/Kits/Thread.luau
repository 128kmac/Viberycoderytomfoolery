-- 91 Thread — Tensioned lines and vulnerable connections (every endpoint is visible and attackable)
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local SILK = Color3.fromRGB(240, 220, 200)

local function endpoint(c, pos, hp, duration, isUlt)
	return K.object(c, { name = "ThreadEnd", pos = pos, size = 0.6, shape = "Ball", hp = hp or 70, duration = duration, solid = false, color = SILK, material = Enum.Material.Fabric, isUlt = isUlt, noCap = true })
end

local function threads(f, includeUlt)
	local out = {}
	for _, t in ipairs(f.state.threads) do
		if t.alive and (includeUlt or not t.isUlt) then
			table.insert(out, t)
		end
	end
	f.state.threads = out
	return out
end

local function endPos(e)
	if e.fighter then
		return e.fighter.root.Position + Vector3.new(0, 0.5, 0)
	end
	return e.obj.part.Position
end
local function taut(t)
	return (endPos(t.a) - endPos(t.b)).Magnitude > K.m(5)
end
local function cut(t)
	t.alive = false
	for _, e in ipairs({ t.a, t.b }) do
		if e.obj and e.obj.alive then
			S.Objects.remove(e.obj, "cut")
		end
	end
	if t.vis then
		t.vis:Destroy()
	end
end

-- Passive: Tension Limit — three threads; Taut beyond 5 m; breaks harmlessly beyond 12 m
local function makeThread(c, a, b, duration, opts)
	local f = c.f
	opts = opts or {}
	if not opts.isUlt then
		local list = threads(f)
		if #list >= 3 then
			cut(list[1])
		end
	end
	local t = { a = a, b = b, alive = true, isUlt = opts.isUlt, expires = K.now() + duration, crossed = {} }
	table.insert(f.state.threads, t)
	return t
end
function Kit.passive.init(f)
	f.state.threads = {}
end
function Kit.passive.tick(f)
	for _, t in ipairs(threads(f, true)) do
		local ok = K.now() < t.expires
		for _, e in ipairs({ t.a, t.b }) do
			if e.obj and not e.obj.alive then
				ok = false
			end
			if e.fighter and not K.alive(e.fighter) then
				ok = false
			end
		end
		if ok and (endPos(t.a) - endPos(t.b)).Magnitude > K.m(12) then
			ok = false
		end
		if not ok then
			cut(t)
		else
			if t.vis then
				t.vis:Destroy()
			end
			t.vis = K.FX.beam(endPos(t.a), endPos(t.b), taut(t) and 0.12 or 0.06, taut(t) and Color3.fromRGB(255, 255, 255) or SILK, 0.2, 0.2)
		end
	end
	K.res(f, "Threads", #threads(f), 3, 1)
end

-- crossing Taut lines (Anchor Weave)
local function crossCheck(c, t, dmg)
	if not t.alive or not taut(t) then
		return
	end
	for _, h in ipairs(K.Hit.segment(endPos(t.a), endPos(t.b), K.m(0.3), K.enemyFilter(c))) do
		if not t.crossed[h.f] then
			t.crossed[h.f] = true
			K.dmg(c, h.f, dmg, { kind = "field" })
			K.slow(c, h.f, 0.2, 1, "Thread")
		end
	end
end

-- 1 Needle Cast — a terrain hit anchors a thread to your hand
Kit[1] = function(c)
	local f = c.f
	local pierced = false
	K.proj(c, {
		range = 16,
		width = 0.2,
		shape = "Block",
		size = Vector3.new(0.15, 0.15, 1),
		color = SILK,
		dmg = 65,
		wall = function(pos, _, obj)
			if c.p60 and obj and obj.hp < 40 and not pierced then
				pierced = true
				S.Objects.destroy(obj, f)
				return "pass"
			end
			local anchor = endpoint(c, pos, 70, 5)
			local t = makeThread(c, { obj = anchor }, { fighter = f }, 5)
			t.handHeld = true
			return nil
		end,
	})
end

-- 2 Anchor Weave
Kit[2] = function(c)
	local center = c:aimPoint(14)
	local side = K.flat(c:dir():Cross(Vector3.yAxis))
	local hp = 70 + (c.p60 and 30 or 0)
	local a = endpoint(c, K.ground(center - side * K.m(3.5)) + Vector3.new(0, K.m(0.6), 0), hp, 7)
	local b = endpoint(c, K.ground(center + side * K.m(3.5)) + Vector3.new(0, K.m(0.6), 0), hp, 7)
	local t = makeThread(c, { obj = a }, { obj = b }, 7)
	K.every(0.05, 7, function()
		if not t.alive then
			return false
		end
		crossCheck(c, t, 55)
		return true
	end)
end

-- 3 Reel Step
Kit.requires = {
	[3] = function(c)
		for _, t in ipairs(threads(c.f)) do
			if t.handHeld then
				return true
			end
		end
		return false, "No hand-held thread"
	end,
	[4] = function(c)
		for _, t in ipairs(threads(c.f)) do
			if taut(t) then
				return true
			end
		end
		return false, "No Taut thread"
	end,
}
Kit[3] = function(c)
	local f = c.f
	local line
	for _, t in ipairs(threads(f)) do
		if t.handHeld then
			line = t
		end
	end
	if not line then
		return
	end
	local anchor = endPos(line.a)
	local d = anchor - f.root.Position
	local dist = math.min(7, d.Magnitude / K.M - 1)
	local stopped = false
	if c.p60 then
		c:recast(0.6, function()
			stopped = true
			local lv = f.root:FindFirstChild("EBDisplace")
			if lv then
				lv:Destroy()
			end
			line.expires = math.max(line.expires, K.now() + 1)
		end)
	end
	K.dash(c, d.Unit, dist, 0.35, { allowY = true })
	if not stopped then
		cut(line)
	end
end

-- 4 Scissor Release
Kit[4] = function(c)
	local f = c.f
	local n = 0
	for _, t in ipairs(threads(f)) do
		if n >= 2 then
			break
		end
		if taut(t) then
			n += 1
			local pa, pb = endPos(t.a), endPos(t.b)
			K.FX.beam(pa, pb, 0.5, Color3.fromRGB(255, 80, 80), 0.25)
			local real = false
			for _, h in ipairs(K.Hit.segment(pa, pb, K.m(0.5), K.enemyFilter(c))) do
				K.dmg(c, h.f, 90, { fromPos = pa })
				if K.isReal(h.f) then
					real = true
				end
			end
			if c.p60 and real then
				K.addEnergy(f, 6)
			end
			cut(t)
		end
	end
end

-- 5 Loom of the Arena (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(18)
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local lines = {}
	for i = -1, 1 do
		-- three lines along the aim and three across it: a marked lattice
		local a = endpoint(c, K.ground(center + side * K.m(i * 2.5) - dir * K.m(4)) + Vector3.new(0, K.m(0.8), 0), 90, 6, true)
		local b = endpoint(c, K.ground(center + side * K.m(i * 2.5) + dir * K.m(4)) + Vector3.new(0, K.m(0.8), 0), 90, 6, true)
		table.insert(lines, makeThread(c, { obj = a }, { obj = b }, 6, { isUlt = true }))
		local a2 = endpoint(c, K.ground(center + dir * K.m(i * 2.5) - side * K.m(4)) + Vector3.new(0, K.m(0.8), 0), 90, 6, true)
		local b2 = endpoint(c, K.ground(center + dir * K.m(i * 2.5) + side * K.m(4)) + Vector3.new(0, K.m(0.8), 0), 90, 6, true)
		table.insert(lines, makeThread(c, { obj = a2 }, { obj = b2 }, 6, { isUlt = true }))
	end
	for i, t in ipairs(lines) do
		K.FX.text((endPos(t.a) + endPos(t.b)) / 2 + Vector3.new(0, 1.5, 0), tostring(i), SILK, 6, 22)
	end
	local totals = {}
	local function snap(t, cc)
		if not t.alive then
			return
		end
		local pa, pb = endPos(t.a), endPos(t.b)
		K.FX.beam(pa, pb, 0.4, Color3.fromRGB(255, 80, 80), 0.6, 0.4)
		task.wait(0.6)
		if not t.alive then
			return
		end
		for _, h in ipairs(K.Hit.segment(pa, pb, K.m(0.6), K.enemyFilter(cc))) do
			if (totals[h.f] or 0) < 3 then
				totals[h.f] = (totals[h.f] or 0) + 1
				K.dmg(cc, h.f, 90, { fromPos = pa })
			end
		end
		cut(t)
	end
	if c.unstable then
		for _, t in ipairs(lines) do
			snap(t, c)
		end
		for _, t in ipairs(threads(f, true)) do
			cut(t)
		end
		return
	end
	local snapped = 0
	c:recast(6, function(c2)
		local aim = c2:aimPoint(30)
		local best, bd
		for _, t in ipairs(lines) do
			if t.alive then
				local d = K.Hit.pointSeg(aim, endPos(t.a), endPos(t.b))
				if not bd or d < bd then
					best, bd = t, d
				end
			end
		end
		if best then
			K.spawn(snap, best, c2)
			snapped += 1
		end
		if snapped < 3 then
			return "keep"
		end
		return nil
	end)
end

return Kit
