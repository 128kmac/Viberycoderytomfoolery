--!nocheck
-- Visual + audio language per power. Every power belongs to a family that defines HOW its effects move
-- and read (shape, motion, material, particles, light, impact, sound); its own colours tint it.
-- The eight showcase powers additionally get bespoke choreography in the client VFX (VFX/Showcase).
local Util = require(script.Parent.Util)

local Styles = {}

--[[ family fields
	shape     projectile body: "orb" | "shard" | "bolt" | "drop" | "crescent" | "chunk" | "well" | "ray" | "seed" | "rune"
	material  body material
	particle  "flame" | "frost" | "spark" | "drip" | "streak" | "dust" | "mote" | "glint" | "leaf" | "wisp"
	motion    "flicker" | "spin" | "jitter" | "wobble" | "swirl" | "tumble" | "orbit" | "pulse" | "sway" | "drift"
	impact    "blast" | "shatter" | "arc" | "splash" | "gust" | "quake" | "implode" | "flare" | "bloom" | "glyph"
	light     PointLight brightness multiplier (0 = none)
	trail     trail lifetime (s)
	sound     key into the SoundBank families
]]
Styles.FAMILIES = {
	flame = { shape = "orb", material = Enum.Material.Neon, particle = "flame", motion = "flicker", impact = "blast", light = 1.4, trail = 0.22, sound = "flame", shake = 1.0 },
	frost = { shape = "shard", material = Enum.Material.Glass, particle = "frost", motion = "spin", impact = "shatter", light = 0.7, trail = 0.18, sound = "frost", shake = 0.7 },
	storm = { shape = "bolt", material = Enum.Material.Neon, particle = "spark", motion = "jitter", impact = "arc", light = 1.6, trail = 0.08, sound = "storm", shake = 0.8 },
	tide = { shape = "drop", material = Enum.Material.Glass, particle = "drip", motion = "wobble", impact = "splash", light = 0.4, trail = 0.3, sound = "tide", shake = 0.6 },
	gale = { shape = "crescent", material = Enum.Material.ForceField, particle = "streak", motion = "swirl", impact = "gust", light = 0, trail = 0.35, sound = "gale", shake = 0.5 },
	stone = { shape = "chunk", material = Enum.Material.Slate, particle = "dust", motion = "tumble", impact = "quake", light = 0, trail = 0.12, sound = "stone", shake = 1.3 },
	gravity = { shape = "well", material = Enum.Material.ForceField, particle = "mote", motion = "orbit", impact = "implode", light = 0.9, trail = 0.25, sound = "gravity", shake = 1.1 },
	radiant = { shape = "ray", material = Enum.Material.Neon, particle = "glint", motion = "pulse", impact = "flare", light = 1.8, trail = 0.2, sound = "radiant", shake = 0.6 },
	verdant = { shape = "seed", material = Enum.Material.Grass, particle = "leaf", motion = "sway", impact = "bloom", light = 0, trail = 0.25, sound = "verdant", shake = 0.6 },
	eldritch = { shape = "rune", material = Enum.Material.Neon, particle = "wisp", motion = "drift", impact = "glyph", light = 0.9, trail = 0.28, sound = "eldritch", shake = 0.7 },
}

local FAMILY_OF = {
	-- flame
	Fire = "flame", Lava = "flame", Solar = "flame", Phoenix = "flame", Ash = "flame", Explosion = "flame",
	Nuclear = "flame", Dragon = "flame", Demon = "flame",
	-- frost
	Ice = "frost", Snow = "frost", Crystal = "frost", Glass = "frost", Mirror = "frost",
	-- storm
	Electric = "storm", Storm = "storm", Plasma = "storm", Laser = "storm", Energy = "storm", Pulse = "storm",
	Technology = "storm", Engine = "storm", Glitch = "storm",
	-- tide
	Water = "tide", Mist = "tide", Slime = "tide", Acid = "tide", Poison = "tide", Ink = "tide", Mud = "tide", Candy = "tide",
	-- gale
	Wind = "gale", Cloud = "gale", Fly = "gale", Sound = "gale", Music = "gale", Agility = "gale",
	-- stone
	Earth = "stone", Rock = "stone", Sand = "stone", Steel = "stone", Gold = "stone", Bone = "stone", Size = "stone",
	Destruction = "stone", Power = "stone", Fight = "stone", Weapon = "stone", Shot = "stone", Slasher = "stone",
	Normal = "stone", Elasticity = "stone", Defensive = "stone",
	-- gravity / cosmic
	Gravity = "gravity", Space = "gravity", Void = "gravity", Cosmic = "gravity", Star = "gravity", Lunar = "gravity",
	Time = "gravity", Dark = "gravity", Shadow = "gravity", Nightmare = "gravity", Psychic = "gravity",
	-- radiant
	Light = "radiant", Angel = "radiant", Heal = "radiant", Life = "radiant", Love = "radiant", Fairy = "radiant",
	Rainbow = "radiant", Magic = "radiant", Arcane = "radiant", ["Yin Yang"] = "radiant",
	-- verdant
	Nature = "verdant", Plant = "verdant", Flower = "verdant", Thorn = "verdant", Insect = "verdant", Animal = "verdant",
	Beast = "verdant", Reptile = "verdant", Eater = "verdant",
	-- eldritch
	Chaos = "eldritch", Corrupt = "eldritch", Death = "eldritch", Vampire = "eldritch", Blood = "eldritch",
	Witch = "eldritch", Ghost = "eldritch", Illusion = "eldritch", Mystery = "eldritch", Dream = "eldritch",
	Copy = "eldritch", Duplication = "eldritch", Creation = "eldritch", Alchemist = "eldritch", Circus = "eldritch",
	Paper = "eldritch", Thread = "eldritch",
}
Styles.FAMILY_OF = FAMILY_OF

-- Showcase powers: bespoke choreography for every move, signature ultimates.
Styles.SHOWCASE = {
	Fire = true, Ice = true, Electric = true, Gravity = true, Water = true, Wind = true, Earth = true, Light = true,
}

-- per-power tweaks layered on the family
local OVERRIDES = {
	Void = { glow = Color3.fromRGB(150, 70, 255) },
	Space = { glow = Color3.fromRGB(120, 110, 255) },
	Shadow = { glow = Color3.fromRGB(120, 90, 160) },
	Dark = { glow = Color3.fromRGB(150, 90, 220) },
	Ink = { glow = Color3.fromRGB(90, 100, 160), material = Enum.Material.SmoothPlastic },
	Nightmare = { glow = Color3.fromRGB(200, 40, 140) },
	Death = { glow = Color3.fromRGB(150, 230, 170) },
	Gravity = { glow = Color3.fromRGB(190, 140, 255) },
	Mud = { material = Enum.Material.Mud, light = 0 },
	Slime = { material = Enum.Material.Neon },
	Acid = { material = Enum.Material.Neon },
	Poison = { material = Enum.Material.Neon },
	Candy = { material = Enum.Material.SmoothPlastic, particle = "glint" },
	Steel = { material = Enum.Material.Metal, particle = "spark", impact = "arc" },
	Gold = { material = Enum.Material.Foil, particle = "glint" },
	Bone = { material = Enum.Material.SmoothPlastic },
	Sand = { material = Enum.Material.Sand },
	Glass = { material = Enum.Material.Glass },
	Crystal = { material = Enum.Material.Glass },
	Laser = { shape = "ray" },
	Lava = { material = Enum.Material.CrackedLava },
	Ash = { particle = "dust" },
	Cloud = { material = Enum.Material.SmoothPlastic, particle = "dust" },
	Sound = { shape = "crescent", impact = "gust", particle = "glint" },
	Music = { particle = "glint" },
	Star = { particle = "glint" },
	Cosmic = { particle = "glint" },
	Time = { shape = "rune" },
	Psychic = { shape = "orb" },
	Blood = { shape = "drop", particle = "drip", impact = "splash" },
	Vampire = { shape = "drop" },
	Paper = { material = Enum.Material.Fabric, shape = "crescent", particle = "leaf" },
	Thread = { shape = "ray", particle = "streak" },
	Glitch = { shape = "chunk", motion = "jitter" },
	Technology = { shape = "chunk" },
	Engine = { particle = "dust" },
}

local cache = {}

-- style for a power: family fields + colours. Unknown powers fall back to "eldritch" with their colour.
function Styles.of(kit)
	if not kit then
		kit = "?"
	end
	local s = cache[kit]
	if s then
		return s
	end
	local famName = FAMILY_OF[kit] or "eldritch"
	local fam = Styles.FAMILIES[famName]
	s = {}
	for k, v in pairs(fam) do
		s[k] = v
	end
	s.family = famName
	s.kit = kit
	local base = Util.ElementColors[kit] or Color3.fromRGB(230, 230, 240)
	s.color = base
	local h, sat, v = base:ToHSV()
	-- glow: bright version for emissive cores; deep: shadowed version for smoke / bodies
	s.glow = Color3.fromHSV(h, math.min(sat, 0.75), math.max(v, 0.92))
	s.deep = Color3.fromHSV(h, math.min(1, sat * 1.1), v * 0.45)
	s.pale = Color3.fromHSV(h, sat * 0.35, 1)
	local o = OVERRIDES[kit]
	if o then
		for k, val in pairs(o) do
			s[k] = val
		end
	end
	s.showcase = Styles.SHOWCASE[kit] == true
	cache[kit] = s
	return s
end

return Styles
