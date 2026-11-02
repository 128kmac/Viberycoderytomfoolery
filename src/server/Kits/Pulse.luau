-- 72 Pulse — Concentric waves and spacing intervals
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local CYAN = Color3.fromRGB(0, 200, 255)

local function echoes(f)
	local now = K.now()
	local out = {}
	for _, e in ipairs(f.state.echoes) do
		if e > now then
			table.insert(out, e)
		end
	end
	f.state.echoes = out
	return #out
end
local function addEcho(f)
	if echoes(f) < 3 then
		table.insert(f.state.echoes, K.now() + 7)
	end
end
local function spendEchoes(f, n)
	local have = echoes(f)
	local take = math.min(have, n)
	for _ = 1, take do
		table.remove(f.state.echoes, 1)
	end
	return take
end

-- Passive: Wave Memory
function Kit.passive.init(f)
	f.state.echoes = {}
end
function Kit.passive.tick(f)
	K.res(f, "Echo", echoes(f), 3, 1)
end

-- expanding/contracting ring wave between radii (metres); each target hit once
local function wave(c, center, r0, r1, time, dmg, outerBand, hitSet)
	local f = c.f
	hitSet = hitSet or {}
	local steps = math.max(4, math.floor(time / 0.05))
	for i = 1, steps do
		local r = r0 + (r1 - r0) * (i / steps)
		local inner, outer = math.max(0, r - 0.6), r + 0.6
		K.FX.ring(center, K.m(math.max(0.3, r)), CYAN, 0.08, 0.3)
		for _, t in ipairs(K.enemiesRing(c, center, inner, outer)) do
			if not hitSet[t] and K.Hit.los(center + Vector3.new(0, 1.5, 0), t.root.Position) then
				hitSet[t] = true
				K.dmg(c, t, dmg, { fromPos = center })
				if outerBand and r >= outerBand and not c.data.echoed and c.slot <= 4 then
					c.data.echoed = true
					addEcho(f)
				end
			end
		end
		task.wait(time / steps)
	end
	return hitSet
end

-- 1 Expanding Ring
Kit[1] = function(c)
	local maxR = c.p60 and 10 or 8
	wave(c, c:feet(), 1, maxR, 0.8 * (maxR - 1) / 7, 75, maxR - 1)
end

-- 2 Compression Point
Kit[2] = function(c)
	local pos = c:aimPoint(16)
	K.telegraph(c, pos, 2, 0.8, CYAN)
	if c.p60 then
		K.FX.ring(pos, K.m(0.5), Color3.fromRGB(120, 255, 140), 0.8, 0.15)
	end
	task.wait(0.8)
	local hit = {}
	for _, t in ipairs(K.enemiesIn(c, pos, 2)) do
		hit[t] = true
		local outer = K.flatDist(t, pos) >= 1
		K.dmg(c, t, 85, { fromPos = pos })
		K.pull(c, t, pos, 1.5)
		if outer and not c.data.echoed then
			c.data.echoed = true
			addEcho(c.f)
		end
	end
	K.FX.burst(pos, K.m(2), CYAN, 0.3)
end

-- 3 Counterpulse
Kit[3] = function(c)
	local f = c.f
	local done = false
	local shell = K.FX.sphere(f.root.Position, K.m(3), CYAN, c.p60 and 0.5 or 0.35, 0.8)
	local _ = shell
	K.every(0.02, c.p60 and 0.5 or 0.35, function()
		if done then
			return false
		end
		for _, p in ipairs(K.enemyProj(c, f.root.Position, 3)) do
			if p.kind ~= "ultimate" then
				done = true
				local back = -p.vel.Unit
				S.Proj.stop(p, "counterpulse")
				K.beam(c, { origin = f.root.Position, dir = back, length = 12, width = 1.2, dmg = 60, color = CYAN, pierce = true })
				return false
			end
		end
		return true
	end)
end

-- 4 Double Interval
Kit[4] = function(c)
	local f = c.f
	local spent = spendEchoes(f, 2)
	local radius = 6 + spent
	local center = c:feet()
	wave(c, center, 1, radius, 0.6, 65, nil, {})
	local delay = 0.9
	if c.p60 and c.mod then
		delay += 0.4
		K.FX.ring(center, K.m(radius), Color3.fromRGB(255, 255, 255), 0.4, 0.3)
	end
	task.wait(delay)
	wave(c, center, radius, 0.5, 0.6, 65, nil, {})
end

-- 5 Heart of the Battlefield (ultimate)
Kit[5] = function(c)
	local center = c:aimPoint(16)
	local dirs = { "out", "in", "out", "in" }
	for i, d in ipairs(dirs) do
		K.FX.text(center + Vector3.new(0, 3, 0), d == "out" and ">> OUT >>" or "<< IN <<", CYAN, 0.9, 28)
		if c.unstable and i == 3 then
			-- relocate the centre up to 3 m; damage is suspended during the 0.8 s preview
			local newCenter = K.ground(center + K.flat(c:aimPoint(30) - center) * math.min(K.m(3), (c:aimPoint(30) - center).Magnitude))
			K.telegraph(c, newCenter, 8, 0.8, CYAN)
			task.wait(0.8)
			center = newCenter
		end
		if d == "out" then
			wave(c, center, 1, 8, 0.8, 75, nil, {})
		else
			wave(c, center, 8, 0.5, 0.8, 75, nil, {})
		end
		task.wait(0.2)
	end
end

return Kit
