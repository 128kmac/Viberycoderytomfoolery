-- 39 Flower — Bloom cycles and restorative traps
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local PINK = Color3.fromRGB(255, 150, 190)
local GREEN = Color3.fromRGB(90, 200, 90)

local function buds(f)
	local out = {}
	for _, o in ipairs(K.owned(f, "Bud")) do
		table.insert(out, o)
	end
	table.sort(out, function(a, b)
		return a.created < b.created
	end)
	return out
end
local function isOpen(b)
	return K.now() >= b.data.opensAt
end
local function show(f)
	K.res(f, "Buds", #buds(f), 3, 1)
end

-- plant a bud that opens after 2 s and expires after 8; onOpen(bud) fires once
local function plant(c, pos, hp, onOpen)
	local f = c.f
	local list = buds(f)
	if #list >= 3 then
		S.Objects.remove(list[1], "replaced")
	end
	local b = K.object(c, { name = "Bud", pos = pos, size = Vector3.new(0.9, 1, 0.9), shape = "Ball", hp = hp or 80, duration = 8, color = GREEN, material = Enum.Material.Grass, noCap = true })
	local accel = (K.partner(c, "Water", 15) and 0.5 or 0)
	b.data.opensAt = K.now() + 2 - accel
	b.data.onOpen = onOpen
	K.every(0.1, 8, function()
		if not b.alive then
			return false
		end
		if isOpen(b) and not b.data.opened then
			b.data.opened = true
			b.part.Color = PINK
			b.part.Material = Enum.Material.SmoothPlastic
			b.part.Size = Vector3.new(K.m(1.4), K.m(0.6), K.m(1.4))
			if b.data.onOpen then
				S.safe(b.data.onOpen, b)
			end
			return false
		end
		return true
	end)
	show(f)
	return b
end
Kit.plant = plant

-- Passive: Bud Cycle — V uproots the nearest unopened bud for 5 Energy
function Kit.action(f)
	for _, b in ipairs(buds(f)) do
		if not isOpen(b) then
			S.Objects.remove(b, "uprooted")
			K.addEnergy(f, 5)
			show(f)
			return
		end
	end
end
function Kit.passive.tick(f)
	show(f)
end

-- 1 Petal Razor
Kit[1] = function(c)
	local f = c.f
	local dir = c:dir3()
	local taken = {}
	for i = 1, 4 do
		local spread = (i - 2.5) * 2
		local returned = false
		K.proj(c, {
			dir = K.rotate(dir, spread),
			range = 18,
			speed = 28,
			width = 0.3,
			color = PINK,
			hit = function(t)
				if (taken[t] or 0) < 4 then
					taken[t] = (taken[t] or 0) + 1
					K.dmg(c, t, 20, { projectile = true })
				end
			end,
			step = function(p)
				if not p.data.fanned then
					for _, b in ipairs(buds(f)) do
						if isOpen(b) and (b.part.Position - p.pos).Magnitude < K.m(1.2) then
							p.data.fanned = true
							p.vel = K.rotate(p.vel, spread * 3.75)
							break
						end
					end
				end
			end,
			finish = function(_, reason)
				if c.p60 and i == 1 and reason ~= "hit" and not returned then
					returned = true
					for _, b in ipairs(buds(f)) do
						if not isOpen(b) then
							b.data.opensAt -= 0.5
							break
						end
					end
				end
			end,
		})
	end
end

-- 2 Restorative Bloom
Kit[2] = function(c)
	local pos = c:aimPoint(12)
	plant(c, pos, 80, function(b)
		K.every(1, 3, function()
			if not b.alive then
				return false
			end
			local allies = K.alliesIn(c, K.ground(b.part.Position), 3, true)
			table.sort(allies, function(x, y)
				return x.health / x.maxHealth < y.health / y.maxHealth
			end)
			if c.p60 and #allies >= 2 then
				K.heal(c, allies[1], 12.5)
				K.heal(c, allies[2], 12.5)
			elseif allies[1] then
				K.heal(c, allies[1], 25)
			end
			return true
		end)
	end)
end

-- 3 Pollen Bell
Kit[3] = function(c)
	local pos = c:aimPoint(16)
	plant(c, pos, 80, function(b)
		local at = K.ground(b.part.Position)
		K.FX.sphere(at + Vector3.new(0, K.m(1), 0), K.m(4), Color3.fromRGB(255, 240, 150), 3, 0.7)
		K.zone(c, {
			pos = at,
			radius = 4,
			duration = 3,
			dmg = 20,
			slow = { 0.2, 1.2 },
			color = Color3.fromRGB(255, 240, 150),
			transparency = 0.85,
			tickFn = function(_, list)
				if c.p60 then
					for _, t in ipairs(list) do
						if K.isEnemy(c.f, t) then
							K.reveal(c, t, 1.2)
						end
					end
				end
			end,
		})
	end)
end

-- 4 Thornless Snare
Kit[4] = function(c)
	local f = c.f
	local pos = c:aimPoint(14)
	local trigger
	if c.p60 then
		for _, b in ipairs(buds(f)) do
			if isOpen(b) and K.flatDist(b.part.Position, pos) <= 3 then
				trigger = b
				break
			end
		end
	end
	local lotus = trigger or K.object(c, { name = "Lotus", pos = pos, size = Vector3.new(1, 0.6, 1), hp = 100, duration = 1, color = PINK, material = Enum.Material.SmoothPlastic })
	local at = trigger and K.ground(trigger.part.Position) or pos
	K.telegraph(c, at, 2, trigger and 0.3 or 0.8, PINK)
	task.wait(trigger and 0.3 or 0.8)
	if not lotus.alive then
		return
	end
	K.circle(c, at, 2, {
		dmg = 100,
		color = PINK,
		hit = function(t)
			K.root(c, t, 0.6)
		end,
	})
	if not trigger then
		S.Objects.remove(lotus, "closed")
	end
end

-- 5 Garden of Returning Spring (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	local flowers = {}
	for i = 1, 6 do
		local a = math.rad(i * 60)
		local role = (i % 2 == 0) and "heal" or "pollen"
		local o = K.object(c, {
			name = "Blossom",
			pos = K.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(4)),
			size = Vector3.new(1.2, 0.8, 1.2),
			hp = 100,
			duration = 6,
			isUlt = true,
			color = role == "heal" and Color3.fromRGB(140, 255, 160) or Color3.fromRGB(255, 220, 120),
			onDestroy = c.unstable and function(obj)
				for _, t in ipairs(K.Hit.cylinder(obj.part.Position, K.m(2), function()
					return true
				end)) do
					K.Combat.damage(nil, t, 50, { kind = "direct", fromPos = obj.part.Position })
				end
			end or nil,
		})
		o.data.role = role
		table.insert(flowers, o)
	end
	local tick = 0
	K.every(1, 6, function()
		tick += 1
		local healed, pulsed = {}, {}
		for _, o in ipairs(flowers) do
			if o.alive then
				local pos = K.ground(o.part.Position)
				local heals = c.unstable or o.data.role == "heal"
				local pollen = c.unstable or o.data.role == "pollen"
				if heals then
					for _, a in ipairs(K.alliesIn(c, pos, 3, true)) do
						if not healed[a] then
							healed[a] = true
							K.heal(c, a, 20)
						end
					end
				end
				if pollen and tick % 2 == 0 then
					K.FX.burst(pos + Vector3.new(0, 1, 0), K.m(3), Color3.fromRGB(255, 230, 130), 0.3)
					for _, t in ipairs(K.enemiesIn(c, pos, 3)) do
						if not pulsed[t] then
							pulsed[t] = true
							K.dmg(c, t, 35, { fromPos = pos })
						end
					end
				end
			end
		end
		return true
	end)
	local _ = f
end

return Kit
