-- Floating combat numbers and status words (client-local, never block tactical information).
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Popups = {}

local folder

function Popups.show(pos, text, color, kind)
	if typeof(pos) ~= "Vector3" then
		return
	end
	local cam = workspace.CurrentCamera
	if (cam.CFrame.Position - pos).Magnitude > 140 then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(pos + Vector3.new(math.random(-15, 15) / 10, 2.5, math.random(-15, 15) / 10))
	anchor.Parent = folder
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, kind == "info" and 26 or 30)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = anchor
	bb.Parent = anchor
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextScaled = true
	lbl.Text = tostring(text)
	lbl.TextColor3 = typeof(color) == "Color3" and color or Color3.new(1, 1, 1)
	lbl.TextStrokeTransparency = 0.2
	lbl.Parent = bb
	if kind == "dot" or kind == "field" then
		bb.Size = UDim2.fromOffset(110, 20)
	end
	TweenService:Create(anchor, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = anchor.CFrame + Vector3.new(0, 3, 0),
	}):Play()
	task.delay(0.5, function()
		TweenService:Create(lbl, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	Debris:AddItem(anchor, 1)
end

function Popups.init(ctx)
	folder = Instance.new("Folder")
	folder.Name = "EBPopups"
	folder.Parent = workspace.CurrentCamera
	ctx.remotes.Pop.OnClientEvent:Connect(Popups.show)
end

return Popups
