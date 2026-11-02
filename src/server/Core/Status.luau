-- Status effects: slows, buffs, damage-over-time, marks, control. Same-name statuses refresh their
-- duration and add stacks up to their cap, but never reset their tick clock.
local S = require(script.Parent.S)

local Status = {}
S.Status = Status

local CONTROL = { stun = true, root = true, sleep = true, lift = true, guardbreak = true, lock = true }
Status.CONTROL = CONTROL

local DOT_CATEGORIES = { burn = true, poison = true, bleed = true, dot = true }
Status.DOT_CATEGORIES = DOT_CATEGORIES

function Status.get(f, name)
	return f and f.statuses[name]
end

function Status.has(f, name)
	return f ~= nil and f.statuses[name] ~= nil
end

function Status.stacks(f, name)
	local st = f and f.statuses[name]
	return st and st.stacks or 0
end

function Status.remaining(f, name)
	local st = f and f.statuses[name]
	if not st then
		return 0
	end
	return math.max(0, st.expires - S.now())
end

--[[ opts:
	duration, stacks (to add, default 1), max (stack cap, default 1), source (fighter), category,
	harmful (default true), removable (default = harmful), slow, speed, dr, drShred (per stack),
	vuln (per stack), dmgBonus, healMult, tick (interval), onTick(f, st), onExpire(f, st),
	onRemove(f, st, reason), label, data, noRefresh, setStacks
]]
function Status.apply(f, name, opts)
	if not S.alive(f) then
		return nil
	end
	opts = opts or {}
	local now = S.now()
	local st = f.statuses[name]
	local dur = opts.duration or 3
	if st then
		local add = opts.stacks or 1
		if opts.setStacks then
			st.stacks = math.min(opts.max or st.max, opts.setStacks)
		else
			st.stacks = math.min(opts.max or st.max, st.stacks + add)
		end
		if not opts.noRefresh then
			st.expires = math.max(st.expires, now + dur)
		end
		if opts.source then
			st.source = opts.source
		end
		for _, k in ipairs({ "slow", "speed", "dr", "drShred", "vuln", "dmgBonus", "healMult", "label" }) do
			if opts[k] ~= nil then
				st[k] = opts[k]
			end
		end
		if opts.data then
			for k, v in pairs(opts.data) do
				st.data[k] = v
			end
		end
	else
		local harmful = opts.harmful
		if harmful == nil then
			harmful = true
		end
		local removable = opts.removable
		if removable == nil then
			removable = harmful
		end
		st = {
			name = name,
			stacks = math.min(opts.max or 1, opts.setStacks or opts.stacks or 1),
			max = opts.max or 1,
			expires = now + dur,
			applied = now,
			source = opts.source,
			category = opts.category or (harmful and "debuff" or "buff"),
			harmful = harmful,
			removable = removable and not CONTROL[name],
			slow = opts.slow,
			speed = opts.speed,
			dr = opts.dr,
			drShred = opts.drShred,
			vuln = opts.vuln,
			dmgBonus = opts.dmgBonus,
			healMult = opts.healMult,
			tick = opts.tick,
			nextTick = opts.tick and (now + opts.tick) or nil,
			onTick = opts.onTick,
			onExpire = opts.onExpire,
			onRemove = opts.onRemove,
			label = opts.label,
			data = opts.data or {},
		}
		f.statuses[name] = st
	end
	f.statusDirty = true
	return st
end

function Status.remove(f, name, reason)
	local st = f and f.statuses[name]
	if not st then
		return false
	end
	f.statuses[name] = nil
	f.statusDirty = true
	if st.onRemove then
		S.safe(st.onRemove, f, st, reason or "removed")
	end
	return true
end

function Status.removeStacks(f, name, n)
	local st = f and f.statuses[name]
	if not st then
		return 0
	end
	local removed = math.min(st.stacks, n or 1)
	st.stacks -= removed
	f.statusDirty = true
	if st.stacks <= 0 then
		Status.remove(f, name, "cleansed")
	end
	return removed
end

-- Cleanse: category filter (string, table set, or nil = any removable harmful). Removes `count` statuses
-- choosing the longest remaining (ties: earliest applied). Returns number removed and list of names.
function Status.cleanse(f, category, count)
	count = count or 1
	local removed = {}
	for _ = 1, count do
		local best
		for _, st in pairs(f.statuses) do
			if st.harmful and st.removable then
				local okCat = category == nil
					or (type(category) == "string" and (st.category == category or (category == "dot" and DOT_CATEGORIES[st.category])))
					or (type(category) == "table" and category[st.category])
				if okCat then
					if
						not best
						or st.expires > best.expires
						or (st.expires == best.expires and st.applied < best.applied)
					then
						best = st
					end
				end
			end
		end
		if not best then
			break
		end
		-- stacking statuses lose one stack per cleanse
		if best.stacks > 1 and best.max > 1 then
			Status.removeStacks(f, best.name, 1)
		else
			Status.remove(f, best.name, "cleansed")
		end
		table.insert(removed, best.name)
	end
	if #removed > 0 then
		S.emit("cleansed", f, removed)
	end
	return #removed, removed
end

function Status.update(f, now)
	for name, st in pairs(f.statuses) do
		if st.tick and st.nextTick and now >= st.nextTick and now <= st.expires + 0.05 then
			st.nextTick += st.tick
			if st.onTick then
				S.safe(st.onTick, f, st)
			end
		end
		if now >= st.expires and f.statuses[name] == st then
			f.statuses[name] = nil
			f.statusDirty = true
			if st.onExpire then
				S.safe(st.onExpire, f, st)
			end
			if st.onRemove then
				S.safe(st.onRemove, f, st, "expired")
			end
		end
	end
end

-- Aggregates ---------------------------------------------------------------
function Status.slow(f)
	local m = 0
	for _, st in pairs(f.statuses) do
		if st.slow and st.slow > m then
			m = st.slow
		end
	end
	return math.min(m, S.Config.MAX_SLOW)
end

function Status.speedBonus(f)
	local s = 0
	for _, st in pairs(f.statuses) do
		if st.speed then
			s += st.speed * (st.speedPerStack and st.stacks or 1)
		end
	end
	return math.min(s, S.Config.MAX_SPEED_BONUS)
end

function Status.dr(f)
	local m = 0
	for _, st in pairs(f.statuses) do
		if st.dr and st.dr > m then
			m = st.dr
		end
	end
	local shred = 0
	for _, st in pairs(f.statuses) do
		if st.drShred then
			shred += st.drShred * st.stacks
		end
	end
	return math.max(0, m - shred)
end

function Status.vuln(f)
	local s = 0
	for _, st in pairs(f.statuses) do
		if st.vuln then
			s += st.vuln * (st.vulnPerStack and st.stacks or 1)
		end
	end
	return s
end

function Status.dmgBonus(f)
	local s = 0
	for _, st in pairs(f.statuses) do
		if st.dmgBonus then
			s += st.dmgBonus
		end
	end
	return s
end

-- strongest healing reduction (healMult is the remaining fraction, e.g. 0.75)
function Status.healMult(f)
	local m = 1
	for _, st in pairs(f.statuses) do
		if st.healMult and st.healMult < m then
			m = st.healMult
		end
	end
	return m
end

function Status.anyControl(f)
	for name in pairs(CONTROL) do
		if f.statuses[name] then
			return name
		end
	end
	return nil
end

-- Damage over time. total damage over duration, ticking every `interval` (default 0.5s).
function Status.dot(f, name, total, duration, src, opts)
	opts = opts or {}
	local interval = opts.interval or 0.5
	local ticks = math.max(1, math.floor(duration / interval + 0.5))
	local per = total / ticks
	local st = f.statuses[name]
	if st then
		st.data.per = per
		st.expires = math.max(st.expires, S.now() + duration)
		st.source = src or st.source
		return st
	end
	return Status.apply(f, name, {
		duration = duration,
		source = src,
		category = opts.category or "dot",
		tick = interval,
		label = opts.label or name,
		max = 1,
		data = { per = per, element = opts.element },
		onTick = function(target, s)
			S.Combat.damage(s.source, target, s.data.per, {
				kind = "dot",
				noGuard = true,
				element = s.data.element,
				tag = name,
			})
		end,
	})
end

function Status.label(f)
	local parts = {}
	for _, st in pairs(f.statuses) do
		local l = st.label
		if l ~= false then
			l = l or st.name
			if st.stacks and st.stacks > 1 then
				l = l .. " x" .. st.stacks
			end
			table.insert(parts, (st.harmful and "-" or "+") .. l)
		end
	end
	table.sort(parts)
	return table.concat(parts, "  ")
end

return Status
