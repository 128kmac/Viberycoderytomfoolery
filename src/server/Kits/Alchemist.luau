-- 03 Alchemist — Reagent combinations and deliberate conversion
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
Kit.stationaryWindup = { [4] = true }

local REAGENTS = { "Salt", "Sulfur", "Mercury" }
local COLORS = {
	Salt = Color3.fromRGB(240, 240, 240),
	Sulfur = Color3.fromRGB(255, 220, 40),
	Mercury = Color3.fromRGB(170, 180, 200),
}

local function show(f)
	local st = f.state
	local parts = {}
	for _, r in ipairs(REAGENTS) do
		table.insert(parts, (st.has[r] and "" or "x") .. r)
	end
	K.res(f, "Reagent", st.sel .. "  [" .. table.concat(parts, " ") .. "]", nil, 1)
end

local function refill(f, r)
	f.state.has[r] = true
	show(f)
end

-- consume the chosen reagent (or the next available one)
local function consume(f)
	local st = f.state
	local pick = st.has[st.sel] and st.sel or nil
	if not pick then
		for _, r in ipairs(REAGENTS) do
			if st.has[r] then
				pick = r
				break
			end
		end
	end
	if not pick then
		return nil
	end
	st.has[pick] = false
	K.after(7, function()
		if f.kitName == "Alchemist" then
			refill(f, pick)
		end
	end)
	-- repeating adds Heat; alternating all three refunds Energy once per cycle
	if st.last == pick then
		K.addHeat(f, 4)
	end
	table.insert(st.history, pick)
	if #st.history > 3 then
		table.remove(st.history, 1)
	end
	if #st.history == 3 and st.history[1] ~= st.history[2] and st.history[2] ~= st.history[3] and st.history[1] ~= st.history[3] then
		K.addEnergy(f, 10)
		st.history = {}
	end
	st.last = pick
	show(f)
	return pick
end

function Kit.passive.init(f)
	f.state.has = { Salt = true, Sulfur = true, Mercury = true }
	f.state.sel = "Salt"
	f.state.history = {}
	show(f)
end
function Kit.passive.cast(f, c)
	if c.slot <= 3 then
		c.data.reagent = consume(f)
	end
end
-- V cycles the chosen reagent
function Kit.action(f)
	local i = table.find(REAGENTS, f.state.sel) or 1
	f.state.sel = REAGENTS[i % 3 + 1]
	show(f)
end

local function anyReagent(c)
	local st = c.f.state
	for _, r in ipairs(REAGENTS) do
		if st.has[r] then
			return true
		end
	end
	return false, "No reagents (refill in 7 s)"
end

local function inCircle(f, pos)
	local circ = f.state.circle
	if circ and circ.zone.alive and K.flatDist(pos, circ.zone.pos) <= 4 then
		return circ
	end
	return nil
end

local function react(c, circ, reagent)
	if circ.reagents[1] == reagent then
		return -- identical flasks produce no recipe
	end
	table.insert(circ.reagents, reagent)
	if #circ.reagents < 2 then
		return
	end
	local a, b = circ.reagents[1], circ.reagents[2]
	local function has(x)
		return a == x or b == x
	end
	local pos = circ.zone.pos
	if has("Salt") and has("Sulfur") then
		K.circle(c, pos, 4, { dmg = 120, color = COLORS.Sulfur })
	elseif has("Salt") and has("Mercury") then
		K.object(c, { name = "Cover", pos = pos, size = Vector3.new(2.5, 2.5, 2.5), hp = 100, duration = 8, color = COLORS.Salt, material = Enum.Material.Salt, tags = { construct = true } })
	elseif has("Sulfur") and has("Mercury") then
		if K.partner(c, "Mud", 15) then
			for _, t in ipairs(K.enemiesIn(c, pos, 4)) do
				K.slow(c, t, 0.25, 2)
			end
		else
			for _, t in ipairs(K.enemiesIn(c, pos, 4)) do
				K.knock(c, t, pos, 4)
			end
		end
		K.FX.burst(pos, K.m(4), COLORS.Mercury, 0.3)
	end
	circ.reagents = {}
	circ.reactions += 1
	if not circ.keep or circ.reactions >= 2 then
		circ.zone:remove("reacted")
		c.f.state.circle = nil
	end
end

-- 1 Retort Flask
Kit.requires = { [1] = anyReagent, [2] = function(c)
	local ok, why = anyReagent(c)
	if not ok then
		return false, why
	end
	local pos = c:aimPoint(10)
	for _, o in ipairs(K.objects(c, pos, 3)) do
		if o.hp < 180 and (o.owner == nil or not K.isEnemy(c.f, o.owner)) and not o.tags.alchemized then
			return true
		end
	end
	return false, "Needs a friendly/neutral construct under 180 durability"
end, [3] = anyReagent }

Kit[1] = function(c)
	local reagent = c.data.reagent or "Salt"
	local col = COLORS[reagent]
	local done = false
	local function apply(t)
		K.dmg(c, t, 55, { projectile = true })
		if reagent == "Salt" then
			K.root(c, t, 0.4)
		elseif reagent == "Sulfur" then
			K.burn(c, t, 30, 3)
		else
			K.push(c, t, K.flat(t.root.Position - c.f.root.Position), 2)
		end
	end
	K.lob(c, {
		range = 18,
		color = col,
		width = 0.6,
		speed = 20,
		hit = function(t)
			done = true
			apply(t)
		end,
		step = function(p)
			if c.p60 and not p.data.intercepted then
				for _, ep in ipairs(K.enemyProj(c, p.pos, 1)) do
					if ep.kind ~= "ultimate" then
						p.data.intercepted = true
						S.Proj.stop(ep, "intercepted")
						refill(c.f, reagent)
						break
					end
				end
			end
		end,
		land = function(pos)
			if not done then
				for _, t in ipairs(K.enemiesIn(c, pos, 1.5)) do
					apply(t)
					break
				end
			end
			K.FX.burst(pos, K.m(1.5), col, 0.3)
			local circ = inCircle(c.f, pos)
			if circ then
				react(c, circ, reagent)
			end
		end,
	})
end

-- 2 Equivalent Exchange
Kit[2] = function(c)
	local reagent = c.data.reagent or "Salt"
	local pos = c:aimPoint(10)
	local target
	for _, o in ipairs(K.objects(c, pos, 3)) do
		if o.hp < 180 and (o.owner == nil or not K.isEnemy(c.f, o.owner)) and not o.tags.alchemized then
			target = o
			break
		end
	end
	if not target then
		return
	end
	local at = K.ground(target.part.Position)
	local gold = target.element == "Gold" and K.synergy()
	S.Objects.remove(target, "converted")
	if reagent == "Salt" then
		K.wall(c, { pos = at, dir = c:dir(), width = 3, height = 2.5, hp = 120, duration = 10, color = COLORS.Salt, tags = { alchemized = true } })
	elseif reagent == "Sulfur" then
		K.shield(c, c.f, 80 + (gold and 30 or 0), 6, "Exchange")
	else
		local drop = at
		if c.p60 then
			drop = K.ground(at + c:dir() * K.m(8))
		end
		local pickup = K.object(c, { name = "Restorative", pos = drop, size = 0.8, shape = "Ball", hp = 1, duration = 12, solid = false, blocks = false, prop = true, noLabel = true, color = Color3.fromRGB(120, 255, 150), material = Enum.Material.Neon })
		K.every(0.1, 12, function()
			if not pickup.alive then
				return false
			end
			for _, a in ipairs(K.alliesIn(c, drop, 1.5, true)) do
				K.heal(c, a, 60)
				S.Objects.remove(pickup, "used")
				return false
			end
			return true
		end)
	end
end

-- 3 Catalyst Circle
Kit[3] = function(c)
	local pos = c:aimPoint(14)
	local f = c.f
	if f.state.circle and f.state.circle.zone.alive then
		f.state.circle.zone:remove("replaced")
	end
	local z = K.zone(c, { pos = pos, radius = 4, duration = 6, color = COLORS[c.data.reagent or "Salt"], transparency = 0.75 })
	f.state.circle = { zone = z, reagents = {}, reactions = 0, keep = c.p60 }
	-- the circle's own reagent counts as the first ingredient
	if c.data.reagent then
		table.insert(f.state.circle.reagents, c.data.reagent)
	end
end

-- 4 Quick Distillation
Kit[4] = function(c)
	local f = c.f
	for _, r in ipairs(REAGENTS) do
		if not f.state.has[r] then
			refill(f, r)
			break
		end
	end
	local who = f
	if c.p60 then
		for _, a in ipairs(K.alliesIn(c, f.root.Position, 3, false)) do
			who = a
			break
		end
	end
	-- remove one removable damage-over-time effect; each remaining tick refunds 3 Energy (max 15)
	local best
	for _, st in pairs(who.statuses) do
		if st.removable and K.Status.DOT_CATEGORIES[st.category] and (not best or st.expires > best.expires) then
			best = st
		end
	end
	if best then
		local ticks = math.floor(math.max(0, best.expires - K.now()) / (best.tick or 0.5))
		K.Status.remove(who, best.name, "cleansed")
		K.addEnergy(f, math.min(15, ticks * 3))
	end
end

-- 5 Magnum Opus (ultimate)
Kit[5] = function(c)
	local center = c:aimPoint(18)
	local dur = c.unstable and 6 or 3
	local ring = K.FX.ring(center, K.m(7), Color3.fromRGB(230, 190, 90), dur + 0.3, 0.4)
	local _ = ring
	local vessels = {}
	for i, r in ipairs(REAGENTS) do
		local a = math.rad(i * 120)
		local p = K.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(4))
		vessels[r] = K.object(c, {
			name = r .. "Vessel",
			neutral = c.unstable,
			pos = p,
			size = Vector3.new(1, 1.6, 1),
			hp = 120,
			duration = dur + 0.5,
			color = COLORS[r],
			material = Enum.Material.Glass,
			isUlt = true,
			onDestroy = c.unstable and function(obj)
				-- neutral explosives
				for _, t in ipairs(K.Hit.cylinder(obj.part.Position, K.m(2), function()
					return true
				end)) do
					K.Combat.damage(c.f, t, 60, { fromPos = obj.part.Position, element = "Alchemist" })
				end
			end or nil,
		})
	end
	local function alive(r)
		return vessels[r] and vessels[r].alive
	end
	if alive("Salt") then
		for _, t in ipairs(K.enemiesIn(c, center, 7)) do
			K.root(c, t, 0.8)
		end
	end
	local t0 = K.now()
	local detonated = false
	while K.now() - t0 < dur do
		task.wait(0.5)
		if alive("Mercury") then
			for _, t in ipairs(K.enemiesIn(c, center, 7)) do
				K.pull(c, t, center, 1)
			end
		end
		if not detonated and K.now() - t0 >= 3 then
			detonated = true
			if alive("Sulfur") then
				K.FX.burst(center, K.m(7), Color3.fromRGB(255, 200, 40), 0.5)
				for _, t in ipairs(K.enemiesIn(c, center, 7)) do
					K.dmg(c, t, 260, { fromPos = center })
				end
			end
		end
	end
	if c.unstable and alive("Sulfur") then
		-- Philosopher Reaction: the second blast damages every unit including the Alchemist
		K.FX.burst(center, K.m(7), Color3.fromRGB(255, 120, 40), 0.5)
		for _, t in ipairs(K.Hit.cylinder(center, K.m(7), function()
			return true
		end)) do
			K.Combat.damage(c.f, t, 160, { cast = c, isUlt = true, fromPos = center, element = "Alchemist" })
		end
	end
end

return Kit
