-- 92 Thorn — Punishing reckless crossings
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local THORN = Color3.fromRGB(70, 110, 40)

local function barb(f, t)
	if t.isSummon then
		return
	end
	local st = K.debuff(f, t, "Barb", { duration = 5, stacks = 1, max = 3, category = "barb", label = "Barb", data = { cleanseAll = true } })
	if st then
		st.data.cleanseAll = true
	end
end
Kit.barb = barb

-- Passive: Barbed Contact — the target's next dash consumes all Barbs for 15 each (max 45)
function Kit.passive.init(f)
	if f.state.unsub then
		f.state.unsub()
	end
	f.state.unsub = S.on("dashed", function(who)
		if f.kitName ~= "Thorn" or f.dead then
			return
		end
		local st = K.Status.get(who, "Barb")
		if st and st.source == f then
			local n = st.stacks
			K.Status.remove(who, "Barb", "consumed")
			K.Combat.damage(f, who, math.min(45, 15 * n), { kind = "dot", noGuard = true, element = "Thorn", tag = "barb" })
		end
	end)
end
function Kit.passive.cleanup(f)
	if f.state.unsub then
		f.state.unsub()
		f.state.unsub = nil
	end
end

-- 1 Briar Needle
Kit[1] = function(c)
	local f = c.f
	local hits = {}
	local dir = c:dir3()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	for i = 1, 2 do
		K.proj(c, {
			origin = c:chest() + side * (i == 1 and -0.4 or 0.4),
			dir = dir,
			range = 18,
			speed = 30,
			width = 0.25,
			shape = "Block",
			size = Vector3.new(0.2, 0.2, 1),
			color = THORN,
			kind = "physical",
			dmg = 35,
			hit = function(t)
				hits[t] = (hits[t] or 0) + 1
				if hits[t] == 2 then
					barb(f, t)
				end
			end,
		})
		if i == 1 then
			task.wait(c.p60 and 0.1 or 0.2)
		end
	end
end

-- 2 Barbed Hedge
Kit[2] = function(c)
	local f = c.f
	local pos = c:aimPoint(12)
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local segments = {}
	if c.p60 and c.mod then
		table.insert(segments, { pos = pos - side * K.m(1.5), len = 2 })
		table.insert(segments, { pos = pos + side * K.m(1.5), len = 2 })
	else
		table.insert(segments, { pos = pos, len = 5 })
	end
	local crossed = {}
	for _, sgm in ipairs(segments) do
		local h = K.wall(c, { name = "BarbedHedge", pos = K.ground(sgm.pos), dir = dir, width = sgm.len, height = 1.5, thick = 0.8, hp = 180, duration = 7, color = THORN, material = Enum.Material.Grass, transparency = 0 })
		K.every(0.1, 7, function()
			if not h.alive then
				return false
			end
			for _, t in ipairs(K.Hit.box(h.part.CFrame, h.part.Size + Vector3.new(1.5, 4, 1.5), K.enemyFilter(c))) do
				if not crossed[t] then
					crossed[t] = true
					K.dmg(c, t, 60, { kind = "field" })
					barb(f, t)
				end
			end
			return true
		end)
	end
end

-- 3 Roseguard
Kit[3] = function(c)
	local f = c.f
	K.shield(c, f, c.p60 and 120 or 90, 4, "Roseguard")
	local retaliated = {}
	local count = 0
	K.hook(f, "taken", function(_, info)
		local src = info.src
		if count >= 2 or not info.opts.melee or not src or not K.isEnemy(f, src) then
			return
		end
		local key = info.opts.cast or src
		if retaliated[key] then
			return
		end
		retaliated[key] = true
		count += 1
		K.dmg(c, src, 30, { kind = "direct", fromPos = f.root.Position })
		barb(f, src)
	end, 4)
end

-- 4 Catchthorn
Kit[4] = function(c)
	local f = c.f
	local pos = c:aimPoint(14)
	local loop = K.object(c, { name = "Catchthorn", pos = pos, size = Vector3.new(1.6, 0.2, 1.6), hp = 80, duration = 5.8, solid = false, queryable = true, color = THORN, material = Enum.Material.Grass })
	K.FX.ring(pos, K.m(0.9), THORN, 0.8, 0.2)
	task.wait(0.8)
	K.every(0.05, 5, function()
		if not loop.alive then
			return false
		end
		for _, t in ipairs(K.enemiesIn(f, pos, 0.9)) do
			K.dmg(c, t, 80, { kind = "field" })
			K.root(c, t, 0.7)
			if c.p60 then
				barb(f, t)
			end
			S.Objects.remove(loop, "triggered")
			return false
		end
		return true
	end)
end

-- 5 Crown of Briars (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(18)
	local gateOffset = 0
	local totals = {}
	local sections = {}
	local function buildSections()
		for _, s in ipairs(sections) do
			if s.obj.alive then
				S.Objects.remove(s.obj, "regrown")
			end
		end
		sections = {}
		-- eight slots of 45 degrees; two opposite slots stay open as gates
		for slot = 0, 7 do
			if slot ~= 0 and slot ~= 4 then
				local ang = slot * 45 + gateOffset
				local a = math.rad(ang)
				local d = Vector3.new(math.cos(a), 0, math.sin(a))
				local obj = K.wall(c, { name = "BriarSection", pos = K.ground(center + d * K.m(7)), dir = d, width = 5, height = 1.5, thick = 0.7, hp = 120, duration = 7, isUlt = true, color = THORN, material = Enum.Material.Grass, transparency = 0 })
				table.insert(sections, { obj = obj, angle = ang, parity = #sections % 2 })
			end
		end
	end
	buildSections()
	for beat = 1, 3 do
		if c.unstable and beat == 3 then
			K.FX.ring(center, K.m(7), Color3.fromRGB(255, 200, 120), 1, 0.3)
			task.wait(1)
			gateOffset = 60
			buildSections()
		end
		local active = {}
		for _, s in ipairs(sections) do
			if s.obj.alive and s.parity == (beat % 2) then
				table.insert(active, s)
				K.FX.sphere(s.obj.part.Position + Vector3.new(0, 2, 0), 0.8, Color3.fromRGB(255, 120, 160), 0.5, 0.2) -- buds
			end
		end
		task.wait(0.5)
		for _, s in ipairs(active) do
			for _, t in ipairs(K.enemiesRing(c, center, 3.5, 7.5)) do
				if K.inSector(K.angleOf(center, t.root.Position), s.angle - 22.5, 45) and (totals[t] or 0) < 3 then
					totals[t] = (totals[t] or 0) + 1
					K.dmg(c, t, 80, { fromPos = s.obj.part.Position })
					barb(f, t)
				end
			end
			K.arcFX(center, 5.25, s.angle - 22.5, s.angle + 22.5, THORN, 0.3, 3.5)
		end
		task.wait(1)
	end
end

return Kit
