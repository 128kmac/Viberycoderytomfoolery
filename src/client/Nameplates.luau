-- Overhead plates drawn per viewer. Friend / foe are distinguished by shape AND colour:
--   enemies  : ✕ glyph, red frame with notched (segmented) health bar
--   allies   : ◆ glyph, blue frame, smooth bar
--   you      : no plate (HUD shows your state)
--   dummies  : ▣ glyph, neutral frame;  summons: smaller plate with the owner's relation
-- Plates also flag enemy ultimates in progress and hide while a fighter is concealed or defeated.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Plates = {}
local ctx, T
local player = Players.LocalPlayer
local plates = {} -- model -> refs

local ENEMY = Color3.fromRGB(255, 90, 80)
local ALLY = Color3.fromRGB(100, 200, 255)
local NEUTRAL = Color3.fromRGB(200, 190, 160)

local function build(model)
	if plates[model] then
		return
	end
	local head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not head then
		return
	end
	local summon = model:GetAttribute("IsSummon") == true
	local bb = Instance.new("BillboardGui")
	bb.Name = "EBPlate"
	bb.Size = UDim2.fromOffset(summon and 110 or 160, summon and 30 or 46)
	bb.StudsOffset = Vector3.new(0, summon and 2.2 or 2.6, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 140
	bb.LightInfluence = 0
	bb.ResetOnSpawn = false
	bb.Adornee = head
	local name = T.new("TextLabel", {
		Name = "Name",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, summon and 12 or 16),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.35,
		Text = "",
		Parent = bb,
	})
	local back = T.new("Frame", {
		Name = "Bar",
		Position = UDim2.fromOffset(0, summon and 14 or 18),
		Size = UDim2.new(1, 0, 0, summon and 6 or 8),
		BackgroundColor3 = Color3.fromRGB(20, 20, 26),
		BackgroundTransparency = 0.15,
		Parent = bb,
	})
	local stroke = T.stroke(back, NEUTRAL, 1.5, 0)
	local fill = T.new("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = NEUTRAL, Parent = back })
	local shield = T.new("Frame", { Name = "Shield", Size = UDim2.fromScale(0, 0.45), BackgroundColor3 = Color3.fromRGB(150, 210, 255), Parent = back })
	-- notches every 10% (enemy bars only)
	local notches = {}
	for i = 1, 9 do
		notches[i] = T.new("Frame", {
			Position = UDim2.new(i / 10, -1, 0, 0),
			Size = UDim2.new(0, 2, 1, 0),
			BackgroundColor3 = Color3.fromRGB(20, 20, 26),
			ZIndex = 3,
			Parent = back,
		})
	end
	local status = T.new("TextLabel", {
		Name = "Status",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, summon and 20 or 28),
		Size = UDim2.new(1, 0, 0, summon and 10 or 16),
		Font = Enum.Font.GothamMedium,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 220, 160),
		TextStrokeTransparency = 0.4,
		Text = "",
		Parent = bb,
	})
	bb.Parent = player:WaitForChild("PlayerGui")
	plates[model] = { bb = bb, name = name, fill = fill, shield = shield, stroke = stroke, notches = notches, status = status, summon = summon }
end

local function relationOf(model)
	if model == player.Character then
		return "self"
	end
	if model:GetAttribute("IsDummy") then
		return "dummy"
	end
	local id = model:GetAttribute("FighterId")
	return ctx.VFX.relation(id)
end

local function update()
	local t = workspace:GetServerTimeNow()
	for model, r in pairs(plates) do
		if not model.Parent then
			r.bb:Destroy()
			plates[model] = nil
		else
			local rel = relationOf(model)
			local show = rel ~= "self" and not model:GetAttribute("Dead") and not model:GetAttribute("Concealed")
			r.bb.Enabled = show
			if show then
				local col = rel == "ally" and ALLY or (rel == "dummy" and NEUTRAL or ENEMY)
				local glyph = rel == "ally" and "◆ " or (rel == "dummy" and "▣ " or "✕ ")
				local kit = model:GetAttribute("Kit")
				local nm = model:GetAttribute("DisplayName") or model.Name
				local kitTxt = ""
				if kit and kit ~= "" and rel ~= "dummy" and not r.summon then
					local kc = ctx.Util.color(kit)
					kitTxt = string.format('  <font color="#%02X%02X%02X">%s</font>', math.floor(kc.R * 255), math.floor(kc.G * 255), math.floor(kc.B * 255), kit)
				end
				r.name.RichText = true
				r.name.Text = glyph .. nm .. kitTxt
				r.name.TextColor3 = rel == "ally" and Color3.fromRGB(200, 235, 255) or Color3.new(1, 1, 1)
				local hp = model:GetAttribute("Health") or 0
				local max = model:GetAttribute("MaxHealth") or 1000
				local frac = math.clamp(hp / math.max(1, max), 0, 1)
				r.fill.Size = UDim2.fromScale(frac, 1)
				r.fill.BackgroundColor3 = col:Lerp(Color3.new(1, 1, 1), 0.1)
				r.stroke.Color = col
				local sh = model:GetAttribute("Shield") or 0
				r.shield.Size = UDim2.fromScale(math.clamp(sh / math.max(1, max), 0, 1), 0.45)
				for _, n in ipairs(r.notches) do
					n.Visible = rel == "enemy" or rel == "neutral"
				end
				local st = model:GetAttribute("Statuses") or ""
				local casting = model:GetAttribute("Casting") or 0
				if casting == 5 and rel ~= "ally" then
					st = "⚠ ULTIMATE" .. (st ~= "" and ("  " .. st) or "")
					r.status.TextColor3 = Color3.fromRGB(255, 120, 80)
				elseif model:GetAttribute("Guarding") then
					st = "GUARD" .. (st ~= "" and ("  " .. st) or "")
					r.status.TextColor3 = Color3.fromRGB(170, 200, 255)
				else
					r.status.TextColor3 = Color3.fromRGB(255, 220, 160)
				end
				if (model:GetAttribute("SpawnProtected") or 0) > t then
					st = "PROTECTED" .. (st ~= "" and ("  " .. st) or "")
				end
				r.status.Text = st
			end
		end
	end
end

function Plates.init(c)
	ctx = c
	T = c.Theme
	for _, m in ipairs(CollectionService:GetTagged("EBFighter")) do
		build(m)
	end
	CollectionService:GetInstanceAddedSignal("EBFighter"):Connect(function(m)
		task.defer(build, m)
	end)
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			update()
		end
	end)
end

return Plates
