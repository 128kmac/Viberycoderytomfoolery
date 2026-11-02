-- 44 Gold — Finite wealth conversion and heavy protection
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local GOLD = Color3.fromRGB(255, 200, 40)

local function setCoins(f, n)
	f.state.coins = math.clamp(n, 0, 6)
	K.res(f, "Coins", f.state.coins, 6, 1)
end
local function spendCoins(f, n)
	local take = math.min(n, f.state.coins or 0)
	setCoins(f, f.state.coins - take)
	return take
end

-- Passive: Minted Value
function Kit.passive.init(f)
	f.state.progress = 0
	f.state.lastExpire = K.now()
	setCoins(f, 0)
end
function Kit.passive.dealt(f, target, info)
	if info.final > 0 and not target.isSummon and K.isEnemy(f, target) and not info.opts.fromSummon then
		f.state.progress += info.final
		while f.state.progress >= 100 do
			f.state.progress -= 100
			setCoins(f, f.state.coins + 1)
		end
	end
end
function Kit.passive.tick(f, dt, now)
	if now - (f.lastContest or 0) > 8 and f.state.coins > 0 and now - f.state.lastExpire > 8 then
		f.state.lastExpire = now
		setCoins(f, f.state.coins - 1)
	elseif now - (f.lastContest or 0) <= 8 then
		f.state.lastExpire = now
	end
end

-- 1 Gilt Dart
Kit[1] = function(c)
	local f = c.f
	local heavy = c.mod and spendCoins(f, 1) > 0
	K.proj(c, {
		range = 20,
		speed = heavy and 22 or 30,
		width = heavy and 0.5 or 0.3,
		gravity = heavy and K.m(6) or nil,
		shape = "Block",
		size = heavy and Vector3.new(0.6, 0.6, 1.6) or Vector3.new(0.3, 0.3, 1.3),
		color = GOLD,
		kind = "physical",
		dmg = heavy and 100 or 75,
		objDmg = heavy and 140 or 75,
		wall = function(_, _, obj)
			if heavy and c.p60 and obj and obj.hp < 150 then
				obj.data.pausedUntil = K.now() + 1
			end
		end,
	})
end

-- 2 Bullion Guard
Kit[2] = function(c)
	local f = c.f
	local n = spendCoins(f, 2)
	local amount = 60 + 50 * n
	K.shield(c, f, amount, 4, "Bullion")
	K.every(0.1, 4, function()
		local remaining = 0
		for _, sh in ipairs(f.shields) do
			if sh.name == "Bullion" then
				remaining = sh.amount
			end
		end
		if remaining <= 0 then
			K.Status.remove(f, "BullionWeight")
			return false
		end
		if c.p60 and remaining < amount / 2 then
			K.Status.remove(f, "BullionWeight")
		else
			K.debuff(c, f, "BullionWeight", { duration = 0.2, slow = 0.1, label = "Heavy", removable = false })
		end
		return true
	end)
end

-- 3 Golden Standard (recast spends a Coin to pulse)
Kit[3] = function(c)
	local f = c.f
	local pos = c:aimPoint(14)
	local standard = K.object(c, { name = "GoldenStandard", pos = pos, size = Vector3.new(0.5, 3.5, 0.5), hp = 180, duration = 6, color = GOLD, material = Enum.Material.Metal })
	standard.element = "Gold"
	local hooked = {}
	K.zone(c, {
		pos = pos,
		radius = 4,
		duration = 6,
		targets = "allies",
		includeOwner = true,
		color = GOLD,
		transparency = 0.85,
		enter = function(_, a)
			hooked[a] = K.hook(a, "beforeDisplace", function(_, info)
				info.dist *= 0.9
			end)
		end,
		exit = function(_, a)
			if hooked[a] then
				hooked[a]()
				hooked[a] = nil
			end
		end,
		finish = function()
			for _, rm in pairs(hooked) do
				rm()
			end
		end,
	})
	local pulsed = false
	c:recast(6, function(c2)
		if pulsed or not standard.alive then
			return nil
		end
		if spendCoins(f, 1) < 1 then
			K.notify(f, "Need a Coin")
			return "keep"
		end
		pulsed = true
		K.circle(c2, pos, 4, { dmg = 70, color = GOLD, hit = function(t)
			K.knock(c2, t, pos, 2)
		end })
		if c2.p60 then
			for _, z in ipairs(K.zonesNear(pos, 4)) do
				if z.owner and K.isEnemy(f, z.owner) then
					z:remove("cleared")
					break
				end
			end
		end
	end)
end

-- 4 Ransom Ring
Kit.requires = {
	[4] = function(c)
		if (c.f.state.coins or 0) >= 2 then
			return true
		end
		return false, "Need two Coins"
	end,
}
Kit[4] = function(c)
	local f = c.f
	spendCoins(f, 2)
	local pos = c:aimPoint(12)
	local radius = (c.p60 and c.mod) and 5 or 4
	local open = false
	local clasp = K.object(c, {
		name = "Clasp",
		pos = K.ground(pos + Vector3.new(K.m(radius), 0, 0)),
		size = Vector3.new(0.8, 1, 0.8),
		hp = 120,
		duration = 4,
		color = GOLD,
		material = Enum.Material.Metal,
		onDestroy = function()
			open = true
		end,
	})
	local _ = clasp
	K.FX.ring(pos, K.m(radius), GOLD, 4, 0.4)
	local punished = {}
	K.zone(c, {
		pos = pos,
		radius = radius,
		duration = 4,
		color = GOLD,
		transparency = 0.9,
		exit = function(_, t)
			if not open and K.isEnemy(f, t) and not punished[t] then
				punished[t] = true
				K.dmg(c, t, 100, { kind = "direct", fromPos = pos })
			end
		end,
	})
end

-- 5 Treasury of the Sun (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	-- stored Coins enlarge the circles by 0.25 m each (max 1.5 m); the unstable drop consumes them all
	local coinsSpent = spendCoins(f, 6)
	local radius = 3 + math.min(1.5, coinsSpent * 0.25)
	local giants = {}
	for i = 0, 2 do
		local a = math.rad(i * 120)
		local p = center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(3.5) + Vector3.new(0, K.m(6), 0)
		giants[i + 1] = K.object(c, {
			name = "GiantCoin",
			shape = "Cylinder",
			cf = CFrame.new(p) * CFrame.Angles(0, 0, math.rad(90)),
			size = Vector3.new(0.5, 3, 3),
			hp = 160,
			duration = 8,
			isUlt = true,
			color = GOLD,
			material = Enum.Material.Metal,
		})
	end
	local function drop(o, totals)
		if not o.alive then
			return
		end
		local ground = K.ground(o.part.Position)
		K.telegraph(c, ground, radius, 0.4, GOLD)
		task.wait(0.4)
		if not o.alive then
			return
		end
		S.Objects.remove(o, "dropped")
		K.FX.beam(o.part.Position, ground, K.m(1.5), GOLD, 0.2)
		for _, t in ipairs(K.enemiesIn(c, ground, radius)) do
			local d = totals and math.min(100, 300 - (totals[t] or 0)) or 100
			if d > 0 then
				if totals then
					totals[t] = (totals[t] or 0) + d
				end
				K.dmg(c, t, d, { fromPos = ground + Vector3.new(0, 10, 0) })
			end
		end
	end
	if c.unstable then
		local totals = {}
		for _, o in ipairs(giants) do
			K.spawn(drop, o, totals)
		end
		K.debuff(c, f, "GildedBurden", { duration = 4, slow = 0.2, removable = false, label = "Gilded Burden" })
		return
	end
	c:recast(8, function(c2)
		local aim = c2:aimPoint(30)
		local best, bd
		for _, o in ipairs(giants) do
			if o.alive then
				local d = K.flatDist(o.part.Position, aim)
				if not bd or d < bd then
					best, bd = o, d
				end
			end
		end
		if best then
			drop(best)
		end
		for _, o in ipairs(giants) do
			if o.alive then
				return "keep"
			end
		end
		return nil
	end)
end

return Kit
