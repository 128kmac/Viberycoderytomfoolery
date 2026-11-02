-- 85 Sound — Resonance, surfaces, and physical pressure (visual cues fully represent every mechanic)
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local BLUE = Color3.fromRGB(120, 180, 255)

local function marks(f)
	local now = K.now()
	local out = {}
	for _, m in ipairs(f.state.marks) do
		if m.expires > now then
			table.insert(out, m)
		end
	end
	f.state.marks = out
	return out
end

-- Passive: Resonant Surface
function Kit.passive.init(f)
	f.state.marks = {}
end
function Kit.passive.tick(f)
	K.res(f, "Resonance", #marks(f), 2, 1)
end
local function markSurface(f, pos)
	local list = marks(f)
	if #list >= 2 then
		table.remove(f.state.marks, 1)
	end
	table.insert(f.state.marks, { pos = pos, expires = K.now() + 6 })
	K.FX.ring(pos, 2, BLUE, 6, 0.2)
end
-- a Sound wave reaching a marked surface emits a 35-damage reflected pulse once
local function resonate(c, pos, directHit)
	for i, m in ipairs(marks(c.f)) do
		if (m.pos - pos).Magnitude < K.m(2) then
			table.remove(c.f.state.marks, i)
			K.FX.burst(m.pos, K.m(3), BLUE, 0.3)
			for _, t in ipairs(K.enemiesIn(c, K.ground(m.pos), 3, { sphere = false })) do
				if not directHit[t] then
					K.dmg(c, t, 35, { fromPos = m.pos })
				end
			end
			return true
		end
	end
	return false
end

local function wave(c, opts)
	local direct = {}
	opts.tags = { sound = true }
	opts.color = BLUE
	local userHit = opts.hit
	opts.hit = function(t, p)
		direct[t] = true
		if userHit then
			return userHit(t, p)
		end
	end
	opts.wall = function(pos, _, obj, p)
		if obj and obj.onProjectile then
			return nil
		end
		if not resonate(c, pos, direct) then
			markSurface(c.f, pos)
		end
		return nil
	end
	return K.proj(c, opts)
end

-- 1 Sonic Snap
Kit[1] = function(c)
	wave(c, { range = 14, speed = 40, width = c.p60 and 1.1 or 0.8, shape = "Block", size = Vector3.new(c.p60 and 3.3 or 2.4, 0.3, 0.6), dmg = 70 })
end

-- 2 Tuning Fork
Kit[2] = function(c)
	local f = c.f
	local pos = c:aimPoint(12)
	local facing = c:dir()
	if c.p60 and c.mod then
		facing = K.rotate(facing, 30)
	end
	local fork = K.object(c, { name = "TuningFork", cf = CFrame.lookAt(pos + Vector3.new(0, K.m(1), 0), pos + Vector3.new(0, K.m(1), 0) + facing), size = Vector3.new(0.6, 2, 0.3), hp = 120, duration = 7, color = BLUE, material = Enum.Material.Metal })
	local used = false
	fork.onProjectile = function(obj, p)
		if used or p.owner ~= f or not p.tags.sound then
			return nil
		end
		used = true
		local hit = {}
		local fwd = p.vel.Unit
		for _, a in ipairs({ -60, 60 }) do
			K.proj(c, {
				origin = obj.part.Position + fwd * K.m(0.6),
				dir = K.rotate(fwd, a),
				range = 12,
				speed = 36,
				width = 0.8,
				color = BLUE,
				tags = { soundSplit = true },
				filter = function(t)
					return K.isEnemy(f, t) and not hit[t]
				end,
				hit = function(t)
					hit[t] = true
					K.dmg(c, t, 50)
				end,
			})
		end
		return "stop"
	end
end

-- 3 Pressure Break
Kit[3] = function(c)
	local f = c.f
	K.cone(c, {
		range = c.p60 and 7 or 6,
		angle = 90,
		color = BLUE,
		hit = function(t)
			local before = t.guard
			K.dmg(c, t, 90, { guardDmg = 35 })
			if t.guarding == false and before > 0 and t.guard <= 0 then
				K.push(c, t, K.flat(t.root.Position - f.root.Position), 2)
			end
		end,
	})
end

-- 4 Quiet Pocket (audio only; every visual telegraph is unchanged)
Kit[4] = function(c)
	local f = c.f
	local pos = c:aimPoint(14)
	K.FX.ring(pos, K.m(4), BLUE, 5, 0.3)
	local rippled = {}
	K.zone(c, {
		pos = pos,
		radius = 4,
		duration = 5,
		targets = "all",
		color = BLUE,
		transparency = 0.9,
		tickFn = function(_, list)
			for _, t in ipairs(list) do
				K.buff(t, "Muffled", { duration = 1.1, label = "Muffled" })
			end
		end,
	})
	if c.p60 then
		K.every(0.05, 5, function()
			for _, p in pairs(S.Proj.list) do
				if p.alive and not rippled[p] and math.abs(K.flatDist(p.pos, pos) - 4) < 0.6 then
					rippled[p] = true
					K.FX.burst(p.pos, 2, Color3.fromRGB(255, 255, 255), 0.2)
				end
			end
			return true
		end)
	end
	local _ = f
end

-- 5 Resonance Cathedral (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(18)
	local pillars = {}
	for i = 0, 3 do
		local a = math.rad(i * 90 + 45)
		pillars[i + 1] = K.object(c, { name = "ResonancePillar", pos = K.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(7)), size = Vector3.new(0.8, 3, 0.8), hp = 120, duration = 6, isUlt = true, color = BLUE, material = Enum.Material.Metal })
	end
	local function path(from, to, dmg, preview, hitSet)
		if not (from.alive and to.alive) then
			return
		end
		local pa, pb = from.part.Position + Vector3.new(0, 1.5, 0), to.part.Position + Vector3.new(0, 1.5, 0)
		if preview then
			K.FX.beam(pa, pb, 0.3, Color3.fromRGB(255, 120, 120), 0.6, 0.5)
		end
		return function()
			if not (from.alive and to.alive) then
				return
			end
			K.FX.beam(pa, pb, 0.8, BLUE, 0.2)
			for _, h in ipairs(K.Hit.segment(pa, pb, K.m(0.8), K.enemyFilter(c))) do
				if not hitSet[h.f] then
					hitSet[h.f] = true
					K.dmg(c, h.f, dmg, { fromPos = pa })
				end
			end
		end
	end
	for w = 1, 3 do
		local hitSet = {}
		local fires = {}
		for i = 1, 4 do
			local fn = path(pillars[i], pillars[i % 4 + 1], 90, true, hitSet)
			if fn then
				table.insert(fires, fn)
			end
		end
		task.wait(0.6)
		for _, fn in ipairs(fires) do
			fn()
		end
		task.wait(0.4)
		local _ = w
	end
	if c.unstable then
		local hitSet = {}
		local fires = {}
		for i = 1, 4 do
			for j = i + 1, 4 do
				local fn = path(pillars[i], pillars[j], 100, true, hitSet)
				if fn then
					table.insert(fires, fn)
				end
			end
		end
		task.wait(0.6)
		for _, fn in ipairs(fires) do
			fn()
		end
		for _, p in ipairs(pillars) do
			if p.alive then
				S.Objects.remove(p, "shattered")
			end
		end
	end
	local _ = f
end

return Kit
