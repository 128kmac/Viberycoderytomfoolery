-- 16 Corrupt — Hostile modification of battlefield objects
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local PURPLE = Color3.fromRGB(110, 0, 130)

local function infectPlayer(c, t, n)
	return K.debuff(c, t, "Infection", { duration = 5, stacks = n or 1, max = 3, shieldShred = 0.05, category = "infection", label = "Infection" })
end

local function objStacks(o)
	local inf = o.data.infection
	if inf and inf.expires > K.now() then
		return inf.stacks
	end
	return 0
end

local function infectObj(c, o, n)
	if not o.alive or o.tags.protected then
		return 0
	end
	local inf = o.data.infection
	if not inf or inf.expires <= K.now() then
		inf = { stacks = 0 }
		o.data.infection = inf
	end
	inf.stacks = math.min(3, inf.stacks + (n or 1))
	inf.expires = K.now() + 5
	if o.label then
		o.label.Text = tostring(math.floor(o.hp)) .. "  [INF " .. inf.stacks .. "]"
		o.label.TextColor3 = Color3.fromRGB(220, 120, 255)
	end
	if not o.data.infHl and o.part then
		o.data.infHl = K.FX.highlight(o.part, PURPLE, 5, 0.6)
	end
	return inf.stacks
end

-- Passive: Infection Ledger
function Kit.passive.dealt(f, target, info)
	if info.kind == "direct" and info.opts.cast and not info.opts.isBasic then
		infectPlayer(f, target, 1)
	end
end

local function findInfected(c, rangeM, minStacks)
	local pos = c:aimPoint(rangeM)
	local best, bd
	for _, o in ipairs(K.objects(c, pos, 4)) do
		if objStacks(o) >= (minStacks or 1) and not o.isUlt then
			local d = (o.part.Position - pos).Magnitude
			if not bd or d < bd then
				best, bd = o, d
			end
		end
	end
	if best then
		return best, "object"
	end
	for _, t in ipairs(K.enemies(c.f, rangeM)) do
		if t.isSummon and K.stacks(t, "Infection") >= (minStacks or 1) then
			return t, "summon"
		end
	end
	return nil
end

-- 1 Black Patch
Kit[1] = function(c)
	K.proj(c, {
		range = 20,
		width = 0.4,
		color = PURPLE,
		shape = "Block",
		size = Vector3.new(0.5, 0.5, 1.2),
		dmg = 60,
		objDmg = 80,
		wall = function(pos, _, obj)
			if obj then
				infectObj(c, obj, 2)
				if c.p60 then
					for _, o in ipairs(K.objects(c, obj.part.Position, 3)) do
						if o ~= obj then
							infectObj(c, o, 1)
							break
						end
					end
				end
			end
			local _ = pos
		end,
	})
end

-- 2 Fault Injection
Kit.requires = {
	[2] = function(c)
		if findInfected(c, 14, 1) then
			return true
		end
		return false, "No infected construct"
	end,
	[3] = function(c)
		if findInfected(c, 12, 3) then
			return true
		end
		return false, "Needs a three-stack construct"
	end,
}
Kit[2] = function(c)
	local target, kind = findInfected(c, 14, 1)
	if not target then
		return
	end
	if kind == "object" then
		local dur = (c.p60 and objStacks(target) >= 3) and 3 or 2
		target.data.pausedUntil = K.now() + dur
		K.FX.highlight(target.part, Color3.fromRGB(255, 255, 255), dur, 0.3)
	else
		local dur = (c.p60 and K.stacks(target, "Infection") >= 3) and 3 or 2
		K.Status.apply(target, "stun", { duration = dur, source = c.f, category = "control", label = "Paused" })
	end
end

-- 3 Borrowed Ownership
Kit[3] = function(c)
	local f = c.f
	local target, kind = findInfected(c, 12, 3)
	if not target then
		return
	end
	if kind == "object" then
		local prevOwner = target.owner
		target.owner = f
		if c.p60 then
			target.part.CFrame += K.flat(c:aimPoint(12) - target.part.Position) * K.m(2)
		end
		K.FX.highlight(target.part, PURPLE, 4, 0.4)
		K.after(4, function()
			if target.alive then
				target.owner = prevOwner
			end
		end)
	else
		local prevOwner, prevTeam = target.owner, target.team
		target.owner = f
		target.team = f.team
		target.sm.target = nil
		local dealt = 0
		local rm = K.hook(target, "beforeDeal", function(_, _, info)
			local amt = math.min(info.amount, 100 - dealt)
			dealt += amt
			info.amount = amt
			if amt <= 0 then
				info.cancel = true
			end
		end, 4)
		local _ = rm
		K.after(4, function()
			if K.alive(target) then
				target.owner = prevOwner
				target.team = prevTeam
				target.sm.target = nil
			end
		end)
	end
end

-- 4 Quarantine Ring
Kit[4] = function(c)
	local f = c.f
	local pos = c:aimPoint(16)
	local zone
	local core = K.object(c, {
		name = "QuarantineCore",
		pos = pos,
		size = Vector3.new(1, 1.5, 1),
		hp = 140,
		duration = 5,
		color = PURPLE,
		material = Enum.Material.Neon,
		onDestroy = function()
			if zone and zone.alive then
				zone:remove("core destroyed")
			end
		end,
	})
	local _ = core
	zone = K.zone(c, {
		pos = pos,
		radius = 5,
		duration = 5,
		tick = 0.5,
		immediate = true,
		targets = "all",
		color = PURPLE,
		transparency = 0.8,
		tickFn = function(z, list)
			for _, t in ipairs(list) do
				if K.isEnemy(f, t) and not t.isSummon then
					K.debuff(c, t, "Quarantined", { duration = 0.7, shieldIn = 0.75, label = "Shields -25%" })
				end
			end
			for _, o in ipairs(K.enemyObjects(c, z.pos, 5)) do
				o.data.noRepairUntil = K.now() + 0.7
			end
		end,
		enter = function(_, t, first)
			if c.p60 and first and K.isAlly(f, t) and t ~= f then
				K.cleanse(t, "infection", 1)
			end
		end,
	})
end

-- 5 System Rot (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	local erupted = {}
	local function erupt(o)
		local pos = o.part.Position
		K.FX.burst(pos, K.m(2), PURPLE, 0.3)
		for _, t in ipairs(K.enemiesIn(c, K.ground(pos), 2)) do
			if (erupted[t] or 0) < 2 then
				erupted[t] = (erupted[t] or 0) + 1
				K.dmg(c, t, 70, { fromPos = pos })
			end
		end
	end
	for pulse = 1, 3 do
		K.telegraph(c, center, 7, 0.3, PURPLE)
		task.wait(pulse == 1 and 0.3 or 0.7)
		K.circle(c, center, 7, { dmg = 65, color = PURPLE, hit = function(t)
			infectPlayer(c, t, 1)
		end })
		for _, o in ipairs(K.objects(c, center, 7, function(o)
			return not o.isUlt and o.owner ~= f
		end)) do
			if infectObj(c, o, 1) >= 3 and not o.data.rotErupted then
				o.data.rotErupted = true
				erupt(o)
			end
		end
	end
	if c.unstable then
		-- spread one extra stack through connected constructs; each processes one spread event
		local processed = {}
		local frontier = {}
		for _, o in ipairs(K.objects(c, center, 7)) do
			if objStacks(o) > 0 then
				table.insert(frontier, o)
			end
		end
		while #frontier > 0 do
			local o = table.remove(frontier, 1)
			if not processed[o] and o.alive then
				processed[o] = true
				infectObj(c, o, 1)
				for _, n in ipairs(K.objects(c, o.part.Position, 4)) do
					if not processed[n] and not n.isUlt then
						table.insert(frontier, n)
					end
				end
			end
		end
		-- Root Corruption price: stolen objects and shield generation are disabled for 6 s
		f.noShieldGen = K.now() + 6
		for _, o in pairs(S.Objects.list) do
			if o.owner == f and o.data.infection then
				o.owner = nil
			end
		end
	end
end

return Kit
