-- 13 Circus — Performance setups and prop-based misdirection
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local RED = Color3.fromRGB(255, 80, 80)
local GOLD = Color3.fromRGB(255, 210, 80)

local function setEncore(f, n)
	f.state.encore = math.clamp(n, 0, 2)
	K.res(f, "Encore", f.state.encore, 2, 1)
end

-- Passive: Applause — three different abilities hitting within 6 s grant an Encore
function Kit.passive.init(f)
	f.state.hits = {}
	setEncore(f, 0)
end
function Kit.passive.dealt(f, target, info)
	local c = info.opts.cast
	if not c or c.isUlt or info.kind == "dot" or f.state.noApplause then
		return
	end
	local now = K.now()
	f.state.hits[c.slot] = now
	local distinct = 0
	for _, t in pairs(f.state.hits) do
		if now - t <= 6 then
			distinct += 1
		end
	end
	if distinct >= 3 then
		f.state.hits = {}
		setEncore(f, f.state.encore + 1)
	end
end
-- V: spend an Encore to repeat the last prop's utility at half duration (never its damage)
function Kit.action(f)
	if (f.state.encore or 0) <= 0 then
		K.notify(f, "No Encore")
		return
	end
	local last = f.state.lastProp
	if not last then
		K.notify(f, "No prop to repeat")
		return
	end
	setEncore(f, f.state.encore - 1)
	last()
end

-- 1 Juggler's Comets
Kit[1] = function(c)
	local f = c.f
	local target = c:aimPoint(18)
	local function club(delayBounce)
		K.lob(c, {
			target = target + Vector3.new(math.random(-10, 10) / 10, 0, math.random(-10, 10) / 10),
			speed = 20,
			gravityM = 18,
			width = 0.6,
			color = GOLD,
			dmg = 30,
			land = function(pos)
				for _, t in ipairs(K.enemiesIn(c, pos, 1.2)) do
					K.dmg(c, t, 30)
					break
				end
			end,
			wall = delayBounce and function(_, normal, _, p)
				if not p.data.bounced then
					p.data.bounced = true
					local n = normal
					p.vel = p.vel - 2 * p.vel:Dot(n) * n
					return "bounce"
				end
				return nil
			end or nil,
		})
	end
	club(false)
	task.wait(0.15)
	club(false)
	local held = c:hold(0.6)
	if held < 0.1 then
		task.wait(0.15)
	end
	club(c.p60)
end

-- 2 Trapeze Escape
local function swing(c, anchorPos, duration, kick)
	local f = c.f
	local start = f.root.Position
	local flatTo = K.flat(anchorPos - start)
	local dist = K.flatDist(anchorPos, start)
	local finish = start + flatTo * K.m(dist) * 2
	local anchorObj = c.data.anchor
	local dropped = false
	K.path(c, function(a)
		if anchorObj and not anchorObj.alive then
			dropped = true
			return f.root.Position
		end
		local p = start:Lerp(finish, a)
		return p - Vector3.new(0, math.sin(a * math.pi) * K.m(1), 0) + Vector3.new(0, a * K.m(1.5), 0)
	end, duration)
	if dropped then
		return
	end
	if kick then
		local hits = K.melee(c, { range = 2.5, arc = 120, dmg = 75 })
		local _ = hits
	end
end
Kit[2] = function(c)
	local f = c.f
	local anchorGround = c:aimPoint(14, 4)
	local anchorPos = anchorGround + Vector3.new(0, K.m(4), 0)
	c.data.anchor = K.object(c, {
		name = "Trapeze",
		pos = anchorGround + Vector3.new(0, K.m(3.5), 0),
		cf = CFrame.new(anchorPos),
		size = Vector3.new(1.5, 0.3, 0.3),
		hp = 100,
		duration = 3,
		solid = false,
		color = RED,
		material = Enum.Material.Metal,
	})
	local rope = K.FX.beam(anchorPos, f.root.Position, 0.15, GOLD, 1.2)
	local _ = rope
	local held = c:hold(1.2)
	swing(c, anchorPos, math.clamp(0.5 + held, 0.6, 2), true)
	f.state.lastProp = function()
		local cc = S.Cast.newCtx(f, 2, c.def)
		cc.data.anchor = nil
		K.spawn(swing, cc, f.root.Position + c:dir() * K.m(6) + Vector3.new(0, K.m(4), 0), 0.5, false)
	end
	if c.p60 then
		local ally = c:ally(10)
		if ally then
			local ac = S.Cast.newCtx(ally, 2, c.def)
			K.spawn(swing, ac, anchorPos, 0.8, false)
		end
	end
end

-- 3 False Bottom
local function trapdoors(c, duration)
	local f = c.f
	local a = c:feet()
	local b = c:aimPoint(12)
	local struck = {}
	local doors = {}
	for i, p in ipairs({ a, b }) do
		doors[i] = K.object(c, {
			name = "Trapdoor",
			pos = p,
			size = Vector3.new(2, 0.15, 2),
			hp = 100,
			duration = duration,
			solid = false,
			blocks = false,
			queryable = true,
			color = Color3.fromRGB(120, 70, 40),
			material = Enum.Material.WoodPlanks,
		})
	end
	K.every(0.1, duration, function()
		for _, d in ipairs(doors) do
			if d.alive then
				for _, t in ipairs(K.enemiesIn(f, K.ground(d.part.Position), 1.2)) do
					if not struck[t] then
						struck[t] = true
						K.FX.sound(d.part.Position, "ping", 0.6)
						K.dmg(c, t, 40, { kind = "field" })
					end
				end
			end
		end
		return true
	end)
	return doors
end
Kit[3] = function(c)
	local f = c.f
	local doors = trapdoors(c, 6)
	f.state.lastProp = function()
		local cc = S.Cast.newCtx(f, 3, c.def)
		trapdoors(cc, 3)
	end
	c:recast(6, function(c2)
		local d1, d2 = doors[1], doors[2]
		if not (d1.alive and d2.alive) then
			return
		end
		local my = f.root.Position
		local target = (d1.part.Position - my).Magnitude < (d2.part.Position - my).Magnitude and d2 or d1
		if c2.p60 then
			local double = K.decoyModel(f, f.root.CFrame, Color3.fromRGB(200, 170, 120))
			game:GetService("Debris"):AddItem(double, 1)
		end
		K.blink(c2, target.part.Position, { throughWalls = true })
		return "keep"
	end, { uses = 3 })
end

-- 4 Ring of Fireworks
Kit[4] = function(c)
	local f = c.f
	local center = c:aimPoint(16)
	local taken = {}
	local launchers = {}
	local colors = { RED, GOLD, Color3.fromRGB(80, 200, 255), Color3.fromRGB(120, 255, 120), Color3.fromRGB(255, 120, 255), Color3.fromRGB(255, 255, 255) }
	for i = 1, 6 do
		local a = math.rad(i * 60)
		launchers[i] = K.object(c, {
			name = "Launcher",
			pos = K.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(4)),
			size = Vector3.new(0.6, 1, 0.6),
			hp = 35,
			duration = 4,
			color = colors[i],
			material = Enum.Material.Neon,
		})
	end
	local order = { 1, 2, 3, 4, 5, 6 }
	if c.p60 and c.mod then
		order = { 6, 5, 4, 3, 2, 1 }
	end
	local music = K.partner(c, "Music", 20)
	for n, i in ipairs(order) do
		local l = launchers[i]
		if l.alive then
			local from = l.part.Position + Vector3.new(0, 1, 0)
			K.proj(c, {
				origin = from,
				dir = (center + Vector3.new(0, 1.5, 0) - from).Unit,
				range = 9,
				speed = 26,
				width = 0.5,
				color = colors[i],
				pierce = true,
				hit = function(t)
					if (taken[t] or 0) < 4 then
						taken[t] = (taken[t] or 0) + 1
						K.dmg(c, t, 35)
					end
					return "continue"
				end,
			})
		end
		if not music or n % 2 == 0 then
			task.wait(0.3)
		end
	end
end

-- 5 The Final Act (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	K.FX.disc(center, K.m(7), Color3.fromRGB(140, 30, 30), 6.2, 0.6)
	local platform
	if not c.unstable then
		platform = K.object(c, { name = "PerformerPlatform", pos = center, size = Vector3.new(2, 0.6, 2), hp = 200, duration = 6, isUlt = true, color = GOLD })
	end
	local _ = platform
	local sectors = { 0, 120, 240 }
	local done = {}
	local fired = 0
	f.state.noApplause = true
	local function fire(index, mult)
		local from = sectors[index]
		K.arcFX(center, 4, from, from + 120, RED, 0.5, 6)
		task.wait(0.5)
		for _, t in ipairs(K.enemiesIn(c, center, 7)) do
			if K.inSector(K.angleOf(center, t.root.Position), from, 120) then
				K.dmg(c, t, 90 * (mult or 1), { fromPos = center })
			end
		end
		K.FX.burst(center + Vector3.new(0, 1, 0), K.m(7), GOLD, 0.3)
	end
	local first
	local function nextSector(chosen)
		if fired >= 3 then
			return
		end
		local idx = chosen
		if not idx or done[idx] then
			for i = 1, 3 do
				if not done[i] then
					idx = i
					break
				end
			end
		end
		done[idx] = true
		fired += 1
		first = first or idx
		fire(idx)
		if fired == 3 and c.unstable then
			fire(first, 0.5)
		end
	end
	c:recast(6, function(c2)
		local ang = K.angleOf(center, c2:aimPoint(30))
		local idx = math.floor(ang / 120) % 3 + 1
		nextSector(idx)
		if fired < 3 then
			return "keep"
		end
		return nil
	end)
	-- unchosen sectors still perform on schedule
	for _ = 1, 3 do
		task.wait(1.8)
		if fired < 3 then
			nextSector(nil)
		end
	end
	f.state.noApplause = nil
end

return Kit
