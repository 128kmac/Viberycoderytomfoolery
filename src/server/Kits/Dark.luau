-- 20 Dark — Absence of light and resource suppression
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local BLACK = Color3.fromRGB(40, 20, 60)
local LUMINOUS = { Light = true, Solar = true, Star = true, Fire = true, Lava = true, Electric = true, Laser = true, Phoenix = true, Plasma = true }

local function setGloom(f, n)
	f.state.gloom = math.clamp(n, 0, 3)
	K.res(f, "Gloom", f.state.gloom, 3, 1)
end

-- Passive: Light Hunger
function Kit.passive.init(f)
	setGloom(f, 0)
end
function Kit.passive.dealt(f, target, info)
	local c = info.opts.cast
	if c and not c.data.gloomed and K.has(target, "Revealed") then
		c.data.gloomed = true
		setGloom(f, f.state.gloom + 1)
	end
end
function Kit.passive.cast(f, c)
	if c.slot <= 4 and (f.state.gloom or 0) > 0 and (c.def.energy or 0) > 0 then
		setGloom(f, f.state.gloom - 1)
		K.addEnergy(f, 5)
	end
end

local function extinguish(c, obj)
	if obj and LUMINOUS[obj.element or ""] and obj.owner and K.isEnemy(c.f, obj.owner) then
		obj.data.extinguishedUntil = K.now() + 3
		if obj.part then
			obj.part.Material = Enum.Material.SmoothPlastic
		end
		setGloom(c.f, c.f.state.gloom + 1)
		return true
	end
	return false
end

-- 1 Blackout Spear
Kit[1] = function(c)
	local pierced = false
	K.proj(c, {
		range = 22,
		width = 0.45,
		shape = "Block",
		size = Vector3.new(0.45, 0.45, 2.6),
		color = BLACK,
		dmg = 80,
		wall = function(_, _, obj)
			if obj and extinguish(c, obj) and c.p60 and not pierced then
				pierced = true
				return "pass"
			end
			return nil
		end,
	})
end

-- 2 Dusk Mantle
Kit[2] = function(c)
	local f = c.f
	K.shield(c, f, 100, 4, "DuskMantle")
	if c.p60 then
		K.cleanse(f, "reveal", 1)
	end
	K.every(0.25, 4, function()
		local has = false
		for _, sh in ipairs(f.shields) do
			if sh.name == "DuskMantle" then
				has = true
			end
		end
		if not has then
			return false
		end
		local st = K.Status.get(f, "Revealed")
		if st then
			st.expires -= 0.25 -- marks expire twice as fast
		end
		return true
	end)
end

-- 3 Unlit Corridor
Kit[3] = function(c)
	local f = c.f
	local origin = c:feet()
	local dir = c:dir()
	local function lane(from, d, len)
		local mid = from + d * K.m(len / 2) + Vector3.new(0, K.m(1.5), 0)
		local box = K.FX.base({ size = Vector3.new(K.m(3), K.m(3), K.m(len)), cf = CFrame.lookAt(mid, mid + d), color = Color3.fromRGB(8, 4, 14), transparency = 0.25, material = Enum.Material.SmoothPlastic })
		game:GetService("Debris"):AddItem(box, 5)
		local struck = {}
		K.zone(c, {
			shape = "rect",
			pos = from,
			dir = d,
			width = 3,
			length = len,
			duration = 5,
			targets = "all",
			noVisual = true,
			enter = function(_, t)
				if K.isEnemy(f, t) and not struck[t] then
					struck[t] = true
					K.dmg(c, t, 45, { kind = "field" })
				end
				t.untargetable += 1
			end,
			exit = function(_, t)
				t.untargetable = math.max(0, t.untargetable - 1)
			end,
			finish = function(z)
				for t in pairs(z.inside) do
					t.untargetable = math.max(0, t.untargetable - 1)
				end
			end,
		})
	end
	local len = 12
	if K.partner(c, "Light", 20) then
		len = 10
	end
	lane(origin, dir, c.p60 and 8 or len)
	if c.p60 then
		local side = K.flat(dir:Cross(Vector3.yAxis))
		local rel = (c:aimPoint(16) - origin):Dot(side)
		lane(origin + dir * K.m(8), rel >= 0 and side or -side, 4)
	end
end

-- 4 Extinguishing Grip
Kit[4] = function(c)
	local pos = c:aimPoint(10)
	if not K.warn(c, pos, 1.6, 0.6, BLACK) then
		return
	end
	K.FX.burst(pos + Vector3.new(0, 2, 0), K.m(1.6), BLACK, 0.3)
	for _, t in ipairs(K.enemiesIn(c, pos, 1.6)) do
		K.dmg(c, t, 110, { fromPos = pos })
		K.debuff(c, t, "Dimmed", { duration = 3, label = "Energy regen -50%" })
		t.energyRegenMult = 0.5
		local token = {}
		t.state.dimToken = token
		K.after(3, function()
			if t.state.dimToken == token then
				t.energyRegenMult = nil
			end
		end)
	end
	if c.p60 then
		for _, o in ipairs(K.enemyObjects(c, pos, 4)) do
			extinguish(c, o)
		end
	end
end

-- 5 Night Without Stars (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	local dome = K.FX.sphere(center, K.m(9), Color3.fromRGB(10, 6, 20), 6.2, 0.45)
	dome.Material = Enum.Material.SmoothPlastic
	local bands = { { 6, 9 }, { 3, 6 }, { 1.2, 3 } }
	if c.unstable then
		table.insert(bands, { 0, 1.2 })
		f.noEnergyRegen = true
		K.after(6, function()
			f.noEnergyRegen = nil
		end)
	end
	for i, b in ipairs(bands) do
		K.FX.ring(center, K.m(b[2]), Color3.fromRGB(200, 200, 230), 1.4, 0.25)
		K.FX.ring(center, K.m(math.max(0.4, b[1])), Color3.fromRGB(200, 200, 230), 1.4, 0.25)
		task.wait(1.4)
		local everyone = c.unstable and i == #bands
		local list = everyone and K.Hit.ring(center, K.m(b[1]), K.m(b[2]), function()
			return true
		end) or K.enemiesRing(c, center, b[1], b[2])
		for _, t in ipairs(list) do
			K.Combat.damage(f, t, 80, { cast = c, isUlt = true, fromPos = center, element = "Dark" })
		end
		K.FX.ring(center, K.m(b[2]), BLACK, 0.3, K.m(b[2] - b[1]))
	end
end

return Kit
