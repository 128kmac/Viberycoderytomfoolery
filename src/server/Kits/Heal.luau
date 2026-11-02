-- 41 Heal — Triage and interruptible restoration
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local GREEN = Color3.fromRGB(110, 255, 140)

-- Passive: Triage Priority — allies below 35% receive +15% (once per ally per 4 s); never self
local function triage(c, t, amount)
	local f = c.f or c
	f.state.triage = f.state.triage or {}
	if t ~= f and not t.isSummon and t.health < t.maxHealth * 0.35 then
		local last = f.state.triage[t]
		if not last or K.now() - last >= 4 then
			f.state.triage[t] = K.now()
			amount *= 1.15
		end
	end
	return K.heal(c, t, amount)
end
Kit.triage = triage

-- 1 Mending Ray
Kit[1] = function(c)
	local f = c.f
	local origin = c:chest()
	local dir = c:dir3()
	local selected = c:ally(18)
	if selected then
		dir = (selected.root.Position - origin).Unit
	end
	local res = K.Hit.raycast(origin, dir * K.m(18))
	local endPos = res and res.Position or origin + dir * K.m(18)
	local hits = K.Hit.segment(origin, endPos, K.m(0.3), function(t)
		return t ~= f and not t.isSummon or (t.isSummon and K.isEnemy(f, t))
	end)
	local first = hits[1] and hits[1].f
	if first then
		endPos = first.root.Position
		if K.isAlly(f, first) then
			local low = first.health < first.maxHealth * 0.35
			triage(c, first, 95)
			if c.p60 and low then
				K.cleanse(first, "slow", 1)
			end
		else
			K.dmg(c, first, 55, { beam = true })
		end
	end
	K.FX.beam(origin, endPos, 0.35, GREEN, 0.25)
end

-- 2 Emergency Dressing
Kit[2] = function(c)
	local f = c.f
	local ally = c:ally(10)
	local amount = 100
	if not ally then
		if c.p60 then
			ally = f
			amount = 80
		else
			K.notify(f, "No ally in range")
			return
		end
	end
	K.shield(c, ally, amount, 3, "Dressing")
	K.after(2.95, function()
		for _, sh in ipairs(ally.shields) do
			if sh.name == "Dressing" and sh.amount > 0 then
				triage(c, ally, 40)
				break
			end
		end
	end)
end

-- 3 Cleanse Pulse (prioritises hard control, then damage-over-time, then slows)
Kit[3] = function(c)
	local f = c.f
	K.FX.burst(c:chest(), K.m(5), GREEN, 0.35)
	for _, a in ipairs(K.alliesIn(c, f.root.Position, 5, true)) do
		local removed = false
		for _, name in ipairs({ "stun", "sleep", "root", "lift" }) do
			if K.has(a, name) then
				K.Status.remove(a, name, "cleansed")
				removed = true
				break
			end
		end
		if not removed then
			removed = K.cleanse(a, "dot", 1) > 0
		end
		if not removed then
			removed = K.cleanse(a, "slow", 1) > 0
		end
		if not removed then
			removed = K.cleanse(a, nil, 1) > 0
		end
		if removed then
			K.heal(c, a, 30)
		end
	end
end

-- 4 Field Clinic
Kit[4] = function(c)
	local pos = c:aimPoint(14)
	local station = K.object(c, { name = "FieldClinic", pos = pos, size = Vector3.new(1.2, 1.6, 1.2), hp = 180, duration = 6, color = GREEN, material = Enum.Material.Neon, transparency = 0.2 })
	K.every(1, 6, function()
		if not station.alive then
			return false
		end
		local from = station.part.Position + Vector3.new(0, 1, 0)
		local list = {}
		for _, a in ipairs(K.alliesIn(c, pos, 5, true)) do
			if a.health < a.maxHealth and K.Hit.los(from, a.root.Position) then
				table.insert(list, a)
			end
		end
		table.sort(list, function(x, y)
			return x.health / x.maxHealth < y.health / y.maxHealth
		end)
		if list[1] then
			K.FX.beam(from, list[1].root.Position, 0.2, GREEN, 0.3)
			triage(c, list[1], 25)
		end
		if c.p60 and list[2] then
			K.FX.beam(from, list[2].root.Position, 0.15, GREEN, 0.3)
			triage(c, list[2], 15)
		end
		return true
	end)
end

-- 5 Refuse the Ending (ultimate)
Kit[5] = function(c)
	local f = c.f
	local allies = K.alliesIn(c, f.root.Position, 16, true)
	table.sort(allies, function(x, y)
		return x.health / x.maxHealth < y.health / y.maxHealth
	end)
	local amount = c.unstable and 180 or 100
	for i = 1, math.min(3, #allies) do
		local a = allies[i]
		if K.los(f, a) or a == f then
			triage(c, a, 120)
			K.mark(c, a, "Refused", 5, { harmful = false, label = "Refuse the Ending", color = GREEN })
			local triggered = false
			K.hook(a, "taken", function(t)
				if not triggered and t.health > 0 and t.health < t.maxHealth * 0.2 then
					triggered = true
					K.shield(c, t, amount, 4, "RefuseEnding")
					if c.unstable and t ~= f then
						-- Overextended Triage: transferred damage bypasses the caster's shields
						K.Combat.damage(nil, f, 80, { kind = "true", pierceShield = true, tag = "transfer" })
					end
				end
			end, 5)
		end
	end
end

return Kit
