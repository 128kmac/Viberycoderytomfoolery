-- 10 Bone — Segmented armor and expendable skeletal tools
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local BONE = Color3.fromRGB(235, 225, 200)

local COST = { 1, 2, 1, 2, 0 }

local function setMarrow(f, n)
	f.state.marrow = math.clamp(n, 0, 5)
	K.res(f, "Marrow", f.state.marrow, 5, 1)
end

local function boneObject(c, opts)
	local f = c.f or c
	opts.color = opts.color or BONE
	opts.material = opts.material or Enum.Material.Marble
	local userDestroy = opts.onDestroy
	opts.onDestroy = function(obj, src)
		if not obj.data.noFragment then
			local frag = K.object(f, {
				name = "BoneFragment",
				pos = K.ground(obj.part.Position),
				size = 0.6,
				hp = 1,
				duration = 3,
				solid = false,
				blocks = false,
				prop = true,
				noLabel = true,
				noCap = true,
				color = BONE,
			})
			frag.data.origin = obj.id
		end
		if userDestroy then
			userDestroy(obj, src)
		end
	end
	return K.object(c, opts)
end

-- Passive: Marrow Economy
function Kit.passive.init(f)
	setMarrow(f, 5)
	f.state.regrow = 0
	f.state.fragCount = {}
end
function Kit.passive.tick(f, dt)
	if f.burnoutUntil and f.burnoutUntil > K.now() then
		return -- regrowth pauses during Burnout
	end
	if f.state.marrow < 5 then
		f.state.regrow += dt
		if f.state.regrow >= 4 then
			f.state.regrow = 0
			setMarrow(f, f.state.marrow + 1)
		end
	end
	for _, o in ipairs(K.owned(f, "BoneFragment")) do
		if K.flatDist(o.part.Position, f.root.Position) < 1.5 then
			local origin = o.data.origin or 0
			S.Objects.remove(o, "collected")
			f.state.fragCount[origin] = (f.state.fragCount[origin] or 0) + 1
			if f.state.fragCount[origin] == 2 then
				setMarrow(f, f.state.marrow + 1)
			end
		end
	end
end
function Kit.passive.cast(f, c)
	setMarrow(f, f.state.marrow - (COST[c.slot] or 0))
end

local function needMarrow(slot)
	return function(c)
		if (c.f.state.marrow or 0) >= COST[slot] then
			return true
		end
		return false, "Need " .. COST[slot] .. " Marrow"
	end
end
Kit.requires = { needMarrow(1), needMarrow(2), needMarrow(3), needMarrow(4) }

-- 1 Splinter Fan
Kit[1] = function(c)
	local fan = (c.p60 and c.mod) and 10 or 35
	local dir = c:dir3()
	for i = 0, 4 do
		local a = -fan / 2 + fan * i / 4
		K.proj(c, {
			dir = K.rotate(dir, a),
			range = 16,
			speed = 30,
			width = 0.25,
			shape = "Block",
			size = Vector3.new(0.25, 0.25, 1.2),
			color = BONE,
			dmg = 18,
			objDmg = 48,
		})
	end
end

-- 2 Ribcage Guard
Kit[2] = function(c)
	local f = c.f
	local ribs = {}
	local angles = { -45, 0, 45 }
	for i, a in ipairs(angles) do
		ribs[i] = boneObject(c, {
			name = "Rib",
			size = Vector3.new(0.9, 2.2, 0.3),
			hp = 70,
			duration = 4,
		})
		ribs[i].data.angle = a
	end
	K.every(0.03, 4, function()
		if not K.alive(f) then
			return false
		end
		local look = K.flat(f.root.CFrame.LookVector)
		for _, r in ipairs(ribs) do
			if r.alive then
				local d = K.rotate(look, r.data.angle)
				local p = f.root.Position + d * K.m(1.3)
				r.part.CFrame = CFrame.lookAt(p, p + d)
			end
		end
		return true
	end)
end

-- 3 Vertebral Vault
Kit[3] = function(c)
	local f = c.f
	local origin = c:feet()
	local dir = c:dir()
	local joints = {}
	for i = 1, 3 do
		joints[i] = boneObject(c, {
			name = "Vertebra",
			pos = K.ground(origin + dir * K.m(i * 3)),
			size = Vector3.new(0.9, 0.6, 0.9),
			hp = 60,
			duration = 4,
			solid = false,
		})
	end
	-- vault 6 metres upward along the spine
	local land = K.ground(origin + dir * K.m(4))
	K.leap(c, land, 0.6, 6)
	c:recast(4, function(c2)
		local length = joints[2].alive and 9 or 4.5
		K.line(c2, origin, dir, length, 2, { dmg = 75, color = BONE })
		for _, j in ipairs(joints) do
			if j.alive then
				j.data.noFragment = true
				S.Objects.remove(j, "collapsed")
			end
		end
	end)
end

-- 4 Ossuary Stakes
Kit[4] = function(c)
	local f = c.f
	local center = c:aimPoint(18)
	local stakes = {}
	local steel = K.partner(c, "Steel", 15)
	for i = 0, 3 do
		local a = math.rad(i * 90 + 45)
		local s = boneObject(c, {
			name = "Stake",
			pos = K.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(2.1)),
			size = Vector3.new(0.6, 2.2, 0.6),
			hp = 90,
			duration = 7,
		})
		table.insert(stakes, s)
	end
	if steel then
		S.Objects.reinforce(stakes[1], 60, steel)
		stakes[1].data.noFragment = true
	end
	if c.p60 then
		local a, b = stakes[1].part.Position, stakes[2].part.Position
		local mid = (a + b) / 2
		K.object(c, {
			name = "Crossbar",
			cf = CFrame.lookAt(mid, b),
			size = Vector3.new(0.4, 0.4, (a - b).Magnitude / K.M),
			hp = 60,
			duration = 7,
			color = BONE,
			material = Enum.Material.Marble,
		})
	end
	local last = {}
	K.every(0.2, 7, function()
		for _, s in ipairs(stakes) do
			if s.alive then
				for _, t in ipairs(K.enemiesIn(f, K.ground(s.part.Position), 1.1)) do
					if not last[t] or K.now() - last[t] >= 1 then
						last[t] = K.now()
						K.dmg(c, t, 40, { kind = "field" })
					end
				end
			end
		end
		return true
	end)
end

-- 5 Cathedral of Ribs (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	local supports = {}
	for i = 0, 5 do
		local a = math.rad(i * 60)
		supports[i + 1] = boneObject(c, {
			name = "RibSupport",
			pos = K.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(7)),
			size = Vector3.new(0.8, 4, 0.8),
			hp = 130,
			duration = 6.5,
			isUlt = true,
		})
		supports[i + 1].data.angle = i * 60
	end
	local dome = K.FX.sphere(center, K.m(7), BONE, 6.5, 0.9)
	local _ = dome
	local closed = false
	local function close(cc)
		if closed then
			return
		end
		closed = true
		cc:closeRecast()
		for wave = 1, 3 do
			local finalCollapse = c.unstable and wave == 3
			local dmg = finalCollapse and 160 or 80
			K.FX.ring(center, K.m(7 - wave * 2), BONE, 0.4, K.m(1.2))
			local targets = finalCollapse and K.Hit.cylinder(center, K.m(7), function()
				return true
			end) or K.enemiesIn(c, center, 7)
			for _, t in ipairs(targets) do
				local ang = K.angleOf(center, t.root.Position)
				local sector = math.floor(((ang + 30) % 360) / 60) + 1
				local sup = supports[sector]
				if sup and sup.alive then
					K.Combat.damage(f, t, dmg, { cast = c, isUlt = true, fromPos = center, element = "Bone" })
				end
			end
			task.wait(0.5)
		end
		if c.unstable then
			setMarrow(f, 0)
		end
	end
	c:recast(6, function(c2)
		close(c2)
	end, {
		onExpire = function()
			K.spawn(close, c)
		end,
	})
end

return Kit
