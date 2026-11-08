-- Input, over-the-shoulder aiming camera, aim replication and touch/gamepad bindings.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local Controls = {}

local ctx
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

Controls.locked = true
Controls.menuOpen = false
Controls.modifier = false

local KEY_SLOTS = {
	[Enum.KeyCode.Q] = 1,
	[Enum.KeyCode.E] = 2,
	[Enum.KeyCode.R] = 3,
	[Enum.KeyCode.F] = 4,
	[Enum.KeyCode.G] = 5,
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.ButtonX] = 1,
	[Enum.KeyCode.ButtonY] = 2,
	[Enum.KeyCode.ButtonB] = 3,
	[Enum.KeyCode.DPadUp] = 4,
	[Enum.KeyCode.ButtonR1] = 5,
}
Controls.KEY_LABELS = { "Q", "E", "R", "F", "G" }

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude

local lastAim = { hit = Vector3.zero, dir = Vector3.new(0, 0, -1), origin = Vector3.zero }
Controls.aim = lastAim

local function character()
	return player.Character
end

local function computeAim()
	local ch = character()
	local ignore = { workspace:FindFirstChild("FX"), workspace:FindFirstChild("Props") }
	if ch then
		table.insert(ignore, ch)
	end
	aimParams.FilterDescendantsInstances = ignore
	local ray
	local vp = camera.ViewportSize
	if Controls.locked or UserInputService.TouchEnabled then
		ray = camera:ViewportPointToRay(vp.X / 2, vp.Y / 2)
	else
		local m = UserInputService:GetMouseLocation()
		ray = camera:ViewportPointToRay(m.X, m.Y)
	end
	local res = workspace:Raycast(ray.Origin, ray.Direction * 600, aimParams)
	local hit = res and res.Position or (ray.Origin + ray.Direction * 300)
	local target
	if res and res.Instance then
		local m = res.Instance:FindFirstAncestorWhichIsA("Model")
		while m and m ~= workspace do
			if m:GetAttribute("FighterId") then
				target = m
				break
			end
			m = m.Parent and m.Parent:FindFirstAncestorWhichIsA("Model")
		end
	end
	lastAim.origin = ray.Origin
	lastAim.dir = ray.Direction.Unit
	lastAim.hit = hit
	lastAim.target = target
	return lastAim
end

local function sendAim()
	local a = computeAim()
	ctx.remotes.Aim:FireServer(a.origin, a.dir, a.hit, a.target)
end
Controls.sendAim = sendAim

local function input(action, ...)
	ctx.remotes.Input:FireServer(action, ...)
end
Controls.input = input

function Controls.cast(slot, down)
	if Controls.menuOpen then
		return
	end
	if down then
		sendAim()
	end
	input("cast", slot, down, Controls.modifier)
end

local basicHeld = false
function Controls.basic(down)
	basicHeld = down
	if down and not Controls.menuOpen then
		sendAim()
		input("basic")
	end
end

function Controls.guard(down)
	if Controls.menuOpen and down then
		return
	end
	input("guard", down)
end

function Controls.dodge()
	if Controls.menuOpen then
		return
	end
	local ch = character()
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local dir = hum and hum.MoveDirection or Vector3.zero
	if dir.Magnitude < 0.1 then
		local lv = camera.CFrame.LookVector
		dir = Vector3.new(lv.X, 0, lv.Z)
	end
	input("dodge", dir.Magnitude > 0 and dir.Unit or nil)
end

function Controls.kitAction()
	if not Controls.menuOpen then
		sendAim()
		input("kit")
	end
end

function Controls.setLocked(on)
	Controls.locked = on
	if not on then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	local ch = character()
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.AutoRotate = not on
	end
	if ctx.HUD and ctx.HUD.setCrosshair then
		ctx.HUD.setCrosshair(on)
	end
end

function Controls.setMenuOpen(open)
	Controls.menuOpen = open
	if open then
		Controls.wasLocked = Controls.locked
		Controls.setLocked(false)
	elseif Controls.wasLocked ~= nil then
		Controls.setLocked(Controls.wasLocked and not UserInputService.TouchEnabled)
	end
end

function Controls.init(c)
	ctx = c
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		Controls.locked = false
	end
	UserInputService.InputBegan:Connect(function(io, processed)
		if io.KeyCode == Enum.KeyCode.Tab or (io.KeyCode == Enum.KeyCode.M and not processed) or io.KeyCode == Enum.KeyCode.ButtonSelect then
			ctx.KitMenu.toggle()
			return
		end
		if (io.KeyCode == Enum.KeyCode.P and not processed) or io.KeyCode == Enum.KeyCode.ButtonStart then
			if ctx.MatchUI then
				ctx.MatchUI.togglePanel()
			end
			return
		end
		if io.UserInputType == Enum.UserInputType.Touch and not processed then
			local vp = camera.ViewportSize
			if io.Position.X > vp.X * 0.4 then
				Controls.cameraTouch = io
			end
		end
		if processed then
			return
		end
		if io.UserInputType == Enum.UserInputType.MouseButton1 then
			Controls.basic(true)
			return
		elseif io.UserInputType == Enum.UserInputType.MouseButton2 then
			Controls.guard(true)
			return
		end
		local kc = io.KeyCode
		if kc == Enum.KeyCode.LeftControl or kc == Enum.KeyCode.RightControl or kc == Enum.KeyCode.ButtonL3 then
			Controls.modifier = true
			return
		end
		if kc == Enum.KeyCode.LeftShift or kc == Enum.KeyCode.ButtonL1 then
			Controls.dodge()
			return
		end
		if kc == Enum.KeyCode.ButtonL2 then
			Controls.guard(true)
			return
		end
		if kc == Enum.KeyCode.ButtonR2 then
			Controls.basic(true)
			return
		end
		if kc == Enum.KeyCode.V or kc == Enum.KeyCode.ButtonR3 then
			Controls.kitAction()
			return
		end
		if kc == Enum.KeyCode.Z or kc == Enum.KeyCode.LeftAlt then
			if not Controls.menuOpen then
				Controls.setLocked(not Controls.locked)
			end
			return
		end
		if kc == Enum.KeyCode.C and ctx.Camera then
			ctx.Camera.shoulder = -ctx.Camera.shoulder
			return
		end
		local slot = KEY_SLOTS[kc]
		if slot then
			Controls.cast(slot, true)
		end
	end)
	UserInputService.InputEnded:Connect(function(io)
		if io == Controls.cameraTouch then
			Controls.cameraTouch = nil
		end
		if io.UserInputType == Enum.UserInputType.MouseButton1 then
			Controls.basic(false)
			return
		elseif io.UserInputType == Enum.UserInputType.MouseButton2 then
			Controls.guard(false)
			return
		end
		local kc = io.KeyCode
		if kc == Enum.KeyCode.LeftControl or kc == Enum.KeyCode.RightControl or kc == Enum.KeyCode.ButtonL3 then
			Controls.modifier = false
			return
		end
		if kc == Enum.KeyCode.ButtonL2 then
			Controls.guard(false)
			return
		end
		if kc == Enum.KeyCode.ButtonR2 then
			Controls.basic(false)
			return
		end
		local slot = KEY_SLOTS[kc]
		if slot then
			ctx.remotes.Input:FireServer("cast", slot, false, Controls.modifier)
		end
	end)

	-- touch buttons
	if UserInputService.TouchEnabled then
		local function bind(name, label, pos, fn)
			ContextActionService:BindAction(name, function(_, state)
				if state == Enum.UserInputState.Begin then
					fn(true)
				elseif state == Enum.UserInputState.End then
					fn(false)
				end
				return Enum.ContextActionResult.Sink
			end, true)
			ContextActionService:SetTitle(name, label)
			ContextActionService:SetPosition(name, pos)
		end
		bind("EBBasic", "Hit", UDim2.new(1, -170, 1, -90), Controls.basic)
		bind("EBGuard", "Guard", UDim2.new(1, -250, 1, -60), Controls.guard)
		bind("EBDodge", "Dodge", UDim2.new(1, -90, 1, -170), function(d)
			if d then
				Controls.dodge()
			end
		end)
		for slot = 1, 5 do
			bind("EBMove" .. slot, slot == 5 and "ULT" or tostring(slot), UDim2.new(1, -330 + slot * 62, 1, -250), function(d)
				Controls.cast(slot, d)
			end)
		end
		bind("EBKit", "Kit", UDim2.new(1, -90, 1, -250), function(d)
			if d then
				Controls.kitAction()
			end
		end)
		bind("EBMod", "Mod", UDim2.new(1, -330, 1, -170), function(d)
			Controls.modifier = d
		end)
	end

	-- camera lock + aim stream
	local aimTimer = 0
	local basicTimer = 0
	RunService.RenderStepped:Connect(function(dt)
		local ch = character()
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if Controls.locked and not Controls.menuOpen and hum and root and hum.Health > 0 and not (ch and ch:GetAttribute("Dead")) then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			hum.AutoRotate = false
			local lv = camera.CFrame.LookVector
			local flat = Vector3.new(lv.X, 0, lv.Z)
			if flat.Magnitude > 0.01 then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
			end
		elseif hum and not Controls.locked then
			hum.AutoRotate = true
		end
		aimTimer += dt
		if aimTimer >= 1 / 15 then
			aimTimer = 0
			if ch then
				sendAim()
			end
		end
		if basicHeld and not Controls.menuOpen then
			basicTimer += dt
			if basicTimer > 0.2 then
				basicTimer = 0
				input("basic")
			end
		end
	end)

	player.CharacterAdded:Connect(function()
		task.wait(0.2)
		Controls.setLocked(Controls.locked and not Controls.menuOpen)
	end)
end

return Controls
