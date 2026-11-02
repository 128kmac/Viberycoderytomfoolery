-- 01 Acid — Armor erosion and corrosive lanes
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }

local function corrode(c, t, n)
	return K.debuff(c, t, "Corrosion", {
		duration = 6,
		stacks = n or 1,
		max = 3,
		drShred = 0.04,
		category = "corrosion",
		label = "Corrosion",
	})
end

-- Passive: Etched Weakness
function Kit.passive.dealt(f, target, info)
	if info.kind == "direct" and info.opts.cast and not info.opts.isBasic and not target.isSummon then
		corrode(f, target, 1)
	end
end
function Kit.passive.beforeDeal(f, target, info)
	if K.stacks(target, "Corrosion") >= 3 then
		info.shieldMult = (info.shieldMult or 1) * 1.25
	end
end

-- 1 Vitriol Needle
Kit[1] = function(c)
	K.proj(c, {
		speed = 24,
		width = 0.3,
		range = 20,
		shape = "Block",
		size = Vector3.new(0.3, 0.3, 2.4),
		objDmg = 100,
		hit = function(t)
			local hadShield = K.totalShield(t) > 0
			K.dmg(c, t, 70, { projectile = true })
			if c.p60 and hadShield then
				corrode(c, t, 1)
			end
		end,
	})
end

-- 2 Solvent Ribbon
Kit[2] = function(c)
	local origin = c:feet()
	local dir = c:dir()
	local steel = K.partner(c, "Steel", 12)
	local function ribbon(from, d, len)
		K.zone(c, {
			shape = "rect",
			pos = from,
			dir = d,
			width = 1.5,
			length = len,
			duration = 5,
			dmg = 20,
			above = 1,
			slow = steel and { 0.2, 2 } or nil,
			tags = { pool = true },
			tickFn = function(z)
				for _, o in ipairs(K.objects(c, z.pos + z.dir * z.length / 2, len / 2)) do
					S.Objects.stripLayer(o)
				end
			end,
		})
	end
	ribbon(origin, dir, 14)
	if c.p60 then
		-- one curved segment: bend toward the side of the aim point around a corner
		local aim = c:aimPoint(14)
		local side = K.flat(dir:Cross(Vector3.yAxis))
		local rel = (aim - origin):Dot(side)
		local bend = K.rotate(dir, rel >= 0 and -60 or 60)
		ribbon(origin + dir * K.m(14), bend, 6)
	end
end

-- 3 Caustic Shed
Kit[3] = function(c)
	local f = c.f
	K.cleanse(f, "slow", 1)
	if c.p60 then
		K.S.Status.removeStacks(f, "Corrosion", 1)
	end
	local pos = c:feet()
	K.object(c, {
		name = "AcidShell",
		pos = pos,
		size = Vector3.new(1.2, 2, 1.2),
		hp = 120,
		duration = 3,
		solid = false,
		blocks = true,
		transparency = 0.55,
		material = Enum.Material.Glass,
		onDestroy = function(obj)
			K.circle(c, pos, 2, { dmg = 45 })
		end,
	})
	K.dash(c, -c:dir(), 3, 0.18)
end

-- 4 Dissolution Brand
Kit.requires = {
	[4] = function(c)
		if c:target(12) then
			return true
		end
		return false, "No target in range"
	end,
}
Kit[4] = function(c)
	local t = c:target(12)
	if not t then
		return
	end
	local f = c.f
	if f.state.brand and K.alive(f.state.brand) then
		K.unmark(f.state.brand, "Brand")
	end
	f.state.brand = t
	local removeHook
	K.mark(c, t, "Brand", 5, {
		label = "Brand",
		onExpire = function(tt)
			if removeHook then
				removeHook()
			end
			K.dmg(c, tt, 90, { kind = "direct" })
			K.FX.burst(tt.root.Position, K.m(2), K.color(c), 0.3)
			if c.p60 then
				K.zone(c, { pos = K.feet(tt), radius = 2, duration = 3, dmg = 20, tags = { pool = true } })
			end
		end,
		onRemove = function(_, _, reason)
			if reason ~= "expired" and removeHook then
				removeHook()
			end
		end,
	})
	removeHook = K.hook(t, "beforeShield", function(tt, info)
		if K.has(tt, "Brand") then
			info.amount = math.max(0, info.amount - 100)
			if info.amount <= 0 then
				info.cancel = true
			end
			K.S.Status.get(tt, "Brand").onExpire = nil
			K.unmark(tt, "Brand")
			K.FX.burst(tt.root.Position, K.m(1.5), K.color(c), 0.25)
		end
	end, 5.1)
end

-- 5 Basilisk Rain (ultimate)
Kit[5] = function(c)
	local center = c:aimPoint(24)
	local R = 8
	K.FX.ring(center, K.m(R), K.color(c), 3.4, 0.4)
	local bands = { { R * 2 / 3, R }, { R / 3, R * 2 / 3 }, { 0, R / 3 } }
	local gap = math.random(0, 359)
	for i, band in ipairs(bands) do
		local gapFrom = (gap + (i - 1) * 120) % 360
		local width = 70
		-- warning for this ring, gap visibly marked
		K.arcFX(center, (band[1] + band[2]) / 2, gapFrom + width, gapFrom + 360, Color3.fromRGB(255, 70, 70), 1, band[2] - band[1])
		K.arcFX(center, (band[1] + band[2]) / 2, gapFrom, gapFrom + width, Color3.fromRGB(120, 255, 140), 1, 0.3)
		if not c:wait(1) then
			-- independent once marked: the remaining rings still fall
		end
		if i == 3 and c.unstable then
			-- moving acid wave sweeps across the zone; it also hits the caster
			local dir = K.flat(Vector3.new(math.random() - 0.5, 0, math.random() - 0.5))
			local start = center - dir * K.m(R)
			local hit = {}
			for step = 0, 16 do
				local p = start + dir * K.m(R * 2) * (step / 16)
				K.FX.rect(CFrame.lookAt(p, p + dir) * CFrame.Angles(0, math.rad(90), 0), K.m(1), K.m(R * 2), 0.12, K.color(c), 0.3)
				for _, t in ipairs(K.Hit.box(CFrame.lookAt(p, p + dir), Vector3.new(K.m(R * 2), K.m(3), K.m(1.2)), function(t)
					return not hit[t]
				end)) do
					hit[t] = true
					K.Combat.damage(c.f, t, 120, { cast = c, isUlt = true, fromPos = p, element = "Acid" })
				end
				task.wait(0.06)
			end
			-- Universal Solvent: Acid pools turn neutral and can hurt the caster
			for _, z in ipairs(K.ownedZones(c.f, "pool")) do
				z.includeOwner = true
				z.targetMode = "all"
			end
		else
			for _, t in ipairs(K.enemiesRing(c, center, band[1], band[2])) do
				if not K.inSector(K.angleOf(center, t.root.Position), gapFrom, width) then
					K.dmg(c, t, 90, { fromPos = center + Vector3.new(0, 10, 0) })
				end
			end
			for _, o in ipairs(K.enemyObjects(c, center, band[2])) do
				K.objDmg(c, o, 150)
			end
			K.FX.ring(center, K.m(band[2]), K.color(c), 0.3, K.m(band[2] - band[1]))
		end
	end
end

return Kit
