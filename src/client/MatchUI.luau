-- Match interface: top bar (phase, timer, score race), countdown splash, results screen with
-- Rematch / Return, and the panel (P) with Match setup, Practice tools, Settings and Controls.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MatchUI = {}
local ctx, T, Settings, Audio
local player = Players.LocalPlayer
local refs = {}
local board

local function send(key, value)
	ctx.remotes.Input:FireServer("setting", key, value)
end

local function click()
	if Audio then
		Audio.play("uiClick")
	end
end

local function fmtTime(s)
	s = math.max(0, math.floor(s))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function button(parent, text, size, color, fn)
	local b = T.new("TextButton", {
		Size = size or UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = color or T.panel2,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = T.text,
		AutoButtonColor = true,
		Parent = parent,
	})
	T.corner(b, 6)
	b.MouseButton1Click:Connect(function()
		click()
		fn(b)
	end)
	b.MouseEnter:Connect(function()
		if Audio then
			Audio.play("uiHover")
		end
	end)
	return b
end

-- labelled row with a value and a control (cycle button or -/+)
local function row(parent, label, order)
	local r = T.new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	T.label({ Size = UDim2.new(0.5, 0, 1, 0), Text = label, TextSize = 14, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left, Parent = r })
	return r
end

local function cycleRow(parent, label, order, options, get, set)
	local r = row(parent, label, order)
	local b = button(r, "", UDim2.new(0.48, 0, 1, -4), T.panel2, function(btn)
		local cur = get()
		local idx = table.find(options, cur) or 0
		local nv = options[idx % #options + 1]
		set(nv)
		btn.Text = tostring(nv)
	end)
	b.AnchorPoint = Vector2.new(1, 0)
	b.Position = UDim2.new(1, 0, 0, 2)
	b.Text = tostring(get())
	return b
end

local function toggleRow(parent, label, order, get, set)
	return cycleRow(parent, label, order, { "On", "Off" }, function()
		return get() and "On" or "Off"
	end, function(v)
		set(v == "On")
	end)
end

local function stepRow(parent, label, order, get, set, stepv, lo, hi, fmt)
	local r = row(parent, label, order)
	local val = T.label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -44, 0, 0), Size = UDim2.new(0.22, 0, 1, 0), Text = "", TextSize = 15, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Center, Parent = r })
	local function refresh()
		val.Text = fmt and fmt(get()) or tostring(get())
	end
	local minus = button(r, "–", UDim2.fromOffset(36, 28), T.panel2, function()
		set(math.clamp(get() - stepv, lo, hi))
		refresh()
	end)
	minus.AnchorPoint = Vector2.new(1, 0)
	minus.Position = UDim2.new(0.78, -48, 0, 3)
	local plus = button(r, "+", UDim2.fromOffset(36, 28), T.panel2, function()
		set(math.clamp(get() + stepv, lo, hi))
		refresh()
	end)
	plus.AnchorPoint = Vector2.new(1, 0)
	plus.Position = UDim2.new(1, 0, 0, 3)
	refresh()
	return refresh
end

local function pct(v)
	return math.floor(v * 100 + 0.5) .. "%"
end

-- Panel ----------------------------------------------------------------------------------------------
local tabs = {}
local function showTab(name)
	for n, t in pairs(tabs) do
		t.page.Visible = n == name
		t.btn.BackgroundColor3 = n == name and T.accent:Lerp(T.panel2, 0.55) or T.panel2
	end
end

local function buildPanel(gui)
	local panel = T.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0.82, 0),
		BackgroundColor3 = T.bg,
		BackgroundTransparency = 0.04,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	T.new("UISizeConstraint", { MaxSize = Vector2.new(620, 560), Parent = panel })
	T.corner(panel, 10)
	T.stroke(panel, T.accent, 1, 0.6)
	T.pad(panel, 12)
	refs.panel = panel
	local title = T.label({ Size = UDim2.new(1, -40, 0, 26), Text = "EB: PROXIMA", TextSize = 20, Font = Enum.Font.GothamBlack, Parent = panel })
	local _ = title
	button(panel, "✕", UDim2.fromOffset(30, 26), T.panel2, function()
		MatchUI.togglePanel(false)
	end).Position = UDim2.new(1, -30, 0, 0)
	local tabBar = T.new("Frame", { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, Parent = panel })
	T.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), Parent = tabBar })
	local body = T.new("Frame", { Position = UDim2.fromOffset(0, 72), Size = UDim2.new(1, 0, 1, -72), BackgroundTransparency = 1, Parent = panel })
	local function page(name)
		local pg = T.new("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ScrollBarThickness = 4,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			Visible = false,
			Parent = body,
		})
		T.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = pg })
		local b = button(tabBar, name, UDim2.new(0.25, -5, 1, 0), T.panel2, function()
			showTab(name)
		end)
		tabs[name] = { page = pg, btn = b }
		return pg
	end
	-- Match
	local mp = page("Match")
	refs.startBtn = button(mp, "START MATCH", UDim2.new(1, 0, 0, 44), Color3.fromRGB(60, 140, 90), function()
		send("start")
		MatchUI.togglePanel(false)
	end)
	refs.startBtn.LayoutOrder = 0
	refs.startBtn.TextSize = 18
	local function wattr(name, default)
		local v = workspace:GetAttribute(name)
		if v == nil then
			return default
		end
		return v
	end
	stepRow(mp, "Bots", 1, function()
		return wattr("BotCount", 3)
	end, function(v)
		send("bots", v)
		workspace:SetAttribute("BotCount", v)
	end, 1, 0, 7)
	cycleRow(mp, "Bot difficulty", 2, { "Easy", "Normal", "Hard" }, function()
		return wattr("BotDifficulty", "Normal")
	end, function(v)
		send("difficulty", v)
	end)
	cycleRow(mp, "KOs to win", 3, { 3, 5, 10, 15 }, function()
		return wattr("KOTarget", 5)
	end, function(v)
		send("koTarget", v)
	end)
	cycleRow(mp, "Time limit", 4, { "3:00", "5:00", "8:00" }, function()
		return fmtTime(wattr("TimeLimit", 300))
	end, function(v)
		local m = tonumber(string.sub(v, 1, 1)) or 5
		send("timeLimit", m * 60)
	end)
	toggleRow(mp, "Teams (Sun vs Moon)", 5, function()
		return wattr("Teams", false)
	end, function(v)
		send("teams", v)
	end)
	toggleRow(mp, "Synergy mode", 6, function()
		return wattr("Synergy", true)
	end, function(v)
		send("synergy", v)
	end)
	refs.endBtn = button(mp, "End match & return to practice", UDim2.new(1, 0, 0, 34), Color3.fromRGB(120, 60, 60), function()
		send("practice")
		MatchUI.togglePanel(false)
	end)
	refs.endBtn.LayoutOrder = 9
	-- Practice
	local pp = page("Practice")
	T.label({ Size = UDim2.new(1, 0, 0, 40), Text = "Training Annex tools (practice only). Dummies stand at the range; warnings they cast use the same telegraph shapes as real fights.", TextWrapped = true, TextSize = 13, TextColor3 = T.dim, LayoutOrder = 0, Parent = pp })
	cycleRow(pp, "Dummy behaviour", 1, { "Idle", "Guard", "Strafe", "Shoot" }, function()
		return wattr("DummyMode", "Idle")
	end, function(v)
		send("dummyMode", v)
	end)
	local free = false
	toggleRow(pp, "Free cast (no costs / short cooldowns)", 2, function()
		return free
	end, function(v)
		free = v
		send("freeCast", v)
	end)
	button(pp, "Fill Proxima + Heat (try ultimates)", UDim2.new(1, 0, 0, 34), T.panel2, function()
		send("fillProxima")
	end).LayoutOrder = 3
	button(pp, "Add sparring bot (your selected power's rival)", UDim2.new(1, 0, 0, 34), T.panel2, function()
		send("spar", true)
	end).LayoutOrder = 4
	button(pp, "Remove sparring bots", UDim2.new(1, 0, 0, 34), T.panel2, function()
		send("spar", false)
	end).LayoutOrder = 5
	button(pp, "Choose power (TAB)", UDim2.new(1, 0, 0, 34), T.panel2, function()
		MatchUI.togglePanel(false)
		ctx.KitMenu.open()
	end).LayoutOrder = 6
	-- Settings
	local sp = page("Settings")
	local function vol(key, order)
		stepRow(sp, Settings.LABELS[key], order, function()
			return Settings.get(key)
		end, function(v)
			Settings.set(key, math.floor(v * 100 + 0.5) / 100)
		end, 0.1, 0, 1, pct)
	end
	vol("MasterVolume", 1)
	vol("SfxVolume", 2)
	vol("AmbienceVolume", 3)
	vol("UIVolume", 4)
	T.label({ Size = UDim2.new(1, 0, 0, 18), Text = "Music: none included (no licensed tracks in this build).", TextSize = 12, TextColor3 = T.dim, LayoutOrder = 5, Parent = sp })
	cycleRow(sp, Settings.LABELS.Quality, 6, { "Low", "Medium", "High" }, function()
		return ({ "Low", "Medium", "High" })[Settings.get("Quality")]
	end, function(v)
		Settings.set("Quality", v == "Low" and 1 or (v == "Medium" and 2 or 3))
	end)
	toggleRow(sp, Settings.LABELS.ReducedFlash, 7, function()
		return Settings.get("ReducedFlash")
	end, function(v)
		Settings.set("ReducedFlash", v)
	end)
	toggleRow(sp, Settings.LABELS.ReducedMotion, 8, function()
		return Settings.get("ReducedMotion")
	end, function(v)
		Settings.set("ReducedMotion", v)
	end)
	stepRow(sp, Settings.LABELS.ShakeScale, 9, function()
		return Settings.get("ShakeScale")
	end, function(v)
		Settings.set("ShakeScale", math.floor(v * 100 + 0.5) / 100)
	end, 0.25, 0, 1.5, pct)
	stepRow(sp, Settings.LABELS.Sensitivity, 10, function()
		return Settings.get("Sensitivity")
	end, function(v)
		Settings.set("Sensitivity", math.floor(v * 100 + 0.5) / 100)
	end, 0.1, 0.2, 3, pct)
	stepRow(sp, Settings.LABELS.FieldOfView, 11, function()
		return Settings.get("FieldOfView")
	end, function(v)
		Settings.set("FieldOfView", v)
	end, 4, 56, 96)
	toggleRow(sp, Settings.LABELS.DamageNumbers, 12, function()
		return Settings.get("DamageNumbers")
	end, function(v)
		Settings.set("DamageNumbers", v)
	end)
	-- Controls
	local cp = page("Controls")
	T.label({
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		RichText = true,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = table.concat({
			"<b>Move</b>  WASD · <b>Jump</b>  Space · <b>Aim</b>  mouse (camera-locked crosshair)",
			"<b>Basic attack</b>  Left mouse (hold to chain) · <b>Guard</b>  Right mouse (hold; tap just before a hit = Perfect Guard)",
			"<b>Dodge</b>  Shift (2 charges, brief invulnerability) · <b>Kit action</b>  V",
			"<b>Moves 1–4</b>  Q E R F  (or 1–4) · <b>Ultimate</b>  G (needs 100 Proxima; hold with 60+ Heat for the Unstable version)",
			"<b>Modifier</b>  hold Ctrl while casting (alternate version where a move has one)",
			"<b>Powers</b>  TAB · <b>Match / practice / settings</b>  P · <b>Free cursor</b>  Z · <b>Swap shoulder</b>  C · <b>Zoom</b>  mouse wheel",
			"Gamepad: sticks move/look, R2 basic, L2 guard, L1 dodge, X/Y/B/D-up moves, R1 ultimate, R3 kit action, Select powers, Start panel.",
			"Touch: on-screen buttons; drag the right half of the screen to look.",
			"",
			"<b>Reading the fight</b>: hostile warnings have spiked, pulsing edges and fill up until impact; allied warnings are thin dashed outlines; your own are thin solid lines. Enemy plates show ✕ and a notched bar, allies ◆.",
		}, "\n"),
		Parent = cp,
	})
	showTab("Match")
end

function MatchUI.togglePanel(force)
	local open = force
	if open == nil then
		open = not refs.panel.Visible
	end
	refs.panel.Visible = open
	if ctx.Controls then
		ctx.Controls.setMenuOpen(open or (ctx.KitMenu and ctx.KitMenu.isOpen and ctx.KitMenu.isOpen()) or false)
	end
	if open and Audio then
		Audio.play("uiOpen")
	end
end

function MatchUI.isOpen()
	return refs.panel and refs.panel.Visible
end

-- Top bar ---------------------------------------------------------------------------------------------
local function buildTop(gui)
	local top = T.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(460, 52),
		BackgroundColor3 = T.bg,
		BackgroundTransparency = 0.25,
		Parent = gui,
	})
	T.corner(top, 8)
	refs.top = top
	refs.phase = T.label({ Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 4), Text = "", TextSize = 17, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Center, Parent = top })
	refs.race = T.label({ Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 27), Text = "", RichText = true, TextSize = 13, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Center, Parent = top })
	refs.hint = T.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(620, 20),
		Text = "",
		TextSize = 14,
		TextColor3 = T.dim,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
		Parent = gui,
	})
	refs.splash = T.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(600, 110),
		Text = "",
		TextSize = 96,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.2,
		TextTransparency = 1,
		ZIndex = 12,
		Parent = gui,
	})
end

local function entries()
	local list = {}
	for _, c in ipairs(board:GetChildren()) do
		if c:GetAttribute("InMatch") then
			table.insert(list, c)
		end
	end
	table.sort(list, function(a, b)
		local ka, kb = a:GetAttribute("KOs") or 0, b:GetAttribute("KOs") or 0
		if ka ~= kb then
			return ka > kb
		end
		return (a:GetAttribute("Deaths") or 0) < (b:GetAttribute("Deaths") or 0)
	end)
	return list
end

local lastCount
local function updateTop()
	local state = workspace:GetAttribute("MatchState") or "Practice"
	local phaseEnd = workspace:GetAttribute("PhaseEnd") or 0
	local now = workspace:GetServerTimeNow()
	local target = workspace:GetAttribute("KOTarget") or 5
	if state == "Practice" then
		refs.phase.Text = "PRACTICE  ·  TRAINING ANNEX"
		refs.race.Text = "Press <b>P</b> to start a match · <b>TAB</b> powers"
		refs.hint.Text = ""
	elseif state == "Countdown" then
		refs.phase.Text = "GET READY"
		local left = math.ceil(phaseEnd - now)
		if left ~= lastCount and left >= 1 and left <= 3 then
			lastCount = left
			MatchUI.splash(tostring(left), Color3.new(1, 1, 1), 0.8)
			if Audio then
				Audio.play("countdown")
			end
		end
	elseif state == "Fight" then
		refs.phase.Text = string.format("FIRST TO %d  ·  %s", target, fmtTime(phaseEnd - now))
	elseif state == "Results" then
		refs.phase.Text = (workspace:GetAttribute("Winner") or "") ~= "" and string.upper(workspace:GetAttribute("Winner")) or "RESULTS"
	end
	if state ~= "Practice" then
		local list = entries()
		local parts = {}
		local myKey
		for _, c in ipairs(list) do
			if c:GetAttribute("UserId") == player.UserId and not c:GetAttribute("IsBot") then
				myKey = c
			end
		end
		for i = 1, math.min(4, #list) do
			local c = list[i]
			local nm = c:GetAttribute("Name") or "?"
			local mine = c == myKey
			local col = mine and "#FFD45A" or "#E6E8F0"
			table.insert(parts, string.format('<font color="%s">%s %d</font>', col, (mine and "YOU" or nm), c:GetAttribute("KOs") or 0))
		end
		refs.race.Text = table.concat(parts, "   ·   ")
	end
	if state ~= "Countdown" then
		lastCount = nil
	end
end

function MatchUI.splash(text, color, dur)
	local s = refs.splash
	s.Text = text
	s.TextColor3 = color or Color3.new(1, 1, 1)
	s.TextTransparency = 0
	s.TextStrokeTransparency = 0.2
	s.TextSize = 120
	local reduced = Settings.get("ReducedMotion")
	if not reduced then
		TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back), { TextSize = 96 }):Play()
	else
		s.TextSize = 96
	end
	refs.splashTok = (refs.splashTok or 0) + 1
	local tok = refs.splashTok
	task.delay(dur or 0.8, function()
		if refs.splashTok == tok then
			TweenService:Create(s, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

-- Results ---------------------------------------------------------------------------------------------
local function buildResults(gui)
	local r = T.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.new(0.92, 0, 0.7, 0),
		BackgroundColor3 = T.bg,
		BackgroundTransparency = 0.06,
		Visible = false,
		ZIndex = 15,
		Parent = gui,
	})
	T.new("UISizeConstraint", { MaxSize = Vector2.new(700, 480), Parent = r })
	T.corner(r, 10)
	T.pad(r, 14)
	refs.results = r
	refs.resTitle = T.label({ Size = UDim2.new(1, 0, 0, 40), Text = "", TextSize = 32, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Center, Parent = r })
	refs.resSub = T.label({ Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 20), Text = "", TextSize = 14, TextColor3 = T.dim, TextXAlignment = Enum.TextXAlignment.Center, Parent = r })
	local tbl = T.new("Frame", { Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 1, -130), BackgroundTransparency = 1, Parent = r })
	T.new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tbl })
	refs.resTable = tbl
	local btns = T.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, Parent = r })
	T.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = btns })
	button(btns, "REMATCH", UDim2.new(0.42, 0, 1, 0), Color3.fromRGB(60, 140, 90), function()
		send("rematch")
	end).TextSize = 18
	button(btns, "RETURN TO PRACTICE", UDim2.new(0.42, 0, 1, 0), T.panel2, function()
		send("practice")
	end).TextSize = 16
	refs.resTimer = T.label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(160, 18), Text = "", TextSize = 12, TextColor3 = T.dim, TextXAlignment = Enum.TextXAlignment.Right, Parent = r })
end

function MatchUI.showResults(data)
	local r = refs.results
	for _, c in ipairs(refs.resTable:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local won = false
	local myTeam = player.Character and player.Character:GetAttribute("Team") or ""
	local winner = data.winner or ""
	for i, row0 in ipairs(data.rows or {}) do
		local mine = row0.userId == player.UserId and not row0.isBot
		if i == 1 and mine and not data.teams then
			won = true
		end
		local fr = T.new("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = mine and Color3.fromRGB(70, 60, 30) or T.panel, BackgroundTransparency = 0.2, LayoutOrder = i, Parent = refs.resTable })
		T.corner(fr, 5)
		local kc = ctx.Util.color(row0.kit)
		local function cell(x, w, text, align, color)
			T.label({ Position = UDim2.new(x, 6, 0, 0), Size = UDim2.new(w, -6, 1, 0), Text = text, TextSize = 14, Font = Enum.Font.GothamMedium, TextXAlignment = align or Enum.TextXAlignment.Left, TextColor3 = color or T.text, Parent = fr })
		end
		cell(0, 0.06, "#" .. i)
		cell(0.06, 0.32, (row0.team ~= "" and (row0.team == "Sun" and "☀ " or "☾ ") or "") .. row0.name .. (row0.name == data.mvp and "  ★MVP" or ""), nil, mine and Color3.fromRGB(255, 215, 90) or nil)
		cell(0.38, 0.18, row0.kit, nil, kc)
		cell(0.56, 0.1, tostring(row0.kos) .. " KO", Enum.TextXAlignment.Right)
		cell(0.66, 0.1, tostring(row0.deaths) .. " D", Enum.TextXAlignment.Right)
		cell(0.76, 0.12, tostring(row0.damage) .. " dmg", Enum.TextXAlignment.Right)
		cell(0.88, 0.12, "best " .. tostring(row0.bestHit), Enum.TextXAlignment.Right, T.dim)
	end
	if data.teams and myTeam ~= "" then
		won = winner:find(myTeam) ~= nil
	end
	refs.resTitle.Text = winner ~= "" and (won and "VICTORY" or (winner == "Draw" and "DRAW" or "DEFEAT")) or "MATCH OVER"
	refs.resTitle.TextColor3 = won and Color3.fromRGB(255, 215, 90) or Color3.fromRGB(230, 230, 240)
	refs.resSub.Text = winner .. (data.reason == "time" and "  ·  time limit" or "") .. (data.mvp ~= "" and ("  ·  MVP " .. data.mvp) or "")
	r.Visible = true
	if Audio then
		Audio.play(won and "victory" or "defeat")
	end
	if ctx.Controls then
		ctx.Controls.setMenuOpen(true)
	end
end

local function hideResults()
	if refs.results.Visible then
		refs.results.Visible = false
		if ctx.Controls and not MatchUI.isOpen() then
			ctx.Controls.setMenuOpen(false)
		end
	end
end

function MatchUI.init(c)
	ctx = c
	T = c.Theme
	Settings = c.Settings
	Audio = c.Audio
	board = ReplicatedStorage:WaitForChild("Scoreboard")
	local gui = Instance.new("ScreenGui")
	gui.Name = "EBMatch"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")
	refs.gui = gui
	buildTop(gui)
	buildResults(gui)
	buildPanel(gui)
	ctx.remotes.MatchEvent.OnClientEvent:Connect(function(name, data)
		if name == "results" then
			MatchUI.showResults(data)
		elseif name == "fight" then
			MatchUI.splash("FIGHT!", Color3.fromRGB(255, 200, 80), 0.9)
			if Audio then
				Audio.play("fight")
			end
			hideResults()
		elseif name == "state" then
			if data.state ~= "Results" then
				hideResults()
			end
			if data.state == "Practice" then
				MatchUI.splash("PRACTICE", Color3.fromRGB(150, 210, 255), 0.9)
			end
		end
	end)
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			updateTop()
			if refs.results.Visible then
				local left = (workspace:GetAttribute("PhaseEnd") or 0) - workspace:GetServerTimeNow()
				refs.resTimer.Text = left > 0 and string.format("returning in %d", math.ceil(left)) or ""
			end
		end
	end)
end

return MatchUI
