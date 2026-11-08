-- Soundscape. PLACEHOLDER SOURCE AUDIO: no custom audio assets ship with this project, so every sound is
-- built from Roblox's built-in engine samples (rbxasset://sounds/...) layered, pitch-shifted and filtered
-- per element family. Swap SAMPLES / BANK entries for real assets without touching call sites.
-- Features: sound groups (effects / ambience / UI) bound to Settings, spatial emitters (pooled), voice
-- limits per sound and globally, subtle pitch/volume variation, distance culling.
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

local Audio = {}
local ctx, Settings

local SAMPLES = {
	slash = "rbxasset://sounds/swordslash.wav",
	lunge = "rbxasset://sounds/swordlunge.wav",
	unsheath = "rbxasset://sounds/unsheath.wav",
	shot = "rbxasset://sounds/Rocket shot.wav",
	whoosh = "rbxasset://sounds/Rocket whoosh.wav",
	collide = "rbxasset://sounds/collide.wav",
	ping = "rbxasset://sounds/electronicpingshort.wav",
	glass = "rbxasset://sounds/glassbreak.wav",
	jump = "rbxasset://sounds/action_jump.mp3",
	land = "rbxasset://sounds/action_jump_land.mp3",
	falling = "rbxasset://sounds/action_falling.mp3",
	step = "rbxasset://sounds/action_footsteps_plastic.mp3",
	getup = "rbxasset://sounds/action_get_up.mp3",
	swim = "rbxasset://sounds/action_swim.mp3",
	water = "rbxasset://sounds/impact_water.mp3",
	splat = "rbxasset://sounds/splat.wav",
	snap = "rbxasset://sounds/snap.wav",
}

-- layer = { sample, pitch, volume, delay? }
local function L(sample, pitch, volume, delay)
	return { sample, pitch, volume, delay or 0 }
end

-- family sound sets: charge (windup), release, travel (loop), impact, big (extra low layer)
local FAMILY = {
	flame = { charge = { L("whoosh", 0.55, 0.22) }, release = { L("shot", 0.95, 0.45), L("lunge", 0.7, 0.25) }, travel = L("whoosh", 0.9, 0.12), impact = { L("collide", 0.6, 0.5), L("shot", 0.55, 0.35) } },
	frost = { charge = { L("ping", 0.45, 0.14), L("whoosh", 1.5, 0.08) }, release = { L("unsheath", 1.35, 0.35), L("glass", 1.7, 0.16) }, travel = L("whoosh", 1.7, 0.08), impact = { L("glass", 1.05, 0.45), L("snap", 1.4, 0.25) } },
	storm = { charge = { L("ping", 0.75, 0.16), L("snap", 2.0, 0.12, 0.08) }, release = { L("snap", 0.6, 0.5), L("ping", 1.45, 0.25) }, travel = L("whoosh", 2.1, 0.06), impact = { L("snap", 0.5, 0.55), L("collide", 1.25, 0.3) } },
	tide = { charge = { L("swim", 0.9, 0.18) }, release = { L("water", 1.25, 0.4) }, travel = L("swim", 1.3, 0.08), impact = { L("water", 0.9, 0.5), L("splat", 0.9, 0.3) } },
	gale = { charge = { L("whoosh", 1.2, 0.15) }, release = { L("lunge", 1.2, 0.45), L("whoosh", 1.5, 0.15) }, travel = L("whoosh", 1.3, 0.1), impact = { L("lunge", 0.8, 0.4), L("whoosh", 0.9, 0.2) } },
	stone = { charge = { L("whoosh", 0.4, 0.2) }, release = { L("slash", 0.6, 0.4), L("collide", 0.55, 0.3) }, travel = L("whoosh", 0.6, 0.1), impact = { L("collide", 0.45, 0.6), L("land", 0.6, 0.45) } },
	gravity = { charge = { L("whoosh", 0.38, 0.25), L("ping", 0.4, 0.08) }, release = { L("shot", 0.5, 0.45), L("whoosh", 0.45, 0.2) }, travel = L("whoosh", 0.5, 0.12), impact = { L("collide", 0.38, 0.6), L("ping", 0.38, 0.22) } },
	radiant = { charge = { L("ping", 1.2, 0.16), L("ping", 1.8, 0.08, 0.12) }, release = { L("ping", 1.6, 0.35), L("unsheath", 1.6, 0.3) }, travel = L("whoosh", 1.9, 0.06), impact = { L("ping", 1.0, 0.4), L("glass", 2.0, 0.15) } },
	verdant = { charge = { L("swim", 1.4, 0.12) }, release = { L("slash", 1.25, 0.35), L("snap", 1.4, 0.2) }, travel = L("whoosh", 1.4, 0.06), impact = { L("splat", 1.2, 0.4), L("snap", 0.8, 0.3) } },
	eldritch = { charge = { L("whoosh", 0.6, 0.16), L("ping", 0.55, 0.1) }, release = { L("ping", 0.6, 0.35), L("lunge", 0.6, 0.3) }, travel = L("whoosh", 0.7, 0.08), impact = { L("ping", 0.45, 0.4), L("collide", 0.8, 0.3) } },
}
Audio.FAMILY = FAMILY

-- named one-shots
local BANK = {
	swing = { L("slash", 1.0, 0.35) },
	lunge = { L("lunge", 1.0, 0.35) },
	shoot = { L("shot", 1.0, 0.3) },
	hit = { L("collide", 1.0, 0.35) },
	ping = { L("ping", 1.0, 0.3) },
	unsheath = { L("unsheath", 1.0, 0.3) },
	guardUp = { L("unsheath", 0.8, 0.18) },
	block = { L("collide", 1.6, 0.4), L("unsheath", 1.3, 0.25) },
	perfect = { L("ping", 2.0, 0.4), L("unsheath", 1.8, 0.35), L("glass", 2.4, 0.12, 0.03) },
	shieldHit = { L("glass", 2.0, 0.18), L("ping", 1.25, 0.25) },
	evade = { L("lunge", 1.6, 0.25) },
	dash = { L("lunge", 1.35, 0.32), L("whoosh", 1.8, 0.1) },
	dodge = { L("lunge", 1.6, 0.35), L("whoosh", 2.2, 0.12) },
	jump = { L("jump", 1.0, 0.3) },
	land = { L("land", 1.0, 0.35) },
	step = { L("step", 1.0, 0.18) },
	death = { L("collide", 0.5, 0.5), L("whoosh", 0.42, 0.3), L("getup", 0.6, 0.15, 0.25) },
	respawn = { L("ping", 1.0, 0.25), L("ping", 1.5, 0.22, 0.12), L("ping", 2.0, 0.18, 0.24) },
	status = { L("ping", 0.7, 0.14) },
	guardBreak = { L("glass", 0.8, 0.45), L("collide", 0.6, 0.4) },
	ultCharge = { L("whoosh", 0.35, 0.45), L("ping", 0.5, 0.2, 0.2) },
	ultRelease = { L("shot", 0.45, 0.7), L("collide", 0.35, 0.6), L("whoosh", 0.6, 0.35) },
	-- UI (non-spatial)
	uiHover = { L("ping", 2.4, 0.06) },
	uiClick = { L("snap", 1.6, 0.25) },
	uiOpen = { L("whoosh", 2.4, 0.12) },
	countdown = { L("ping", 1.0, 0.35) },
	fight = { L("ping", 1.5, 0.4), L("shot", 1.2, 0.35) },
	ko = { L("snap", 0.9, 0.35), L("ping", 1.2, 0.3, 0.05) },
	victory = { L("ping", 1.0, 0.35), L("ping", 1.26, 0.35, 0.14), L("ping", 1.5, 0.35, 0.28), L("ping", 2.0, 0.4, 0.42) },
	defeat = { L("ping", 0.8, 0.3), L("ping", 0.6, 0.3, 0.2) },
	hitmarker = { L("snap", 2.2, 0.16) },
}
Audio.BANK = BANK

local groups = {}
local emitters = {} -- pooled anchored parts with an attachment
local active = {} -- sound -> { key, t }
local activeCount = 0
local perKey = {}
local MAX_VOICES = 28
local MAX_PER_KEY = 4
local rng = Random.new()

local function group(name)
	local g = SoundService:FindFirstChild(name)
	if not g then
		g = Instance.new("SoundGroup")
		g.Name = name
		g.Parent = SoundService
	end
	return g
end

local function applyVolumes()
	local master = Settings.get("MasterVolume")
	groups.SFX.Volume = master * Settings.get("SfxVolume")
	groups.Ambience.Volume = master * Settings.get("AmbienceVolume")
	groups.UI.Volume = master * Settings.get("UIVolume")
end

local folder
local function emitter()
	local e = table.remove(emitters)
	if e then
		return e
	end
	local p = Instance.new("Part")
	p.Name = "SoundEmitter"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Parent = folder
	return p
end

local function listenerPos()
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame.Position or Vector3.zero
end

local function finish(s, holder)
	if active[s] then
		local key = active[s].key
		active[s] = nil
		activeCount -= 1
		perKey[key] = math.max(0, (perKey[key] or 1) - 1)
	end
	s:Destroy()
	if holder then
		holder.CFrame = CFrame.new(0, -5000, 0)
		table.insert(emitters, holder)
	end
end

-- play one layer. where = Vector3 (spatial), Instance (attached) or nil (2D UI/ambient)
local function playLayer(layer, where, volMul, pitchMul, grp, key)
	local id = SAMPLES[layer[1]]
	if not id then
		return
	end
	if activeCount >= MAX_VOICES then
		-- drop the quietest new layer rather than cutting existing ones
		if layer[3] * volMul < 0.25 then
			return
		end
	end
	if (perKey[key] or 0) >= MAX_PER_KEY then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = layer[3] * volMul * rng:NextNumber(0.9, 1.08)
	s.PlaybackSpeed = layer[2] * pitchMul * rng:NextNumber(0.95, 1.05)
	s.SoundGroup = grp
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 14
	s.RollOffMaxDistance = 240
	local holder
	if typeof(where) == "Vector3" then
		holder = emitter()
		holder.CFrame = CFrame.new(where)
		s.Parent = holder
	elseif typeof(where) == "Instance" and where.Parent then
		s.Parent = where
	else
		s.Parent = grp
	end
	active[s] = { key = key, t = os.clock() }
	activeCount += 1
	perKey[key] = (perKey[key] or 0) + 1
	s.Ended:Connect(function()
		finish(s, holder)
	end)
	s:Play()
	-- safety cleanup if Ended never fires
	task.delay(4 / math.max(0.3, s.PlaybackSpeed), function()
		if s.Parent then
			finish(s, holder)
		end
	end)
	return s
end

local function playLayers(layers, where, volMul, pitchMul, grp, key)
	if typeof(where) == "Vector3" and (where - listenerPos()).Magnitude > 260 then
		return
	end
	for _, layer in ipairs(layers) do
		if layer[4] and layer[4] > 0 then
			task.delay(layer[4], playLayer, layer, where, volMul, pitchMul, grp, key .. layer[1])
		else
			playLayer(layer, where, volMul, pitchMul, grp, key .. layer[1])
		end
	end
end

-- named sound from the bank
function Audio.play(name, where, volume, pitch)
	local layers = BANK[name]
	if not layers then
		return
	end
	local grp = name:sub(1, 2) == "ui" and groups.UI or groups.SFX
	if name == "countdown" or name == "fight" or name == "ko" or name == "victory" or name == "defeat" or name == "hitmarker" then
		grp = groups.UI
	end
	playLayers(layers, where, volume or 1, pitch or 1, grp, name)
end

-- family sound: stage = "charge" | "release" | "impact"
function Audio.family(style, stage, where, volume, pitch)
	local fam = FAMILY[style and style.sound or "eldritch"] or FAMILY.eldritch
	local layers = fam[stage]
	if not layers then
		return
	end
	playLayers(layers, where, volume or 1, pitch or 1, groups.SFX, (style and style.sound or "x") .. stage)
end

-- looping travel sound attached to a moving part; returns the Sound (caller destroys it)
function Audio.loop(style, part, volume)
	local fam = FAMILY[style and style.sound or "eldritch"] or FAMILY.eldritch
	local layer = fam.travel
	if not layer or not part then
		return nil
	end
	if activeCount >= MAX_VOICES - 4 then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = SAMPLES[layer[1]]
	s.Looped = true
	s.Volume = layer[3] * (volume or 1)
	s.PlaybackSpeed = layer[2] * rng:NextNumber(0.95, 1.05)
	s.SoundGroup = groups.SFX
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 8
	s.RollOffMaxDistance = 120
	s.Parent = part
	s:Play()
	return s
end

-- legacy server sound names (FX.sound) map onto the bank
local LEGACY = { swing = "swing", lunge = "lunge", shoot = "shoot", hit = "hit", ping = "ping", unsheath = "unsheath" }
function Audio.legacy(name, where, volume)
	local n = LEGACY[name]
	if n then
		Audio.play(n, where, (volume or 0.4) / 0.35)
	end
end

-- Ambience: observatory wind bed, slow orrery hum, sparse distant chimes ----------------------------
local ambience = {}
local function startAmbience()
	local function bed(sample, pitch, volume)
		local s = Instance.new("Sound")
		s.SoundId = SAMPLES[sample]
		s.Looped = true
		s.Volume = volume
		s.PlaybackSpeed = pitch
		s.SoundGroup = groups.Ambience
		s.Parent = groups.Ambience
		s:Play()
		table.insert(ambience, s)
		return s
	end
	bed("whoosh", 0.32, 0.22)
	bed("swim", 0.45, 0.06)
	task.spawn(function()
		while true do
			task.wait(rng:NextNumber(7, 14))
			playLayer(L("ping", rng:NextNumber(0.42, 0.62), 0.05), nil, 1, 1, groups.Ambience, "chime")
		end
	end)
end

-- spatial ambience source (e.g. the orrery); returns the sound
function Audio.ambientAt(part, sample, pitch, volume)
	local s = Instance.new("Sound")
	s.SoundId = SAMPLES[sample] or SAMPLES.whoosh
	s.Looped = true
	s.Volume = volume or 0.2
	s.PlaybackSpeed = pitch or 0.3
	s.SoundGroup = groups.Ambience
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 20
	s.RollOffMaxDistance = 180
	s.Parent = part
	s:Play()
	return s
end

function Audio.stats()
	return { active = activeCount, pooledEmitters = #emitters }
end

function Audio.init(c)
	ctx = c
	Settings = c.Settings
	groups.SFX = group("EB_SFX")
	groups.Ambience = group("EB_Ambience")
	groups.UI = group("EB_UI")
	if not groups.Ambience:FindFirstChildOfClass("EqualizerSoundEffect") then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.HighGain = -8
		eq.MidGain = -2
		eq.LowGain = 2
		eq.Parent = groups.Ambience
	end
	folder = Instance.new("Folder")
	folder.Name = "EBSoundEmitters"
	folder.Parent = workspace
	applyVolumes()
	Settings.onChanged(function(key)
		if key:find("Volume") then
			applyVolumes()
		end
	end)
	startAmbience()
	local _ = RunService
end

return Audio
