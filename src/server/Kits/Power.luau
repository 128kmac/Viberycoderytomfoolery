-- 71 Power — Heavy force and committed lifting
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local GOLD = Color3.fromRGB(255, 220, 0)

-- Passive: Set Your Feet
function Kit.passive.tick(f, dt)
	local hum = f.humanoid
	if not hum then
		return
	end
	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	local dashing = f.dodgingUntil and f.dodgingUntil > K.now() or f.root:FindFirstChild("EBDisplace") ~= nil
	if not grounded or dashing or hum.Jump then
		f.state.braceT = 0
		if f.state.braced then
			f.state.braced = false
			K.clearRes(f, "Braced")
		end
	else
		f.state.braceT = (f.state.braceT or 0) + dt
		if f.state.braceT >= 1 and not f.state.braced then
			f.state.braced = true
			K.res(f, "Braced", "yes", nil, 1)
		end
	end
end
function Kit.passive.cast(f, c)
	if f.state.braced then
		f.state.braced = false
		K.clearRes(f, "Braced")
		c.data.braced = true
		-- resists light knockback during its active frames
		K.hook(f, "beforeDisplace", function(_, info)
			if info.dist <= K.m(2) then
				info.cancel = true
			end
		end, (c.def.windup or 0) + 0.6)
	end
end
function Kit.passive.beforeDeal(f, target, info)
	local c = info.opts.cast
	if c and c.data.braced and not c.data.braceUsed then
		c.data.braceUsed = true
		info.guardDmg = (info.guardDmg or 0) + 20
	end
end

-- 1 Heavy Hand
Kit[1] = function(c)
	local dir = c:dir()
	local hits = K.melee(c, {
		range = 4,
		arc = 60,
		dmg = 110,
		color = GOLD,
		hit = function(t)
			K.push(c, t, dir, 2)
		end,
	})
	if #hits == 0 then
		c.recovery = 0.6
	elseif c.p60 then
		local first = hits[1]
		local behind = first.root.Position + dir * K.m(1)
		K.line(c, behind, dir, 3, 2, { color = GOLD, hit = function(t)
			if t ~= first then
				K.dmg(c, t, 30)
			end
		end })
	end
end

-- 2 Lift and Carry
local function liftable(c)
	local front = c.f.root.Position + c:dir() * K.m(2)
	for _, o in ipairs(K.objects(c, front, 3)) do
		if not o.isUlt and o.hp <= 400 and not o.tags.protected and (o.owner == nil or o.owner == c.f or o.name:find("Boulder") or o.name:find("Debris")) then
			return o
		end
	end
	return nil
end
Kit.requires = {
	[2] = function(c)
		if liftable(c) then
			return true
		end
		return false, "No liftable prop in reach"
	end,
	[4] = function(c)
		if c:target(3) then
			return true
		end
		return false, "No one in grab range"
	end,
}
Kit[2] = function(c)
	local f = c.f
	local prop = liftable(c)
	if not prop then
		return
	end
	local size = prop.part.Size
	local color = prop.part.Color
	S.Objects.remove(prop, "lifted")
	local carried = K.object(c, { name = "CarriedProp", size = size / K.M, hp = 150, duration = 4.2, color = color, material = Enum.Material.Rock, noCap = true })
	f.jumpMult = c.p60 and 1 or 0
	local thrown = false
	local function throw(cc)
		if thrown then
			return
		end
		thrown = true
		f.jumpMult = 1
		if not carried.alive then
			return
		end
		local from = carried.part.Position
		S.Objects.remove(carried, "thrown")
		K.lob(cc, { origin = from, target = cc:aimPoint(10), speed = 20, width = math.max(1, size.X / K.M), shape = "Block", size = size, color = color, kind = "physical", dmg = 100, land = function(pos)
			K.circle(cc, pos, 1.5, { dmg = 0, color = color })
		end })
	end
	K.every(0.03, 4, function()
		if thrown or not carried.alive or not K.alive(f) then
			f.jumpMult = 1
			return false
		end
		local d = K.flat(f.root.CFrame.LookVector)
		local p = f.root.Position + d * K.m(1.5) + Vector3.new(0, 1, 0)
		carried.part.CFrame = CFrame.lookAt(p, p + d)
		return true
	end)
	c:recast(4, function(c2)
		throw(c2)
	end, {
		onExpire = function()
			throw(c)
		end,
	})
end

-- 3 Ground Breaker
Kit[3] = function(c)
	K.cone(c, {
		range = 6,
		angle = c.p60 and 75 or 60,
		dmg = 100,
		color = GOLD,
		hit = function(t)
			K.lift(c, t, 0.5, 1)
		end,
	})
	K.FX.burst(c:feet(), K.m(2), GOLD, 0.3)
end

-- 4 Iron Grip (guardable)
Kit[4] = function(c)
	local f = c.f
	local t = c:target(3)
	if not t then
		return
	end
	if t.guarding and K.Combat.facingAngle(t, f.root.Position) <= 60 then
		K.announce(t, "BLOCKED GRAB", Color3.fromRGB(200, 200, 255), 0.8)
		c.recovery = 0.6
		return
	end
	if K.Combat.isInvulnerable(t) then
		K.dmg(c, t, 1)
		return
	end
	K.Combat.control(t, "stun", 0.5, f)
	f.stationary += 1
	local ok = c:wait(0.5)
	f.stationary -= 1
	if not ok then
		return -- interruption releases the target without the throw
	end
	local dir = c:dir()
	if c.p60 and c.mod then
		dir = K.flat(dir:Cross(Vector3.yAxis))
	end
	K.dmg(c, t, 110, { unblockable = true, grab = true })
	K.push(c, t, dir, 4, { up = 15 })
end

-- 5 Atlas Moment (ultimate)
Kit[5] = function(c)
	local f = c.f
	local front = K.forward(c, 3)
	local slab = K.FX.base({ size = Vector3.new(K.m(6), K.m(1), K.m(6)), cf = CFrame.new(front), color = Color3.fromRGB(130, 120, 100), transparency = 0, material = Enum.Material.Slate })
	for _, t in ipairs(K.enemiesIn(c, front, 4)) do
		K.lift(c, t, 0.6, 1)
	end
	local target = front
	if c.unstable then
		task.wait(0.5) -- visible aiming time
		target = c:aimPoint(9)
	end
	K.telegraph(c, target, 5, 0.8, GOLD)
	for i = 1, 8 do
		slab.CFrame = CFrame.new(front:Lerp(target, i / 8) + Vector3.new(0, K.m(3) * math.sin(i / 8 * math.pi), 0))
		task.wait(0.1)
	end
	slab:Destroy()
	K.circle(c, target, 5, { dmg = 220, color = GOLD })
	if c.unstable then
		f.rupturePending = true -- Burnout begins on impact
	end
end

return Kit
