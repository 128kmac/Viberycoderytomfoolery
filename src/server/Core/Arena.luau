-- Procedural compact arena: ~67 m square platform, solid walls for wall-running, raised platforms,
-- destructible neutral cover pillars (respawning), spawn pads and a training lane.
local Lighting = game:GetService("Lighting")
local S = require(script.Parent.S)

local Arena = {}
S.Arena = Arena

local M = S.Config.METRE
local SIZE = 200 -- studs
local FLOOR_Y = 0

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = props.Parent or S.folders.Arena
	return p
end

local function wedge(props)
	local p = Instance.new("WedgePart")
	p.Anchored = true
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = S.folders.Arena
	return p
end

Arena.spawns = {}
Arena.dummySpots = {}
Arena.coverSpots = {}

local function spawnCover(pos, size)
	local obj = S.Objects.create({
		owner = nil,
		name = "Cover",
		cf = CFrame.new(pos + Vector3.new(0, size.Y / 2, 0)),
		size = size,
		hp = 400,
		color = Color3.fromRGB(150, 140, 125),
		material = Enum.Material.Cobblestone,
		noCap = true,
		tags = { cover = true, terrain = true },
	})
	obj.onDestroy = function()
		task.delay(20, function()
			spawnCover(pos, size)
		end)
	end
	return obj
end

function Arena.build()
	for _, c in ipairs(S.folders.Arena:GetChildren()) do
		c:Destroy()
	end
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	workspace.FallenPartsDestroyHeight = -2000
	workspace.Gravity = 196.2

	local center = Vector3.new(0, FLOOR_Y, 0)
	S.arenaBounds = { center = center, half = SIZE / 2, floorY = FLOOR_Y }

	-- floor (two-tone tiles for readable distances: each tile is 4 m)
	part({
		Name = "Floor",
		Size = Vector3.new(SIZE, 4, SIZE),
		CFrame = CFrame.new(center - Vector3.new(0, 2, 0)),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(70, 74, 88),
	})
	local tile = 4 * M
	local n = math.floor(SIZE / tile)
	for i = 0, n - 1 do
		for j = 0, n - 1 do
			if (i + j) % 2 == 0 then
				part({
					Name = "Tile",
					Size = Vector3.new(tile, 0.05, tile),
					CFrame = CFrame.new(-SIZE / 2 + tile * (i + 0.5), FLOOR_Y + 0.03, -SIZE / 2 + tile * (j + 0.5)),
					Material = Enum.Material.SmoothPlastic,
					Color = Color3.fromRGB(78, 82, 98),
					CanCollide = false,
					CanQuery = false,
				})
			end
		end
	end
	-- low rim with gaps at corners (forced displacement can threaten the out-of-bounds penalty there)
	local rimH = 1.6
	for _, side in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local len = SIZE - 40
		local x, z = side[1] * (SIZE / 2 - 0.5), side[2] * (SIZE / 2 - 0.5)
		part({
			Name = "Rim",
			Size = side[1] ~= 0 and Vector3.new(1, rimH, len) or Vector3.new(len, rimH, 1),
			CFrame = CFrame.new(x, FLOOR_Y + rimH / 2, z),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(110, 115, 130),
		})
	end
	-- central dais
	part({
		Name = "Dais",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 36, 36),
		CFrame = CFrame.new(0, FLOOR_Y + 0.8, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Marble,
		Color = Color3.fromRGB(200, 195, 185),
	})
	part({
		Name = "DaisGlow",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.7, 6, 6),
		CFrame = CFrame.new(0, FLOOR_Y + 0.8, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(120, 200, 255),
		CanCollide = false,
	})
	-- four solid walls (indestructible) for cover and wall routes
	local wallSpecs = {
		{ Vector3.new(-45, 0, -20), Vector3.new(4, 14, 34) },
		{ Vector3.new(45, 0, 20), Vector3.new(4, 14, 34) },
		{ Vector3.new(20, 0, -45), Vector3.new(34, 14, 4) },
		{ Vector3.new(-20, 0, 45), Vector3.new(34, 14, 4) },
	}
	for _, w in ipairs(wallSpecs) do
		part({
			Name = "Wall",
			Size = w[2],
			CFrame = CFrame.new(w[1] + Vector3.new(0, FLOOR_Y + w[2].Y / 2, 0)),
			Material = Enum.Material.Brick,
			Color = Color3.fromRGB(120, 85, 70),
		})
	end
	-- two raised platforms with ramps
	for _, sgn in ipairs({ 1, -1 }) do
		local pc = Vector3.new(sgn * 62, FLOOR_Y, -sgn * 62)
		part({
			Name = "Platform",
			Size = Vector3.new(30, 7, 30),
			CFrame = CFrame.new(pc + Vector3.new(0, 3.5, 0)),
			Material = Enum.Material.Concrete,
			Color = Color3.fromRGB(95, 100, 115),
		})
		wedge({
			Name = "Ramp",
			Size = Vector3.new(10, 7, 18),
			CFrame = CFrame.new(pc + Vector3.new(0, 3.5, sgn * 24)) * CFrame.Angles(0, sgn > 0 and math.pi or 0, 0),
			Material = Enum.Material.Concrete,
			Color = Color3.fromRGB(95, 100, 115),
		})
	end
	-- spawn pads
	table.clear(Arena.spawns)
	for i = 0, 7 do
		local a = i * math.pi / 4 + math.pi / 8
		local p = Vector3.new(math.cos(a) * 80, FLOOR_Y, math.sin(a) * 80)
		table.insert(Arena.spawns, p)
		part({
			Name = "SpawnPad",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, 10, 10),
			CFrame = CFrame.new(p + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(90, 160, 255),
			CanCollide = false,
			CanQuery = false,
			Transparency = 0.4,
		})
	end
	-- destructible cover pillars
	local coverSpots = {
		Vector3.new(-25, 0, -25), Vector3.new(25, 0, 25), Vector3.new(-25, 0, 25), Vector3.new(25, 0, -25),
		Vector3.new(0, 0, -55), Vector3.new(0, 0, 55), Vector3.new(-55, 0, 0), Vector3.new(55, 0, 0),
	}
	for _, p in ipairs(coverSpots) do
		spawnCover(p + Vector3.new(0, FLOOR_Y, 0), Vector3.new(6, 9, 6))
	end
	-- training lane (dummies)
	table.clear(Arena.dummySpots)
	for i = 1, 4 do
		table.insert(Arena.dummySpots, Vector3.new(-80 + i * 9, FLOOR_Y, 88))
	end
	part({
		Name = "TrainingSign",
		Size = Vector3.new(30, 4, 0.5),
		CFrame = CFrame.new(-57, FLOOR_Y + 9, 96),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(40, 40, 60),
		CanCollide = false,
		CanQuery = false,
	})
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.Parent = S.folders.Arena.TrainingSign
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Text = "TRAINING DUMMIES"
	tl.TextScaled = true
	tl.Font = Enum.Font.GothamBlack
	tl.TextColor3 = Color3.fromRGB(255, 255, 255)
	tl.Parent = sg

	-- lighting
	Lighting.ClockTime = 15.5
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(70, 70, 90)
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 120, 140)
	Lighting.GlobalShadows = true
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atm = Instance.new("Atmosphere")
		atm.Density = 0.25
		atm.Haze = 1
		atm.Color = Color3.fromRGB(190, 200, 230)
		atm.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local b = Instance.new("BloomEffect")
		b.Intensity = 0.6
		b.Size = 20
		b.Threshold = 1.6
		b.Parent = Lighting
	end
end

function Arena.randomSpawn()
	local best, bestScore
	for _, p in ipairs(Arena.spawns) do
		-- prefer pads far from fighters
		local score = 0
		for _, f in pairs(S.fighters) do
			if S.alive(f) and not f.isSummon then
				score += math.min(60, (f.root.Position - p).Magnitude)
			end
		end
		score += math.random() * 30
		if not bestScore or score > bestScore then
			best, bestScore = p, score
		end
	end
	return (best or Vector3.new(0, 0, 0)) + Vector3.new(0, 4, 0)
end

return Arena
