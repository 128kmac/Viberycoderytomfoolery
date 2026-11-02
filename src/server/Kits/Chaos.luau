-- 12 Chaos — Telegraphed variation and unusual angles
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local PINK = Color3.fromRGB(255, 60, 160)
local WHEEL = { "Split", "Curve", "Return" }

local function symbol(f)
	if f.state.frozenSym and f.state.frozenUntil > K.now() then
		return f.state.frozenSym
	end
	local i = math.floor((K.now() - (f.state.wheel0 or 0)) / 2) % 3 + 1
	return WHEEL[i]
end

-- Passive: Loaded Disorder
function Kit.passive.init(f)
	f.state.wheel0 = K.now()
end
function Kit.passive.tick(f)
	K.res(f, "Wheel", symbol(f), nil, 1)
end
function Kit.passive.cast(f, c)
	c.data.symbol = symbol(f)
	if c.slot == 1 then
		K.announce(f, c.data.symbol, PINK, 0.8)
	end
end

local function insured(c, reason)
	local f = c.f
	local ins = f.state.insurance
	if ins and ins.expires > K.now() and (reason == "range" or reason == "lifetime") then
		f.state.insurance = nil
		K.addEnergy(f, (c.def.energy or 12) * 0.5)
		K.shield(c, f, 60, 4, "Insurance")
		if ins.p60 then
			K.reduceCd(f, c.slot, 2)
		end
	end
end

-- 1 Discord Bolt (90 total damage budget, split by the wheel)
Kit[1] = function(c)
	local f = c.f
	local sym = c.data.symbol or "Split"
	if c.p60 then
		f.state.frozenSym = sym
		f.state.frozenUntil = K.now() + 1
	end
	local dir = c:dir3()
	local anyHit = false
	local pending = 0
	local function done(reason)
		pending -= 1
		if pending <= 0 and not anyHit then
			insured(c, reason)
		end
	end
	if sym == "Split" then
		for i = -1, 1 do
			pending += 1
			K.proj(c, { dir = K.rotate(dir, i * 8), range = 20, color = PINK, dmg = 30, hit = function()
				anyHit = true
			end, finish = function(_, reason)
				done(reason)
			end })
		end
	elseif sym == "Curve" then
		pending = 1
		local target = c:target(22)
		local side = K.flat(dir:Cross(Vector3.yAxis))
		K.proj(c, {
			dir = (dir + side * 0.6).Unit,
			range = 26,
			color = PINK,
			width = 0.5,
			dmg = 90,
			homing = target,
			turnRate = 140,
			hit = function()
				anyHit = true
			end,
			finish = function(_, reason)
				done(reason)
			end,
		})
	else
		pending = 1
		local out = true
		local hitOut, hitBack = {}, {}
		K.proj(c, {
			dir = dir,
			range = 40,
			color = PINK,
			width = 0.5,
			lifetime = 2.2,
			pierce = true,
			filter = function(t)
				return K.isEnemy(f, t) and not (out and hitOut[t]) and not (not out and hitBack[t])
			end,
			hit = function(t, p)
				anyHit = true
				if out then
					hitOut[t] = true
				else
					hitBack[t] = true
				end
				K.dmg(c, t, 45, { projectile = true })
				p.hits[t] = nil
				return "continue"
			end,
			step = function(p)
				if out and p.traveled >= K.m(20) then
					out = false
					p.hits = {}
				end
				if not out and K.alive(f) then
					p.vel = (f.root.Position - p.pos).Unit * p.speed
					if (p.pos - f.root.Position).Magnitude < K.m(1) then
						S.Proj.stop(p, anyHit and "caught" or "range")
					end
				end
			end,
			finish = function(_, reason)
				done(reason)
			end,
		})
	end
end

-- 2 Wrong Turn
Kit[2] = function(c)
	local f = c.f
	local start = c:feet()
	local dir = c:dir()
	local arrowDir = -dir
	if c.p60 and c.mod then
		arrowDir = K.flat(dir:Cross(Vector3.yAxis))
	end
	K.dash(c, dir, 6, 0.2)
	local arrow = K.object(c, {
		name = "WrongTurnArrow",
		cf = CFrame.lookAt(start + Vector3.new(0, 1.5, 0), start + Vector3.new(0, 1.5, 0) + arrowDir),
		size = Vector3.new(0.6, 0.2, 1.6),
		hp = 60,
		duration = 4,
		solid = false,
		blocks = false,
		prop = true,
		noLabel = true,
		color = PINK,
		material = Enum.Material.Neon,
	})
	local armedAt = K.now() + 0.4
	K.every(0.05, 4, function()
		if not arrow.alive then
			return false
		end
		if K.now() < armedAt then
			return true
		end
		for _, p in ipairs(K.enemyProj(c, start + Vector3.new(0, 1.5, 0), 1.6)) do
			if p.kind ~= "ultimate" and not p.reflected then
				p.reflected = true
				p.vel = -p.vel
				p.filter = function()
					return true
				end
				p.hits = {}
				p.range = p.traveled + K.m(8)
				if p.part then
					p.part.Color = Color3.fromRGB(200, 200, 200)
				end
				S.Objects.remove(arrow, "used")
				return false
			end
		end
		return true
	end)
end

-- 3 Anomaly Box
Kit[3] = function(c)
	local f = c.f
	local pos = c:aimPoint(16)
	local box = K.object(c, { name = "AnomalyBox", pos = pos, size = 1.4, hp = 120, duration = 6, color = PINK, material = Enum.Material.Neon, transparency = 0.2 })
	local states = { "Lift", "Slow", "Shove" }
	local idx = 1
	if c.p60 then
		idx = table.find(WHEEL, c.data.symbol or "Split") or 1
	end
	if K.partner(c, "Glitch", 20) then
		task.wait(0.5)
	end
	K.every(2, 6, function()
		if not box.alive then
			return false
		end
		local st = states[idx]
		K.FX.text(pos + Vector3.new(0, 3, 0), st, PINK, 1.8, 30)
		K.FX.burst(pos + Vector3.new(0, 1, 0), K.m(3), PINK, 0.3)
		for _, t in ipairs(K.enemiesIn(c, pos, 3)) do
			if st == "Lift" then
				K.lift(c, t, 0.6, 2)
			elseif st == "Slow" then
				K.slow(c, t, 0.25, 2, "Anomaly")
			else
				K.push(c, t, K.flat(t.root.Position - pos):Cross(Vector3.yAxis), 2)
			end
		end
		idx = idx % 3 + 1
		return true
	end)
	local _ = f
end

-- 4 Misfire Insurance
Kit[4] = function(c)
	c.f.state.insurance = { expires = K.now() + 3, p60 = c.p60 }
	K.FX.highlight(c.f.model, PINK, 3, 0.8)
end

-- 5 Probability Carnival (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(22)
	local size = 3
	local tiles = {}
	for i = -1, 1 do
		for j = -1, 1 do
			table.insert(tiles, K.ground(center + Vector3.new(i * K.m(size), 0, j * K.m(size))))
		end
	end
	for _, p in ipairs(tiles) do
		K.FX.rect(CFrame.new(p + Vector3.new(0, 0.1, 0)), K.m(size) - 0.5, K.m(size) - 0.5, 4.6, Color3.fromRGB(60, 40, 70), 0.5)
	end
	local rng = Random.new()
	for wave = 1, 3 do
		-- choose six struck tiles (at least three safe), announce and preview
		local order = {}
		for i = 1, 9 do
			order[i] = i
		end
		S.Util.shuffle(order, rng)
		local struck = {}
		for i = 1, 6 do
			struck[order[i]] = true
		end
		if c.unstable and wave == 3 then
			-- manual rotation of the final pattern toward the aim (preview still mandatory)
			local aim = c:aimPoint(30)
			local best, bd = 1, math.huge
			for i, p in ipairs(tiles) do
				local d = (p - aim).Magnitude
				if d < bd then
					best, bd = i, d
				end
			end
			struck = {}
			local row = math.floor((best - 1) / 3)
			local col = (best - 1) % 3
			for i = 1, 9 do
				local r, cc = math.floor((i - 1) / 3), (i - 1) % 3
				if r == row or cc == col then
					struck[i] = true
				end
			end
		end
		K.announce(f, "PATTERN " .. wave, PINK, 0.7)
		for i, p in ipairs(tiles) do
			if struck[i] then
				K.FX.rect(CFrame.new(p + Vector3.new(0, 0.2, 0)), K.m(size) - 0.6, K.m(size) - 0.6, 0.7, Color3.fromRGB(255, 60, 60), 0.35)
			else
				K.FX.rect(CFrame.new(p + Vector3.new(0, 0.2, 0)), K.m(size) - 0.6, K.m(size) - 0.6, 0.7, Color3.fromRGB(80, 255, 120), 0.6)
			end
		end
		task.wait(0.7)
		for i, p in ipairs(tiles) do
			if struck[i] then
				K.FX.burst(p + Vector3.new(0, 1, 0), K.m(1.6), PINK, 0.25)
				local list
				if c.unstable and wave == 3 then
					list = K.Hit.box(CFrame.new(p), Vector3.new(K.m(size), K.m(4), K.m(size)), function()
						return true
					end)
				else
					list = K.Hit.box(CFrame.new(p), Vector3.new(K.m(size), K.m(4), K.m(size)), K.enemyFilter(c))
				end
				for _, t in ipairs(list) do
					K.Combat.damage(f, t, 100, { cast = c, isUlt = true, fromPos = p + Vector3.new(0, 8, 0), element = "Chaos" })
				end
			end
		end
		task.wait(0.55)
	end
end

return Kit
