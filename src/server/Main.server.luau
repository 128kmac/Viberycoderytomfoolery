-- EB: Proxima — server bootstrap.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Server = script.Parent
local Core = Server:WaitForChild("Core")

local S = require(Core.S)
require(Core.FX)
require(Core.Hit)
local Status = require(Core.Status)
local Combat = require(Core.Combat)
local Fighter = require(Core.Fighter)
local Objects = require(Core.Objects)
local Zones = require(Core.Zones)
require(Core.Proj)
require(Core.Summons)
local Cast = require(Core.Cast)
require(Core.Danger)
local Nav = require(Core.Nav)
require(Core.K)
require(Server:WaitForChild("Kits"))
local Arena = require(Core.Arena)
local Match = require(Core.Match)
require(Core.Bots)
local _ = Status

-- Remotes ----------------------------------------------------------------------------------------
local remoteFolder = Instance.new("Folder")
remoteFolder.Name = "Remotes"
local function remote(name, class)
	local r = Instance.new(class or "RemoteEvent")
	r.Name = name
	r.Parent = remoteFolder
	return r
end
local remotes = {
	Input = remote("Input"),
	Aim = remote("Aim", "UnreliableRemoteEvent"),
	Pop = remote("Pop"),
	Notice = remote("Notice"),
	Feed = remote("Feed"),
	MatchEvent = remote("MatchEvent"),
	Cue = remote("Cue"),
	ProjSync = remote("ProjSync", "UnreliableRemoteEvent"),
}
remoteFolder.Parent = ReplicatedStorage

S.FX.init(remotes)
Combat.init(remotes)
Cast.init(remotes)

Arena.build()
Match.init(remotes)
task.spawn(function()
	local b = S.arenaBounds
	local n = Nav.build({ center = b.center, half = b.half + 10, floorY = b.floorY, top = b.floorY + 80 })
	print("[EB: Proxima] navigation graph: " .. n .. " nodes")
end)

-- Input --------------------------------------------------------------------------------------------
local function isVec(v)
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e5
end

remotes.Input.OnServerEvent:Connect(function(player, action, a, b, c)
	if type(action) ~= "string" then
		return
	end
	if action == "selectKit" then
		if type(a) == "string" then
			Match.selectKit(player, a)
		end
		return
	elseif action == "setting" then
		if type(a) == "string" then
			Match.setting(player, a, b)
		end
		return
	end
	local f = Fighter.forPlayer(player)
	if not f or f.dead then
		return
	end
	if action == "cast" then
		if type(a) == "number" then
			Cast.press(f, math.floor(a), b == true, c == true)
		end
	elseif action == "basic" then
		Fighter.basic(f)
	elseif action == "dodge" then
		Fighter.dodge(f, isVec(a) and a or nil)
	elseif action == "guard" then
		Fighter.setGuard(f, a == true)
	elseif action == "kit" then
		Cast.kitAction(f, a)
	end
end)

remotes.Aim.OnServerEvent:Connect(function(player, origin, dir, hit, target)
	local f = Fighter.forPlayer(player)
	if not f or f.dead then
		return
	end
	if not (isVec(origin) and isVec(dir) and isVec(hit)) then
		return
	end
	if dir.Magnitude < 0.01 then
		return
	end
	-- the aim origin must be near the character (camera offset tolerance)
	if (origin - f.root.Position).Magnitude > 60 then
		return
	end
	if typeof(target) ~= "Instance" or not target:IsA("Model") then
		target = nil
	end
	f.aim = { origin = origin, dir = dir.Unit, hit = hit, target = target }
end)

-- Main tick (10 Hz resources/statuses, zones; objects) ------------------------------------------
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.1 then
		return
	end
	local step = acc
	acc = 0
	local now = S.now()
	for _, f in pairs(S.fighters) do
		S.FX.current = S.FX.ctxOf(f)
		local ok, err = pcall(Fighter.tick, f, step, now)
		S.FX.current = nil
		if not ok then
			warn("[EB] fighter tick: " .. tostring(err))
		end
	end
	local ok1, e1 = pcall(Zones.update, now)
	S.FX.current = nil
	if not ok1 then
		warn("[EB] zones: " .. tostring(e1))
	end
	local ok2, e2 = pcall(Objects.update, now)
	S.FX.current = nil
	if not ok2 then
		warn("[EB] objects: " .. tostring(e2))
	end
end)


print("[EB: Proxima] server ready — " .. #S.Kits.index .. " powers loaded")
