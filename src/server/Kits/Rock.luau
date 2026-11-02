-- 76 Rock — Persistent boulders and momentum choices
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local STONE = Color3.fromRGB(120, 110, 100)

local function boulders(f)
	local out = {}
	for _, o in ipairs(K.owned(f, "Boulder")) do
		table.insert(out, o)
	end
	table.sort(out, function(a, b)
		return a.created < b.created
	end)
	return out
end

-- Passive: Three Stones
local function makeBoulder(c, pos, hp)
	local f = c.f
	local list = boulders(f)
	if #list >= 3 then
		S.Objects.remove(list[1], "replaced")
	end
	return K.object(c, { name = "Boulder", pos = pos, size = 2, shape = "Ball", hp = hp or 140, duration = 12, color = STONE, material = Enum.Material.Rock, noCap = true })
end
Kit.makeBoulder = makeBoulder
function Kit.passive.tick(f, dt)
	K.res(f, "Boulders", #boulders(f), 3, 1)
	local hum = f.humanoid
	if hum and hum.MoveDirection.Magnitude < 0.05 then
		f.state.still = (f.state.still or 0) + dt
	else
		f.state.still = 0
	end
end

-- 1 Pebble Volley
Kit[1] = function(c)
	local fan = (c.p60 and (c.f.state.still or 0) >= 0.5) and 4 or 12
	local dir = c:dir3()
	for i = -1, 1 do
		K.proj(c, { dir = K.rotate(dir, i * fan / 2), range = 18, speed = 28, width = 0.4, color = STONE, kind = "physical", dmg = 25 })
	end
end

-- 2 Boulder Birth
Kit[2] = function(c)
	local pos = c:aimPoint(12)
	K.telegraph(c, pos, 1.2, 0.6, STONE)
	task.wait(0.6)
	for _, t in ipairs(K.Hit.cylinder(pos, K.m(1.4), function()
		return true
	end)) do
		if K.isEnemy(c.f, t) then
			K.dmg(c, t, 60, { fromPos = pos })
		end
		K.push(c, t, K.flat(t.root.Position - pos), 1.5)
	end
	makeBoulder(c, pos, 140 + (c.p60 and 40 or 0))
end

-- 3 Rolling Verdict
Kit.requires = {
	[3] = function(c)
		for _, b in ipairs(boulders(c.f)) do
			if K.flatDist(b.part.Position, c.f) <= 6 then
				return true
			end
		end
		return false, "No boulder within kicking range"
	end,
	[4] = function(c)
		if #boulders(c.f) > 0 then
			return true
		end
		return false, "No boulder"
	end,
}
Kit[3] = function(c)
	local f = c.f
	local b
	local bd
	for _, o in ipairs(boulders(f)) do
		local d = K.flatDist(o.part.Position, f)
		if d <= 6 and (not bd or d < bd) then
			b, bd = o, d
		end
	end
	if not b then
		return
	end
	local dir = c:dir()
	local hit = {}
	local traveled = 0
	local corrected = false
	b.data.rolling = true
	while traveled < 18 and b.alive do
		if c.p60 and not corrected and traveled > 3 then
			corrected = true
			local want = c:dir()
			local ang = math.deg(math.acos(math.clamp(want:Dot(dir), -1, 1)))
			dir = ang <= 15 and want or dir:Lerp(want, 15 / ang).Unit
		end
		local from = b.part.Position
		local step = K.m(0.6)
		local blocked = workspace:Raycast(from, dir * (step + b.part.Size.X / 2), K.Hit.arenaParams)
		if blocked then
			break
		end
		local to = from + dir * step
		local g = K.Hit.ground(to + Vector3.new(0, 3, 0), 12)
		if g then
			to = Vector3.new(to.X, g.Y + b.part.Size.Y / 2, to.Z)
		end
		b.part.CFrame = CFrame.new(to) * CFrame.Angles(traveled, 0, 0)
		for _, t in ipairs(K.enemiesIn(f, to, 1.4)) do
			if not hit[t] then
				hit[t] = true
				K.dmg(c, t, 110, { fromPos = from })
			end
		end
		traveled += 0.6
		task.wait(0.02)
	end
	b.data.rolling = nil
	if b.alive and b.hp < b.maxHp / 2 then
		S.Objects.remove(b, "crumbled")
	end
end

-- 4 Stone Splitter
Kit[4] = function(c)
	local f = c.f
	local aim = c:aimPoint(14)
	local list = boulders(f)
	table.sort(list, function(a, b)
		return (a.part.Position - aim).Magnitude < (b.part.Position - aim).Magnitude
	end)
	local b = list[1]
	if not b then
		return
	end
	local from = b.part.Position
	S.Objects.remove(b, "shattered")
	local dir = K.flat(aim - from)
	if (aim - from).Magnitude < K.m(1) then
		dir = c:dir()
	end
	local totals = {}
	for i = -2, 2 do
		K.proj(c, {
			origin = from,
			dir = K.rotate(dir, i * 17),
			range = 10,
			speed = 26,
			width = 0.6,
			color = STONE,
			kind = "physical",
			hit = function(t)
				if (totals[t] or 0) < 3 then
					totals[t] = (totals[t] or 0) + 1
					K.dmg(c, t, 35)
				end
			end,
		})
	end
	if c.p60 then
		K.object(c, { name = "Remnant", pos = K.ground(from), size = 1.2, hp = 60, duration = 6, color = STONE, material = Enum.Material.Rock })
	end
end

-- 5 Monolith Procession (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local monos = {}
	for i = -1.5, 1.5, 1 do
		local p = K.ground(center + side * K.m(i * 3))
		local m = K.object(c, { name = "Monolith", cf = CFrame.lookAt(p + Vector3.new(0, K.m(2), 0), p + Vector3.new(0, K.m(2), 0) + dir), size = Vector3.new(1, 4, 1), hp = 180, duration = 6, isUlt = true, color = STONE, material = Enum.Material.Rock })
		m.data.base = p
		table.insert(monos, m)
	end
	local totals = {}
	local function topple(m, cc, d)
		if not m.alive then
			return
		end
		local base = m.data.base
		K.telegraphLine(cc, base, d, 5, 1.2, 0.7, STONE)
		task.wait(0.7)
		if not m.alive then
			return
		end
		S.Objects.remove(m, "toppled")
		K.FX.rect(CFrame.lookAt(base + d * K.m(2.5) + Vector3.new(0, 0.5, 0), base + d * K.m(5)), K.m(1), K.m(5), 0.6, STONE, 0)
		for _, t in ipairs(K.enemiesLine(cc, base, d, 5, 1.2)) do
			if (totals[t] or 0) < 3 then
				totals[t] = (totals[t] or 0) + 1
				K.dmg(cc, t, 100, { fromPos = base + Vector3.new(0, 8, 0) })
			end
		end
	end
	if c.unstable then
		for _, m in ipairs(monos) do
			topple(m, c, dir)
		end
		return
	end
	c:recast(6, function(c2)
		local aim = c2:aimPoint(30)
		local best, bd
		for _, m in ipairs(monos) do
			if m.alive then
				local d = (m.part.Position - aim).Magnitude
				if not bd or d < bd then
					best, bd = m, d
				end
			end
		end
		if best then
			topple(best, c2, K.flat(aim - best.data.base).Magnitude > 1 and K.flat(aim - best.data.base) or dir)
		end
		for _, m in ipairs(monos) do
			if m.alive then
				return "keep"
			end
		end
		return nil
	end)
	local _ = f
end

return Kit
