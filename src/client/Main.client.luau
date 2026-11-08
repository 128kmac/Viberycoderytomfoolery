-- EB: Proxima — client bootstrap.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Client = script.Parent

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local ctx = {
	player = player,
	remotes = {
		Input = remotes:WaitForChild("Input"),
		Aim = remotes:WaitForChild("Aim"),
		Pop = remotes:WaitForChild("Pop"),
		Notice = remotes:WaitForChild("Notice"),
		Feed = remotes:WaitForChild("Feed"),
		MatchEvent = remotes:WaitForChild("MatchEvent"),
		Cue = remotes:WaitForChild("Cue"),
		ProjSync = remotes:WaitForChild("ProjSync"),
	},
	Config = require(Shared:WaitForChild("Config")),
	Util = require(Shared:WaitForChild("Util")),
	KitIndex = require(Shared:WaitForChild("KitIndex")),
	Styles = require(Shared:WaitForChild("Styles")),
	KitData = Shared:WaitForChild("KitData"),
}

local dataCache = {}
function ctx.kitData(name)
	if not name then
		return nil
	end
	local id = string.gsub(name, "[^%w]", "")
	if dataCache[id] == nil then
		local m = ctx.KitData:FindFirstChild(id)
		dataCache[id] = m and require(m) or false
	end
	return dataCache[id] or nil
end

local gui = Instance.new("ScreenGui")
gui.Name = "EBProxima"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")
ctx.gui = gui

local Theme = require(Client:WaitForChild("Theme"))
ctx.Theme = Theme

-- order matters: settings → audio → effects → camera/animation → interface → input
local Settings = require(Client:WaitForChild("Settings"))
local Audio = require(Client:WaitForChild("Audio"))
local VFX = require(Client:WaitForChild("VFX"))
local Fam = require(Client.VFX:WaitForChild("Fam"))
local Showcase = require(Client.VFX:WaitForChild("Showcase"))
local Camera = require(Client:WaitForChild("CameraRig"))
local Animator = require(Client:WaitForChild("Animator"))
local Nameplates = require(Client:WaitForChild("Nameplates"))
local HUD = require(Client:WaitForChild("HUD"))
local KitMenu = require(Client:WaitForChild("KitMenu"))
local Popups = require(Client:WaitForChild("Popups"))
local MatchUI = require(Client:WaitForChild("MatchUI"))
local Controls = require(Client:WaitForChild("Controls"))

ctx.Settings = Settings
ctx.Audio = Audio
ctx.VFX = VFX
ctx.Fam = Fam
ctx.Showcase = Showcase
ctx.Camera = Camera
ctx.Animator = Animator
ctx.HUD = HUD
ctx.KitMenu = KitMenu
ctx.Popups = Popups
ctx.MatchUI = MatchUI
ctx.Controls = Controls
ctx.latency = 0.06

Settings.init()
Audio.init(ctx)
VFX.init(ctx)
Fam.init(ctx)
Showcase.init(ctx)
Camera.init(ctx)
Animator.init(ctx)
Nameplates.init(ctx)
Popups.init(ctx)
HUD.init(ctx)
KitMenu.init(ctx)
MatchUI.init(ctx)
Controls.init(ctx)

-- one-way latency estimate for projectile extrapolation
task.spawn(function()
	while true do
		local ok, ping = pcall(function()
			return player:GetNetworkPing()
		end)
		if ok and type(ping) == "number" then
			ctx.latency = math.clamp(ping, 0.01, 0.3)
		end
		task.wait(2)
	end
end)

-- open the power compendium on first join
task.delay(1, function()
	KitMenu.open()
end)
