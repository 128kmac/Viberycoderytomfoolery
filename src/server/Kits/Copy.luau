-- 15 Copy — Borrowed techniques with explicit restrictions
-- Copy's own data lives in f.copyState; borrowed techniques run in a sandboxed f.state so no passive,
-- resource engine or reserve of the source kit is ever inherited.
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local SILVER = Color3.fromRGB(190, 195, 215)

local function cs(f)
	f.copyState = f.copyState or {}
	return f.copyState
end

local function show(f)
	local st = cs(f)
	local bp = st.bp
	if bp and bp.expires > K.now() then
		K.res(f, "Blueprint", bp.kitName .. ": " .. bp.moveName .. string.format(" (%.0fs)", bp.expires - K.now()), nil, 1)
	else
		st.bp = nil
		K.res(f, "Blueprint", "none", nil, 1)
	end
	if st.second and st.second.expires > K.now() then
		K.res(f, "Second", st.second.kitName .. ": " .. st.second.moveName, nil, 2)
	else
		K.clearRes(f, "Second")
	end
end

local function makeBlueprint(caster, c)
	local now = K.now()
	return {
		owner = caster,
		kitName = caster.kitName,
		slot = c.slot,
		moveName = c.def.name,
		first = now,
		expires = now + 8,
		ally = false,
	}
end

-- Passive: Study Window
function Kit.passive.init(f)
	local st = cs(f)
	st.bp = nil
	st.used = {}
	if st.unsub then
		st.unsub()
	end
	st.unsub = S.on("cast", function(caster, c)
		if f.dead or f.kitName ~= "Copy" or caster == f or caster.isSummon or caster.kitName == "Copy" then
			return
		end
		if c.slot > 4 or c.isRecast or not K.alive(caster) then
			return
		end
		if K.dist(caster, f) > 18 or not K.los(f, caster) then
			return
		end
		if st.locked and st.locked > K.now() then
			return
		end
		local bp = makeBlueprint(caster, c)
		bp.ally = K.isAlly(f, caster)
		if st.protectUntil and st.protectUntil > K.now() and st.bp then
			st.second = bp
		else
			st.bp = bp
		end
		show(f)
	end)
	show(f)
end
function Kit.passive.cleanup(f)
	local st = cs(f)
	if st.unsub then
		st.unsub()
		st.unsub = nil
	end
	st.bp, st.second = nil, nil
end
function Kit.passive.tick(f)
	show(f)
end
-- borrowed output caps
function Kit.passive.beforeDeal(f, target, info)
	local c = info.opts.cast
	local b = c and c.borrowed
	if b then
		local done = b.totals[target] or 0
		local amt = math.min(info.amount * b.mult, b.cap - done)
		b.totals[target] = done + math.max(0, amt)
		if amt <= 0 then
			info.cancel = true
		end
		info.amount = math.max(0, amt)
		info.opts.noProxima = b.ally or info.opts.noProxima
	end
end

-- run a stored blueprint with Copy's fixed budgets
local function execute(c, bp, mult, cap)
	local f = c.f
	local kit = S.Kits.get(bp.kitName)
	local data = S.Kits.data(bp.kitName)
	if not kit or not data or not kit[bp.slot] then
		return false
	end
	if bp.ally then
		mult = math.min(mult, 0.5)
	end
	local def = data.moves[bp.slot]
	local cc = S.Cast.newCtx(f, bp.slot, def)
	cc.active = true
	cc.phase = "active"
	cc.borrowed = { mult = mult, cap = cap, totals = {}, ally = bp.ally }
	local req = kit.requires and kit.requires[bp.slot]
	if req then
		local ok = pcall(req, cc)
		if not ok then
			return false
		end
	end
	-- halved control, capped healing, sandboxed state
	local savedState = f.state
	f.state = {}
	f.healOutMult = mult
	f.healOutCap = 90
	f.controlOutMult = 0.5
	local ok, err = pcall(kit[bp.slot], cc)
	f.state = savedState
	K.after(3, function()
		f.healOutMult, f.healOutCap, f.controlOutMult = nil, nil, nil
	end)
	if not ok then
		-- unsupported geometry: fall back to an echo of the technique's damage
		warn("[EB] Copy fallback for " .. bp.kitName .. " " .. bp.slot .. ": " .. tostring(err))
		local dmg = tonumber(string.match(def.desc, "(%d+) damage")) or 60
		K.proj(cc, { range = math.max(8, def.range or 12), color = SILVER, dmg = dmg })
	end
	K.FX.highlight(f.model, S.Util.color(bp.kitName), 0.6, 0.6)
	return true
end

-- 1 Mimetic Bolt
Kit[1] = function(c)
	local f = c.f
	local st = cs(f)
	K.proj(c, {
		range = 20,
		width = 0.35,
		color = SILVER,
		dmg = 65,
		hit = function(t)
			local bp = st.bp
			if bp and t == bp.owner then
				bp.expires = math.min(bp.first + 16, bp.expires + 4)
				if c.p60 then
					local left = K.cdLeft(t, bp.slot)
					K.notify(f, bp.moveName .. (left > 0 and string.format(" ready in %.1fs", left) or " is READY"))
				end
				show(f)
			end
		end,
	})
end

-- 2 Borrowed Technique
Kit.requires = {
	[2] = function(c)
		local st = cs(c.f)
		if st.bp and st.bp.expires > K.now() then
			if st.perfect and st.used[st.bp.kitName .. st.bp.slot] then
				return false, "Already interpreted this technique"
			end
			return true
		end
		return false, "No blueprint stored"
	end,
	[4] = function(c)
		local st = cs(c.f)
		if st.bp and st.bp.expires > K.now() then
			return true
		end
		return false, "No blueprint stored"
	end,
}
Kit[2] = function(c)
	local f = c.f
	local st = cs(f)
	local bp = st.bp
	if not bp then
		return
	end
	local mult = c.p60 and 0.85 or 0.7
	local cap = 130
	if st.perfect then
		mult = 1
		cap = st.perfect.cap
		st.used[bp.kitName .. bp.slot] = true
		if st.perfect.heat then
			K.addHeat(f, 15)
		end
	end
	execute(c, bp, mult, cap)
	if st.perfect and st.perfect.charges > 1 then
		st.perfect.charges -= 1
		K.setCd(f, 2, 0.4)
	end
end

-- 3 Selective Memory
Kit[3] = function(c)
	local f = c.f
	local st = cs(f)
	st.protectUntil = K.now() + 5
	if st.bp then
		st.bp.expires = math.max(st.bp.expires, K.now() + 5)
	end
	c:recast(5, function(c2)
		st.protectUntil = nil
		if st.second then
			local keep, discard
			if c2.mod then
				keep, discard = st.bp, st.second
			else
				keep, discard = st.second, st.bp
			end
			st.bp = keep
			st.second = nil
			if c2.p60 and discard then
				K.addEnergy(f, 8)
			end
		end
		show(f)
	end, {
		onExpire = function()
			st.protectUntil = nil
			st.second = nil
			show(f)
		end,
	})
end

-- 4 Original Rebuttal
Kit[4] = function(c)
	local f = c.f
	local st = cs(f)
	local bp = st.bp
	if not bp then
		return
	end
	local used = false
	K.FX.highlight(f.model, SILVER, 0.7, 0.5)
	K.hook(f, "beforeTake", function(_, info)
		if used then
			return
		end
		local cc = info.opts.cast
		if cc and info.src == bp.owner and cc.slot == bp.slot and (info.opts.projectile or info.opts.melee) then
			used = true
			info.cancel = true
			K.dmg(c, info.src, 100, { fromPos = f.root.Position })
			K.announce(f, "REBUTTAL", SILVER, 1)
			if c.p60 then
				bp.first = K.now()
				bp.expires = K.now() + 8
			end
		end
	end, 0.7)
	c:channel(0.7, { stationary = false })
end

-- 5 Perfect Interpretation (ultimate)
Kit[5] = function(c)
	local f = c.f
	local st = cs(f)
	st.perfect = { charges = 2, cap = c.unstable and 180 or 130, heat = c.unstable }
	st.used = {}
	K.setCd(f, 2, 0)
	K.FX.highlight(f.model, SILVER, 7, 0.6)
	c:form(7, {
		onEnd = function()
			st.perfect = nil
			if c.unstable then
				st.locked = K.now() + 6
			end
			-- Identity Overwrite: all blueprints disappear on expiry
			st.bp, st.second = nil, nil
			show(f)
		end,
	})
end

return Kit
