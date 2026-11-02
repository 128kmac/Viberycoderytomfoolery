-- 93 Time — Local timing changes and limited snapshots (positions only; never health or resources)
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local BRASS = Color3.fromRGB(210, 180, 100)

local function ticks(f)
	local now = K.now()
	local out = {}
	for _, t in ipairs(f.state.ticks) do
		if t > now then
			table.insert(out, t)
		end
	end
	f.state.ticks = out
	return #out
end
local function addTick(f)
	if ticks(f) < 3 then
		table.insert(f.state.ticks, K.now() + 8)
	end
end
local function spendTick(f)
	if ticks(f) > 0 then
		table.remove(f.state.ticks, 1)
		return true
	end
	return false
end

-- Passive: Second Hand
function Kit.passive.init(f)
	f.state.ticks = {}
end
function Kit.passive.tick(f)
	K.res(f, "Ticks", ticks(f), 3, 1)
end
function Kit.passive.cast(f, c)
	if c.slot <= 3 then
		task.spawn(function()
			while f.action == c do
				task.wait(0.05)
			end
			if not c.interrupted then
				addTick(f)
			end
		end)
	end
end

-- slow ordinary projectiles inside a field; restores speed on exit
local function projectileField(c, pos, radiusM, duration, mult, suspend)
	local f = c.f
	local saved = {}
	local function inside(p)
		return K.flatDist(p.pos, pos) <= radiusM and math.abs(p.pos.Y - pos.Y) < K.m(5)
	end
	K.every(0.03, duration, function()
		for _, p in pairs(S.Proj.list) do
			if p.alive and p.owner and K.isEnemy(f, p.owner) and p.kind ~= "ultimate" then
				local isIn = inside(p)
				if isIn and not saved[p] then
					saved[p] = p.speed
					local m = suspend and suspend() or mult
					p.speed = saved[p] * m
					p.vel = p.vel.Magnitude > 0 and p.vel.Unit * math.max(0.01, p.speed) or p.vel
				elseif isIn and saved[p] and suspend then
					local m = suspend()
					p.speed = saved[p] * m
					if p.vel.Magnitude > 0 then
						p.vel = p.vel.Unit * math.max(0.01, p.speed)
					end
				elseif not isIn and saved[p] then
					p.speed = saved[p]
					p.vel = p.vel.Unit * p.speed
					saved[p] = nil
				end
			end
		end
		return true
	end)
	K.after(duration + 0.05, function()
		for p, sp in pairs(saved) do
			if p.alive then
				p.speed = sp
				p.vel = p.vel.Unit * sp
			end
		end
	end)
end

-- 1 Clock Shard (modifier spends a Tick to slow)
Kit[1] = function(c)
	local f = c.f
	local slow = c.mod and spendTick(f)
	K.proj(c, {
		range = 20,
		width = 0.4,
		shape = "Block",
		size = Vector3.new(0.4, 0.4, 1.2),
		color = BRASS,
		dmg = 75,
		hit = function(t)
			if slow then
				K.slow(c, t, 0.15, c.p60 and 2 or 1.5, "Clock")
			end
		end,
	})
end

-- 2 Moment Anchor
Kit[2] = function(c)
	local f = c.f
	local window = c.p60 and 5 or 4
	local recorded = f.root.Position
	local clock = K.object(c, { name = "MomentClock", pos = c:feet(), size = Vector3.new(1, 1.4, 0.3), hp = 100, duration = window, color = BRASS, material = Enum.Material.Metal })
	c:recast(window, function(c2)
		if not clock.alive then
			K.notify(f, "The clock was destroyed")
			return
		end
		if not K.Hit.los(f.root.Position, recorded, true) then
			K.notify(f, "Return route blocked")
			return
		end
		local stand = K.Hit.findLegal(recorded)
		if stand then
			K.FX.burst(f.root.Position, 3, BRASS, 0.3)
			S.Fighter.teleport(f, stand)
			S.Objects.remove(clock, "returned")
		end
		local _ = c2
	end)
end

-- 3 Slow Hour
Kit[3] = function(c)
	local pos = c:aimPoint(16)
	K.zone(c, { pos = pos, radius = 4, duration = 4, tick = 0.25, immediate = true, slow = { 0.2, 0.4 }, slowName = "Slow Hour", color = BRASS, transparency = 0.7 })
	projectileField(c, pos, K.m(4), 4, 0.8)
end

-- 4 Borrowed Second
Kit.requires = {
	[4] = function(c)
		if ticks(c.f) > 0 then
			return true
		end
		return false, "No Ticks"
	end,
}
Kit[4] = function(c)
	local f = c.f
	local n = ticks(f)
	f.state.ticks = {}
	local best, left = nil, 0
	for s = 1, 3 do
		local l = K.cdLeft(f, s)
		if l > left then
			best, left = s, l
		end
	end
	if best then
		K.reduceCd(f, best, n)
	end
	if c.p60 and n >= 3 then
		K.addEnergy(f, 5)
	end
end

-- 5 The Suspended Hour (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(18)
	local suspensions = c.unstable and 4 or 3
	local duration = c.unstable and 7 or 6
	local suspendedUntil = 0
	K.zone(c, { pos = center, radius = 7, duration = duration, tick = 0.25, immediate = true, slow = { 0.25, 0.4 }, slowName = "Suspended Hour", color = BRASS, transparency = 0.75 })
	projectileField(c, center, K.m(7), duration, 1, function()
		return K.now() < suspendedUntil and 0.0001 or 1
	end)
	for i = 1, suspensions do
		task.wait(duration / (suspensions + 1))
		K.FX.text(center + Vector3.new(0, 4, 0), "NOON", BRASS, 0.6, 30)
		K.FX.ring(center, K.m(7), Color3.fromRGB(255, 240, 180), 0.6, 0.3)
		suspendedUntil = K.now() + 0.6
		if c.unstable and i == 4 then
			-- Time Owed: normal cooldown recovery is locked during the extra second
			for s = 1, 4 do
				local left = K.cdLeft(f, s)
				if left > 0 then
					K.setCd(f, s, left + 1)
				end
			end
		end
	end
end

return Kit
