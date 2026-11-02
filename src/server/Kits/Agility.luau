-- 02 Agility — Footwork and evasive punishment
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }

local function setStride(f, n)
	n = math.clamp(n, 0, 3)
	f.state.stride = n
	K.res(f, "Stride", n, 3)
	if n > 0 then
		K.buff(f, "Stride", { duration = 999, speed = 0.03 * n, label = false })
	else
		K.S.Status.remove(f, "Stride")
	end
end

-- Passive: Unbroken Stride
function Kit.passive.init(f)
	f.state.moveT, f.state.stillT = 0, 0
	setStride(f, 0)
end
function Kit.passive.tick(f, dt)
	local hum = f.humanoid
	local moving = hum and hum.MoveDirection.Magnitude > 0.1
	if moving then
		f.state.stillT = 0
		f.state.moveT += dt
		if f.state.moveT >= 2 then
			f.state.moveT = 0
			setStride(f, f.state.stride + 1)
		end
	else
		f.state.moveT = 0
		f.state.stillT += dt
		if f.state.stillT >= 1 then
			f.state.stillT = 0
			setStride(f, f.state.stride - 1)
		end
	end
end
function Kit.passive.controlled(f, kind)
	if kind ~= "root" then
		setStride(f, 0)
	end
end
function Kit.passive.evaded(f)
	local now = K.now()
	if not f.state.lastEvade or now - f.state.lastEvade > 0.4 then
		f.state.lastEvade = now
		setStride(f, f.state.stride + 1)
		if f.state.frame and f.state.frame.charges < 4 then
			f.state.frame.charges += 1
			K.res(f, "Counterstrikes", f.state.frame.charges, 4)
		end
	end
end

-- 1 Needle Step
Kit[1] = function(c)
	local f = c.f
	local dist = 5
	if c.mod and f.state.stride > 0 then
		setStride(f, f.state.stride - 1)
		dist += 2
		c.recovery = 0.45
	end
	local dir = c:dir()
	local struck
	K.dash(c, dir, dist, 0.2, {
		passWidth = 1.6,
		stopOnHit = true,
		onPass = function(t)
			if not struck then
				struck = t
				K.dmg(c, t, 65, { melee = true })
			end
		end,
	})
	if not struck then
		local hits = K.melee(c, { range = 1.5, arc = 60, dmg = 65, dir = dir })
		struck = hits[1]
	end
	if struck and c.p60 then
		K.dash(c, K.flat(dir:Cross(Vector3.yAxis)), 1, 0.1)
	end
	if c.recovery == nil or c.recovery < 0.45 then
		c.recovery = c.mod and 0.45 or 0.25
	end
end

-- 2 Wall Waltz
local function findWall(c)
	local origin = c:chest()
	local res = K.Hit.raycast(origin, c:dir() * K.m(8))
	return res
end
Kit.requires = {
	[2] = function(c)
		if findWall(c) then
			return true
		end
		return false, "No wall within 8 m"
	end,
}
Kit[2] = function(c)
	local f = c.f
	local res = findWall(c)
	if not res then
		return
	end
	local n = Vector3.new(res.Normal.X, 0, res.Normal.Z)
	if n.Magnitude < 0.1 then
		return
	end
	n = n.Unit
	local along = n:Cross(Vector3.yAxis)
	if along:Dot(c:dir()) < 0 then
		along = -along
	end
	local wallPoint = res.Position + n * K.m(0.7)
	local start = f.root.Position
	-- approach
	K.path(c, function(a)
		return start:Lerp(Vector3.new(wallPoint.X, start.Y, wallPoint.Z), a)
	end, 0.2)
	-- run along the wall (no attacks during the run); the run ends if the wall is destroyed
	local runLen = c.p60 and 9 or 6
	local wallObj = K.S.Objects.fromPart(res.Instance)
	local runStart = f.root.Position
	local fell = false
	K.path(c, function(a)
		if wallObj and not wallObj.alive then
			fell = true
		end
		return runStart + along * K.m(runLen) * a + Vector3.new(0, math.sin(a * math.pi) * K.m(1.2), 0)
	end, c.p60 and 1.4 or 1.0)
	if fell then
		return
	end
	-- vault away with a descending kick
	local exit = 4 + (K.partner(c, "Wind", 15) and 2 or 0)
	local land = K.ground(f.root.Position + (n + along * 0.5).Unit * K.m(exit))
	K.leap(c, land, 0.35, 1.5)
	K.circle(c, K.feet(f), 2, { dmg = 85 })
	c.recovery = 0.25
end

-- 3 Borrowed Opening
Kit[3] = function(c)
	local f = c.f
	local done = false
	local function counter(attacker)
		if done or not K.alive(attacker) then
			return
		end
		done = true
		c.endChannel = true
		local behind = attacker.root.Position - K.flat(attacker.root.CFrame.LookVector) * K.m(1.5)
		K.blink(c, behind)
		c:face(attacker.root.Position - f.root.Position)
		K.dmg(c, attacker, 100, { melee = true, fromPos = behind })
		K.FX.burst(attacker.root.Position, K.m(1.5), K.color(c), 0.3)
		if c.p60 then
			setStride(f, f.state.stride + 1)
		end
	end
	local rm1 = K.hook(f, "beforeTake", function(_, info)
		if not done and info.opts.melee and info.src and K.dist(info.src, f) <= 3 then
			info.cancel = true
			counter(info.src)
		end
	end)
	local rm2 = S.on("meleeWhiff", function(attacker, origin)
		if not done and attacker ~= f and K.isEnemy(attacker, f) and K.dist(origin, f) <= 2.5 then
			counter(attacker)
		end
	end)
	K.buff(f, "LowStance", { duration = 0.5, label = "Low Stance" })
	c:channel(0.5, { stationary = false, halfSpeed = true })
	rm1()
	rm2()
end

-- 4 Redline Route
Kit[4] = function(c)
	local f = c.f
	local origin = c:feet()
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local total = math.min(16, K.flatDist(c:aimPoint(16), origin) + 2)
	local points = {}
	for i = 1, 3 do
		local p = origin + dir * K.m(total * i / 3) + side * K.m((i % 2 == 1) and 2 or -2)
		points[i] = K.ground(p)
	end
	local markers = {}
	for i, p in ipairs(points) do
		markers[i] = K.FX.sphere(p + Vector3.new(0, 1, 0), 0.8, K.color(c), 4.2, 0.2)
	end
	c:recast(4, function(c2)
		if c2.p60 then
			points[3] = c2:aimPoint(16)
			if markers[3] then
				markers[3].Position = points[3] + Vector3.new(0, 1, 0)
			end
		end
		local hitCount = {}
		for i = 1, 3 do
			local from = f.root.Position
			local to = K.Hit.standAt(points[i])
			local passed = {}
			K.path(c2, function(a)
				return from:Lerp(to, a)
			end, 0.16)
			for _, h in ipairs(K.Hit.segment(from, to, K.m(0.8), K.enemyFilter(c2))) do
				local t = h.f
				if not passed[t] and (hitCount[t] or 0) < 2 then
					passed[t] = true
					hitCount[t] = (hitCount[t] or 0) + 1
					K.dmg(c2, t, 35, { melee = true })
				end
			end
			if markers[i] then
				markers[i]:Destroy()
			end
		end
		c2.recovery = 0.25
	end, {
		onExpire = function()
			for _, m in ipairs(markers) do
				if m.Parent then
					m:Destroy()
				end
			end
		end,
	})
end

-- 5 Frame Perfect (ultimate)
local function release(c, frame)
	local f = c.f
	local charges = frame.charges
	frame.charges = 0
	K.clearRes(f, "Counterstrikes")
	local speedMult = c.unstable and 2 or 1
	local lockedDir = c:dir()
	for _ = 1, charges do
		if not K.alive(f) then
			break
		end
		local t = K.nearestEnemy(f, 10)
		local dir
		if c.unstable then
			dir = lockedDir -- no steering
		else
			dir = t and K.flat(t.root.Position - f.root.Position) or c:dir()
		end
		local dist = t and math.min(10, K.flatDist(t, f)) or 6
		local struck = false
		if c.unstable then
			f.noDodge = true
		end
		K.dash(c, dir, dist, 0.25 / speedMult, {
			passWidth = 1.6,
			onPass = function(tt)
				if not struck then
					struck = true
					K.dmg(c, tt, 60, { melee = true })
				end
			end,
		})
		task.wait(0.05)
	end
	f.noDodge = nil
	if c.unstable then
		-- Impossible Footwork: exhausted at the last endpoint
		K.slow(f, f, 0.4, 1.5, "Exhausted")
	end
end

Kit[5] = function(c)
	local f = c.f
	local frame = { charges = 0 }
	f.state.frame = frame
	K.res(f, "Counterstrikes", 0, 4)
	K.FX.highlight(f.model, K.color(c), 6, 0.8)
	local released = false
	local form
	form = c:form(6, {
		onEnd = function()
			f.state.frame = nil
			if not released then
				released = true
				release(c, frame)
			end
		end,
	})
	c:recast(6, function(c2)
		if not released then
			released = true
			release(c2, frame)
			form.finish("recast")
		end
	end)
end

return Kit
