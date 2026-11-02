-- 50 Laser — Line of sight and heat-limited precision
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local RED = Color3.fromRGB(255, 30, 60)

local function setFocus(f, n)
	f.state.focus = math.clamp(n, 0, 3)
	K.res(f, "Focus", f.state.focus, 3, 1)
end

function Kit.passive.init(f)
	setFocus(f, 0)
end

-- fire one beam honouring Lens Temperature and an owned bending lens
local function fireBeam(c, origin, dir, lengthM, dmg, opts)
	local f = c.f
	opts = opts or {}
	local focus = f.state.focus or 0
	local width = (opts.width or 0.4) * (1 - 0.1 * focus)
	dmg = dmg * (1 + math.min(0.15, 0.05 * focus))
	-- bending lens: if the beam passes the lens, it bends once and deals 85%
	local lens = f.state.lens
	local len = K.m(lengthM)
	local any = false
	if lens and lens.obj.alive then
		local lp = lens.obj.part.Position
		local toLens = lp - origin
		local along = toLens:Dot(dir)
		if along > 0 and along < len and (origin + dir * along - lp).Magnitude < K.m(1.2) and K.Hit.los(origin, lp) then
			local _, struck = K.beam(c, { origin = origin, dir = toLens.Unit, length = toLens.Magnitude / K.M, width = width / 1, dmg = dmg, color = RED, dur = 0.2 })
			any = #struck > 0
			local exit = lens.exit
			if c.mod and lens.exit2 then
				exit = lens.exit2
			end
			local _, struck2 = K.beam(c, { origin = lp, dir = exit, length = (len - along) / K.M, width = width, dmg = dmg * 0.85, color = RED, dur = 0.2 })
			any = any or #struck2 > 0
			S.Objects.remove(lens.obj, "used")
			f.state.lens = nil
			setFocus(f, f.state.focus + (any and 1 or -1))
			return any
		end
	end
	local pierced = false
	local endPos, struck, res = K.beam(c, {
		origin = origin,
		dir = dir,
		length = lengthM,
		width = width,
		dmg = dmg,
		color = RED,
		dur = 0.2,
		objDmg = opts.objDmg,
	})
	if opts.pierce and res and not pierced then
		local obj = S.Objects.fromPart(res.Instance)
		if obj and obj.hp <= 60 then
			pierced = true
			S.Objects.destroy(obj, f)
			local _, s2 = K.beam(c, { origin = endPos + dir * 0.5, dir = dir, length = lengthM - (endPos - origin).Magnitude / K.M, width = width, dmg = dmg, color = RED, dur = 0.2 })
			for _, t in ipairs(s2) do
				table.insert(struck, t)
			end
		end
	end
	any = #struck > 0
	if any then
		setFocus(f, f.state.focus + 1)
	else
		setFocus(f, f.state.focus - 1)
		K.addHeat(f, 3)
	end
	return any, endPos
end
Kit.fireBeam = fireBeam

-- 1 Redline Shot
Kit[1] = function(c)
	local f = c.f
	local aimTime = 0.4
	if f.state.quickUntil and f.state.quickUntil > K.now() then
		aimTime = 0.3
		f.state.quickUntil = nil
	end
	local dir = c:dir3()
	local t0 = K.now()
	while K.now() - t0 < aimTime do
		local want = c:dir3()
		local rate = (K.now() - t0 > aimTime - 0.15) and 0.5 or 1
		dir = dir:Lerp(want, rate).Unit
		local res = K.Hit.raycast(c:chest(), dir * K.m(30))
		local endP = res and res.Position or c:chest() + dir * K.m(30)
		K.FX.beam(c:chest(), endP, 0.08, Color3.fromRGB(255, 80, 80), 0.06, 0.4)
		if not c:wait(0.05) then
			return
		end
	end
	fireBeam(c, c:chest(), dir, 30, 100, { pierce = c.p60, width = 0.5 })
	f.state.lastFire = K.now()
end

-- 2 Lens Slide
Kit[2] = function(c)
	local f = c.f
	local side = K.flat(c:dir():Cross(Vector3.yAxis))
	local rel = 1
	if f.humanoid and f.humanoid.MoveDirection.Magnitude > 0.1 then
		rel = f.humanoid.MoveDirection:Dot(side) >= 0 and 1 or -1
	end
	K.dash(c, side * rel, 5, 0.2)
	f.state.quickUntil = K.now() + 2
	if c.p60 then
		local mark = K.now()
		K.after(1, function()
			if (f.state.lastFire or 0) < mark then
				f.heat = math.max(0, f.heat - 10)
			end
		end)
	end
end

-- 3 Mirrorless Bend
Kit[3] = function(c)
	local f = c.f
	local pos = c:aimPoint(24) + Vector3.new(0, K.m(1.2), 0)
	local exit = K.rotate(c:dir(), 60)
	local exit2 = c.p60 and K.rotate(c:dir(), -60) or nil
	local obj = K.object(c, { name = "Lens", cf = CFrame.new(pos), size = Vector3.new(0.8, 0.8, 0.8), shape = "Ball", hp = 90, duration = 5, solid = false, blocks = false, queryable = false, color = Color3.fromRGB(255, 180, 190), material = Enum.Material.Glass })
	f.state.lens = { obj = obj, exit = exit, exit2 = exit2 }
	K.FX.beam(pos, pos + exit * K.m(8), 0.1, Color3.fromRGB(255, 150, 150), 5, 0.5)
	if exit2 then
		K.FX.beam(pos, pos + exit2 * K.m(8), 0.1, Color3.fromRGB(255, 200, 150), 5, 0.6)
	end
end

-- 4 Searing Sweep
Kit[4] = function(c)
	local f = c.f
	local angle = c.p60 and 80 or 60
	local base = c:dir3()
	local sign = ((c:aimPoint(20) - f.root.Position):Dot(K.flat(base:Cross(Vector3.yAxis))) >= 0) and 1 or -1
	local hitCount = {}
	f.speedMult = 0.3
	c:channel(1.5, {
		stationary = false,
		tick = 0.3,
		onTick = function(elapsed)
			local a = -angle / 2 + angle * math.min(1, elapsed / 1.5)
			local dir = K.rotate(base, a * sign)
			c:face(dir)
			local _, struck = K.beam(c, {
				dir = dir,
				length = 22,
				width = 0.5,
				color = RED,
				dur = 0.25,
				filter = function(t)
					return K.isEnemy(f, t) and (hitCount[t] or 0) < 5
				end,
				hit = function(t)
					hitCount[t] = (hitCount[t] or 0) + 1
					K.dmg(c, t, 30, { beam = true })
				end,
			})
			local _ = struck
		end,
	})
	f.speedMult = 1
end

-- 5 Horizon Incision (ultimate)
Kit[5] = function(c)
	local f = c.f
	local dir = c:dir3()
	f.stationary += 1
	local t0 = K.now()
	while K.now() - t0 < 1.2 do
		dir = dir:Lerp(c:dir3(), 0.3).Unit
		K.FX.beam(c:chest(), c:chest() + dir * K.m(36), 0.15, Color3.fromRGB(255, 120, 120), 0.06, 0.3)
		task.wait(0.05)
	end
	local pulses = c.unstable and 4 or 3
	for i = 1, pulses do
		if not c.unstable then
			dir = dir:Lerp(c:dir3(), 0.5).Unit
		end
		local dmg = i == 4 and 80 or 100
		K.beam(c, { dir = dir, length = 36, width = 1.6, dmg = dmg, color = RED, dur = 0.25, objDmg = 180 })
		task.wait(0.33)
	end
	f.stationary -= 1
	if c.unstable then
		f.heat = 100
		f.rupturePending = true
	end
end

return Kit
