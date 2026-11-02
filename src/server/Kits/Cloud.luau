-- 14 Cloud — Buoyant platforms and stored weather
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local WHITE = Color3.fromRGB(235, 242, 255)

local function clouds(f)
	local out = {}
	for _, o in ipairs(K.owned(f, "Cloud")) do
		table.insert(out, o)
	end
	table.sort(out, function(a, b)
		return a.created < b.created
	end)
	return out
end

-- a solid cloud platform (supports two loads; heavier sinks at 2 m/s and dissolves on terrain)
local function makeCloud(f, pos, duration, hp, size)
	local cs = clouds(f)
	if #cs >= 3 then
		S.Objects.remove(cs[1], "replaced")
	end
	local o = K.object(f, {
		name = "Cloud",
		cf = CFrame.new(pos),
		size = size or Vector3.new(3, 0.6, 3),
		hp = hp or 120,
		duration = duration,
		color = WHITE,
		material = Enum.Material.SmoothPlastic,
		transparency = 0.15,
		noCap = true,
	})
	K.res(f, "Clouds", #clouds(f), 3, 1)
	return o
end
Kit.makeCloud = makeCloud

-- Passive: Condensation — load limit
function Kit.passive.tick(f, dt)
	for _, o in ipairs(clouds(f)) do
		local part = o.part
		local load = 0
		for _, t in pairs(S.fighters) do
			if K.alive(t) and not t.isSummon then
				local lp = part.CFrame:PointToObjectSpace(t.root.Position)
				if math.abs(lp.X) < part.Size.X / 2 + 1 and math.abs(lp.Z) < part.Size.Z / 2 + 1 and lp.Y > 0 and lp.Y < 5 then
					load += 1
				end
			end
		end
		if o.data.extraLoad then
			load += o.data.extraLoad
		end
		if load > 2 then
			part.CFrame -= Vector3.new(0, K.m(2) * dt, 0)
			if workspace:Raycast(part.Position, Vector3.new(0, -part.Size.Y, 0), K.Hit.arenaParams) then
				S.Objects.remove(o, "sank")
			end
		end
	end
	K.res(f, "Clouds", #clouds(f), 3, 1)
end

-- 1 Nimbus Disc
Kit[1] = function(c)
	local f = c.f
	K.proj(c, {
		range = 18,
		speed = 20,
		width = 1,
		shape = "Block",
		size = Vector3.new(2.5, 0.5, 2.5),
		color = WHITE,
		dmg = 65,
		finish = function(pos)
			local p = pos + Vector3.new(0, 0.5, 0)
			local cloud = makeCloud(f, p, 6)
			if c.p60 then
				K.every(0.05, 1, function(i)
					if cloud.alive then
						cloud.part.CFrame += Vector3.new(0, K.m(2) / 20, 0)
					end
					return i < 20
				end)
			end
		end,
	})
end

-- 2 Updraft Lift
Kit[2] = function(c)
	local f = c.f
	local pos = c:aimPoint(10)
	local col = K.FX.base({ shape = Enum.PartType.Cylinder, size = Vector3.new(K.m(6), K.m(4), K.m(4)), cf = CFrame.new(pos + Vector3.new(0, K.m(3), 0)) * CFrame.Angles(0, 0, math.rad(90)), color = WHITE, transparency = 0.8, material = Enum.Material.ForceField })
	game:GetService("Debris"):AddItem(col, 2)
	local lifted = {}
	K.every(0.1, 2, function()
		for _, t in ipairs(K.Hit.cylinder(pos, K.m(2), function()
			return true
		end)) do
			if not lifted[t] then
				if K.isEnemy(f, t) then
					lifted[t] = true
					K.dmg(c, t, 45, { kind = "direct", fromPos = pos })
					K.lift(c, t, 0.8, 5)
				elseif t.humanoid and t.humanoid.Jump or (t.humanoid and t.humanoid.FloorMaterial == Enum.Material.Air) then
					lifted[t] = true
					local exit = Vector3.new(0, 1, 0)
					S.Fighter.displace(t, exit, K.m(5), 0.8)
				end
			end
		end
		return true
	end)
end

-- 3 Heavy Weather
Kit.requires = {
	[3] = function(c)
		if #clouds(c.f) > 0 then
			return true
		end
		return false, "Needs a Cloud"
	end,
	[4] = function(c)
		if #clouds(c.f) >= 2 then
			return true
		end
		return false, "Needs two Clouds"
	end,
}
Kit[3] = function(c)
	local f = c.f
	local aim = c:aimPoint(16)
	local best, bd
	for _, o in ipairs(clouds(f)) do
		local d = (o.part.Position - aim).Magnitude
		if not bd or d < bd then
			best, bd = o, d
		end
	end
	if not best then
		return
	end
	best.part.Color = Color3.fromRGB(70, 75, 90)
	if c.p60 then
		for _, p in ipairs(K.projNear(best.part.Position, 3)) do
			S.Proj.stop(p, "rained")
		end
	end
	local ground = K.ground(best.part.Position)
	K.telegraph(c, ground, 3, 0.8)
	task.wait(0.8)
	local from = best.part.Position
	S.Objects.remove(best, "dropped")
	K.FX.beam(from, ground, 2, Color3.fromRGB(70, 75, 90), 0.25)
	K.circle(c, ground, 3, {
		dmg = 120,
		color = Color3.fromRGB(90, 95, 110),
		hit = function(t)
			K.stun(c, t, 0.5)
		end,
	})
end

-- 4 Cloudbank Bridge
Kit[4] = function(c)
	local f = c.f
	local cs = clouds(f)
	local a, b = cs[#cs], cs[#cs - 1]
	local pa, pb = a.part.Position, b.part.Position
	local mid = (pa + pb) / 2
	local bridge = K.object(c, {
		name = "VaporBridge",
		cf = CFrame.lookAt(mid, pb),
		size = Vector3.new(2, 0.4, (pa - pb).Magnitude / K.M),
		hp = 180,
		duration = 7,
		color = WHITE,
		transparency = 0.3,
		noCap = true,
	})
	K.every(0.1, 7, function()
		if not (a.alive and b.alive) then
			S.Objects.remove(bridge, "endpoint broken")
			return false
		end
		return bridge.alive
	end)
end

-- 5 Kingdom Aloft (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(22)
	local plats = {}
	for i = 0, 2 do
		local a = math.rad(i * 120 + 30)
		local p = center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(5) + Vector3.new(0, K.m(4), 0)
		plats[i + 1] = K.object(c, {
			name = "SkyPlatform",
			cf = CFrame.new(p),
			size = Vector3.new(4, 0.8, 4),
			hp = 200,
			duration = 8,
			isUlt = true,
			color = WHITE,
			transparency = 0.1,
		})
	end
	local function drop(o, dmg)
		if not o.alive then
			return
		end
		local ground = K.ground(o.part.Position)
		local from = o.part.Position
		S.Objects.remove(o, "dropped")
		K.FX.beam(from, ground, 3, Color3.fromRGB(200, 210, 230), 0.25)
		K.circle(c, ground, 3, { dmg = dmg })
	end
	if c.unstable then
		task.wait(1)
		for _, o in ipairs(plats) do
			K.telegraph(c, K.ground(o.part.Position), 3, 0.6)
		end
		task.wait(0.6)
		for _, o in ipairs(plats) do
			drop(o, 80)
		end
		return
	end
	c:recast(8, function(c2)
		local aim = c2:aimPoint(40)
		local best, bd
		for _, o in ipairs(plats) do
			if o.alive then
				local d = K.flatDist(o.part.Position, aim)
				if not bd or d < bd then
					best, bd = o, d
				end
			end
		end
		if best then
			K.telegraph(c2, K.ground(best.part.Position), 3, 0.4)
			task.wait(0.4)
			drop(best, 100)
		end
		for _, o in ipairs(plats) do
			if o.alive then
				return "keep"
			end
		end
		return nil
	end)
end

return Kit
