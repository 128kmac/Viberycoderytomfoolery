-- 49 Insect — Chitin, brood commands, and controlled infestation
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local GREEN = Color3.fromRGB(120, 140, 30)
local SPEC = {
	Stinger = { color = Color3.fromRGB(230, 200, 40), size = Vector3.new(0.5, 0.4, 0.8) },
	Beetle = { color = Color3.fromRGB(60, 80, 40), size = Vector3.new(0.9, 0.5, 1) },
	Scout = { color = Color3.fromRGB(160, 200, 120), size = Vector3.new(0.4, 0.3, 0.6) },
}
local SLOTS = { "Stinger", "Stinger", "Beetle", "Scout" }

local function hive(f)
	local h = f.state.hive
	if h and h.alive then
		return h
	end
	return nil
end

local function spawnInsect(f, kind, hp, dur)
	local spec = SPEC[kind]
	local pos = (hive(f) and hive(f).part.Position or f.root.Position) + Vector3.new(math.random(-3, 3), 3, math.random(-3, 3))
	local s = K.summon(f, { name = kind, pos = pos, hp = hp or 45, duration = dur, speed = 11, size = spec.size, color = spec.color, flying = 2.5, ai = "follow" })
	return s
end

local function insects(f, kind)
	return K.summons(f, kind)
end

local function show(f)
	K.res(f, "Brood", #insects(f, "Stinger") .. "S " .. #insects(f, "Beetle") .. "B " .. #insects(f, "Scout") .. "Sc", nil, 1)
end

-- Passive: Brood Slots — two Stingers, one Beetle, one Scout; regrow after 6 s at a hive, else 10 s
function Kit.passive.init(f)
	f.state.regrow = {}
	K.after(0.5, function()
		if f.kitName == "Insect" and not f.dead then
			for _, kind in ipairs(SLOTS) do
				spawnInsect(f, kind)
			end
			show(f)
		end
	end)
end
function Kit.passive.cleanup(f)
	for _, s in ipairs(K.summons(f)) do
		S.Summons.remove(s, "cleanup")
	end
end
function Kit.passive.tick(f, dt, now)
	local need = { Stinger = 2, Beetle = 1, Scout = 1 }
	for kind, n in pairs(need) do
		local have = #insects(f, kind)
		local pending = 0
		for _, r in ipairs(f.state.regrow) do
			if r.kind == kind then
				pending += 1
			end
		end
		for _ = 1, n - have - pending do
			table.insert(f.state.regrow, { kind = kind, at = now + (hive(f) and 6 or 10) })
		end
	end
	for i = #f.state.regrow, 1, -1 do
		local r = f.state.regrow[i]
		if now >= r.at then
			table.remove(f.state.regrow, i)
			spawnInsect(f, r.kind)
		end
	end
	show(f)
end

local function sting(c, s, t, dmg, onDone)
	s.sm.ai = "chase"
	S.Summons.command(s, t)
	K.every(0.1, 3, function()
		if not K.alive(s) or not K.alive(t) then
			return false
		end
		if K.dist(s, t) <= 2 then
			K.Combat.damage(s, t, dmg, { fromSummon = true, element = "Insect" })
			if K.partner(c, "Poison", 20) then
				K.dot(c, t, "Venom", 15, 3, "poison")
			end
			s.sm.ai = "follow"
			s.sm.target = nil
			if onDone then
				onDone(s)
			end
			return false
		end
		return true
	end)
end

-- 1 Stinging Order
Kit.requires = {
	[1] = function(c)
		if #insects(c.f, "Stinger") == 0 then
			return false, "No Stingers"
		end
		if not c:target(18) then
			return false, "No target"
		end
		return true
	end,
	[2] = function(c)
		if #insects(c.f, "Beetle") > 0 then
			return true
		end
		return false, "Beetle is regrowing"
	end,
	[3] = function(c)
		if #insects(c.f, "Scout") > 0 then
			return true
		end
		return false, "Scout is regrowing"
	end,
}
Kit[1] = function(c)
	local t = c:target(18)
	local list = insects(c.f, "Stinger")
	local second = c.p60
	for i = 1, math.min(2, #list) do
		sting(c, list[i], t, 35, function(s)
			if second then
				second = false
				K.after(0.4, function()
					if K.alive(s) and K.alive(t) then
						sting(c, s, t, 35)
					end
				end)
			end
		end)
	end
end

-- 2 Beetle Buckler
Kit[2] = function(c)
	local f = c.f
	local beetle = insects(f, "Beetle")[1]
	local ward = f
	if c.p60 then
		ward = c:ally(10) or f
	end
	beetle.sm.ai = "none"
	local budget = 100
	K.every(0.03, 3, function()
		if not K.alive(beetle) or not K.alive(ward) then
			return false
		end
		local fwd = K.flat(ward.root.CFrame.LookVector)
		beetle.root.CFrame = CFrame.new(ward.root.Position + fwd * K.m(1) + Vector3.new(0, 0.5, 0))
		return true
	end)
	K.hook(ward, "beforeTake", function(_, info)
		if budget > 0 and info.opts.projectile and K.alive(beetle) and K.Combat.facingAngle(ward, info.fromPos) <= 60 then
			local take = math.min(budget, info.amount)
			budget -= take
			info.amount -= take
			if info.amount <= 0 then
				info.cancel = true
			end
		end
	end, 3)
	K.after(3, function()
		if K.alive(beetle) then
			beetle.sm.ai = "follow"
		end
	end)
end

-- 3 Scout Dust
Kit[3] = function(c)
	local f = c.f
	local scout = insects(f, "Scout")[1]
	local pos = c:aimPoint(16)
	S.Summons.moveTo(scout, pos)
	scout.sm.ai = "stay"
	local z = K.zone(c, {
		pos = pos,
		radius = 4,
		duration = 4,
		dmg = 15,
		color = Color3.fromRGB(200, 190, 120),
		transparency = 0.7,
		tickFn = function(zz, list)
			if not K.alive(scout) then
				zz:remove("scout destroyed")
				return
			end
			for _, t in ipairs(list) do
				if t.humanoid and t.humanoid.MoveDirection.Magnitude > 0.1 then
					K.reveal(c, t, 1.2)
				end
			end
		end,
		finish = function()
			if K.alive(scout) then
				scout.sm.ai = "follow"
			end
		end,
	})
	if c.p60 then
		c:recast(4, function(c2)
			local d = K.flat(c2:aimPoint(20) - z.pos)
			z:move(z.pos + d * K.m(2))
			S.Summons.moveTo(scout, z.pos)
		end)
	end
end

-- 4 Hive Stake
Kit[4] = function(c)
	local f = c.f
	if hive(f) then
		S.Objects.remove(hive(f), "replaced")
	end
	for _, s in ipairs(insects(f, "HiveStinger")) do
		S.Summons.remove(s, "replaced")
	end
	local h = K.object(c, { name = "Hive", pos = c:aimPoint(12), size = Vector3.new(1.6, 2.2, 1.6), shape = "Ball", hp = 220, duration = 10, color = GREEN, material = Enum.Material.Sand })
	if c.p60 then
		S.Objects.reinforce(h, 60)
	end
	f.state.hive = h
	local extra = spawnInsect(f, "Stinger", 45, 10)
	extra.model.Name = "HiveStinger"
	extra.sm.ai = "chase"
	extra.sm.attack = { range = 2, dmg = 20, interval = 1.5 }
	h.cleanup = function()
		if K.alive(extra) then
			S.Summons.remove(extra, "hive gone")
		end
	end
end

-- 5 Brood Eclipse (ultimate)
Kit[5] = function(c)
	local f = c.f
	local swarm = {}
	for _ = 1, 12 do
		local s = K.summon(c, { name = "Brood", pos = f.root.Position + Vector3.new(math.random(-4, 4), 3, math.random(-4, 4)), hp = 25, duration = 6, speed = 12, size = Vector3.new(0.4, 0.3, 0.5), color = GREEN, flying = 3, ai = "follow" })
		table.insert(swarm, s)
	end
	local waves = c.unstable and 4 or 3
	local per = math.floor(12 / waves)
	local wave = 0
	c:recast(6, function(c2)
		wave += 1
		local t = c2:target(25) or K.nearestEnemy(f, 25)
		if t then
			local totals = 0
			local sent = 0
			for _, s in ipairs(swarm) do
				if sent >= per then
					break
				end
				if K.alive(s) and not s.data.sent then
					s.data.sent = true
					sent += 1
					s.sm.ai = "chase"
					S.Summons.command(s, t)
					K.every(0.1, 3, function()
						if not K.alive(s) or not K.alive(t) then
							return false
						end
						if K.dist(s, t) <= 2 then
							local d = math.min(30, 90 - totals)
							if d > 0 then
								totals += d
								K.Combat.damage(s, t, d, { fromSummon = true, element = "Insect" })
							end
							S.Summons.remove(s, "struck")
							return false
						end
						return true
					end)
				end
			end
		end
		if wave < waves then
			return "keep"
		end
		if c.unstable then
			K.after(3, function()
				if hive(f) then
					S.Objects.remove(hive(f), "consumed")
				end
				for _, kind in ipairs({ "Stinger", "Beetle", "Scout" }) do
					for _, s in ipairs(insects(f, kind)) do
						S.Summons.remove(s, "locust hunger")
					end
				end
			end)
		end
		return nil
	end)
end

return Kit
