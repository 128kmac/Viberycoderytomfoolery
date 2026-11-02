-- 63 Nightmare — Dread buildup and threatening false shapes
-- In-world fear only: no screen obstruction, forced camera changes or invisible walls.
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local DREAD = Color3.fromRGB(110, 0, 80)

local function dread(f, t, n)
	if t.isSummon then
		return
	end
	K.debuff(f, t, "Dread", { duration = 6, stacks = n or 1, max = 3, category = "curse", label = "Dread" })
end

-- Passive: Dread Gauge — at three stacks the next hit deals 30 bonus and consumes them
function Kit.passive.beforeDeal(f, target, info)
	if info.kind == "direct" and K.stacks(target, "Dread") >= 3 and not info.opts.noDreadBonus then
		info.amount += 30
		K.unmark(target, "Dread")
		info.opts.consumedDread = true
	end
end
function Kit.passive.dealt(f, target, info)
	if info.kind == "direct" and info.opts.cast and not info.opts.consumedDread and not info.opts.noDread then
		dread(f, target, 1)
	end
end

-- 1 Under the Bed
Kit[1] = function(c)
	local start = c:feet()
	local dir = c:dir()
	local target = c:aimPoint(18)
	local function ripple(real)
		K.proj(c, {
			origin = start + Vector3.new(0, 0.5, 0),
			dir = K.flat(target - start),
			range = 18,
			speed = 16,
			width = 1,
			ground = true,
			shape = "Block",
			size = Vector3.new(1.2, 0.2, 1.2),
			color = real and DREAD or Color3.fromRGB(60, 40, 60),
			filter = (not real) and function()
				return false
			end or nil,
			dmg = real and 75 or nil,
			finish = (not real) and function(pos)
				K.FX.ring(K.ground(pos), K.m(1), Color3.fromRGB(200, 200, 200), 0.6, 0.2) -- hollow outline
			end or nil,
		})
	end
	ripple(true)
	if c.p60 then
		target = K.ground(target + K.flat(dir:Cross(Vector3.yAxis)) * K.m(3))
		ripple(false)
	end
end

-- 2 Watching Eyes
Kit[2] = function(c)
	local f = c.f
	local start = c:aimPoint(15)
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local eyes = {}
	for i = -1, 1 do
		local p = K.ground(start + side * K.m(i * 3)) + Vector3.new(0, K.m(1.2), 0)
		local e = K.object(c, { name = "WatchingEye", cf = CFrame.lookAt(p, p - dir), size = Vector3.new(0.8, 0.8, 0.4), hp = 50, duration = 7, color = Color3.fromRGB(255, 240, 200), material = Enum.Material.Neon })
		e.data.look = -dir
		e.data.watch = {}
		e.data.given = {}
		table.insert(eyes, e)
	end
	if c.p60 then
		c:recast(7, function()
			for _, e in ipairs(eyes) do
				if e.alive then
					e.data.look = K.rotate(e.data.look, 45)
					break
				end
			end
		end)
	end
	K.every(0.1, 7, function()
		for _, e in ipairs(eyes) do
			if e.alive then
				for _, t in ipairs(K.enemiesCone(f, 12, 60, e.part.Position, e.data.look, true)) do
					e.data.watch[t] = (e.data.watch[t] or 0) + 0.1
					if e.data.watch[t] >= 1 and not e.data.given[t] then
						e.data.given[t] = true
						dread(f, t, 1)
					end
				end
			end
		end
		return true
	end)
end

-- 3 False Awakening
Kit[3] = function(c)
	local f = c.f
	local cf = f.root.CFrame
	local double = K.object(c, { name = "DreamDouble", cf = cf, size = Vector3.new(1.4, 4.4, 1), hp = c.p60 and 100 or 60, duration = 2, solid = false, color = DREAD, transparency = 1, noLabel = true })
	local model = K.decoyModel(f, cf, Color3.fromRGB(60, 20, 50))
	game:GetService("Debris"):AddItem(model, 2)
	K.dash(c, c:dir(), 5, 0.2)
	K.after(0.5, function()
		if double.alive then
			K.FX.highlight(model, Color3.fromRGB(255, 255, 255), 0.3, 0.9) -- solid outline before the lunge
		end
	end)
	K.after(0.8, function()
		if not double.alive then
			return
		end
		local t = K.nearestEnemy(f, 8, cf.Position)
		local d = t and K.flat(t.root.Position - cf.Position) or K.flat(cf.LookVector)
		local from = cf.Position
		local hit = false
		for s = 1, 8 do
			local p = from + d * K.m(4) * (s / 8)
			model:PivotTo(CFrame.lookAt(p, p + d))
			if not hit then
				for _, v in ipairs(K.enemiesIn(f, K.ground(p), 1.2)) do
					hit = true
					K.dmg(c, v, 95, { fromPos = p })
					break
				end
			end
			task.wait(0.03)
		end
		S.Objects.remove(double, "lunged")
	end)
end

-- 4 Weight of Dread
Kit.requires = {
	[4] = function(c)
		local t = c:target(12, { filter = function(t)
			return K.has(t, "Dread")
		end })
		if t then
			return true
		end
		return false, "Needs a Dread-marked target"
	end,
}
Kit[4] = function(c)
	local f = c.f
	local t = c:target(12, { filter = function(t)
		return K.has(t, "Dread")
	end })
	if not t then
		return
	end
	-- the tether must hold line of sight through the windup (already elapsed); verify now
	if not K.los(f, t) then
		return
	end
	K.FX.beam(c:chest(), t.root.Position, 0.25, DREAD, 0.3)
	local n = K.stacks(t, "Dread")
	K.unmark(t, "Dread")
	K.dmg(c, t, 35 * n, { noDread = true, noDreadBonus = true })
	K.root(c, t, 0.25 * n)
	if c.p60 and n >= 3 then
		dread(f, t, 1)
	end
end

-- 5 The Room That Follows (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(18)
	local frames = {}
	for i = 0, 3 do
		local a = math.rad(i * 90)
		local d = Vector3.new(math.cos(a), 0, math.sin(a))
		local p = K.ground(center + d * K.m(7))
		frames[i + 1] = { pos = p, dir = -d }
		K.FX.base({ size = Vector3.new(K.m(2.5), K.m(3.2), 0.4), cf = CFrame.lookAt(p + Vector3.new(0, K.m(1.6), 0), p + Vector3.new(0, K.m(1.6), 0) - d), color = Color3.fromRGB(40, 20, 35), transparency = 0.5 })
	end
	local t0 = K.now()
	local beat = 0
	local function creature(fr)
		local from = fr.pos
		local hit = {}
		for s = 1, 14 do
			local p = from + fr.dir * K.m(14) * (s / 14)
			K.FX.sphere(p + Vector3.new(0, 1.5, 0), 1.2, DREAD, 0.15, 0.2)
			for _, t in ipairs(K.enemiesIn(f, p, 1.5)) do
				if not hit[t] then
					hit[t] = true
					K.dmg(c, t, 90, { fromPos = p, noDread = true })
				end
			end
			task.wait(0.03)
		end
	end
	while K.now() - t0 < 7 do
		beat += 1
		local idx = (beat - 1) % 4 + 1
		local final = K.now() - t0 > 5.4
		local active = { frames[idx] }
		if c.unstable and final then
			table.insert(active, frames[(idx + 1) % 4 + 1])
			K.Combat.control(f, "root", 1.5, f, { force = true })
		end
		for _, fr in ipairs(active) do
			K.FX.beam(fr.pos + Vector3.new(-1, K.m(3.2), 0), fr.pos + Vector3.new(1, K.m(3.2), 0), 0.6, Color3.fromRGB(255, 230, 150), 0.7) -- lit lintel
			K.telegraphLine(c, fr.pos, fr.dir, 14, 2.5, 0.7, DREAD)
		end
		task.wait(0.7)
		for _, fr in ipairs(active) do
			K.spawn(creature, fr)
		end
		task.wait(0.8)
		if final then
			break
		end
	end
end

return Kit
