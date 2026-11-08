-- Procedural animator for every R15 fighter (players, bots, dummies, humanoid summons). Each client
-- writes Motor6D.Transform before physics every frame from replicated state (velocity, floor, cast phase
-- attributes, guard, dash, hits, death), blending layers with per-joint smoothing:
--   stance / breathing · directional run cycle with foot plants · jump, fall, landing squash ·
--   guard · cast anticipation → release (hand reaches the shared emission point) → follow-through →
--   recovery · basic-attack jabs · dash lean · hit flinch springs · death collapse · spawn rise.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Poses = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Poses"))

local Anim = {}
local ctx, Audio
local player = Players.LocalPlayer
local rigs = {} -- model -> state

local JOINTS = {
	Root = "LowerTorso",
	Waist = "UpperTorso",
	Neck = "Head",
	LeftShoulder = "LeftUpperArm",
	RightShoulder = "RightUpperArm",
	LeftElbow = "LeftLowerArm",
	RightElbow = "RightLowerArm",
	LeftWrist = "LeftHand",
	RightWrist = "RightHand",
	LeftHip = "LeftUpperLeg",
	RightHip = "RightUpperLeg",
	LeftKnee = "LeftLowerLeg",
	RightKnee = "RightLowerLeg",
	LeftAnkle = "LeftFoot",
	RightAnkle = "RightFoot",
}

local ID = CFrame.new()
local sin, cos, abs, clamp, exp = math.sin, math.cos, math.abs, math.clamp, math.exp

local function ang(x, y, z)
	return CFrame.Angles(x or 0, y or 0, z or 0)
end

local function setup(model)
	if rigs[model] then
		return rigs[model]
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return nil
	end
	local motors = {}
	for name, partName in pairs(JOINTS) do
		local p = model:FindFirstChild(partName)
		local m = p and p:FindFirstChild(name)
		if m and m:IsA("Motor6D") then
			motors[name] = m
		end
	end
	if not motors.Root then
		return nil
	end
	local st = {
		model = model,
		root = root,
		hum = hum,
		motors = motors,
		cur = {},
		phase = 0,
		lastStepPhase = 0,
		grounded = true,
		airTime = 0,
		landT = 10,
		landAmt = 0,
		lastVy = 0,
		flinch = Vector3.zero, -- axis * amount (spring)
		flinchV = Vector3.zero,
		basicN = 0,
		lastBasic = 0,
		spawnT = 0,
		lod = 0,
	}
	for name in pairs(motors) do
		st.cur[name] = ID
	end
	rigs[model] = st
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			rigs[model] = nil
		end
	end)
	return st
end

function Anim.flinch(model, dir, strength)
	local st = model and rigs[model]
	if not st then
		return
	end
	-- torso bends away from the hit: axis = up x dir (in world), converted at apply time
	local axis = Vector3.yAxis:Cross(dir)
	if axis.Magnitude < 1e-3 then
		axis = Vector3.xAxis
	end
	st.flinchV += axis.Unit * strength * 9
end

-- aim pitch for the local player comes from the camera; others from the server attribute
local function aimPitch(st)
	if st.model == player.Character and ctx.Camera then
		return ctx.Camera.pitch
	end
	return math.rad(st.model:GetAttribute("AimPitch") or 0)
end

-- rotation taking the hanging arm (0,-1,0) to point along localDir
local function armToward(localDir)
	local rest = Vector3.new(0, -1, 0)
	local d = localDir.Magnitude > 1e-3 and localDir.Unit or rest
	local axis = rest:Cross(d)
	local dot = clamp(rest:Dot(d), -1, 1)
	if axis.Magnitude < 1e-4 then
		return dot > 0 and ID or ang(math.pi, 0, 0)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

local function easeOut(k)
	return 1 - (1 - k) * (1 - k)
end

local function step(st, dt, now, serverNow)
	local model, root, hum = st.model, st.root, st.hum
	local m = model
	local T = {}
	for name in pairs(st.motors) do
		T[name] = ID
	end
	local vel = root.AssemblyLinearVelocity
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	local speed = flatVel.Magnitude
	local rcf = root.CFrame
	local localVel = rcf:VectorToObjectSpace(flatVel)
	local dead = m:GetAttribute("Dead") == true
	-- grounded state from humanoid floor material, falling back to a short ray
	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	local vy = vel.Y
	if grounded and not st.grounded then
		local impact = -st.lastVy
		if impact > 12 then
			st.landT = 0
			st.landAmt = clamp(impact / 60, 0.2, 1)
			if Audio and (model == player.Character or (root.Position - workspace.CurrentCamera.CFrame.Position).Magnitude < 50) then
				Audio.play("land", root.Position - Vector3.new(0, 3, 0), 0.6 + st.landAmt * 0.6)
			end
		end
	elseif not grounded and st.grounded and vy > 8 and Audio and model == player.Character then
		Audio.play("jump", root.Position)
	end
	st.grounded = grounded
	st.lastVy = vy
	st.landT += dt
	-- weights
	local run = grounded and clamp(speed / 16, 0, 1.2) or 0
	local casting = m:GetAttribute("CastPhase") or ""
	local castStart = m:GetAttribute("CastStart") or 0
	local castEnd = m:GetAttribute("CastEnd") or 0
	local castActive = m:GetAttribute("CastActive") or 0
	local recoverEnd = m:GetAttribute("RecoverEnd") or 0
	local hand = m:GetAttribute("CastHand") or "right"
	local isUlt = m:GetAttribute("CastUlt") == true
	local guarding = m:GetAttribute("Guarding") == true
	local dashAt = m:GetAttribute("DashAt") or 0
	local dashDur = m:GetAttribute("DashDur") or 0.3
	local basicAt = m:GetAttribute("BasicAt") or 0
	local spawnedAt = m:GetAttribute("SpawnedAt") or 0
	local combatStance = true

	-- 1. stance + breathing ------------------------------------------------------------------------
	local breath = sin(now * 2.1 + st.phase * 0.1) * 0.03
	T.Waist = ang(breath + 0.05, 0, 0)
	T.Neck = ang(-0.05 - breath, 0, 0)
	if combatStance then
		T.RightShoulder = ang(0.35, 0, 0.12)
		T.LeftShoulder = ang(0.45, 0, -0.12)
		T.RightElbow = ang(1.1, 0, 0)
		T.LeftElbow = ang(1.25, 0, 0)
	end
	T.LeftHip = ang(0.12, 0.08, -0.04)
	T.RightHip = ang(-0.06, -0.08, 0.04)
	T.LeftKnee = ang(-0.22, 0, 0)
	T.RightKnee = ang(-0.12, 0, 0)
	local rootOff = Vector3.new(0, -0.1 + breath * 0.5, 0)
	local rootRot = ID

	-- 2. locomotion --------------------------------------------------------------------------------
	if run > 0.05 then
		local stride = 5.2
		st.phase += speed * dt / stride * math.pi
		local ph = st.phase
		local dirL = localVel.Magnitude > 0.1 and localVel.Unit or Vector3.new(0, 0, -1)
		local axis = dirL:Cross(Vector3.yAxis)
		if axis.Magnitude < 1e-3 then
			axis = Vector3.xAxis
		end
		axis = axis.Unit
		local amp = 0.75 * math.min(run, 1)
		local swingL = sin(ph) * amp
		local swingR = -swingL
		local kneeL = -math.max(0, cos(ph)) * 1.1 * math.min(run, 1) - 0.15
		local kneeR = -math.max(0, -cos(ph)) * 1.1 * math.min(run, 1) - 0.15
		T.LeftHip = T.LeftHip:Lerp(CFrame.fromAxisAngle(axis, swingL), math.min(1, run))
		T.RightHip = T.RightHip:Lerp(CFrame.fromAxisAngle(axis, swingR), math.min(1, run))
		T.LeftKnee = ang(kneeL, 0, 0)
		T.RightKnee = ang(kneeR, 0, 0)
		-- arms counter-swing, kept tighter in combat stance
		local armAmp = 0.45 * math.min(run, 1)
		T.LeftShoulder = T.LeftShoulder * CFrame.fromAxisAngle(axis, -swingL * armAmp / amp)
		T.RightShoulder = T.RightShoulder * CFrame.fromAxisAngle(axis, -swingR * armAmp / amp)
		-- lean into motion, bob on footfalls
		local fwd = -localVel.Z / math.max(speed, 1)
		local side = localVel.X / math.max(speed, 1)
		rootRot = ang(-0.1 * fwd * run, 0, -0.08 * side * run)
		T.Waist = T.Waist * ang(0, sin(ph) * 0.12 * run, 0)
		rootOff += Vector3.new(0, abs(sin(ph)) * 0.18 * run - 0.08 * run, 0)
		-- foot plants
		local stepIdx = math.floor(ph / math.pi)
		if stepIdx ~= st.lastStep then
			st.lastStep = stepIdx
			if Audio and grounded and speed > 6 then
				local cam = workspace.CurrentCamera
				local d = (root.Position - cam.CFrame.Position).Magnitude
				if model == player.Character or d < 40 then
					Audio.play("step", root.Position - Vector3.new(0, 3, 0), model == player.Character and 0.9 or 0.6)
				end
			end
		end
	end

	-- 3. air -----------------------------------------------------------------------------------------
	if not grounded and not dead then
		st.airTime += dt
		if vy > 2 then
			T.LeftHip = ang(0.7, 0, -0.1)
			T.RightHip = ang(0.2, 0, 0.1)
			T.LeftKnee = ang(-1.2, 0, 0)
			T.RightKnee = ang(-0.5, 0, 0)
			T.LeftShoulder = T.LeftShoulder * ang(0.3, 0, -0.5)
			T.RightShoulder = T.RightShoulder * ang(0.3, 0, 0.5)
		else
			local f = clamp(-vy / 40, 0, 1)
			T.LeftHip = ang(0.35 - 0.2 * f, 0, -0.15)
			T.RightHip = ang(-0.1, 0, 0.15)
			T.LeftKnee = ang(-0.6, 0, 0)
			T.RightKnee = ang(-0.25, 0, 0)
			T.LeftShoulder = T.LeftShoulder * ang(0.5 * f, 0, -0.7 * f)
			T.RightShoulder = T.RightShoulder * ang(0.5 * f, 0, 0.7 * f)
		end
	else
		st.airTime = 0
	end
	-- landing squash
	if st.landT < 0.3 then
		local k = (1 - st.landT / 0.3) * st.landAmt
		rootOff += Vector3.new(0, -0.7 * k, 0)
		T.LeftKnee = T.LeftKnee * ang(-0.9 * k, 0, 0)
		T.RightKnee = T.RightKnee * ang(-0.9 * k, 0, 0)
		T.LeftHip = T.LeftHip * ang(0.6 * k, 0, 0)
		T.RightHip = T.RightHip * ang(0.6 * k, 0, 0)
		T.Waist = T.Waist * ang(0.25 * k, 0, 0)
	end

	-- 4. guard ---------------------------------------------------------------------------------------
	if guarding and not dead then
		T.RightShoulder = ang(1.35, 0, -0.55)
		T.LeftShoulder = ang(1.35, 0, 0.55)
		T.RightElbow = ang(1.7, 0, 0)
		T.LeftElbow = ang(1.7, 0, 0)
		T.Waist = T.Waist * ang(0.15, 0, 0)
		T.Neck = T.Neck * ang(0.12, 0, 0)
		rootOff += Vector3.new(0, -0.25, 0)
	end

	-- 5. casting -------------------------------------------------------------------------------------
	local castW = 0
	local pitch = aimPitch(st)
	local function reachArm(which, extend, k)
		-- point the arm at its shared emission point (reach), blended by k
		local upper = model:FindFirstChild("UpperTorso")
		local shoulder = model:FindFirstChild(which == "left" and "LeftUpperArm" or "RightUpperArm")
		if not upper or not shoulder then
			return
		end
		local look = rcf.LookVector
		local target = Poses.handWorld(root.Position, look, which) + Vector3.new(0, math.sin(pitch) * 1.4, 0)
		local sPos = upper.CFrame * Vector3.new(which == "left" and -1 or 1, 0.55, 0)
		local dirW = target - sPos
		local localDir = upper.CFrame:VectorToObjectSpace(dirW)
		local aimCF = armToward(localDir)
		local mot = which == "left" and "LeftShoulder" or "RightShoulder"
		local elb = which == "left" and "LeftElbow" or "RightElbow"
		T[mot] = T[mot]:Lerp(aimCF, k)
		T[elb] = T[elb]:Lerp(ang(0.15 * (1 - extend) + 0.05, 0, 0), k)
		T[which == "left" and "LeftWrist" or "RightWrist"] = ang(-0.3 * k, 0, 0)
	end
	if not dead and casting ~= "" and casting ~= nil then
		local side = hand == "left" and -1 or 1
		if casting == "windup" then
			local w = math.max(0.05, castEnd - castStart)
			local k = clamp((serverNow - castStart) / w, 0, 1)
			castW = 1
			if isUlt then
				-- buildup: arms spread and rise, body lifts and arches
				local e = easeOut(k)
				T.RightShoulder = ang(0.6 + 0.9 * e, 0, 1.0 + 0.3 * e)
				T.LeftShoulder = ang(0.6 + 0.9 * e, 0, -1.0 - 0.3 * e)
				T.RightElbow = ang(0.3, 0, 0)
				T.LeftElbow = ang(0.3, 0, 0)
				T.Waist = ang(-0.25 * e, 0, 0)
				T.Neck = ang(-0.3 * e, 0, 0)
				rootOff += Vector3.new(0, 0.35 * e + sin(now * 18) * 0.04 * e, 0)
			elseif hand == "both" then
				-- gather both hands at the hip, body coils
				T.RightShoulder = ang(-0.2 - 0.3 * k, 0, 0.35)
				T.LeftShoulder = ang(-0.2 - 0.3 * k, 0, -0.35)
				T.RightElbow = ang(1.6, 0, 0)
				T.LeftElbow = ang(1.6, 0, 0)
				T.Waist = T.Waist * ang(0.15 * k, 0.5 * k, 0)
				rootOff += Vector3.new(0, -0.3 * k, 0)
			else
				-- draw the casting hand back, twist the torso away (anticipation)
				local mot = side > 0 and "RightShoulder" or "LeftShoulder"
				local elb = side > 0 and "RightElbow" or "LeftElbow"
				T[mot] = ang(-0.5 * k, 0, 0.7 * side * k) * ang(0.2, 0, 0)
				T[elb] = ang(1.5, 0, 0)
				T.Waist = T.Waist * ang(0.05, 0.45 * side * k, 0)
				T.Neck = T.Neck * ang(0, -0.3 * side * k, 0)
				rootOff += Vector3.new(0, -0.2 * k, 0)
			end
		elseif casting == "active" then
			local t = serverNow - castActive
			castW = 1
			local hold = isUlt and 0.6 or 0.28
			local k = t < hold and 1 or clamp(1 - (t - hold) / 0.6, 0.35, 1)
			if hand == "both" or isUlt then
				reachArm("right", 1, k)
				reachArm("left", 1, k)
				T.Waist = T.Waist * ang(-0.1 * k + pitch * 0.4, 0, 0)
			else
				reachArm(hand, 1, k)
				-- torso snaps through toward the hand (release), off hand pulls back
				T.Waist = T.Waist * ang(pitch * 0.4, -0.35 * side * k, 0)
				local off = side > 0 and "LeftShoulder" or "RightShoulder"
				T[off] = T[off] * ang(-0.3 * k, 0, -0.3 * side * k)
			end
			rootOff += Vector3.new(0, -0.15 * k, 0)
		elseif casting == "recovery" then
			local left = recoverEnd - serverNow
			local k = clamp(left / 0.35, 0, 1)
			if k > 0 then
				castW = k
				if hand == "both" then
					reachArm("right", 0.6, 0.5 * k)
					reachArm("left", 0.6, 0.5 * k)
				else
					reachArm(hand, 0.5, 0.6 * k)
				end
			end
		end
	end
	-- recast re-thrust
	local recastAt = m:GetAttribute("RecastAt") or 0
	if not dead and serverNow - recastAt < 0.3 then
		local k = 1 - (serverNow - recastAt) / 0.3
		local slot = m:GetAttribute("RecastSlot") or 1
		local rh = Poses.handFor(slot)
		if rh == "both" then
			reachArm("right", 1, k)
			reachArm("left", 1, k)
		else
			reachArm(rh, 1, k)
		end
	end
	-- basic attacks: alternating jabs
	if not dead and castW < 0.5 and serverNow - basicAt < 0.32 then
		if basicAt ~= st.lastBasic then
			st.lastBasic = basicAt
			st.basicN += 1
		end
		local t = serverNow - basicAt
		local k = t < 0.1 and t / 0.1 or clamp(1 - (t - 0.1) / 0.22, 0, 1)
		local which = st.basicN % 2 == 0 and "left" or "right"
		reachArm(which, 1, k)
		T.Waist = T.Waist * ang(0.05, (which == "right" and -0.4 or 0.4) * k, 0)
	end

	-- 6. dash ----------------------------------------------------------------------------------------
	local dt0 = serverNow - dashAt
	if not dead and dt0 < dashDur + 0.1 then
		local k = clamp(1 - dt0 / (dashDur + 0.1), 0, 1)
		local dirL = localVel.Magnitude > 1 and localVel.Unit or Vector3.new(0, 0, -1)
		local axis = dirL:Cross(Vector3.yAxis)
		if axis.Magnitude > 1e-3 then
			rootRot = rootRot * CFrame.fromAxisAngle(axis.Unit, -0.55 * k)
		end
		T.LeftShoulder = T.LeftShoulder * ang(-0.8 * k, 0, -0.3 * k)
		T.RightShoulder = T.RightShoulder * ang(-0.8 * k, 0, 0.3 * k)
		T.LeftKnee = T.LeftKnee * ang(-0.6 * k, 0, 0)
		T.RightKnee = T.RightKnee * ang(-0.9 * k, 0, 0)
		rootOff += Vector3.new(0, -0.45 * k, 0)
	end

	-- 7. flinch spring -------------------------------------------------------------------------------
	local fl = st.flinch
	local fv = st.flinchV
	fv += (-fl * 220 - fv * 18) * dt
	fl += fv * dt
	st.flinch, st.flinchV = fl, fv
	if fl.Magnitude > 1e-3 then
		local axisLocal = rcf:VectorToObjectSpace(fl)
		local a = math.min(fl.Magnitude, 0.9)
		T.Waist = T.Waist * CFrame.fromAxisAngle(axisLocal.Unit, a * 0.8)
		T.Neck = T.Neck * CFrame.fromAxisAngle(axisLocal.Unit, a * 0.5)
	end

	-- 8. death / spawn -------------------------------------------------------------------------------
	if dead then
		local diedAt = m:GetAttribute("DiedAt") or serverNow
		local t = serverNow - diedAt
		local buckle = clamp(t / 0.25, 0, 1)
		local fall = clamp((t - 0.15) / 0.55, 0, 1)
		fall = fall * fall
		T.LeftKnee = ang(-1.4 * buckle, 0, 0)
		T.RightKnee = ang(-1.1 * buckle, 0, 0)
		T.LeftHip = ang(0.9 * buckle, 0, -0.2)
		T.RightHip = ang(0.6 * buckle, 0, 0.2)
		T.Neck = ang(0.4 * buckle, 0.3, 0)
		T.RightShoulder = ang(0.2, 0, 0.9 * fall)
		T.LeftShoulder = ang(0.1, 0, -0.9 * fall)
		T.RightElbow = ang(0.3, 0, 0)
		T.LeftElbow = ang(0.4, 0, 0)
		rootRot = ang(1.45 * fall, 0, 0.2 * fall)
		rootOff = Vector3.new(0, -1.1 * buckle - 1.2 * fall, 0.4 * fall)
	end
	local sinceSpawn = serverNow - spawnedAt
	if not dead and sinceSpawn < 0.6 then
		local k = 1 - clamp(sinceSpawn / 0.6, 0, 1)
		k = k * k
		rootOff += Vector3.new(0, -1.2 * k, 0)
		T.LeftKnee = T.LeftKnee * ang(-1.4 * k, 0, 0)
		T.RightKnee = T.RightKnee * ang(-1.4 * k, 0, 0)
		T.LeftHip = T.LeftHip * ang(1.0 * k, 0, 0)
		T.RightHip = T.RightHip * ang(1.0 * k, 0, 0)
		T.Waist = T.Waist * ang(0.5 * k, 0, 0)
	end

	-- head follows aim pitch (players read where others look)
	if not dead then
		T.Neck = T.Neck * ang(clamp(pitch, -0.9, 0.7) * 0.6, 0, 0)
		T.Waist = T.Waist * ang(clamp(pitch, -0.9, 0.7) * 0.25, 0, 0)
	end
	T.Root = CFrame.new(rootOff) * rootRot

	-- apply with smoothing (casts snap faster so releases read crisply)
	local rate = castW > 0.5 and 26 or 14
	if dead then
		rate = 10
	end
	local alpha = 1 - exp(-dt * rate)
	for name, motor in pairs(st.motors) do
		local target = T[name] or ID
		local cur = st.cur[name]:Lerp(target, alpha)
		st.cur[name] = cur
		motor.Transform = cur
	end
end

local function track(model)
	task.defer(function()
		if model.Parent and model:FindFirstChildOfClass("Humanoid") then
			-- stock animation scripts would fight the procedural poses
			local a = model:FindFirstChild("Animate")
			if a then
				a:Destroy()
			end
			setup(model)
		end
	end)
end

function Anim.count()
	local n = 0
	for _ in pairs(rigs) do
		n += 1
	end
	return n
end

function Anim.init(c)
	ctx = c
	Audio = c.Audio
	for _, m in ipairs(CollectionService:GetTagged("EBFighter")) do
		track(m)
	end
	CollectionService:GetInstanceAddedSignal("EBFighter"):Connect(track)
	local frame = 0
	RunService.Stepped:Connect(function(_, dt)
		frame += 1
		local now = os.clock()
		local serverNow = workspace:GetServerTimeNow()
		local camPos = workspace.CurrentCamera.CFrame.Position
		for model, st in pairs(rigs) do
			if not model.Parent or not st.root.Parent then
				rigs[model] = nil
			else
				-- distance LOD: far rigs update every third frame
				local d = (st.root.Position - camPos).Magnitude
				if d < 160 or (frame + st.lod) % 3 == 0 then
					local ok, err = pcall(step, st, d < 160 and dt or dt * 3, now, serverNow)
					if not ok then
						warn("[EB anim] " .. tostring(err))
						rigs[model] = nil
					end
				end
			end
		end
	end)
end

return Anim
