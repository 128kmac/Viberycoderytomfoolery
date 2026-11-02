-- 52 Life — Growth investment and gradual restoration
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local GREEN = Color3.fromRGB(140, 255, 120)

local function setGrowth(f, n)
	f.state.growth = math.clamp(n, 0, 4)
	K.res(f, "Growth", f.state.growth, 4, 1)
end
local function useGrowth(f)
	if (f.state.growth or 0) > 0 then
		setGrowth(f, f.state.growth - 1)
		return 10
	end
	return 0
end

-- Passive: Vital Growth
function Kit.passive.init(f)
	f.state.quiet = 0
	setGrowth(f, 0)
end
function Kit.passive.tick(f, dt, now)
	if now - (f.lastDirectHit or 0) >= 3 then
		f.state.quiet += dt
		if f.state.quiet >= 3 then
			f.state.quiet = 0
			setGrowth(f, f.state.growth + 1)
		end
	else
		f.state.quiet = 0
	end
end
function Kit.passive.taken(f, info)
	if info.kind == "direct" then
		setGrowth(f, f.state.growth - 1)
	end
end

local function hot(c, t, total, dur, pauseOnHit)
	local ticks = math.floor(dur / 0.5)
	local per = total / ticks
	local paused = false
	if pauseOnHit then
		local rm
		rm = K.hook(t, "taken", function(_, info)
			if info.kind == "direct" and info.src and K.isEnemy(c.f, info.src) then
				paused = true
				rm()
			end
		end, dur)
	end
	K.every(0.5, dur, function()
		if paused then
			paused = false
			return true
		end
		K.heal(c, t, per)
		return true
	end)
end

-- 1 Vital Seed
Kit[1] = function(c)
	local f = c.f
	local bonus = useGrowth(f)
	K.proj(c, {
		range = 18,
		speed = 20,
		width = 0.5,
		color = GREEN,
		allies = true,
		ally = function(t)
			hot(c, t, 60 + bonus, 3)
			return nil
		end,
		dmg = 60,
		finish = function(pos, reason)
			if reason == "wall" or reason == "range" then
				local shoot = K.object(c, { name = "Shoot", pos = K.ground(pos), size = Vector3.new(0.6, 1, 0.6), hp = 70, duration = 8, solid = false, color = GREEN, material = Enum.Material.Grass })
				local matureAt = K.now() + (c.p60 and 0.5 or 1)
				K.every(0.1, 8, function()
					if not shoot.alive then
						return false
					end
					if K.now() < matureAt then
						return true
					end
					for _, a in ipairs(K.alliesIn(c, K.ground(shoot.part.Position), 1.4, true)) do
						K.heal(c, a, 50)
						S.Objects.remove(shoot, "collected")
						return false
					end
					return true
				end)
			end
		end,
	})
end

-- 2 Living Armor
Kit[2] = function(c)
	local f = c.f
	local ally = c:ally(10, true) or f
	K.shield(c, ally, 120, 5, "LivingArmor")
	if c.p60 and K.has(ally, "Bleed") and useGrowth(f) > 0 then
		K.Status.remove(ally, "Bleed", "cleansed")
	end
	K.every(1, 5, function()
		if K.now() - (ally.lastDirectHit or 0) < 1 then
			return true
		end
		for _, sh in ipairs(ally.shields) do
			if sh.name == "LivingArmor" then
				sh.amount = math.min(120, sh.amount + 10)
				return true
			end
		end
		return false
	end)
end

-- 3 Renewal Trail
Kit[3] = function(c)
	local f = c.f
	local totals = {}
	K.zone(c, {
		shape = "rect",
		pos = c:feet(),
		dir = c:dir(),
		width = 2,
		length = 10,
		duration = 6,
		tick = 0.5,
		targets = "allies",
		includeOwner = true,
		color = GREEN,
		transparency = 0.6,
		tickFn = function(_, list)
			for _, a in ipairs(list) do
				if K.isAlly(f, a) and a.humanoid and a.humanoid.MoveDirection.Magnitude > 0.1 then
					local done = totals[a] or 0
					if done < 60 then
						local amt = math.min(7.5, 60 - done)
						totals[a] = done + amt
						K.heal(c, a, amt)
					end
					if c.p60 then
						K.speed(a, 0.1, 0.6, "Renewal")
					end
				end
			end
		end,
	})
end

-- 4 Second Growth
Kit[4] = function(c)
	local f = c.f
	local target
	for _, sm in ipairs(K.summons(f)) do
		if K.alive(sm) and K.dist(sm, f) <= 12 then
			target = sm
			break
		end
	end
	target = c:ally(12, true) or target or f
	local amount = target.isSummon and 100 or 80
	if c.p60 then
		while (f.state.growth or 0) > 0 do
			amount += useGrowth(f)
		end
	end
	hot(c, target, amount, 4, true)
end

-- 5 Tree of Returning Days (ultimate)
Kit[5] = function(c)
	local f = c.f
	local pos = c:aimPoint(18)
	local tree = K.object(c, { name = "TreeOfDays", pos = pos, size = Vector3.new(2, 6, 2), hp = 350, duration = 8, isUlt = true, color = Color3.fromRGB(110, 80, 50), material = Enum.Material.Wood })
	local crown = K.FX.sphere(pos + Vector3.new(0, K.m(6), 0), K.m(3), GREEN, c.unstable and 4 or 8, 0.2)
	local _ = crown
	local shielded = {}
	local dur = c.unstable and 4 or 8
	K.zone(c, {
		pos = pos,
		radius = 7,
		duration = dur,
		heal = c.unstable and 50 or 25,
		targets = "allies",
		includeOwner = true,
		color = GREEN,
		transparency = 0.85,
		tickFn = function(z)
			if not tree.alive then
				z:remove("tree destroyed")
			end
		end,
		enter = function(_, a)
			if not shielded[a] and not a.isSummon then
				shielded[a] = true
				K.shield(c, a, 80, 4, "TreeOfDays")
			end
		end,
	})
	if c.unstable then
		K.after(4, function()
			if tree.alive then
				S.Objects.remove(tree, "withered")
			end
			K.debuff(c, f, "BorrowedSpring", { duration = 6, healMult = 0.7, removable = false, label = "Healing -30%" })
		end)
	end
end

return Kit
