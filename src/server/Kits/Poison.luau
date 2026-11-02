-- 70 Poison — Exposure management and gradual attrition
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local VIOLET = Color3.fromRGB(130, 40, 200)

-- Passive: Toxic Load — each Load deals 5/s for 5 s; refreshes never reset the tick clock; a cleanse removes all
local function load(f, t, n)
	if t.isSummon then
		return
	end
	local st = K.debuff(f, t, "Load", {
		duration = 5,
		stacks = n or 1,
		max = 4,
		category = "poison",
		tick = 1,
		label = "Toxic Load",
		data = { cleanseAll = true },
		onTick = function(tt, s)
			K.Combat.damage(s.source, tt, 5 * s.stacks, { kind = "dot", noGuard = true, element = "Poison", tag = "Load" })
		end,
	})
	if st then
		st.data.cleanseAll = true
	end
	return st
end
Kit.load = load

-- 1 Venom Fang
Kit[1] = function(c)
	K.proj(c, {
		range = c.p60 and 14 or 10,
		width = 0.3,
		shape = "Block",
		size = Vector3.new(0.3, 0.3, 1.2),
		color = VIOLET,
		hit = function(t)
			local full = K.stacks(t, "Load") >= 4
			K.dmg(c, t, full and 75 or 55, { projectile = true })
			load(c.f, t, 1)
		end,
	})
end

-- 2 Spore Ampoule
Kit[2] = function(c)
	local f = c.f
	local radius = c.p60 and 3.5 or 3
	K.lob(c, {
		range = 16,
		speed = 18,
		width = 0.5,
		color = VIOLET,
		land = function(pos)
			local inside = {}
			local applied = {}
			local cloud = K.FX.sphere(K.ground(pos) + Vector3.new(0, K.m(1), 0), K.m(radius), Color3.fromRGB(150, 80, 200), 5, 0.6)
			local _ = cloud
			K.zone(c, {
				pos = K.ground(pos),
				radius = radius,
				duration = 5,
				tick = 0.25,
				immediate = true,
				color = VIOLET,
				transparency = 0.85,
				tags = { cloud = true },
				tickFn = function(_, list)
					local now = {}
					for _, t in ipairs(list) do
						if K.isEnemy(f, t) then
							now[t] = true
							inside[t] = (inside[t] or 0) + 0.25
							if inside[t] >= 1 and (applied[t] or 0) < 2 then
								inside[t] = 0
								applied[t] = (applied[t] or 0) + 1
								load(f, t, 1)
							end
						end
					end
					for t in pairs(inside) do
						if not now[t] then
							inside[t] = 0 -- brief crossings do not apply it
						end
					end
				end,
			})
		end,
	})
end

-- 3 Antidote Exchange
Kit[3] = function(c)
	local f = c.f
	local who = c:ally(8, true) or f
	local removed = false
	for _, st in pairs(who.statuses) do
		if st.category == "poison" and st.harmful then
			K.Status.remove(who, st.name, "cleansed")
			removed = true
		end
	end
	K.shield(c, who, c.p60 and 90 or 60, 3, "Antidote")
	if removed then
		local pos = K.feet(who) + K.flat(who.root.CFrame.RightVector) * K.m(1.5)
		local vial = K.object(c, { name = "AntidoteVial", pos = pos, size = Vector3.new(0.4, 0.8, 0.4), hp = 80, duration = 8, solid = false, color = Color3.fromRGB(150, 255, 200), material = Enum.Material.Neon })
		K.every(0.1, 8, function()
			if not vial.alive then
				return false
			end
			for _, a in ipairs(K.alliesIn(c, pos, 1.3, true)) do
				if a ~= who and not a.isSummon then
					K.cleanse(a, nil, 1)
					S.Objects.remove(vial, "claimed")
					return false
				end
			end
			return true
		end)
	end
end

-- 4 Catalyst Pin
Kit[4] = function(c)
	K.proj(c, {
		range = 16,
		speed = 30,
		width = 0.3,
		shape = "Block",
		size = Vector3.new(0.25, 0.25, 1.4),
		color = VIOLET,
		hit = function(t)
			local n = K.stacks(t, "Load")
			K.Status.remove(t, "Load", "cashout")
			K.dmg(c, t, 70 + 25 * n, { projectile = true })
			if c.p60 and n >= 4 then
				load(c.f, t, 1)
			end
		end,
	})
end

-- 5 Garden of Venom (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(18)
	local pods = {}
	for i = 0, 3 do
		local a = math.rad(i * 90 + 45)
		local d = Vector3.new(math.cos(a), 0, math.sin(a))
		local o = K.object(c, { name = "VenomPod", pos = K.ground(center + d * K.m(5)), size = Vector3.new(1.2, 1, 1.2), shape = "Ball", hp = 100, duration = 7, isUlt = true, color = VIOLET, material = Enum.Material.SmoothPlastic })
		o.data.dir = -d
		table.insert(pods, o)
	end
	local beat = 0
	K.every(2, 7, function()
		beat += 1
		if c.unstable and beat == 1 then
			-- Toxic Bloom: pods advance inward instead of the first puff
			for _, o in ipairs(pods) do
				if o.alive then
					o.part.CFrame += o.data.dir * K.m(2)
				end
			end
			return true
		end
		local hitThisBeat = {}
		for _, o in ipairs(pods) do
			if o.alive then
				local pos = K.ground(o.part.Position)
				K.FX.burst(pos + Vector3.new(0, 1, 0), K.m(2.5), VIOLET, 0.3)
				local list = c.unstable and K.Hit.cylinder(pos, K.m(2.5), function()
					return true
				end) or K.enemiesIn(c, pos, 2.5)
				for _, t in ipairs(list) do
					if not hitThisBeat[t] then
						hitThisBeat[t] = true
						K.Combat.damage(f, t, 40, { cast = c, isUlt = true, fromPos = pos, element = "Poison" })
						if K.isEnemy(f, t) then
							load(f, t, 1)
						end
					end
				end
			end
		end
		return true
	end)
end

return Kit
