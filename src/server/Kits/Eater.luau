-- 29 Eater — Projectile consumption and limited digestion
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local MAW = Color3.fromRGB(140, 60, 120)

local function meals(f)
	local now = K.now()
	local out = {}
	for _, m in ipairs(f.state.meals) do
		if m > now then
			table.insert(out, m)
		end
	end
	f.state.meals = out
	return out
end
local function show(f)
	K.res(f, "Meals", #meals(f), 3, 1)
end
local function addMeal(f)
	local ms = meals(f)
	if #ms >= 3 then
		table.remove(ms, 1)
	end
	table.insert(f.state.meals, K.now() + 10)
	show(f)
end
local function eatMeal(f)
	local ms = meals(f)
	if #ms > 0 then
		table.remove(f.state.meals, 1)
		show(f)
		return true
	end
	return false
end

-- Passive: Stomach Capacity
function Kit.passive.init(f)
	f.state.meals = {}
	show(f)
end
function Kit.passive.tick(f)
	show(f)
end

local function canEat(p)
	return p.kind ~= "ultimate" and not p.tags.beam and not p.ground
end

-- 1 Snap Bite
Kit[1] = function(c)
	local f = c.f
	local front = f.root.Position + c:dir() * K.m(2)
	local threshold = c.p60 and 110 or 80
	for _, o in ipairs(K.enemyObjects(c, front, 2)) do
		if o.hp < threshold and not o.isUlt then
			S.Objects.remove(o, "eaten")
			addMeal(f)
			K.FX.burst(front, K.m(1.5), MAW, 0.25)
			return
		end
	end
	K.melee(c, { range = 4, arc = 80, dmg = 80, color = MAW })
end

-- 2 Vacuum Maw
Kit[2] = function(c)
	local f = c.f
	local eaten = 0
	f.noGuard = true
	f.guarding = false
	c:channel(1, {
		stationary = false,
		halfSpeed = true,
		tick = 0.05,
		onTick = function()
			local dir = K.flat(f.root.CFrame.LookVector)
			for _, p in pairs(S.Proj.list) do
				if eaten < 2 and p.alive and canEat(p) and p.owner ~= f then
					local to = p.pos - f.root.Position
					if to.Magnitude <= K.m(8) and to.Magnitude > 0.1 and K.flat(to):Dot(dir) > math.cos(math.rad(35)) then
						S.Proj.stop(p, "eaten")
						eaten += 1
						if p.owner and K.isEnemy(f, p.owner) then
							addMeal(f)
						end
					end
				end
			end
		end,
	})
	f.noGuard = nil
end

-- 3 Spitback
Kit[3] = function(c)
	local fed = eatMeal(c.f)
	local bounced = false
	K.proj(c, {
		range = 20,
		width = 0.6,
		color = MAW,
		hit = function(t)
			K.dmg(c, t, bounced and 80 or (fed and 110 or 45), { projectile = true })
		end,
		wall = function(_, normal, _, p)
			if c.p60 and fed and not bounced then
				bounced = true
				p.vel = p.vel - 2 * p.vel:Dot(normal) * normal
				return "bounce"
			end
			return nil
		end,
	})
end

-- 4 Comfort Food
Kit[4] = function(c)
	local f = c.f
	local n = 0
	for _ = 1, 2 do
		if eatMeal(f) then
			n += 1
		end
	end
	if n == 0 then
		K.notify(f, "No Meals")
		return
	end
	if c.p60 then
		K.cleanse(f, "slow", 1)
	end
	local per = 55 * n / 6
	local pausedUntil = 0
	local rm = K.hook(f, "taken", function(_, info)
		if info.kind == "direct" then
			pausedUntil = K.now() + 0.5
		end
	end, 3)
	local _ = rm
	K.every(0.5, 3, function()
		if K.now() >= pausedUntil then
			K.heal(c, f, per)
		end
		return true
	end)
end

-- 5 Bottomless Banquet (ultimate)
Kit[5] = function(c)
	local f = c.f
	local items = 0
	local projEaten, objEaten = 0, 0
	f.disabled = { [1] = true, [2] = true, [3] = true, [4] = true }
	local released = false
	local function release(cc)
		if released then
			return
		end
		released = true
		f.disabled = nil
		cc:closeRecast()
		local capV = c.unstable and 360 or 300
		local dmg = math.min(capV, 100 + 25 * items)
		K.circle(cc, cc:feet(), 5, { dmg = dmg, color = MAW })
		if c.unstable then
			if items < 3 then
				K.Combat.damage(nil, f, 80, { kind = "true", tag = "backlash" })
			end
			f.state.meals = {}
			show(f)
			f.noHeal = true
			K.after(4, function()
				f.noHeal = nil
			end)
		end
	end
	c:recast(5, function(c2)
		release(c2)
	end, {
		onExpire = function()
			release(c)
		end,
	})
	K.every(0.05, 5, function()
		if released then
			return false
		end
		local dir = K.flat(f.root.CFrame.LookVector)
		for _, p in pairs(S.Proj.list) do
			if projEaten < 6 and p.alive and canEat(p) and p.owner ~= f then
				local to = p.pos - f.root.Position
				if to.Magnitude <= K.m(10) and to.Magnitude > 0.1 and K.flat(to):Dot(dir) > math.cos(math.rad(40)) then
					S.Proj.stop(p, "eaten")
					projEaten += 1
					-- friendly projectiles defend but add nothing
					if p.owner and K.isEnemy(f, p.owner) then
						items += 1
					end
				end
			end
		end
		if objEaten < 2 then
			for _, o in ipairs(K.enemyObjects(c, f.root.Position + dir * K.m(3), 3)) do
				if o.hp <= 150 and not o.isUlt then
					S.Objects.remove(o, "eaten")
					objEaten += 1
					items += 1
					break
				end
			end
		end
		K.res(f, "Banquet", items, nil, 2)
		return true
	end)
	K.after(5.1, function()
		K.clearRes(f, "Banquet")
	end)
end

return Kit
