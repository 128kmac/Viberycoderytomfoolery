-- Server-simulated projectiles. Default: 24 m/s, 0.3 m wide, stops on first solid collision.
local RunService = game:GetService("RunService")
local S = require(script.Parent.S)

local Proj = {}
S.Proj = Proj

local Config = S.Config
local M = Config.METRE
local list = {}
local nextId = 0
Proj.list = list
local syncQueue = {}
local syncRemote
function Proj.init(r)
	syncRemote = r.ProjSync
end

--[[ opts (studs unless noted):
	owner, cast, origin, dir (unit), speed, radius, range, gravity (studs/s^2 downward, for lobs),
	targetPoint (lob: computes arc to land there), pierce (extra targets, or true = infinite),
	onHit(p, target) -> return "continue" to keep flying, onWall(p, pos, normal, obj), onEnd(p, pos, reason),
	onStep(p, dt), filter(f) (who can be hit; default enemies), allies (hit allies too -> onAlly(p, ally)),
	kind ("energy"|"physical"|"ultimate"), color, size (visual), shape ("Ball"|"Block"), element,
	homing (fighter), turnRate (deg/s), objDmg, dmg (used for construct damage default), lifetime,
	reflectable, noObjects (pass through constructs), ground (follows floor), noVisual
]]
function Proj.fire(opts)
	nextId += 1
	local owner = opts.owner
	local dir = opts.dir
	if dir.Magnitude < 1e-4 then
		dir = Vector3.new(0, 0, -1)
	end
	dir = dir.Unit
	local speed = opts.speed or Config.PROJ_SPEED * M
	local p = {
		id = nextId,
		owner = owner,
		cast = opts.cast,
		pos = opts.origin,
		vel = dir * speed,
		speed = speed,
		radius = opts.radius or (Config.PROJ_WIDTH * M / 2),
		range = opts.range or S.m(30),
		traveled = 0,
		gravity = opts.gravity,
		pierce = opts.pierce,
		hits = {},
		hitCount = 0,
		onHit = opts.onHit,
		onAlly = opts.onAlly,
		onWall = opts.onWall,
		onEnd = opts.onEnd,
		onStep = opts.onStep,
		filter = opts.filter,
		allies = opts.allies,
		kind = opts.kind or "energy",
		element = opts.element or (owner and owner.kitName),
		homing = opts.homing,
		turnRate = opts.turnRate or 180,
		objDmg = opts.objDmg,
		dmg = opts.dmg,
		born = S.now(),
		lifetime = opts.lifetime,
		alive = true,
		reflected = false,
		data = opts.data or {},
		noObjects = opts.noObjects,
		ground = opts.ground,
		tags = opts.tags or {},
	}
	if opts.targetPoint and opts.gravity then
		-- solve a lob that lands at targetPoint with the given horizontal speed
		local to = opts.targetPoint - opts.origin
		local flat = Vector3.new(to.X, 0, to.Z)
		local dist = flat.Magnitude
		local t = math.max(0.25, dist / speed)
		local vy = (to.Y + 0.5 * opts.gravity * t * t) / t
		p.vel = (dist > 0.01 and flat.Unit * (dist / t) or Vector3.zero) + Vector3.new(0, vy, 0)
		p.range = math.huge
		p.lifetime = p.lifetime or (t + 2)
	end
	-- clients render and extrapolate the projectile; the server only sends spawn / correction / end
	p.visual = not opts.noVisual
	if p.visual then
		p.lastSync = S.now()
		p.syncVel = p.vel
		S.FX.cue("proj", {
			pid = p.id,
			p = p.pos,
			v = p.vel,
			g = p.gravity,
			r = p.radius,
			c = opts.color,
			sz = opts.size,
			sh = opts.shape,
			kind = p.kind,
			gr = p.ground or nil,
			ho = p.homing and p.homing.model or nil,
			tr = p.homing and p.turnRate or nil,
			k = p.element,
			o = owner and owner.id or nil,
			life = p.lifetime,
		})
	end
	list[p.id] = p
	return p
end

function Proj.stop(p, reason, pos)
	if not p.alive then
		return
	end
	p.alive = false
	list[p.id] = nil
	if p.visual then
		S.FX.cue("projEnd", { pid = p.id, p = pos or p.pos, why = reason, k = p.element })
	end
	if p.onEnd then
		S.safe(p.onEnd, p, pos or p.pos, reason)
	end
end

function Proj.reflect(p, newOwner, newDir)
	if not p.alive or p.reflected then
		return false
	end
	p.reflected = true
	p.owner = newOwner
	p.cast = nil
	p.hits = {}
	p.vel = (newDir or -p.vel).Unit * p.speed
	p.element = newOwner.kitName
	if p.visual then
		S.FX.cue("projSync", { pid = p.id, p = p.pos, v = p.vel, k = p.element, reflect = true })
		p.syncVel = p.vel
		p.lastSync = S.now()
	end
	return true
end

function Proj.inRadius(pos, r, filter)
	local out = {}
	for _, p in pairs(list) do
		if p.alive and (p.pos - pos).Magnitude <= r + p.radius and (filter == nil or filter(p)) then
			table.insert(out, p)
		end
	end
	return out
end

local function defaultFilter(p, f)
	if f == p.owner then
		return false
	end
	if p.owner and f.owner == p.owner then
		return false
	end
	return S.isEnemy(p.owner, f)
end

local function step(p, dt)
	if p.lifetime and S.now() - p.born > p.lifetime then
		Proj.stop(p, "lifetime")
		return
	end
	if p.homing and S.alive(p.homing) then
		local to = (p.homing.root.Position - p.pos)
		if to.Magnitude > 0.1 then
			local cur = p.vel.Unit
			local want = to.Unit
			local ang = math.acos(math.clamp(cur:Dot(want), -1, 1))
			local maxAng = math.rad(p.turnRate) * dt
			if ang > 1e-3 then
				local t = math.min(1, maxAng / ang)
				local nd = cur:Lerp(want, t)
				if nd.Magnitude > 1e-3 then
					p.vel = nd.Unit * p.speed
				end
			end
		end
	end
	if p.gravity then
		p.vel -= Vector3.new(0, p.gravity * dt, 0)
	end
	if p.onStep then
		S.safe(p.onStep, p, dt)
		if not p.alive then
			return
		end
	end
	local a = p.pos
	local move = p.vel * dt
	local b = a + move
	if p.ground then
		local g = S.Hit.ground(b + Vector3.new(0, 2.5, 0), 8)
		if g then
			b = Vector3.new(b.X, g.Y + p.radius + 0.3, b.Z)
			-- climb small steps instead of treating the riser as a wall
			local rise = b.Y - a.Y
			if rise > 0 and rise <= 2.5 then
				a = Vector3.new(a.X, b.Y, a.Z)
			end
			move = b - a
		end
	end
	-- world / constructs
	local wallDist = math.huge
	local wallRes
	if move.Magnitude > 0 then
		local res = workspace:Raycast(a, move, p.noObjects and S.Hit.arenaParams or S.Hit.worldParams)
		if res then
			wallDist = (res.Position - a).Magnitude
			wallRes = res
		end
	end
	-- fighters
	local segEnd = wallRes and wallRes.Position or b
	local candidates = S.Hit.segment(a, segEnd, p.radius, function(f)
		if p.hits[f] then
			return false
		end
		if p.filter then
			return p.filter(f)
		end
		if p.allies and f ~= p.owner and S.isAlly(p.owner, f) and not f.isSummon then
			return true
		end
		return defaultFilter(p, f)
	end)
	for _, c in ipairs(candidates) do
		local f = c.f
		p.hits[f] = true
		if S.Combat.isInvulnerable(f) then
			S.FX.hit(f, 0, "evade", p.owner, { projectile = true })
			S.Combat.hook(f, "evaded", p.owner, { projectile = p })
			S.Combat.extraHooks(f, "evaded", p.owner, { projectile = p })
			S.emit("evaded", f, p.owner, { projectile = p })
		else
			local result
			if p.allies and S.isAlly(p.owner, f) and p.onAlly then
				result = p.onAlly(p, f)
			elseif p.onHit then
				local ok, r = pcall(p.onHit, p, f)
				if not ok then
					warn("[EB] projectile onHit: " .. tostring(r))
				end
				result = r
			end
			-- target hooks for projectile interception (mirrors, shields...)
			if p.alive then
				p.hitCount += 1
				local unlimited = p.pierce == true
				if result ~= "continue" and not unlimited and p.hitCount > (p.pierce or 0) then
					p.pos = a + (segEnd - a) * c.s
					Proj.stop(p, "hit", p.pos)
					return
				end
			else
				return
			end
		end
	end
	if wallRes then
		p.pos = wallRes.Position
		local obj = S.Objects.fromPart(wallRes.Instance)
		-- objects may intercept projectiles (mirrors reflect, lenses bend...)
		if obj and obj.onProjectile then
			local r = obj.onProjectile(obj, p, wallRes.Normal, wallRes.Position)
			if r == "consumed" then
				p.pos = wallRes.Position + wallRes.Normal * (p.radius + 0.4)
				p.needSync = true
				return
			elseif r == "stop" then
				Proj.stop(p, "intercepted", wallRes.Position)
				return
			end
		end
		local result
		if p.onWall then
			result = p.onWall(p, wallRes.Position, wallRes.Normal, obj)
		end
		-- shots never erode constructs owned by their own side
		if obj and result ~= "pass" and result ~= "bounce" then
			if not (p.owner and obj.owner and S.isAlly(p.owner, obj.owner)) then
				S.Objects.damage(obj, p.objDmg or p.dmg or 40, p.owner, { projectile = p })
			end
		end
		if result == "bounce" then
			p.pos = wallRes.Position + wallRes.Normal * (p.radius + 0.3)
			p.hits = p.data.keepHits and p.hits or {}
			p.needSync = true
			S.FX.cue("projBounce", { pid = p.id, p = p.pos, n = wallRes.Normal, k = p.element })
			return
		end
		if result ~= "pass" and result ~= "continue" then
			Proj.stop(p, "wall", wallRes.Position)
			return
		end
	end
	p.pos = b
	p.traveled += move.Magnitude
	-- corrections: velocity changed by something other than gravity (homing, onStep, ground follow)
	if p.visual then
		local expect = p.syncVel
		if p.gravity then
			expect = expect - Vector3.new(0, p.gravity * (S.now() - p.lastSync), 0)
		end
		local now = S.now()
		if p.needSync or ((p.vel - expect).Magnitude > 0.5 and now - p.lastSync > 0.08) or now - p.lastSync > 1 then
			p.needSync = false
			p.lastSync = now
			p.syncVel = p.vel
			syncQueue[#syncQueue + 1] = { p.id, p.pos, p.vel }
		end
	end
	if p.traveled >= p.range then
		Proj.stop(p, "range", p.pos)
	end
end

RunService.Heartbeat:Connect(function(dt)
	if #syncQueue > 0 then
		local batch = syncQueue
		syncQueue = {}
		if syncRemote then
			-- UnreliableRemoteEvent payloads are capped (~1 KB): send in small chunks
			local CHUNK = 12
			for i = 1, #batch, CHUNK do
				syncRemote:FireAllClients(table.move(batch, i, math.min(#batch, i + CHUNK - 1), 1, {}))
			end
		end
	end
	for _, p in pairs(list) do
		if p.alive then
			S.FX.current = S.FX.ctxOf(p.owner)
			local ok, err = pcall(step, p, dt)
			S.FX.current = nil
			if not ok then
				warn("[EB] projectile error: " .. tostring(err))
				Proj.stop(p, "error")
			end
		end
	end
end)

return Proj
