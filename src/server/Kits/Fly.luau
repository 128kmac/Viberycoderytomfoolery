-- 36 Fly — Aerial positioning and lift conservation
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local SKY = Color3.fromRGB(200, 230, 250)

local function setLift(f, v)
	f.state.lift = math.clamp(v, 0, 100)
	K.res(f, "Lift", math.floor(f.state.lift), 100, 1)
	if f.state.lift <= 0 and f.state.hover then
		f.state.hover.stop()
		f.state.hover = nil
	end
end

-- Passive: Lift Budget
function Kit.passive.init(f)
	setLift(f, 100)
end
function Kit.passive.tick(f, dt)
	local hum = f.humanoid
	if not hum then
		return
	end
	local sky = f.state.openSky
	if f.state.hover and f.state.hover.alive then
		local cost = 15
		if sky then
			cost = sky.unstable and 0 or 7.5
		end
		setLift(f, f.state.lift - cost * dt)
		if sky then
			K.FX.sphere(f.root.Position - Vector3.new(0, 2, 0), 0.6, SKY, 1.5, 0.5)
		end
	elseif hum.FloorMaterial ~= Enum.Material.Air and hum.MoveDirection.Magnitude > 0.1 then
		setLift(f, f.state.lift + 20 * dt)
	end
end
function Kit.passive.taken(f, info)
	if info.kind == "direct" and f.humanoid and f.humanoid.FloorMaterial == Enum.Material.Air then
		setLift(f, f.state.lift - 10)
	end
end
function Kit.passive.beforeTake(f, info)
	local sky = f.state.openSky
	if sky and sky.unstable and f.humanoid and f.humanoid.FloorMaterial == Enum.Material.Air then
		info.bonus = (info.bonus or 0) + 0.2
	end
end

-- 1 Wing Dart
Kit[1] = function(c)
	local dir = c:dir3()
	for i, a in ipairs({ -3, 3 }) do
		local curve = c.p60 and i == 2
		K.proj(c, {
			dir = K.rotate(dir, a),
			range = 20,
			speed = 32,
			width = 0.25,
			shape = "Block",
			size = Vector3.new(0.25, 0.25, 1.4),
			color = SKY,
			dmg = 35,
			step = curve and function(p)
				if not p.data.curved and p.traveled > K.m(6) then
					p.data.curved = true
					local t = K.nearestEnemy(c.f, 20, p.pos)
					if t then
						local want = (t.root.Position - p.pos).Unit
						local ang = math.deg(math.acos(math.clamp(want:Dot(p.vel.Unit), -1, 1)))
						if ang <= 15 then
							p.vel = want * p.speed
						end
					end
				end
			end or nil,
		})
		task.wait(0.06)
	end
end

-- 2 Takeoff (recast cancels hover)
Kit.requires = {
	[2] = function(c)
		if c.f.state.takeoffLock and c.f.state.takeoffLock > K.now() then
			return false, "Takeoff locked"
		end
		if (c.f.state.lift or 0) >= 20 then
			return true
		end
		return false, "Need 20 Lift"
	end,
	[3] = function(c)
		if (c.f.state.lift or 0) >= 15 or (c.f.state.openSky and c.f.state.openSky.unstable) then
			return true
		end
		return false, "Need 15 Lift"
	end,
}
Kit[2] = function(c)
	local f = c.f
	setLift(f, f.state.lift - 20)
	if f.state.hover then
		f.state.hover.stop()
	end
	f.state.hover = K.hover(f, 6, 60, 0.6)
	if c.p60 then
		K.hook(f, "beforeDisplace", function(_, info)
			info.cancel = true
		end, 0.4)
	end
	local spiral = K.FX.ring(c:feet(), K.m(1.5), SKY, 0.6, 0.3)
	local _ = spiral
	c:recast(60, function()
		if f.state.hover then
			f.state.hover.stop()
			f.state.hover = nil
		end
	end)
end

-- 3 Crosswind Bank
Kit[3] = function(c)
	local f = c.f
	local sky = f.state.openSky
	if not (sky and sky.unstable) then
		setLift(f, f.state.lift - 15)
	end
	local side = K.flat(c:dir():Cross(Vector3.yAxis))
	local aimRel = (c:aimPoint(20) - f.root.Position):Dot(side)
	local dir = aimRel >= 0 and side or -side
	local clipped = {}
	K.dash(c, dir, 6, 0.25, {
		passWidth = 2,
		onPass = function(t)
			if not clipped[t] then
				clipped[t] = true
				K.dmg(c, t, 60, { melee = true })
			end
		end,
	})
	if sky and (sky.bankCharges or 0) > 0 then
		sky.bankCharges -= 1
		K.setCd(f, 3, 0.3)
	end
end

-- 4 Dive Intercept
local function dive(c, rM, dmg)
	local f = c.f
	local target = c:aimPoint(14)
	if f.state.hover then
		f.state.hover.stop()
		f.state.hover = nil
	end
	K.telegraph(c, target, rM, 0.25, SKY)
	local start = f.root.Position
	local stand = K.Hit.standAt(target)
	K.path(c, function(a)
		return start:Lerp(stand, a * a)
	end, 0.35)
	local hits = K.circle(c, target, rM, { dmg = dmg, color = SKY })
	setLift(f, f.state.lift + 20)
	f.state.takeoffLock = K.now() + 1
	return hits
end
Kit[4] = function(c)
	local hits = dive(c, 2, 110)
	if c.p60 and #hits > 0 then
		K.dash(c, -c:dir(), 2, 0.15, { up = 10 })
	end
end

-- 5 Open Sky (ultimate)
Kit[5] = function(c)
	local f = c.f
	local sky = { unstable = c.unstable, bankCharges = 1 }
	f.state.openSky = sky
	local finished = false
	local function finalDive(cc)
		if finished then
			return
		end
		finished = true
		f.state.openSky = nil
		cc:closeRecast()
		dive(cc, 4, 180)
	end
	c:form(8, {
		onEnd = function()
			f.state.openSky = nil
			if c.unstable and not finished then
				-- Icarus Limit: the landing marker appears 0.8 s early
				K.telegraph(c, c:aimPoint(14), 4, 0.8, Color3.fromRGB(255, 120, 80))
				task.wait(0.8)
				finalDive(c)
			end
		end,
	})
	c:recast(8, function(c2)
		finalDive(c2)
	end)
end

return Kit
