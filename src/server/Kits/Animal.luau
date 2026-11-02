-- 05 Animal — Companion commands and shared positioning
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }

local TYPES = {
	Hound = { speed = 8.5, color = Color3.fromRGB(150, 110, 70), size = Vector3.new(1.0, 0.9, 1.6) },
	Hawk = { speed = 9.5, color = Color3.fromRGB(200, 170, 120), size = Vector3.new(1.2, 0.5, 0.8), flying = 6 },
	Boar = { speed = 7, color = Color3.fromRGB(110, 70, 50), size = Vector3.new(1.2, 1.0, 1.7) },
}
local ORDER = { "Hound", "Hawk", "Boar" }

local function summonCompanion(f, kind, hp, dur, name)
	local spec = TYPES[kind]
	local sm = K.summon(f, {
		name = name or kind,
		hp = hp or 220,
		duration = dur,
		speed = spec.speed,
		size = spec.size,
		color = spec.color,
		shape = "Block",
		material = Enum.Material.SmoothPlastic,
		flying = spec.flying,
		ai = "follow",
		leash = 20,
	})
	sm.data.kind = kind
	return sm
end

local function companion(f)
	local sm = f.state.companion
	if sm and K.alive(sm) then
		return sm
	end
	return nil
end

local function showRes(f)
	local sm = companion(f)
	local txt = f.state.kind .. (sm and "" or (f.state.lockout and f.state.lockout > K.now() and " (down)" or " (V: resummon 20E)"))
	K.res(f, "Companion", txt, nil, 1)
end

local function spawnMain(f)
	local sm = summonCompanion(f, f.state.kind)
	f.state.companion = sm
	sm.sm.onDeath = function()
		f.state.lockout = K.now() + 12
		showRes(f)
	end
	showRes(f)
	return sm
end

-- Passive: Pack Bond
function Kit.passive.init(f)
	f.state.kind = f.state.kind or "Hound"
	K.after(0.5, function()
		if f.kitName == "Animal" and not f.dead then
			spawnMain(f)
		end
	end)
end
function Kit.passive.cleanup(f)
	for _, sm in ipairs(K.summons(f)) do
		S.Summons.remove(sm, "cleanup")
	end
end
-- V: choose companion (resummons if down and the 12 s lockout has passed)
function Kit.action(f)
	local sm = companion(f)
	if not sm then
		if f.state.lockout and f.state.lockout > K.now() then
			K.notify(f, "Companion down")
			return
		end
		if f.energy < 20 then
			K.notify(f, "Need 20 Energy")
			return
		end
		K.Combat.spendEnergy(f, 20)
		spawnMain(f)
		return
	end
	local i = table.find(ORDER, f.state.kind) or 1
	f.state.kind = ORDER[i % 3 + 1]
	K.notify(f, "Next companion: " .. f.state.kind .. " (applies on resummon)")
	showRes(f)
end

local function needCompanion(c)
	if companion(c.f) then
		return true
	end
	return false, "Companion is down"
end

-- order a one-shot strike; onArrive(target) when in reach
local function strike(sm, target, onArrive)
	sm.sm.ai = "chase"
	S.Summons.command(sm, target)
	local t0 = K.now()
	K.every(0.1, 4, function()
		if not K.alive(sm) or not K.alive(target) then
			return false
		end
		if K.dist(sm, target) <= 2 then
			onArrive(target)
			sm.sm.ai = "follow"
			sm.sm.target = nil
			return false
		end
		if K.now() - t0 > 3.9 or sm.sm.target == nil then
			sm.sm.ai = "follow"
			return false
		end
		return true
	end)
end

Kit.requires = {
	[1] = function(c)
		local ok, why = needCompanion(c)
		if not ok then
			return false, why
		end
		if not c:target(18) then
			return false, "No target"
		end
		return true
	end,
	[2] = needCompanion,
	[3] = needCompanion,
	[4] = needCompanion,
}

-- 1 Sic
Kit[1] = function(c)
	local f = c.f
	local sm = companion(f)
	local t = c:target(18)
	if not sm or not t then
		return
	end
	if sm.data.kind == "Hawk" then
		sm.sm.flying = 3
	end
	strike(sm, t, function(target)
		K.Combat.damage(sm, target, 70, { fromSummon = true, element = "Animal" })
		if sm.data.kind == "Boar" then
			K.knock(c, target, sm.root.Position, 1.5)
		end
	end)
	if c.p60 then
		K.speed(f, 0.1, 2, "Pursuit")
	end
end

-- 2 Recall Leap
Kit[2] = function(c)
	local f = c.f
	local sm = companion(f)
	if not sm then
		return
	end
	if K.has(sm, "root") then
		K.reduceCd(f, 2, c.def.cd / 2)
		return
	end
	local arrive = f.root.Position + K.flat(f.root.CFrame.RightVector) * K.m(1.2)
	S.Fighter.teleport(sm, arrive)
	sm.sm.ai = "follow"
	sm.sm.target = nil
	if c.p60 then
		K.shield(c, sm, 80, 3, "Recall")
	end
	if K.has(f, "root") then
		return
	end
	K.dash(c, -c:dir(), 4, 0.22, { up = 8 })
end

-- 3 Territorial Call
Kit[3] = function(c)
	local f = c.f
	local sm = companion(f)
	local pos = c:aimPoint(16)
	local radius = c.p60 and 7.5 or 5
	S.Summons.moveTo(sm, pos)
	sm.sm.ai = "stay"
	K.zone(c, {
		pos = pos,
		radius = radius,
		duration = 7,
		tick = 2,
		transparency = 0.8,
		tickFn = function(z, list)
			if not K.alive(sm) then
				return
			end
			for _, t in ipairs(list) do
				if K.isEnemy(f, t) and K.los(sm, t) then
					K.Combat.damage(sm, t, 35, { fromSummon = true, element = "Animal" })
					K.reveal(c, t, 1)
					K.FX.beam(sm.root.Position, t.root.Position, 0.3, K.color(c), 0.15)
					break
				end
			end
		end,
		finish = function()
			if K.alive(sm) then
				sm.sm.ai = "follow"
			end
		end,
	})
end

-- 4 Shared Instinct
Kit[4] = function(c)
	local f = c.f
	local sm = companion(f)
	if c.p60 and sm then
		local a, b = f.root.Position, sm.root.Position
		if K.Hit.spaceFree(b) then
			S.Fighter.teleport(f, b + Vector3.new(0, 1.5, 0))
			S.Fighter.teleport(sm, a)
		end
	end
	local holder = f
	local function onHit(victim)
		holder = (victim == f) and sm or f
		if holder and K.alive(holder) then
			K.dr(holder, 0.4, 0.5, "Instinct")
		end
	end
	local r1 = K.hook(f, "taken", function(_, info)
		if info.kind == "direct" then
			onHit(f)
		end
	end, 4)
	local r2 = sm and K.hook(sm, "taken", function(_, info)
		if info.kind == "direct" then
			onHit(sm)
		end
	end, 4)
	local _ = r1
	local __ = r2
	K.dr(f, 0.4, 0.5, "Instinct")
end

-- 5 Wild Assembly (ultimate)
Kit[5] = function(c)
	local f = c.f
	local pack = {}
	for _, kind in ipairs(ORDER) do
		if kind ~= f.state.kind then
			local sm = summonCompanion(f, kind, 160, c.unstable and 20 or 8, kind .. " (wild)")
			sm.sm.ai = "chase"
			sm.sm.attack = { range = 2, dmg = 20, interval = 1.2 }
			table.insert(pack, sm)
		end
	end
	local charges = c.unstable and 3 or 2
	local finalTarget
	c:recast(c.unstable and 20 or 8, function(c2)
		local t = c2:target(25) or K.nearestEnemy(f, 25)
		if not t then
			return "keep"
		end
		finalTarget = t
		local animals = {}
		for _, sm in ipairs(pack) do
			if K.alive(sm) then
				table.insert(animals, sm)
			end
		end
		local main = companion(f)
		if main then
			table.insert(animals, main)
		end
		for _, sm in ipairs(animals) do
			strike(sm, t, function(target)
				K.Combat.damage(sm, target, 60, { fromSummon = true, element = "Animal" })
			end)
			if c.unstable and sm ~= main then
				-- Primal Muster: pursue the final target, ignoring recall
				sm.sm.target = finalTarget
			end
		end
		charges -= 1
		if charges > 0 then
			return "keep"
		end
		return nil
	end, { uses = 1 })
end

return Kit
