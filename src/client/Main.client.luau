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
	},
	Config = require(Shared:WaitForChild("Config")),
	Util = require(Shared:WaitForChild("Util")),
	KitIndex = require(Shared:WaitForChild("KitIndex")),
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

local HUD = require(Client:WaitForChild("HUD"))
local KitMenu = require(Client:WaitForChild("KitMenu"))
local Popups = require(Client:WaitForChild("Popups"))
local Controls = require(Client:WaitForChild("Controls"))

ctx.HUD = HUD
ctx.KitMenu = KitMenu
ctx.Popups = Popups
ctx.Controls = Controls

Popups.init(ctx)
HUD.init(ctx)
KitMenu.init(ctx)
Controls.init(ctx)

-- open the compendium on first join
task.delay(1, function()
	KitMenu.open()
end)
