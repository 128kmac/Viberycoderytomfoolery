-- Boot: DataModel creation, script environments, require, players, frame stepping.
local R = ...
local DATA = R.DATA
local v3 = R.v3

---------------------------------------------------------------- sound lengths (seconds) for built-in ids
local LENGTHS = {
	["rbxasset://sounds/swordslash.wav"] = 0.45, ["rbxasset://sounds/swordlunge.wav"] = 0.6, ["rbxasset://sounds/unsheath.wav"] = 0.6,
	["rbxasset://sounds/Rocket shot.wav"] = 0.9, ["rbxasset://sounds/Rocket whoosh.wav"] = 2.5, ["rbxasset://sounds/collide.wav"] = 0.5,
	["rbxasset://sounds/electronicpingshort.wav"] = 0.3, ["rbxasset://sounds/glassbreak.wav"] = 1.0, ["rbxasset://sounds/action_jump.mp3"] = 0.35,
	["rbxasset://sounds/action_jump_land.mp3"] = 0.3, ["rbxasset://sounds/action_falling.mp3"] = 1.5, ["rbxasset://sounds/action_footsteps_plastic.mp3"] = 0.35,
	["rbxasset://sounds/action_get_up.mp3"] = 0.6, ["rbxasset://sounds/action_swim.mp3"] = 1.2, ["rbxasset://sounds/impact_water.mp3"] = 0.8,
	["rbxasset://sounds/uuhhh.mp3"] = 0.7, ["rbxasset://sounds/splat.wav"] = 0.5, ["rbxasset://sounds/snap.wav"] = 0.2,
}
function R.soundLength(id)
	return LENGTHS[id] or 0.8
end

---------------------------------------------------------------- DataModel
R.game = R.new("DataModel")
R.game.Name = "EB_Proxima"
R.services.DataModel = R.game
R.workspace = R.getService("Workspace")
R.workspace.Name = "Workspace"
R.terrain = R.new("Terrain")
R.terrain.Name = "Terrain"
R.setParent(R.terrain, DATA[R.terrain], R.workspace)
local cam = R.new("Camera")
cam.Name = "Camera"
cam.Parent = R.workspace
R.workspace.CurrentCamera = cam
for _, n in ipairs({ "ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterPlayer", "StarterGui", "Lighting", "Players", "Teams", "SoundService", "RunService", "TweenService", "Debris", "CollectionService", "UserInputService", "ContextActionService" }) do
	R.getService(n)
end
local SP = R.services.StarterPlayer
local sps = R.new("StarterPlayerScripts")
sps.Name = "StarterPlayerScripts"
R.setParent(sps, DATA[sps], SP)
local scs = R.new("StarterCharacterScripts")
scs.Name = "StarterCharacterScripts"
R.setParent(scs, DATA[scs], SP)

---------------------------------------------------------------- globals
local base = {}
local realTostring = tostring
local function luauTostring(v)
	if type(v) == "number" then
		if v ~= v then
			return "nan"
		elseif v == math.huge then
			return "inf"
		elseif v == -math.huge then
			return "-inf"
		elseif math.type(v) == "float" and v == math.floor(v) and math.abs(v) < 1e15 then
			return string.format("%d", v)
		end
		return string.format("%.14g", v)
	end
	return realTostring(v)
end
R.tostring = luauTostring

local function join(...)
	local n = select("#", ...)
	local parts = {}
	for i = 1, n do
		parts[i] = luauTostring((select(i, ...)))
	end
	return table.concat(parts, " ")
end

local mathx = {}
for k, f in pairs(math) do
	mathx[k] = f
end
function mathx.clamp(x, lo, hi)
	if type(x) ~= "number" or type(lo) ~= "number" or type(hi) ~= "number" then
		error("invalid argument to 'clamp' (number expected)", 2)
	end
	if lo > hi then
		error("invalid argument #3 to 'clamp' (max must be greater than or equal to min)", 2)
	end
	return x < lo and lo or (x > hi and hi or x)
end
mathx.sign = R.sign
function mathx.round(x)
	if x >= 0 then
		return math.floor(x + 0.5)
	end
	return math.ceil(x - 0.5)
end
function mathx.noise(x, y, z)
	x, y, z = x or 0, y or 0, z or 0
	return (math.sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453) % 1 * 2 - 1
end
function mathx.lerp(a, b, t)
	return a + (b - a) * t
end
function mathx.map(x, a, b, c, d)
	return c + (x - a) * (d - c) / (b - a)
end
local rngState = 12345
function mathx.random(a, b)
	rngState = (rngState * 1103515245 + 12345) % 2147483648
	local r = rngState / 2147483648
	if a == nil then
		return r
	end
	if b == nil then
		a, b = 1, a
	end
	if a ~= math.floor(a) or b ~= math.floor(b) then
		error("bad argument to 'random' (number has no integer representation)", 2)
	end
	if a > b then
		error("bad argument #2 to 'random' (interval is empty)", 2)
	end
	return math.floor(a + r * (b - a + 1))
end
function mathx.randomseed(s)
	rngState = math.floor(s or 0) % 2147483648
end
function mathx.atan2(y, x)
	return math.atan(y, x)
end
function mathx.pow(a, b)
	return a ^ b
end
function mathx.log10(x)
	return math.log(x, 10)
end
function mathx.cosh(x)
	return (math.exp(x) + math.exp(-x)) / 2
end
function mathx.sinh(x)
	return (math.exp(x) - math.exp(-x)) / 2
end
function mathx.tanh(x)
	local a, b = math.exp(x), math.exp(-x)
	return (a - b) / (a + b)
end
function mathx.ldexp(m, e)
	return m * 2.0 ^ e
end
function mathx.frexp(x)
	if x == 0 then
		return 0, 0
	end
	local e = math.floor(math.log(math.abs(x), 2)) + 1
	return x / 2.0 ^ e, e
end
mathx.isnan = function(x)
	return x ~= x
end
mathx.isinf = function(x)
	return x == math.huge or x == -math.huge
end
mathx.isfinite = function(x)
	return x == x and x ~= math.huge and x ~= -math.huge
end

local stringx = {}
for k, f in pairs(string) do
	stringx[k] = f
end
local realFormat = string.format
function stringx.format(fmt, ...)
	local args = table.pack(...)
	local i = 0
	for spec in fmt:gmatch("%%[-+ #0]*%d*%.?%d*(%a)") do
		i = i + 1
		local v = args[i]
		if spec == "s" and type(v) ~= "string" then
			args[i] = luauTostring(v)
		elseif (spec == "d" or spec == "i" or spec == "x" or spec == "X") and type(v) == "number" then
			-- Luau truncates non-integral numbers for integer conversions
			if v ~= v or v == math.huge or v == -math.huge then
				args[i] = 0
			else
				args[i] = v >= 0 and math.floor(v) or math.ceil(v)
			end
		end
	end
	return realFormat(fmt, table.unpack(args, 1, args.n))
end
local function luauCat(a, b)
	local ta, tb = type(a), type(b)
	if (ta ~= "string" and ta ~= "number") or (tb ~= "string" and tb ~= "number") then
		error("attempt to concatenate " .. ta .. " with " .. tb, 2)
	end
	if ta == "number" then
		a = luauTostring(a)
	end
	if tb == "number" then
		b = luauTostring(b)
	end
	return a .. b
end
base.__cat = luauCat
function stringx.split(s, sep)
	sep = sep or ","
	local out = {}
	if sep == "" then
		for ch in s:gmatch(".") do
			out[#out + 1] = ch
		end
		return out
	end
	local i = 1
	while true do
		local j = s:find(sep, i, true)
		if not j then
			out[#out + 1] = s:sub(i)
			break
		end
		out[#out + 1] = s:sub(i, j - 1)
		i = j + #sep
	end
	return out
end
-- string methods via the shared string metatable keep working; add split there too
getmetatable("").__index.split = stringx.split
getmetatable("").__index.format = stringx.format

local tablex = {}
for k, f in pairs(table) do
	tablex[k] = f
end
function tablex.find(t, v, init)
	for i = init or 1, #t do
		if t[i] == v then
			return i
		end
	end
	return nil
end
function tablex.clear(t)
	for k in pairs(t) do
		t[k] = nil
	end
end
function tablex.clone(t)
	if type(t) ~= "table" then
		error("invalid argument #1 to 'clone' (table expected)", 2)
	end
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return setmetatable(out, getmetatable(t))
end
function tablex.create(n, v)
	local out = {}
	for i = 1, n do
		out[i] = v
	end
	return out
end
function tablex.freeze(t)
	return t
end
function tablex.isfrozen()
	return false
end
function tablex.getn(t)
	return #t
end
function tablex.foreach(t, f)
	for k, v in pairs(t) do
		f(k, v)
	end
end
function tablex.maxn(t)
	local m = 0
	for k in pairs(t) do
		if type(k) == "number" and k > m then
			m = k
		end
	end
	return m
end

local bit32 = {
	band = function(...)
		local r = 0xFFFFFFFF
		for _, x in ipairs({ ... }) do
			r = r & math.floor(x)
		end
		return r
	end,
	bor = function(...)
		local r = 0
		for _, x in ipairs({ ... }) do
			r = r | math.floor(x)
		end
		return r
	end,
	bxor = function(...)
		local r = 0
		for _, x in ipairs({ ... }) do
			r = r ~ math.floor(x)
		end
		return r
	end,
	bnot = function(x)
		return (~math.floor(x)) & 0xFFFFFFFF
	end,
	lshift = function(x, n)
		return (math.floor(x) << n) & 0xFFFFFFFF
	end,
	rshift = function(x, n)
		return (math.floor(x) & 0xFFFFFFFF) >> n
	end,
	btest = function(a, b)
		return (math.floor(a) & math.floor(b)) ~= 0
	end,
}
bit32.arshift = bit32.rshift

base.print = function(...)
	R.log(R.output, join(...))
end
base.warn = function(...)
	R.log(R.warnings, join(...))
end
base.error, base.assert, base.pcall, base.xpcall = error, assert, pcall, xpcall
base.select, base.type, base.tonumber, base.tostring = select, type, tonumber, luauTostring
base.pairs, base.ipairs, base.next = pairs, ipairs, next
base.rawget, base.rawset, base.rawequal, base.rawlen = rawget, rawset, rawequal, rawlen
base.setmetatable, base.getmetatable = setmetatable, getmetatable
base.unpack = table.unpack
base.typeof = R.typeof
base.math, base.string, base.table, base.coroutine, base.utf8, base.bit32 = mathx, stringx, tablex, coroutine, utf8, bit32
base.os = { time = function()
	return math.floor(R.now + 1700000000)
end, clock = function()
	return R.now
end, date = os.date, difftime = os.difftime }
base.debug = { traceback = debug.traceback, info = function(a, opts)
	return "harness"
end, profilebegin = function() end, profileend = function() end, setmemorycategory = function() end, resetmemorycategory = function() end }
base.task = R.task
base.wait = function(t)
	local e = R.task.wait(t)
	return e, R.now
end
base.delay = function(t, f)
	R.task.delay(t, f)
end
base.spawn = function(f)
	R.task.defer(f)
end
base.tick = function()
	return R.now + 1700000000
end
base.time = function()
	return R.now
end
base.elapsedTime = base.time
base.game = R.game
base.Game = R.game
base.workspace = R.workspace
base.Workspace = R.workspace
base.Instance = {
	new = function(cn, parent)
		return R.newInstance(cn, parent)
	end,
	fromExisting = function(x)
		return x:Clone()
	end,
}
for _, k in ipairs({ "Vector3", "Vector2", "CFrame", "Color3", "BrickColor", "UDim", "UDim2", "Rect", "NumberRange", "NumberSequence", "NumberSequenceKeypoint", "ColorSequence", "ColorSequenceKeypoint", "TweenInfo", "Random", "Ray", "RaycastParams", "OverlapParams", "Enum", "Font", "PhysicalProperties" }) do
	base[k] = R[k]
end
base.DateTime = { now = function()
	return { UnixTimestamp = math.floor(R.now + 1700000000), UnixTimestampMillis = math.floor((R.now + 1700000000) * 1000) }
end }
base.UserSettings = function()
	return R.getService("UserSettings")
end
base.settings = function()
	return { Rendering = { QualityLevel = 10 } }
end
base.shared = {}
base._G = base.shared
base.newproxy = function()
	return setmetatable({}, {})
end
base.gcinfo = function()
	return collectgarbage("count")
end
base.collectgarbage = function(opt)
	if opt == "count" then
		return collectgarbage("count")
	end
	return 0
end
base.version = function()
	return "0.harness"
end
local BaseMT = { __index = base }
R.globals = base

---------------------------------------------------------------- scripts and require
R.modCache = { server = {}, client = {} }
local compiled = {}
local function compile(scriptInst)
	local d = DATA[scriptInst]
	local src = d.props.Source
	local name = d.path or R.fullName(scriptInst)
	local key = name .. "\0" .. src
	local lua = compiled[key]
	if not lua then
		local ok, res = pcall(R.transpile, src, name)
		if not ok then
			error("transpile failed for " .. name .. ": " .. tostring(res), 0)
		end
		lua = res
		compiled[key] = lua
	end
	return lua, name
end

local function makeEnv(scriptInst, peer)
	local env = setmetatable({}, BaseMT)
	env.script = scriptInst
	env.require = function(mod)
		return R.require(peer, mod)
	end
	return env
end
R.makeEnv = makeEnv

function R.require(peer, mod)
	if type(mod) == "number" then
		error("require(assetId) is not available in the harness", 2)
	end
	if not DATA[mod] or DATA[mod].cls.name ~= "ModuleScript" then
		error("Attempted to call require with invalid argument(s).", 2)
	end
	local cache = R.modCache[peer]
	local entry = cache[mod]
	if entry then
		if entry.loading then
			error("Requested module was required recursively: " .. R.fullName(mod), 2)
		end
		if entry.failed then
			error("Requested module experienced an error while loading", 2)
		end
		return entry.value
	end
	entry = { loading = true }
	cache[mod] = entry
	local lua, name = compile(mod)
	local fn, err = load(lua, "@" .. name, "t", makeEnv(mod, peer))
	if not fn then
		entry.failed = true
		error(err, 0)
	end
	local res = table.pack(xpcall(fn, function(e)
		return debug.traceback(tostring(e), 2)
	end))
	entry.loading = false
	if not res[1] then
		entry.failed = true
		error(res[2], 0)
	end
	if res.n ~= 2 then
		entry.failed = true
		error("Module code did not return exactly one value: " .. name, 2)
	end
	entry.value = res[2]
	return res[2]
end

R.scriptsRun = {}
function R.runScript(scriptInst, peer)
	local d = DATA[scriptInst]
	if d.props.Disabled or d.props.Enabled == false then
		return
	end
	local lua, name = compile(scriptInst)
	local fn, err = load(lua, "@" .. name, "t", makeEnv(scriptInst, peer))
	if not fn then
		R.log(R.errors, "load error: " .. tostring(err))
		return
	end
	R.scriptsRun[#R.scriptsRun + 1] = name
	local co = R.newThread(fn, peer, name)
	R.resume(co)
end

function R.startServer()
	for _, root in ipairs({ R.services.ServerScriptService, R.workspace }) do
		for _, x in ipairs(R.descendants(root, {})) do
			if DATA[x].cls.name == "Script" then
				R.runScript(x, "server")
			end
		end
	end
end

---------------------------------------------------------------- players
local PlayerCls = R.CLASSES.Player
PlayerCls.P.Character.set = function(obj, d, model)
	local old = d.props.Character
	if old == R.NIL then
		old = nil
	end
	if old == model then
		return false
	end
	if old then
		R.fire(R.getSignal(d, "CharacterRemoving"), old)
	end
	d.props.Character = model == nil and R.NIL or model
	if model then
		R.fire(R.getSignal(d, "CharacterAdded"), model)
	end
end
PlayerCls.M.LoadCharacter = function(self)
	local d = DATA[self]
	local old = self.Character
	if old then
		old:Destroy()
	end
	local desc = R.new("HumanoidDescription")
	local model = R.buildRig(desc, R.Enum.HumanoidRigType.R15)
	model.Name = self.Name
	for _, c in ipairs(DATA[R.services.StarterPlayer.StarterCharacterScripts].children) do
		local cc = c:Clone()
		cc.Parent = model
	end
	model.Parent = R.workspace
	self.Character = model
	for _, x in ipairs(R.descendants(model, {})) do
		local cn = DATA[x].cls.name
		if cn == "LocalScript" then
			R.runScript(x, "client")
		elseif cn == "Script" then
			R.runScript(x, "server")
		end
	end
end
PlayerCls.M.LoadCharacterWithHumanoidDescription = function(self)
	PlayerCls.M.LoadCharacter(self)
end
PlayerCls.M.Kick = function(self, msg)
	R.log(R.warnings, "Player kicked: " .. tostring(msg))
	R.kicked = msg
end
PlayerCls.M.GetMouse = function(self)
	local m = { X = R.viewport.X / 2, Y = R.viewport.Y / 2, Hit = R.CFrame.identity, Target = nil, Icon = "" }
	m.Button1Down = R.newSignal("Button1Down")
	m.Button1Up = R.newSignal("Button1Up")
	m.Move = R.newSignal("Move")
	return m
end
PlayerCls.M.GetNetworkPing = function()
	return R.latency
end
PlayerCls.M.IsInGroup = function()
	return false
end
PlayerCls.M.GetRankInGroup = function()
	return 0
end
PlayerCls.M.HasAppearanceLoaded = function()
	return true
end
PlayerCls.M.ClearCharacterAppearance = function() end

function R.addPlayer(name, userId)
	local players = R.services.Players
	local p = R.new("Player")
	p.Name = name
	p.DisplayName = name
	p.UserId = userId or 1
	local gui = R.new("PlayerGui")
	gui.Name = "PlayerGui"
	R.setParent(gui, DATA[gui], p)
	local ps = R.new("PlayerScripts")
	ps.Name = "PlayerScripts"
	R.setParent(ps, DATA[ps], p)
	local bp = R.new("Backpack")
	bp.Name = "Backpack"
	bp.Parent = p
	R.localPlayer = p
	R.setParent(p, DATA[p], players)
	R.fire(R.getSignal(DATA[players], "PlayerAdded"), p)
	-- client side boot
	for _, c in ipairs(DATA[R.services.StarterGui].children) do
		local cc = c:Clone()
		cc.Parent = gui
	end
	for _, c in ipairs(DATA[R.services.StarterPlayer.StarterPlayerScripts].children) do
		local cc = c:Clone()
		cc.Parent = ps
	end
	for _, x in ipairs(R.descendants(ps, {})) do
		if DATA[x].cls.name == "LocalScript" then
			R.runScript(x, "client")
		end
	end
	if players.CharacterAutoLoads then
		p:LoadCharacter()
	end
	return p
end

-- keep cloned script paths
R.CLASSES.LuaSourceContainer.cloneHook = function(src, copy, sd, cd)
	cd.path = sd.path
end

---------------------------------------------------------------- input injection (client)
local function inputObject(kind, key, state, pos)
	local io = R.new("InputObject")
	io.UserInputType = kind
	if key then
		io.KeyCode = key
	end
	io.UserInputState = state
	io.Position = pos or v3(R.viewport.X / 2, R.viewport.Y / 2, 0)
	return io
end
function R.inputKey(keyName, down)
	local uis = R.services.UserInputService
	local key = R.Enum.KeyCode[keyName]
	R.keysDown[key] = down or nil
	local io = inputObject(R.Enum.UserInputType.Keyboard, key, down and R.Enum.UserInputState.Begin or R.Enum.UserInputState.End)
	local prev = R.currentPeer
	R.currentPeer = "client"
	R.fire(R.getSignal(DATA[uis], down and "InputBegan" or "InputEnded"), io, false)
	R.currentPeer = prev
end
function R.inputMouse(button, down)
	local uis = R.services.UserInputService
	local t = R.Enum.UserInputType[button]
	R.keysDown[t] = down or nil
	local io = inputObject(t, nil, down and R.Enum.UserInputState.Begin or R.Enum.UserInputState.End)
	local prev = R.currentPeer
	R.currentPeer = "client"
	R.fire(R.getSignal(DATA[uis], down and "InputBegan" or "InputEnded"), io, false)
	R.currentPeer = prev
end
function R.inputMouseMove(dx, dy)
	local uis = R.services.UserInputService
	R.mouseDelta = R.v2(dx, dy)
	local io = inputObject(R.Enum.UserInputType.MouseMovement, nil, R.Enum.UserInputState.Change)
	io.Delta = v3(dx, dy, 0)
	local prev = R.currentPeer
	R.currentPeer = "client"
	R.fire(R.getSignal(DATA[uis], "InputChanged"), io, false)
	R.currentPeer = prev
end

---------------------------------------------------------------- frame stepping
R.frame = 0
function R.step(dt)
	R.frame = R.frame + 1
	R.now = R.now + dt
	R.workspace.DistributedGameTime = R.now
	local rs = DATA[R.services.RunService]
	-- client render step
	if R.localPlayer then
		local binds = {}
		for name, b in pairs(R.renderBindings) do
			binds[#binds + 1] = b
		end
		table.sort(binds, function(a, b)
			return a.p < b.p
		end)
		for _, b in ipairs(binds) do
			local co = R.newThread(b.fn, "client", "RenderStep")
			R.resume(co, dt)
		end
		if rs.signals.RenderStepped then
			R.fire(rs.signals.RenderStepped, dt)
		end
		if rs.signals.PreRender then
			R.fire(rs.signals.PreRender, dt)
		end
	end
	R.mouseDelta = R.v2(0, 0)
	if rs.signals.PreAnimation then
		R.fire(rs.signals.PreAnimation, dt)
	end
	R.Sched.runTimers()
	if rs.signals.Stepped then
		R.fire(rs.signals.Stepped, R.now, dt)
	end
	if rs.signals.PreSimulation then
		R.fire(rs.signals.PreSimulation, dt)
	end
	R.stepTweens()
	R.stepHumanoids(dt)
	R.stepFreeParts(dt)
	R.solveJoints()
	if rs.signals.Heartbeat then
		R.fire(rs.signals.Heartbeat, dt)
	end
	if rs.signals.PostSimulation then
		R.fire(rs.signals.PostSimulation, dt)
	end
	R.Sched.runDeferred()
end

function R.stats()
	local counts = {}
	for _, x in ipairs(R.descendants(R.game, {})) do
		local cn = DATA[x].cls.name
		counts[cn] = (counts[cn] or 0) + 1
	end
	local wsCount = #R.descendants(R.workspace, {})
	local camCount = #R.descendants(R.workspace.CurrentCamera, {})
	local np = 0
	for _ in pairs(R.parts) do
		np = np + 1
	end
	return {
		instances = R.instanceCount, inGame = #R.descendants(R.game, {}), workspace = wsCount, camera = camCount,
		parts = np, connections = R.connCount, timers = #R.Sched.timers, tweens = (function()
			local n = 0
			for _ in pairs(R.tweens) do
				n = n + 1
			end
			return n
		end)(), counts = counts, remotes = R.remoteCount, rays = R.rayCount or 0,
	}
end

---------------------------------------------------------------- test drivers (plain Lua run as a peer coroutine)
function R.runTest(code, name, peer)
	local env = makeEnv(nil, peer or "server")
	env.R = R
	env.find = function(path)
		local obj = R.game
		for part in path:gmatch("[^%.]+") do
			obj = obj == R.game and R.getService(part) or obj:FindFirstChild(part)
			if not obj then
				error("not found: " .. path, 2)
			end
		end
		return obj
	end
	-- drivers are written in Luau and transpiled like project scripts
	local fn, err = load(R.transpile(code, name or "test"), "@" .. (name or "test"), "t", env)
	if not fn then
		error(err)
	end
	local state = { done = false }
	local co = R.newThread(function()
		local ok, res = xpcall(fn, function(e)
			return debug.traceback(tostring(e), 2)
		end)
		state.ok = ok
		state.result = res
		state.done = true
	end, peer or "server", name)
	R.resume(co)
	return state
end
