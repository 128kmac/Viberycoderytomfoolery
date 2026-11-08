-- 31 Electric — Conductive marks and linked burst
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local YELLOW = Color3.fromRGB(255, 240, 60)

local function charge(f, t)
	if t.state.chargeImmune and t.state.chargeImmune > K.now() then
		return
	end
	K.debuff(f, t, "Charge", { duration = 5, stacks = 1, max = 3, category = "charge", label = "Charge" })
end

-- Passive: Potential Difference
function Kit.passive.beforeDeal(f, target, info)
	if info.kind == "direct" and K.stacks(target, "Charge") >= 3 and not info.opts.noDischarge then
		info.amount += 40
		K.unmark(target, "Charge")
		target.state.chargeImmune = K.now() + 1
		K.FX.burst(target.root.Position, 4, YELLOW, 0.2)
		info.opts.discharged = true
	end
end
function Kit.passive.dealt(f, target, info)
	if info.kind == "direct" and info.opts.cast and not info.opts.discharged and not info.opts.noCharge then
		charge(f, target)
	end
end

local function arc(a, b)
	local mid = (a + b) / 2 + Vector3.new(math.random(-10, 10) / 10, math.random(-10, 10) / 10, 0)
	K.FX.beam(a, mid, 0.25, YELLOW, 0.15)
	K.FX.beam(mid, b, 0.25, YELLOW, 0.15)
end

local function jump(c, from, exclude, rangeM, dmg)
	local wet = K.partner(c, "Water", 20) and 2 or 0
	for _, t in ipairs(K.enemiesIn(c.f, from, rangeM + wet, { sphere = true })) do
		if t ~= exclude and K.has(t, "Charge") and K.Hit.los(from, t.root.Position) then
			arc(from, t.root.Position)
			K.dmg(c, t, dmg, { fromPos = from })
			return t
		end
	end
	return nil
end

-- 1 Arc Needle
Kit[1] = function(c)
	K.proj(c, {
		range = 22,
		speed = 40,
		width = 0.25,
		color = YELLOW,
		shape = "Block",
		size = Vector3.new(0.25, 0.25, 2),
		tags = { electric = true },
		hit = function(t)
			local hadCharge = K.has(t, "Charge")
			K.dmg(c, t, 70, { projectile = true })
			local _ = hadCharge
			jump(c, t.root.Position, t, c.p60 and 6 or 4, 30)
		end,
	})
end

-- 2 Flash Ground
Kit[2] = function(c)
	local f = c.f
	local start = c:feet()
	local dir = c:dir()
	local traveled = K.dash(c, dir, 7, 0.2)
	local struck = {}
	K.zone(c, {
		shape = "rect",
		pos = start,
		dir = dir,
		width = 1.2,
		length = math.max(1, traveled),
		duration = 2,
		tick = 0.1,
		immediate = true,
		color = YELLOW,
		transparency = 0.4,
		tickFn = function(_, list)
			for _, t in ipairs(list) do
				if K.isEnemy(f, t) and not struck[t] then
					struck[t] = true
					K.dmg(c, t, 40, { kind = "field" })
				end
			end
		end,
	})
	if c.p60 then
		for _, t in ipairs(K.enemiesIn(c, f.root.Position, 3)) do
			if K.has(t, "Charge") then
				K.S.Status.removeStacks(t, "Charge", 1)
				K.shield(c, f, 60, 3, "FlashGround")
				break
			end
		end
	end
end

-- 3 Lightning Rod
Kit[3] = function(c)
	local f = c.f
	local pos = c:aimPoint(16)
	local rod = K.object(c, { name = "LightningRod", pos = pos, size = Vector3.new(0.4, 3, 0.4), hp = 140, duration = 6, color = YELLOW, material = Enum.Material.Metal })
	local routed = false
	local moved = false
	if c.p60 then
		c:recast(6, function(c2)
			if rod.alive and not moved then
				moved = true
				local d = K.flat(c2:aimPoint(30) - rod.part.Position)
				rod.part.CFrame += d * K.m(2)
			end
		end)
	end
	K.every(0.03, 6, function()
		if not rod.alive or routed then
			return false
		end
		local top = rod.part.Position + Vector3.new(0, 1, 0)
		for _, p in pairs(S.Proj.list) do
			if p.alive and p.owner == f and p.tags.electric and (p.pos - top).Magnitude < K.m(1.5) then
				local t = K.nearestEnemy(f, 20, top)
				if t then
					routed = true
					p.pos = top
					p.vel = (t.root.Position - top).Unit * p.speed
					arc(top, top + p.vel.Unit * 3)
					return false
				end
			end
		end
		return true
	end)
end

-- 4 Short Circuit
Kit.requires = {
	[4] = function(c)
		if c:target(12) then
			return true
		end
		return false, "No target"
	end,
}
Kit[4] = function(c)
	local t = c:target(12)
	if not t then
		return
	end
	local n = K.stacks(t, "Charge")
	arc(c:chest(), t.root.Position)
	if n > 0 then
		K.unmark(t, "Charge")
		K.dmg(c, t, 45 * n, { noDischarge = true, noCharge = true })
		K.interrupt(t, "short circuit")
		K.stun(c, t, 0.2)
	else
		K.dmg(c, t, 30, { noCharge = false })
	end
	if c.p60 then
		for _, sm in ipairs(K.enemies(c.f, 20)) do
			if sm.isSummon and K.dist(sm, t) < 6 then
				K.Status.apply(sm, "stun", { duration = 1, source = c.f, category = "control", label = "Shorted" })
				break
			end
		end
	end
end

-- 5 Heaven's Circuit (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(24)
	local rods = {}
	for i = 0, 2 do
		local a = math.rad(i * 120 + 90)
		rods[i + 1] = K.object(c, {
			name = "CircuitRod",
			pos = K.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(8 / math.sqrt(3))),
			size = Vector3.new(0.5, 3.5, 0.5),
			hp = 160,
			duration = 6,
			isUlt = true,
			color = YELLOW,
			material = Enum.Material.Neon,
		})
	end
	local totals = {}
	local rodPos = {}
	for i, r in ipairs(rods) do
		rodPos[i] = r.part.Position
	end
	K.phase(c, "begin", { p = center, rods = rodPos })
	for loop = 1, 3 do
		for i = 1, 3 do
			local a, b = rods[i], rods[i % 3 + 1]
			if a.alive and b.alive then
				local pa, pb = a.part.Position + Vector3.new(0, 1, 0), b.part.Position + Vector3.new(0, 1, 0)
				arc(pa, pb)
				K.phase(c, "surge", { a = pa, b = pb, loop = loop })
				for _, h in ipairs(K.Hit.segment(pa, pb, K.m(0.8), K.enemyFilter(c))) do
					local t = h.f
					local d = math.min(70, 280 - (totals[t] or 0))
					if d > 0 then
						totals[t] = (totals[t] or 0) + d
						K.dmg(c, t, d, { fromPos = pa, noDischarge = true })
					end
				end
			end
			task.wait(0.2)
		end
		local _ = loop
	end
	K.phase(c, "finish", { p = center })
	if c.unstable then
		K.phase(c, "overload", { p = center })
		K.telegraph(c, center, 3, 0.5, YELLOW)
		task.wait(0.5)
		for _, t in ipairs(K.Hit.cylinder(center, K.m(3), function()
			return true
		end)) do
			K.Combat.damage(f, t, 120, { cast = c, isUlt = true, fromPos = center, element = "Electric" })
		end
		K.FX.burst(center, K.m(3), YELLOW, 0.4)
		for _, r in ipairs(rods) do
			if r.alive then
				S.Objects.remove(r, "overload")
			end
		end
	end
end

return Kit
