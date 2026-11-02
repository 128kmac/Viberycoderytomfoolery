-- Heads-up display: health/shield, Energy, Guard, Heat, Proxima, dodge pips, ability bar with
-- cooldowns / recasts / P60 cues, statuses, kit resources, cast bar, crosshair, feed and notices.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local HUD = {}

local ctx, T
local player = Players.LocalPlayer
local slots = {}
local refs = {}

local function now()
	return workspace:GetServerTimeNow()
end

local function esc(s)
	return (string.gsub(string.gsub(string.gsub(s or "", "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

local function bar(parent, name, pos, size, color, labelText)
	local back = T.new("Frame", {
		Name = name,
		Position = pos,
		Size = size,
		BackgroundColor3 = Color3.fromRGB(12, 13, 18),
		BackgroundTransparency = 0.2,
		Parent = parent,
	})
	T.corner(back, 4)
	local fill = T.new("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, Parent = back })
	T.corner(fill, 4)
	local over = T.new("Frame", {
		Name = "Over",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = T.shield,
		BackgroundTransparency = 0.25,
		Parent = back,
	})
	T.corner(over, 4)
	local lbl = T.label({
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		Text = labelText or "",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		ZIndex = 3,
		Parent = back,
	})
	return { back = back, fill = fill, over = over, label = lbl }
end

local function marker(b, frac, color)
	T.new("Frame", {
		Position = UDim2.new(frac, -1, 0, -2),
		Size = UDim2.new(0, 2, 1, 4),
		BackgroundColor3 = color or Color3.new(1, 1, 1),
		ZIndex = 4,
		Parent = b.back,
	})
end

function HUD.setCrosshair(on)
	if refs.cross then
		refs.cross.Visible = on
	end
end

function HUD.notice(text)
	local n = refs.notice
	n.Text = text
	n.TextTransparency = 0
	n.TextStrokeTransparency = 0.3
	refs.noticeToken = (refs.noticeToken or 0) + 1
	local tok = refs.noticeToken
	task.delay(2.2, function()
		if refs.noticeToken == tok then
			TweenService:Create(n, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

function HUD.feed(text)
	local item = T.label({
		Size = UDim2.new(1, 0, 0, 20),
		Text = text,
		TextSize = 13,
		Font = Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.4,
		Parent = refs.feed,
	})
	task.delay(7, function()
		TweenService:Create(item, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.6)
		item:Destroy()
	end)
	local kids = {}
	for _, c in ipairs(refs.feed:GetChildren()) do
		if c:IsA("TextLabel") then
			table.insert(kids, c)
		end
	end
	if #kids > 6 then
		kids[1]:Destroy()
	end
end

local function buildSlot(parent, i)
	local f = T.new("Frame", {
		Name = "Slot" .. i,
		Size = UDim2.fromOffset(i == 5 and 84 or 72, 72),
		BackgroundColor3 = T.panel,
		BackgroundTransparency = 0.1,
		LayoutOrder = i,
		Parent = parent,
	})
	T.corner(f, 8)
	local stroke = T.stroke(f, Color3.new(1, 1, 1), 2, 0.7)
	local key = T.label({
		Name = "Key",
		Position = UDim2.fromOffset(5, 3),
		Size = UDim2.fromOffset(20, 16),
		Text = ctx.Controls.KEY_LABELS[i],
		Font = Enum.Font.GothamBlack,
		TextSize = 14,
		TextColor3 = T.accent,
		Parent = f,
	})
	local cost = T.label({
		Name = "Cost",
		Position = UDim2.new(1, -40, 0, 3),
		Size = UDim2.fromOffset(36, 16),
		Text = "",
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = T.energy,
		Font = Enum.Font.GothamBold,
		Parent = f,
	})
	local name = T.label({
		Name = "MoveName",
		Position = UDim2.fromOffset(4, 22),
		Size = UDim2.new(1, -8, 0, 34),
		Text = "",
		TextSize = 11,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = f,
	})
	local badge = T.label({
		Name = "Badge",
		Position = UDim2.new(0, 4, 1, -16),
		Size = UDim2.new(1, -8, 0, 14),
		Text = "",
		TextSize = 10,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(255, 235, 120),
		Parent = f,
	})
	local cd = T.new("Frame", {
		Name = "CD",
		Size = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		ZIndex = 5,
		Parent = f,
	})
	T.corner(cd, 8)
	local cdText = T.label({
		Name = "CDText",
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextSize = 22,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		ZIndex = 6,
		Parent = f,
	})
	local btn = T.new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 7, Parent = f })
	btn.MouseEnter:Connect(function()
		refs.tipSlot = i
	end)
	btn.MouseLeave:Connect(function()
		if refs.tipSlot == i then
			refs.tipSlot = nil
		end
	end)
	btn.Activated:Connect(function()
		ctx.Controls.cast(i, true)
		task.delay(0.05, function()
			ctx.remotes.Input:FireServer("cast", i, false, false)
		end)
	end)
	slots[i] = { frame = f, stroke = stroke, key = key, cost = cost, name = name, badge = badge, cd = cd, cdText = cdText }
end

function HUD.init(c)
	ctx = c
	T = c.Theme
	local gui = c.gui

	-- bottom cluster
	local bottom = T.new("Frame", {
		Name = "Bottom",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(460, 190),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	refs.bottom = bottom
	refs.kitName = T.label({
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 18),
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
		Parent = bottom,
	})
	refs.kitRes = T.label({
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 16),
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(255, 225, 160),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
		Parent = bottom,
	})
	refs.health = bar(bottom, "Health", UDim2.fromOffset(0, 38), UDim2.new(1, 0, 0, 18), T.health)
	refs.energy = bar(bottom, "Energy", UDim2.fromOffset(0, 60), UDim2.new(0.62, -4, 0, 12), T.energy)
	refs.guard = bar(bottom, "Guard", UDim2.new(0.62, 4, 0, 60), UDim2.new(0.38, -4, 0, 12), T.guard)
	local row = T.new("Frame", {
		Position = UDim2.fromOffset(0, 78),
		Size = UDim2.new(1, 0, 0, 76),
		BackgroundTransparency = 1,
		Parent = bottom,
	})
	T.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	for i = 1, 5 do
		buildSlot(row, i)
	end
	refs.status = T.label({
		Position = UDim2.fromOffset(0, 158),
		Size = UDim2.new(1, 0, 0, 16),
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(255, 200, 200),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
		Parent = bottom,
	})
	refs.help = T.label({
		Position = UDim2.fromOffset(-120, 174),
		Size = UDim2.new(1, 240, 0, 14),
		Text = "Q E R F moves · G ultimate (hold 1s at 60+ Heat = Unstable) · LMB basic · RMB guard · Shift dodge · Ctrl modifier · V kit action · Z camera · Tab/M powers",
		TextSize = 11,
		TextColor3 = T.dim,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.6,
		Parent = bottom,
	})

	-- left gauges: Proxima and Heat
	local gauges = T.new("Frame", {
		Name = "Gauges",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.5, -244, 1, -40),
		Size = UDim2.fromOffset(170, 120),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	T.label({ Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 14), Text = "PROXIMA", Font = Enum.Font.GothamBlack, TextSize = 12, TextColor3 = T.proxima, Parent = gauges })
	refs.prox = bar(gauges, "Proxima", UDim2.fromOffset(0, 16), UDim2.new(1, 0, 0, 16), T.proxima)
	marker(refs.prox, 0.6, Color3.fromRGB(255, 240, 120))
	T.label({ Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 14), Text = "HEAT", Font = Enum.Font.GothamBlack, TextSize = 12, TextColor3 = T.heat, Parent = gauges })
	refs.heat = bar(gauges, "Heat", UDim2.fromOffset(0, 54), UDim2.new(1, 0, 0, 16), T.heat)
	marker(refs.heat, 0.6, Color3.fromRGB(255, 200, 80))
	marker(refs.heat, 0.7, Color3.fromRGB(255, 80, 60))
	refs.dodge = T.label({ Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 0, 16), Text = "", Font = Enum.Font.GothamBold, TextSize = 13, Parent = gauges })
	refs.state = T.label({ Position = UDim2.fromOffset(0, 94), Size = UDim2.new(1, 0, 0, 26), Text = "", Font = Enum.Font.GothamBlack, TextSize = 13, TextColor3 = Color3.fromRGB(255, 120, 80), Parent = gauges })

	-- cast bar
	local cb = T.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.62, 0),
		Size = UDim2.fromOffset(220, 10),
		BackgroundColor3 = Color3.fromRGB(10, 10, 14),
		BackgroundTransparency = 0.2,
		Visible = false,
		Parent = gui,
	})
	T.corner(cb, 4)
	refs.castFill = T.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(255, 255, 255), Parent = cb })
	T.corner(refs.castFill, 4)
	refs.castBar = cb

	-- crosshair
	refs.cross = T.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = gui,
	})
	T.corner(refs.cross, 3)
	T.stroke(refs.cross, Color3.new(0, 0, 0), 1, 0.3)

	-- notice + feed
	refs.notice = T.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(600, 28),
		Text = "",
		TextSize = 20,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		Parent = gui,
	})
	refs.feed = T.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 60),
		Size = UDim2.fromOffset(420, 160),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	T.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = refs.feed })

	-- tooltip
	refs.tip = T.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -210),
		Size = UDim2.fromOffset(460, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = T.bg,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = gui,
	})
	T.corner(refs.tip, 8)
	T.pad(refs.tip, 10)
	refs.tipText = T.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = "", TextSize = 13, RichText = true, Parent = refs.tip })

	-- spectate / respawn label
	refs.dead = T.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(500, 40),
		Text = "",
		TextSize = 30,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		Parent = gui,
	})

	ctx.remotes.Notice.OnClientEvent:Connect(HUD.notice)
	ctx.remotes.Feed.OnClientEvent:Connect(HUD.feed)

	RunService.RenderStepped:Connect(HUD.update)
end

local function setBar(b, value, max, text, overValue)
	local frac = max > 0 and math.clamp(value / max, 0, 1) or 0
	b.fill.Size = UDim2.fromScale(frac, 1)
	b.label.Text = text or ""
	if overValue then
		b.over.Size = UDim2.fromScale(math.clamp(overValue / max, 0, 1), 1)
	end
end

local lastKit
function HUD.update()
	local ch = player.Character
	if not ch or not ch:GetAttribute("FighterId") then
		refs.bottom.Visible = false
		return
	end
	refs.bottom.Visible = true
	local t = now()
	local kitName = ch:GetAttribute("Kit")
	local data = ctx.kitData(kitName)
	if kitName ~= lastKit and data then
		lastKit = kitName
		refs.kitName.Text = string.format("%02d  %s  —  %s", data.num, string.upper(data.name), data.passive.name)
		refs.kitName.TextColor3 = ctx.Util.color(data.name)
		for i = 1, 5 do
			local m = data.moves[i]
			slots[i].name.Text = m.name
			slots[i].cost.Text = m.energy and (tostring(m.energy) .. "E") or ""
		end
	end
	local hp = ch:GetAttribute("Health") or 0
	local maxHp = ch:GetAttribute("MaxHealth") or 1000
	local sh = ch:GetAttribute("Shield") or 0
	setBar(refs.health, hp, maxHp, string.format("%d / %d%s", hp, maxHp, sh > 0 and ("  +" .. sh .. " shield") or ""), sh)
	local energy = ch:GetAttribute("Energy") or 0
	setBar(refs.energy, energy, 100, "Energy " .. energy)
	local guard = ch:GetAttribute("Guard") or 0
	setBar(refs.guard, guard, 100, (ch:GetAttribute("Guarding") and "GUARDING " or "Guard ") .. guard)
	local prox = ch:GetAttribute("Proxima") or 0
	setBar(refs.prox, prox, 100, "P " .. prox .. (prox >= 100 and "  ULT READY" or (prox >= 60 and "  P60" or "")))
	local heat = ch:GetAttribute("Heat") or 0
	setBar(refs.heat, heat, 100, "Heat " .. heat .. (heat >= 70 and "  STRESS" or ""))
	refs.heat.fill.BackgroundColor3 = heat >= 70 and Color3.fromRGB(255, 60, 40) or ctx.Theme.heat
	local dodge = ch:GetAttribute("Dodge") or 0
	refs.dodge.Text = "Dodge " .. string.rep("● ", dodge) .. string.rep("○ ", 2 - dodge)
	local burn = ch:GetAttribute("Burnout") or 0
	local state = ""
	if burn > t then
		state = string.format("BURNOUT %.1fs", burn - t)
	elseif ch:GetAttribute("Rupture") then
		state = "RUPTURE PENDING"
	end
	local hold = ch:GetAttribute("UltHold") or 0
	if hold > 0 then
		state = string.format("UNSTABLE HOLD %d%%", math.clamp((t - hold) / 1 * 100, 0, 100))
	end
	local imm = ch:GetAttribute("CCImmune") or 0
	if imm > t then
		state = state .. (state ~= "" and "  " or "") .. "CC IMMUNE"
	end
	refs.state.Text = state
	refs.kitRes.Text = ch:GetAttribute("KitRes") or ""
	refs.status.Text = ch:GetAttribute("Statuses") or ""
	-- slots
	for i = 1, 5 do
		local s = slots[i]
		local ready = ch:GetAttribute("CD" .. i) or 0
		local len = ch:GetAttribute("CDLen" .. i) or 1
		local rc = ch:GetAttribute("RC" .. i) or 0
		local left = ready - t
		if ready == -1 then
			s.cd.Size = UDim2.fromScale(1, 1)
			s.cdText.Text = "ACTIVE"
			s.cdText.TextSize = 13
		elseif left > 0 then
			s.cd.Size = UDim2.fromScale(1, math.clamp(left / math.max(len, 0.1), 0, 1))
			s.cdText.Text = left >= 10 and tostring(math.ceil(left)) or string.format("%.1f", left)
			s.cdText.TextSize = 22
		else
			s.cd.Size = UDim2.fromScale(1, 0)
			s.cdText.Text = ""
		end
		local m = data and data.moves[i]
		local badge = ""
		local strokeColor, strokeT = Color3.new(1, 1, 1), 0.7
		if rc > t then
			badge = string.format("RECAST %.1f", rc - t)
			strokeColor, strokeT = Color3.fromRGB(120, 255, 160), 0
		elseif i == 5 then
			if prox >= 100 then
				badge = heat >= 60 and "READY · HOLD=UNSTABLE" or "READY"
				strokeColor, strokeT = Color3.fromRGB(255, 220, 90), 0
			else
				badge = "P " .. prox .. "/100"
			end
		elseif prox >= 60 and m and m.p60 then
			badge = "P60"
			strokeColor, strokeT = Color3.fromRGB(255, 240, 120), 0.2
		end
		if m and m.energy and energy < m.energy then
			s.cost.TextColor3 = Color3.fromRGB(255, 90, 90)
		else
			s.cost.TextColor3 = ctx.Theme.energy
		end
		s.badge.Text = badge
		s.stroke.Color = strokeColor
		s.stroke.Transparency = strokeT
	end
	-- cast bar
	local castEnd = ch:GetAttribute("CastEnd") or 0
	local casting = ch:GetAttribute("Casting") or 0
	if casting > 0 and castEnd > t and data then
		local w = data.moves[casting].windup or 0.1
		refs.castBar.Visible = true
		refs.castFill.Size = UDim2.fromScale(math.clamp(1 - (castEnd - t) / math.max(w, 0.05), 0, 1), 1)
	else
		refs.castBar.Visible = false
	end
	-- tooltip
	if refs.tipSlot and data then
		local m = data.moves[refs.tipSlot]
		local txt = string.format("<b>%s</b>  <font color=\"#9aa\">%s</font>\n%s", esc(m.name), esc(m.statline), esc(m.desc))
		if m.p60 then
			txt ..= "\n<font color=\"#ffe680\"><b>P60.</b> " .. esc(m.p60) .. "</font>"
		end
		if m.unstable then
			txt ..= "\n<font color=\"#ff8a50\"><b>Unstable.</b> " .. esc(m.unstable) .. "</font>"
		end
		if m.counterplay then
			txt ..= "\n<font color=\"#9ab\"><i>Counterplay. " .. esc(m.counterplay) .. "</i></font>"
		end
		refs.tipText.Text = txt
		refs.tip.Visible = true
	else
		refs.tip.Visible = false
	end
	local hum = ch:FindFirstChildOfClass("Humanoid")
	refs.dead.Text = (hum and hum.Health <= 0) and "DEFEATED — respawning..." or ""
end

return HUD
