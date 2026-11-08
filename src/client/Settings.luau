-- Client settings: audio volumes per group, effect quality, accessibility (reduced flash / motion),
-- camera. Values persist for the session as player attributes so they survive respawns and UI rebuilds.
local Players = game:GetService("Players")

local Settings = {}

local player = Players.LocalPlayer

Settings.DEFAULTS = {
	MasterVolume = 0.8,
	SfxVolume = 0.8,
	AmbienceVolume = 0.5,
	UIVolume = 0.6,
	Quality = 3, -- 1 Low, 2 Medium, 3 High
	ReducedFlash = false,
	ReducedMotion = false,
	ShakeScale = 1,
	Sensitivity = 1,
	FieldOfView = 72,
	DamageNumbers = true,
}

Settings.LABELS = {
	MasterVolume = "Master volume",
	SfxVolume = "Effects volume",
	AmbienceVolume = "Ambience volume",
	UIVolume = "Interface volume",
	Quality = "Effect quality",
	ReducedFlash = "Reduced flashing",
	ReducedMotion = "Reduced motion",
	ShakeScale = "Camera shake",
	Sensitivity = "Camera sensitivity",
	FieldOfView = "Field of view",
	DamageNumbers = "Damage numbers",
}

local values = {}
local listeners = {}

function Settings.get(key)
	local v = values[key]
	if v == nil then
		return Settings.DEFAULTS[key]
	end
	return v
end

function Settings.set(key, value)
	if Settings.DEFAULTS[key] == nil then
		return
	end
	values[key] = value
	pcall(function()
		player:SetAttribute("EBSet_" .. key, value)
	end)
	for _, fn in ipairs(listeners) do
		task.spawn(fn, key, value)
	end
end

function Settings.onChanged(fn)
	table.insert(listeners, fn)
end

-- derived helpers ---------------------------------------------------------------------------------
-- particle / part budget multiplier for the current quality level
function Settings.density()
	local q = Settings.get("Quality")
	return q >= 3 and 1 or (q == 2 and 0.6 or 0.3)
end

function Settings.lightsOn()
	return Settings.get("Quality") >= 2
end

function Settings.maxEffects()
	local q = Settings.get("Quality")
	return q >= 3 and 260 or (q == 2 and 150 or 70)
end

-- flash brightness multiplier (reduced-flash caps bright pulses and disables strobing)
function Settings.flash()
	return Settings.get("ReducedFlash") and 0.35 or 1
end

function Settings.shake()
	if Settings.get("ReducedMotion") then
		return 0
	end
	return Settings.get("ShakeScale")
end

function Settings.init()
	for key in pairs(Settings.DEFAULTS) do
		local v = player:GetAttribute("EBSet_" .. key)
		if v ~= nil and typeof(v) == typeof(Settings.DEFAULTS[key]) then
			values[key] = v
		end
	end
end

return Settings
