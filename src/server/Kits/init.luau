-- Kit registry: maps power names to behaviour modules (children of this module) and generated data.
local S = require(script.Parent.Core.S)

local Kits = {}
S.Kits = Kits

local KitDataFolder = S.Shared:WaitForChild("KitData")
local Index = require(S.Shared:WaitForChild("KitIndex"))
Kits.index = Index

local nameToId = {}
local idToName = {}
for _, e in ipairs(Index) do
	nameToId[e.name] = e.id
	nameToId[e.id] = e.id
	nameToId[string.lower(e.name)] = e.id
	idToName[e.id] = e.name
end

local cache = {}
local dataCache = {}

function Kits.id(name)
	return name and nameToId[name] or nil
end

function Kits.displayName(name)
	local id = Kits.id(name)
	return id and idToName[id] or nil
end

function Kits.data(name)
	local id = Kits.id(name)
	if not id then
		return nil
	end
	if not dataCache[id] then
		local mod = KitDataFolder:FindFirstChild(id)
		if not mod then
			return nil
		end
		dataCache[id] = require(mod)
	end
	return dataCache[id]
end

-- Fallback behaviour used only if a kit module is missing or fails to load, so a broken kit never
-- breaks the server. It reads the first damage figure from each move description.
local function fallback(id)
	local K = S.K
	local data = Kits.data(id)
	local kit = { passive = {} }
	for slot = 1, 5 do
		local def = data.moves[slot]
		local dmg = tonumber(string.match(def.desc, "(%d+) damage")) or (slot == 5 and 150 or 60)
		kit[slot] = function(c)
			if slot == 5 then
				local pos = c:aimPoint(def.range > 0 and def.range or 10)
				if K.warn(c, pos, 6, 1) then
					K.circle(c, pos, 6, { dmg = dmg })
				end
			elseif def.range == 0 then
				K.circle(c, c:feet(), 4, { dmg = dmg })
			else
				K.proj(c, { dmg = dmg, range = def.range })
			end
		end
	end
	return kit
end

function Kits.get(name)
	local id = Kits.id(name)
	if not id then
		return nil
	end
	if cache[id] then
		return cache[id]
	end
	local mod = script:FindFirstChild(id)
	local kit
	if mod then
		local ok, res = pcall(require, mod)
		if ok and type(res) == "table" then
			kit = res
		else
			warn("[EB] kit " .. id .. " failed to load: " .. tostring(res))
		end
	end
	if not kit then
		kit = fallback(id)
		kit.isFallback = true
	end
	cache[id] = kit
	return kit
end

function Kits.names()
	local out = {}
	for _, e in ipairs(Index) do
		table.insert(out, e.name)
	end
	return out
end

function Kits.random(rng)
	rng = rng or Random.new()
	return Index[rng:NextInteger(1, #Index)].name
end

return Kits
