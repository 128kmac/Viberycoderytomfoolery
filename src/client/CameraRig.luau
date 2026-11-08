-- Over-the-shoulder combat camera (Scriptable): mouse / touch / gamepad orbit, right-shoulder offset,
-- collision against the arena (no clipping through walls), zoom, shoulder swap, death cam, and feedback
-- channels (trauma shake, kicks, FOV pulses) that respect reduced-motion and shake settings.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Cam = {}
local ctx, Settings
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

Cam.yaw = 0
Cam.pitch = math.rad(-12)
Cam.distance = 12
Cam.shoulder = 1
Cam.enabled = true

local trauma = 0
local kickT, kickAmt = 0, 0
local fovPulses = {}
local punch = 0
local smoothedFocus
local currentDist = 12
local collisionParams = RaycastParams.new()
collisionParams.FilterType = Enum.RaycastFilterType.Include

local MIN_PITCH, MAX_PITCH = math.rad(-70), math.rad(55)
local rng = Random.new()

function Cam.impulse(amount)
	local s = Settings.shake()
	if s <= 0 then
		return
	end
	trauma = math.min(1, trauma + amount * s)
end

-- small recoil kick (pitch up) on releases
function Cam.kick(amount)
	if Settings.get("ReducedMotion") then
		return
	end
	kickT = 0
	kickAmt = amount
end

-- short zoom punch (perfect guard, big hits)
function Cam.punch(amount)
	if Settings.get("ReducedMotion") then
		return
	end
	punch = math.max(punch, amount)
end

-- FOV pulse: delta degrees eased in/out over dur
function Cam.fov(delta, dur)
	if Settings.get("ReducedMotion") then
		return
	end
	table.insert(fovPulses, { d = delta, dur = dur, t = 0 })
end

local function character()
	return player.Character
end

local function rootOf(ch)
	return ch and ch:FindFirstChild("HumanoidRootPart")
end

function Cam.look()
	return CFrame.fromEulerAnglesYXZ(Cam.pitch, Cam.yaw, 0)
end

-- align the camera behind the character (on spawn)
function Cam.snapBehind()
	local root = rootOf(character())
	if root then
		local lv = root.CFrame.LookVector
		Cam.yaw = math.atan2(-lv.X, -lv.Z)
		Cam.pitch = math.rad(-10)
		smoothedFocus = nil
	end
end

local function rotate(dx, dy)
	local sens = Settings.get("Sensitivity")
	Cam.yaw -= dx * 0.0042 * sens
	Cam.pitch = math.clamp(Cam.pitch - dy * 0.0036 * sens, MIN_PITCH, MAX_PITCH)
end

local function step(dt)
	if not Cam.enabled then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local ch = character()
	local root = rootOf(ch)
	local Controls = ctx.Controls
	-- input: mouse delta when locked; gamepad right stick
	if Controls and Controls.locked and not Controls.menuOpen then
		local d = UserInputService:GetMouseDelta()
		rotate(d.X, d.Y)
	end
	if Cam.stick then
		rotate(Cam.stick.X * 900 * dt, -Cam.stick.Y * 700 * dt)
	end
	local dead = ch and ch:GetAttribute("Dead")
	local focus
	if root then
		focus = root.Position + Vector3.new(0, 1.9, 0)
	else
		focus = smoothedFocus or Vector3.new(0, 10, 0)
	end
	if dead then
		-- death cam: slow orbit, pulled back and up
		Cam.yaw += dt * 0.35
		Cam.pitch = Cam.pitch + (math.rad(-28) - Cam.pitch) * math.min(1, dt * 2)
	end
	if not smoothedFocus then
		smoothedFocus = focus
	end
	-- follow tightly horizontally, softly vertically (keeps jumps readable)
	local k = math.min(1, dt * 22)
	local ky = math.min(1, dt * 10)
	smoothedFocus = Vector3.new(
		smoothedFocus.X + (focus.X - smoothedFocus.X) * k,
		smoothedFocus.Y + (focus.Y - smoothedFocus.Y) * ky,
		smoothedFocus.Z + (focus.Z - smoothedFocus.Z) * k
	)
	local look = Cam.look()
	local wantDist = dead and 18 or Cam.distance
	local shoulder = dead and 0 or 2.1 * Cam.shoulder
	local pivot = smoothedFocus + look.RightVector * shoulder + Vector3.new(0, dead and 1 or 0.4, 0)
	local back = -look.LookVector
	-- collision: spherecast from the focus to the desired camera spot
	local desired = pivot + back * wantDist
	local res = workspace:Spherecast(smoothedFocus, 0.7, desired - smoothedFocus, collisionParams)
	local dist = wantDist
	if res then
		dist = math.max(1.2, (res.Position - smoothedFocus):Dot(back) - 0.4)
	end
	-- pull in fast, ease out slowly
	if dist < currentDist then
		currentDist = dist
	else
		currentDist += (dist - currentDist) * math.min(1, dt * 4)
	end
	local camPos = pivot + back * math.min(currentDist, wantDist)
	if res and currentDist < wantDist then
		camPos = smoothedFocus + (camPos - smoothedFocus).Unit * math.max(1, currentDist)
	end
	-- feedback
	trauma = math.max(0, trauma - dt * 1.6)
	local shake = trauma * trauma
	local t = os.clock()
	local shakeCF = CFrame.Angles(
		math.noise(t * 18, 1.3) * 0.045 * shake,
		math.noise(t * 18, 7.1) * 0.045 * shake,
		math.noise(t * 18, 3.7) * 0.03 * shake
	)
	kickT += dt
	local kick = kickAmt * math.max(0, 1 - kickT / 0.18) * math.sin(math.min(1, kickT / 0.18) * math.pi)
	local fov = Settings.get("FieldOfView")
	for i = #fovPulses, 1, -1 do
		local p = fovPulses[i]
		p.t += dt
		local a = p.t / p.dur
		if a >= 1 then
			table.remove(fovPulses, i)
		else
			fov += p.d * math.sin(a * math.pi)
		end
	end
	punch = math.max(0, punch - dt * 4)
	fov -= punch * 6
	camera.FieldOfView = math.clamp(fov, 40, 100)
	camera.CFrame = CFrame.lookAt(camPos, camPos + look.LookVector) * CFrame.Angles(kick * 0.08, 0, 0) * shakeCF
	camera.Focus = CFrame.new(smoothedFocus)
	local _ = rng
end

function Cam.init(c)
	ctx = c
	Settings = c.Settings
	collisionParams.FilterDescendantsInstances = { workspace:WaitForChild("Arena"), workspace:WaitForChild("Constructs") }
	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.InputChanged:Connect(function(io, processed)
		if io.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			Cam.distance = math.clamp(Cam.distance - io.Position.Z * 1.5, 6, 18)
		elseif io.UserInputType == Enum.UserInputType.Touch and not processed and ctx.Controls and ctx.Controls.cameraTouch == io then
			rotate(io.Delta.X * 1.6, io.Delta.Y * 1.6)
		elseif io.KeyCode == Enum.KeyCode.Thumbstick2 then
			local v = io.Position
			Cam.stick = Vector2.new(math.abs(v.X) > 0.15 and v.X or 0, math.abs(v.Y) > 0.15 and v.Y or 0)
		end
	end)
	player.CharacterAdded:Connect(function()
		task.wait()
		Cam.snapBehind()
	end)
	RunService:BindToRenderStep("EBCamera", Enum.RenderPriority.Camera.Value + 1, step)
end

return Cam
