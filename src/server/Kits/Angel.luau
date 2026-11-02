-- 04 Angel — Aerial rescue and protective judgment
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }

local function setGrace(f, n)
	f.state.grace = math.clamp(n, 0, 3)
	K.res(f, "Grace", f.state.grace, 3)
	if f.state.grace > 0 then
		f.state.graceExpires = K.now() + 10
	end
end

local function spendGrace(f)
	if (f.state.grace or 0) > 0 then
		setGrace(f, f.state.grace - 1)
		return 20
	end
	return 0
end

-- Passive: Witness — preventing 60 damage to an ally (via Angel shields) grants Grace
function Kit.passive.init(f)
	f.state.prevented = 0
	setGrace(f, 0)
	f.state.unsub = S.on("damaged", function(target, info)
		if f.kitName ~= "Angel" or f.dead or target == f or info.absorbed <= 0 then
			return
		end
		if not K.isAlly(f, target) or target.isSummon or (info.src and K.isAlly(f, info.src)) then
			return
		end
		local mine = false
		for _, sh in ipairs(target.shields) do
			if sh.src == f then
				mine = true
			end
		end
		if mine or target.state.angelShieldFrom == f then
			f.state.prevented += info.absorbed
			while f.state.prevented >= 60 do
				f.state.prevented -= 60
				setGrace(f, f.state.grace + 1)
			end
		end
	end)
end
function Kit.passive.tick(f)
	if (f.state.grace or 0) > 0 and K.now() > (f.state.graceExpires or 0) then
		setGrace(f, 0)
	end
end
function Kit.passive.cleanup(f)
	if f.state.unsub then
		f.state.unsub()
	end
end

local function angelShield(c, t, amount, dur)
	t.state.angelShieldFrom = c.f
	K.after(dur, function()
		if t.state.angelShieldFrom == c.f then
			t.state.angelShieldFrom = nil
		end
	end)
	return K.shield(c, t, amount, dur, "AngelShield")
end

-- 1 Feather Verdict
Kit[1] = function(c)
	local dir = c:dir3()
	local healedBack = false
	for i = -1, 1 do
		local d = K.rotate(dir, i * 5)
		K.proj(c, {
			dir = d,
			range = 22,
			width = 0.35,
			color = Color3.fromRGB(255, 255, 240),
			dmg = 25,
			allies = true,
			ally = function(t)
				K.heal(c, t, 10)
				return nil
			end,
			finish = function(_, reason)
				if c.p60 and reason ~= "hit" and not healedBack then
					healedBack = true
					K.after(0.3, function()
						K.heal(c, c.f, 15)
					end)
				end
			end,
		})
	end
end

-- 2 Mercy Descent
Kit[2] = function(c)
	local f = c.f
	local ally = c:ally(12)
	local dest = ally and K.feet(ally) or c:aimPoint(12)
	local knocked = false
	local rm = K.hook(f, "taken", function(_, info)
		if info.kind == "direct" and info.src and K.isEnemy(f, info.src) then
			knocked = true
			local lv = f.root:FindFirstChild("EBDisplace")
			if lv then
				lv:Destroy()
			end
		end
	end)
	local start = f.root.Position
	local stand = K.Hit.standAt(dest) + (ally and K.flat(start - dest) * K.m(1.2) or Vector3.zero)
	K.path(c, function(a)
		if knocked then
			return f.root.Position
		end
		return start:Lerp(stand, a) + Vector3.new(0, math.sin(a * math.pi) * K.m(2), 0)
	end, 0.5)
	rm()
	if knocked then
		return
	end
	local amount = 140 + spendGrace(f)
	angelShield(c, f, amount, 2)
	if ally then
		angelShield(c, ally, amount, 2)
		if c.p60 then
			K.cleanse(ally, "slow", 1)
		end
	end
	K.FX.burst(dest, K.m(2), Color3.fromRGB(255, 250, 220), 0.4)
end

-- 3 Sanctuary Wing
Kit[3] = function(c)
	local f = c.f
	local stored = 0
	local wall = K.wall(c, {
		name = "SanctuaryWing",
		pos = K.forward(c, 2),
		width = 4,
		height = 3,
		thick = 0.4,
		hp = 240,
		duration = 4,
		allyPass = true,
		color = Color3.fromRGB(255, 252, 230),
		material = Enum.Material.ForceField,
		onDamage = function(_, amt)
			stored = math.min(60, stored + amt * 0.2)
		end,
	})
	local function finish()
		f.speedMult = 1
		if f.disabled then
			f.disabled[1] = nil
		end
		if c.p60 and stored > 0 then
			K.heal(c, f, stored)
			stored = 0
		end
	end
	wall.cleanup = finish
	f.speedMult = 0.5
	f.disabled = f.disabled or {}
	f.disabled[1] = true
	-- Light synergy: beams through the wing gain range but consume durability (handled by Light kit)
	wall.tags.angelWing = true
end

-- 4 Ascension Bell
Kit[4] = function(c)
	local pos = c:aimPoint(14)
	if not K.warn(c, pos, 3, 0.8, Color3.fromRGB(255, 240, 180)) then
		return
	end
	K.FX.burst(pos, K.m(3), Color3.fromRGB(255, 250, 200), 0.4)
	local nudged = false
	for _, t in ipairs(K.enemiesIn(c, pos, 3)) do
		K.lift(c, t, 0.8, 2)
		K.dmg(c, t, 95, { fromPos = pos })
		if c.p60 and not nudged then
			nudged = true
			K.after(0.3, function()
				K.push(c, t, c:dir():Cross(Vector3.yAxis), 2)
			end)
		end
	end
	local sound = K.partner(c, "Sound", 20)
	for _, a in ipairs(K.alliesIn(c, pos, sound and 6 or 3, true)) do
		a.jumpMult = 2.2
		K.after(2.5, function()
			a.jumpMult = 1
		end)
		if sound then
			K.speed(a, 0.1, 2, "Bell Cue")
		end
	end
end

-- 5 Choir of Return (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(18)
	local destroyed = 0
	local ended = false
	local transferred = 0
	local zone
	local pillars = {}
	local hooks = {}
	local function finish(withShield)
		if ended then
			return
		end
		ended = true
		for _, rm in ipairs(hooks) do
			rm()
		end
		if zone and zone.alive then
			zone:remove("ended")
		end
		for _, p in ipairs(pillars) do
			if p.alive then
				S.Objects.remove(p, "ended")
			end
		end
		if withShield then
			local amount = (c.unstable and 240 or 120) + spendGrace(f)
			for _, a in ipairs(K.alliesIn(c, center, 7, true)) do
				angelShield(c, a, amount, 4)
			end
		end
		c:closeRecast()
	end
	for i = 0, 3 do
		local a = math.rad(i * 90 + 45)
		pillars[i + 1] = K.object(c, {
			name = "ChoirPillar",
			pos = K.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(7)),
			size = Vector3.new(0.8, 3, 0.8),
			hp = 100,
			duration = 6.2,
			isUlt = true,
			color = Color3.fromRGB(255, 250, 225),
			material = Enum.Material.Marble,
			onDestroy = function()
				destroyed += 1
				if destroyed >= 2 then
					finish(false)
				end
			end,
		})
	end
	zone = K.zone(c, {
		pos = center,
		radius = 7,
		duration = 6,
		targets = "all",
		color = Color3.fromRGB(255, 245, 200),
		transparency = 0.8,
		tickFn = function(z, list)
			for _, t in ipairs(list) do
				if K.isEnemy(f, t) then
					K.Combat.damage(f, t, 25, { kind = "field", fromPos = center, isUlt = true, element = "Angel" })
				elseif not t.isSummon then
					K.heal(c, t, 20)
				end
			end
		end,
		finish = function(_, reason)
			if reason == "expired" then
				finish(false)
			end
		end,
	})
	if c.unstable then
		-- Seraphic Burden: up to 200 incoming allied damage is transferred to the Angel, unreduced
		for _, a in ipairs(K.alliesIn(c, center, 30, false)) do
			table.insert(hooks, K.hook(a, "beforeTake", function(t, info)
				if transferred < 200 and zone.alive and zone:contains(t) and info.amount > 0 then
					local take = math.min(200 - transferred, info.amount)
					transferred += take
					info.amount -= take
					K.Combat.damage(info.src, f, take, { kind = "true", tag = "transfer" })
				end
			end))
		end
	end
	c:recast(6, function()
		finish(true)
	end)
end

return Kit
