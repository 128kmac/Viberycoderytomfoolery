-- 51 Lava — Slow terrain pressure and cooling crust
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local LAVA = Color3.fromRGB(255, 70, 0)
local CRUST = Color3.fromRGB(60, 45, 40)

-- Passive: Cooling Cycle — pools are molten for 4 s, then 120-durability crust for 5 s
local function pool(c, pos, radius, opts)
	opts = opts or {}
	local f = c.f
	local z = K.zone(c, {
		pos = pos,
		radius = radius,
		duration = opts.duration or 4,
		tick = 0.5,
		dmg = (opts.dps or 20) / 2,
		color = LAVA,
		transparency = 0.25,
		includeOwner = opts.everyone,
		dmgAll = opts.everyone,
		targets = opts.everyone and "all" or "enemies",
		tags = { molten = true },
		finish = function(zz, reason)
			if reason == "expired" and not opts.noCrust then
				local crust = K.object(c, { name = "Crust", pos = zz.pos, size = Vector3.new(radius * 2, 0.3, radius * 2), hp = 120, duration = 5, color = CRUST, material = Enum.Material.Basalt, neutral = opts.neutralCrust })
				crust.data.crust = true
			end
		end,
	})
	if opts.everyone then
		z.targetMode = "all"
	end
	return z
end
Kit.pool = pool

-- 1 Melt Glob
Kit[1] = function(c)
	local hit = false
	K.lob(c, {
		range = 18,
		speed = 16,
		width = 0.8,
		color = LAVA,
		hit = function(t)
			hit = true
			K.dmg(c, t, 90, { projectile = true })
		end,
		land = function(pos)
			if not hit then
				for _, t in ipairs(K.enemiesIn(c, pos, 1.2)) do
					K.dmg(c, t, 90)
					break
				end
			end
			pool(c, K.ground(pos), c.p60 and 3 or 2)
		end,
	})
end

-- 2 Basalt Step
Kit[2] = function(c)
	local f = c.f
	local pos = c:aimPoint(5, 3)
	local dir = c:dir()
	local cf = CFrame.lookAt(pos + Vector3.new(0, K.m(1), 0), pos + Vector3.new(0, K.m(1), 0) + dir)
	if c.p60 and c.mod then
		cf *= CFrame.Angles(math.rad(-20), 0, 0)
	end
	local plat = K.object(c, { name = "BasaltStep", cf = cf, size = Vector3.new(3, 0.6, 3), hp = 180, duration = 6, color = CRUST, material = Enum.Material.Basalt })
	plat.data.crust = true
	K.leap(c, pos + Vector3.new(0, K.m(1.4), 0), 0.4, 2)
	local _ = f
end

-- 3 Lava Vein
Kit[3] = function(c)
	local origin = c:feet()
	local dir = c:dir()
	local hit = {}
	local function vein(from, d)
		K.telegraphLine(c, from, d, 10, 1.2, 0.9, LAVA)
		return d
	end
	vein(origin, dir)
	local branch = c.p60 and K.rotate(dir, 30) or nil
	if branch then
		vein(origin + dir * K.m(4), branch)
	end
	task.wait(0.9)
	local function erupt(from, d)
		K.line(c, from, d, 10, 1.2, { color = LAVA, hit = function(t)
			if not hit[t] then
				hit[t] = true
				K.dmg(c, t, 130, { fromPos = from })
			end
		end })
		K.zone(c, { shape = "rect", pos = from, dir = d, width = 1, length = 10, duration = 4, tick = 0.5, dmg = 10, color = LAVA, tags = { molten = true } })
	end
	erupt(origin, dir)
	if branch then
		erupt(origin + dir * K.m(4), branch)
	end
end

-- 4 Crustbreaker
Kit.requires = {
	[4] = function(c)
		for _, o in ipairs(K.owned(c.f)) do
			if o.data.crust then
				return true
			end
		end
		return false, "No owned crust"
	end,
}
Kit[4] = function(c)
	local f = c.f
	local aim = c:aimPoint(14)
	local crusts = {}
	for _, o in ipairs(K.owned(f)) do
		if o.data.crust then
			table.insert(crusts, o)
		end
	end
	table.sort(crusts, function(a, b)
		return (a.part.Position - aim).Magnitude < (b.part.Position - aim).Magnitude
	end)
	for i = 1, math.min(2, #crusts) do
		local pos = K.ground(crusts[i].part.Position)
		S.Objects.remove(crusts[i], "broken")
		K.circle(c, pos, 3, {
			dmg = 100,
			color = LAVA,
			hit = function(t)
				if c.p60 then
					local molten = K.zonesNear(t.root.Position, 10, "Lava")
					if molten[1] then
						K.knock(c, t, molten[1].pos, 2)
					end
				end
			end,
		})
	end
end

-- 5 Mantle Breach (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(22)
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local vents = {}
	for i = -1, 1 do
		local p = K.ground(center + side * K.m(i * 3))
		local rim = K.object(c, { name = "VentRim", pos = p, size = Vector3.new(1.6, 0.6, 1.6), hp = 140, duration = 5, isUlt = true, color = CRUST, material = Enum.Material.Basalt })
		table.insert(vents, { pos = p, rim = rim })
	end
	local pools = {}
	for _, v in ipairs(vents) do
		K.telegraph(c, v.pos, 3, 1, LAVA)
		task.wait(1)
		local dmg = v.rim.alive and 110 or 50
		K.circle(c, v.pos, 3, { dmg = dmg, color = LAVA })
		if v.rim.alive then
			S.Objects.remove(v.rim, "erupted")
		end
		table.insert(pools, pool(c, v.pos, 2))
	end
	if c.unstable then
		for _, p in ipairs(pools) do
			p:remove("joined")
		end
		-- Core Exposure: a shared lava lake; its crust is neutral afterwards
		pool(c, center, 8, { duration = 4, dps = 25, everyone = true, neutralCrust = true })
	end
	local _ = f
end

return Kit
