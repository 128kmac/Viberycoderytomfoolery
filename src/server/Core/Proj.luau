-- Server-simulated projectiles. Default: 24 m/s, 0.3 m wide, stops on first solid collision.
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local S = require(script.Parent.S)

local Proj = {}
S.Proj = Proj

local Config = S.Config
local M = Config.METRE
local list = {}
local nextId = 0
Proj.list = list

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
	if not opts.noVisual then
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = opts.color or (owner and S.Util.color(owner.kitName)) or Color3.new(1, 1, 1)
		if opts.shape == "Block" then
			part.Size = opts.size or Vector3.new(p.radius * 2, p.radius * 2, math.max(1, p.radius * 4))
		else
			part.Shape = Enum.PartType.Ball
			part.Size = opts.size or Vector3.one * math.max(0.6, p.radius * 2)
		end
		part.Transparency = opts.transparency or 0.1
		part.CFrame = CFrame.lookAt(p.pos, p.pos + p.vel)
		part.Name = "Projectile"
		part.Parent = S.folders.FX
		p.part = part
		S.FX.trail(part, part.Color)
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
	if p.part then
		Debris:AddItem(p.part, 0.05)
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
	if p.part then
		p.part.Color = S.Util.color(newOwner.kitName)
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
		local g = S.Hit.ground(b + Vector3.new(0, 2, 0), 8)
		if g then
			b = Vector3.new(b.X, g.Y + p.radius + 0.3, b.Z)
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
		local result
		if p.onWall then
			result = p.onWall(p, wallRes.Position, wallRes.Normal, obj)
		end
		if obj and result ~= "pass" then
			if not (p.owner and obj.owner and not S.isEnemy(p.owner, obj.owner) and obj.allyPass) then
				S.Objects.damage(obj, p.objDmg or p.dmg or 40, p.owner, { projectile = p })
			end
		end
		if result == "bounce" then
			p.pos = wallRes.Position + wallRes.Normal * (p.radius + 0.3)
			p.hits = p.data.keepHits and p.hits or {}
			if p.part then
				p.part.CFrame = CFrame.lookAt(p.pos, p.pos + p.vel)
			end
			return
		end
		if result ~= "pass" and result ~= "continue" then
			Proj.stop(p, "wall", wallRes.Position)
			return
		end
	end
	p.pos = b
	p.traveled += move.Magnitude
	if p.part then
		if p.vel.Magnitude > 0.01 then
			p.part.CFrame = CFrame.lookAt(p.pos, p.pos + p.vel)
		else
			p.part.CFrame = CFrame.new(p.pos)
		end
	end
	if p.traveled >= p.range then
		Proj.stop(p, "range", p.pos)
	end
end

RunService.Heartbeat:Connect(function(dt)
	for _, p in pairs(list) do
		if p.alive then
			local ok, err = pcall(step, p, dt)
			if not ok then
				warn("[EB] projectile error: " .. tostring(err))
				Proj.stop(p, "error")
			end
		end
	end
end)

return Proj
