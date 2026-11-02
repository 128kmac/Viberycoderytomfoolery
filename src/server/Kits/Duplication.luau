-- 27 Duplication — Multiple bodies with shared limits
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local TEAL = Color3.fromRGB(120, 200, 200)

local function doubles(f)
	return K.summons(f, "Double")
end

local function cap(f)
	return f.state.cap or 2
end

local function makeDouble(f, pos, hp)
	if #doubles(f) >= cap(f) then
		return nil
	end
	local idx = (f.state.nextSide or 0) + 1
	f.state.nextSide = idx
	local d = K.summon(f, {
		name = "Double",
		pos = pos,
		hp = hp or 150,
		speed = 7,
		size = Vector3.new(1.4, 4.6, 0.8),
		shape = "Block",
		color = TEAL,
		material = Enum.Material.SmoothPlastic,
		transparency = 0.3,
		ai = "none",
	})
	d.data.side = (idx % 2 == 0) and 1 or -1
	d.data.rank = math.ceil(idx / 2)
	d.data.lastStrike = 0
	return d
end

-- Passive: Shared Attention
function Kit.passive.init(f)
	f.state.hist = {}
	f.state.respawnAt = 0
	f.state.basicTotals = {}
	K.after(0.5, function()
		if f.kitName == "Duplication" and not f.dead then
			for i = 1, 2 do
				makeDouble(f, f.root.Position + K.flat(f.root.CFrame.RightVector) * K.m(i == 1 and 3 or -3))
			end
		end
	end)
end
function Kit.passive.cleanup(f)
	for _, d in ipairs(doubles(f)) do
		S.Summons.remove(d, "cleanup")
	end
end
function Kit.passive.tick(f, dt, now)
	-- movement history for the 0.3 s delayed copy
	table.insert(f.state.hist, { t = now, cf = f.root.CFrame })
	while #f.state.hist > 0 and now - f.state.hist[1].t > 1 do
		table.remove(f.state.hist, 1)
	end
	local past
	for i = #f.state.hist, 1, -1 do
		if now - f.state.hist[i].t >= 0.3 then
			past = f.state.hist[i].cf
			break
		end
	end
	past = past or f.root.CFrame
	local ds = doubles(f)
	K.res(f, "Doubles", #ds, cap(f), 1)
	for _, d in ipairs(ds) do
		if not d.data.ordered then
			local offset = past.RightVector * K.m(3 * d.data.side * d.data.rank)
			local goal = past.Position + offset
			S.Summons.moveTo(d, goal)
			d.sm.ai = "stay"
		end
		-- basic 25-damage strike at most once per second (75 total per second per target during Assembly)
		if now - d.data.lastStrike >= 1 and not d.data.intercepting then
			for _, t in ipairs(K.enemiesIn(f, d.root.Position, 2.5)) do
				local key = t
				local tot = f.state.basicTotals[key]
				if not tot or now - tot.t >= 1 then
					tot = { t = now, n = 0 }
					f.state.basicTotals[key] = tot
				end
				if tot.n + 25 <= 75 then
					tot.n += 25
					d.data.lastStrike = now
					K.FX.beam(d.root.Position, t.root.Position, 0.3, TEAL, 0.1)
					K.Combat.damage(d, t, 25, { fromSummon = true, melee = true, element = "Duplication" })
				end
				break
			end
		end
	end
	-- maintain the ordinary doubles
	if #ds < 2 and now >= f.state.respawnAt then
		f.state.respawnAt = now + 6
		makeDouble(f, f.root.Position + K.flat(f.root.CFrame.RightVector) * K.m(3))
	end
end

-- 1 Split Entry
Kit[1] = function(c)
	local f = c.f
	local side = c.mod and -1 or 1
	makeDouble(f, f.root.Position + K.flat(f.root.CFrame.RightVector) * K.m(3 * side))
	K.dash(c, c:dir(), 3, 0.15)
	K.melee(c, { range = 3, arc = 90, dmg = 70, color = TEAL })
end

-- 2 Twin Relay
Kit.requires = {
	[2] = function(c)
		if #doubles(c.f) > 0 then
			return true
		end
		return false, "No double"
	end,
}
Kit[2] = function(c)
	local f = c.f
	local aim = c:aimPoint(16)
	local best, bd
	for _, d in ipairs(doubles(f)) do
		local dist = (d.root.Position - aim).Magnitude
		if K.dist(d, f) <= 16 and K.los(f, d) and (not bd or dist < bd) then
			best, bd = d, dist
		end
	end
	if not best then
		return
	end
	K.FX.beam(f.root.Position, best.root.Position, 0.4, TEAL, 0.35)
	task.wait(0.35)
	if not K.alive(best) then
		return
	end
	local a, b = f.root.Position, best.root.Position
	local stand = K.Hit.findLegal(b)
	if stand then
		S.Fighter.teleport(f, stand)
		S.Fighter.teleport(best, a)
		if c.p60 then
			K.shield(c, best, 60, 3, "Relay")
		end
	end
	if (f.state.relayCharges or 0) > 0 then
		f.state.relayCharges -= 1
		K.setCd(f, 2, 0.5)
	end
end

-- 3 Echo Formation
Kit[3] = function(c)
	local f = c.f
	local ds = doubles(f)
	for i, d in ipairs(ds) do
		d.data.ordered = true
		d.data.intercepting = true
		d.data.formationIndex = i
	end
	K.every(0.05, 4, function()
		if not K.alive(f) then
			return false
		end
		local fwd = K.flat(f.root.CFrame.LookVector)
		local right = fwd:Cross(Vector3.yAxis)
		for i, d in ipairs(ds) do
			if K.alive(d) then
				local slotPos = f.root.Position + fwd * K.m(2.2) + right * K.m((i - (#ds + 1) / 2) * 1.6)
				if c.p60 or i <= 3 then
					S.Summons.moveTo(d, slotPos)
				end
				for _, p in ipairs(K.enemyProj(c, d.root.Position, 1.2)) do
					if p.kind ~= "ultimate" and not d.data.blocked then
						d.data.blocked = true
						S.Proj.stop(p, "intercepted")
						K.Combat.damage(nil, d, 60, { kind = "true" })
						break
					end
				end
			end
		end
		return true
	end)
	K.after(4, function()
		for _, d in ipairs(ds) do
			if K.alive(d) then
				d.data.ordered = nil
				d.data.intercepting = nil
				d.data.blocked = nil
			end
		end
	end)
end

-- 4 Synchronized Strike
local function strike(c, capTotal, delayOne)
	local f = c.f
	local totals = {}
	local function hitT(t, dmg, src)
		local d = math.min(dmg, capTotal - (totals[t] or 0))
		if d > 0 then
			totals[t] = (totals[t] or 0) + d
			if src == f then
				K.dmg(c, t, d, { melee = true })
			else
				K.Combat.damage(src, t, d, { fromSummon = true, melee = true, element = "Duplication" })
			end
		end
	end
	local aim = c:aimPoint(14)
	for i, d in ipairs(doubles(f)) do
		local target = K.nearestEnemy(d, 14) or nil
		local goal = target and target.root.Position or (aim + K.rotate(c:dir(), i * 40) * K.m(2))
		local function go()
			if not K.alive(d) then
				return
			end
			d.data.ordered = true
			local from = d.root.Position
			for s = 1, 6 do
				local p = from:Lerp(goal, s / 6)
				d.root.CFrame = CFrame.new(Vector3.new(p.X, from.Y, p.Z))
				task.wait(0.03)
			end
			for _, t in ipairs(K.enemiesIn(f, d.root.Position, 1.8)) do
				hitT(t, 45, d)
				break
			end
			d.data.ordered = nil
		end
		if delayOne and i == 1 then
			K.after(0.4, go)
		else
			K.spawn(go)
		end
	end
	local struck = false
	K.dash(c, K.flat(aim - f.root.Position), math.min(14, K.flatDist(aim, f)), 0.25, {
		passWidth = 1.6,
		onPass = function(t)
			if not struck then
				struck = true
				hitT(t, 90, f)
			end
		end,
	})
end
Kit[4] = function(c)
	strike(c, 150, c.p60)
end

-- 5 Assembly of One (ultimate)
Kit[5] = function(c)
	local f = c.f
	f.state.cap = 5
	f.state.relayCharges = 1
	K.setCd(f, 2, 0)
	for _ = 1, 3 do
		makeDouble(f, f.root.Position + K.flat(K.rotate(f.root.CFrame.LookVector, math.random(0, 359))) * K.m(3), 120)
	end
	c:form(7, {
		onEnd = function()
			f.state.cap = 2
			f.state.relayCharges = 0
			local ds = doubles(f)
			for i = 3, #ds do
				S.Summons.remove(ds[i], "assembly end")
			end
			if c.unstable then
				for _, d in ipairs(doubles(f)) do
					S.Summons.remove(d, "crash")
				end
				K.FX.highlight(f.model, Color3.fromRGB(255, 255, 255), 2, 0.3)
			end
		end,
	})
	if c.unstable then
		c:recast(7, function(c2)
			strike(c2, 240, false)
			K.after(0.6, function()
				for _, d in ipairs(doubles(f)) do
					S.Summons.remove(d, "crash")
				end
			end)
		end)
	end
end

return Kit
