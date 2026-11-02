-- 87 Star — Small celestial bodies and finite stellar fuel
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local STAR = Color3.fromRGB(255, 240, 150)

local function setFuel(f, n)
	f.state.fuel = math.clamp(n, 0, 3)
	K.res(f, "Fuel", f.state.fuel, 3, 1)
end
local function stars(f)
	local out = {}
	for _, o in ipairs(K.owned(f, "Star")) do
		if not o.isUlt then
			table.insert(out, o)
		end
	end
	return out
end

-- Passive: Stellar Fuel
function Kit.passive.init(f)
	setFuel(f, 3)
	f.state.lastStarCast = 0
end
function Kit.passive.cast(f)
	f.state.lastStarCast = K.now()
end
function Kit.passive.tick(f, dt, now)
	K.res(f, "Stars", #stars(f), nil, 2)
	if f.state.noRecoverUntil and f.state.noRecoverUntil > now then
		return
	end
	if f.state.fuel < 3 and now - f.state.lastStarCast >= 4 then
		f.state.lastStarCast = now
		setFuel(f, f.state.fuel + 1)
	end
end

local function nearestStar(c, pos, rangeM)
	local best, bd
	for _, s in ipairs(stars(c.f)) do
		local d = (s.part.Position - pos).Magnitude
		if d <= K.m(rangeM) and (not bd or d < bd) then
			best, bd = s, d
		end
	end
	return best
end

Kit.requires = {
	[1] = function(c)
		if (c.f.state.fuel or 0) >= 1 then
			return true
		end
		return false, "No Fuel"
	end,
	[2] = function(c)
		if nearestStar(c, c.f.root.Position, 18) then
			return true
		end
		return false, "No star in range"
	end,
	[3] = function(c)
		if #stars(c.f) >= 2 then
			return true
		end
		return false, "Needs two stars"
	end,
	[4] = function(c)
		if nearestStar(c, c:aimPoint(16), 30) then
			return true
		end
		return false, "No star"
	end,
}

-- 1 Spark Birth
Kit[1] = function(c)
	local f = c.f
	setFuel(f, f.state.fuel - 1)
	local pos = c:aimPoint(14)
	K.telegraph(c, pos, 1.5, 0.3, STAR)
	task.wait(0.3)
	K.circle(c, pos, 1.5, { dmg = 55, color = STAR })
	K.object(c, { name = "Star", cf = CFrame.new(pos + Vector3.new(0, K.m(1.2), 0)), size = 0.9, shape = "Ball", hp = 80, duration = c.p60 and 9 or 7, solid = false, color = STAR, material = Enum.Material.Neon })
end

-- 2 Comet Throw
Kit[2] = function(c)
	local f = c.f
	local s = nearestStar(c, f.root.Position, 18)
	if not s then
		return
	end
	local from = s.part.Position
	local dir = K.flat(c:aimPoint(30) - from)
	S.Objects.remove(s, "thrown")
	K.proj(c, {
		origin = from,
		dir = dir,
		range = 14,
		speed = 26,
		width = 0.9,
		color = STAR,
		dmg = 100,
		finish = function(pos)
			if c.p60 then
				K.delayed(c, K.ground(pos), 1, 0.3, function(p)
					K.circle(c, p, 1, { dmg = 30, color = STAR })
				end, STAR)
			end
		end,
	})
end

-- 3 Binary Link
Kit[3] = function(c)
	local f = c.f
	local list = stars(f)
	local aim = c:aimPoint(16)
	table.sort(list, function(a, b)
		return (a.part.Position - aim).Magnitude < (b.part.Position - aim).Magnitude
	end)
	local a, b
	for i = 1, #list do
		for j = i + 1, #list do
			if (list[i].part.Position - list[j].part.Position).Magnitude <= K.m(8) then
				a, b = list[i], list[j]
				break
			end
		end
		if a then
			break
		end
	end
	if not a then
		K.notify(f, "Stars must be within 8 m of each other")
		return
	end
	local hit = {}
	K.every(0.05, 4, function()
		if not (a.alive and b.alive) then
			return false
		end
		K.FX.beam(a.part.Position, b.part.Position, 0.25, STAR, 0.08)
		for _, h in ipairs(K.Hit.segment(a.part.Position, b.part.Position, K.m(0.5), K.enemyFilter(c))) do
			if not hit[h.f] then
				hit[h.f] = true
				K.dmg(c, h.f, 75, { kind = "field" })
				K.reveal(c, h.f, 2)
			end
		end
		return true
	end)
	if c.p60 then
		K.after(4, function()
			if a.alive and b.alive then
				setFuel(f, f.state.fuel + 1)
			end
		end)
	end
end

-- 4 Dying Light
Kit[4] = function(c)
	local f = c.f
	local s = nearestStar(c, c:aimPoint(16), 30)
	if not s or s.data.collapsing then
		return
	end
	s.data.collapsing = true
	local pos = K.ground(s.part.Position)
	K.telegraph(c, pos, 3, 0.8, STAR)
	task.wait(0.8)
	if not s.alive then
		return -- destroyed during the warning: collapse cancelled
	end
	S.Objects.remove(s, "collapsed")
	K.circle(c, pos, 3, { dmg = 120, color = STAR })
	if c.p60 then
		for _, a in ipairs(K.alliesIn(c, pos, 3, true)) do
			K.shield(c, a, 50, 3, "DyingLight")
		end
	end
end

-- 5 Constellation's End (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	local temp = {}
	local layout = { Vector3.new(0, 0, 0), Vector3.new(5, 0, 2), Vector3.new(-5, 0, 2), Vector3.new(3, 0, -4), Vector3.new(-3, 0, -4) }
	for i, off in ipairs(layout) do
		local p = K.ground(center + off * K.M)
		temp[i] = K.object(c, { name = "Star", cf = CFrame.new(p + Vector3.new(0, K.m(1.2), 0)), size = 1.1, shape = "Ball", hp = 100, duration = 6, solid = false, isUlt = true, color = STAR, material = Enum.Material.Neon })
		temp[i].data.r = off.Magnitude
	end
	local totals = {}
	local function collapse(s, cc)
		if not s.alive then
			return
		end
		local pos = K.ground(s.part.Position)
		K.telegraph(cc, pos, 3, 0.7, STAR)
		task.wait(0.7)
		if not s.alive then
			return
		end
		S.Objects.remove(s, "collapsed")
		K.FX.burst(pos + Vector3.new(0, 1, 0), K.m(3), STAR, 0.3)
		for _, t in ipairs(K.enemiesIn(cc, pos, 3)) do
			if (totals[t] or 0) < 3 then
				totals[t] = (totals[t] or 0) + 1
				K.dmg(cc, t, 95, { fromPos = pos })
			end
		end
	end
	if c.unstable then
		table.sort(temp, function(a, b)
			return a.data.r > b.data.r
		end)
		for _, s in ipairs(temp) do
			collapse(s, c)
		end
		f.state.noRecoverUntil = K.now() + 6
		return
	end
	local chosen = 0
	c:recast(6, function(c2)
		local aim = c2:aimPoint(30)
		local best, bd
		for _, s in ipairs(temp) do
			if s.alive and not s.data.collapsing then
				local d = (s.part.Position - aim).Magnitude
				if not bd or d < bd then
					best, bd = s, d
				end
			end
		end
		if best then
			best.data.collapsing = true
			K.spawn(collapse, best, c2)
			chosen += 1
		end
		if chosen < 3 then
			return "keep"
		end
		return nil
	end)
end

return Kit
