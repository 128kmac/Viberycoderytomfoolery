-- Summons / companions / constructs that act: lightweight kinematic fighters owned by a caster.
-- They cannot capture objectives, generate Proxima, create more summons or count as real players.
local RunService = game:GetService("RunService")
local S = require(script.Parent.S)

local Summons = {}
S.Summons = Summons

local M = S.Config.METRE
local active = {}
Summons.active = active

--[[ opts:
	owner, name, pos (studs), hp, duration, speed (m/s), size (Vector3 studs), color, shape ("Ball"|"Block"),
	material, attack = { range (m), dmg, interval, kind ("melee"|"ranged"), projSpeed (m/s), onHit(sm, t), push },
	ai = "chase" | "stay" | "follow" | "turret" | "none", aggro (m), leash (m), target, flying (height studs),
	onDeath(sm, src), onExpire(sm), onTick(sm, dt), controlImmune, data, visible tell
]]
function Summons.create(opts)
	local owner = opts.owner
	local model = Instance.new("Model")
	model.Name = (opts.name or "Summon")
	local size = opts.size or Vector3.new(2.4, 2.4, 2.4)
	local body = Instance.new("Part")
	body.Name = "HumanoidRootPart"
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.Size = size
	if opts.shape ~= "Block" then
		body.Shape = Enum.PartType.Ball
	end
	body.Material = opts.material or Enum.Material.Neon
	body.Color = opts.color or (owner and S.Util.color(owner.kitName)) or Color3.new(1, 1, 1)
	body.Transparency = opts.transparency or 0.1
	local pos = opts.pos or (owner and owner.root.Position)
	body.CFrame = CFrame.new(pos)
	body.Parent = model
	local eye = Instance.new("Part")
	eye.Name = "Eye"
	eye.Anchored = true
	eye.CanCollide = false
	eye.CanQuery = false
	eye.Size = Vector3.new(size.X * 0.5, size.Y * 0.2, 0.2)
	eye.Color = Color3.new(0, 0, 0)
	eye.Material = Enum.Material.SmoothPlastic
	eye.CFrame = body.CFrame * CFrame.new(0, size.Y * 0.15, -size.Z / 2)
	eye.Parent = model
	model.PrimaryPart = body
	model.Parent = S.folders.Summons
	local f = S.Fighter.new(model, {
		isSummon = true,
		owner = owner,
		team = owner and owner.team,
		maxHealth = opts.hp or 150,
		name = (owner and (owner.name .. "'s ") or "") .. (opts.name or "Summon"),
		radius = math.max(size.X, size.Z) / 2,
	})
	f.kitName = owner and owner.kitName
	f.sm = {
		speed = (opts.speed or S.Config.SUMMON_SPEED) * M,
		attack = opts.attack,
		ai = opts.ai or "chase",
		aggro = (opts.aggro or 20) * M,
		leash = opts.leash and opts.leash * M or nil,
		target = opts.target,
		goal = nil,
		lastAttack = 0,
		lastSeen = 0,
		expires = opts.duration and (S.now() + opts.duration) or nil,
		onDeath = opts.onDeath,
		onExpire = opts.onExpire,
		onTick = opts.onTick,
		flying = opts.flying,
		size = size,
		eye = eye,
		hover = size.Y / 2 + (opts.flying or 0.2),
	}
	f.data = opts.data or {}
	f.controlImmune = opts.controlImmune
	f.energy = 0
	if owner then
		table.insert(owner.summons, f)
	end
	active[f] = true
	return f
end

function Summons.remove(f, reason)
	if not active[f] then
		return
	end
	active[f] = nil
	f.dead = true
	if f.owner then
		local i = table.find(f.owner.summons, f)
		if i then
			table.remove(f.owner.summons, i)
		end
	end
	S.fighters[f.id] = nil
	S.byModel[f.model] = nil
	if f.model then
		S.FX.burst(f.root.Position, 3, f.root.Color, 0.25)
		f.model:Destroy()
	end
	if reason == "expired" and f.sm.onExpire then
		S.safe(f.sm.onExpire, f)
	end
end

function Summons.command(f, target)
	if f.sm then
		f.sm.target = target
		f.sm.goal = nil
		f.sm.lastSeen = S.now()
	end
end

function Summons.moveTo(f, pos)
	if f.sm then
		f.sm.goal = pos
		f.sm.target = nil
	end
end

function Summons.owned(owner, name)
	local out = {}
	for _, f in ipairs(owner.summons) do
		if active[f] and (name == nil or f.model.Name == name) then
			table.insert(out, f)
		end
	end
	return out
end

local function nearestEnemy(f, range)
	local best, bd
	for _, t in pairs(S.fighters) do
		if S.alive(t) and S.isEnemy(f, t) and not (t.untargetable > 0) then
			local d = (t.root.Position - f.root.Position).Magnitude
			if d <= range and (not bd or d < bd) and S.Hit.los(f.root.Position, t.root.Position) then
				best, bd = t, d
			end
		end
	end
	return best
end
Summons.nearestEnemy = nearestEnemy

local function doAttack(f, t)
	local a = f.sm.attack
	local now = S.now()
	if now - f.sm.lastAttack < (a.interval or 1) then
		return
	end
	f.sm.lastAttack = now
	local src = f
	if a.kind == "ranged" then
		S.Proj.fire({
			owner = f,
			origin = f.root.Position,
			dir = (t.root.Position - f.root.Position).Unit,
			speed = (a.projSpeed or 24) * M,
			range = (a.range or 12) * M + 4,
			radius = 0.6,
			color = f.root.Color,
			dmg = a.dmg,
			onHit = function(_, target)
				S.Combat.damage(src, target, a.dmg or 30, { fromSummon = true, element = f.kitName })
				if a.onHit then
					a.onHit(f, target)
				end
			end,
		})
	else
		S.FX.beam(f.root.Position, t.root.Position, 0.4, f.root.Color, 0.12)
		S.Combat.damage(src, t, a.dmg or 30, { fromSummon = true, melee = true, element = f.kitName })
		if a.push then
			S.Combat.knockback(t, f.root.Position, a.push * M, src)
		end
		if a.onHit then
			a.onHit(f, t)
		end
	end
end

local aiTimer = 0
RunService.Heartbeat:Connect(function(dt)
	local now = S.now()
	aiTimer += dt
	local think = aiTimer >= 0.2
	if think then
		aiTimer = 0
	end
	for f in pairs(active) do
		if f.dead or not f.root or not f.root.Parent then
			Summons.remove(f, "dead")
		else
			local sm = f.sm
			S.FX.current = S.FX.ctxOf(f)
			if sm.expires and now >= sm.expires then
				Summons.remove(f, "expired")
			elseif f.owner and f.owner.dead and not sm.persist then
				Summons.remove(f, "owner")
			else
				if think then
					-- statuses / shields are updated by the main fighter tick
					if sm.onTick then
						S.safe(sm.onTick, f, 0.2)
					end
					-- choose target
					if sm.ai ~= "none" and sm.ai ~= "follow" then
						local t = sm.target
						if t and (not S.alive(t)) then
							t = nil
							sm.target = nil
						end
						if t then
							if S.Hit.los(f.root.Position, t.root.Position) then
								sm.lastSeen = now
							elseif now - sm.lastSeen > 1 then
								sm.target = nil
								t = nil
							end
						end
						if not t and sm.ai ~= "stay" then
							t = nearestEnemy(f, sm.aggro)
							if t then
								sm.autoTarget = t
							end
						elseif not t and sm.ai == "stay" then
							t = nearestEnemy(f, sm.attack and (sm.attack.range or 3) * M or 6)
						end
						sm.current = t
						if t and sm.attack then
							local d = (t.root.Position - f.root.Position).Magnitude
							if d <= (sm.attack.range or 2) * M + 2 then
								doAttack(f, t)
							end
						end
					end
					if f.sm and not active[f] then
						continue
					end
					if S.alive(f) and f.sm then
						f.model:SetAttribute("Health", math.floor(f.health))
					end
				end
				-- movement
				if not S.Fighter.canMove(f) then
					continue
				end
				local goal = sm.goal
				local t = sm.current
				if sm.ai == "follow" and f.owner and S.alive(f.owner) then
					goal = f.owner.root.Position + f.owner.root.CFrame.RightVector * 4
				elseif t and (sm.ai == "chase") then
					goal = t.root.Position
				end
				if sm.leash and f.owner and S.alive(f.owner) then
					if (f.root.Position - f.owner.root.Position).Magnitude > sm.leash then
						goal = f.owner.root.Position
					end
				end
				if goal and sm.ai ~= "turret" and sm.ai ~= "stay" or (goal and sm.goal) then
					local pos = f.root.Position
					local to = Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z)
					local stopAt = (t and sm.attack and (sm.attack.range or 2) * M * 0.8) or 1
					if to.Magnitude > stopAt then
						local mult = (1 - S.Status.slow(f)) * (1 + S.Status.speedBonus(f)) * (f.speedMult or 1)
						local stepLen = math.min(to.Magnitude - stopAt * 0.5, sm.speed * mult * dt)
						local dir = to.Unit
						local nextPos = pos + dir * stepLen
						local blocked = workspace:Raycast(pos, dir * (stepLen + sm.size.X / 2), S.Hit.worldParams)
						if blocked and not sm.flying then
							-- try sliding along the obstacle
							local n = blocked.Normal
							local slide = dir - n * dir:Dot(n)
							if slide.Magnitude > 0.1 then
								nextPos = pos + Vector3.new(slide.X, 0, slide.Z).Unit * stepLen
							else
								nextPos = pos
							end
						end
						local g = S.Hit.ground(nextPos + Vector3.new(0, 3, 0), 30)
						local y = g and (g.Y + sm.hover) or nextPos.Y
						local np = Vector3.new(nextPos.X, y, nextPos.Z)
						f.root.CFrame = CFrame.lookAt(np, np + dir)
					elseif sm.goal and to.Magnitude <= stopAt then
						sm.goal = nil
					end
				end
				if sm.eye and sm.eye.Parent then
					sm.eye.CFrame = f.root.CFrame * CFrame.new(0, sm.size.Y * 0.15, -sm.size.Z / 2)
				end
			end
		end
	end
	S.FX.current = nil
end)

-- death of summons is routed through the defeated event
S.on("defeated", function(f, killer)
	if f.isSummon and active[f] then
		if f.sm.onDeath then
			S.safe(f.sm.onDeath, f, killer)
		end
		Summons.remove(f, "defeated")
	end
end)

return Summons
