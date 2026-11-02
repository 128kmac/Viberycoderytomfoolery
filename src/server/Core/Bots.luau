-- Simple practice AI: approaches, strafes, guards against windups, dodges shots, uses its kit.
local S = require(script.Parent.S)

local Bots = {}
S.Bots = Bots

local M = S.Config.METRE
local rng = Random.new()

local function pickTarget(f)
	local best, bd
	for _, t in pairs(S.fighters) do
		if S.alive(t) and t ~= f and S.isEnemy(f, t) and not t.isDummy and t.untargetable <= 0 then
			local d = (t.root.Position - f.root.Position).Magnitude
			if t.isSummon then
				d += 40
			end
			if not bd or d < bd then
				best, bd = t, d
			end
		end
	end
	return best, bd
end

local function think(f, now)
	local t, d = pickTarget(f)
	local hum = f.humanoid
	if not t or not hum then
		f.aim = nil
		return
	end
	local myPos = f.root.Position
	local tp = t.root.Position
	local dm = d / M
	-- aim with a little inaccuracy
	local lead = t.root.AssemblyLinearVelocity * math.min(0.4, dm / 24) * 0.6
	local hitPos = tp + lead + Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
	local g = S.Hit.ground(hitPos) or hitPos
	f.aim = {
		origin = myPos + Vector3.new(0, 1.5, 0),
		dir = (hitPos - myPos).Unit,
		hit = dm < 3 and tp or Vector3.new(hitPos.X, (hitPos.Y + g.Y) / 2, hitPos.Z),
		target = t.model,
	}
	f.botState = f.botState or { strafe = 1, nextStrafe = 0, guardUntil = 0 }
	local st = f.botState
	-- guard against visible windups
	if t.action and t.action.phase == "windup" and dm < 16 and not S.Cast.isBusy(f) and rng:NextNumber() < 0.35 then
		S.Fighter.setGuard(f, true)
		st.guardUntil = now + rng:NextNumber(0.4, 0.9)
	end
	if f.guarding and now > st.guardUntil then
		S.Fighter.setGuard(f, false)
	end
	-- dodge nearby incoming projectiles
	if f.dodgeCharges > 0 and rng:NextNumber() < 0.25 then
		for _, p in ipairs(S.Proj.inRadius(myPos, M * 5, function(p)
			return p.owner and S.isEnemy(f, p.owner)
		end)) do
			local toMe = myPos - p.pos
			if toMe.Magnitude > 0.1 and p.vel.Unit:Dot(toMe.Unit) > 0.7 then
				local side = p.vel.Unit:Cross(Vector3.yAxis)
				S.Fighter.dodge(f, side * (rng:NextNumber() < 0.5 and 1 or -1))
				break
			end
		end
	end
	-- movement
	if now > st.nextStrafe then
		st.strafe = -st.strafe
		st.nextStrafe = now + rng:NextNumber(0.8, 2)
		if rng:NextNumber() < 0.15 then
			hum.Jump = true
		end
	end
	local flat = Vector3.new(tp.X - myPos.X, 0, tp.Z - myPos.Z)
	local dir = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, 1)
	local side = dir:Cross(Vector3.yAxis) * st.strafe
	local goal
	local wanted = f.botRange or 7
	if dm > wanted + 3 then
		goal = myPos + dir * 12 + side * 4
	elseif dm < wanted - 3 then
		goal = myPos - dir * 6 + side * 6
	else
		goal = myPos + side * 8
	end
	-- stay inside the arena
	local b = S.arenaBounds
	if b then
		local h = b.half - 12
		goal = Vector3.new(math.clamp(goal.X, b.center.X - h, b.center.X + h), goal.Y, math.clamp(goal.Z, b.center.Z - h, b.center.Z + h))
	end
	hum:MoveTo(goal)
	-- face target when acting
	if not f.guarding and not S.Cast.isBusy(f) then
		-- basic attack in melee range
		if dm < 3 then
			f.root.CFrame = CFrame.lookAt(myPos, myPos + dir)
			S.Fighter.basic(f)
		end
		-- abilities
		if f.kitData and rng:NextNumber() < 0.45 then
			local order = { 5, 1, 2, 3, 4 }
			for _, slot in ipairs(order) do
				local def = f.kitData.moves[slot]
				local range = (def.range and def.range > 0) and def.range or 6
				local okRange = dm <= range + 2
				if slot == 5 then
					okRange = dm <= math.max(range, 8)
				end
				if okRange and (slot ~= 5 or f.proxima >= 100) then
					local ok = S.Cast.canStart(f, slot)
					if ok and rng:NextNumber() < (slot == 5 and 0.8 or 0.5) then
						f.root.CFrame = CFrame.lookAt(myPos, myPos + dir)
						S.Cast.begin(f, slot, f.heat >= 60 and rng:NextNumber() < 0.3 and slot == 5, rng:NextNumber() < 0.3)
						-- recasts later
						break
					end
				end
			end
		end
		-- use open recast windows sometimes
		for slot, r in pairs(f.recasts) do
			if r.expires > now and rng:NextNumber() < 0.3 then
				S.Cast.press(f, slot, true, false)
				break
			end
		end
		-- kit action key occasionally
		if f.kit and f.kit.action and rng:NextNumber() < 0.05 then
			S.Cast.kitAction(f)
		end
	end
	-- preferred range from kit: average of moves 1-4
	if not f.botRange and f.kitData then
		local sum, n = 0, 0
		for slot = 1, 4 do
			local r = f.kitData.moves[slot].range
			if r and r > 0 then
				sum += r
				n += 1
			end
		end
		f.botRange = n > 0 and math.clamp(sum / n * 0.6, 3, 14) or 5
	end
end

local timer = 0
game:GetService("RunService").Heartbeat:Connect(function(dt)
	timer += dt
	if timer < 0.2 then
		return
	end
	timer = 0
	local now = S.now()
	for _, f in pairs(S.fighters) do
		if f.isBot and S.alive(f) and S.Fighter.canAct(f) then
			local ok, err = pcall(think, f, now)
			if not ok then
				warn("[EB] bot think: " .. tostring(err))
			end
		end
	end
end)

return Bots
