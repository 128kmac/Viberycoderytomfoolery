-- 19 Crystal — Growing facets and precise refraction
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local CYAN = Color3.fromRGB(150, 230, 255)

local function crystals(f)
	local out = {}
	for _, o in ipairs(K.owned(f)) do
		if o.data.crystal then
			table.insert(out, o)
		end
	end
	table.sort(out, function(a, b)
		return a.created < b.created
	end)
	return out
end

local function stored(o)
	local s = o.data.stored
	if s and s.expires > K.now() then
		return s.amount
	end
	o.data.stored = nil
	return 0
end

-- every owned crystal stores one incoming energy hit (up to 60); physical hits damage it normally
local function makeCrystal(c, opts)
	local f = c.f or c
	local list = crystals(f)
	if #list >= 3 and not opts.isUlt then
		S.Objects.remove(list[1], "replaced")
	end
	opts.color = opts.color or CYAN
	opts.material = Enum.Material.Glass
	opts.transparency = 0.2
	local o = K.object(c, opts)
	o.data.crystal = true
	o.beforeDamage = function(obj, info)
		local p = info.opts and info.opts.projectile
		if p and p.kind == "energy" and stored(obj) == 0 then
			local amt = math.min(60, info.amount)
			obj.data.stored = { amount = amt, expires = K.now() + 6 }
			info.cancel = true
			K.FX.highlight(obj.part, Color3.fromRGB(255, 255, 200), 6, 0.3)
		end
	end
	return o
end

local function updateRes(f)
	K.res(f, "Crystals", #crystals(f), 3, 1)
end
function Kit.passive.tick(f)
	updateRes(f)
end

-- 1 Prism Dart
Kit[1] = function(c)
	local f = c.f
	local redirects = 0
	local bonus = 0
	K.proj(c, {
		range = 30,
		width = 0.25,
		speed = 30,
		color = CYAN,
		shape = "Block",
		size = Vector3.new(0.25, 0.25, 1.6),
		hit = function(t)
			K.dmg(c, t, 75 + bonus, { projectile = true })
		end,
		wall = function(pos, normal, obj, p)
			if obj and obj.owner == f and obj.data.crystal and redirects < 2 then
				redirects += 1
				if c.p60 and redirects == 1 then
					bonus = math.min(40, stored(obj))
				end
				p.vel = K.flat(obj.part.CFrame.LookVector) * p.speed
				p.pos = obj.part.Position + p.vel.Unit * (obj.part.Size.Magnitude / 2 + 1)
				return "bounce"
			end
			return nil
		end,
	})
end

-- 2 Amethyst Rise
Kit[2] = function(c)
	local pos = c:aimPoint(14)
	local dir = c:dir()
	K.telegraph(c, pos, 1.2, 0.5, CYAN)
	task.wait(0.5)
	for _, t in ipairs(K.enemiesIn(c, pos, 1.5)) do
		K.dmg(c, t, 70, { fromPos = pos })
		K.knock(c, t, pos, 1.5)
	end
	local col = makeCrystal(c, {
		name = "AmethystColumn",
		cf = CFrame.lookAt(pos + Vector3.new(0, K.m(1.5), 0), pos + Vector3.new(0, K.m(1.5), 0) + dir),
		size = Vector3.new(1.2, 3, 1.2),
		hp = 180,
		duration = 8,
		color = Color3.fromRGB(180, 120, 255),
	})
	local arrow = K.FX.base({ size = Vector3.new(0.3, 0.3, 1.6), cf = col.part.CFrame * CFrame.new(0, K.m(1.6), -0.8), color = Color3.fromRGB(255, 255, 255) })
	arrow.Parent = col.part
	updateRes(c.f)
end

-- 3 Facet Turn
Kit[3] = function(c)
	local f = c.f
	local list = crystals(f)
	local aim = c:aimPoint(18)
	table.sort(list, function(a, b)
		return (a.part.Position - aim).Magnitude < (b.part.Position - aim).Magnitude
	end)
	local split = c.p60
	for i = 1, math.min(2, #list) do
		local o = list[i]
		local cf = o.part.CFrame * CFrame.Angles(0, math.rad(90), 0)
		o.part.CFrame = cf
		local amt = stored(o)
		if amt > 0 then
			o.data.stored = nil
			K.FX.sphere(o.part.Position, 1.5, Color3.fromRGB(255, 255, 220), 0.4, 0.2)
			task.wait(0.4)
			local look = K.flat(cf.LookVector)
			if split then
				split = false
				for _, a in ipairs({ -12, 12 }) do
					K.beam(c, { origin = o.part.Position, dir = K.rotate(look, a), length = 18, width = 0.5, dmg = 30, color = CYAN })
				end
			else
				K.beam(c, { origin = o.part.Position, dir = look, length = 18, width = 0.5, dmg = 60, color = CYAN })
			end
		end
	end
end

-- 4 Geode Shell
Kit[4] = function(c)
	local f = c.f
	local shell = K.object(c, {
		name = "GeodeShell",
		pos = c:feet(),
		size = Vector3.new(2.2, 2.6, 2.2),
		shape = "Ball",
		hp = 220,
		duration = 2.1,
		solid = false,
		color = Color3.fromRGB(170, 140, 255),
		material = Enum.Material.Glass,
		transparency = 0.35,
		noCap = true,
	})
	local rm = K.hook(f, "beforeTake", function(_, info)
		if shell.alive then
			S.Objects.damage(shell, info.amount, info.src)
			info.cancel = true
		end
	end)
	f.stationary += 1
	local released = false
	local function release(cc)
		if released then
			return
		end
		released = true
		rm()
		f.stationary -= 1
		local frac = shell.alive and (shell.hp / 220) or 0
		local pos = shell.part.Position
		S.Objects.remove(shell, "cracked")
		if frac > 0 then
			K.circle(cc, K.ground(pos), 3, { dmg = 80 * frac, color = Color3.fromRGB(170, 140, 255) })
		end
		if c.p60 then
			makeCrystal(cc, { name = "Facet", pos = K.ground(pos) + c:dir() * K.m(1.5), size = Vector3.new(1, 1.6, 1), hp = 80, duration = 8 })
		end
	end
	c:recast(2, function(c2)
		release(c2)
	end, {
		onExpire = function()
			release(c)
		end,
	})
end

-- 5 Cathedral Refraction (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(22)
	local facets = {}
	for i = 0, 5 do
		local a = math.rad(i * 60)
		local p = K.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(7))
		facets[i + 1] = makeCrystal(c, { name = "CathedralFacet", pos = p, size = Vector3.new(1, 2.4, 1), hp = 100, duration = 8, isUlt = true })
	end
	-- start at the facet nearest the aim, travel three edges
	local aim = c:aimPoint(30)
	local start, bd = 1, math.huge
	for i, o in ipairs(facets) do
		local d = (o.part.Position - aim).Magnitude
		if d < bd then
			start, bd = i, d
		end
	end
	local totals = {}
	local function run(order, dmg, cap, everyone)
		for n = 1, #order - 1 do
			local a, b = facets[order[n]], facets[order[n + 1]]
			if not (a.alive and b.alive) then
				return
			end
			local pa, pb = a.part.Position + Vector3.new(0, 1.5, 0), b.part.Position + Vector3.new(0, 1.5, 0)
			K.FX.beam(pa, pb, 0.6, Color3.fromRGB(255, 120, 120), 0.5, 0.5)
			task.wait(0.5)
			K.FX.beam(pa, pb, 1.2, CYAN, 0.25)
			local filter = everyone and function()
				return true
			end or K.enemyFilter(c)
			for _, h in ipairs(K.Hit.segment(pa, pb, K.m(0.8), filter)) do
				local t = h.f
				local d = math.min(dmg, cap - (totals[t] or 0))
				if d > 0 then
					totals[t] = (totals[t] or 0) + d
					K.Combat.damage(f, t, d, { cast = c, isUlt = true, fromPos = pa, element = "Crystal" })
				end
			end
		end
	end
	local order = {}
	for k = 0, 3 do
		order[k + 1] = (start - 1 + k) % 6 + 1
	end
	run(order, 90, 240, false)
	if c.unstable then
		local rev = {}
		for k = #order, 1, -1 do
			table.insert(rev, order[k])
		end
		totals = {}
		run(rev, 47, 140, true)
		for _, o in ipairs(facets) do
			if o.alive then
				S.Objects.remove(o, "shattered")
			end
		end
	end
end

return Kit
