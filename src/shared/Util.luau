-- EB: Proxima — small shared helpers.
local Config = require(script.Parent.Config)

local Util = {}

local M = Config.METRE

function Util.m(metres)
	return metres * M
end

function Util.toMetres(studs)
	return studs / M
end

function Util.flat(v)
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-4 then
		return Vector3.new(0, 0, -1)
	end
	return f.Unit
end

function Util.flatDist(a, b)
	local d = a - b
	return Vector3.new(d.X, 0, d.Z).Magnitude
end

function Util.rotateY(v, degrees)
	return CFrame.Angles(0, math.rad(degrees), 0):VectorToWorldSpace(v)
end

function Util.angleBetween(a, b)
	local au, bu = a.Unit, b.Unit
	local d = math.clamp(au:Dot(bu), -1, 1)
	return math.deg(math.acos(d))
end

function Util.shuffle(t, rng)
	rng = rng or Random.new()
	for i = #t, 2, -1 do
		local j = rng:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

function Util.copy(t)
	local r = {}
	for k, v in pairs(t) do
		r[k] = v
	end
	return r
end

function Util.round(x, step)
	step = step or 1
	return math.floor(x / step + 0.5) * step
end

function Util.fmt(n)
	if math.abs(n - math.floor(n)) < 0.05 then
		return tostring(math.floor(n + 0.5))
	end
	return string.format("%.1f", n)
end

-- Element colours (each important colour is also paired with text/shape cues on the client).
Util.ElementColors = {
	Acid = Color3.fromRGB(170, 255, 60), Agility = Color3.fromRGB(120, 230, 255), Alchemist = Color3.fromRGB(230, 190, 90),
	Angel = Color3.fromRGB(255, 250, 220), Animal = Color3.fromRGB(170, 120, 70), Arcane = Color3.fromRGB(160, 90, 255),
	Ash = Color3.fromRGB(120, 115, 110), Beast = Color3.fromRGB(150, 60, 40), Blood = Color3.fromRGB(170, 0, 20),
	Bone = Color3.fromRGB(235, 225, 200), Candy = Color3.fromRGB(255, 130, 200), Chaos = Color3.fromRGB(255, 60, 160),
	Circus = Color3.fromRGB(255, 80, 80), Cloud = Color3.fromRGB(230, 240, 255), Copy = Color3.fromRGB(180, 180, 200),
	Corrupt = Color3.fromRGB(110, 0, 130), Cosmic = Color3.fromRGB(80, 60, 200), Creation = Color3.fromRGB(255, 220, 120),
	Crystal = Color3.fromRGB(150, 230, 255), Dark = Color3.fromRGB(40, 20, 60), Death = Color3.fromRGB(60, 70, 60),
	Defensive = Color3.fromRGB(90, 140, 200), Demon = Color3.fromRGB(200, 30, 30), Destruction = Color3.fromRGB(255, 100, 0),
	Dragon = Color3.fromRGB(220, 60, 30), Dream = Color3.fromRGB(200, 170, 255), Duplication = Color3.fromRGB(120, 200, 200),
	Earth = Color3.fromRGB(130, 100, 60), Eater = Color3.fromRGB(140, 60, 120), Elasticity = Color3.fromRGB(255, 170, 80),
	Electric = Color3.fromRGB(255, 240, 60), Energy = Color3.fromRGB(80, 255, 220), Engine = Color3.fromRGB(150, 150, 150),
	Explosion = Color3.fromRGB(255, 140, 30), Fairy = Color3.fromRGB(255, 190, 255), Fly = Color3.fromRGB(200, 230, 250),
	Fight = Color3.fromRGB(230, 120, 60), Fire = Color3.fromRGB(255, 90, 20), Flower = Color3.fromRGB(255, 150, 190),
	Ghost = Color3.fromRGB(190, 230, 255), Heal = Color3.fromRGB(110, 255, 140), Glass = Color3.fromRGB(200, 240, 240),
	Glitch = Color3.fromRGB(0, 255, 140), Gold = Color3.fromRGB(255, 200, 40), Gravity = Color3.fromRGB(100, 60, 160),
	Ice = Color3.fromRGB(160, 220, 255), Illusion = Color3.fromRGB(220, 140, 255), Ink = Color3.fromRGB(25, 25, 40),
	Insect = Color3.fromRGB(120, 140, 30), Laser = Color3.fromRGB(255, 30, 60), Lava = Color3.fromRGB(255, 70, 0),
	Life = Color3.fromRGB(140, 255, 120), Light = Color3.fromRGB(255, 255, 180), Love = Color3.fromRGB(255, 90, 140),
	Lunar = Color3.fromRGB(200, 210, 255), Magic = Color3.fromRGB(190, 80, 255), Mirror = Color3.fromRGB(220, 230, 240),
	Mist = Color3.fromRGB(200, 210, 220), Mud = Color3.fromRGB(100, 75, 45), Music = Color3.fromRGB(255, 120, 220),
	Mystery = Color3.fromRGB(90, 70, 130), Nature = Color3.fromRGB(60, 170, 60), Nightmare = Color3.fromRGB(70, 0, 50),
	Normal = Color3.fromRGB(200, 200, 200), Nuclear = Color3.fromRGB(120, 255, 0), Paper = Color3.fromRGB(245, 240, 225),
	Phoenix = Color3.fromRGB(255, 120, 30), Plant = Color3.fromRGB(80, 200, 80), Plasma = Color3.fromRGB(255, 60, 255),
	Poison = Color3.fromRGB(130, 40, 200), Power = Color3.fromRGB(255, 220, 0), Pulse = Color3.fromRGB(0, 200, 255),
	Psychic = Color3.fromRGB(255, 100, 255), Rainbow = Color3.fromRGB(255, 160, 60), Reptile = Color3.fromRGB(80, 140, 60),
	Rock = Color3.fromRGB(120, 110, 100), Sand = Color3.fromRGB(230, 200, 130), Shot = Color3.fromRGB(255, 210, 120),
	Shadow = Color3.fromRGB(30, 30, 40), Size = Color3.fromRGB(255, 160, 120), Slasher = Color3.fromRGB(200, 0, 40),
	Slime = Color3.fromRGB(90, 255, 120), Snow = Color3.fromRGB(240, 250, 255), Solar = Color3.fromRGB(255, 180, 0),
	Sound = Color3.fromRGB(120, 180, 255), Space = Color3.fromRGB(30, 20, 80), Star = Color3.fromRGB(255, 240, 150),
	Steel = Color3.fromRGB(170, 180, 190), Storm = Color3.fromRGB(90, 100, 160), Technology = Color3.fromRGB(0, 170, 255),
	Thread = Color3.fromRGB(240, 220, 200), Thorn = Color3.fromRGB(70, 110, 40), Time = Color3.fromRGB(210, 180, 100),
	Vampire = Color3.fromRGB(140, 0, 40), Void = Color3.fromRGB(15, 0, 30), Water = Color3.fromRGB(40, 140, 255),
	Weapon = Color3.fromRGB(190, 190, 210), Wind = Color3.fromRGB(190, 255, 230), Witch = Color3.fromRGB(110, 60, 150),
	["Yin Yang"] = Color3.fromRGB(245, 245, 245),
}

function Util.color(element)
	return Util.ElementColors[element] or Color3.fromRGB(255, 255, 255)
end

return Util
