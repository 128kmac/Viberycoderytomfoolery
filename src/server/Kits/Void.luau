-- 95 Void — Finite cancellation and empty boundaries (cancelled damage never becomes a resource)
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local VOID = Color3.fromRGB(15, 0, 30)
local EDGE = Color3.fromRGB(150, 90, 220)

local function setAbsence(f, n)
	f.state.absence = math.clamp(n, 0, 2)
	K.res(f, "Absence", f.state.absence, 2, 1)
end
local function consume(f)
	if f.state.absence > 0 then
		setAbsence(f, f.state.absence - 1)
		f.state.lastCancel = K.now()
		return true
	end
	return false
end

-- Passive: Absence Charges
function Kit.passive.init(f)
	setAbsence(f, 2)
	f.state.lastCancel = 0
end
function Kit.passive.tick(f, dt, now)
	if f.state.absence < 2 and now - f.state.lastCancel >= 5 then
		f.state.lastCancel = now
		setAbsence(f, f.state.absence + 1)
	end
end

-- suppress an ordinary enemy ground field: its duration keeps running; it resumes if still active
local function suppress(z, seconds)
	if z.data.suppressed then
		return false
	end
	z.data.suppressed = true
	local savedTick = z.onTick
	z.onTick = nil
	local vis = z.visual
	if vis then
		vis.Transparency = 0.95
	end
	K.after(seconds, function()
		z.data.suppressed = nil
		if z.alive then
			z.onTick = savedTick
			if vis and vis.Parent then
				vis.Transparency = 0.65
			end
		end
	end)
	return true
end

-- 1 Null Shard
Kit[1] = function(c)
	local f = c.f
	local passed = false
	local dmg = 75
	K.proj(c, {
		range = 20,
		width = 0.4,
		shape = "Block",
		size = Vector3.new(0.4, 0.4, 1.4),
		color = VOID,
		hit = function(t)
			K.dmg(c, t, dmg, { projectile = true })
		end,
		objDmg = 100, -- 25 extra against temporary constructs
		wall = function(_, _, obj)
			if obj and c.p60 and not passed and obj.hp <= 100 and not obj.invulnerable then
				passed = true
				dmg = 40
				S.Objects.destroy(obj, f)
				return "pass"
			end
			return nil
		end,
	})
	local _ = f
end

-- 2 Empty Palm
Kit.requires = {
	[2] = function(c)
		if (c.f.state.absence or 0) > 0 then
			return true
		end
		return false, "No Absence"
	end,
	[3] = function(c)
		if (c.f.state.absence or 0) > 0 then
			return true
		end
		return false, "No Absence"
	end,
}
Kit[2] = function(c)
	local f = c.f
	local reach = c.p60 and 6 or 5
	local done = false
	K.FX.cone(f.root.Position, K.flat(f.root.CFrame.LookVector), K.m(reach), 90, EDGE, 0.35)
	K.every(0.02, 0.35, function()
		if done then
			return false
		end
		local fwd = K.flat(f.root.CFrame.LookVector)
		for _, p in ipairs(K.enemyProj(c, f.root.Position, reach)) do
			local to = K.flat(p.pos - f.root.Position)
			if p.kind ~= "ultimate" and to:Dot(fwd) > math.cos(math.rad(45)) then
				if consume(f) then
					done = true
					S.Proj.stop(p, "nullified")
					K.FX.burst(p.pos, 1.5, VOID, 0.2)
				end
				return false
			end
		end
		return true
	end)
end

-- 3 Hollow Patch
Kit[3] = function(c)
	local f = c.f
	local pos = c:aimPoint(14)
	local moved = false
	local z = K.zone(c, { pos = pos, radius = 3, duration = 3, targets = "all", color = VOID, transparency = 0.5 })
	local used = false
	K.every(0.1, 3, function()
		if used or not z.alive then
			return false
		end
		for _, other in ipairs(K.zonesNear(z.pos, 3)) do
			if other ~= z and other.owner and K.isEnemy(f, other.owner) and not other.tags.ult then
				if consume(f) then
					used = true
					suppress(other, 3)
				end
				return false
			end
		end
		return true
	end)
	if c.p60 then
		c:recast(3, function(c2)
			if not moved and z.alive then
				moved = true
				z:move(z.pos + K.flat(c2:aimPoint(30) - z.pos) * K.m(2))
			end
		end)
	end
end

-- 4 Vanishing Step
Kit[4] = function(c)
	local f = c.f
	local start = f.root.CFrame
	local image = K.decoyModel(f, start, Color3.fromRGB(40, 20, 60))
	game:GetService("Debris"):AddItem(image, 1)
	if K.blink(c, c:aimPoint(5, 5)) then
		c.recovery = 0.3
	end
	if c.p60 and (f.state.absence or 0) > 0 then
		local blocked = false
		K.every(0.03, 1, function()
			if blocked then
				return false
			end
			for _, p in ipairs(K.enemyProj(c, start.Position, 1.5)) do
				if p.kind ~= "ultimate" and consume(f) then
					blocked = true
					S.Proj.stop(p, "afterimage")
				end
				return false
			end
			return true
		end)
	end
end

-- 5 Boundary of Nothing (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(18)
	local nodes = {}
	for i = 0, 3 do
		local a = math.rad(i * 90)
		nodes[i + 1] = K.object(c, { name = "BoundaryNode", pos = K.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(7)), size = Vector3.new(0.8, 1.6, 0.8), hp = 100, duration = 6, isUlt = true, color = VOID, material = Enum.Material.Neon })
	end
	K.FX.ring(center, K.m(7), EDGE, 6, 0.3)
	local allowance = 6
	if c.unstable then
		for _, z in ipairs(K.zonesNear(center, 7)) do
			if z.owner and K.isEnemy(f, z.owner) then
				suppress(z, 3)
				break
			end
		end
		allowance = 3
	end
	local notches = {}
	for i = 1, allowance do
		local a = math.rad(i * 360 / allowance)
		notches[i] = K.FX.base({ shape = Enum.PartType.Ball, size = Vector3.one * 0.8, cf = CFrame.new(center + Vector3.new(math.cos(a) * K.m(7), 3, math.sin(a) * K.m(7))), color = EDGE })
		game:GetService("Debris"):AddItem(notches[i], 6)
	end
	local lastCancel = 0
	local prevDist = {}
	K.every(0.03, 6, function()
		local anyNode = false
		for _, n in ipairs(nodes) do
			if n.alive then
				anyNode = true
			end
		end
		if not anyNode or allowance <= 0 then
			return false
		end
		for _, p in pairs(S.Proj.list) do
			if p.alive and p.owner and K.isEnemy(f, p.owner) and p.kind ~= "ultimate" then
				local d = K.flatDist(p.pos, center)
				local before = prevDist[p]
				prevDist[p] = d
				if before and before > 7 and d <= 7 and K.now() - lastCancel >= 0.3 then
					lastCancel = K.now()
					allowance -= 1
					S.Proj.stop(p, "nothing")
					local notch = table.remove(notches)
					if notch then
						notch:Destroy()
					end
					if allowance <= 0 then
						return false
					end
				end
			end
		end
		return true
	end)
end

return Kit
