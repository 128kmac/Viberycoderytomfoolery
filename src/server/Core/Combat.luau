-- Damage / protection / healing / control pipeline (Compendium: "Resolve each impact once").
local S = require(script.Parent.S)
local Status = require(script.Parent.Status)

local Combat = {}
S.Combat = Combat

local Config = S.Config

local remotes -- set by init
function Combat.init(r)
	remotes = r
end

local function hook(f, name, ...)
	local h = f and f.hooks and f.hooks[name]
	if h then
		local ok, res = pcall(h, f, ...)
		if not ok then
			warn("[EB] hook " .. name .. " failed for " .. tostring(f.kitName) .. ": " .. tostring(res))
			return nil
		end
		return res
	end
	return nil
end
Combat.hook = hook

local function extraHooks(f, name, ...)
	if f and f.extraHooks and f.extraHooks[name] then
		for _, fn in ipairs(table.clone(f.extraHooks[name])) do
			local ok, err = pcall(fn, f, ...)
			if not ok then
				warn("[EB] extra hook " .. name .. ": " .. tostring(err))
			end
		end
	end
end
Combat.extraHooks = extraHooks

-- temporary hook registration (stances, marks, transformations). Returns remover.
function Combat.addHook(f, name, fn)
	f.extraHooks = f.extraHooks or {}
	f.extraHooks[name] = f.extraHooks[name] or {}
	table.insert(f.extraHooks[name], fn)
	return function()
		local l = f.extraHooks and f.extraHooks[name]
		if l then
			local i = table.find(l, fn)
			if i then
				table.remove(l, i)
			end
		end
	end
end

local function pop(pos, text, color, kind)
	if remotes and remotes.Pop then
		remotes.Pop:FireAllClients(pos, text, color, kind)
	end
end
Combat.pop = pop

local function facingAngle(target, fromPos)
	if not fromPos then
		return 0
	end
	local look = target.root.CFrame.LookVector
	local to = fromPos - target.root.Position
	local flatTo = Vector3.new(to.X, 0, to.Z)
	if flatTo.Magnitude < 0.1 then
		return 0
	end
	local flatLook = Vector3.new(look.X, 0, look.Z).Unit
	return math.deg(math.acos(math.clamp(flatLook:Dot(flatTo.Unit), -1, 1)))
end
Combat.facingAngle = facingAngle

function Combat.isInvulnerable(f)
	local now = S.now()
	return (f.iframeUntil and f.iframeUntil > now) or (f.invulnUntil and f.invulnUntil > now) or (f.invulnCount or 0) > 0
end

-- Proxima helpers -------------------------------------------------------------
function Combat.addProxima(f, amount, reason)
	if f.isSummon or f.rupturePending or amount <= 0 then
		return 0
	end
	local now = S.now()
	-- 10 P/s cap from all sources (rolling 1s window)
	f.pWindow = f.pWindow or {}
	local sum = 0
	for i = #f.pWindow, 1, -1 do
		local e = f.pWindow[i]
		if now - e.t > 1 then
			table.remove(f.pWindow, i)
		else
			sum += e.a
		end
	end
	local allowed = math.max(0, Config.P_MAX_PER_SECOND - sum)
	local gain = math.min(amount, allowed, Config.MAX_PROXIMA - f.proxima)
	if gain > 0 then
		table.insert(f.pWindow, { t = now, a = gain })
		f.proxima += gain
	end
	return gain
end

function Combat.contest(a, b)
	if not (S.isReal(a) and S.isReal(b)) then
		return
	end
	if not S.isEnemy(a, b) then
		return
	end
	local now = S.now()
	a.contest[b] = now
	b.contest[a] = now
	a.lastContest = now
	b.lastContest = now
end

local function FXwarn(f)
	if S.FX and f.model then
		S.FX.text(f.root, "RUPTURE PENDING", Color3.fromRGB(255, 80, 40), 2)
	end
end

function Combat.addHeat(f, amount)
	if amount <= 0 then
		return
	end
	f.heat = math.min(Config.MAX_HEAT, f.heat + amount)
	f.lastAbilityUse = S.now()
	if f.heat >= Config.MAX_HEAT and not f.rupturePending and not (f.burnoutUntil and f.burnoutUntil > S.now()) then
		f.rupturePending = true
		FXwarn(f)
	end
end

function Combat.spendEnergy(f, amount)
	if amount <= 0 then
		return true
	end
	if f.energy < amount then
		return false
	end
	f.energy -= amount
	f.lastEnergySpend = S.now()
	return true
end

function Combat.addEnergy(f, amount)
	f.energy = math.clamp(f.energy + amount, 0, Config.MAX_ENERGY)
end

-- Shields ----------------------------------------------------------------------
function Combat.totalShield(f)
	local s = 0
	for _, sh in ipairs(f.shields) do
		s += sh.amount
	end
	return s
end

-- add a personal shield; same name replaces if higher; respects the 400 cap
function Combat.shield(target, amount, duration, name, src)
	if not S.alive(target) or amount <= 0 then
		return 0
	end
	local now = S.now()
	name = name or "shield"
	duration = duration or 4
	if src and src.noShieldGen and src.noShieldGen > now then
		return 0
	end
	if src then
		amount *= Status.shieldOutMult(src)
	end
	amount *= Status.shieldInMult(target)
	local info = { amount = amount, duration = duration, name = name, src = src }
	hook(target, "beforeShield", info)
	extraHooks(target, "beforeShield", info)
	if info.cancel then
		return 0
	end
	amount = info.amount
	for i, sh in ipairs(target.shields) do
		if sh.name == name then
			if amount > sh.amount then
				table.remove(target.shields, i)
				break
			else
				return 0
			end
		end
	end
	local room = Config.MAX_SHIELD - Combat.totalShield(target)
	amount = math.min(amount, room)
	if amount <= 0 then
		return 0
	end
	table.insert(target.shields, { amount = amount, expires = now + duration, name = name, src = src })
	table.sort(target.shields, function(a, b)
		return a.expires < b.expires
	end)
	hook(target, "shieldCreated", amount, name, src)
	extraHooks(target, "shieldCreated", amount, name, src)
	if src and src ~= target and S.isAlly(src, target) and target.lastContest and now - target.lastContest < 4 then
		Combat.addProxima(src, Config.P_SUPPORT_GAIN, "support")
	end
	pop(target.root.Position, "+" .. math.floor(amount) .. " shield", Color3.fromRGB(140, 200, 255), "shield")
	return amount
end

function Combat.removeShield(target, name, amount)
	for i = #target.shields, 1, -1 do
		local sh = target.shields[i]
		if name == nil or sh.name == name then
			if amount then
				local take = math.min(amount, sh.amount)
				sh.amount -= take
				amount -= take
				if sh.amount <= 0 then
					table.remove(target.shields, i)
				end
				if amount <= 0 then
					return
				end
			else
				table.remove(target.shields, i)
			end
		end
	end
end

local function absorb(target, amount, info)
	local absorbed = 0
	local mult = info.shieldMult or 1
	local i = 1
	while amount > 0 and i <= #target.shields do
		local sh = target.shields[i]
		local need = amount * mult
		if sh.amount > need then
			sh.amount -= need
			absorbed += amount
			amount = 0
		else
			local covers = sh.amount / mult
			absorbed += covers
			amount -= covers
			table.remove(target.shields, i)
			hook(target, "shieldBroken", sh)
			extraHooks(target, "shieldBroken", sh)
		end
	end
	return amount, absorbed
end

-- Healing ------------------------------------------------------------------------
function Combat.heal(src, target, amount, opts)
	if not S.alive(target) or amount <= 0 then
		return 0
	end
	opts = opts or {}
	if target.noHeal and not opts.force then
		return 0
	end
	local now = S.now()
	if src and src.healOutMult then
		amount *= src.healOutMult
	end
	if src and src.healOutCap then
		amount = math.min(amount, src.healOutCap)
	end
	local info = { amount = amount * Status.healMult(target), src = src, opts = opts }
	hook(target, "beforeHeal", info)
	extraHooks(target, "beforeHeal", info)
	amount = info.amount
	-- 250 health / rolling second
	target.healWindow = target.healWindow or {}
	local sum = 0
	for i = #target.healWindow, 1, -1 do
		local e = target.healWindow[i]
		if now - e.t > 1 then
			table.remove(target.healWindow, i)
		else
			sum += e.a
		end
	end
	amount = math.min(amount, Config.HEAL_CAP_PER_SECOND - sum, target.maxHealth - target.health)
	if amount <= 0 then
		return 0
	end
	table.insert(target.healWindow, { t = now, a = amount })
	target.health += amount
	if S.Fighter then
		S.Fighter.syncHealth(target)
	end
	if src and src ~= target and S.isAlly(src, target) and not opts.noProxima and target.lastContest and now - target.lastContest < 4 then
		Combat.addProxima(src, Config.P_SUPPORT_GAIN, "support")
	end
	if amount >= 1 then
		pop(target.root.Position, "+" .. math.floor(amount + 0.5), Color3.fromRGB(110, 255, 140), "heal")
	end
	hook(src, "healed", target, amount)
	return amount
end

-- Damage -----------------------------------------------------------------------
--[[ opts:
	kind = "direct" (default) | "dot" | "field" | "true" (ignores reductions)
	cast (ctx), slot, isUlt, isBasic, fromPos (for guard facing), guardDmg (extra guard damage),
	noGuard, unblockable, pierceShield, element, tag, noProxima, fromSummon, melee, projectile,
	noReduction, shieldMult, cap
]]
function Combat.damage(src, target, amount, opts)
	if not S.alive(target) or amount <= 0 then
		return 0, "invalid"
	end
	opts = opts or {}
	local now = S.now()
	if target.isDummyInvuln then
		return 0, "invalid"
	end
	if Combat.isInvulnerable(target) and opts.kind ~= "true" then
		hook(target, "evaded", src, opts)
		extraHooks(target, "evaded", src, opts)
		S.emit("evaded", target, src, opts)
		pop(target.root.Position, "EVADE", Color3.fromRGB(200, 200, 200), "info")
		return 0, "invulnerable"
	end
	local info = {
		src = src,
		target = target,
		amount = amount,
		base = amount,
		bonus = 0, -- additive % bonuses
		kind = opts.kind or "direct",
		opts = opts,
		fromPos = opts.fromPos or (src and src.root and src.root.Position),
		guardDmg = opts.guardDmg or 0,
		shieldMult = opts.shieldMult or 1,
	}
	local direct = info.kind == "direct"
	-- passive hooks (attacker then target)
	if src and src ~= target then
		hook(src, "beforeDeal", target, info)
		extraHooks(src, "beforeDeal", target, info)
	end
	hook(target, "beforeTake", info)
	extraHooks(target, "beforeTake", info)
	if info.cancel then
		return 0, info.cancelReason or "cancelled"
	end
	-- percentage bonuses add, never compound
	if src and info.kind ~= "true" then
		info.bonus += Status.dmgBonus(src)
	end
	if info.kind ~= "true" then
		info.bonus += Status.vuln(target)
	end
	local dmg = info.amount * math.max(0, 1 + info.bonus)
	if opts.cap then
		dmg = math.min(dmg, opts.cap)
	end
	local pre = dmg
	-- guard
	local guarded, perfect = false, false
	if direct and not opts.noGuard and not opts.unblockable and target.guarding and not target.isSummon then
		if facingAngle(target, info.fromPos) <= Config.GUARD_ARC / 2 then
			guarded = true
			perfect = target.guardStart and (now - target.guardStart) <= Config.PERFECT_GUARD_WINDOW
		end
	end
	local reduction = 0
	if info.kind ~= "true" and not opts.noReduction then
		reduction = Status.dr(target)
	end
	if guarded then
		local drain = pre * Config.GUARD_HIT_DRAIN + info.guardDmg
		if perfect then
			drain *= 0.5
			reduction = Config.PERFECT_GUARD_REDUCTION
			if not target.lastPerfectGuard or now - target.lastPerfectGuard >= Config.P_PERFECT_GUARD_ICD then
				target.lastPerfectGuard = now
				Combat.addProxima(target, Config.P_PERFECT_GUARD_GAIN, "perfect")
			end
			pop(target.root.Position, "PERFECT", Color3.fromRGB(255, 255, 120), "info")
			hook(target, "perfectGuard", src, info)
			extraHooks(target, "perfectGuard", src, info)
		else
			reduction = math.min(Config.MAX_COMBINED_REDUCTION, 1 - (1 - Config.GUARD_REDUCTION) * (1 - reduction))
		end
		target.guard -= drain
		target.lastGuardHit = now
		if target.guard <= 0 then
			target.guard = 0
			Combat.guardBreak(target, src)
		end
		hook(target, "guarded", src, info)
		extraHooks(target, "guarded", src, info)
	else
		reduction = math.min(reduction, Config.MAX_COMBINED_REDUCTION)
	end
	dmg = dmg * (1 - reduction)
	local prevented = pre - dmg
	-- shields
	local absorbed = 0
	if not opts.pierceShield and #target.shields > 0 then
		dmg, absorbed = absorb(target, dmg, info)
	end
	info.final = dmg
	info.absorbed = absorbed
	info.prevented = prevented
	info.guarded = guarded
	info.perfect = perfect
	-- apply to health
	if dmg > 0 then
		target.health -= dmg
		target.lastHit = now
		target.lastDamager = src and (src.owner or src) or target.lastDamager
		target.lastDamagerTime = now
	end
	if direct or info.kind == "field" then
		target.lastDirectHit = now
	end
	-- sleep breaks on damage
	if dmg > 0 and target.statuses.sleep and not target.statuses.sleep.data.noWake then
		Status.remove(target, "sleep", "woken")
	end
	-- contest + proxima
	if src and src ~= target and (direct or prevented > 0 or absorbed > 0) then
		local real = src.owner or src
		Combat.contest(real, target)
		local c = opts.cast
		if
			c
			and direct
			and not c.isUlt
			and not opts.isBasic
			and not opts.noProxima
			and not opts.fromSummon
			and not src.isSummon
			and S.isReal(target)
			and not c.pGranted
		then
			c.pGranted = true
			Combat.addProxima(src, Config.P_HIT_GAIN, "hit")
		end
	end
	-- popups
	local shown = dmg + absorbed
	if shown >= 0.5 then
		local col = guarded and Color3.fromRGB(150, 170, 255) or Color3.fromRGB(255, 220, 120)
		if absorbed > 0 and dmg <= 0 then
			col = Color3.fromRGB(140, 200, 255)
		end
		pop(target.root.Position, tostring(math.floor(shown + 0.5)), col, info.kind)
	end
	if S.Fighter then
		S.Fighter.syncHealth(target)
	end
	-- after hooks
	if src and src ~= target then
		hook(src, "dealt", target, info)
		extraHooks(src, "dealt", target, info)
		if src.isSummon and src.owner then
			hook(src.owner, "summonDealt", target, info, src)
		end
	end
	hook(target, "taken", info)
	extraHooks(target, "taken", info)
	S.emit("damaged", target, info)
	if target.health <= 0 then
		Combat.defeat(target, src, info)
	end
	return dmg + absorbed, guarded and "guarded" or "hit", info
end

function Combat.defeat(target, src, info)
	if target.dead then
		return
	end
	-- a previously committed effect may intercept defeat (e.g. Phoenix rescue)
	local saved = hook(target, "beforeDefeat", src, info)
	if not saved and target.extraHooks and target.extraHooks.beforeDefeat then
		for _, fn in ipairs(table.clone(target.extraHooks.beforeDefeat)) do
			local ok, res = pcall(fn, target, src, info)
			if ok and res then
				saved = true
				break
			end
		end
	end
	if saved and target.health > 0 then
		return
	end
	target.health = 0
	if S.Fighter then
		S.Fighter.kill(target, src)
	end
end

-- Control -------------------------------------------------------------------------
local CONTROL_LABEL = { stun = "Stun", root = "Root", sleep = "Sleep", lift = "Lifted", guardbreak = "Guard Break", lock = "Locked" }

-- Applies hard control subject to the shared 2s / 6s budget. Returns applied duration.
function Combat.control(target, kind, duration, src, opts)
	if not S.alive(target) or duration <= 0 then
		return 0
	end
	opts = opts or {}
	local now = S.now()
	if target.isSummon and target.controlImmune then
		return 0
	end
	if Combat.isInvulnerable(target) and not opts.force then
		return 0
	end
	if src and src.controlOutMult then
		duration *= src.controlOutMult
	end
	local info = { kind = kind, duration = duration, src = src }
	hook(target, "beforeControl", info)
	extraHooks(target, "beforeControl", info)
	if info.cancel then
		return 0
	end
	duration = info.duration
	if target.ccImmuneUntil and target.ccImmuneUntil > now then
		pop(target.root.Position, "IMMUNE", Color3.fromRGB(255, 255, 255), "info")
		return 0
	end
	-- rolling budget
	local used = 0
	for i = #target.controlLog, 1, -1 do
		local e = target.controlLog[i]
		if now - (e.t + e.d) > Config.CONTROL_WINDOW then
			table.remove(target.controlLog, i)
		else
			local startIn = math.max(e.t, now - Config.CONTROL_WINDOW)
			used += math.max(0, (e.t + e.d) - startIn)
		end
	end
	local budget = Config.CONTROL_BUDGET - used
	if budget <= 0.02 then
		target.ccImmuneUntil = now + Config.CONTROL_IMMUNITY
		pop(target.root.Position, "IMMUNE", Color3.fromRGB(255, 255, 255), "info")
		return 0
	end
	local applied = math.min(duration, budget)
	table.insert(target.controlLog, { t = now, d = applied })
	if applied >= budget - 0.01 then
		target.ccImmuneUntil = now + applied + Config.CONTROL_IMMUNITY
	end
	local st = Status.apply(target, kind, {
		duration = applied,
		source = src,
		category = "control",
		label = CONTROL_LABEL[kind] or kind,
		data = { noWake = opts.noWake },
	})
	if st then
		st.removable = false
	end
	if kind == "stun" or kind == "sleep" or kind == "guardbreak" or kind == "lock" then
		Combat.interrupt(target, kind)
		target.guarding = false
	end
	if kind == "lift" and S.Fighter then
		S.Fighter.applyLift(target, opts.height or S.m(2), applied)
	end
	hook(target, "controlled", kind, applied, src)
	extraHooks(target, "controlled", kind, applied, src)
	S.emit("controlled", target, kind, applied, src)
	pop(target.root.Position, (CONTROL_LABEL[kind] or kind):upper(), Color3.fromRGB(255, 200, 255), "info")
	return applied
end

function Combat.stun(t, d, src)
	return Combat.control(t, "stun", d, src)
end
function Combat.root(t, d, src)
	return Combat.control(t, "root", d, src)
end
function Combat.sleep(t, d, src)
	return Combat.control(t, "sleep", d, src)
end
function Combat.lift(t, d, src, height)
	return Combat.control(t, "lift", d, src, { height = height })
end

function Combat.guardBreak(target, src)
	target.guarding = false
	target.guardBrokenUntil = S.now() + Config.GUARD_BREAK_TIME
	local applied = Combat.control(target, "guardbreak", Config.GUARD_BREAK_TIME, src)
	if applied <= 0 then
		target.guardBrokenUntil = S.now() + 0.05
	end
	task.delay(Config.GUARD_BREAK_TIME, function()
		if S.alive(target) then
			target.guard = math.max(target.guard, Config.GUARD_BREAK_RETURN)
		end
	end)
	pop(target.root.Position, "GUARD BREAK", Color3.fromRGB(255, 120, 60), "info")
end

-- interrupt current channel/windup (named interrupt). Returns true if something was interrupted.
function Combat.interrupt(target, reason)
	local c = target.action
	if c and not c.uninterruptible then
		c.interrupted = true
		c.interruptReason = reason
		return true
	end
	return false
end

-- Displacement (distance in studs) ---------------------------------------------------
function Combat.knockback(target, fromPos, dist, src, opts)
	if not S.alive(target) or dist <= 0 then
		return
	end
	opts = opts or {}
	local info = { dist = dist, src = src, kind = "knockback" }
	hook(target, "beforeDisplace", info)
	extraHooks(target, "beforeDisplace", info)
	if info.cancel then
		return
	end
	local d = target.root.Position - fromPos
	d = Vector3.new(d.X, 0, d.Z)
	if d.Magnitude < 0.05 then
		d = -target.root.CFrame.LookVector
	end
	S.Fighter.displace(target, d.Unit, info.dist, opts.time or 0.2, opts.up)
end

function Combat.push(target, dir, dist, src, opts)
	if not S.alive(target) or dist <= 0 then
		return
	end
	opts = opts or {}
	local info = { dist = dist, src = src, kind = "push" }
	hook(target, "beforeDisplace", info)
	extraHooks(target, "beforeDisplace", info)
	if info.cancel then
		return
	end
	local d = Vector3.new(dir.X, 0, dir.Z)
	if d.Magnitude < 0.01 then
		return
	end
	S.Fighter.displace(target, d.Unit, info.dist, opts.time or 0.2, opts.up)
end

function Combat.pull(target, toPos, dist, src, opts)
	if not S.alive(target) then
		return
	end
	opts = opts or {}
	local d = toPos - target.root.Position
	d = Vector3.new(d.X, 0, d.Z)
	local maxd = d.Magnitude - S.m(0.8)
	if maxd <= 0.1 then
		return
	end
	local info = { dist = math.min(dist, maxd), src = src, kind = "pull" }
	hook(target, "beforeDisplace", info)
	extraHooks(target, "beforeDisplace", info)
	if info.cancel then
		return
	end
	S.Fighter.displace(target, d.Unit, info.dist, opts.time or 0.25)
end

return Combat
