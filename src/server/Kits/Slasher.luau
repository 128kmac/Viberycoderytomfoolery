-- 81 Slasher — Cut angles and exposed recovery
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local RED = Color3.fromRGB(200, 0, 40)

-- Passive: Crosscut — a horizontal and a vertical hit on the same enemy within 4 s primes 35 bonus
function Kit.passive.init(f)
	f.state.cuts = {}
	f.state.primed = {}
end
function Kit.passive.beforeDeal(f, target, info)
	local c = info.opts.cast
	if c and f.state.primed[target] and info.kind == "direct" and not (c.isUlt and f.state.ultCrossUsed) then
		f.state.primed[target] = nil
		info.amount += 35
		if c.isUlt then
			f.state.ultCrossUsed = true
		end
		K.FX.burst(target.root.Position, 3, RED, 0.25)
	end
end
function Kit.passive.dealt(f, target, info)
	local c = info.opts.cast
	local angle = info.opts.angle or (c and c.data.angle)
	if not angle then
		return
	end
	local rec = f.state.cuts[target] or {}
	f.state.cuts[target] = rec
	rec[angle] = K.now()
	if rec.h and rec.v and math.abs(rec.h - rec.v) <= 4 then
		f.state.cuts[target] = nil
		f.state.primed[target] = true
		K.mark(f, target, "Crosscut", 4, { label = "Crosscut primed", color = RED })
	end
end

-- 1 Horizon Edge (horizontal)
Kit[1] = function(c)
	c.data.angle = "h"
	K.melee(c, { range = c.p60 and 6 or 5, arc = 100, dmg = 75, color = RED })
end

-- 2 Falling Line (vertical)
Kit[2] = function(c)
	c.data.angle = "v"
	local origin = c:feet()
	local dir = c:dir()
	local res = K.Hit.raycast(c:chest(), dir * K.m(7))
	local len = res and math.max(1, (res.Position - c:chest()).Magnitude / K.M) or 7
	K.telegraphLine(c, origin, dir, len, 1, 0.25, RED)
	task.wait(0.25)
	K.line(c, origin, dir, len, 1, { dmg = 100, guardDmg = c.p60 and 20 or 0, color = RED })
end

-- 3 Draw and Pass (horizontal)
Kit[3] = function(c)
	c.data.angle = "h"
	local cut = false
	K.dash(c, c:dir(), 6, 0.25, {
		passWidth = 3,
		onPass = function(t)
			if not cut then
				cut = true
				K.dmg(c, t, 70, { melee = true })
			end
		end,
	})
end

-- 4 Guard Splitter (vertical)
Kit[4] = function(c)
	local f = c.f
	c.data.angle = "v"
	local hits = K.melee(c, {
		range = 4,
		arc = 60,
		color = RED,
		hit = function(t)
			local before = t.guard
			K.dmg(c, t, 120, { melee = true, guardDmg = 60 })
			if c.p60 and before > 0 and t.guard <= 0 then
				K.addEnergy(f, 8)
			end
		end,
	})
	if #hits == 0 then
		c.recovery = 0.8
	end
end

-- 5 Thirteen Visible Cuts (ultimate)
Kit[5] = function(c)
	local f = c.f
	f.state.ultCrossUsed = false
	local center = c:aimPoint(14)
	local rng = Random.new()
	-- thirteen thin cosmetic strokes (never in active-hit warning colours)
	for _ = 1, 13 do
		local a = rng:NextNumber(0, 360)
		local d = K.rotate(Vector3.new(1, 0, 0), a)
		local mid = center + K.rotate(Vector3.new(1, 0, 0), rng:NextNumber(0, 360)) * K.m(rng:NextNumber(0, 3))
		K.FX.beam(mid - d * K.m(3) + Vector3.new(0, 0.3, 0), mid + d * K.m(3) + Vector3.new(0, 0.3, 0), 0.08, Color3.fromRGB(120, 120, 130), 4, 0.5)
	end
	local base = c:dir()
	local cuts = {
		{ dirs = { K.rotate(base, 90) }, angle = "h" },
		{ dirs = { base }, angle = "v" },
		{ dirs = { K.rotate(base, 45) }, angle = "d" },
		{ dirs = { K.rotate(base, 45), K.rotate(base, -45) }, angle = "x" },
	}
	if c.unstable then
		f.noDodge = true
	end
	for i, cut in ipairs(cuts) do
		local warn = 0.6
		if i == 4 and c.unstable then
			warn += 0.5
			local rot = (K.flat(c:aimPoint(30) - center):Dot(K.flat(base:Cross(Vector3.yAxis))) >= 0) and 45 or -45
			cut.dirs = { K.rotate(cut.dirs[1], rot), K.rotate(cut.dirs[2], rot) }
		end
		K.FX.text(center + Vector3.new(0, 3, 0), tostring(i), RED, warn, 30)
		for _, d in ipairs(cut.dirs) do
			K.telegraphLine(c, center - d * K.m(6), d, 12, 1.2, warn, RED)
		end
		task.wait(warn)
		local hit = {}
		for _, d in ipairs(cut.dirs) do
			for _, t in ipairs(K.enemiesLine(c, center - d * K.m(6), d, 12, 1.2)) do
				if not hit[t] then
					hit[t] = true
					K.dmg(c, t, 75, { fromPos = center, angle = (cut.angle == "h" or cut.angle == "v") and cut.angle or nil })
				end
			end
		end
	end
	f.noDodge = nil
end

return Kit
