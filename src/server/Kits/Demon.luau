-- 23 Demon — Bargained power and delayed payment
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local RED = Color3.fromRGB(200, 30, 30)

-- debt is tracked in health units: one borrowed Energy point = 2 health due in 6 seconds
local function totalDebt(f)
	local s = 0
	for _, d in ipairs(f.state.debts) do
		s += d.amount
	end
	return s
end
local function show(f)
	local d = totalDebt(f)
	if d > 0 then
		K.res(f, "Debt", math.ceil(d), nil, 1)
	else
		K.clearRes(f, "Debt")
	end
end
local function addDebt(f, health)
	table.insert(f.state.debts, { amount = health, due = K.now() + 6 })
	show(f)
end
local function repay(f, health)
	while health > 0 and #f.state.debts > 0 do
		local d = f.state.debts[1]
		local take = math.min(d.amount, health)
		d.amount -= take
		health -= take
		if d.amount <= 0 then
			table.remove(f.state.debts, 1)
		end
	end
	show(f)
end

-- Passive: Infernal Credit
function Kit.passive.init(f)
	f.state.debts = {}
	show(f)
end
function Kit.energyCredit(f, slot)
	if slot > 4 then
		return 0
	end
	local borrowedEnergy = totalDebt(f) / 2
	return math.max(0, math.min(10, 30 - borrowedEnergy))
end
function Kit.passive.borrowEnergy(f, amount)
	addDebt(f, amount * 2)
	K.announce(f, "BORROWED " .. math.floor(amount), RED, 1)
end
function Kit.passive.dealt(f, target, info)
	if info.final > 0 and not target.isSummon and not info.opts.fromSummon and #f.state.debts > 0 then
		local rate = f.state.contract and 2 or 1
		if info.opts.contractBonus then
			rate = 1
		end
		-- 4 health damage dealt repays 1 borrowed Energy (= 2 health of debt)
		repay(f, info.final * 0.5 * rate)
	end
end
function Kit.passive.tick(f)
	local now = K.now()
	for i = #f.state.debts, 1, -1 do
		local d = f.state.debts[i]
		if now >= d.due then
			table.remove(f.state.debts, i)
			K.Combat.damage(nil, f, d.amount, { kind = "true", tag = "debt" })
			show(f)
		end
	end
end
-- Hellbrand bonus
function Kit.passive.beforeDeal(f, target, info)
	local st = K.Status.get(target, "Hellbrand")
	if st and info.opts.cast and info.opts.cast.data.brandCast ~= true then
		local last = target.state.hellbrandAt or 0
		if K.now() - last >= 2 then
			target.state.hellbrandAt = K.now()
			info.amount += 25
			K.unmark(target, "Hellbrand")
		end
	end
end

-- 1 Hellbrand Claw
Kit[1] = function(c)
	c.data.brandCast = true
	K.melee(c, {
		range = 4,
		arc = 100,
		dmg = 85,
		color = RED,
		hit = function(t)
			K.mark(c, t, "Hellbrand", 4, { label = "Hellbrand", color = RED })
			if c.p60 then
				K.reveal(c, t, 4)
			end
		end,
	})
end

-- 2 Debt Collector
Kit[2] = function(c)
	local f = c.f
	K.proj(c, {
		range = 12,
		speed = 16,
		width = 0.6,
		color = RED,
		shape = "Block",
		size = Vector3.new(0.8, 0.8, 1.2),
		hit = function(t)
			local branded = K.has(t, "Hellbrand")
			K.dmg(c, t, 60, { projectile = true })
			if c.p60 and branded then
				K.dash(c, K.flat(t.root.Position - f.root.Position), math.max(0, K.flatDist(t, f) - 1.5), 0.25)
			else
				K.pull(c, t, f.root.Position, branded and 3 or 1)
			end
			K.FX.beam(f.root.Position, t.root.Position, 0.2, RED, 0.3)
		end,
	})
end

-- 3 Devil's Shelter
Kit[3] = function(c)
	local f = c.f
	K.shield(c, f, 160, 3, "DevilShelter")
	local shared
	if c.p60 then
		for _, a in ipairs(K.alliesIn(c, f.root.Position, 6, false)) do
			shared = a
			K.shield(c, a, 80, 3, "DevilShelter")
			break
		end
	end
	local _ = shared
	K.after(2.95, function()
		local remaining = 0
		for _, sh in ipairs(f.shields) do
			if sh.name == "DevilShelter" then
				remaining = sh.amount
			end
		end
		local absorbed = 160 - remaining
		if absorbed > 0 then
			addDebt(f, absorbed * 0.25)
		end
	end)
end

-- 4 Hellgate
Kit[4] = function(c)
	local f = c.f
	local pos = c:aimPoint(16)
	local gate = K.object(c, { name = "Hellgate", pos = pos, size = Vector3.new(2, 3, 0.5), hp = 120, duration = 5, color = RED, material = Enum.Material.Neon, transparency = 0.2 })
	local bolts = 3
	local stepped = false
	c:recast(5, function(c2)
		if not gate.alive then
			return nil
		end
		if c2.p60 and c2.mod and not stepped then
			stepped = true
			K.blink(c2, K.ground(gate.part.Position) + K.flat(f.root.Position - gate.part.Position) * K.m(1.5))
			return "keep"
		end
		local origin = gate.part.Position + Vector3.new(0, 1, 0)
		local t = c2:target(30)
		if t and K.Hit.los(origin, t.root.Position) then
			bolts -= 1
			K.proj(c2, { origin = origin, dir = (t.root.Position - origin).Unit, range = 30, speed = 30, width = 0.5, color = RED, dmg = 45 })
		else
			K.notify(f, "No visible target from the gate")
		end
		if bolts > 0 then
			return "keep"
		end
		return nil
	end, { uses = 1 })
end

-- 5 Pandemonium Contract (ultimate)
Kit[5] = function(c)
	local f = c.f
	local bonus = c.unstable and 0.35 or 0.2
	K.dmgBuff(f, bonus, 7, "Pandemonium")
	f.state.contract = true
	f.noEnergyRegen = true
	K.FX.highlight(f.model, RED, 7, 0.55)
	c:form(7, {
		onEnd = function()
			f.state.contract = nil
			f.noEnergyRegen = nil
			if c.unstable then
				-- Archdemon Default: unpaid debt doubles (capped at 240) and comes due now
				local d = math.min(240, totalDebt(f) * 2)
				f.state.debts = {}
				if d > 0 then
					addDebt(f, d)
					f.state.debts[1].due = K.now()
				end
			end
			show(f)
		end,
	})
end

return Kit
