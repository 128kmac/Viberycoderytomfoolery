-- 09 Blood — Visible resource expenditure and delayed recovery
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local RED = Color3.fromRGB(170, 0, 20)

local function setReserve(f, v)
	f.state.reserve = math.clamp(v, 0, 100)
	K.res(f, "Reserve", math.floor(f.state.reserve), 100, 1)
end
local function spend(f, n)
	if (f.state.reserve or 0) >= n then
		setReserve(f, f.state.reserve - n)
		return true
	end
	return false
end

local function droplets(f)
	local out = {}
	for _, d in ipairs(f.state.drops or {}) do
		if d.alive then
			table.insert(out, d)
		end
	end
	f.state.drops = out
	return out
end

local function addDroplet(f, pos, life)
	local d = K.object(f, {
		name = "Droplet",
		pos = pos,
		size = Vector3.new(0.6, 0.6, 0.6),
		shape = "Ball",
		hp = 1,
		duration = life or 8,
		solid = false,
		blocks = false,
		prop = true,
		noLabel = true,
		noCap = true,
		color = RED,
		material = Enum.Material.Neon,
	})
	table.insert(f.state.drops, d)
	return d
end

-- Passive: Crimson Reserve
function Kit.passive.init(f)
	f.state.drops = {}
	setReserve(f, 60)
end
function Kit.passive.dealt(f, target, info)
	if info.kind ~= "direct" or info.final <= 0 or target.isSummon then
		return
	end
	local c = info.opts.cast
	local gained = c and (c.data.reserveGained or 0) or 0
	local gain = math.min(10 - gained, info.final * 0.15)
	if gain > 0 then
		if c then
			c.data.reserveGained = gained + gain
		end
		setReserve(f, (f.state.reserve or 0) + gain)
	end
	if f.state.lifesteal and f.state.lifesteal.left > 0 and info.opts.isUlt then
		local h = math.min(f.state.lifesteal.left, info.final * 0.3)
		f.state.lifesteal.left -= h
		K.heal(f, f, h)
	end
end
function Kit.passive.tick(f)
	for _, d in ipairs(droplets(f)) do
		if K.flatDist(d.part.Position, f.root.Position) < 1.5 then
			S.Objects.remove(d, "collected")
			setReserve(f, f.state.reserve + 5)
		end
	end
end

-- 1 Hemal Lance
Kit[1] = function(c)
	local f = c.f
	local empowered = spend(f, 10)
	K.proj(c, {
		range = 20,
		width = 0.4,
		shape = "Block",
		size = Vector3.new(0.4, 0.4, 3),
		color = RED,
		dmg = empowered and 90 or 55,
		hit = function(t)
			addDroplet(f, K.feet(t) + K.flat(t.root.Position - f.root.Position) * K.m(1), c.p60 and 14 or 8)
		end,
	})
end

-- 2 Crimson Tether
Kit.requires = {
	[2] = function(c)
		if c:target(10) then
			return true
		end
		return false, "No target in range"
	end,
	[4] = function(c)
		if c.f.state.returnLocked and c.f.state.returnLocked > K.now() then
			return false, "Return locked"
		end
		return true
	end,
}
Kit[2] = function(c)
	local f = c.f
	local t = c:target(10)
	if not t then
		return
	end
	local snapped = false
	local rm = K.hook(t, "dodge", function()
		snapped = true
	end, 3)
	local start = K.now()
	K.every(0.1, 3, function(i)
		if snapped or not K.alive(t) or not K.alive(f) then
			return false
		end
		if K.dist(f, t) > 14 then
			snapped = true
			return false
		end
		if K.los(f, t) then
			K.FX.beam(f.root.Position, t.root.Position, 0.15, RED, 0.12)
			if i % 10 == 0 then
				K.dmg(c, t, 15, { kind = "field" })
			end
		end
		return true
	end)
	local _ = start
	local __ = rm
	c:recast(3, function(c2)
		if snapped or not K.alive(t) then
			return
		end
		if not spend(f, 15) then
			K.notify(f, "Need 15 Reserve")
			return "keep"
		end
		if c2.p60 then
			K.dash(c2, K.flat(t.root.Position - f.root.Position), 2, 0.15)
		else
			K.pull(c2, t, f.root.Position, 2)
		end
	end)
end

-- 3 Coagulate
Kit[3] = function(c)
	local f = c.f
	local amount = math.min(30, f.state.reserve or 0)
	if amount <= 0 then
		K.notify(f, "No Reserve")
		return
	end
	setReserve(f, f.state.reserve - amount)
	local given = K.shield(c, f, amount * 3, 4, "Coagulate")
	K.FX.highlight(f.model, RED, 0.5, 0.5)
	if c.p60 then
		K.hook(f, "beforeDisplace", function(_, info)
			info.cancel = true
		end, 0.5)
	end
	K.after(3.95, function()
		for _, sh in ipairs(f.shields) do
			if sh.name == "Coagulate" then
				setReserve(f, (f.state.reserve or 0) + sh.amount / 3 * 0.5)
			end
		end
	end)
	local _ = given
end

-- 4 Circulatory Return
Kit[4] = function(c)
	local f = c.f
	local ds = droplets(f)
	for i = 1, math.min(6, #ds) do
		local d = ds[i]
		local from = d.part.Position + Vector3.new(0, 1, 0)
		S.Objects.remove(d, "returning")
		K.proj(c, {
			origin = from,
			dir = (f.root.Position - from).Unit,
			speed = 18,
			range = 40,
			width = 0.5,
			color = RED,
			homing = f,
			turnRate = c.p60 and 360 or 200,
			lifetime = 4,
			filter = function(t)
				return t ~= f and K.isEnemy(f, t)
			end,
			hit = function()
				-- intercepted: destroyed, no healing for the interceptor
			end,
			step = function(p)
				if K.alive(f) and (p.pos - f.root.Position).Magnitude < K.m(1) then
					K.heal(c, f, 12)
					setReserve(f, (f.state.reserve or 0) + 5)
					S.Proj.stop(p, "returned")
				end
			end,
		})
	end
end

-- 5 Crimson Orrery (ultimate)
Kit[5] = function(c)
	local f = c.f
	local spent = math.min(60, f.state.reserve or 0)
	setReserve(f, (f.state.reserve or 0) - spent)
	local dmg = 35 + spent / 2
	local taken = {}
	local spears = {}
	for i = 1, 6 do
		spears[i] = K.FX.base({ size = Vector3.new(0.3, 0.3, 2.4), color = RED, transparency = 0.05 })
	end
	local alive = true
	local t0 = K.now()
	task.spawn(function()
		while alive and K.now() - t0 < 5 and K.alive(f) do
			local a0 = (K.now() - t0) * 2.5
			for i, sp in ipairs(spears) do
				if sp.Parent then
					local a = a0 + i * math.pi / 3
					local p = f.root.Position + Vector3.new(math.cos(a) * 4, 1.5, math.sin(a) * 4)
					sp.CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a)))
				end
			end
			task.wait()
		end
		for _, sp in ipairs(spears) do
			sp:Destroy()
		end
	end)
	local function fireSpear(sp, target, origin)
		local from = origin or sp.Position
		local dir = target and (target.root.Position - from).Unit or c:dir3()
		sp:Destroy()
		K.proj(c, {
			origin = from,
			dir = dir,
			range = 20,
			speed = 30,
			width = 0.5,
			shape = "Block",
			size = Vector3.new(0.4, 0.4, 2.4),
			color = RED,
			homing = target,
			turnRate = 120,
			hit = function(t)
				if (taken[t] or 0) < 4 then
					taken[t] = (taken[t] or 0) + 1
					K.dmg(c, t, dmg)
				end
			end,
		})
	end
	if c.unstable then
		-- converging ring with 30% lifesteal (capped at 120); Return locked for 8 s
		local t = c:target(16) or K.nearestEnemy(f, 16)
		f.state.lifesteal = { left = 120 }
		f.state.returnLocked = K.now() + 8
		K.after(3, function()
			f.state.lifesteal = nil
		end)
		local center = t and t.root.Position or c:aimPoint(16) + Vector3.new(0, 2, 0)
		for i, sp in ipairs(spears) do
			local a = i * math.pi / 3
			local origin = center + Vector3.new(math.cos(a) * K.m(5), 1, math.sin(a) * K.m(5))
			fireSpear(sp, t, origin)
		end
		alive = false
		return
	end
	local idx = 0
	c:recast(5, function(c2)
		idx += 1
		local sp = spears[idx]
		if sp and sp.Parent then
			fireSpear(sp, c2:target(20))
		end
		if idx < 6 then
			return "keep"
		end
		alive = false
		return nil
	end)
end

return Kit
