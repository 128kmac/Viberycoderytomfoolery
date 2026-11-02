-- 40 Ghost — Phasing windows and anchored haunting
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local SPIRIT = Color3.fromRGB(190, 230, 255)

local function haunt(f, t)
	K.mark(f, t, "Haunt", 5, { label = "Haunt", color = SPIRIT })
end

-- Passive: Haunt Anchor
function Kit.passive.dealt(f, target, info)
	local c = info.opts.cast
	if c and info.kind == "direct" and not c.data.noHaunt and not target.isSummon then
		haunt(f, target)
	end
end

local function hauntNear(f, rM)
	for _, t in ipairs(K.enemies(f, rM)) do
		if K.has(t, "Haunt") then
			return true
		end
	end
	return false
end

-- try to pass through an ordinary wall up to 1 m thick in direction dir
local function tryPhaseThrough(f, dir)
	local origin = f.root.Position
	local res = K.Hit.raycast(origin, dir * K.m(1.2), false)
	if not res then
		return false
	end
	local far = res.Position + dir * K.m(1.6)
	local back = workspace:Raycast(far, -dir * K.m(1.6), K.Hit.worldParams)
	if back then
		local thickness = (back.Position - res.Position).Magnitude
		if thickness <= K.m(1) then
			local dest = back.Position + dir * K.m(0.8)
			local stand = K.Hit.findLegal(dest)
			if stand and (stand - dest).Magnitude < K.m(1.5) then
				S.Fighter.teleport(f, stand)
				return true
			end
		end
	end
	return false
end

-- 1 Cold Touch
Kit[1] = function(c)
	local f = c.f
	local reach = (c.p60 and f.state.reappearedAt and K.now() - f.state.reappearedAt < 1) and 6 or 4
	c.data.noHaunt = true
	K.melee(c, {
		range = reach,
		arc = 70,
		color = SPIRIT,
		hit = function(t)
			local was = K.has(t, "Haunt")
			K.dmg(c, t, 75, { melee = true })
			if was then
				K.slow(c, t, 0.2, 2, "Cold")
			else
				haunt(f, t)
			end
		end,
	})
end

-- 2 Phase Walk
Kit[2] = function(c)
	local f = c.f
	local dur = 1.2 + (hauntNear(f, 8) and 0.5 or 0)
	if c.p60 then
		local decoy = K.decoyModel(f, f.root.CFrame, SPIRIT)
		game:GetService("Debris"):AddItem(decoy, dur)
	end
	f.invulnUntil = math.max(f.invulnUntil or 0, K.now() + dur)
	f.noBasic = true
	f.disabled = { [1] = true, [3] = true, [4] = true }
	local restore = K.conceal(f, dur, 0.7)
	local crossed = false
	c.recovery = 0
	K.every(0.1, dur, function()
		if not crossed and f.humanoid and f.humanoid.MoveDirection.Magnitude > 0.1 then
			crossed = tryPhaseThrough(f, K.flat(f.humanoid.MoveDirection))
		end
		return true
	end)
	K.after(dur, function()
		f.noBasic = nil
		f.disabled = nil
		f.state.reappearedAt = K.now()
		restore()
	end)
end

-- 3 Poltergeist Cabinet
local function findProp(c)
	local pos = c:aimPoint(14)
	local best, bd
	for _, o in ipairs(K.objects(c, pos, 4)) do
		if o.hp <= 150 and not o.isUlt and not o.data.possessed and (o.owner == nil or o.owner == c.f or K.isEnemy(c.f, o.owner)) then
			local d = (o.part.Position - pos).Magnitude
			if not bd or d < bd then
				best, bd = o, d
			end
		end
	end
	return best
end
Kit.requires = {
	[3] = function(c)
		if findProp(c) then
			return true
		end
		return false, "No loose prop (150 durability or less)"
	end,
	[4] = function(c)
		if c:target(16, { filter = function(t)
			return K.has(t, "Haunt")
		end }) then
			return true
		end
		return false, "Needs a visible haunted enemy"
	end,
}
Kit[3] = function(c)
	local f = c.f
	local prop = findProp(c)
	if not prop then
		return
	end
	prop.data.possessed = true
	K.FX.highlight(prop.part, SPIRIT, 5, 0.3)
	f.stationary += 1
	local released = false
	local function release(cc, throw)
		if released then
			return
		end
		released = true
		f.stationary -= 1
		if not prop.alive then
			return
		end
		if throw then
			local from = prop.part.Position + Vector3.new(0, 1, 0)
			local t = cc:target(30)
			local dir = t and (t.root.Position - from).Unit or K.flat(cc:aimPoint(30) - from)
			S.Objects.remove(prop, "thrown")
			K.proj(cc, { origin = from, dir = dir, range = 20, speed = 26, width = 1.2, shape = "Block", size = prop.part.Size, color = prop.part.Color, dmg = 120, kind = "physical" })
		else
			prop.data.possessed = nil
		end
	end
	if c.p60 then
		c:channel(0.4, {
			stationary = false,
			tick = 0.05,
			onTick = function()
				if prop.alive then
					prop.part.CFrame += K.flat(c:aimPoint(14) - prop.part.Position) * K.m(3 / 8)
				end
			end,
		})
	end
	c:recast(5, function(c2)
		release(c2, true)
	end, {
		onExpire = function()
			release(c, false)
		end,
	})
end

-- 4 Haunting Return
Kit[4] = function(c)
	local f = c.f
	local t = c:target(16, { filter = function(t)
		return K.has(t, "Haunt")
	end })
	if not t then
		return
	end
	local behind = t.root.Position - K.flat(t.root.CFrame.LookVector) * K.m(2)
	local sil = K.decoyModel(f, CFrame.new(behind) * f.root.CFrame.Rotation, SPIRIT)
	game:GetService("Debris"):AddItem(sil, 0.7)
	if not c:wait(0.7) then
		return
	end
	if not K.alive(t) then
		return
	end
	behind = t.root.Position - K.flat(t.root.CFrame.LookVector) * K.m(2)
	if K.blink(c, K.ground(behind), { throughWalls = false }) then
		K.unmark(t, "Haunt")
		c:face(t.root.Position - f.root.Position)
		if c.p60 then
			K.shield(c, f, 70, 3, "HauntingReturn")
		end
	end
end

-- 5 House of the Unseen (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	local lamps = {}
	for i = 0, 3 do
		local a = math.rad(i * 90 + 45)
		lamps[i + 1] = K.object(c, {
			name = "SpiritLamp",
			pos = K.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(5)),
			size = Vector3.new(0.8, 1.6, 0.8),
			hp = 100,
			duration = 7,
			isUlt = true,
			color = SPIRIT,
			material = Enum.Material.Neon,
			onDestroy = c.unstable and function()
				K.Combat.damage(nil, f, 40, { kind = "true", tag = "lamp backlash" })
			end or nil,
		})
	end
	local transitions = c.unstable and 4 or 2
	c:recast(7, function(c2)
		local aim = c2:aimPoint(30)
		local best, bd
		for _, l in ipairs(lamps) do
			if l.alive then
				local d = (l.part.Position - aim).Magnitude
				if not bd or d < bd then
					best, bd = l, d
				end
			end
		end
		if not best then
			return nil
		end
		local depart = c2:feet()
		K.telegraph(c2, depart, 3, 0.5, SPIRIT)
		K.after(0.5, function()
			K.circle(c2, depart, 3, { dmg = 90, color = SPIRIT })
		end)
		K.blink(c2, K.ground(best.part.Position) + Vector3.new(K.m(1), 0, 0), { throughWalls = true })
		transitions -= 1
		if transitions > 0 then
			return "keep"
		end
		return nil
	end)
end

return Kit
