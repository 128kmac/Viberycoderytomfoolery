-- 38 Fire — Ignition and managed fuel
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local FIRE = Color3.fromRGB(255, 90, 20)
local WHITEFIRE = Color3.fromRGB(255, 245, 230)

-- Passive: Kindling — three Kindling consumed by a Fire hit become a 45 burn over 3 s
function Kit.passive.dealt(f, target, info)
	if info.kind ~= "direct" or not info.opts.cast then
		return
	end
	if K.stacks(target, "Kindling") >= 3 then
		K.unmark(target, "Kindling")
		K.burn(f, target, 45, 3)
	else
		K.debuff(f, target, "Kindling", { duration = 5, stacks = 1, max = 3, category = "burn", label = "Kindling" })
	end
	-- Backdraft seal ignition
	local seal = f.state.seal
	if seal and seal.alive and info.opts.cast.slot ~= 3 and K.flatDist(target, seal.pos) <= 3 then
		f.state.igniteSeal(seal)
	end
end

local function embers(f)
	return K.owned(f, "Ember")
end

local function ember(c, pos)
	local f = c.f
	local e = K.object(c, { name = "Ember", pos = pos, size = Vector3.new(2, 0.2, 2), hp = 1, duration = 3, solid = false, blocks = false, prop = true, noLabel = true, noCap = false, color = FIRE, material = Enum.Material.Neon })
	K.every(0.1, 3, function()
		if not e.alive then
			return false
		end
		for _, t in ipairs(K.enemiesIn(f, pos, 1, { below = 1, above = 2 })) do
			K.dmg(c, t, 15, { kind = "field" })
			S.Objects.remove(e, "triggered")
			return false
		end
		local seal = f.state.seal
		if c.p60 and seal and seal.alive and K.flatDist(pos, seal.pos) <= 3 then
			f.state.igniteSeal(seal)
		end
		return true
	end)
	return e
end

-- 1 Cinder Shot
Kit[1] = function(c)
	local f = c.f
	K.proj(c, {
		range = 22,
		width = 0.6,
		color = FIRE,
		dmg = 70,
		finish = function(pos, reason)
			if reason == "wall" or reason == "range" then
				local g = K.ground(pos)
				local seal = f.state.seal
				if seal and seal.alive and K.flatDist(g, seal.pos) <= 3 then
					f.state.igniteSeal(seal)
				end
				ember(c, g)
				if c.p60 then
					ember(c, g + K.flat(c:dir():Cross(Vector3.yAxis)) * K.m(1.2))
				end
			end
		end,
	})
end

-- 2 Flamewheel
Kit[2] = function(c)
	local f = c.f
	local start = c:feet()
	local dir = c:dir()
	local struck = {}
	local ring = K.FX.ring(start, K.m(1.2), FIRE, 0.4, 0.4)
	local _ = ring
	local traveled = K.dash(c, dir, 6, 0.35, {
		passWidth = 2,
		onPass = function(t)
			if not struck[t] then
				struck[t] = true
				K.dmg(c, t, 85, { melee = true })
			end
		end,
	})
	if c.p60 then
		local hit = {}
		K.zone(c, {
			shape = "rect",
			pos = start,
			dir = dir,
			width = 1.2,
			length = math.max(1, traveled),
			duration = 2,
			tick = 0.2,
			immediate = true,
			color = FIRE,
			tickFn = function(_, list)
				for _, t in ipairs(list) do
					if K.isEnemy(f, t) and not hit[t] then
						hit[t] = true
						K.dmg(c, t, 20, { kind = "field" })
					end
				end
			end,
		})
	end
end

-- 3 Backdraft Seal
Kit[3] = function(c)
	local f = c.f
	local pos = c:aimPoint(14)
	local seal = { pos = pos, alive = true }
	local zone = K.zone(c, { pos = pos, radius = 3, duration = 5, color = FIRE, transparency = 0.8, finish = function()
		seal.alive = false
	end })
	local center = K.FX.base({ shape = Enum.PartType.Ball, size = Vector3.one * 0.8, cf = CFrame.new(pos + Vector3.new(0, 0.4, 0)), color = FIRE })
	game:GetService("Debris"):AddItem(center, 5)
	f.state.seal = seal
	f.state.igniteSeal = function(s)
		if not s.alive then
			return
		end
		s.alive = false
		zone:remove("ignited")
		center:Destroy()
		K.circle(c, s.pos, 3, {
			dmg = 120,
			color = FIRE,
			hit = function(t)
				K.pull(c, t, s.pos, 2)
			end,
		})
	end
end

-- 4 Furnace Wall
Kit[4] = function(c)
	local f = c.f
	local center = c:aimPoint(12)
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local function curtain(from, d, len)
		local last = {}
		local mid = from + d * K.m(len / 2) + Vector3.new(0, K.m(1.2), 0)
		local vis = K.FX.base({ size = Vector3.new(K.m(0.4), K.m(2.4), K.m(len)), cf = CFrame.lookAt(mid, mid + d), color = FIRE, transparency = 0.4 })
		game:GetService("Debris"):AddItem(vis, 5)
		K.zone(c, {
			shape = "rect",
			pos = from,
			dir = d,
			width = 0.8,
			length = len,
			duration = 5,
			tick = 0.1,
			immediate = true,
			noVisual = true,
			tickFn = function(z, list)
				for _, t in ipairs(list) do
					if K.isEnemy(f, t) and (not last[t] or K.now() - last[t] >= 2) then
						last[t] = K.now()
						K.dmg(c, t, 80, { kind = "field" })
					end
				end
				-- burns away weak projectiles
				for _, p in pairs(S.Proj.list) do
					if p.alive and p.owner and K.isEnemy(f, p.owner) and (p.dmg or 30) < 40 then
						local lp = CFrame.lookAt(z.pos, z.pos + z.dir):PointToObjectSpace(p.pos)
						if math.abs(lp.X) < K.m(0.6) and -lp.Z >= 0 and -lp.Z <= K.m(len) and lp.Y < K.m(3) then
							S.Proj.stop(p, "burned")
						end
					end
				end
			end,
		})
	end
	if c.p60 and c.mod then
		curtain(center - side * K.m(3), side, 3)
		curtain(center, dir, 3)
	else
		curtain(center - side * K.m(3), side, 6)
	end
end

-- 5 Cremation Horizon (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(22)
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local color = c.unstable and WHITEFIRE or FIRE
	local extraLen = K.partner(c, "Wind", 20) and 2 or 0
	local emberTotals = {}
	for i = -1, 1 do
		local lineCenter = center + dir * K.m(3 * i)
		local from = lineCenter - side * K.m(4.5 + extraLen / 2)
		K.telegraphLine(c, from, side, 9 + extraLen, 1.6, 0.8, color)
		task.wait(0.8)
		local list
		if c.unstable then
			local mid = from + side * K.m((9 + extraLen) / 2)
			list = K.Hit.box(CFrame.lookAt(mid, mid + side), Vector3.new(K.m(1.6), K.m(4), K.m(9 + extraLen)), function()
				return true
			end)
		else
			list = K.enemiesLine(c, from, side, 9 + extraLen, 1.6)
		end
		for _, t in ipairs(list) do
			K.Combat.damage(f, t, 90, { cast = c, isUlt = true, fromPos = lineCenter, element = "Fire" })
		end
		K.line(c, from, side, 9 + extraLen, 1.6, { color = color })
	end
	-- existing embers ignite once
	for _, e in ipairs(embers(f)) do
		local pos = e.part.Position
		if K.flatDist(pos, center) <= 9 then
			for _, t in ipairs(K.enemiesIn(c, pos, 1.5)) do
				local d = math.min(25, 50 - (emberTotals[t] or 0))
				if d > 0 then
					emberTotals[t] = (emberTotals[t] or 0) + d
					K.dmg(c, t, d, { fromPos = pos })
				end
			end
			K.FX.burst(pos, K.m(1.5), color, 0.3)
		end
		if c.unstable or K.flatDist(pos, center) <= 9 then
			S.Objects.remove(e, "ignited")
		end
	end
	if K.partner(c, "Ash", 25) then
		local ash = K.partner(c, "Ash", 25)
		local kit = S.Kits.get("Ash")
		if kit and kit.addPile then
			kit.addPile(ash, center)
		end
	end
end

return Kit
