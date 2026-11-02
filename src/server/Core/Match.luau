-- Match flow: players, kit selection, respawns, kill feed, leaderstats, teams, bots and dummies.
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local S = require(script.Parent.S)
local Fighter = require(script.Parent.Fighter)

local Match = {}
S.Match = Match

local Config = S.Config
local remotes

Match.botTarget = 0
Match.teamsOn = false
Match.dummies = {}

local function setWorldAttrs()
	workspace:SetAttribute("Synergy", S.synergy == true)
	workspace:SetAttribute("Teams", Match.teamsOn)
	workspace:SetAttribute("BotCount", Match.botTarget)
end

local function ensureTeams()
	local sun = Teams:FindFirstChild("Sun")
	if not sun then
		sun = Instance.new("Team")
		sun.Name = "Sun"
		sun.TeamColor = BrickColor.new("Bright orange")
		sun.AutoAssignable = false
		sun.Parent = Teams
	end
	local moon = Teams:FindFirstChild("Moon")
	if not moon then
		moon = Instance.new("Team")
		moon.Name = "Moon"
		moon.TeamColor = BrickColor.new("Bright blue")
		moon.AutoAssignable = false
		moon.Parent = Teams
	end
	return sun, moon
end

local function teamCounts()
	local sun, moon = 0, 0
	for _, f in pairs(S.fighters) do
		if not f.isSummon and not f.isDummy then
			if f.team == "Sun" then
				sun += 1
			elseif f.team == "Moon" then
				moon += 1
			end
		end
	end
	return sun, moon
end

local function pickTeam()
	if not Match.teamsOn then
		return nil
	end
	local s, m = teamCounts()
	return s <= m and "Sun" or "Moon"
end

local function leaderstats(player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local k = Instance.new("IntValue")
	k.Name = "Kills"
	k.Parent = ls
	local d = Instance.new("IntValue")
	d.Name = "Deaths"
	d.Parent = ls
	ls.Parent = player
end

local function feed(text)
	if remotes then
		remotes.Feed:FireAllClients(text)
	end
end
Match.feed = feed

-- Players ------------------------------------------------------------------------------------
local function onCharacter(player, char)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	local hum = char:WaitForChild("Humanoid", 10)
	if not root or not hum then
		return
	end
	task.wait()
	local spawnPos = S.Arena.randomSpawn()
	char:PivotTo(CFrame.new(spawnPos, Vector3.new(0, spawnPos.Y, 0)))
	local kit = player:GetAttribute("Kit") or Config.DEFAULT_KIT
	local team = Match.teamsOn and player.Team and player.Team.Name or nil
	local f = Fighter.new(char, { player = player, kit = kit, team = team, name = player.DisplayName })
	f.invulnUntil = S.now() + Config.SPAWN_PROTECTION
	S.FX.highlight(char, Color3.fromRGB(255, 255, 255), Config.SPAWN_PROTECTION, 0.85)
	hum.Died:Connect(function()
		if not f.dead then
			Fighter.kill(f, f.lastDamager)
		end
	end)
end

local function loadCharacter(player)
	if player.Parent then
		player:LoadCharacter()
	end
end

function Match.onPlayerAdded(player)
	leaderstats(player)
	pcall(function()
		player.DevEnableMouseLock = false -- LeftShift is dodge; the HUD provides its own aim lock (Z)
	end)
	player:SetAttribute("Kit", player:GetAttribute("Kit") or Config.DEFAULT_KIT)
	if Match.teamsOn then
		local sun, moon = ensureTeams()
		local s, m = teamCounts()
		player.Team = s <= m and sun or moon
	end
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	task.defer(loadCharacter, player)
end

-- Kit selection: swaps immediately when out of combat, otherwise on respawn.
function Match.selectKit(player, name)
	local display = S.Kits.displayName(name)
	if not display then
		return
	end
	player:SetAttribute("Kit", display)
	local f = Fighter.forPlayer(player)
	if not f or f.dead then
		return
	end
	local now = S.now()
	local inCombat = now - (f.lastContest or 0) < 5 or now - (f.lastHit or 0) < 5
	if inCombat or S.Cast.isBusy(f) or f.formActive then
		S.Cast.notify(f, display .. " equips on respawn (in combat)")
		return
	end
	S.Objects.removeOwned(f)
	S.Zones.removeOwned(f)
	for _, sm in ipairs(table.clone(f.summons)) do
		S.Summons.remove(sm, "kit swap")
	end
	for name2 in pairs(f.statuses) do
		S.Status.remove(f, name2, "kit swap")
	end
	f.shields = {}
	f.proxima = 0
	f.heat = 0
	f.energy = Config.MAX_ENERGY
	f.speedMult, f.jumpMult, f.hitScale = 1, 1, 1
	f.noGuard, f.noDodge, f.noBasic, f.basicOverride, f.disabled = nil, nil, nil, nil, nil
	Fighter.setKit(f, display)
	for slot = 1, 5 do
		f.model:SetAttribute("CD" .. slot, 0)
		f.model:SetAttribute("RC" .. slot, 0)
	end
	S.Cast.notify(f, "Equipped " .. display)
end

-- Defeat / respawn -------------------------------------------------------------------------------
local function credit(victim, killer)
	if victim.player then
		local ls = victim.player:FindFirstChild("leaderstats")
		if ls then
			ls.Deaths.Value += 1
		end
	end
	if killer and killer ~= victim and killer.player then
		local ls = killer.player:FindFirstChild("leaderstats")
		if ls then
			ls.Kills.Value += 1
		end
	end
	if not victim.isSummon then
		local kname = killer and killer ~= victim and (killer.name .. " [" .. tostring(killer.kitName) .. "]") or "the arena"
		feed(kname .. "  defeated  " .. victim.name .. " [" .. tostring(victim.kitName) .. "]")
	end
end

S.on("defeated", function(f, killer)
	if f.isSummon then
		return
	end
	credit(f, killer)
	if f.player then
		local player = f.player
		task.delay(Config.RESPAWN_TIME, function()
			Fighter.remove(f)
			if player.Parent then
				if Match.teamsOn and not player.Team then
					local sun, moon = ensureTeams()
					local s, m = teamCounts()
					player.Team = s <= m and sun or moon
				end
				loadCharacter(player)
			end
		end)
	elseif f.isBot then
		task.delay(Config.RESPAWN_TIME, function()
			Fighter.remove(f)
			if f.model then
				f.model:Destroy()
			end
			Match.syncBots()
		end)
	elseif f.isDummy then
		task.delay(3, function()
			Fighter.remove(f)
			if f.model then
				f.model:Destroy()
			end
			Match.spawnDummy(f.dummyIndex)
		end)
	end
end)

-- Rigs -----------------------------------------------------------------------------------------------
local function makeRig(name, color)
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = color
	desc.TorsoColor = color
	desc.LeftArmColor = color
	desc.RightArmColor = color
	desc.LeftLegColor = Color3.fromRGB(60, 60, 70)
	desc.RightLegColor = Color3.fromRGB(60, 60, 70)
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		-- minimal fallback rig
		model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.Transparency = 1
		root.Parent = model
		local torso = Instance.new("Part")
		torso.Name = "UpperTorso"
		torso.Size = Vector3.new(2, 4.5, 1.2)
		torso.Color = color
		torso.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = torso
		w.Parent = root
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Size = Vector3.new(1.4, 1.4, 1.4)
		head.Color = color
		head.CFrame = CFrame.new(0, 3, 0)
		head.Parent = model
		local w2 = Instance.new("WeldConstraint")
		w2.Part0 = torso
		w2.Part1 = head
		w2.Parent = torso
		local hum = Instance.new("Humanoid")
		hum.HipHeight = 2
		hum.Parent = model
		model.PrimaryPart = root
	end
	model.Name = name
	return model
end

function Match.spawnBot(kitName)
	kitName = kitName or S.Kits.random()
	local model = makeRig("Bot " .. kitName, S.Util.color(kitName))
	local pos = S.Arena.randomSpawn()
	model:PivotTo(CFrame.new(pos))
	model.Parent = S.folders.Bots
	local root = model:FindFirstChild("HumanoidRootPart")
	if root then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	local f = Fighter.new(model, { isBot = true, kit = kitName, team = pickTeam(), name = "Bot " .. kitName })
	f.invulnUntil = S.now() + Config.SPAWN_PROTECTION
	local hum = f.humanoid
	if hum then
		hum.Died:Connect(function()
			if not f.dead then
				Fighter.kill(f, f.lastDamager)
			end
		end)
	end
	return f
end

function Match.botCount()
	local n = 0
	for _, f in pairs(S.fighters) do
		if f.isBot then
			n += 1
		end
	end
	return n
end

function Match.syncBots()
	local n = Match.botCount()
	while n < Match.botTarget do
		Match.spawnBot()
		n += 1
	end
	if n > Match.botTarget then
		for _, f in pairs(S.fighters) do
			if n <= Match.botTarget then
				break
			end
			if f.isBot then
				Fighter.remove(f)
				if f.model then
					f.model:Destroy()
				end
				n -= 1
			end
		end
	end
end

function Match.spawnDummy(i)
	local spot = S.Arena.dummySpots[i]
	if not spot then
		return
	end
	local model = makeRig("Training Dummy " .. i, Color3.fromRGB(200, 170, 110))
	model:PivotTo(CFrame.new(spot + Vector3.new(0, 4, 0)) * CFrame.Angles(0, math.pi, 0))
	model.Parent = S.folders.Bots
	local root = model:FindFirstChild("HumanoidRootPart")
	if root then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	local f = Fighter.new(model, { isDummy = true, name = "Training Dummy" })
	f.kitName = "Dummy"
	f.dummyIndex = i
	f.noGuard = true
	Match.dummies[i] = f
	return f
end

-- Dummies reset to full health 4 seconds after their last hit.
task.spawn(function()
	while true do
		task.wait(1)
		local now = S.now()
		for _, f in pairs(Match.dummies) do
			if S.alive(f) and now - (f.lastHit or 0) > 4 and f.health < f.maxHealth then
				f.health = f.maxHealth
				f.shields = {}
				Fighter.syncHealth(f)
			end
		end
	end
end)

-- Settings (casual servers: any player may change them) -----------------------------------------------
function Match.setting(player, key, value)
	if key == "synergy" then
		S.synergy = value == true
		feed("Synergy Mode " .. (S.synergy and "ON" or "OFF") .. " (" .. player.DisplayName .. ")")
	elseif key == "teams" then
		Match.teamsOn = value == true
		local sun, moon = ensureTeams()
		local i = 0
		for _, p in ipairs(Players:GetPlayers()) do
			if Match.teamsOn then
				p.Team = (i % 2 == 0) and sun or moon
				p.Neutral = false
			else
				p.Team = nil
				p.Neutral = true
			end
			i += 1
		end
		for _, f in pairs(S.fighters) do
			if f.player then
				f.team = Match.teamsOn and f.player.Team and f.player.Team.Name or nil
			elseif f.isBot then
				f.team = nil
				if Match.teamsOn then
					f.team = pickTeam()
				end
			end
		end
		feed("Teams " .. (Match.teamsOn and "ON (Sun vs Moon)" or "OFF (free-for-all)"))
	elseif key == "bots" then
		local n = tonumber(value)
		if n then
			Match.botTarget = math.clamp(math.floor(n), 0, Config.MAX_BOTS)
			Match.syncBots()
		end
	elseif key == "botKit" then
		local name = S.Kits.displayName(value)
		if name and Match.botCount() < Config.MAX_BOTS then
			Match.botTarget = math.min(Config.MAX_BOTS, Match.botTarget + 1)
			Match.spawnBot(name)
		end
	end
	setWorldAttrs()
end

function Match.init(r)
	remotes = r
	setWorldAttrs()
	Players.CharacterAutoLoads = false
	pcall(function()
		game:GetService("StarterPlayer").EnableMouseLockOption = false
	end)
	Players.RespawnTime = Config.RESPAWN_TIME
	for _, p in ipairs(Players:GetPlayers()) do
		Match.onPlayerAdded(p)
	end
	Players.PlayerAdded:Connect(Match.onPlayerAdded)
	for i = 1, #S.Arena.dummySpots do
		Match.spawnDummy(i)
	end
end

return Match
