-- 96 Water — Directed flow and flexible pressure (shallow and temporary; no drowning)
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local WATER = Color3.fromRGB(40, 140, 255)
local KIND = { [1] = "jet", [4] = "jet", [2] = "current", [3] = "current" }

local function flow(f)
	local now = K.now()
	local out = {}
	for _, t in ipairs(f.state.flow) do
		if t > now then
			table.insert(out, t)
		end
	end
	f.state.flow = out
	return #out
end
local function spendFlow(f, n)
	local take = math.min(n, flow(f))
	for _ = 1, take do
		table.remove(f.state.flow, 1)
	end
	return take
end

-- Passive: Flow Sequence — alternating a jet with a current grants Flow (max 3, 7 s)
function Kit.passive.init(f)
	f.state.flow = {}
end
function Kit.passive.tick(f)
	K.res(f, "Flow", flow(f), 3, 1)
end
function Kit.passive.cast(f, c)
	local kind = KIND[c.slot]
	if kind and f.state.lastKind and f.state.lastKind ~= kind and flow(f) < 3 then
		table.insert(f.state.flow, K.now() + 7)
	end
	if kind then
		f.state.lastKind = kind
	end
end

-- a direct Water hit removes one Burn or extinguishes one small Fire patch
local function douse(c, pos)
	for _, z in ipairs(K.zonesNear(pos, 1.5)) do
		if z.element == "Fire" and (z.radius or 0) <= K.m(3) then
			z:remove("extinguished")
			return
		end
	end
	for _, o in pairs(S.Objects.list) do
		if o.alive and o.name == "Ember" and (o.part.Position - pos).Magnitude < K.m(1.5) then
			S.Objects.remove(o, "extinguished")
			return
		end
	end
end

local function channel(c, from, dir, length, duration)
	local f = c.f
	return K.zone(c, {
		shape = "rect",
		pos = from,
		dir = dir,
		width = 2,
		length = length,
		duration = duration,
		tick = 0.25,
		immediate = true,
		targets = "all",
		color = WATER,
		transparency = 0.5,
		tags = { channel = true },
		tickFn = function(z, list)
			for _, t in ipairs(list) do
				local md = t.humanoid and t.humanoid.MoveDirection or Vector3.zero
				if md.Magnitude > 0.1 then
					local along = md:Dot(z.dir)
					if K.isAlly(f, t) and along > 0.5 then
						K.speed(t, 0.15, 0.4, "Downstream")
					elseif K.isEnemy(f, t) and along < -0.5 then
						K.slow(c, t, 0.15, 0.4, "Upstream")
					end
				end
			end
		end,
	})
end

-- 1 Pressure Lance (modifier spends a Flow to push)
Kit[1] = function(c)
	local push = c.mod and spendFlow(c.f, 1) > 0
	local endPos = K.beam(c, {
		length = c.p60 and 23 or 20,
		width = 0.5,
		dmg = 80,
		color = WATER,
		dur = 0.3,
		hit = function(t)
			if push then
				K.push(c, t, c:dir(), 1)
			end
		end,
	})
	douse(c, endPos)
	for _, a in ipairs(K.alliesIn(c, endPos, 1.5, false)) do
		K.cleanse(a, "burn", 1)
		break
	end
end

-- 2 Running Channel
Kit[2] = function(c)
	local start = c:feet()
	local dir = c:dir()
	if c.p60 and c.mod then
		channel(c, start, dir, 4, 6)
		local side = K.flat(dir:Cross(Vector3.yAxis))
		local rel = (c:aimPoint(20) - start):Dot(side) >= 0 and side or -side
		channel(c, start + dir * K.m(4), rel, 4, 6)
	else
		channel(c, start, dir, 8, 6)
	end
end

-- 3 Undertow Step
Kit[3] = function(c)
	local f = c.f
	if c.p60 then
		K.cleanse(f, "burn", 1)
	end
	local onChannel = false
	for _, z in ipairs(K.ownedZones(f, "channel")) do
		if z:contains(f) then
			onChannel = true
		end
	end
	local hit = {}
	K.dash(c, c:dir(), onChannel and 8 or 6, 0.35, {
		passWidth = 3,
		onPass = function(t)
			if not hit[t] then
				hit[t] = true
				K.dmg(c, t, 45)
			end
		end,
	})
end

-- 4 Crest Break
Kit[4] = function(c)
	local f = c.f
	local extra = spendFlow(f, 2)
	local origin = f.root.Position
	local dir = c:dir()
	K.telegraphLine(c, origin, dir, 6, 4, 0.25, WATER)
	task.wait(0.25)
	K.line(c, origin, dir, 6, 4, {
		dmg = 100 + 15 * extra,
		color = WATER,
		hit = function(t)
			K.push(c, t, dir, 2)
		end,
	})
	douse(c, origin + dir * K.m(6))
	if c.p60 then
		channel(c, K.ground(origin + dir * K.m(5)), dir, 3, 3)
	end
end

-- 5 Tide of the Returning Sea (ultimate)
Kit[5] = function(c)
	local f = c.f
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local start = c:feet() + dir * K.m(1)
	local hitOut = {}
	local function sweep(from, d, width, dmg, hitSet, onHit, lane)
		local wall = K.FX.base({ size = Vector3.new(K.m(width), K.m(2), K.m(1.2)), cf = CFrame.lookAt(from, from + d), color = WATER, transparency = 0.25, material = Enum.Material.Glass })
		for s = 0, 24 do
			local p = from + d * K.m(12) * (s / 24) + Vector3.new(0, K.m(1), 0)
			wall.CFrame = CFrame.lookAt(p, p + d)
			for _, t in ipairs(K.Hit.box(wall.CFrame, wall.Size + Vector3.new(0, 2, 0), K.enemyFilter(c))) do
				if not hitSet[t] and (not lane or lane(t)) then
					hitSet[t] = true
					K.dmg(c, t, dmg, { fromPos = p })
					if onHit then
						onHit(t)
					end
				end
			end
			task.wait(0.05)
		end
		wall:Destroy()
	end
	K.phase(c, "begin", { p = start, dir = dir, len = K.m(12), w = K.m(8) })
	sweep(start, dir, 8, 140, hitOut)
	K.phase(c, "pause", { p = start + dir * K.m(12), dir = dir, w = K.m(8) })
	task.wait(1)
	K.phase(c, "return", { p = start + dir * K.m(12), dir = -dir, len = K.m(12), w = K.m(8) })
	local finish = start + dir * K.m(12)
	local returned = {}
	local pullBack = function(t)
		K.pull(c, t, start, 2)
	end
	if c.unstable then
		-- two 80-damage side currents leave a 3-metre central safe lane
		K.spawn(sweep, finish - side * K.m(2.75), -dir, 2.5, 80, returned, pullBack)
		sweep(finish + side * K.m(2.75), -dir, 2.5, 80, returned, pullBack)
	else
		sweep(finish, -dir, 8, 100, returned, pullBack)
	end
	K.phase(c, "finish", { p = start })
	local _ = f
end

return Kit
