-- 35 Fairy — Tiny helpers and conditional bargains
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local PINK = Color3.fromRGB(255, 190, 255)

local function sprites(f)
	return K.summons(f, "Sprite")
end
local function freeSprite(f)
	for _, s in ipairs(sprites(f)) do
		if (s.data.busyUntil or 0) <= K.now() then
			return s
		end
	end
	return nil
end
local function show(f)
	local free = 0
	for _, s in ipairs(sprites(f)) do
		if (s.data.busyUntil or 0) <= K.now() then
			free += 1
		end
	end
	K.res(f, "Sprites", free, 3, 1)
end

local function makeSprite(f, hp, dur, name)
	local s = K.summon(f, {
		name = name or "Sprite",
		hp = hp or 40,
		duration = dur,
		speed = 10,
		size = 0.6,
		color = PINK,
		flying = 3,
		ai = "follow",
	})
	s.data.startHp = s.health
	return s
end

-- assign a sprite for up to 4 s; unharmed return grants 5 Energy; defeat returns after 7 s
local function assign(f, s, dur)
	s.data.busyUntil = K.now() + (dur or 4)
	s.data.startHp = s.health
	show(f)
	K.after(dur or 4, function()
		if K.alive(s) then
			s.sm.ai = "follow"
			s.sm.goal = nil
			if s.health >= s.data.startHp then
				K.addEnergy(f, 5)
			end
		end
		show(f)
	end)
end

-- Passive: Court Favor
function Kit.passive.init(f)
	f.state.respawns = {}
	K.after(0.5, function()
		if f.kitName == "Fairy" and not f.dead then
			for _ = 1, 3 do
				makeSprite(f)
			end
			show(f)
		end
	end)
end
function Kit.passive.cleanup(f)
	for _, s in ipairs(K.summons(f)) do
		S.Summons.remove(s, "cleanup")
	end
end
function Kit.passive.tick(f, dt, now)
	local n = #sprites(f)
	local pending = 0
	for i = #f.state.respawns, 1, -1 do
		if now >= f.state.respawns[i] then
			table.remove(f.state.respawns, i)
			if n < 3 then
				makeSprite(f)
				n += 1
			end
		else
			pending += 1
		end
	end
	if n + pending < 3 then
		table.insert(f.state.respawns, now + 7)
	end
	show(f)
end

local function needSprite(c)
	if freeSprite(c.f) then
		return true
	end
	return false, "No free sprite"
end
Kit.requires = {
	[1] = function(c)
		local ok, why = needSprite(c)
		if not ok then
			return false, why
		end
		if c:target(18) then
			return true
		end
		return false, "No target"
	end,
	[2] = needSprite,
	[4] = function(c)
		local n = 0
		for _, s in ipairs(sprites(c.f)) do
			if (s.data.busyUntil or 0) <= K.now() then
				n += 1
			end
		end
		if n >= 2 then
			return true
		end
		return false, "Needs two free sprites"
	end,
}

-- 1 Pixie Sting
Kit[1] = function(c)
	local f = c.f
	local s = freeSprite(f)
	local t = c:target(18)
	if not s or not t then
		return
	end
	assign(f, s, 4)
	s.sm.ai = "none"
	local t0 = K.now()
	-- loop toward the target, circle once for 0.6 s, then strike
	while K.alive(s) and K.alive(t) and K.dist(s, t) > 2.5 and K.now() - t0 < 2.5 do
		local d = (t.root.Position - s.root.Position)
		local side = K.flat(d):Cross(Vector3.yAxis)
		local p = s.root.Position + (d.Unit + side * 0.5).Unit * K.m(0.9)
		s.root.CFrame = CFrame.new(Vector3.new(p.X, t.root.Position.Y + 1.5, p.Z))
		task.wait(0.05)
	end
	local c0 = K.now()
	while K.alive(s) and K.alive(t) and K.now() - c0 < 0.6 do
		local a = (K.now() - c0) / 0.6 * math.pi * 2
		s.root.CFrame = CFrame.new(t.root.Position + Vector3.new(math.cos(a) * 4, 2, math.sin(a) * 4))
		if K.los(f, t) then
			K.reveal(c, t, 0.1)
		end
		task.wait(0.05)
	end
	if K.alive(s) and K.alive(t) then
		K.FX.beam(s.root.Position, t.root.Position, 0.2, PINK, 0.15)
		K.dmg(c, t, 60, { fromPos = s.root.Position })
	end
	if K.alive(s) then
		s.sm.ai = "follow"
	end
end

-- 2 Borrowed Wings
Kit[2] = function(c)
	local f = c.f
	local s = freeSprite(f)
	local ally = c:ally(10, true) or f
	assign(f, s, 4)
	s.sm.ai = "none"
	local used = false
	K.speed(ally, 0.1, 4, "Borrowed Wings")
	K.every(0.05, 4, function()
		if used or not K.alive(ally) then
			return false
		end
		if K.alive(s) then
			s.root.CFrame = CFrame.new(ally.root.Position + Vector3.new(0, 3, 0))
		end
		local hum = ally.humanoid
		if hum and hum.Jump and hum.FloorMaterial == Enum.Material.Air and (ally.root.AssemblyLinearVelocity.Y < 5) then
			used = true
			S.Fighter.displace(ally, Vector3.yAxis, K.m(3.5), 0.3)
			if c.p60 then
				K.shield(c, ally, 50, 3, "Wings")
			end
			return false
		end
		return true
	end)
end

-- 3 Faerie Bargain
Kit[3] = function(c)
	local f = c.f
	local pos = c:aimPoint(12)
	local fruit = K.object(c, { name = "FaerieFruit", pos = pos, size = 0.9, shape = "Ball", hp = 40, duration = 5, solid = false, color = Color3.fromRGB(255, 120, 200), material = Enum.Material.Neon })
	local s = freeSprite(f)
	if s then
		assign(f, s, 4)
		S.Summons.moveTo(s, pos)
	end
	K.every(0.1, 5, function()
		if not fruit.alive then
			return false
		end
		for _, t in ipairs(K.Hit.cylinder(pos, K.m(1.3), function(t)
			return not t.isSummon
		end)) do
			if K.isAlly(f, t) then
				K.heal(c, t, 60)
			else
				K.heal(c, t, 40)
				K.slow(c, t, 0.25, 3, "Bargain")
			end
			S.Objects.remove(fruit, "collected")
			return false
		end
		return true
	end)
	if c.p60 then
		c:recast(5, function()
			if fruit.alive then
				S.Objects.remove(fruit, "recalled")
				K.addEnergy(f, (c.def.energy or 22) / 2)
			end
		end)
	end
end

-- 4 Mischief Circle
Kit[4] = function(c)
	local f = c.f
	local center = c:aimPoint(16)
	local orbiters = {}
	for _ = 1, 2 do
		local s = freeSprite(f)
		if s then
			assign(f, s, 5)
			s.sm.ai = "none"
			table.insert(orbiters, s)
		end
	end
	local bent = {}
	local shielded = false
	K.FX.ring(center, K.m(4), PINK, 5, 0.2)
	K.every(0.05, 5, function(i)
		for n, s in ipairs(orbiters) do
			if K.alive(s) then
				local a = i * 0.15 + n * math.pi
				s.root.CFrame = CFrame.new(center + Vector3.new(math.cos(a) * K.m(4), 2, math.sin(a) * K.m(4)))
			end
		end
		for _, p in ipairs(K.enemyProj(c, center + Vector3.new(0, 2, 0), 4.5)) do
			if not bent[p] and p.kind ~= "ultimate" then
				bent[p] = true
				local away = K.flat(p.pos - center)
				local v = p.vel
				local sign = K.flat(v):Cross(away).Y >= 0 and -1 or 1
				p.vel = CFrame.Angles(0, math.rad(15 * sign), 0):VectorToWorldSpace(v)
				if c.p60 and not shielded then
					shielded = true
					K.shield(c, f, 40, 3, "Mischief")
				end
			end
		end
		return true
	end)
end

-- 5 Court of the Small (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(18)
	local court = {}
	for i = 1, 6 do
		local a = math.rad(i * 60)
		local s = makeSprite(f, 50, 6, "CourtSprite")
		S.Fighter.teleport(s, center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(3) + Vector3.new(0, 3, 0))
		s.sm.ai = "stay"
		s.data.actions = c.unstable and 2 or 1
		table.insert(court, s)
	end
	K.FX.disc(center, K.m(7), PINK, 6, 0.8)
	if c.unstable then
		K.every(1, 6, function()
			K.Combat.damage(nil, f, 10, { kind = "true", tag = "unpaid favor" })
			return true
		end)
	end
	c:recast(6, function(c2)
		for _, s in ipairs(court) do
			if K.alive(s) and s.data.actions > 0 then
				s.data.actions -= 1
				local hurt
				for _, a in ipairs(K.alliesIn(c2, center, 7, true)) do
					if a.health < a.maxHealth and (not hurt or a.health < hurt.health) then
						hurt = a
					end
				end
				if hurt then
					K.FX.beam(s.root.Position, hurt.root.Position, 0.2, Color3.fromRGB(150, 255, 170), 0.2)
					K.heal(c2, hurt, 30)
				else
					local t = K.nearestEnemy(f, 8, center)
					if t then
						K.FX.beam(s.root.Position, t.root.Position, 0.2, PINK, 0.2)
						K.dmg(c2, t, 35, { fromPos = s.root.Position })
					end
				end
			end
		end
		for _, s in ipairs(court) do
			if K.alive(s) and s.data.actions > 0 then
				return "keep"
			end
		end
		return nil
	end)
end

return Kit
