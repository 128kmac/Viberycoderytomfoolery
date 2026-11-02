-- 17 Cosmic — Orbital patterns and constellation links
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local BLUE = Color3.fromRGB(110, 90, 230)
local RunService = game:GetService("RunService")

local function motes(f)
	return f.state.motes
end
local function ready(f)
	local n = 0
	for _, m in ipairs(motes(f)) do
		if m.ready then
			n += 1
		end
	end
	return n
end
local function show(f)
	K.res(f, "Motes", ready(f), 3, 1)
end
local function spendMote(f, delay)
	for _, m in ipairs(motes(f)) do
		if m.ready then
			m.ready = false
			m.part.Transparency = 1
			local token = {}
			m.token = token
			K.after(5 + (delay or 0) + (f.state.recoveryDelay or 0), function()
				if m.token == token then
					m.ready = true
					m.part.Transparency = 0.1
					show(f)
				end
			end)
			show(f)
			return m
		end
	end
	return nil
end
local function restoreMote(f)
	for _, m in ipairs(motes(f)) do
		if not m.ready then
			m.ready = true
			m.token = nil
			m.part.Transparency = 0.1
			show(f)
			return
		end
	end
end
local function moteWorld(f, i)
	local a = f.state.angle + (i - 1) * math.pi * 2 / 3
	return f.root.Position + Vector3.new(math.cos(a), 0.4, math.sin(a)) * K.m(f.state.radius or 2.5), a
end

-- Passive: Three Satellites
function Kit.passive.init(f)
	f.state.motes = {}
	f.state.angle = 0
	for i = 1, 3 do
		local p = K.FX.base({ shape = Enum.PartType.Ball, size = Vector3.one * 0.9, color = BLUE, transparency = 0.1, name = "Mote" })
		f.state.motes[i] = { part = p, ready = true }
	end
	f.state.conn = RunService.Heartbeat:Connect(function(dt)
		if not K.alive(f) then
			return
		end
		f.state.angle += dt * 1.6
		for i, m in ipairs(f.state.motes) do
			m.part.Position = moteWorld(f, i)
		end
	end)
	show(f)
end
function Kit.passive.cleanup(f)
	if f.state.conn then
		f.state.conn:Disconnect()
	end
	for _, m in ipairs(f.state.motes or {}) do
		m.part:Destroy()
	end
end
function Kit.passive.tick(f)
	local now = K.now()
	if f.state.lastMark and now - f.state.lastMark < 3 then
		return
	end
	-- two motes aligned with an enemy: the enemy lies on the line through two ready motes
	local pts = {}
	for i, m in ipairs(motes(f)) do
		if m.ready then
			table.insert(pts, (moteWorld(f, i)))
		end
	end
	if #pts < 2 then
		return
	end
	for _, t in ipairs(K.enemies(f, 22)) do
		for i = 1, #pts do
			for j = i + 1, #pts do
				local a, b = pts[i], pts[j]
				local dir = K.flat(b - a)
				local rel = Vector3.new(t.root.Position.X - a.X, 0, t.root.Position.Z - a.Z)
				local perp = (rel - dir * rel:Dot(dir)).Magnitude
				if perp < K.m(0.8) and K.los(f, t) then
					f.state.lastMark = now
					K.mark(f, t, "Constellation", 4, { label = "Constellation", color = BLUE })
					return
				end
			end
		end
	end
end

local function needMote(c)
	if ready(c.f) > 0 then
		return true
	end
	return false, "No satellites"
end
Kit.requires = { needMote, needMote, needMote }

-- 1 Satellite Sling
Kit[1] = function(c)
	local f = c.f
	local m = spendMote(f)
	local origin = m and m.part.Position or c:chest()
	local marked
	for _, t in ipairs(K.enemies(f, 26)) do
		if K.has(t, "Constellation") then
			marked = t
		end
	end
	local target = c:target(22)
	local dir = ((target and target.root.Position) or c:aimPoint(22) + Vector3.new(0, 2, 0)) - origin
	K.proj(c, {
		origin = origin,
		dir = dir.Unit,
		range = 22,
		width = 0.6,
		color = BLUE,
		dmg = 80,
		step = function(p)
			if c.p60 and marked and K.alive(marked) and not p.homing and p.traveled >= K.m(19) then
				p.homing = marked
				p.turnRate = 400
			end
		end,
	})
end

-- 2 Orbital Shelter
Kit[2] = function(c)
	local f = c.f
	f.state.radius = 2
	local restored = false
	K.every(0.05, 3, function()
		for i, m in ipairs(motes(f)) do
			if m.ready then
				local pos = moteWorld(f, i)
				for _, p in ipairs(K.enemyProj(c, pos, 1)) do
					if p.kind ~= "ultimate" then
						S.Proj.stop(p, "intercepted")
						spendMote(f)
						K.FX.burst(pos, 2, BLUE, 0.2)
						if c.p60 and not restored then
							restored = true
							K.after(0.2, restoreMote, f)
						end
						break
					end
				end
			end
		end
		return true
	end)
	K.after(3, function()
		f.state.radius = 2.5
	end)
end

-- 3 Constellation Stitch
local function stitches(f)
	local out = {}
	for _, s in ipairs(f.state.stitches or {}) do
		if s.a.alive and s.b.alive and s.expires > K.now() then
			table.insert(out, s)
		end
	end
	f.state.stitches = out
	return out
end
Kit[3] = function(c)
	local f = c.f
	spendMote(f)
	local center = c:aimPoint(18)
	local side = K.flat(c:dir():Cross(Vector3.yAxis))
	local function endpoint(p)
		return K.object(c, { name = "StitchStar", pos = p, size = 0.8, shape = "Ball", hp = 80, duration = 5, solid = false, color = BLUE, material = Enum.Material.Neon })
	end
	local a = endpoint(K.ground(center - side * K.m(3)))
	local b = endpoint(K.ground(center + side * K.m(3)))
	local mid
	if c.p60 then
		mid = endpoint(K.ground(center + c:dir() * K.m(2)))
	end
	local s = { a = a, b = b, mid = mid, expires = K.now() + 5 }
	f.state.stitches = f.state.stitches or {}
	table.insert(f.state.stitches, s)
	local last = {}
	K.every(0.1, 5, function()
		if not (a.alive and b.alive) then
			return false
		end
		local segs = mid and mid.alive and { { a, mid }, { mid, b } } or { { a, b } }
		for _, seg in ipairs(segs) do
			local pa, pb = seg[1].part.Position, seg[2].part.Position
			K.FX.beam(pa, pb, 0.2, BLUE, 0.12)
			for _, h in ipairs(K.Hit.segment(pa, pb, K.m(0.5), K.enemyFilter(c))) do
				local t = h.f
				if not last[t] or K.now() - last[t] >= 1 then
					last[t] = K.now()
					K.dmg(c, t, 55, { kind = "field" })
					if K.has(t, "Constellation") then
						K.slow(c, t, 0.25, 2, "Stitched")
					end
				end
			end
		end
		return true
	end)
end

-- 4 Precession
Kit[4] = function(c)
	local f = c.f
	local sign = (c.p60 and c.mod) and -1 or 1
	local center = f.root.Position
	local hit = {}
	f.stationary += 1
	local ss = stitches(f)
	local starts = {}
	for _, s in ipairs(ss) do
		starts[s] = { a = s.a.part.Position, b = s.b.part.Position }
	end
	local t0 = K.now()
	while K.now() - t0 < 0.6 do
		task.wait(0.03)
		local ang = math.rad(90 * sign * math.min(1, (K.now() - t0) / 0.6))
		local cf = CFrame.Angles(0, ang, 0)
		for _, s in ipairs(ss) do
			if s.a.alive and s.b.alive then
				local pa = center + cf:VectorToWorldSpace(starts[s].a - center)
				local pb = center + cf:VectorToWorldSpace(starts[s].b - center)
				s.a.part.Position, s.b.part.Position = pa, pb
				for _, h in ipairs(K.Hit.segment(pa, pb, K.m(0.6), K.enemyFilter(c))) do
					if not hit[h.f] then
						hit[h.f] = true
						K.dmg(c, h.f, 70)
					end
				end
			end
		end
		-- satellites sweep their orbit too
		f.state.angle += 0.08 * sign
		for i, m in ipairs(motes(f)) do
			if m.ready then
				for _, t in ipairs(K.enemiesIn(f, moteWorld(f, i), 1)) do
					if not hit[t] then
						hit[t] = true
						K.dmg(c, t, 70)
					end
				end
			end
		end
	end
	f.stationary -= 1
end

-- 5 Astral Alignment (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(24)
	local stars = {}
	for i = 0, 2 do
		local a = math.rad(i * 120)
		stars[i + 1] = K.object(c, {
			name = "AstralStar",
			cf = CFrame.new(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(8) + Vector3.new(0, K.m(1.5), 0)),
			size = 1.2,
			shape = "Ball",
			hp = 160,
			duration = 4.5,
			isUlt = true,
			color = Color3.fromRGB(255, 245, 180),
			material = Enum.Material.Neon,
		})
	end
	local totals = {}
	local function fireBeams(dmg, everyone, rot)
		for _, s in ipairs(stars) do
			if s.alive then
				local from = s.part.Position
				local rel = center + Vector3.new(0, K.m(1.5), 0) - from
				local dir = CFrame.Angles(0, math.rad(rot or 0), 0):VectorToWorldSpace(rel).Unit
				local to = from + dir * K.m(16)
				K.FX.beam(from, to, 1.2, Color3.fromRGB(255, 245, 180), 0.35)
				local filter = everyone and function()
					return true
				end or K.enemyFilter(c)
				for _, h in ipairs(K.Hit.segment(from, to, K.m(0.8), filter)) do
					local t = h.f
					local cap = everyone and 370 or 250
					local d = math.min(dmg, cap - (totals[t] or 0))
					if d > 0 then
						totals[t] = (totals[t] or 0) + d
						K.Combat.damage(f, t, d, { cast = c, isUlt = true, fromPos = from, element = "Cosmic" })
					end
				end
			end
		end
	end
	for _, s in ipairs(stars) do
		K.FX.lineTelegraph(s.part.Position, center - s.part.Position, K.m(16), K.m(1.4), 2, Color3.fromRGB(255, 220, 120))
	end
	task.wait(2)
	fireBeams(100, false, 0)
	if c.unstable then
		task.wait(0.8)
		fireBeams(120, true, 35)
		-- Conjunction Failure: empty all satellites and delay their recovery
		f.state.recoveryDelay = 5
		for _ = 1, 3 do
			spendMote(f)
		end
		K.after(10, function()
			f.state.recoveryDelay = 0
		end)
	end
end

return Kit
