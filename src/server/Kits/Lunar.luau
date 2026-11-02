-- 55 Lunar — Visible phases and recurring windows (a gameplay abstraction, not real lunar dates)
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local SILVER = Color3.fromRGB(200, 210, 255)
local PHASES = { "Crescent", "Full", "New" }

local function phase(f)
	if f.state.noPhaseUntil and f.state.noPhaseUntil > K.now() then
		return "None"
	end
	if f.state.lockedPhase and f.state.lockedUntil > K.now() then
		return f.state.lockedPhase
	end
	local t = K.now() - f.state.clock0 - (f.state.pausedTotal or 0)
	return PHASES[math.floor(t / 4) % 3 + 1]
end

-- Passive: Three Phases (public icon on the HUD/nameplate)
function Kit.passive.init(f)
	f.state.clock0 = K.now()
	f.state.pausedTotal = 0
end
function Kit.passive.tick(f)
	local p = phase(f)
	K.res(f, "Phase", p, nil, 1)
	f.model:SetAttribute("LunarPhase", p)
end
function Kit.passive.dodge(f)
	if phase(f) == "New" then
		K.conceal(f, 2, 0.6)
	end
end

local function fullBonus(f)
	return phase(f) == "Full" and 30 or 0
end
local function rangeBonus(f)
	return phase(f) == "Crescent" and 2 or 0
end

-- 1 Silver Crescent
Kit[1] = function(c)
	local f = c.f
	local range = 20 + rangeBonus(f)
	local totals = {}
	local function apply(t, dmg)
		local d = math.min(dmg, 100 - (totals[t] or 0))
		if d > 0 then
			totals[t] = (totals[t] or 0) + d
			K.dmg(c, t, d, { projectile = true })
		end
	end
	local dir = c:dir3()
	K.proj(c, {
		dir = K.rotate(dir, 10),
		range = range,
		width = 0.8,
		shape = "Block",
		size = Vector3.new(2, 0.3, 0.6),
		color = SILVER,
		pierce = true,
		hit = function(t)
			apply(t, 75)
			return "continue"
		end,
		finish = function(pos, reason)
			if reason == "wall" then
				return -- terrain stops both travel phases
			end
			if not K.alive(f) then
				return
			end
			K.proj(c, {
				origin = pos,
				dir = (c:chest() - pos).Unit,
				range = range,
				width = 0.8,
				shape = "Block",
				size = Vector3.new(2, 0.3, 0.6),
				color = SILVER,
				pierce = true,
				homing = f,
				turnRate = 30,
				filter = function(t)
					return K.isEnemy(f, t)
				end,
				hit = function(t)
					apply(t, 35)
					return "continue"
				end,
				step = function(p)
					if (p.pos - f.root.Position).Magnitude < K.m(1.5) then
						S.Proj.stop(p, "caught")
					end
				end,
			})
		end,
	})
end

-- 2 Moonpool
Kit[2] = function(c)
	local f = c.f
	local pos = c:aimPoint(14)
	local radius = 4 + (K.partner(c, "Water", 20) and 1 or 0)
	local center = K.object(c, { name = "MoonpoolCenter", pos = pos, size = 0.8, shape = "Ball", hp = 100, duration = 5, color = SILVER, material = Enum.Material.Neon })
	local shielded = {}
	K.zone(c, {
		pos = pos,
		radius = radius,
		duration = 5,
		tick = 0.25,
		immediate = true,
		targets = "all",
		color = SILVER,
		transparency = 0.6,
		tickFn = function(z, list)
			if not center.alive then
				z:remove("center destroyed")
				return
			end
			for _, t in ipairs(list) do
				if K.isEnemy(f, t) then
					K.slow(c, t, 0.15, 0.4, "Moonpool")
				elseif not t.isSummon then
					K.speed(t, 0.1, 0.4, "Moonpool")
				end
			end
		end,
		enter = function(_, t)
			if c.p60 and K.isAlly(f, t) and not shielded[t] and phase(f) == "Full" then
				shielded[t] = true
				K.shield(c, t, 40, 3, "Moonpool")
			end
		end,
	})
end

-- 3 Tidal Veil
Kit[3] = function(c)
	local f = c.f
	local amount = 130 + fullBonus(f)
	K.shield(c, f, amount, 3, "TidalVeil")
	c:recast(3, function(c2)
		local remaining = 0
		for _, sh in ipairs(f.shields) do
			if sh.name == "TidalVeil" then
				remaining = sh.amount
			end
		end
		K.Combat.removeShield(f, "TidalVeil")
		local dist = 2 * math.clamp(remaining / amount, 0, 1)
		K.FX.burst(f.root.Position, K.m(3), SILVER, 0.3)
		for _, t in ipairs(K.enemiesIn(c2, f.root.Position, 3)) do
			K.knock(c2, t, f.root.Position, dist)
		end
		if c2.p60 then
			K.cleanse(f, "reveal", 1)
		end
	end)
end

-- 4 Phase Arrest
Kit[4] = function(c)
	local f = c.f
	local p = phase(f)
	if c.p60 and c.mod then
		local i = table.find(PHASES, p) or 1
		p = PHASES[i % 3 + 1]
	end
	f.state.lockedPhase = p
	f.state.lockedUntil = K.now() + 4
	f.state.pausedTotal += 4 -- the clock resumes from its saved position afterward
	local pos = c:aimPoint(16)
	K.telegraph(c, pos, 3, 0.8, SILVER)
	task.wait(0.8)
	K.circle(c, pos, 3, { dmg = 120, color = SILVER })
end

-- 5 Thirteenfold Moonfall (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(22)
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	-- a continuous exit corridor (along `dir`, offset to one side) stays clear
	local corridorOffset = (math.random() < 0.5 and -1 or 1) * K.m(4)
	local totals = {}
	local rng = Random.new()
	local clusters = { 4, 4, 5 }
	for _, n in ipairs(clusters) do
		local spots = {}
		for _ = 1, n do
			local p
			for _ = 1, 10 do
				p = center + dir * K.m(rng:NextNumber(-7, 7)) + side * K.m(rng:NextNumber(-7, 7))
				local lateral = (p - center):Dot(side)
				if math.abs(lateral - corridorOffset) > K.m(1.8) then
					break
				end
			end
			p = K.ground(p)
			table.insert(spots, p)
			K.telegraph(c, p, 1.5, 0.8, SILVER)
		end
		task.wait(0.8)
		for _, p in ipairs(spots) do
			K.FX.burst(p + Vector3.new(0, 1, 0), K.m(1.5), SILVER, 0.25)
			for _, t in ipairs(K.enemiesIn(c, p, 1.5)) do
				local d = math.min(45, 270 - (totals[t] or 0))
				if d > 0 then
					totals[t] = (totals[t] or 0) + d
					K.dmg(c, t, d, { fromPos = p + Vector3.new(0, 10, 0) })
				end
			end
		end
		task.wait(0.5)
	end
	if c.unstable then
		K.telegraph(c, center, 4, 0.8, Color3.fromRGB(255, 120, 120))
		task.wait(0.8)
		K.circle(c, center, 4, { dmg = 120, color = Color3.fromRGB(255, 120, 120) })
		-- Blood Moon: reset to New with no phase benefits for 6 s
		f.state.noPhaseUntil = K.now() + 6
	end
end

return Kit
