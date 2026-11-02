-- 100 Yin Yang — Complementary stances and balanced expenditure
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local YIN = Color3.fromRGB(30, 30, 40)
local YANG = Color3.fromRGB(245, 245, 245)

local function show(f)
	K.res(f, "Stance", f.state.stance, nil, 1)
	local dial = f.state.dial
	K.res(f, "Dial", (dial > 0 and "+" or "") .. dial, nil, 2)
end

-- Passive: Balance Dial (-3..+3); crossing zero after using both stances grants 40 shield (once per 5 s)
local function moveDial(f, delta)
	local old = f.state.dial
	local new = math.clamp(old + delta, -3, 3)
	f.state.dial = new
	if delta < 0 then
		f.state.usedYin = true
	elseif delta > 0 then
		f.state.usedYang = true
	end
	local crossed = (old < 0 and new >= 0) or (old > 0 and new <= 0)
	if crossed and f.state.usedYin and f.state.usedYang and K.now() - (f.state.lastBalance or 0) >= 5 then
		f.state.lastBalance = K.now()
		K.shield(f, f, 40, 4, "Balance")
		K.announce(f, "BALANCE", Color3.fromRGB(200, 200, 200), 1)
	end
	show(f)
end
function Kit.passive.init(f)
	f.state.dial = 0
	f.state.stance = "Yin"
	show(f)
end

local function stanceColor(f)
	return f.state.stance == "Yin" and YIN or YANG
end
local function complete(c)
	moveDial(c.f, c.f.state.stance == "Yin" and -1 or 1)
end

-- 1 Twin Current
Kit[1] = function(c)
	local f = c.f
	local yin = f.state.stance == "Yin"
	K.proj(c, {
		range = 16,
		width = 0.8,
		shape = "Block",
		size = Vector3.new(2, 0.3, 0.6),
		color = stanceColor(f),
		dmg = yin and 55 or 85,
		guardDmg = (not yin and c.p60) and 15 or 0,
		hit = function()
			if yin then
				K.shield(c, f, c.p60 and 50 or 35, 3, "TwinCurrent")
			end
		end,
	})
	complete(c)
end

-- 2 Turning Circle (does not move the dial)
Kit[2] = function(c)
	local f = c.f
	f.state.stance = f.state.stance == "Yin" and "Yang" or "Yin"
	show(f)
	K.FX.highlight(f.model, stanceColor(f), 0.4, 0.4)
	local dir = f.humanoid and f.humanoid.MoveDirection.Magnitude > 0.1 and K.flat(f.humanoid.MoveDirection) or c:dir()
	if c.p60 and c.mod then
		K.dash(c, K.rotate(dir, 30), 2, 0.12)
		K.dash(c, K.rotate(dir, -30), 2, 0.12)
	else
		K.dash(c, dir, 4, 0.2)
	end
end

-- 3 Stillness and Motion
Kit[3] = function(c)
	local f = c.f
	if f.state.stance == "Yin" then
		K.wall(c, { name = "Stillness", pos = K.forward(c, 2), dir = c:dir(), width = 3, height = 2.5, hp = 100 + (c.p60 and 40 or 0), duration = 3, color = YIN, material = Enum.Material.ForceField })
	else
		local reach = 10 + (c.p60 and 2 or 0)
		local dir = c:dir()
		K.line(c, f.root.Position, dir, reach, 2, {
			dmg = 90,
			color = YANG,
			hit = function(t)
				K.push(c, t, dir, 2)
			end,
		})
	end
	complete(c)
end

-- 4 Restore the Centre (unavailable at zero; does not trigger the Balance shield)
Kit.requires = {
	[4] = function(c)
		if c.f.state.dial ~= 0 then
			return true
		end
		return false, "The dial is already centred"
	end,
}
Kit[4] = function(c)
	local f = c.f
	local steps = math.abs(f.state.dial)
	if f.state.dial < 0 then
		K.heal(c, f, 25 * steps)
	else
		K.ringHit(c, c:feet(), 0, 3, { dmg = 25 * steps, color = YANG })
	end
	if c.p60 and steps >= 2 then
		K.cleanse(f, "slow", 1)
	end
	f.state.dial = 0
	show(f)
end

-- 5 Whole of the Turning World (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(18)
	local normal = c:dir() -- the dividing line is perpendicular to this; +normal side is Yang
	local function yangSide(pos)
		return K.flat(pos - center):Dot(normal) >= 0
	end
	local function drawHalves()
		local side = K.flat(normal:Cross(Vector3.yAxis))
		K.FX.beam(center - side * K.m(8) + Vector3.new(0, 0.3, 0), center + side * K.m(8) + Vector3.new(0, 0.3, 0), 0.3, Color3.fromRGB(150, 150, 150), 7, 0.2)
		K.FX.disc(center + normal * K.m(4), K.m(4), YANG, 1.1, 0.75)
		K.FX.disc(center - normal * K.m(4), K.m(4), YIN, 1.1, 0.6)
	end
	K.FX.ring(center, K.m(8), Color3.fromRGB(180, 180, 180), 7, 0.3)
	local rotated = false
	c:recast(7, function(c2)
		if rotated then
			return
		end
		rotated = true
		-- rotate up to 90 degrees once, with a 0.8 s preview
		local want = c2:dir()
		local ang = math.deg(math.acos(math.clamp(want:Dot(normal), -1, 1)))
		local nextN = ang <= 90 and want or normal:Lerp(want, 90 / ang).Unit
		local side = K.flat(nextN:Cross(Vector3.yAxis))
		K.FX.beam(center - side * K.m(8) + Vector3.new(0, 0.4, 0), center + side * K.m(8) + Vector3.new(0, 0.4, 0), 0.3, Color3.fromRGB(255, 220, 120), 0.8, 0.2)
		task.wait(0.8)
		normal = K.flat(nextN)
	end)
	local total = c.unstable and 5 or 7
	local t0 = K.now()
	local swapped = false
	while K.now() - t0 < total do
		if c.unstable and not swapped and K.now() - t0 >= 4 then
			K.FX.text(center + Vector3.new(0, 3, 0), "EXCHANGE", Color3.fromRGB(200, 200, 200), 1, 28)
			task.wait(1)
			swapped = true
			normal = -normal
		end
		drawHalves()
		for _, t in ipairs(K.Hit.cylinder(center, K.m(8), function()
			return true
		end)) do
			local yang = yangSide(t.root.Position)
			if yang and K.isEnemy(f, t) then
				K.Combat.damage(f, t, 25, { kind = "field", cast = c, isUlt = true, fromPos = center, element = "Yin Yang" })
			elseif not yang and K.isAlly(f, t) and not t.isSummon then
				K.heal(c, t, 20)
			end
		end
		task.wait(1)
	end
	if c.unstable then
		-- Balance Spent: the collapse replaces the final 2 seconds and ends all healing
		K.ringHit(c, center, 0, 8, { dmg = 120, color = Color3.fromRGB(200, 200, 200) })
	end
end

return Kit
