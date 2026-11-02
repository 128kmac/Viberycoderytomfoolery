-- Shared server state + late-bound module registry (avoids require cycles).
-- Every core module registers itself here: S.Combat, S.Status, S.Hit, S.FX, S.Proj, S.Objects,
-- S.Zones, S.Summons, S.Cast, S.Fighter, S.K, S.Match, S.Kits.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local S = {}

S.Shared = ReplicatedStorage:WaitForChild("Shared")
S.Config = require(S.Shared.Config)
S.Util = require(S.Shared.Util)

S.fighters = {} -- [id] = fighter
S.byModel = {} -- [model] = fighter
S.nextId = 0
S.synergy = S.Config.START_SYNERGY

-- workspace folders
local function folder(name)
	local f = workspace:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = workspace
	end
	return f
end
S.folders = {
	Arena = folder("Arena"),
	Constructs = folder("Constructs"),
	Props = folder("Props"),
	FX = folder("FX"),
	Summons = folder("Summons"),
	Bots = folder("Bots"),
}

function S.now()
	return workspace:GetServerTimeNow()
end

function S.m(metres)
	return metres * S.Config.METRE
end

-- Simple event bus for cross-kit hooks.
S.listeners = {}
function S.on(event, fn)
	S.listeners[event] = S.listeners[event] or {}
	table.insert(S.listeners[event], fn)
	return function()
		local l = S.listeners[event]
		if l then
			local i = table.find(l, fn)
			if i then
				table.remove(l, i)
			end
		end
	end
end
function S.emit(event, ...)
	local l = S.listeners[event]
	if not l then
		return
	end
	for _, fn in ipairs(table.clone(l)) do
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("[EB] listener error for " .. event .. ": " .. tostring(err))
		end
	end
end

function S.alive(f)
	return f ~= nil and not f.dead and f.root ~= nil and f.root.Parent ~= nil
end

function S.isEnemy(a, b)
	if a == nil or b == nil then
		return false
	end
	local oa = a.owner or a
	local ob = b.owner or b
	if oa == ob then
		return false
	end
	if oa.team ~= nil and oa.team == ob.team then
		return false
	end
	return true
end

function S.isAlly(a, b)
	if a == nil or b == nil then
		return false
	end
	return not S.isEnemy(a, b)
end

-- "Real player" for Proxima/passives: players, bots, (optionally) dummies; never summons.
function S.isReal(f)
	if f == nil or f.isSummon then
		return false
	end
	if f.player then
		return true
	end
	return S.Config.DUMMIES_COUNT_AS_REAL and (f.isBot or f.isDummy) or false
end

function S.forEachFighter(fn)
	for _, f in pairs(S.fighters) do
		if S.alive(f) then
			fn(f)
		end
	end
end

function S.safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[EB] " .. tostring(err))
	end
	return ok, err
end

return S
