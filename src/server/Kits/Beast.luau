-- 08 Beast — Predatory transformation and commitment
local K = require(script.Parent.Parent.Core.K)

local Kit = { passive = {} }
local RED = Color3.fromRGB(170, 60, 40)

local function scented(t)
	return K.has(t, "Scented")
end

-- Passive: Scent of Weakness
function Kit.passive.dealt(f, target, info)
	if target.isSummon then
		return
	end
	if target.health < target.maxHealth * 0.5 and K.dist(f, target) <= 15 then
		K.mark(f, target, "Scented", 4, { label = "Scent", color = RED })
	end
end
function Kit.passive.tick(f)
	local hum = f.humanoid
	if not hum or hum.MoveDirection.Magnitude < 0.1 then
		return
	end
	for _, t in ipairs(K.enemies(f, 15)) do
		if scented(t) and K.flat(t.root.Position - f.root.Position):Dot(hum.MoveDirection.Unit) > 0.6 then
			K.speed(f, 0.08, 0.3, "Tracking")
			break
		end
	end
end

local function apex(f)
	return f.state.apex
end

-- 1 Rending Claw
Kit[1] = function(c)
	local f = c.f
	local stored = f.state.hideStore or 0
	f.state.hideStore = 0
	local first = K.melee(c, { range = 3, arc = 110, dmg = 35 + stored })
	if not c:wait(0.2) then
		return
	end
	local reach = c.p60 and 4 or 3
	local second = K.melee(c, { range = reach, arc = 110, dmg = 35 })
	if #first > 0 then
		for _, t in ipairs(second) do
			local bleed = 30
			if apex(f) and apex(f).unstable then
				bleed = 45
			end
			K.bleed(c, t, bleed, 3)
		end
	end
	if apex(f) then
		K.setCd(f, 1, 2)
	end
end

-- 2 Predator Pounce
Kit[2] = function(c)
	local f = c.f
	local target = c:aimPoint(11)
	if c.p60 then
		-- one midair adjustment of up to 20 degrees toward the nearest enemy
		local t = K.nearestEnemy(f, 13)
		if t then
			local want = K.flat(t.root.Position - f.root.Position)
			local cur = K.flat(target - f.root.Position)
			local ang = math.deg(math.acos(math.clamp(want:Dot(cur), -1, 1)))
			if ang <= 20 then
				target = K.feet(t)
			end
		end
	end
	local land = K.leap(c, target, 0.45, 2.5)
	local hits = K.circle(c, land, 2, { dmg = 100, color = RED })
	local scentHit = false
	for _, t in ipairs(hits) do
		if scented(t) then
			scentHit = true
		end
	end
	if scentHit then
		K.reduceCd(f, 2, 3)
	end
	if #hits == 0 then
		c.recovery = 0.6
		local a = apex(f)
		if a and a.unstable then
			K.Combat.control(f, "lock", 1, f, { force = true })
		end
	else
		c.recovery = 0.25
	end
	local a = apex(f)
	if a and a.pounceCharges > 0 then
		a.pounceCharges -= 1
		K.setCd(f, 2, 0.3)
	end
end

-- 3 Hide of the Cornered
Kit.requires = {
	[3] = function(c)
		if apex(c.f) then
			return false, "Hide is unavailable during Apex Hunt"
		end
		return true
	end,
}
Kit[3] = function(c)
	local f = c.f
	local prevented = 0
	K.slow(f, f, 0.15, 3, "Heavy Hide")
	K.buff(f, "Hide", { duration = 3, label = "Hide (front -30%)" })
	K.hook(f, "beforeTake", function(_, info)
		if K.Combat.facingAngle(f, info.fromPos) <= 60 then
			local before = info.amount
			info.amount *= 0.7
			prevented += before - info.amount
			if c.p60 then
				f.state.hideStore = math.min(60, prevented)
			end
		end
	end, 3)
	K.hook(f, "beforeDisplace", function(_, info)
		info.dist *= 0.5
	end, 3)
	K.FX.highlight(f.model, Color3.fromRGB(120, 90, 60), 3, 0.6)
end

-- 4 Territorial Roar
Kit[4] = function(c)
	local f = c.f
	K.cone(c, {
		range = 7,
		angle = 70,
		dmg = 75,
		color = RED,
		hit = function(t)
			K.interrupt(t, "roar")
			K.knock(c, t, f.root.Position, scented(t) and 3 or 1)
			if c.p60 then
				K.reveal(c, t, 3)
			end
		end,
	})
end

-- 5 Apex Hunt (ultimate)
Kit[5] = function(c)
	local f = c.f
	local state = { unstable = c.unstable, pounceCharges = 1 }
	f.state.apex = state
	K.setCd(f, 1, 0)
	K.setCd(f, 2, 0)
	local hl = K.FX.highlight(f.model, RED, 7, 0.5)
	local _ = hl
	f.hitScale = 1.1
	if c.unstable then
		K.speed(f, 0.2, 7, "Apex")
		f.noGuard = true
		f.guarding = false
	end
	c:form(7, {
		onEnd = function()
			f.state.apex = nil
			f.hitScale = 1
			f.noGuard = nil
		end,
	})
end

return Kit
