-- Match flow.
--   Practice  : everyone trains in the Training Annex (dummies, optional sparring bot, free-cast toggle).
--   Countdown : entrants are placed in the arena spawn alcoves, frozen, resources reset.
--   Fight     : first to `koTarget` knockouts (or most KOs when the timer runs out) wins.
--   Results   : standings + MVP; Rematch restarts with the same settings, otherwise back to Practice.
-- Entrants (players and bots) keep their score across respawns. Bots are full fighters driven by Bots.luau.
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local S = require(script.Parent.S)
local Fighter = require(script.Parent.Fighter)

local Match = {}
S.Match = Match

local Config = S.Config
local remotes

Match.state = "Practice"
Match.phaseEnd = 0
Match.round = 0
Match.settings = {
	bots = 3,
	difficulty = "Normal",
	koTarget = 5,
	timeLimit = 300,
	teams = false,
	dummyMode = "Idle",
}
Match.entrants = {} -- key -> entrant
Match.dummies = {}
Match.teamsOn = false
Match.botTarget = 0 -- legacy field (Practice sparring bots)

local DIFFICULTIES = { Easy = true, Normal = true, Hard = true }
local DUMMY_MODES = { Idle = true, Guard = true, Strafe = true, Shoot = true }

-- Scoreboard replication: one Configuration per entrant with attributes.
local board = Instance.new("Folder")
board.Name = "Scoreboard"
board.Parent = ReplicatedStorage

local function setWorldAttrs()
	workspace:SetAttribute("MatchState", Match.state)
	workspace:SetAttribute("PhaseEnd", Match.phaseEnd)
	workspace:SetAttribute("KOTarget", Match.settings.koTarget)
	workspace:SetAttribute("TimeLimit", Match.settings.timeLimit)
	workspace:SetAttribute("BotCount", Match.settings.bots)
	workspace:SetAttribute("BotDifficulty", Match.settings.difficulty)
	workspace:SetAttribute("Teams", Match.settings.teams)
	workspace:SetAttribute("DummyMode", Match.settings.dummyMode)
	workspace:SetAttribute("Synergy", S.synergy == true)
	workspace:SetAttribute("Round", Match.round)
end

local function syncEntrant(e)
	local c = e.boardItem
	if not c then
		c = Instance.new("Configuration")
		c.Name = e.key
		c.Parent = board
		e.boardItem = c
	end
	c:SetAttribute("Name", e.name)
	c:SetAttribute("Kit", e.kit)
	c:SetAttribute("KOs", e.kos)
	c:SetAttribute("Deaths", e.deaths)
	c:SetAttribute("Damage", math.floor(e.damage + 0.5))
	c:SetAttribute("Team", e.team or "")
	c:SetAttribute("IsBot", e.isBot == true)
	c:SetAttribute("UserId", e.player and e.player.UserId or 0)
	c:SetAttribute("Alive", e.fighter ~= nil and not e.fighter.dead)
	c:SetAttribute("FighterId", e.fighter and e.fighter.id or 0)
	c:SetAttribute("InMatch", e.inMatch == true)
end

local function feed(data)
	if remotes then
		remotes.Feed:FireAllClients(data)
	end
end
Match.feed = feed

local function event(name, data)
	if remotes and remotes.MatchEvent then
		remotes.MatchEvent:FireAllClients(name, data)
	end
end

-- Teams ------------------------------------------------------------------------------------------
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

local function assignTeams()
	if not Match.settings.teams then
		for _, e in pairs(Match.entrants) do
			e.team = nil
			if e.player then
				e.player.Team = nil
				e.player.Neutral = true
			end
		end
		return
	end
	local sun, moon = ensureTeams()
	-- players first (alternating), then bots fill the smaller side
	local list = {}
	for _, e in pairs(Match.entrants) do
		table.insert(list, e)
	end
	table.sort(list, function(a, b)
		if (a.isBot == true) ~= (b.isBot == true) then
			return not a.isBot
		end
		return a.order < b.order
	end)
	local counts = { Sun = 0, Moon = 0 }
	for _, e in ipairs(list) do
		local t = counts.Sun <= counts.Moon and "Sun" or "Moon"
		counts[t] += 1
		e.team = t
		if e.player then
			e.player.Neutral = false
			e.player.Team = t == "Sun" and sun or moon
		end
	end
end

-- Characters -------------------------------------------------------------------------------------
local BODY_TONES = {
	Color3.fromRGB(234, 192, 160),
	Color3.fromRGB(198, 145, 110),
	Color3.fromRGB(141, 95, 70),
	Color3.fromRGB(96, 64, 48),
}

local function styledDescription(e)
	local desc = Instance.new("HumanoidDescription")
	local tone = BODY_TONES[(e.order % #BODY_TONES) + 1]
	local accent = S.Util.color(e.kit) or Color3.fromRGB(200, 200, 200)
	desc.HeadColor = tone
	desc.LeftArmColor = tone
	desc.RightArmColor = tone
	desc.TorsoColor = accent:Lerp(Color3.fromRGB(30, 30, 40), 0.35)
	desc.LeftLegColor = Color3.fromRGB(42, 44, 56)
	desc.RightLegColor = Color3.fromRGB(42, 44, 56)
	return desc
end

local function fallbackRig(color)
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.Parent = model
	local torso = Instance.new("Part")
	torso.Name = "UpperTorso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.Color = color
	torso.Parent = model
	local m = Instance.new("Motor6D")
	m.Name = "Waist"
	m.Part0 = root
	m.Part1 = torso
	m.C0 = CFrame.new(0, 0.5, 0)
	m.Parent = torso
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Color = color
	head.Parent = model
	local n = Instance.new("Motor6D")
	n.Name = "Neck"
	n.Part0 = torso
	n.Part1 = head
	n.C0 = CFrame.new(0, 1.6, 0)
	n.Parent = head
	local hum = Instance.new("Humanoid")
	hum.HipHeight = 2
	hum.Parent = model
	model.PrimaryPart = root
	return model
end

local function makeCharacter(e)
	local desc = e.desc
	if not desc then
		if e.player and e.player.UserId > 0 then
			local ok, d = pcall(function()
				return Players:GetHumanoidDescriptionFromUserId(e.player.UserId)
			end)
			if ok and d then
				desc = d
			end
		end
		desc = desc or styledDescription(e)
		e.desc = desc
	end
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		model = fallbackRig(S.Util.color(e.kit))
	end
	model.Name = e.name
	-- all fighters are animated by the procedural animator (client); drop stock scripts
	for _, n in ipairs({ "Animate", "Health" }) do
		local sc = model:FindFirstChild(n)
		if sc then
			sc:Destroy()
		end
	end
	return model
end

-- Spawn points -----------------------------------------------------------------------------------
local function enemyPositions(e)
	local out = {}
	for _, f in pairs(S.fighters) do
		if S.alive(f) and not f.isSummon and not f.isDummy and f.entrant ~= e then
			if not (e.team and f.team == e.team) then
				table.insert(out, f.root.Position)
			end
		end
	end
	return out
end

local function pickArenaSpawn(e)
	local spawns = S.Arena.spawns
	local enemies = enemyPositions(e)
	local best, bestScore
	for _, sp in ipairs(spawns) do
		local pos = sp.Position
		local nearest = 400
		for _, p in ipairs(enemies) do
			nearest = math.min(nearest, (p - pos).Magnitude)
		end
		local score = nearest + math.random() * 25
		-- team play: prefer the team's half
		if e.team and sp.team and sp.team ~= e.team then
			score -= 120
		end
		if not bestScore or score > bestScore then
			best, bestScore = sp, score
		end
	end
	return best and best.cf or CFrame.new(0, 3, 0)
end

local function pickAnnexSpawn()
	local a = S.Arena.annex
	local base = a and a.spawn or CFrame.new(0, 3, 0)
	local off = Vector3.new(math.random(-6, 6), 0, math.random(-3, 3))
	return base + off
end

-- Entrants ----------------------------------------------------------------------------------------
local orderCounter = 0
local function newEntrant(key, opts)
	orderCounter += 1
	local e = {
		key = key,
		order = orderCounter,
		name = opts.name,
		player = opts.player,
		isBot = opts.isBot,
		kit = opts.kit or Config.DEFAULT_KIT,
		kos = 0,
		deaths = 0,
		damage = 0,
		bestHit = 0,
		team = nil,
		fighter = nil,
		inMatch = false,
		spar = opts.spar,
		difficulty = opts.difficulty,
		freeCast = false,
	}
	Match.entrants[key] = e
	syncEntrant(e)
	return e
end

local function removeEntrant(e)
	if e.fighter then
		local f = e.fighter
		e.fighter = nil
		Fighter.remove(f)
		if f.model and not f.player then
			f.model:Destroy()
		end
	end
	if e.boardItem then
		e.boardItem:Destroy()
		e.boardItem = nil
	end
	Match.entrants[e.key] = nil
end

local function despawn(e)
	local f = e.fighter
	if not f then
		return
	end
	e.fighter = nil
	Fighter.remove(f)
	if f.model then
		f.model:Destroy()
	end
end

-- snap a spawn frame onto the walkable surface beneath it (never inside geometry)
local function onGround(cf)
	local res = workspace:Raycast(cf.Position + Vector3.new(0, 40, 0), Vector3.new(0, -90, 0), S.Hit.arenaParams)
	if res then
		return CFrame.new(res.Position) * cf.Rotation
	end
	return cf
end

local function spawnEntrant(e, cf)
	despawn(e)
	cf = onGround(cf)
	if e.player and not e.player.Parent then
		return nil
	end
	local model = makeCharacter(e)
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	model:PivotTo(cf + Vector3.new(0, 3.2, 0))
	if e.player then
		e.player.Character = model
		model.Parent = workspace
		if root then
			pcall(function()
				root:SetNetworkOwner(e.player)
			end)
		end
	else
		model.Parent = S.folders.Bots
		if root then
			pcall(function()
				root:SetNetworkOwner(nil)
			end)
		end
	end
	local f = Fighter.new(model, {
		player = e.player,
		isBot = e.isBot,
		kit = e.kit,
		team = e.team,
		name = e.name,
	})
	f.entrant = e
	f.botDifficulty = e.difficulty or Match.settings.difficulty
	e.fighter = f
	f.invulnUntil = S.now() + Config.SPAWN_PROTECTION
	f.spawnProtected = true
	model:SetAttribute("SpawnProtected", S.now() + Config.SPAWN_PROTECTION)
	model:SetAttribute("Team", e.team or "")
	model:SetAttribute("IsBot", e.isBot == true)
	model:SetAttribute("EntrantKey", e.key)
	if Match.state == "Countdown" or Match.state == "Results" and e.inMatch then
		f.frozen = true
	end
	local hum = f.humanoid
	if hum then
		hum.Died:Connect(function()
			if not f.dead then
				Fighter.kill(f, f.lastDamager)
			end
		end)
	end
	syncEntrant(e)
	return f
end
Match.spawnEntrant = spawnEntrant

local function placeEntrant(e)
	if (Match.state == "Fight" or Match.state == "Countdown") and e.inMatch then
		return spawnEntrant(e, pickArenaSpawn(e))
	end
	return spawnEntrant(e, pickAnnexSpawn())
end

-- casting or attacking ends spawn protection early
S.on("cast", function(f)
	if f.spawnProtected then
		f.spawnProtected = false
		f.invulnUntil = 0
		if f.model then
			f.model:SetAttribute("SpawnProtected", 0)
		end
	end
end)

-- Players -----------------------------------------------------------------------------------------
local function playerKey(player)
	return "p" .. tostring(player.UserId) .. "_" .. player.Name
end

function Match.entrantFor(player)
	return Match.entrants[playerKey(player)]
end

function Match.onPlayerAdded(player)
	pcall(function()
		player.DevEnableMouseLock = false
	end)
	local kit = player:GetAttribute("Kit") or Config.DEFAULT_KIT
	player:SetAttribute("Kit", kit)
	local e = newEntrant(playerKey(player), { name = player.DisplayName, player = player, kit = kit })
	if Match.state == "Fight" or Match.state == "Countdown" then
		e.inMatch = true
		assignTeams()
	end
	task.defer(function()
		if player.Parent then
			placeEntrant(e)
		end
	end)
end

local function onPlayerRemoving(player)
	local e = Match.entrants[playerKey(player)]
	if e then
		removeEntrant(e)
	end
end

-- Kit selection: swaps immediately when out of combat, otherwise on respawn.
function Match.selectKit(player, name)
	local display = S.Kits.displayName(name)
	if not display then
		return
	end
	player:SetAttribute("Kit", display)
	local e = Match.entrantFor(player)
	if e then
		e.kit = display
		syncEntrant(e)
	end
	local f = Fighter.forPlayer(player)
	if not f or f.dead then
		return
	end
	local now = S.now()
	local inCombat = Match.state ~= "Practice" and (now - (f.lastContest or 0) < 5 or now - (f.lastHit or 0) < 5)
	if inCombat or S.Cast.isBusy(f) or f.formActive then
		S.Cast.notify(f, display .. " equips on respawn (in combat)")
		return
	end
	Match.swapKit(f, display)
	S.Cast.notify(f, "Equipped " .. display)
end

function Match.swapKit(f, display)
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
end

-- Bots --------------------------------------------------------------------------------------------
local BOT_NAMES = { "Vesper", "Orrin", "Kestrel", "Sable", "Ione", "Corvid", "Lumen", "Thane", "Nyx", "Rook", "Halcyon", "Ember" }
local botSerial = 0

local function botKitChoice()
	-- variety without repeats inside one match
	local used = {}
	for _, e in pairs(Match.entrants) do
		used[e.kit] = true
	end
	local pinned = Match.nextBotKit
	if pinned then
		Match.nextBotKit = nil
		return pinned
	end
	for _ = 1, 20 do
		local k = S.Kits.random()
		if not used[k] then
			return k
		end
	end
	return S.Kits.random()
end

local function addBot(opts)
	botSerial += 1
	local kit = opts.kit or botKitChoice()
	local name = BOT_NAMES[(botSerial - 1) % #BOT_NAMES + 1]
	local e = newEntrant("b" .. botSerial, {
		name = name .. " (Bot)",
		isBot = true,
		kit = kit,
		spar = opts.spar,
		difficulty = opts.difficulty,
	})
	return e
end

local function removeBots(filter)
	for _, e in pairs(table.clone(Match.entrants)) do
		if e.isBot and (filter == nil or filter(e)) then
			removeEntrant(e)
		end
	end
end

-- smoke-test / tooling helper: a free-standing bot fighter that is not part of the match
function Match.spawnBot(kitName)
	local e = addBot({ kit = kitName or S.Kits.random(), spar = true })
	local f = spawnEntrant(e, pickAnnexSpawn())
	return f
end

function Match.botCount()
	local n = 0
	for _, e in pairs(Match.entrants) do
		if e.isBot then
			n += 1
		end
	end
	return n
end

-- Dummies -----------------------------------------------------------------------------------------
function Match.spawnDummy(i)
	local spots = S.Arena.annex and S.Arena.annex.dummySpots or S.Arena.dummySpots
	local spot = spots and spots[i]
	if not spot then
		return
	end
	local e = { order = i, kit = "Normal", name = "Training Dummy" }
	local desc = Instance.new("HumanoidDescription")
	local straw = Color3.fromRGB(196, 168, 112)
	desc.HeadColor = straw
	desc.TorsoColor = Color3.fromRGB(150, 110, 70)
	desc.LeftArmColor = straw
	desc.RightArmColor = straw
	desc.LeftLegColor = Color3.fromRGB(120, 90, 60)
	desc.RightLegColor = Color3.fromRGB(120, 90, 60)
	e.desc = desc
	local model = makeCharacter(e)
	model.Name = "Training Dummy " .. i
	local face = S.Arena.annex and S.Arena.annex.dummyFacing or Vector3.new(0, 0, 1)
	local p = spot + Vector3.new(0, 3.2, 0)
	model:PivotTo(CFrame.lookAt(p, p + face))
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
	f.dummyHome = spot
	f.noGuard = Match.settings.dummyMode ~= "Guard"
	model:SetAttribute("IsDummy", true)
	Match.dummies[i] = f
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

-- Phases ------------------------------------------------------------------------------------------
local function setState(name, dur)
	Match.state = name
	Match.phaseEnd = dur and (S.now() + dur) or 0
	setWorldAttrs()
	event("state", { state = name, phaseEnd = Match.phaseEnd, round = Match.round })
end

local function resetEntrantScore(e)
	e.kos, e.deaths, e.damage, e.bestHit = 0, 0, 0, 0
	syncEntrant(e)
end

function Match.startMatch(byPlayer)
	if Match.state ~= "Practice" and Match.state ~= "Results" then
		return
	end
	Match.round += 1
	-- roster: all players + configured bots
	removeBots()
	for _, e in pairs(Match.entrants) do
		e.inMatch = true
		resetEntrantScore(e)
	end
	for _ = 1, Match.settings.bots do
		local b = addBot({ difficulty = Match.settings.difficulty })
		b.inMatch = true
	end
	assignTeams()
	setState("Countdown", 4)
	for _, e in pairs(Match.entrants) do
		local f = spawnEntrant(e, pickArenaSpawn(e))
		if f then
			f.frozen = true
			f.invulnUntil = Match.phaseEnd + Config.SPAWN_PROTECTION
		end
	end
	feed({ kind = "info", text = (byPlayer and byPlayer.DisplayName .. " started" or "Match") .. " — first to " .. Match.settings.koTarget .. " KOs" })
end

local function beginFight()
	setState("Fight", Match.settings.timeLimit)
	for _, e in pairs(Match.entrants) do
		local f = e.fighter
		if f then
			f.frozen = false
			f.invulnUntil = S.now() + 1
		end
	end
	event("fight", {})
end

local function standings()
	local list = {}
	for _, e in pairs(Match.entrants) do
		if e.inMatch then
			table.insert(list, e)
		end
	end
	table.sort(list, function(a, b)
		if a.kos ~= b.kos then
			return a.kos > b.kos
		end
		if a.deaths ~= b.deaths then
			return a.deaths < b.deaths
		end
		return a.damage > b.damage
	end)
	return list
end
Match.standings = standings

local function endMatch(reason)
	if Match.state ~= "Fight" then
		return
	end
	local list = standings()
	local rows = {}
	local winnerText
	if Match.settings.teams then
		local score = { Sun = 0, Moon = 0 }
		for _, e in ipairs(list) do
			if e.team then
				score[e.team] += e.kos
			end
		end
		if score.Sun == score.Moon then
			winnerText = "Draw"
		else
			winnerText = (score.Sun > score.Moon and "Team Sun" or "Team Moon") .. " wins"
		end
	else
		local top = list[1]
		local second = list[2]
		if top and second and top.kos == second.kos and top.deaths == second.deaths then
			winnerText = "Draw"
		elseif top then
			winnerText = top.name .. " wins"
		end
	end
	local mvp, mvpScore
	for i, e in ipairs(list) do
		local score = e.kos * 3 - e.deaths + e.damage / 400
		if not mvpScore or score > mvpScore then
			mvp, mvpScore = e, score
		end
		rows[i] = {
			name = e.name,
			kit = e.kit,
			kos = e.kos,
			deaths = e.deaths,
			damage = math.floor(e.damage + 0.5),
			bestHit = math.floor(e.bestHit + 0.5),
			team = e.team or "",
			isBot = e.isBot == true,
			userId = e.player and e.player.UserId or 0,
		}
	end
	setState("Results", 15)
	for _, e in pairs(Match.entrants) do
		local f = e.fighter
		if f and not f.dead then
			f.frozen = true
			f.invulnUntil = math.huge
			if S.Cast.isBusy(f) and f.action then
				f.action.interrupted = true
			end
		end
	end
	workspace:SetAttribute("Winner", winnerText or "")
	event("results", {
		winner = winnerText or "",
		reason = reason,
		rows = rows,
		mvp = mvp and mvp.name or "",
		teams = Match.settings.teams,
	})
end
Match.endMatch = endMatch

function Match.returnToPractice()
	removeBots(function(e)
		return not e.spar
	end)
	for _, e in pairs(Match.entrants) do
		e.inMatch = false
	end
	setState("Practice")
	for _, e in pairs(Match.entrants) do
		if e.player then
			spawnEntrant(e, pickAnnexSpawn())
		end
	end
	for _, e in pairs(Match.entrants) do
		syncEntrant(e)
	end
end

-- Defeat / respawn --------------------------------------------------------------------------------
S.on("damaged", function(target, info)
	local src = info.src
	local real = src and (src.owner or src)
	local e = real and real.entrant
	if e and target ~= real and not target.isSummon then
		local amt = (info.final or 0) + (info.absorbed or 0)
		e.damage += amt
		if amt > e.bestHit then
			e.bestHit = amt
		end
		e.dirty = true
	end
end)

S.on("defeated", function(f, killer)
	if f.isSummon then
		return
	end
	local e = f.entrant
	local real = killer and (killer.owner or killer) or nil
	if real == f then
		real = nil
	end
	local ke = real and real.entrant
	local counted = Match.state == "Fight" and e ~= nil and e.inMatch
	if counted then
		e.deaths += 1
		syncEntrant(e)
		if ke and ke ~= e and ke.inMatch and not (ke.team and ke.team == e.team) then
			ke.kos += 1
			syncEntrant(ke)
		end
	end
	if not f.isDummy then
		feed({
			kind = "ko",
			killer = real and real.name or "",
			killerKit = real and real.kitName or "",
			killerTeam = real and real.team or "",
			killerId = real and real.id or 0,
			victim = f.name,
			victimKit = f.kitName or "",
			victimTeam = f.team or "",
			victimId = f.id,
		})
	end
	if f.isDummy then
		task.delay(2.5, function()
			Fighter.remove(f)
			if f.model then
				f.model:Destroy()
			end
			if Match.dummies[f.dummyIndex] == f then
				Match.spawnDummy(f.dummyIndex)
			end
		end)
		return
	end
	if not e then
		task.delay(3, function()
			Fighter.remove(f)
			if f.model then
				f.model:Destroy()
			end
		end)
		return
	end
	-- win check
	if counted and ke and Match.state == "Fight" then
		local target = Match.settings.koTarget
		if Match.settings.teams and ke.team then
			local sum = 0
			for _, x in pairs(Match.entrants) do
				if x.team == ke.team and x.inMatch then
					sum += x.kos
				end
			end
			if sum >= target then
				task.delay(0.6, endMatch, "ko")
			end
		elseif ke.kos >= target then
			task.delay(0.6, endMatch, "ko")
		end
	end
	local round = Match.round
	local respawnAt = Config.RESPAWN_TIME
	if e.player then
		e.player:SetAttribute("RespawnAt", S.now() + respawnAt)
	end
	task.delay(respawnAt, function()
		if e.fighter ~= f then
			return -- already respawned by a phase change
		end
		if Match.entrants[e.key] ~= e then
			despawn(e)
			return
		end
		if Match.round ~= round and Match.state ~= "Practice" then
			return
		end
		placeEntrant(e)
	end)
end)

-- Settings ----------------------------------------------------------------------------------------
function Match.setting(player, key, value)
	local s = Match.settings
	local e = Match.entrantFor(player)
	if key == "start" then
		Match.startMatch(player)
	elseif key == "rematch" then
		if Match.state == "Results" then
			Match.startMatch(player)
		end
	elseif key == "practice" then
		if Match.state == "Results" or Match.state == "Fight" or Match.state == "Countdown" then
			if Match.state == "Fight" then
				feed({ kind = "info", text = player.DisplayName .. " ended the match" })
				endMatch("ended")
			end
			Match.returnToPractice()
		end
	elseif key == "synergy" then
		S.synergy = value == true
	elseif key == "teams" then
		if Match.state == "Practice" or Match.state == "Results" then
			s.teams = value == true
			Match.teamsOn = s.teams
		end
	elseif key == "bots" then
		local n = tonumber(value)
		if n then
			s.bots = math.clamp(math.floor(n), 0, Config.MAX_BOTS)
		end
	elseif key == "difficulty" then
		if type(value) == "string" and DIFFICULTIES[value] then
			s.difficulty = value
			for _, x in pairs(Match.entrants) do
				if x.isBot then
					x.difficulty = value
					if x.fighter then
						x.fighter.botDifficulty = value
					end
				end
			end
		end
	elseif key == "koTarget" then
		local n = tonumber(value)
		if n and Match.state ~= "Fight" then
			s.koTarget = math.clamp(math.floor(n), 1, 50)
		end
	elseif key == "timeLimit" then
		local n = tonumber(value)
		if n and Match.state ~= "Fight" then
			s.timeLimit = math.clamp(math.floor(n), 60, 1200)
		end
	elseif key == "dummyMode" then
		if type(value) == "string" and DUMMY_MODES[value] then
			s.dummyMode = value
			for _, d in pairs(Match.dummies) do
				d.noGuard = value ~= "Guard"
			end
		end
	elseif key == "freeCast" then
		if e then
			e.freeCast = value == true
		end
	elseif key == "fillProxima" then
		local f = e and e.fighter
		if f and Match.state == "Practice" and S.alive(f) then
			f.proxima = Config.MAX_PROXIMA
			f.heat = math.max(f.heat, Config.UNSTABLE_MIN_HEAT + 5)
			f.lastAbilityUse = S.now()
		end
	elseif key == "spar" or key == "botKit" then
		if Match.state ~= "Practice" then
			if key == "botKit" then
				local name = S.Kits.displayName(value)
				if name then
					Match.nextBotKit = name
				end
			end
			return setWorldAttrs()
		end
		local sparCount = 0
		for _, x in pairs(Match.entrants) do
			if x.isBot and x.spar then
				sparCount += 1
			end
		end
		if value == false then
			removeBots(function(x)
				return x.spar
			end)
		elseif sparCount < 2 then
			local name = type(value) == "string" and S.Kits.displayName(value) or nil
			local b = addBot({ kit = name, spar = true, difficulty = s.difficulty })
			spawnEntrant(b, pickAnnexSpawn())
		end
	end
	setWorldAttrs()
end

-- Main loop ---------------------------------------------------------------------------------------
local acc = 0
local function step(dt)
	acc += dt
	if acc < 0.2 then
		return
	end
	acc = 0
	local now = S.now()
	if Match.state == "Countdown" and now >= Match.phaseEnd then
		beginFight()
	elseif Match.state == "Fight" and now >= Match.phaseEnd then
		endMatch("time")
	elseif Match.state == "Results" and now >= Match.phaseEnd then
		Match.returnToPractice()
	end
	for _, e in pairs(Match.entrants) do
		local f = e.fighter
		if f and S.alive(f) then
			-- practice: free cast keeps resources topped up
			if e.freeCast and Match.state == "Practice" then
				f.energy = Config.MAX_ENERGY
				for i = 1, 4 do
					if f.cooldowns[i] > now + 0.3 then
						S.Cast.setCooldown(f, i, 0.3)
					end
				end
			end
			if f.spawnProtected and (f.invulnUntil or 0) <= now then
				f.spawnProtected = false
				f.model:SetAttribute("SpawnProtected", 0)
			end
		end
		if e.dirty then
			e.dirty = false
			syncEntrant(e)
		end
	end
	-- dummies reset to full health 4 seconds after their last hit
	for _, d in pairs(Match.dummies) do
		if S.alive(d) and now - (d.lastHit or 0) > 4 and d.health < d.maxHealth then
			d.health = d.maxHealth
			d.shields = {}
			Fighter.syncHealth(d)
		end
	end
end

function Match.init(r)
	remotes = r
	Players.CharacterAutoLoads = false
	pcall(function()
		game:GetService("StarterPlayer").EnableMouseLockOption = false
	end)
	Players.RespawnTime = Config.RESPAWN_TIME
	setWorldAttrs()
	for _, p in ipairs(Players:GetPlayers()) do
		Match.onPlayerAdded(p)
	end
	Players.PlayerAdded:Connect(Match.onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	local spots = S.Arena.annex and S.Arena.annex.dummySpots or S.Arena.dummySpots
	for i = 1, #spots do
		Match.spawnDummy(i)
	end
	RunService.Heartbeat:Connect(step)
end

return Match
