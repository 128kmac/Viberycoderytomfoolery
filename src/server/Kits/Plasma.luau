-- 69 Plasma — Charged containment and unstable filaments
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local MAGENTA = Color3.fromRGB(255, 60, 255)

local function setCharges(f, n)
	f.state.charges = math.clamp(n, 0, 3)
	K.res(f, "Charge", f.state.charges, 3, 1)
end

-- Passive: Containment Charge
function Kit.passive.init(f)
	setCharges(f, 0)
end
function Kit.passive.cast(f, c)
	if f.state.charges >= 3 and c.slot <= 4 then
		c.data.contained = true
		setCharges(f, 0)
		K.addHeat(f, 5)
	end
end
function Kit.passive.beforeDeal(f, target, info)
	local c = info.opts.cast
	if c and c.data.contained and not c.data.bonusDone then
		c.data.bonusDone = true
		info.amount += 20
	end
end
function Kit.passive.dealt(f, target, info)
	local c = info.opts.cast
	if c and c.slot <= 4 and not c.data.contained and not c.data.charged and info.kind == "direct" then
		c.data.charged = true
		setCharges(f, f.state.charges + 1)
	end
end

local function plasmaShot(c, opts)
	opts.tags = opts.tags or {}
	opts.tags.plasma = true
	return K.proj(c, opts)
end

-- 1 Ion Needle (hold 0.5 s for a narrower 90-damage needle)
Kit[1] = function(c)
	local f = c.f
	local held = c:hold(0.5)
	local charged = held >= 0.45
	if charged then
		local res = K.Hit.raycast(c:chest(), c:dir3() * K.m(24))
		K.FX.beam(c:chest(), res and res.Position or c:chest() + c:dir3() * K.m(24), 0.08, MAGENTA, 0.15, 0.4)
	end
	local pierced = 0
	plasmaShot(c, {
		range = 24,
		speed = 34,
		width = charged and 0.2 or 0.4,
		shape = "Block",
		size = Vector3.new(0.3, 0.3, 1.8),
		color = MAGENTA,
		pierce = (charged and c.p60) and 1 or 0,
		hit = function(t)
			pierced += 1
			K.dmg(c, t, pierced == 1 and (charged and 90 or 70) or 45, { projectile = true })
		end,
	})
	local _ = f
end

-- 2 Magnetic Bottle
Kit[2] = function(c)
	local f = c.f
	local pos = c:aimPoint(14) + Vector3.new(0, K.m(1.2), 0)
	local bottle = K.object(c, { name = "MagneticBottle", cf = CFrame.new(pos), size = 1.2, shape = "Ball", hp = 140, duration = 7, solid = false, blocks = false, color = MAGENTA, material = Enum.Material.ForceField })
	local stored
	local holdTime = c.p60 and 5 or 3
	K.every(0.03, 7, function()
		if not bottle.alive then
			return false
		end
		if not stored then
			for _, p in ipairs(K.projNear(pos, 1.5, function(p)
				return p.owner == f and p.tags.plasma and not p.data.stored
			end)) do
				stored = p
				p.data.stored = true
				p.data.savedVel = p.vel
				p.vel = Vector3.zero
				p.pos = pos
				if p.part then
					p.part.CFrame = CFrame.new(pos)
				end
				K.after(holdTime, function()
					if p.alive and p.vel.Magnitude < 0.01 then
						p.vel = p.data.savedVel
					end
				end)
				break
			end
		end
		return true
	end)
	c:recast(7, function(c2)
		if stored and stored.alive and stored.vel.Magnitude < 0.01 then
			stored.vel = c2:dir3() * stored.speed
			return nil
		end
		return "keep"
	end)
end

-- 3 Filament Bridge
Kit[3] = function(c)
	local center = c:aimPoint(16)
	local side = K.flat(c:dir():Cross(Vector3.yAxis))
	local a = K.ground(center - side * K.m(4))
	local b = K.ground(center + side * K.m(4))
	if not K.Hit.los(a + Vector3.new(0, 1, 0), b + Vector3.new(0, 1, 0)) then
		b = K.ground(K.Hit.clearPath(a + Vector3.new(0, 1, 0), side, K.m(8), 0.4))
	end
	local len = math.max(1, (b - a).Magnitude / K.M)
	local moved = false
	local z = K.zone(c, { shape = "rect", pos = a, dir = K.flat(b - a), width = 0.8, length = len, duration = 4, tick = 0.5, dmg = 17.5, color = MAGENTA, transparency = 0.2 })
	if c.p60 then
		c:recast(4, function(c2)
			if not moved and z.alive then
				moved = true
				local na = a + K.flat(c2:aimPoint(30) - a) * K.m(2)
				z.pos = na
				z.dir = K.flat(b - na)
				z.length = (b - na).Magnitude
				z:buildVisual(0.2)
			end
		end)
	end
end

-- 4 Corona Skin
Kit[4] = function(c)
	local f = c.f
	K.shield(c, f, 100, 4, "Corona")
	local discharges = 3
	local graceUntil = 0
	K.hook(f, "taken", function(_, info)
		if discharges <= 0 or not info.opts.melee or not info.src or not K.isEnemy(f, info.src) then
			return
		end
		local hasShield = false
		for _, sh in ipairs(f.shields) do
			if sh.name == "Corona" then
				hasShield = true
			end
		end
		if hasShield or K.now() < graceUntil then
			discharges -= 1
			K.FX.beam(f.root.Position, info.src.root.Position, 0.3, MAGENTA, 0.15)
			K.dmg(c, info.src, 30, { kind = "direct", fromPos = f.root.Position })
		end
	end, 5)
	if c.p60 then
		K.hook(f, "shieldBroken", function(_, sh)
			if sh.name == "Corona" then
				graceUntil = K.now() + 1
			end
		end, 4)
	end
end

-- 5 Contained Starfire (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	local sphere = K.FX.sphere(center + Vector3.new(0, K.m(1), 0), K.m(5), MAGENTA, 5, 0.6)
	local anchorCount = c.unstable and 2 or 3
	local anchors = {}
	for i = 1, anchorCount do
		local a = math.rad(i * 360 / anchorCount)
		anchors[i] = K.object(c, { name = "StarfireAnchor", pos = K.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(6)), size = Vector3.new(0.6, 2, 0.6), hp = 100, duration = 5, isUlt = true, color = MAGENTA, material = Enum.Material.Neon })
	end
	local dps = c.unstable and 45 or 35
	K.zone(c, {
		pos = center,
		radius = 5,
		duration = 5,
		dmg = dps,
		color = MAGENTA,
		transparency = 0.8,
		tickFn = function(z)
			local alive = 0
			for _, a in ipairs(anchors) do
				if a.alive then
					alive += 1
				end
			end
			if alive < 2 then
				-- Loss of Containment: collapse releases no surprise explosion
				z:remove("collapsed")
				if sphere.Parent then
					sphere:Destroy()
				end
			end
		end,
	})
	local _ = f
end

return Kit
