-- Services and global environment for the emulator.
local R = ...
local P, def = R.P, R.defineClass
local DATA = R.DATA
local v3 = R.v3

R.services = {}
R.latency = 0.03 -- one-way remote latency (seconds)
R.viewport = R.v2(1280, 720)
R.guiInset = 58

local SERVICE_CLASSES = {}
local function service(name, super, defn)
	defn = defn or {}
	defn.creatable = false
	def(name, super or "Instance", defn)
	SERVICE_CLASSES[name] = true
end

function R.getService(name)
	local s = R.services[name]
	if s then
		return s
	end
	if not SERVICE_CLASSES[name] then
		error("'" .. tostring(name) .. "' is not a valid Service name", 3)
	end
	s = R.new(name)
	s.Name = name
	R.services[name] = s
	R.setParent(s, DATA[s], R.game)
	return s
end

---------------------------------------------------------------- Workspace
service("Workspace", "Model", {
	props = {
		Gravity = P("number", 196.2), FallenPartsDestroyHeight = P("number", -500), StreamingEnabled = P("boolean", false),
		CurrentCamera = P("Instance", nil, { class = "Camera" }), DistributedGameTime = P("number", 0), SignalBehavior = P("any"),
		Retargeting = P("any"), TouchesUseCollisionGroups = P("boolean", false), AirDensity = P("number", 0.0012), GlobalWind = P("Vector3", v3(0, 0, 0)),
		Terrain = { t = "Instance", readonly = true, get = function()
			return R.terrain
		end },
	},
	methods = {
		GetServerTimeNow = function()
			return R.now + 1000
		end,
		GetRealPhysicsFPS = function()
			return 60
		end,
	},
})

---------------------------------------------------------------- simple containers
for _, n in ipairs({ "ReplicatedStorage", "ReplicatedFirst", "ServerScriptService", "ServerStorage", "StarterPack", "Teams", "SoundService", "Chat", "TextChatService", "LocalizationService", "LogService", "TestService", "MaterialService", "VoiceChatService", "AnimationClipProvider", "KeyframeSequenceProvider", "BadgeService", "GroupService", "PolicyService", "SocialService", "AvatarEditorService", "VRService", "HapticService", "Selection", "ProximityPromptService" }) do
	service(n)
end
R.CLASSES.SoundService.P.AmbientReverb = P("Enum:ReverbType", R.Enum.ReverbType.NoReverb)
R.CLASSES.SoundService.P.RespectFilteringEnabled = P("boolean", true)
R.CLASSES.SoundService.P.RolloffScale = P("number", 1)
R.CLASSES.SoundService.M.PlayLocalSound = function(self, s)
	s:Play()
end

service("StarterPlayer", "Instance", { props = {
	EnableMouseLockOption = P("boolean", true), CharacterWalkSpeed = P("number", 16), CharacterJumpHeight = P("number", 7.2),
	CharacterJumpPower = P("number", 50), CharacterUseJumpPower = P("boolean", false), CameraMaxZoomDistance = P("number", 128),
	CameraMinZoomDistance = P("number", 0.5), DevComputerMovementMode = P("any"), DevTouchMovementMode = P("any"),
	DevComputerCameraMovementMode = P("any"), DevCameraOcclusionMode = P("any"), AutoJumpEnabled = P("boolean", true),
	LoadCharacterAppearance = P("boolean", true), CharacterMaxSlopeAngle = P("number", 89), HealthDisplayDistance = P("number", 100),
	NameDisplayDistance = P("number", 100), CameraMode = P("any"), UserEmotesEnabled = P("boolean", true),
} })
def("StarterPlayerScripts", "Instance", { creatable = false })
def("StarterCharacterScripts", "StarterPlayerScripts", { creatable = false })
service("StarterGui", "Instance", { props = { ShowDevelopmentGui = P("boolean", true), ResetPlayerGuiOnSpawn = P("boolean", true), ScreenOrientation = P("any") }, methods = {
	SetCoreGuiEnabled = function() end,
	GetCoreGuiEnabled = function()
		return true
	end,
	SetCore = function() end,
	GetCore = function()
		return nil
	end,
} })
service("Lighting", "Instance", { props = {
	Ambient = P("Color3", R.c3(0.27, 0.27, 0.27)), Brightness = P("number", 2), ClockTime = P("number", 14), ColorShift_Bottom = P("Color3", R.c3(0, 0, 0)),
	ColorShift_Top = P("Color3", R.c3(0, 0, 0)), EnvironmentDiffuseScale = P("number", 0), EnvironmentSpecularScale = P("number", 0),
	ExposureCompensation = P("number", 0), FogColor = P("Color3", R.c3(0.75, 0.75, 0.75)), FogEnd = P("number", 100000), FogStart = P("number", 0),
	GeographicLatitude = P("number", 41.7), GlobalShadows = P("boolean", true), OutdoorAmbient = P("Color3", R.c3(0.5, 0.5, 0.5)),
	ShadowSoftness = P("number", 0.2), TimeOfDay = P("string", "14:00:00"), Technology = P("Enum:Technology", R.Enum.Technology.Future),
	LightingStyle = P("any"), PrioritizeLightingQuality = P("boolean", true),
}, methods = {
	GetSunDirection = function(self)
		local t = (self.ClockTime / 24) * 2 * math.pi
		return v3(-math.sin(t) * 0.3, -math.cos(t), 0.4).Unit
	end,
	GetMinutesAfterMidnight = function(self)
		return self.ClockTime * 60
	end,
	SetMinutesAfterMidnight = function(self, m)
		self.ClockTime = m / 60
	end,
} })

---------------------------------------------------------------- Players
service("Players", "Instance", {
	props = {
		CharacterAutoLoads = P("boolean", true), RespawnTime = P("number", 5), MaxPlayers = P("number", 12), BubbleChat = P("boolean", true),
		LocalPlayer = { t = "Instance", readonly = true, get = function()
			if R.peer() == "client" then
				return R.localPlayer
			end
			return nil
		end },
	},
	events = { "PlayerAdded", "PlayerRemoving", "PlayerMembershipChanged" },
	methods = {
		GetPlayers = function(self)
			local out = {}
			for _, c in ipairs(DATA[self].children) do
				if DATA[c].cls.name == "Player" then
					out[#out + 1] = c
				end
			end
			return out
		end,
		GetPlayerFromCharacter = function(self, model)
			for _, p in ipairs(self:GetPlayers()) do
				if p.Character == model then
					return p
				end
			end
			return nil
		end,
		GetPlayerByUserId = function(self, id)
			for _, p in ipairs(self:GetPlayers()) do
				if p.UserId == id then
					return p
				end
			end
			return nil
		end,
		GetHumanoidDescriptionFromUserId = function()
			error("HTTP 403 (simulated: avatar web service unavailable in the harness)", 2)
		end,
		CreateHumanoidModelFromDescription = function(self, desc, rigType)
			return R.buildRig(desc, rigType)
		end,
		GetNameFromUserIdAsync = function()
			return "Player"
		end,
		GetUserThumbnailAsync = function()
			return "", true
		end,
	},
})

---------------------------------------------------------------- RunService
service("RunService", "Instance", {
	events = { "Heartbeat", "Stepped", "RenderStepped", "PreRender", "PreAnimation", "PreSimulation", "PostSimulation" },
	methods = {
		IsClient = function()
			return R.peer() == "client"
		end,
		IsServer = function()
			return R.peer() == "server"
		end,
		IsStudio = function()
			return true
		end,
		IsRunning = function()
			return true
		end,
		IsRunMode = function()
			return false
		end,
		IsEdit = function()
			return false
		end,
		BindToRenderStep = function(self, name, priority, fn)
			R.renderBindings[name] = { p = priority, fn = fn, peer = R.peer() }
		end,
		UnbindFromRenderStep = function(self, name)
			R.renderBindings[name] = nil
		end,
	},
})
R.renderBindings = {}

---------------------------------------------------------------- TweenService
R.tweens = {}
def("TweenBase", "Instance", { creatable = false, props = { PlaybackState = P("Enum:PlaybackState", R.Enum.PlaybackState.Begin) }, events = { "Completed" } })
def("Tween", "TweenBase", { creatable = false, props = { Instance = P("Instance"), TweenInfo = P("any") }, methods = {
	Play = function(self)
		local d = DATA[self]
		d.startT = R.now + d.info.DelayTime
		d.from = {}
		d.props.PlaybackState = R.Enum.PlaybackState.Playing
		R.tweens[self] = true
	end,
	Cancel = function(self)
		R.tweens[self] = nil
		DATA[self].props.PlaybackState = R.Enum.PlaybackState.Cancelled
	end,
	Pause = function(self)
		R.tweens[self] = nil
		DATA[self].props.PlaybackState = R.Enum.PlaybackState.Paused
	end,
} })
local function ease(style, dir, t)
	local n = style.Name
	local function easeIn(x)
		if n == "Linear" then
			return x
		elseif n == "Quad" then
			return x * x
		elseif n == "Cubic" then
			return x * x * x
		elseif n == "Quart" then
			return x ^ 4
		elseif n == "Quint" then
			return x ^ 5
		elseif n == "Sine" then
			return 1 - math.cos(x * math.pi / 2)
		elseif n == "Exponential" then
			return x == 0 and 0 or 2 ^ (10 * x - 10)
		elseif n == "Circular" then
			return 1 - math.sqrt(1 - x * x)
		elseif n == "Back" then
			return 2.70158 * x * x * x - 1.70158 * x * x
		elseif n == "Elastic" then
			if x == 0 or x == 1 then
				return x
			end
			return -(2 ^ (10 * x - 10)) * math.sin((x * 10 - 10.75) * (2 * math.pi / 3))
		elseif n == "Bounce" then
			local y = 1 - x
			local v
			if y < 1 / 2.75 then
				v = 7.5625 * y * y
			elseif y < 2 / 2.75 then
				y = y - 1.5 / 2.75
				v = 7.5625 * y * y + 0.75
			elseif y < 2.5 / 2.75 then
				y = y - 2.25 / 2.75
				v = 7.5625 * y * y + 0.9375
			else
				y = y - 2.625 / 2.75
				v = 7.5625 * y * y + 0.984375
			end
			return 1 - v
		end
		return x
	end
	local dn = dir.Name
	if dn == "In" then
		return easeIn(t)
	elseif dn == "Out" then
		return 1 - easeIn(1 - t)
	end
	if t < 0.5 then
		return easeIn(t * 2) / 2
	end
	return 1 - easeIn((1 - t) * 2) / 2
end
R.ease = ease
local function lerpValue(a, b, t)
	local ta = R.typeof(a)
	if ta == "number" then
		return a + (b - a) * t
	elseif ta == "Vector3" or ta == "Color3" or ta == "UDim2" or ta == "CFrame" or ta == "Vector2" then
		return a:Lerp(b, t)
	elseif ta == "UDim" then
		return R.UDim.new(a.Scale + (b.Scale - a.Scale) * t, a.Offset + (b.Offset - a.Offset) * t)
	end
	return t >= 1 and b or a
end
function R.stepTweens()
	for tw in pairs(R.tweens) do
		local d = DATA[tw]
		local inst = d.props.Instance
		if not DATA[inst] or DATA[inst].destroyed then
			R.tweens[tw] = nil
		elseif R.now >= d.startT then
			local info = d.info
			local t = info.Time > 0 and math.min(1, (R.now - d.startT) / info.Time) or 1
			local a = ease(info.EasingStyle, info.EasingDirection, t)
			for k, goal in pairs(d.goals) do
				if d.from[k] == nil then
					d.from[k] = inst[k]
				end
				inst[k] = lerpValue(d.from[k], goal, a)
			end
			if t >= 1 then
				R.tweens[tw] = nil
				d.props.PlaybackState = R.Enum.PlaybackState.Completed
				R.fire(R.getSignal(d, "Completed"), R.Enum.PlaybackState.Completed)
			end
		end
	end
end
service("TweenService", "Instance", { methods = {
	Create = function(self, inst, info, goals)
		if not DATA[inst] then
			error("TweenService:Create: invalid instance", 2)
		end
		if R.typeof(info) ~= "TweenInfo" then
			error("TweenService:Create: TweenInfo expected", 2)
		end
		for k, v in pairs(goals) do
			local spec = DATA[inst].cls.P[k]
			if not spec then
				error("TweenService:Create property named '" .. tostring(k) .. "' cannot be tweened due to type mismatch (property is a 'nil', but given type is '" .. R.typeof(v) .. "')", 2)
			end
			local cur = inst[k]
			if R.typeof(cur) ~= R.typeof(v) then
				error("TweenService:Create property named '" .. k .. "' cannot be tweened due to type mismatch", 2)
			end
		end
		local tw = R.new("Tween")
		local d = DATA[tw]
		d.props.Instance = inst
		d.info = info
		d.goals = goals
		return tw
	end,
	GetValue = function(self, alpha, style, dir)
		return ease(style, dir, alpha)
	end,
} })

---------------------------------------------------------------- Debris, CollectionService
service("Debris", "Instance", { props = { MaxItems = P("number", 1000) }, methods = {
	AddItem = function(self, inst, t)
		R.task.delay(t or 10, function()
			if DATA[inst] and not DATA[inst].destroyed then
				R.destroy(inst)
			end
		end)
	end,
} })
R.tagged = {}
local tagSignals = {}
local function tagSig(kind, tag)
	local key = kind .. "\0" .. tag
	if not tagSignals[key] then
		tagSignals[key] = R.newSignal(key)
	end
	return tagSignals[key]
end
function R.addTag(obj, tag)
	local d = DATA[obj]
	if d.tags[tag] then
		return
	end
	d.tags[tag] = true
	if R.inDataModel(obj) then
		R.fire(tagSig("add", tag), obj)
	end
end
function R.removeTag(obj, tag)
	local d = DATA[obj]
	if not d.tags[tag] then
		return
	end
	d.tags[tag] = nil
	R.fire(tagSig("rem", tag), obj)
end
table.insert(R.hooks.added, function(x)
	for tag in pairs(DATA[x].tags) do
		R.fire(tagSig("add", tag), x)
	end
end)
table.insert(R.hooks.removing, function(x)
	for tag in pairs(DATA[x].tags) do
		R.fire(tagSig("rem", tag), x)
	end
end)
service("CollectionService", "Instance", { methods = {
	AddTag = function(self, obj, tag)
		R.addTag(obj, tag)
	end,
	RemoveTag = function(self, obj, tag)
		R.removeTag(obj, tag)
	end,
	HasTag = function(self, obj, tag)
		return DATA[obj].tags[tag] == true
	end,
	GetTagged = function(self, tag)
		local out = {}
		for _, x in ipairs(R.descendants(R.game, {})) do
			if DATA[x].tags[tag] then
				out[#out + 1] = x
			end
		end
		return out
	end,
	GetTags = function(self, obj)
		return obj:GetTags()
	end,
	GetInstanceAddedSignal = function(self, tag)
		return tagSig("add", tag)
	end,
	GetInstanceRemovedSignal = function(self, tag)
		return tagSig("rem", tag)
	end,
	GetAllTags = function()
		return {}
	end,
} })

---------------------------------------------------------------- input services (client)
def("InputObject", "Instance", { creatable = false, props = {
	KeyCode = P("Enum:KeyCode", R.Enum.KeyCode.Unknown), UserInputType = P("Enum:UserInputType", R.Enum.UserInputType.None),
	UserInputState = P("Enum:UserInputState", R.Enum.UserInputState.None), Position = P("Vector3", v3(0, 0, 0)), Delta = P("Vector3", v3(0, 0, 0)),
}, methods = {
	IsModifierKeyDown = function()
		return false
	end,
} })
R.keysDown = {}
service("UserInputService", "Instance", {
	props = {
		MouseBehavior = P("Enum:MouseBehavior", R.Enum.MouseBehavior.Default), MouseIconEnabled = P("boolean", true), MouseDeltaSensitivity = P("number", 1),
		KeyboardEnabled = P("boolean", true), MouseEnabled = P("boolean", true), TouchEnabled = P("boolean", false), GamepadEnabled = P("boolean", false),
		AccelerometerEnabled = P("boolean", false), GyroscopeEnabled = P("boolean", false), VREnabled = P("boolean", false), ModalEnabled = P("boolean", false),
		MouseIcon = P("string", ""), OverrideMouseIconBehavior = P("any"), PreferredInput = P("any"),
	},
	events = { "InputBegan", "InputEnded", "InputChanged", "JumpRequest", "LastInputTypeChanged", "TouchStarted", "TouchEnded", "TouchMoved", "TouchTap", "WindowFocused", "WindowFocusReleased", "GamepadConnected", "GamepadDisconnected", "TextBoxFocused", "TextBoxFocusReleased" },
	methods = {
		GetMouseLocation = function()
			return R.mousePos or R.v2(R.viewport.X / 2, R.viewport.Y / 2)
		end,
		GetMouseDelta = function()
			return R.mouseDelta or R.v2(0, 0)
		end,
		IsKeyDown = function(self, k)
			return R.keysDown[k] == true
		end,
		IsMouseButtonPressed = function(self, b)
			return R.keysDown[b] == true
		end,
		GetKeysPressed = function()
			return {}
		end,
		GetConnectedGamepads = function()
			return {}
		end,
		GetGamepadConnected = function()
			return false
		end,
		GetLastInputType = function()
			return R.Enum.UserInputType.Keyboard
		end,
		GetFocusedTextBox = function()
			return nil
		end,
		GetGamepadState = function()
			return {}
		end,
		GetStringForKeyCode = function(self, k)
			return k.Name
		end,
		GetNavigationGamepads = function()
			return {}
		end,
	},
})
R.boundActions = {}
service("ContextActionService", "Instance", { methods = {
	BindAction = function(self, name, fn, touch, ...)
		R.boundActions[name] = { fn = fn, keys = { ... } }
	end,
	BindActionAtPriority = function(self, name, fn, touch, prio, ...)
		R.boundActions[name] = { fn = fn, keys = { ... } }
	end,
	UnbindAction = function(self, name)
		R.boundActions[name] = nil
	end,
	SetTitle = function() end,
	SetPosition = function() end,
	SetImage = function() end,
	SetDescription = function() end,
	GetButton = function()
		return nil
	end,
} })
service("GuiService", "Instance", { props = { SelectedObject = P("Instance"), AutoSelectGuiEnabled = P("boolean", true), MenuIsOpen = P("boolean", false), TouchControlsEnabled = P("boolean", true), PreferredTransparency = P("number", 1), ReducedMotionEnabled = P("boolean", false) }, methods = {
	GetGuiInset = function()
		return R.v2(0, R.guiInset), R.v2(0, 0)
	end,
	IsTenFootInterface = function()
		return false
	end,
} })
service("TextService", "Instance", { methods = {
	GetTextSize = function(self, text, size)
		return R.v2(#text * size * 0.52, size * 1.15)
	end,
} })
service("HttpService", "Instance", { props = { HttpEnabled = P("boolean", false) }, methods = {
	GenerateGUID = function(self, braces)
		R.guidN = (R.guidN or 0) + 1
		local s = string.format("%08X-0000-4000-8000-%012X", R.guidN, R.guidN)
		return braces == false and s or ("{" .. s .. "}")
	end,
	JSONEncode = function(self, v)
		return R.json(v)
	end,
} })
service("PhysicsService", "Instance", { methods = {
	RegisterCollisionGroup = function() end,
	CollisionGroupSetCollidable = function() end,
	CreateCollisionGroup = function() end,
	IsCollisionGroupRegistered = function()
		return true
	end,
} })
service("DataStoreService", "Instance", { methods = {
	GetDataStore = function()
		error("You must publish this place to the web to access DataStore. (harness)", 2)
	end,
} })
service("MarketplaceService", "Instance", { methods = {} })
service("TeleportService", "Instance", { methods = {} })
service("PathfindingService", "Instance", { methods = {} })
service("UserGameSettings", "Instance", { props = { MouseSensitivity = P("number", 1), SavedQualityLevel = P("any"), RotationType = P("any"), ComputerMovementMode = P("any") }, events = { "FullscreenChanged" } })
service("UserSettings", "Instance", { methods = {
	GetService = function(self, n)
		return R.getService(n)
	end,
} })

---------------------------------------------------------------- remotes
local function deepCopy(v, seen)
	if type(v) ~= "table" or getmetatable(v) ~= nil then
		return v
	end
	seen = seen or {}
	if seen[v] then
		return seen[v]
	end
	local out = {}
	seen[v] = out
	for k, x in pairs(v) do
		out[deepCopy(k, seen)] = deepCopy(x, seen)
	end
	return out
end
R.deepCopy = deepCopy
local function checkPayload(...)
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		local t = type(v)
		if t == "function" or t == "thread" or t == "userdata" then
			error("Remote payload cannot contain a " .. t, 3)
		end
	end
end
R.remoteCount = 0
local function later(peer, fn, ...)
	local args = table.pack(...)
	R.remoteCount = R.remoteCount + 1
	R.task.delay(R.latency, function()
		fn(table.unpack(args, 1, args.n))
	end)
	-- the delayed thread runs as the receiving peer
	R.PEER[R.Sched.timers[#R.Sched.timers].co] = peer
end
local remoteMethods = {
	FireServer = function(self, ...)
		if R.peer() ~= "client" then
			error("FireServer can only be called from the client", 2)
		end
		checkPayload(...)
		local args = deepCopy(table.pack(...))
		later("server", function()
			R.fire(R.getSignal(DATA[self], "OnServerEvent"), R.localPlayer, table.unpack(args, 1, args.n))
		end)
	end,
	FireClient = function(self, player, ...)
		if R.peer() ~= "server" then
			error("FireClient can only be called from the server", 2)
		end
		if not DATA[player] or DATA[player].cls.name ~= "Player" then
			error("FireClient: player argument must be a Player", 2)
		end
		checkPayload(...)
		if player ~= R.localPlayer then
			return
		end
		local args = deepCopy(table.pack(...))
		later("client", function()
			R.fire(R.getSignal(DATA[self], "OnClientEvent"), table.unpack(args, 1, args.n))
		end)
	end,
	FireAllClients = function(self, ...)
		if R.peer() ~= "server" then
			error("FireAllClients can only be called from the server", 2)
		end
		checkPayload(...)
		if not R.localPlayer then
			return
		end
		local args = deepCopy(table.pack(...))
		later("client", function()
			R.fire(R.getSignal(DATA[self], "OnClientEvent"), table.unpack(args, 1, args.n))
		end)
	end,
}
for k, f in pairs(remoteMethods) do
	R.CLASSES.RemoteEvent.M[k] = f
	R.CLASSES.UnreliableRemoteEvent.M[k] = f
end
R.CLASSES.RemoteFunction.M.InvokeServer = function(self, ...)
	local f = self.OnServerInvoke
	if not f then
		error("OnServerInvoke not set", 2)
	end
	R.task.wait(R.latency * 2)
	local prev = R.currentPeer
	return f(R.localPlayer, ...)
end

---------------------------------------------------------------- tiny JSON (for HttpService)
function R.json(v)
	local t = type(v)
	if t == "table" then
		if #v > 0 then
			local parts = {}
			for _, x in ipairs(v) do
				parts[#parts + 1] = R.json(x)
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local parts = {}
		for k, x in pairs(v) do
			parts[#parts + 1] = string.format("%q", tostring(k)) .. ":" .. R.json(x)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif t == "string" then
		return string.format("%q", v)
	elseif t == "number" or t == "boolean" then
		return tostring(v)
	end
	return "null"
end
