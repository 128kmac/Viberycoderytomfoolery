-- Kit API: concise, metre-based helpers used by every power in Kits/.
-- `c` is a cast context (from Cast) or, where noted, a fighter.
local RunService = game:GetService("RunService")
local S = require(script.Parent.S)
local Combat = require(script.Parent.Combat)
local Status = require(script.Parent.Status)
local Hit = require(script.Parent.Hit)
local FX = require(script.Parent.FX)

local K = {}
S.K = K

local Config = S.Config
local M = Config.METRE
K.M = M
K.S = S
K.FX = FX
K.Status = Status
K.Combat = Combat
K.Hit = Hit
K.Config = Config

local function F(c)
	if c == nil then
		return nil
	end
	if c.f then
		return c.f
	end
	return c
end
K.F = F

function K.m(x)
	return x * M
end
function K.now()
	return S.now()
end
function K.alive(f)
	return S.alive(f)
end
function K.isEnemy(a, b)
	return S.isEnemy(F(a), F(b))
end
function K.isAlly(a, b)
	return S.isAlly(F(a), F(b))
end
function K.isReal(f)
	return S.isReal(f)
end
function K.synergy()
	return S.synergy == true
end
function K.color(c)
	return S.Util.color(F(c).kitName)
end
function K.pos(x)
	if typeof(x) == "Vector3" then
		return x
	end
	return F(x).root.Position
end
-- distance in metres between fighters/points
function K.dist(a, b)
	return (K.pos(a) - K.pos(b)).Magnitude / M
end
function K.flatDist(a, b)
	local d = K.pos(a) - K.pos(b)
	return Vector3.new(d.X, 0, d.Z).Magnitude / M
end
function K.flat(v)
	return S.Util.flat(v)
end
function K.rotate(v, deg)
	return S.Util.rotateY(v, deg)
end
function K.ground(pos)
	return Hit.ground(pos + Vector3.new(0, 4, 0), 60) or pos
end
function K.feet(f)
	f = F(f)
	return Hit.ground(f.root.Position) or (f.root.Position - Vector3.new(0, Config.BODY_DOWN, 0))
end
function K.forward(c, distM)
	local f = F(c)
	local d = c.dir and c:dir() or K.flat(f.root.CFrame.LookVector)
	return K.ground(f.root.Position + d * distM * M)
end
function K.los(a, b)
	return Hit.los(K.pos(a), K.pos(b))
end
function K.after(t, fn, ...)
	local args = table.pack(...)
	return task.delay(t, function()
		S.safe(fn, table.unpack(args, 1, args.n))
	end)
end
function K.spawn(fn, ...)
	return task.spawn(function(...)
		S.safe(fn, ...)
	end, ...)
end
-- run fn(i, elapsed) every interval for duration (non-blocking). fn returns false to stop.
function K.every(interval, duration, fn)
	return task.spawn(function()
		local start = S.now()
		local i = 0
		while S.now() - start < duration do
			task.wait(interval)
			i += 1
			local ok, r = pcall(fn, i, S.now() - start)
			if not ok then
				warn("[EB] every: " .. tostring(r))
				break
			end
			if r == false then
				break
			end
		end
	end)
end

-- filters ---------------------------------------------------------------------------------
function K.enemyFilter(c, opts)
	local f = F(c)
	opts = opts or {}
	return function(t)
		if t == f or not S.isEnemy(f, t) then
			return false
		end
		if opts.noSummons and t.isSummon then
			return false
		end
		if opts.exclude and opts.exclude[t] then
			return false
		end
		return true
	end
end
function K.allyFilter(c, includeSelf, opts)
	local f = F(c)
	opts = opts or {}
	return function(t)
		if t == f then
			return includeSelf == true
		end
		if t.isSummon and not opts.summons then
			return false
		end
		return S.isAlly(f, t)
	end
end

-- queries (metres) --------------------------------------------------------------------------
function K.enemiesIn(c, pos, rM, opts)
	opts = opts or {}
	local filter = K.enemyFilter(c, opts)
	local list
	if opts.sphere then
		list = Hit.sphere(pos, rM * M, filter)
	else
		list = Hit.cylinder(pos, rM * M, filter, opts.above and opts.above * M, opts.below and opts.below * M)
	end
	if opts.los then
		local out = {}
		for _, t in ipairs(list) do
			if Hit.los(pos + Vector3.new(0, 2, 0), t.root.Position) then
				table.insert(out, t)
			end
		end
		return out
	end
	return list
end
function K.alliesIn(c, pos, rM, includeSelf, opts)
	return Hit.cylinder(pos, rM * M, K.allyFilter(c, includeSelf, opts))
end
function K.enemiesRing(c, pos, innerM, outerM)
	return Hit.ring(pos, innerM * M, outerM * M, K.enemyFilter(c))
end
function K.enemiesCone(c, rangeM, angle, origin, dir, needLos)
	local f = F(c)
	origin = origin or f.root.Position
	dir = dir or (c.dir and c:dir()) or f.root.CFrame.LookVector
	return Hit.cone(origin, dir, rangeM * M, angle, K.enemyFilter(c), needLos)
end
-- oriented box from origin along dir
function K.enemiesLine(c, origin, dir, lengthM, widthM, heightM)
	local d = K.flat(dir)
	local mid = origin + d * lengthM * M / 2
	local cf = CFrame.lookAt(mid, mid + d)
	return Hit.box(cf, Vector3.new(widthM * M, (heightM or 4) * M, lengthM * M), K.enemyFilter(c))
end
function K.nearestEnemy(c, rangeM, pos, needLos)
	local f = F(c)
	pos = pos or f.root.Position
	local best, bd
	for _, t in pairs(S.fighters) do
		if S.alive(t) and t ~= f and S.isEnemy(f, t) and t.untargetable <= 0 then
			local d = (t.root.Position - pos).Magnitude
			if d <= rangeM * M and (not bd or d < bd) and (needLos == false or Hit.los(pos + Vector3.new(0, 1, 0), t.root.Position)) then
				best, bd = t, d
			end
		end
	end
	return best
end
function K.enemies(c, rangeM)
	local f = F(c)
	local out = {}
	for _, t in pairs(S.fighters) do
		if S.alive(t) and t ~= f and S.isEnemy(f, t) and (not rangeM or (t.root.Position - f.root.Position).Magnitude <= rangeM * M) then
			table.insert(out, t)
		end
	end
	return out
end

-- damage & support ----------------------------------------------------------------------------
function K.dmg(c, t, amount, opts)
	if not t or not S.alive(t) then
		return 0
	end
	local f = F(c)
	local o = opts and table.clone(opts) or {}
	if c and c.f then
		o.cast = o.cast or c
		o.slot = o.slot or c.slot
		o.isUlt = o.isUlt or c.isUlt
	end
	o.element = o.element or (f and f.kitName)
	if o.fromPos == nil and f and f.root then
		o.fromPos = f.root.Position
	end
	return Combat.damage(f, t, amount, o)
end
-- damage a list; onHit(t) after each
function K.dmgAll(c, list, amount, opts, onHit)
	local n = 0
	for _, t in ipairs(list) do
		local d = K.dmg(c, t, amount, opts)
		if onHit then
			S.safe(onHit, t, d)
		end
		n += 1
	end
	return n
end
function K.heal(c, t, amount, opts)
	return Combat.heal(F(c), t, amount, opts)
end
function K.shield(c, t, amount, dur, name)
	return Combat.shield(t, amount, dur, name or ((F(c).kitName or "") .. "Shield"), F(c))
end
function K.totalShield(t)
	return Combat.totalShield(t)
end
function K.addEnergy(f, n)
	Combat.addEnergy(F(f), n)
end
function K.addHeat(f, n)
	Combat.addHeat(F(f), n)
end
function K.addP(f, n)
	return Combat.addProxima(F(f), n, "kit")
end
function K.reduceCd(f, slot, seconds)
	S.Cast.reduceCooldown(F(f), slot, seconds)
end
function K.setCd(f, slot, seconds)
	S.Cast.setCooldown(F(f), slot, seconds)
end
function K.cdLeft(f, slot)
	return S.Cast.cooldownLeft(F(f), slot)
end

-- statuses & control -------------------------------------------------------------------------
function K.slow(c, t, pct, dur, name)
	return Status.apply(t, name or "Slow", { duration = dur, slow = pct, source = F(c), category = "slow", label = "Slow " .. math.floor(pct * 100) .. "%" })
end
function K.speed(f, pct, dur, name)
	return Status.apply(F(f), name or "Haste", { duration = dur, speed = pct, harmful = false, label = "Speed +" .. math.floor(pct * 100) .. "%" })
end
function K.dr(f, pct, dur, name)
	return Status.apply(F(f), name or "Guarded", { duration = dur, dr = pct, harmful = false, label = (name or "DR") .. " " .. math.floor(pct * 100) .. "%" })
end
function K.vuln(c, t, pct, dur, name)
	return Status.apply(t, name or "Exposed", { duration = dur, vuln = pct, source = F(c), category = "curse", label = (name or "Exposed") .. " +" .. math.floor(pct * 100) .. "%" })
end
function K.dmgBuff(f, pct, dur, name)
	return Status.apply(F(f), name or "Empowered", { duration = dur, dmgBonus = pct, harmful = false })
end
function K.buff(f, name, opts)
	opts = opts or {}
	opts.harmful = false
	return Status.apply(F(f), name, opts)
end
function K.debuff(c, t, name, opts)
	opts = opts or {}
	opts.source = opts.source or F(c)
	return Status.apply(t, name, opts)
end
function K.mark(c, t, name, dur, opts)
	opts = opts or {}
	opts.duration = dur
	opts.source = F(c)
	opts.category = opts.category or "mark"
	local st = Status.apply(t, name, opts)
	if st and not st.data.hl and t.model then
		st.data.hl = FX.highlight(t.model, opts.color or K.color(c), dur, 0.8)
	end
	return st
end
function K.has(t, name)
	return Status.has(t, name)
end
function K.stacks(t, name)
	return Status.stacks(t, name)
end
function K.unmark(t, name)
	local st = Status.get(t, name)
	if st and st.data.hl then
		st.data.hl:Destroy()
	end
	return Status.remove(t, name)
end
function K.dot(c, t, name, total, dur, category, interval)
	return Status.dot(t, name, total, dur, F(c), { category = category or "dot", interval = interval, element = F(c).kitName })
end
function K.burn(c, t, total, dur)
	return Status.dot(t, "Burn", total, dur, F(c), { category = "burn", label = "Burn", element = F(c).kitName })
end
function K.bleed(c, t, total, dur)
	return Status.dot(t, "Bleed", total, dur, F(c), { category = "bleed", label = "Bleed", element = F(c).kitName })
end
function K.cleanse(t, category, n)
	return Status.cleanse(t, category, n)
end
function K.root(c, t, dur)
	return Combat.control(t, "root", dur, F(c))
end
function K.stun(c, t, dur)
	return Combat.control(t, "stun", dur, F(c))
end
function K.sleep(c, t, dur)
	return Combat.control(t, "sleep", dur, F(c))
end
function K.lift(c, t, dur, heightM)
	return Combat.control(t, "lift", dur, F(c), { height = (heightM or 2) * M })
end
function K.silence(c, t, dur)
	return Status.apply(t, "silence", { duration = dur, source = F(c), category = "silence", label = "Silenced" })
end
function K.interrupt(t, reason)
	return Combat.interrupt(t, reason or "interrupt")
end
function K.knock(c, t, fromPos, distM, opts)
	Combat.knockback(t, fromPos, distM * M, F(c), opts)
end
function K.push(c, t, dir, distM, opts)
	Combat.push(t, dir, distM * M, F(c), opts)
end
function K.pull(c, t, toPos, distM, opts)
	Combat.pull(t, toPos, distM * M, F(c), opts)
end
function K.reveal(c, t, dur)
	local st = Status.apply(t, "Revealed", { duration = dur, source = F(c), category = "reveal", label = "Revealed" })
	if st and t.model and not st.data.hl then
		local h = FX.highlight(t.model, Color3.fromRGB(255, 255, 255), dur, 1)
		if h then
			h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		end
		st.data.hl = h
	end
	return st
end
function K.invuln(f, dur)
	f = F(f)
	f.invulnUntil = math.max(f.invulnUntil or 0, S.now() + dur)
end
function K.untargetable(f, dur)
	f = F(f)
	f.untargetable += 1
	task.delay(dur, function()
		f.untargetable = math.max(0, f.untargetable - 1)
	end)
end
-- partially hide a fighter's body (in-world concealment; never hides warnings)
function K.conceal(f, dur, transparency)
	f = F(f)
	local parts = {}
	for _, p in ipairs(f.model:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			parts[p] = p.Transparency
			p.Transparency = math.max(p.Transparency, transparency or 0.8)
		elseif p:IsA("Decal") then
			parts[p] = p.Transparency
			p.Transparency = 1
		end
	end
	if f.plate then
		f.plate.Enabled = false
	end
	f.concealed = (f.concealed or 0) + 1
	local function restore()
		f.concealed = math.max(0, (f.concealed or 1) - 1)
		if f.concealed > 0 then
			return
		end
		for p, tr in pairs(parts) do
			if p.Parent then
				p.Transparency = tr
			end
		end
		if f.plate then
			f.plate.Enabled = true
		end
	end
	task.delay(dur, restore)
	return restore
end

-- hooks for timed stances. returns remover
function K.hook(f, name, fn, dur)
	local remover = Combat.addHook(F(f), name, fn)
	if dur then
		task.delay(dur, remover)
	end
	return remover
end

-- resources -----------------------------------------------------------------------------------
function K.res(f, key, value, max, order)
	S.Fighter.setRes(F(f), key, value, max, order)
end
function K.clearRes(f, key)
	S.Fighter.clearRes(F(f), key)
end
function K.announce(f, text, color, dur)
	f = F(f)
	FX.text(f.root, text, color or K.color(f), dur or 1.6, 34)
end
function K.notify(f, text)
	S.Cast.notify(F(f), text)
end

-- shapes ----------------------------------------------------------------------------------------
--[[ K.proj(c, opts) metres: speed (m/s), width (m), range (m), origin, dir, dmg, hit(t, p), wall(pos, normal, obj, p),
	finish(pos, reason, p), pierce, lob (true: arcs to aimPoint), target point, homing, color, size (studs) ]]
function K.proj(c, opts)
	opts = opts or {}
	local f = F(c)
	local origin = opts.origin or (c.chest and c:chest()) or f.root.Position
	local dir = opts.dir or (c.dir3 and c:dir3()) or f.root.CFrame.LookVector
	local range = (opts.range or (c.def and c.def.range) or 20)
	local p
	p = S.Proj.fire({
		owner = f,
		cast = c.f and c or nil,
		origin = origin,
		dir = dir,
		speed = (opts.speed or Config.PROJ_SPEED) * M,
		radius = (opts.width or Config.PROJ_WIDTH) * M / 2,
		range = range * M,
		gravity = opts.gravity,
		targetPoint = opts.targetPoint,
		pierce = opts.pierce,
		homing = opts.homing,
		turnRate = opts.turnRate,
		kind = opts.kind or (c.isUlt and "ultimate" or "energy"),
		color = opts.color,
		size = opts.size,
		shape = opts.shape,
		dmg = opts.dmg,
		objDmg = opts.objDmg,
		allies = opts.allies,
		filter = opts.filter,
		lifetime = opts.lifetime,
		ground = opts.ground,
		noObjects = opts.noObjects,
		data = opts.data,
		tags = opts.tags,
		onStep = opts.step,
		onAlly = opts.ally and function(pp, t)
			return opts.ally(t, pp)
		end or nil,
		onHit = function(pp, t)
			if opts.dmg then
				K.dmg(c, t, opts.dmg, { fromPos = pp.pos, projectile = true, guardDmg = opts.guardDmg, cap = opts.cap })
			end
			if opts.hit then
				return opts.hit(t, pp)
			end
			return nil
		end,
		onWall = opts.wall and function(pp, pos, normal, obj)
			return opts.wall(pos, normal, obj, pp)
		end or nil,
		onEnd = opts.finish and function(pp, pos, reason)
			opts.finish(pos, reason, pp)
		end or nil,
	})
	FX.sound(f.root, "shoot", 0.25)
	return p
end

-- arcing throw to a ground point; land(pos) on impact (also fires if it hits a body: hit(t))
function K.lob(c, opts)
	opts = opts or {}
	local target = opts.target or c:aimPoint(opts.range or c.def.range)
	local landed = false
	local o = table.clone(opts)
	o.gravity = (opts.gravityM or 20) * M
	o.targetPoint = target
	o.speed = opts.speed or 18
	local userFinish = opts.finish
	o.finish = function(pos, reason, p)
		if not landed then
			landed = true
			if opts.land then
				opts.land(pos, reason, p)
			end
		end
		if userFinish then
			userFinish(pos, reason, p)
		end
	end
	return K.proj(c, o)
end

-- instant beam. opts: origin, dir (3D), length (m), width (m), dmg, pierce (true = all), hit(t), color, dur
function K.beam(c, opts)
	opts = opts or {}
	local f = F(c)
	local origin = opts.origin or (c.chest and c:chest()) or f.root.Position
	local dir = (opts.dir or (c.dir3 and c:dir3()) or f.root.CFrame.LookVector).Unit
	local len = (opts.length or (c.def and c.def.range) or 20) * M
	local res = opts.throughWalls and nil or Hit.raycast(origin, dir * len, opts.ignoreConstructs)
	local endPos = res and res.Position or (origin + dir * len)
	local width = (opts.width or 0.5) * M
	local hits = Hit.segment(origin, endPos, width / 2, opts.filter or K.enemyFilter(c))
	local struck = {}
	for _, h in ipairs(hits) do
		local t = h.f
		if Combat.isInvulnerable(t) then
			Combat.damage(f, t, 1, { kind = "direct" }) -- registers evade
		else
			table.insert(struck, t)
			if opts.dmg then
				K.dmg(c, t, opts.dmg, { fromPos = origin, beam = true, guardDmg = opts.guardDmg })
			end
			if opts.hit then
				S.safe(opts.hit, t)
			end
			if not opts.pierce then
				endPos = origin + (endPos - origin) * h.s
				break
			end
		end
	end
	if res and opts.objDmg ~= false then
		local obj = S.Objects.fromPart(res.Instance)
		if obj and (opts.dmg or opts.objDmg) then
			S.Objects.damage(obj, opts.objDmg or opts.dmg, f)
		end
		if opts.wall then
			S.safe(opts.wall, res.Position, res.Normal, obj)
		end
	end
	if not opts.noVisual then
		FX.beam(origin, endPos, width, opts.color or K.color(c), opts.dur or 0.25, 0.15)
	end
	return endPos, struck, res
end

-- melee arc in front. opts: range (m), arc (deg), dmg, hit(t), guardDmg, origin, dir
function K.melee(c, opts)
	opts = opts or {}
	local f = F(c)
	local dir = opts.dir or (c.dir and c:dir()) or K.flat(f.root.CFrame.LookVector)
	if c.face then
		c:face(dir)
	end
	local origin = opts.origin or f.root.Position
	local list = Hit.cone(origin, dir, (opts.range or 3) * M, opts.arc or 100, opts.filter or K.enemyFilter(c), true)
	FX.cone(origin, dir, (opts.range or 3) * M, math.min(opts.arc or 100, 160), opts.color or K.color(c), 0.15)
	FX.sound(f.root, "swing", 0.35)
	local hits = {}
	for _, t in ipairs(list) do
		if opts.dmg then
			K.dmg(c, t, opts.dmg, { melee = true, guardDmg = opts.guardDmg, fromPos = origin })
		end
		if opts.hit then
			S.safe(opts.hit, t)
		end
		table.insert(hits, t)
	end
	if opts.objDmg ~= false then
		for _, o in ipairs(S.Objects.inRadius(origin + dir * (opts.range or 3) * M * 0.6, (opts.range or 3) * M * 0.6, function(o)
			return o.owner == nil or S.isEnemy(f, o.owner)
		end)) do
			S.Objects.damage(o, opts.objDmg or opts.dmg or 40, f)
		end
	end
	if #hits == 0 then
		S.emit("meleeWhiff", f, origin, dir, (opts.range or 3) * M)
	end
	return hits
end

-- cone blast. opts: range, angle, dmg, hit(t), origin, dir, needLos
function K.cone(c, opts)
	opts = opts or {}
	local f = F(c)
	local dir = opts.dir or (c.dir and c:dir()) or K.flat(f.root.CFrame.LookVector)
	local origin = opts.origin or f.root.Position
	local list = Hit.cone(origin, dir, (opts.range or 6) * M, opts.angle or 60, opts.filter or K.enemyFilter(c), opts.needLos ~= false)
	FX.cone(origin, dir, (opts.range or 6) * M, opts.angle or 60, opts.color or K.color(c), 0.25)
	for _, t in ipairs(list) do
		if opts.dmg then
			K.dmg(c, t, opts.dmg, { fromPos = origin, guardDmg = opts.guardDmg })
		end
		if opts.hit then
			S.safe(opts.hit, t)
		end
	end
	return list
end

-- instant circle. opts: dmg, hit(t), allies (bool -> ally list instead), includeSelf, fx (false), sphere, objDmg
function K.circle(c, pos, rM, opts)
	opts = opts or {}
	local list
	if opts.allies then
		list = K.alliesIn(c, pos, rM, opts.includeSelf)
	elseif opts.everyone then
		list = Hit.cylinder(pos, rM * M, function(t)
			return opts.includeSelf or t ~= F(c)
		end)
	else
		list = K.enemiesIn(c, pos, rM, { sphere = opts.sphere, los = opts.los, noSummons = opts.noSummons })
	end
	if opts.fx ~= false then
		FX.burst(pos + Vector3.new(0, 1, 0), rM * M, opts.color or K.color(c), 0.35)
	end
	for _, t in ipairs(list) do
		if opts.dmg then
			K.dmg(c, t, opts.dmg, { fromPos = pos, guardDmg = opts.guardDmg, kind = opts.kind })
		end
		if opts.hit then
			S.safe(opts.hit, t)
		end
	end
	if opts.objDmg then
		for _, o in ipairs(S.Objects.inRadius(pos, rM * M, function(o)
			return o.owner == nil or o.owner == F(c) and opts.selfObjects or S.isEnemy(F(c), o.owner)
		end)) do
			S.Objects.damage(o, opts.objDmg, F(c))
		end
	end
	return list
end

-- instant rectangle from origin along dir. opts like circle
function K.line(c, origin, dir, lengthM, widthM, opts)
	opts = opts or {}
	local list = K.enemiesLine(c, origin, dir, lengthM, widthM, opts.height)
	if opts.fx ~= false then
		local d = K.flat(dir)
		local mid = K.ground(origin) + d * lengthM * M / 2 + Vector3.new(0, 0.3, 0)
		FX.rect(CFrame.lookAt(mid, mid + d), widthM * M, lengthM * M, 0.3, opts.color or K.color(c), 0.3)
	end
	for _, t in ipairs(list) do
		if opts.dmg then
			K.dmg(c, t, opts.dmg, { fromPos = origin, guardDmg = opts.guardDmg })
		end
		if opts.hit then
			S.safe(opts.hit, t)
		end
	end
	return list
end

function K.ringHit(c, pos, innerM, outerM, opts)
	opts = opts or {}
	local list = K.enemiesRing(c, pos, innerM, outerM)
	if opts.fx ~= false then
		FX.ring(pos, outerM * M, opts.color or K.color(c), 0.4, math.max(0.4, (outerM - innerM) * M))
	end
	for _, t in ipairs(list) do
		if opts.dmg then
			K.dmg(c, t, opts.dmg, { fromPos = pos })
		end
		if opts.hit then
			S.safe(opts.hit, t)
		end
	end
	return list
end

-- arc of a ring between two angles (degrees, 0 = +X axis), used for marked gaps / sectors
function K.arcFX(pos, radiusM, fromDeg, toDeg, color, dur, thicknessM)
	local r = radiusM * M
	local span = toDeg - fromDeg
	local segs = math.max(2, math.floor(math.abs(span) / 10))
	local th = (thicknessM or 0.3) * M
	local model = Instance.new("Model")
	model.Name = "Arc"
	for i = 0, segs - 1 do
		local a = math.rad(fromDeg + span * (i + 0.5) / segs)
		local segLen = 2 * math.pi * r * math.abs(span) / 360 / segs * 1.05
		local cf = CFrame.new(pos + Vector3.new(math.cos(a) * r, 0.2, math.sin(a) * r)) * CFrame.Angles(0, -a, 0)
		FX.base({ size = Vector3.new(th, 0.25, segLen), cf = cf, color = color, transparency = 0.15, parent = model })
	end
	model.Parent = S.folders.FX
	if dur then
		game:GetService("Debris"):AddItem(model, dur)
	end
	return model
end

-- angle (degrees, 0 = +X, matching arcFX) of a point around a centre
function K.angleOf(center, p)
	return math.deg(math.atan2(p.Z - center.Z, p.X - center.X)) % 360
end

-- true if angle a lies inside the sector [from, from+width]
function K.inSector(a, from, width)
	local d = (a - from) % 360
	return d <= width
end

-- telegraphs -----------------------------------------------------------------------------------
function K.telegraph(c, pos, rM, t, color)
	return FX.telegraph(pos, rM * M, t, color or K.color(c))
end
function K.telegraphLine(c, origin, dir, lengthM, widthM, t, color)
	return FX.lineTelegraph(K.ground(origin) + Vector3.new(0, 0.2, 0), dir, lengthM * M, widthM * M, t, color or K.color(c))
end
-- blocking warning; returns true if the cast is still valid
function K.warn(c, pos, rM, t, color)
	K.telegraph(c, pos, rM, t, color)
	return c:wait(t)
end
-- independent delayed effect: telegraph now, fn(pos) after t
function K.delayed(c, pos, rM, t, fn, color)
	K.telegraph(c, pos, rM, t, color)
	return task.delay(t, function()
		S.safe(fn, pos)
	end)
end

-- zones (metres) --------------------------------------------------------------------------------
--[[ opts: pos, radius, shape, width, length, dir, inner, duration, tick, immediate, targets, dmg (per tick, kind "field"),
	heal (per tick to allies), slow = {pct, dur}, tickFn(z, list), enter(z, t, first), exit(z, t), finish(z, reason),
	follow, above, color, transparency, tags, data, includeOwner, cap (per target total) ]]
function K.zone(c, opts)
	local f = F(c)
	local capTotals = {}
	local z = S.Zones.create({
		owner = f,
		cast = c.f and c or nil,
		pos = opts.pos or K.feet(f),
		radius = (opts.radius or 3) * M,
		shape = opts.shape,
		width = opts.width and opts.width * M,
		length = opts.length and opts.length * M,
		dir = opts.dir,
		inner = opts.inner and opts.inner * M,
		duration = opts.duration,
		tick = opts.tick,
		immediate = opts.immediate,
		targets = opts.targets or (opts.heal and "allies" or "enemies"),
		color = opts.color or K.color(f),
		transparency = opts.transparency,
		above = opts.above and opts.above * M,
		follow = opts.follow,
		tags = opts.tags,
		data = opts.data,
		element = opts.element,
		includeOwner = opts.includeOwner,
		noVisual = opts.noVisual,
		onTick = function(z, list)
			for _, t in ipairs(list) do
				if opts.dmg and S.isEnemy(f, t) or (opts.dmg and opts.includeOwner and t == f) then
					local amt = opts.dmg
					if opts.cap then
						local done = capTotals[t] or 0
						amt = math.min(amt, opts.cap - done)
						capTotals[t] = done + math.max(0, amt)
					end
					if amt > 0 then
						Combat.damage(f, t, amt, { kind = opts.kind or "field", element = f.kitName, fromPos = z.pos, slot = c.slot, isUlt = c.isUlt, cast = c.f and c or nil })
					end
				end
				if opts.heal and S.isAlly(f, t) then
					Combat.heal(f, t, opts.heal)
				end
				if opts.slow and (S.isEnemy(f, t)) then
					K.slow(f, t, opts.slow[1], opts.slow[2] or 1.2, opts.slowName)
				end
			end
			if opts.tickFn then
				opts.tickFn(z, list)
			end
		end,
		onEnter = opts.enter,
		onExit = opts.exit,
		onEnd = opts.finish,
	})
	return z
end

function K.zonesNear(pos, rM, element, filter)
	return S.Zones.near(pos, rM * M, function(z)
		return (element == nil or z.element == element) and (filter == nil or filter(z))
	end)
end
function K.ownedZones(f, tag)
	return S.Zones.owned(F(f), tag)
end

-- objects (metres) ------------------------------------------------------------------------------
-- wall perpendicular to `dir`, centred on ground point pos. opts: width, height, thick, hp, duration, color...
function K.wall(c, opts)
	local f = F(c)
	local dir = K.flat(opts.dir or (c.dir and c:dir()) or f.root.CFrame.LookVector)
	local pos = opts.pos or K.forward(c, 3)
	local w, h, th = (opts.width or 4) * M, (opts.height or 2.5) * M, (opts.thick or 0.5) * M
	local cf = CFrame.lookAt(pos + Vector3.new(0, h / 2, 0), pos + Vector3.new(0, h / 2, 0) + dir)
	local o = table.clone(opts)
	o.owner = f
	o.cf = cf
	o.size = Vector3.new(w, h, th)
	o.color = opts.color or K.color(f)
	o.material = opts.material or Enum.Material.Glass
	o.transparency = opts.transparency or 0.25
	o.isUlt = opts.isUlt or (c.isUlt == true)
	return S.Objects.create(o)
end
-- generic construct: pos (ground point), size (metres Vector3 or number), shape
function K.object(c, opts)
	local f = F(c)
	local size = opts.size or 1.5
	if type(size) == "number" then
		size = Vector3.new(size, size, size)
	end
	size = size * M
	local pos = opts.pos or K.feet(f)
	local o = table.clone(opts)
	o.owner = opts.neutral and nil or f
	o.cf = opts.cf or CFrame.new(pos + Vector3.new(0, size.Y / 2, 0))
	o.size = size
	o.color = opts.color or K.color(f)
	o.material = opts.material or Enum.Material.SmoothPlastic
	o.isUlt = opts.isUlt or (c.isUlt == true)
	return S.Objects.create(o)
end
function K.objects(c, pos, rM, filter)
	return S.Objects.inRadius(pos, rM * M, filter)
end
function K.enemyObjects(c, pos, rM)
	local f = F(c)
	return S.Objects.inRadius(pos, rM * M, function(o)
		return o.owner == nil or S.isEnemy(f, o.owner)
	end)
end
function K.owned(f, name)
	return S.Objects.owned(F(f), name)
end
function K.objDmg(c, o, amount)
	return S.Objects.damage(o, amount, F(c))
end
function K.objAt(o)
	return o.part and o.part.Position
end

-- summons (metres) -------------------------------------------------------------------------------
function K.summon(c, opts)
	local f = F(c)
	local o = table.clone(opts)
	o.owner = f
	if opts.size and type(opts.size) == "number" then
		o.size = Vector3.one * opts.size * M
	elseif opts.size then
		o.size = opts.size * M
	end
	o.pos = opts.pos or (f.root.Position + K.flat(f.root.CFrame.RightVector) * 3)
	return S.Summons.create(o)
end
function K.summons(f, name)
	return S.Summons.owned(F(f), name)
end

-- projectiles in area (for interception/reflection)
function K.projNear(pos, rM, filter)
	return S.Proj.inRadius(pos, rM * M, filter)
end
function K.enemyProj(c, pos, rM)
	local f = F(c)
	return S.Proj.inRadius(pos, rM * M, function(p)
		return p.owner and S.isEnemy(f, p.owner)
	end)
end

-- movement ----------------------------------------------------------------------------------------
-- blocking dash. opts: onPass(t) once per target, passWidth (m), up
function K.dash(c, dir, distM, time, opts)
	opts = opts or {}
	local f = F(c)
	time = time or math.max(0.12, distM / 25)
	local start = f.root.Position
	local real = S.Fighter.dash(f, dir, distM * M, time, { up = opts.up, allowY = opts.allowY })
	if c.recovery == nil and c.f then
		c.recovery = Config.MOVE_RECOVERY
	end
	local passed = {}
	local t0 = S.now()
	local last = start
	while S.now() - t0 < time do
		task.wait(0.03)
		if not S.alive(f) then
			break
		end
		local now = f.root.Position
		if opts.onPass then
			for _, h in ipairs(Hit.segment(last, now, (opts.passWidth or 1) * M / 2, K.enemyFilter(c))) do
				if not passed[h.f] then
					passed[h.f] = true
					S.safe(opts.onPass, h.f)
				end
			end
		end
		last = now
		if opts.stopOnHit and next(passed) then
			local lv = f.root:FindFirstChild("EBDisplace")
			if lv then
				lv:Destroy()
			end
			break
		end
	end
	return real / M, passed
end
-- teleport to pos if legal (pos is ground or stand point). Returns true on success.
function K.blink(c, pos, opts)
	opts = opts or {}
	local f = F(c)
	local stand = Hit.findLegal(pos, f.hitScale)
	if not stand then
		return false
	end
	if not opts.throughWalls and not Hit.los(f.root.Position, stand + Vector3.new(0, 1, 0), true) then
		-- short combat teleports do not cross sealed walls
		local dir = (stand - f.root.Position)
		local p = Hit.clearPath(f.root.Position, dir.Unit, dir.Magnitude, 1)
		stand = Hit.findLegal(p, f.hitScale)
		if not stand then
			return false
		end
	end
	FX.burst(f.root.Position, 3, K.color(f), 0.25)
	S.Fighter.teleport(f, stand)
	FX.burst(stand, 3, K.color(f), 0.25)
	if c.recovery == nil and c.f then
		c.recovery = Config.MOVE_RECOVERY
	end
	return true
end
-- follow an arbitrary path: pathFn(alpha 0..1) -> world position. Blocking.
function K.path(c, pathFn, time)
	local f = F(c)
	if not S.alive(f) then
		return
	end
	if f.isSummon or not f.humanoid then
		local t0 = S.now()
		while S.now() - t0 < time do
			task.wait()
			local a = math.min(1, (S.now() - t0) / time)
			f.root.CFrame = CFrame.new(pathFn(a)) * f.root.CFrame.Rotation
		end
		return
	end
	local att = f.root:FindFirstChild("EBMoveAtt")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "EBMoveAtt"
		att.Parent = f.root
	end
	local old = f.root:FindFirstChild("EBDisplace")
	if old then
		old:Destroy()
	end
	local lv = Instance.new("LinearVelocity")
	lv.Name = "EBDisplace"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 1e7
	lv.Parent = f.root
	local t0 = S.now()
	while S.now() - t0 < time and lv.Parent and S.alive(f) do
		local dt = RunService.Heartbeat:Wait()
		local a = math.min(1, (S.now() - t0 + dt) / time)
		local want = pathFn(a)
		local v = (want - f.root.Position) / math.max(dt, 1 / 60)
		if v.Magnitude > 300 then
			v = v.Unit * 300
		end
		lv.VectorVelocity = v
	end
	if lv.Parent then
		lv:Destroy()
	end
	f.root.AssemblyLinearVelocity = Vector3.zero
	if c.recovery == nil and c.f then
		c.recovery = Config.MOVE_RECOVERY
	end
end
-- arcing leap to ground point; returns landing position
function K.leap(c, target, time, heightM)
	local f = F(c)
	local start = f.root.Position
	local stand = Hit.standAt(target)
	local dir = stand - start
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude > 0.1 then
		local clear = Hit.clearPath(start + Vector3.new(0, 2, 0), flat.Unit, flat.Magnitude, 1.2)
		stand = Vector3.new(clear.X, stand.Y, clear.Z)
	end
	local h = (heightM or 2.5) * M
	K.path(c, function(a)
		local p = start:Lerp(stand, a)
		return p + Vector3.new(0, math.sin(a * math.pi) * h, 0)
	end, time or 0.5)
	return K.feet(f)
end

-- rise heightM and hover for dur seconds; only vertical velocity is constrained so the player can steer.
-- Returns a handle with :stop().
function K.hover(f, heightM, dur, riseTime)
	f = F(f)
	local h = { alive = true }
	if not S.alive(f) or not f.humanoid then
		return h
	end
	local att = f.root:FindFirstChild("EBMoveAtt")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "EBMoveAtt"
		att.Parent = f.root
	end
	local old = f.root:FindFirstChild("EBHover")
	if old then
		old:Destroy()
	end
	local lv = Instance.new("LinearVelocity")
	lv.Name = "EBHover"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	lv.LineDirection = Vector3.yAxis
	lv.MaxForce = 1e6
	riseTime = riseTime or 0.4
	lv.LineVelocity = heightM * M / riseTime
	lv.Parent = f.root
	f.hovering = true
	task.delay(riseTime, function()
		if lv.Parent then
			lv.LineVelocity = 0
		end
	end)
	function h.stop()
		if not h.alive then
			return
		end
		h.alive = false
		f.hovering = false
		if lv.Parent then
			lv:Destroy()
		end
	end
	function h.extend(sec)
		dur += sec
	end
	task.spawn(function()
		local t0 = S.now()
		while h.alive and S.now() - t0 < dur do
			task.wait(0.05)
			if not S.alive(f) then
				break
			end
		end
		h.stop()
	end)
	return h
end

function K.face(c, dir)
	if c.face then
		c:face(dir)
	end
end

-- synergy helpers ----------------------------------------------------------------------------------
function K.partner(c, element, rM, pos)
	if not S.synergy then
		return nil
	end
	local f = F(c)
	pos = pos or f.root.Position
	for _, t in pairs(S.fighters) do
		if S.alive(t) and t ~= f and not t.isSummon and t.kitName == element and S.isAlly(f, t) then
			if not rM or (t.root.Position - pos).Magnitude <= rM * M then
				return t
			end
		end
	end
	return nil
end

-- spawn a visual-only decoy body copy of a fighter at pos (cosmetic, for illusions/clones)
function K.decoyModel(f, cf, color)
	f = F(f)
	local m = Instance.new("Model")
	m.Name = "Decoy"
	for _, p in ipairs(f.model:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			local q = p:Clone()
			for _, ch in ipairs(q:GetChildren()) do
				if not ch:IsA("SpecialMesh") and not ch:IsA("Decal") then
					ch:Destroy()
				end
			end
			q.Anchored = true
			q.CanCollide = false
			q.CanQuery = false
			q.CanTouch = false
			if color then
				q.Color = color
			end
			q.CFrame = cf * f.root.CFrame:ToObjectSpace(p.CFrame)
			q.Parent = m
		end
	end
	m.Parent = S.folders.FX
	return m
end

-- copy-safe access to another kit's move (used by Copy/Mystery style kits)
function K.kitMove(kitName, slot)
	local kit = S.Kits.get(kitName)
	return kit and kit[slot], S.Kits.data(kitName)
end

return K
