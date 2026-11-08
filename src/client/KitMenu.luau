-- In-game compendium: browse and search all 100 powers, read every rule, equip, and change match settings.
local KitMenu = {}

local ctx, T
local root
local listFrame, detail, search
local selected
local buttons = {}

local function esc(s)
	return (string.gsub(string.gsub(string.gsub(s or "", "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

local function section(parent, order, title, body, color)
	local f = T.new("Frame", {
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = T.panel2,
		BackgroundTransparency = 0.2,
		LayoutOrder = order,
		Parent = parent,
	})
	T.corner(f, 6)
	T.pad(f, 8)
	T.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3), Parent = f })
	T.label({
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = title,
		RichText = true,
		Font = Enum.Font.GothamBlack,
		TextSize = 15,
		TextColor3 = color or T.text,
		LayoutOrder = 1,
		Parent = f,
	})
	T.label({
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = body,
		RichText = true,
		TextSize = 13,
		LayoutOrder = 2,
		Parent = f,
	})
	return f
end

local function showDetail(name)
	selected = name
	for n, b in pairs(buttons) do
		b.stroke.Transparency = n == name and 0 or 0.85
	end
	for _, ch in ipairs(detail:GetChildren()) do
		if not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") then
			ch:Destroy()
		end
	end
	local d = ctx.kitData(name)
	if not d then
		return
	end
	local col = ctx.Util.color(d.name)
	local hex = string.format("#%02x%02x%02x", math.floor(col.R * 255), math.floor(col.G * 255), math.floor(col.B * 255))
	section(detail, 1, string.format("<font color=\"%s\">%02d  %s</font>", hex, d.num, esc(string.upper(d.name))), "<i>" .. esc(d.tagline) .. "</i>\n" .. esc(d.identity))
	local sty = ctx.Styles.of(d.name)
	section(detail, 2, "Passive — " .. esc(d.passive.name), esc(d.passive.text) .. "\n<font color=\"#8f98ad\">" .. (sty.showcase and "★ Showcase power: every move has bespoke choreography, sound and camera work." or ("Visual family: " .. sty.family .. " (shared element language, tinted for " .. esc(d.name) .. ").")) .. "</font>", Color3.fromRGB(255, 225, 160))
	for i = 1, 5 do
		local m = d.moves[i]
		local body = "<font color=\"#8fa0b8\">" .. esc(m.statline) .. "</font>\n" .. esc(m.desc)
		if m.p60 then
			body ..= "\n<font color=\"#ffe680\"><b>P60.</b> " .. esc(m.p60) .. "</font>"
		end
		if m.unstable then
			body ..= "\n<font color=\"#ff8a50\"><b>Unstable mutation.</b> " .. esc(m.unstable) .. "</font>"
		end
		if m.counterplay then
			body ..= "\n<font color=\"#9fb3c8\"><i>Counterplay. " .. esc(m.counterplay) .. "</i></font>"
		end
		local key = ctx.Controls.KEY_LABELS[i]
		section(detail, 2 + i, string.format("[%s] %d  %s%s", key, i, esc(m.name), i == 5 and "  — ULTIMATE" or ""), body, i == 5 and Color3.fromRGB(255, 200, 90) or T.text)
	end
	section(detail, 8, "Mutation rules — " .. esc(d.mutation.name), esc(d.mutation.text), Color3.fromRGB(255, 140, 90))
	if d.sequence then
		section(detail, 9, "Sequence and weakness", esc(d.sequence), T.accent)
	end
	section(detail, 10, "Team interactions — " .. esc(d.team.partners) .. "  (Synergy Mode)", esc(d.team.text), Color3.fromRGB(150, 255, 180))
	detail.CanvasPosition = Vector2.zero
end

local function rebuildList(filter)
	filter = filter and string.lower(filter) or ""
	for _, e in ipairs(ctx.KitIndex) do
		local b = buttons[e.name]
		if b then
			local match = filter == "" or string.find(string.lower(e.name), filter, 1, true) ~= nil or string.find(string.lower(e.tagline), filter, 1, true) ~= nil or tostring(e.num) == filter
			b.button.Visible = match
		end
	end
end

function KitMenu.open()
	root.Visible = true
	ctx.Controls.setMenuOpen(true)
	local ch = ctx.player.Character
	local cur = ch and ch:GetAttribute("Kit") or ctx.player:GetAttribute("Kit")
	showDetail(selected or cur or ctx.KitIndex[1].name)
end

function KitMenu.close()
	root.Visible = false
	ctx.Controls.setMenuOpen(ctx.MatchUI and ctx.MatchUI.isOpen() or false)
end

function KitMenu.isOpen()
	return root ~= nil and root.Visible
end

function KitMenu.toggle()
	if root.Visible then
		KitMenu.close()
	else
		KitMenu.open()
	end
end

function KitMenu.init(c)
	ctx = c
	T = c.Theme
	root = T.new("Frame", {
		Name = "Compendium",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.86, 0, 0.84, 0),
		BackgroundColor3 = T.bg,
		BackgroundTransparency = 0.04,
		Visible = false,
		ZIndex = 10,
		Parent = c.gui,
	})
	T.corner(root, 10)
	T.stroke(root, T.accent, 2, 0.5)
	T.new("UISizeConstraint", { MaxSize = Vector2.new(1300, 860), Parent = root })

	-- header
	T.label({
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(0.5, 0, 0, 30),
		Text = "EB: PROXIMA — POWER COMPENDIUM",
		Font = Enum.Font.GothamBlack,
		TextSize = 22,
		TextColor3 = T.accent,
		Parent = root,
	})
	local close = T.button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(34, 30), Text = "X", Parent = root })
	close.Activated:Connect(KitMenu.close)

	-- settings row
	local settings = T.new("Frame", {
		Position = UDim2.new(0, 16, 0, 44),
		Size = UDim2.new(1, -32, 0, 32),
		BackgroundTransparency = 1,
		Parent = root,
	})
	T.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = settings })
	local equip = T.button({
		Size = UDim2.fromOffset(200, 30),
		Text = "EQUIP SELECTED POWER",
		BackgroundColor3 = Color3.fromRGB(50, 120, 220),
		LayoutOrder = 6,
		Parent = settings,
	})
	equip.Activated:Connect(function()
		if selected then
			ctx.remotes.Input:FireServer("selectKit", selected)
			KitMenu.close()
		end
	end)
	local botBtn = T.button({ Size = UDim2.fromOffset(230, 30), Text = "Spar against it (practice)", LayoutOrder = 7, Parent = settings })
	botBtn.Activated:Connect(function()
		if selected then
			ctx.remotes.Input:FireServer("setting", "spar", selected)
			ctx.remotes.Input:FireServer("setting", "botKit", selected)
		end
	end)
	T.label({ Size = UDim2.fromOffset(300, 30), Text = "★ = showcase power (bespoke choreography)", TextSize = 12, TextColor3 = T.dim, LayoutOrder = 8, Parent = settings })

	-- list
	search = T.new("TextBox", {
		Position = UDim2.new(0, 16, 0, 84),
		Size = UDim2.new(0.3, -16, 0, 30),
		BackgroundColor3 = T.panel2,
		PlaceholderText = "Search powers (name, number, theme)...",
		Text = "",
		TextColor3 = T.text,
		PlaceholderColor3 = T.dim,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		ClearTextOnFocus = false,
		Parent = root,
	})
	T.corner(search, 6)
	search:GetPropertyChangedSignal("Text"):Connect(function()
		rebuildList(search.Text)
	end)
	listFrame = T.new("ScrollingFrame", {
		Position = UDim2.new(0, 16, 0, 120),
		Size = UDim2.new(0.3, -16, 1, -136),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = root,
	})
	T.new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -6, 0, 34),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = listFrame,
	})
	for _, e in ipairs(c.KitIndex) do
		local col = c.Util.color(e.name)
		local b = T.button({
			Text = "",
			BackgroundColor3 = T.panel,
			LayoutOrder = e.num,
			Parent = listFrame,
		})
		local stroke = T.stroke(b, col, 2, 0.85)
		T.new("Frame", { Position = UDim2.fromOffset(4, 4), Size = UDim2.new(0, 6, 1, -8), BackgroundColor3 = col, Parent = b })
		T.label({
			Position = UDim2.fromOffset(16, 0),
			Size = UDim2.new(1, -20, 1, 0),
			Text = string.format("%02d  %s%s", e.num, e.name, ctx.Styles.SHOWCASE[e.name] and "  ★" or ""),
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = b,
		})
		b.Activated:Connect(function()
			showDetail(e.name)
		end)
		buttons[e.name] = { button = b, stroke = stroke }
	end

	-- detail
	detail = T.new("ScrollingFrame", {
		Position = UDim2.new(0.3, 8, 0, 84),
		Size = UDim2.new(0.7, -24, 1, -100),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		Parent = root,
	})
	T.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), Parent = detail })
end

return KitMenu
