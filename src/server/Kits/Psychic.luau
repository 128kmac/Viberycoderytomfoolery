-- 73 Psychic — Telekinetic objects and interruptible focus
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local PINK = Color3.fromRGB(255, 100, 255)
local RunService = game:GetService("RunService")

local function setStones(f, n)
	n = math.clamp(n, 0, 3)
	f.state.stones = n
	K.res(f, "Stones", n, 3, 1)
	for i, p in ipairs(f.state.stoneParts or {}) do
		p.Transparency = i <= n and 0.1 or 1
	end
end

-- Passive: Focus Orbit
function Kit.passive.init(f)
	f.state.stoneParts = {}
	for i = 1, 3 do
		f.state.stoneParts[i] = K.FX.base({ shape = Enum.PartType.Ball, size = Vector3.one * 0.7, color = Color3.fromRGB(180, 150, 200), transparency = 1, material = Enum.Material.Slate })
	end
	f.state.orbitT = 0
	f.state.conn = RunService.Heartbeat:Connect(function(dt)
		if not K.alive(f) then
			return
		end
		f.state.orbitT += dt * 2
		for i, p in ipairs(f.state.stoneParts) do
			local a = f.state.orbitT + i * math.pi * 2 / 3
			p.Position = f.root.Position + Vector3.new(math.cos(a) * 2.2, 2.2, math.sin(a) * 2.2)
		end
	end)
	f.state.quiet = 0
	setStones(f, 0)
end
function Kit.passive.cleanup(f)
	if f.state.conn then
		f.state.conn:Disconnect()
	end
	for _, p in ipairs(f.state.stoneParts or {}) do
		p:Destroy()
	end
end
function Kit.passive.tick(f, dt, now)
	if now - (f.lastDirectHit or 0) >= 2 and f.state.stones < 3 then
		f.state.quiet += dt
		if f.state.quiet >= 2 then
			f.state.quiet = 0
			setStones(f, f.state.stones + 1)
		end
	else
		f.state.quiet = 0
	end
end

-- 1 Mind Lance
Kit[1] = function(c)
	local f = c.f
	local dir = c:dir3()
	K.proj(c, { dir = dir, range = 22, speed = 30, width = 0.35, color = PINK, dmg = 75 })
	if f.state.stones > 0 then
		setStones(f, f.state.stones - 1)
		task.wait(0.2)
		local d2 = dir
		if c.p60 then
			local want = c:dir3()
			local ang = math.deg(math.acos(math.clamp(want:Dot(dir), -1, 1)))
			d2 = ang <= 10 and want or dir:Lerp(want, 10 / ang).Unit
		end
		K.proj(c, { dir = d2, range = 22, speed = 30, width = 0.3, color = Color3.fromRGB(180, 150, 200), dmg = 30 })
	end
end

-- 2 Levitate Object (recast throws)
local function eligible(c)
	local pos = c:aimPoint(12)
	for _, o in ipairs(K.objects(c, pos, 3)) do
		if not o.isUlt and not o.tags.protected and o.hp <= 400 then
			return o
		end
	end
	return nil
end
Kit.requires = {
	[2] = function(c)
		if eligible(c) then
			return true
		end
		return false, "No loose prop there"
	end,
	[3] = function(c)
		if c:target(14) then
			return true
		end
		return false, "No visible enemy"
	end,
}
Kit[2] = function(c)
	local f = c.f
	local prop = eligible(c)
	if not prop then
		return
	end
	local size, color = prop.part.Size, prop.part.Color
	S.Objects.remove(prop, "levitated")
	local held = K.object(c, { name = "LevitatedProp", size = size / K.M, hp = 120, duration = 4.2, color = color, material = Enum.Material.Slate, noCap = true })
	K.FX.highlight(held.part, PINK, 4, 0.6)
	local thrown = false
	local rot = CFrame.new()
	K.every(0.03, 4, function()
		if thrown or not held.alive then
			return false
		end
		local aim = c:aimPoint(6)
		held.part.CFrame = CFrame.new(aim + Vector3.new(0, K.m(1.5), 0)) * rot
		return true
	end)
	local rotated = false
	c:recast(4, function(c2)
		if c2.p60 and c2.mod and not rotated then
			rotated = true
			rot = CFrame.Angles(0, math.rad(90), 0)
			return "keep"
		end
		if not held.alive then
			return nil
		end
		thrown = true
		local from = held.part.Position
		S.Objects.remove(held, "thrown")
		local t = c2:target(14)
		local dir = t and (t.root.Position - from).Unit or K.flat(c2:aimPoint(14) - from)
		K.proj(c2, { origin = from, dir = dir, range = 10, speed = 24, width = math.max(1, size.X / K.M), shape = "Block", size = size, color = color, kind = "physical", dmg = 90 })
		return nil
	end)
end

-- 3 Mental Thread
Kit[3] = function(c)
	local f = c.f
	local t = c:target(14)
	if not t then
		return
	end
	local broken = false
	local rm = K.hook(f, "taken", function(_, info)
		if info.kind == "direct" then
			broken = true
		end
	end, 2)
	local ok = c:channel(2, {
		stationary = false,
		halfSpeed = true,
		tick = 0.1,
		onTick = function()
			if broken or not K.alive(t) or not K.los(f, t) or K.dist(f, t) > 16 then
				broken = true
				return false
			end
			K.FX.beam(c:chest(), t.root.Position, 0.15, PINK, 0.12)
			K.slow(c, t, 0.2, 0.3, "Thread")
		end,
	})
	rm()
	if ok and not broken and K.alive(t) then
		K.dmg(c, t, 90)
		if c.p60 then
			K.addEnergy(f, 8)
		end
	end
end

-- 4 Repulsion Palm
Kit[4] = function(c)
	local f = c.f
	local stones = f.state.stones
	setStones(f, 0)
	local hits = K.cone(c, {
		range = 6,
		angle = 90,
		dmg = 80 + 10 * stones,
		color = PINK,
		hit = function(t)
			K.knock(c, t, f.root.Position, 3)
		end,
	})
	local real = 0
	for _, t in ipairs(hits) do
		if K.isReal(t) then
			real += 1
		end
	end
	if c.p60 and real >= 2 then
		setStones(f, 1)
	end
end

-- 5 Crown of Thought (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(18)
	local stones = {}
	for i = 0, 5 do
		local a = math.rad(i * 60)
		stones[i + 1] = K.object(c, { name = "CrownStone", cf = CFrame.new(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(6) + Vector3.new(0, K.m(1.5), 0)), size = 1.2, shape = "Ball", hp = 60, duration = 5.5, isUlt = true, color = Color3.fromRGB(180, 150, 200), material = Enum.Material.Slate })
	end
	local totals = {}
	local function launch(st, cc)
		if not st.alive then
			return
		end
		local from = st.part.Position
		local t = K.nearestEnemy(f, 20, from)
		local to = t and t.root.Position or center + Vector3.new(0, K.m(1), 0)
		K.FX.beam(from, to, 0.2, PINK, 0.5, 0.5)
		task.wait(0.5)
		if not st.alive then
			return
		end
		S.Objects.remove(st, "launched")
		K.proj(cc, {
			origin = from,
			dir = (to - from).Unit,
			range = 20,
			speed = 30,
			width = 1,
			color = Color3.fromRGB(180, 150, 200),
			hit = function(v)
				if (totals[v] or 0) < 3 then
					totals[v] = (totals[v] or 0) + 1
					K.dmg(cc, v, 90)
				end
			end,
		})
	end
	if c.unstable then
		K.Combat.control(f, "root", 2, f, { force = true })
		for i = 1, 3 do
			K.spawn(launch, stones[i], c)
			K.spawn(launch, stones[i + 3], c)
			task.wait(0.6)
		end
		return
	end
	local launched = 0
	c:recast(5, function(c2)
		local aim = c2:aimPoint(30)
		local best, bd
		for _, st in ipairs(stones) do
			if st.alive then
				local d = (st.part.Position - aim).Magnitude
				if not bd or d < bd then
					best, bd = st, d
				end
			end
		end
		if best then
			K.spawn(launch, best, c2)
			launched += 1
		end
		if launched < 3 then
			return "keep"
		end
		return nil
	end)
end

return Kit
