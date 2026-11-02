-- 07 Ash — Persistent aftermath and ember management
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local GREY = Color3.fromRGB(120, 115, 110)
local EMBER = Color3.fromRGB(255, 120, 40)

local function piles(f)
	local out = {}
	for _, p in ipairs(f.state.piles or {}) do
		if p.alive then
			table.insert(out, p)
		end
	end
	f.state.piles = out
	return out
end

local function setEmbers(f, n)
	f.state.embers = math.clamp(n, 0, 3)
	K.res(f, "Embers", f.state.embers, 3, 1)
	K.res(f, "Ash", #piles(f), 5, 2)
end

local function addPile(f, pos)
	local ps = piles(f)
	if #ps >= 5 then
		S.Objects.remove(ps[1], "replaced")
	end
	local p = K.object(f, {
		name = "AshPile",
		pos = pos,
		size = Vector3.new(1.4, 0.3, 1.4),
		hp = 1,
		duration = 40,
		solid = false,
		blocks = false,
		prop = true,
		noLabel = true,
		noCap = true,
		color = GREY,
		material = Enum.Material.Sand,
	})
	table.insert(f.state.piles, p)
	setEmbers(f, f.state.embers or 0)
	return p
end
Kit.addPile = addPile

-- Passive: What Remains
function Kit.passive.init(f)
	f.state.piles = {}
	setEmbers(f, 0)
	f.state.unsub = S.on("objectDestroyed", function(obj, src)
		if src == f and obj.name ~= "AshPile" and obj.part then
			addPile(f, K.ground(obj.part.Position))
		end
	end)
end
function Kit.passive.cleanup(f)
	if f.state.unsub then
		f.state.unsub()
	end
end
function Kit.passive.dealt(f, target, info)
	if info.opts.cast and not info.opts.isBasic and info.kind == "direct" then
		local now = K.now()
		if not f.state.lastPile or now - f.state.lastPile > 0.8 then
			f.state.lastPile = now
			addPile(f, K.feet(target))
		end
	end
end
function Kit.passive.tick(f)
	if (f.state.embers or 0) >= 3 then
		return
	end
	local my = K.feet(f)
	for _, p in ipairs(piles(f)) do
		if K.flatDist(p.part.Position, my) < 1.4 then
			S.Objects.remove(p, "collected")
			setEmbers(f, f.state.embers + 1)
			break
		end
	end
end

-- 1 Cinder Finger
Kit[1] = function(c)
	local f = c.f
	local ps = piles(f)
	local function fire(origin, dir)
		K.proj(c, {
			origin = origin,
			dir = dir,
			range = 18,
			width = 0.4,
			color = EMBER,
			dmg = 55,
			hit = function(t)
				K.burn(c, t, 20, 2)
			end,
		})
	end
	if c.mod and (f.state.embers or 0) > 0 and #ps >= 1 then
		setEmbers(f, f.state.embers - 1)
		-- emerge from the owned pile nearest the aim point
		local aim = c:aimPoint(30)
		local exit, ed
		for _, p in ipairs(ps) do
			local d = (p.part.Position - aim).Magnitude
			if not ed or d < ed then
				exit, ed = p, d
			end
		end
		local origin = exit.part.Position + Vector3.new(0, 2, 0)
		local target = c:target(30)
		local dir = target and (target.root.Position - origin).Unit or K.flat(aim - origin)
		K.FX.sphere(origin, 1.2, EMBER, c.p60 and 0.25 or 0.6, 0.2)
		if c.p60 then
			task.wait(0.25)
		end
		fire(origin, dir)
	else
		fire(nil, nil)
	end
end

-- 2 Soot Veil
Kit[2] = function(c)
	local pos = c:aimPoint(12)
	local veil = K.FX.sphere(pos + Vector3.new(0, K.m(1.5), 0), K.m(4), Color3.fromRGB(60, 58, 55), 5, 0.35)
	local coughed = {}
	local z = K.zone(c, {
		pos = pos,
		radius = 4,
		duration = 5,
		targets = "all",
		color = Color3.fromRGB(80, 78, 75),
		transparency = 0.9,
		enter = function(_, t)
			t.untargetable += 1
			if K.isEnemy(c.f, t) and not coughed[t] then
				coughed[t] = true
				K.dmg(c, t, 35, { kind = "field" })
			end
		end,
		exit = function(_, t)
			t.untargetable = math.max(0, t.untargetable - 1)
		end,
		finish = function(zz)
			for t in pairs(zz.inside) do
				t.untargetable = math.max(0, t.untargetable - 1)
			end
		end,
	})
	if c.p60 then
		-- drag the cloud 2 metres toward the aim while channeling
		local dir = c:dir()
		c:channel(0.6, {
			stationary = false,
			tick = 0.1,
			onTick = function()
				local np = z.pos + dir * K.m(2 / 6)
				z:move(np)
				veil.Position = np + Vector3.new(0, K.m(1.5), 0)
			end,
		})
	end
end

-- 3 Ember Rake
Kit[3] = function(c)
	local f = c.f
	local ps = piles(f)
	table.sort(ps, function(a, b)
		return (a.part.Position - f.root.Position).Magnitude < (b.part.Position - f.root.Position).Magnitude
	end)
	local used = 0
	for _, p in ipairs(ps) do
		if used >= 3 then
			break
		end
		if K.flatDist(p.part.Position, f.root.Position) <= 10 then
			used += 1
			K.FX.beam(p.part.Position, f.root.Position, 0.4, EMBER, 0.2)
			S.Objects.remove(p, "raked")
		end
	end
	setEmbers(f, f.state.embers or 0)
	local dmg = 45 + 35 * used
	K.cone(c, { range = 10, angle = 100, dmg = dmg, color = EMBER, hit = function(t)
		K.knock(c, t, f.root.Position, 2)
	end })
	if c.p60 then
		for _, o in ipairs(K.enemyObjects(c, f.root.Position + c:dir() * K.m(5), 5)) do
			addPile(f, K.ground(o.part.Position))
		end
	end
end

-- 4 Cremation Bed
Kit[4] = function(c)
	local pos = c:aimPoint(16)
	local slowed = false
	K.zone(c, {
		pos = pos,
		radius = 5,
		duration = 6,
		dmg = 18,
		color = Color3.fromRGB(150, 70, 40),
		tickFn = function(_, list)
			for _, t in ipairs(list) do
				if K.isEnemy(c.f, t) then
					K.debuff(c, t, "Smolder", { duration = 1.2, healMult = 0.75, label = "Healing -25%" })
				end
			end
		end,
		enter = function(_, t, first)
			if c.p60 and not slowed and first and K.isEnemy(c.f, t) then
				slowed = true
				K.slow(c, t, 0.2, 2)
			end
		end,
	})
end

-- 5 The Last Ember (ultimate)
Kit[5] = function(c)
	local f = c.f
	local ps = piles(f)
	if #ps == 0 then
		local aim = c:aimPoint(22)
		for i = 0, 2 do
			local a = math.rad(i * 120)
			addPile(f, K.ground(aim + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(2.5)))
		end
		ps = piles(f)
	end
	for _, p in ipairs(ps) do
		K.FX.highlight(p.part, EMBER, 1, 0.2)
	end
	task.wait(1)
	local taken = {}
	local sum = Vector3.zero
	for _, p in ipairs(ps) do
		if p.alive then
			local pos = p.part.Position
			sum += pos
			K.FX.burst(pos + Vector3.new(0, 1, 0), K.m(3), EMBER, 0.35)
			for _, t in ipairs(K.enemiesIn(c, pos, 3)) do
				if (taken[t] or 0) < 3 then
					taken[t] = (taken[t] or 0) + 1
					K.dmg(c, t, 90, { fromPos = pos })
				end
			end
			task.wait(0.15)
		end
	end
	local centroid = K.ground(sum / math.max(1, #ps))
	for _, p in ipairs(piles(f)) do
		S.Objects.remove(p, "erupted")
	end
	setEmbers(f, f.state.embers or 0)
	-- soot bank
	K.FX.sphere(centroid + Vector3.new(0, K.m(2), 0), K.m(8), Color3.fromRGB(55, 52, 50), 5, 0.5)
	local bank = K.zone(c, {
		pos = centroid,
		radius = 8,
		duration = 5,
		targets = "all",
		transparency = 0.9,
		enter = function(_, t)
			t.untargetable += 1
		end,
		exit = function(_, t)
			t.untargetable = math.max(0, t.untargetable - 1)
		end,
		finish = function(zz)
			for t in pairs(zz.inside) do
				t.untargetable = math.max(0, t.untargetable - 1)
			end
		end,
	})
	if c.unstable then
		-- Funeral Ash: the bank burns from its perimeter inward for 150, including the caster
		task.wait(1)
		local hit = {}
		for step = 8, 0, -1 do
			K.FX.ring(centroid, K.m(math.max(0.5, step)), EMBER, 0.2, K.m(1))
			for _, t in ipairs(K.Hit.ring(centroid, K.m(math.max(0, step - 1)), K.m(step + 0.5), function(t)
				return not hit[t]
			end)) do
				hit[t] = true
				K.Combat.damage(f, t, 150, { cast = c, isUlt = true, fromPos = centroid, element = "Ash" })
			end
			task.wait(0.1)
		end
		bank:remove("burned")
		setEmbers(f, 0)
	end
end

return Kit
