-- Bot AI. Each bot is a full fighter with a kit; the brain reads the same information players get:
-- telegraphs (Danger registry), incoming projectiles, enemy windups, line of sight and the nav graph.
--   * threat response: leave telegraphed areas before impact, dodge or guard shots, guard visible windups
--   * positioning: path to the target with A* when out of sight/range, hold a kit-appropriate range,
--     strafe, flank occasionally, retreat when low, unstick itself
--   * offence: basic attacks in reach, abilities chosen by range/LOS/cooldown/energy, recasts, ultimates
-- Difficulty scales reaction time, aim error, guard/dodge reliability and ability cadence.
-- Training dummies (Practice) are also driven here: Idle / Guard / Strafe / Shoot behaviours.
local RunService = game:GetService("RunService")
local S = require(script.Parent.S)

local Bots = {}
S.Bots = Bots

local Config = S.Config
local M = Config.METRE
local rng = Random.new()

local PROFILES = {
	Easy = { think = 0.32, react = 0.5, aimErr = 3.2, guard = 0.15, dodge = 0.12, ability = 0.35, danger = 0.55, perfect = 0, ult = 0.5, unstable = 0, flank = 0.05 },
	Normal = { think = 0.2, react = 0.3, aimErr = 1.6, guard = 0.35, dodge = 0.35, ability = 0.6, danger = 0.85, perfect = 0.15, ult = 0.85, unstable = 0.15, flank = 0.12 },
	Hard = { think = 0.13, react = 0.17, aimErr = 0.7, guard = 0.55, dodge = 0.6, ability = 0.85, danger = 1.0, perfect = 0.45, ult = 1, unstable = 0.4, flank = 0.2 },
}
Bots.PROFILES = PROFILES

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function flatUnit(v)
	local f = flat(v)
	if f.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return f.Unit
end

local function brain(f)
	local b = f.brain
	if not b then
		b = {
			nextThink = 0,
			path = nil,
			pathIdx = 1,
			pathGoal = nil,
			repathAt = 0,
			lastPos = f.root.Position,
			lastMoveCheck = S.now(),
			stuck = 0,
			strafe = rng:NextNumber() < 0.5 and 1 or -1,
			strafeUntil = 0,
			guardUntil = 0,
			evadeUntil = 0,
			evadeGoal = nil,
			nextAbility = S.now() + rng:NextNumber(0.6, 1.4),
			nextTargetPick = 0,
			flankUntil = 0,
			retreatUntil = 0,
			faceDir = f.root.CFrame.LookVector,
		}
		f.brain = b
		if f.humanoid then
			f.humanoid.AutoRotate = false
		end
	end
	return b
end

local function profileOf(f)
	return PROFILES[f.botDifficulty or "Normal"] or PROFILES.Normal
end

local function los(a, b)
	return S.Hit.los(a, b, false)
end

-- preferred engagement range (studs) from the kit's move ranges
local function preferredRange(f)
	if f.botRange then
		return f.botRange
	end
	local sum, n = 0, 0
	if f.kitData then
		for slot = 1, 4 do
			local r = f.kitData.moves[slot].range
			if r and r > 0 then
				sum += r
				n += 1
			end
		end
	end
	-- stay inside the Proxima contest band (12 m) so duels build toward ultimates
	local m = n > 0 and math.clamp(sum / n * 0.5, 2.2, 9) or 4
	f.botRange = m * M
	return f.botRange
end

local function validTarget(f, t)
	if not S.alive(t) or t == f or not S.isEnemy(f, t) then
		return false
	end
	if t.isDummy or (t.untargetable or 0) > 0 then
		return false
	end
	local e = f.entrant
	if e and e.spar then
		-- sparring partners only fight players in the Annex
		return t.player ~= nil
	end
	return true
end

local function pickTarget(f, b, now)
	if b.target and validTarget(f, b.target) and now < b.nextTargetPick then
		return b.target
	end
	b.nextTargetPick = now + rng:NextNumber(0.8, 1.6)
	local myPos = f.root.Position
	local best, bs
	for _, t in pairs(S.fighters) do
		if validTarget(f, t) then
			local d = (t.root.Position - myPos).Magnitude
			local score = d
			if t.isSummon then
				score += 45
			end
			if not los(myPos, t.root.Position) then
				score += 30
			end
			if f.lastDamager == t and now - (f.lastHit or 0) < 3 then
				score -= 25
			end
			score -= (1 - t.health / t.maxHealth) * 30
			if t == b.target then
				score -= 10 -- stickiness
			end
			if not bs or score < bs then
				best, bs = t, score
			end
		end
	end
	b.target = best
	return best
end

-- Movement ---------------------------------------------------------------------------------------
local function setPath(f, b, goal, now)
	local path = S.Nav.path(f.root.Position, goal, function(n)
		return S.Danger.unsafe(f, n.pos) and 60 or 0
	end)
	b.path = path
	b.pathIdx = 2
	b.pathGoal = goal
	b.repathAt = now + 0.9
	return path ~= nil
end

local function moveTo(f, pos)
	local hum = f.humanoid
	if hum then
		hum:MoveTo(pos)
	end
	f.botMoveGoal = pos
end

local function followPath(f, b)
	local path = b.path
	if not path then
		return false
	end
	local myPos = f.root.Position
	local idx = b.pathIdx
	-- advance past reached waypoints; skip ahead when the next-next node is directly walkable
	while idx <= #path do
		local n = path[idx]
		local d = flat(n.pos - myPos).Magnitude
		if d < 3 and math.abs(n.pos.Y - (myPos.Y - 3)) < 3.5 then
			idx += 1
		elseif idx < #path then
			local nn = path[idx + 1]
			if math.abs(nn.pos.Y - n.pos.Y) < 1 and S.Nav.edgeKind(path[idx - 1] or n, n) == "walk" and S.Nav.walkableLine(myPos - Vector3.new(0, 3, 0), nn.pos) and flat(nn.pos - myPos).Magnitude < 14 then
				idx += 1
			else
				break
			end
		else
			break
		end
	end
	b.pathIdx = idx
	if idx > #path then
		b.path = nil
		return false
	end
	local n = path[idx]
	local prev = path[idx - 1]
	if prev and S.Nav.edgeKind(prev, n) == "jump" and flat(n.pos - myPos).Magnitude < 7 then
		f.humanoid.Jump = true
	end
	moveTo(f, n.pos + Vector3.new(0, 3, 0))
	return true
end

local function checkStuck(f, b, now)
	if now - b.lastMoveCheck < 0.6 then
		return
	end
	local moved = flat(f.root.Position - b.lastPos).Magnitude
	b.lastPos = f.root.Position
	b.lastMoveCheck = now
	local wants = f.botMoveGoal and flat(f.botMoveGoal - f.root.Position).Magnitude > 3
	if wants and moved < 1.2 and f.humanoid.WalkSpeed > 4 then
		b.stuck += 1
		if b.stuck >= 2 then
			f.humanoid.Jump = true
		end
		if b.stuck >= 4 then
			b.path = nil
			b.repathAt = 0
			b.strafe = -b.strafe
			b.stuck = 0
		end
	else
		b.stuck = 0
	end
end

-- Offence ----------------------------------------------------------------------------------------
local function aimAt(f, t, prof)
	local myPos = f.root.Position
	local tp = t.root.Position
	local dist = (tp - myPos).Magnitude
	local vel = t.root.AssemblyLinearVelocity
	local lead = flat(vel) * math.min(0.6, dist / (Config.PROJ_SPEED * M)) * 0.85
	local err = prof.aimErr * math.clamp(dist / 40, 0.3, 1.5)
	local hitPos = tp + lead + Vector3.new(rng:NextNumber(-err, err), rng:NextNumber(-err, err) * 0.4, rng:NextNumber(-err, err))
	local origin = myPos + Vector3.new(0, 1.5, 0)
	local dir = hitPos - origin
	if dir.Magnitude < 0.1 then
		dir = f.root.CFrame.LookVector
	end
	f.aim = { origin = origin, dir = dir.Unit, hit = hitPos, target = t.model }
end

local function face(f, b, dir)
	b.faceDir = flatUnit(dir)
end

local function snapFace(f, dir)
	local d = flatUnit(dir)
	local p = f.root.Position
	f.root.CFrame = CFrame.lookAt(p, p + d)
end

local function tryAbilities(f, b, t, dist, hasLos, prof, now)
	if now < b.nextAbility or not f.kitData then
		return false
	end
	b.nextAbility = now + rng:NextNumber(0.3, 0.8) / prof.ability
	local moves = f.kitData.moves
	-- ultimate first
	if f.proxima >= Config.MAX_PROXIMA and rng:NextNumber() < prof.ult then
		local def = moves[5]
		local r = (def.range and def.range > 0) and def.range * M or 8 * M
		if dist <= math.max(r, 8 * M) and (hasLos or dist < 6 * M) then
			local unstable = f.heat >= Config.UNSTABLE_MIN_HEAT and rng:NextNumber() < prof.unstable
			if S.Cast.canStart(f, 5, unstable) then
				snapFace(f, t.root.Position - f.root.Position)
				S.Cast.begin(f, 5, unstable, rng:NextNumber() < 0.3)
				return true
			end
		end
	end
	if rng:NextNumber() > math.min(1, prof.ability + 0.25) then
		return false
	end
	local order = { 1, 2, 3, 4 }
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	for _, slot in ipairs(order) do
		local def = moves[slot]
		local r = def.range
		local ok
		if r and r > 0 then
			local rs = r * M
			ok = dist <= rs * 0.92 and (hasLos or rs < 5 * M)
		else
			-- self / utility move: use when an enemy is near
			ok = dist < 7 * M and rng:NextNumber() < 0.5
		end
		-- keep a little energy in reserve for defence
		if ok and def.energy and f.energy - def.energy < 12 and t.health / t.maxHealth > 0.25 then
			ok = rng:NextNumber() < 0.3
		end
		if ok and S.Cast.canStart(f, slot) then
			snapFace(f, t.root.Position - f.root.Position)
			local started = S.Cast.begin(f, slot, false, rng:NextNumber() < 0.25)
			if started then
				-- release held moves after a natural-looking charge
				task.delay(rng:NextNumber(0.35, 1.1), function()
					if S.alive(f) then
						S.Cast.press(f, slot, false, false)
					end
				end)
				return true
			end
		end
	end
	return false
end

-- Main think -------------------------------------------------------------------------------------
local function think(f, now)
	local b = brain(f)
	local prof = profileOf(f)
	local hum = f.humanoid
	if not hum then
		return
	end
	local myPos = f.root.Position
	checkStuck(f, b, now)
	-- 1. threats ------------------------------------------------------------------------------
	local busy = S.Cast.isBusy(f)
	local threat = rng:NextNumber() < prof.danger and S.Danger.threat(f, myPos, prof.react) or nil
	if threat and not busy then
		local speed = math.max(4, hum.WalkSpeed)
		local need = threat.distanceOut / speed
		if threat.timeLeft < need + 0.1 and threat.timeLeft < 0.9 and f.dodgeCharges > 0 and rng:NextNumber() < prof.dodge * 2 then
			S.Fighter.dodge(f, threat.escapeDir)
		elseif threat.timeLeft < 0.35 and not threat.field and rng:NextNumber() < prof.guard then
			S.Fighter.setGuard(f, true)
			b.guardUntil = now + 0.5
		end
		b.evadeGoal = myPos + threat.escapeDir * (threat.distanceOut + 4)
		b.evadeUntil = now + math.max(0.4, math.min(1.5, threat.timeLeft + 0.3))
		b.path = nil
	end
	local inc, tHit = S.Danger.incoming(f, 0.75)
	if inc and now - (inc.born or 0) > prof.react * 0.6 and not busy then
		local side = flatUnit(inc.vel):Cross(Vector3.yAxis)
		if f.dodgeCharges > 0 and tHit < 0.45 and rng:NextNumber() < prof.dodge then
			S.Fighter.dodge(f, side * (rng:NextNumber() < 0.5 and 1 or -1))
		elseif rng:NextNumber() < prof.guard and tHit < 0.5 then
			snapFace(f, -inc.vel)
			S.Fighter.setGuard(f, true)
			b.guardUntil = now + tHit + 0.2
		end
	end
	-- 2. target ------------------------------------------------------------------------------
	local t = pickTarget(f, b, now)
	if not t then
		f.aim = nil
		if f.guarding and now > b.guardUntil then
			S.Fighter.setGuard(f, false)
		end
		-- wander toward the arena centre
		if not b.path or now > b.repathAt then
			local c = S.arenaBounds and S.arenaBounds.center or Vector3.zero
			local n = S.Nav.ready and S.Nav.randomNear(c, 0, 40)
			if n then
				setPath(f, b, n.pos, now)
				b.repathAt = now + 4
			end
		end
		followPath(f, b)
		return
	end
	local tp = t.root.Position
	local toT = tp - myPos
	local dist = toT.Magnitude
	local hasLos = los(myPos + Vector3.new(0, 1.5, 0), tp + Vector3.new(0, 1, 0))
	aimAt(f, t, prof)
	-- 3. guard against windups ------------------------------------------------------------------
	local ta = t.action
	if ta and ta.phase == "windup" and dist < 18 * M and not busy then
		local facing = flatUnit(t.root.CFrame.LookVector):Dot(flatUnit(-toT))
		local castEnd = t.model:GetAttribute("CastEnd") or 0
		if facing > 0.55 then
			local perfectTry = rng:NextNumber() < prof.perfect
			if perfectTry then
				if castEnd - now < 0.22 then
					snapFace(f, toT)
					S.Fighter.setGuard(f, true)
					b.guardUntil = now + 0.45
				end
			elseif rng:NextNumber() < prof.guard * 0.6 then
				snapFace(f, toT)
				S.Fighter.setGuard(f, true)
				b.guardUntil = now + rng:NextNumber(0.4, 0.8)
			end
		end
	end
	if f.guarding and now > b.guardUntil then
		S.Fighter.setGuard(f, false)
	end
	-- 4. movement ------------------------------------------------------------------------------
	local want = preferredRange(f)
	-- press the advantage: close distance on a weakened target
	if t.health / t.maxHealth < 0.35 and f.health / f.maxHealth > 0.5 then
		want = math.min(want, 4 * M)
	end
	local lowHp = f.health / f.maxHealth < 0.3
	if lowHp and now > b.retreatUntil and dist < want + 6 and rng:NextNumber() < 0.15 and S.Nav.ready then
		local far = S.Nav.randomNear(myPos, 18, 45, function(n)
			return (n.pos - tp).Magnitude > dist + 10
		end)
		if far then
			setPath(f, b, far.pos, now)
			b.retreatUntil = now + rng:NextNumber(1.5, 2.6)
		end
	end
	if now < b.evadeUntil and b.evadeGoal then
		moveTo(f, b.evadeGoal)
		face(f, b, toT)
	elseif now < b.retreatUntil and b.path then
		followPath(f, b)
		face(f, b, toT)
	elseif not hasLos or dist > want + 7 then
		-- approach along the nav graph
		if not b.path or now > b.repathAt or (b.pathGoal and (b.pathGoal - tp).Magnitude > 10) then
			if not setPath(f, b, tp, now) then
				moveTo(f, tp)
			end
		end
		if not followPath(f, b) then
			moveTo(f, tp)
		end
		if b.path then
			local n = b.path[b.pathIdx]
			face(f, b, n and (n.pos - myPos) or toT)
		end
		if hasLos and dist < want + 20 then
			face(f, b, toT)
		end
	else
		b.path = nil
		-- flank now and then
		if now > b.flankUntil and rng:NextNumber() < prof.flank * 0.25 and S.Nav.ready then
			local side = flatUnit(toT):Cross(Vector3.yAxis) * b.strafe
			local goal = tp + side * want - flatUnit(toT) * want * 0.3
			local n = S.Nav.nearest(goal, 18)
			if n then
				setPath(f, b, n.pos, now)
				b.flankUntil = now + 2.5
			end
		end
		if now < b.flankUntil and b.path then
			followPath(f, b)
		else
			if now > b.strafeUntil then
				b.strafe = -b.strafe
				b.strafeUntil = now + rng:NextNumber(0.7, 1.9)
				if rng:NextNumber() < 0.12 then
					hum.Jump = true
				end
			end
			local dir = flatUnit(toT)
			local side = dir:Cross(Vector3.yAxis) * b.strafe
			local goal
			if dist > want + 2 then
				goal = myPos + dir * 10 + side * 4
			elseif dist < want - 3 then
				goal = myPos - dir * 7 + side * 5
			else
				goal = myPos + side * 8 + dir * rng:NextNumber(-1, 1.5)
			end
			-- never strafe into a telegraphed area or off an edge
			if S.Danger.unsafe(f, goal) or not S.Hit.ground(goal + Vector3.new(0, 3, 0), 9) then
				b.strafe = -b.strafe
				goal = myPos - side * 6
			end
			moveTo(f, goal)
		end
		face(f, b, toT)
	end
	-- 5. offence -------------------------------------------------------------------------------
	if f.guarding or busy or not S.Fighter.canAct(f) then
		return
	end
	-- open recast windows
	for slot, r in pairs(f.recasts) do
		if r.expires and r.expires > now and rng:NextNumber() < 0.35 then
			S.Cast.press(f, slot, true, false)
			return
		end
	end
	if dist < (Config.BASIC_RANGE + 0.6) * M and hasLos then
		-- in reach: weave basics between abilities
		snapFace(f, toT)
		if rng:NextNumber() < 0.6 then
			S.Fighter.basic(f)
			return
		end
	end
	if tryAbilities(f, b, t, dist, hasLos, prof, now) then
		return
	end
	if dist < (Config.BASIC_RANGE + 0.6) * M and hasLos then
		S.Fighter.basic(f)
	end
	if f.kit and f.kit.action and rng:NextNumber() < 0.04 then
		S.Cast.kitAction(f)
	end
end

-- Training dummies -------------------------------------------------------------------------------
local function nearestPlayer(f, maxD)
	local best, bd
	for _, t in pairs(S.fighters) do
		if t.player and S.alive(t) then
			local d = (t.root.Position - f.root.Position).Magnitude
			if d < maxD and (not bd or d < bd) then
				best, bd = t, d
			end
		end
	end
	return best, bd
end

local function dummyThink(f, now)
	local mode = S.Match and S.Match.settings.dummyMode or "Idle"
	local hum = f.humanoid
	if not hum then
		return
	end
	f.dummyMobile = mode == "Strafe"
	local t = nearestPlayer(f, 70)
	if mode == "Guard" then
		if t then
			snapFace(f, t.root.Position - f.root.Position)
			if not f.guarding then
				S.Fighter.setGuard(f, true)
			end
		end
		return
	end
	if f.guarding then
		S.Fighter.setGuard(f, false)
	end
	if mode == "Strafe" then
		f.dummyPhase = f.dummyPhase or 1
		if now > (f.dummyNext or 0) then
			f.dummyPhase = -f.dummyPhase
			f.dummyNext = now + 2.2
		end
		local home = f.dummyHome or f.root.Position
		local side = Vector3.new(1, 0, 0)
		if S.Arena.annex and S.Arena.annex.dummyFacing then
			side = S.Arena.annex.dummyFacing:Cross(Vector3.yAxis).Unit
		end
		moveTo(f, home + side * 9 * f.dummyPhase + Vector3.new(0, 3, 0))
		if t then
			snapFace(f, t.root.Position - f.root.Position)
		end
	elseif mode == "Shoot" and t then
		snapFace(f, t.root.Position - f.root.Position)
		if now > (f.dummyNext or 0) then
			f.dummyNext = now + 2.6
			f.dummyShots = (f.dummyShots or 0) + 1
			local origin = f.root.Position + Vector3.new(0, 1.2, 0)
			if f.dummyShots % 3 == 0 then
				-- telegraphed slam at the player's feet: teaches reading warnings
				local g = S.Hit.ground(t.root.Position) or t.root.Position
				local r = 2.5
				S.FX.telegraph(g, r * M, 1.1, Color3.fromRGB(255, 120, 60), f)
				local id = S.Danger.add({ shape = "circle", pos = g, radius = r * M, t1 = now + 1.1, owner = f })
				task.delay(1.1, function()
					S.Danger.remove(id)
					if not S.alive(f) then
						return
					end
					S.FX.burst(g + Vector3.new(0, 1, 0), r * M, Color3.fromRGB(255, 140, 70), 0.35)
					for _, v in ipairs(S.Hit.cylinder(g, r * M, function(x)
						return x.player ~= nil
					end)) do
						S.Combat.damage(f, v, 60, { fromPos = g, kind = "direct" })
					end
				end)
			else
				local dir = (t.root.Position - origin).Unit
				S.Proj.fire({
					owner = f,
					origin = origin,
					dir = dir,
					speed = 14 * M,
					radius = 0.6,
					range = 30 * M,
					color = Color3.fromRGB(255, 170, 90),
					element = "Dummy",
					onHit = function(p, v)
						S.Combat.damage(f, v, 40, { fromPos = p.pos, projectile = true })
					end,
					filter = function(v)
						return v.player ~= nil
					end,
				})
			end
		end
	end
end

-- Facing: bots turn smoothly toward their desired facing every frame --------------------------
local function faceStep(f, dt)
	local b = f.brain
	if not b or not b.faceDir or f.dead or not f.root then
		return
	end
	if S.Cast.isBusy(f) and f.action and f.action.phase ~= "windup" then
		return
	end
	local cur = flatUnit(f.root.CFrame.LookVector)
	local want = b.faceDir
	local ang = math.acos(math.clamp(cur:Dot(want), -1, 1))
	if ang < 0.02 then
		return
	end
	local maxA = math.rad(600) * dt
	local tt = math.min(1, maxA / ang)
	local nd = cur:Lerp(want, tt)
	if nd.Magnitude < 1e-3 then
		nd = want
	end
	local p = f.root.Position
	f.root.CFrame = CFrame.lookAt(p, p + nd.Unit)
end

local function active(f)
	local m = S.Match
	if not m then
		return true
	end
	local e = f.entrant
	if m.state == "Fight" then
		return e == nil or e.inMatch or e.spar
	end
	if m.state == "Practice" then
		return e ~= nil and e.spar == true
	end
	return false
end
Bots.active = active

RunService.Heartbeat:Connect(function(dt)
	local now = S.now()
	for _, f in pairs(S.fighters) do
		if f.isBot and S.alive(f) then
			if S.Fighter.canAct(f) and active(f) then
				local b = brain(f)
				if now >= b.nextThink then
					b.nextThink = now + profileOf(f).think * rng:NextNumber(0.85, 1.15)
					local ok, err = pcall(think, f, now)
					if not ok then
						warn("[EB] bot think: " .. tostring(err))
					end
				end
				faceStep(f, dt)
				f.botWasActive = true
			elseif f.botWasActive and f.humanoid and not active(f) then
				-- stop once when a bot becomes inactive (phase change); never fight other controllers
				f.botWasActive = false
				f.humanoid:Move(Vector3.zero)
				f.botMoveGoal = nil
			end
		elseif f.isDummy and S.alive(f) and S.Fighter.canAct(f) then
			if now >= (f.dummyThink or 0) then
				f.dummyThink = now + 0.2
				local ok, err = pcall(dummyThink, f, now)
				if not ok then
					warn("[EB] dummy: " .. tostring(err))
				end
			end
		end
	end
end)

return Bots
