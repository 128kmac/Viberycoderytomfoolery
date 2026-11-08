-- PROXIMA OBSERVATORY — a compact floating observatory under the red dwarf Proxima.
--
--   Central Orrery Plaza  raised dais, ring of cover walls (four diagonal gaps), the Orrery pillar and its
--                         burning core; slow orbital rings overhead (decorative, non-colliding, unqueryable)
--   Ember Forge   (NE)    two open-roofed forge halls, narrow alleys, anvils, a grated lava trench
--   Tidal Cistern (SE)    shallow wading pool with arches, a raised rim walkway and two bridges
--   Verdant Terraces (SW) three stepped levels (ramps + jumpable 4-stud walls), hedge lines, the great tree
--   Storm Spire   (NW)    10-stud high platform with tesla coils; the Gale Bridge drops toward the plaza
--   Avenues + Outer Ring  open N/E/S/W avenues (long sightlines) and a flanking ring walkway
--   Spawn alcoves         eight recessed alcoves with front cover (Sun: south half, Moon: north half)
--   Training Annex        practice range south of the island across the Annex Bridge
--
-- Rules: anything that looks solid at body height collides and stops shots; purely decorative pieces
-- (rings, banners, canopy, light shafts, distant scenery) are CanCollide = false and CanQuery = false.
-- Boundaries: a balustrade plus an invisible barrier around the island and annex; out-of-bounds recovery
-- in Fighter.outOfBounds handles anything that still escapes. Environmental motion is client-side (tags).
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local S = require(script.Parent.S)

local Arena = {}
S.Arena = Arena

local M = S.Config.METRE
local FLOOR_Y = 0
local R_ISLAND = 100
local folder

Arena.spawns = {}
Arena.dummySpots = {}
Arena.annex = nil

-- palette / districts (accent colours double as wayfinding)
local STONE_D = Color3.fromRGB(62, 58, 74)
local MARBLE = Color3.fromRGB(196, 190, 202)
local TRIM = Color3.fromRGB(210, 170, 110)
local EMBER = Color3.fromRGB(255, 120, 50)
local TIDE = Color3.fromRGB(70, 200, 255)
local VERDANT = Color3.fromRGB(120, 230, 110)
local STORM = Color3.fromRGB(170, 120, 255)
local CORE = Color3.fromRGB(255, 96, 52)

-- Builders -----------------------------------------------------------------------------------------
local function part(props, class)
	local p = Instance.new(class or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local parent = props.Parent or folder
	for k, v in pairs(props) do
		if k ~= "Parent" and k ~= "Tags" and k ~= "Deco" then
			p[k] = v
		end
	end
	if props.Deco then
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
	end
	if props.Tags then
		for _, t in ipairs(props.Tags) do
			CollectionService:AddTag(p, t)
		end
	end
	p.Parent = parent
	return p
end

local function box(name, size, cf, mat, color, extra)
	local props = { Name = name, Size = size, CFrame = cf, Material = mat, Color = color }
	for k, v in pairs(extra or {}) do
		props[k] = v
	end
	return part(props)
end

-- vertical cylinder standing on pos.Y
local function cyl(name, radius, height, pos, mat, color, extra)
	local props = {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(pos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = mat,
		Color = color,
	}
	for k, v in pairs(extra or {}) do
		props[k] = v
	end
	return part(props)
end

local function ball(name, radius, pos, mat, color, extra)
	local props = { Name = name, Shape = Enum.PartType.Ball, Size = Vector3.one * radius * 2, CFrame = CFrame.new(pos), Material = mat, Color = color }
	for k, v in pairs(extra or {}) do
		props[k] = v
	end
	return part(props)
end

-- wall segment between two ground points (a.Y is the base height)
local function wall(name, a, b, height, thick, mat, color, extra)
	local mid = (a + b) / 2
	local cf = CFrame.lookAt(Vector3.new(mid.X, a.Y + height / 2, mid.Z), Vector3.new(b.X, a.Y + height / 2, b.Z))
	local len = (Vector3.new(b.X, 0, b.Z) - Vector3.new(a.X, 0, a.Z)).Magnitude
	return box(name, Vector3.new(thick, height, len), cf, mat, color, extra)
end

-- ramp rising `rise` studs over `length` along flat direction d, starting at ground point a
local function ramp(name, a, d, length, width, rise, mat, color)
	d = Vector3.new(d.X, 0, d.Z).Unit
	local c = a + d * (length / 2) + Vector3.new(0, rise / 2, 0)
	return part({
		Name = name,
		Size = Vector3.new(width, rise, length),
		CFrame = CFrame.lookAt(c, c - d),
		Material = mat,
		Color = color,
	}, "WedgePart")
end

local function light(p, color, brightness, range, flicker)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = p
	if flicker then
		CollectionService:AddTag(l, "EBFlicker")
	end
	return l
end

local function neonStrip(a, b, color, y, width)
	local mid = (a + b) / 2
	local len = (Vector3.new(b.X, 0, b.Z) - Vector3.new(a.X, 0, a.Z)).Magnitude
	return box("Inlay", Vector3.new(width or 0.6, 0.06, len), CFrame.lookAt(Vector3.new(mid.X, y + 0.03, mid.Z), Vector3.new(b.X, y + 0.03, b.Z)), Enum.Material.Neon, color, { CanCollide = false, CanQuery = false, CastShadow = false })
end

local function polar(r, deg, y)
	local a = math.rad(deg)
	return Vector3.new(math.cos(a) * r, y or FLOOR_Y, math.sin(a) * r)
end

local function sign(name, size, cf, face, text, color)
	local p = box(name, size, cf, Enum.Material.SmoothPlastic, Color3.fromRGB(28, 26, 36), { CanCollide = false, CanQuery = false })
	-- district signs stand on a pair of posts (gateway), never floating
	if name == "DistrictSign" then
		for _, sx in ipairs({ -1, 1 }) do
			local top = cf * Vector3.new(sx * (size.X / 2 - 0.6), -size.Y / 2, 0)
			cyl("SignPost", 0.45, top.Y, Vector3.new(top.X, FLOOR_Y, top.Z), Enum.Material.Metal, Color3.fromRGB(70, 66, 80))
		end
		box("SignTrim", Vector3.new(size.X, 0.15, size.Z + 0.1), cf * CFrame.new(0, size.Y / 2 + 0.08, 0), Enum.Material.Neon, color, { CanCollide = false, CanQuery = false })
	end
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.Parent = p
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Text = text
	tl.TextScaled = true
	tl.Font = Enum.Font.GothamBlack
	tl.TextColor3 = color
	tl.Parent = sg
	return p
end

-- destructible neutral cover that rebuilds itself
local function cover(pos, size, mat, color)
	local obj = S.Objects.create({
		owner = nil,
		name = "Cover",
		cf = CFrame.new(pos + Vector3.new(0, size.Y / 2, 0)),
		size = size,
		hp = 300,
		color = color,
		material = mat,
		noCap = true,
		tags = { cover = true, terrain = true },
	})
	obj.onDestroy = function()
		task.delay(18, function()
			cover(pos, size, mat, color)
		end)
	end
	return obj
end

-- Island + boundary -----------------------------------------------------------------------------------
local function buildIsland()
	cyl("IslandFloor", R_ISLAND, 6, Vector3.new(0, FLOOR_Y - 6, 0), Enum.Material.Slate, STONE_D)
	cyl("Paving", R_ISLAND - 3, 0.1, Vector3.new(0, FLOOR_Y - 0.05, 0), Enum.Material.Pavement, Color3.fromRGB(104, 98, 112), { CanCollide = false, CanQuery = false })
	for i = 0, 3 do
		local d = polar(1, i * 90)
		neonStrip(d * 46, d * 84, Color3.fromRGB(255, 170, 120), FLOOR_Y, 0.4)
	end
	-- underside: stacked rock tiers + glowing heart (decor)
	for i, r in ipairs({ 92, 76, 58, 38 }) do
		cyl("Underside", r, 10, Vector3.new(0, FLOOR_Y - 6 - i * 10, 0), Enum.Material.Rock, Color3.fromRGB(70, 60, 64), { Deco = true })
	end
	ball("UnderCrystal", 9, Vector3.new(0, FLOOR_Y - 60, 0), Enum.Material.Neon, CORE, { Deco = true })
	-- balustrade with posts and lamps; gap at the south gate (annex bridge)
	local segs = 40
	for i = 0, segs - 1 do
		local a0, a1 = i / segs * 360, (i + 1) / segs * 360
		local mid = (a0 + a1) / 2
		local isGate = math.abs(mid - 90) < 5
		if not isGate then
			wall("Balustrade", polar(R_ISLAND - 1.2, a0), polar(R_ISLAND - 1.2, a1), 3.4, 1.2, Enum.Material.Limestone, Color3.fromRGB(176, 166, 160))
		end
		local pp = polar(R_ISLAND - 1.2, a0)
		cyl("BalusterPost", 1.1, 4.6, pp, Enum.Material.Limestone, Color3.fromRGB(150, 140, 136))
		if i % 4 == 0 then
			local lamp = ball("PostLamp", 0.7, pp + Vector3.new(0, 5.3, 0), Enum.Material.Neon, Color3.fromRGB(255, 190, 140), { CanCollide = false, CanQuery = false })
			light(lamp, Color3.fromRGB(255, 170, 120), 1.2, 16)
		end
	end
	-- invisible barrier: stops falls / knockback over the rail; shots and rays pass through
	for i = 0, 23 do
		local a0, a1 = i / 24 * 360, (i + 1) / 24 * 360
		local mid = (a0 + a1) / 2
		if math.abs(mid - 90) >= 8 then
			wall("Barrier", polar(R_ISLAND + 1.5, a0, FLOOR_Y - 2), polar(R_ISLAND + 1.5, a1, FLOOR_Y - 2), 60, 2, Enum.Material.ForceField, Color3.new(1, 1, 1), { Transparency = 1, CanQuery = false, CastShadow = false })
		end
	end
end

-- Central Orrery Plaza ---------------------------------------------------------------------------------
local function buildPlaza()
	local top = FLOOR_Y + 2
	cyl("Dais", 30, 2, Vector3.new(0, FLOOR_Y, 0), Enum.Material.Marble, MARBLE)
	cyl("DaisTrim", 30.6, 0.5, Vector3.new(0, FLOOR_Y, 0), Enum.Material.Granite, TRIM, { CanCollide = false, CanQuery = false })
	cyl("DaisInlay", 23, 0.06, Vector3.new(0, top, 0), Enum.Material.Neon, Color3.fromRGB(255, 150, 110), { CanCollide = false, CanQuery = false, Transparency = 0.6 })
	cyl("DaisInner", 22.4, 0.08, Vector3.new(0, top, 0), Enum.Material.Marble, Color3.fromRGB(176, 170, 186), { CanCollide = false, CanQuery = false })
	-- four broad ramps (avenues) + four narrower diagonal ramps
	for i = 0, 3 do
		local d = polar(1, i * 90)
		ramp("DaisRamp", d * 40, -d, 10.5, 14, 2, Enum.Material.Marble, MARBLE)
		local dd = polar(1, i * 90 + 45)
		ramp("DaisStep", dd * 38.5, -dd, 9, 8, 2, Enum.Material.Marble, Color3.fromRGB(180, 174, 188))
	end
	-- cover ring around the Orrery (open on the diagonals)
	for i = 0, 3 do
		local a0, a1 = i * 90 + 58, i * 90 + 122
		local steps = 4
		for k = 0, steps - 1 do
			local s0 = a0 + (a1 - a0) * k / steps
			local s1 = a0 + (a1 - a0) * (k + 1) / steps
			wall("OrreryWall", polar(12, s0, top), polar(12, s1, top), 4.2, 2, Enum.Material.Granite, Color3.fromRGB(120, 112, 132))
		end
		cyl("OrreryPost", 1.6, 6, polar(12, a0, top), Enum.Material.Granite, TRIM)
		cyl("OrreryPost", 1.6, 6, polar(12, a1, top), Enum.Material.Granite, TRIM)
	end
	-- the Orrery: pillar, collar, struts and the burning core
	cyl("OrreryPillar", 3.6, 30, Vector3.new(0, top, 0), Enum.Material.Granite, Color3.fromRGB(78, 72, 92))
	cyl("OrreryCollar", 5, 2, Vector3.new(0, top + 30, 0), Enum.Material.Metal, TRIM)
	local coreY = top + 40
	local core = ball("ProximaCore", 5.5, Vector3.new(0, coreY, 0), Enum.Material.Neon, CORE, { CanCollide = false, CanQuery = false, CastShadow = false, Tags = { "EBPulse" } })
	light(core, Color3.fromRGB(255, 120, 70), 4, 70)
	ball("CoreHalo", 8, Vector3.new(0, coreY, 0), Enum.Material.ForceField, Color3.fromRGB(255, 140, 90), { Deco = true, Transparency = 0.2 })
	for i = 0, 5 do
		local a = i * 60
		wall("CoreStrut", polar(4.6, a, top + 32), polar(1.5, a, top + 32), 7, 0.6, Enum.Material.Metal, TRIM, { Deco = true })
	end
	-- orbital rings (spun client-side about their pivot)
	local ringSpecs = {
		{ r = 15, tilt = 18, speed = 6, color = Color3.fromRGB(230, 190, 120), planet = { 2.2, Color3.fromRGB(110, 170, 255) } },
		{ r = 21, tilt = -12, speed = -4, color = Color3.fromRGB(200, 160, 110), planet = { 3, Color3.fromRGB(255, 140, 90) } },
		{ r = 27, tilt = 7, speed = 2.5, color = Color3.fromRGB(170, 140, 120), planet = { 1.8, Color3.fromRGB(170, 255, 200) } },
	}
	for idx, spec in ipairs(ringSpecs) do
		local model = Instance.new("Model")
		model.Name = "OrreryRing" .. idx
		local center = CFrame.new(0, coreY, 0) * CFrame.Angles(math.rad(spec.tilt), 0, math.rad(spec.tilt * 0.5))
		local n = 36
		for k = 0, n - 1 do
			local a = k / n * math.pi * 2
			local cf = center * CFrame.new(math.cos(a) * spec.r, 0, math.sin(a) * spec.r) * CFrame.Angles(0, -a, 0)
			part({ Name = "RingSeg", Size = Vector3.new(0.5, 0.35, 2 * math.pi * spec.r / n * 1.05), CFrame = cf, Material = Enum.Material.Metal, Color = spec.color, Deco = true, Parent = model })
		end
		part({ Name = "Planet", Shape = Enum.PartType.Ball, Size = Vector3.one * spec.planet[1] * 2, CFrame = center * CFrame.new(spec.r, 0, 0), Material = Enum.Material.Neon, Color = spec.planet[2], Deco = true, Parent = model })
		local pivot = part({ Name = "Pivot", Size = Vector3.one, CFrame = center, Transparency = 1, Deco = true, Parent = model })
		model.PrimaryPart = pivot
		model:SetAttribute("SpinSpeed", spec.speed)
		model.Parent = folder
		CollectionService:AddTag(model, "EBSpin")
	end
end

-- Ember Forge (NE: +X, -Z) ---------------------------------------------------------------------------
local function buildForge()
	local brick = Color3.fromRGB(120, 72, 58)
	local dark = Color3.fromRGB(58, 46, 44)
	local function hall(center, sx, sz, doors)
		local h = 11
		local x0, x1 = center.X - sx / 2, center.X + sx / 2
		local z0, z1 = center.Z - sz / 2, center.Z + sz / 2
		local sides = {
			{ Vector3.new(x0, 0, z0), Vector3.new(x1, 0, z0), "N" },
			{ Vector3.new(x1, 0, z0), Vector3.new(x1, 0, z1), "E" },
			{ Vector3.new(x1, 0, z1), Vector3.new(x0, 0, z1), "S" },
			{ Vector3.new(x0, 0, z1), Vector3.new(x0, 0, z0), "W" },
		}
		for _, sd in ipairs(sides) do
			local a, b, key = sd[1], sd[2], sd[3]
			if doors[key] then
				local mid = (a + b) / 2
				local dir = (b - a).Unit
				wall("ForgeWall", a, mid - dir * 4, h, 2, Enum.Material.Brick, brick)
				wall("ForgeWall", mid + dir * 4, b, h, 2, Enum.Material.Brick, brick)
				wall("ForgeLintel", mid - dir * 4 + Vector3.new(0, 8, 0), mid + dir * 4 + Vector3.new(0, 8, 0), h - 8, 2, Enum.Material.Brick, dark)
			else
				wall("ForgeWall", a, b, h, 2, Enum.Material.Brick, brick)
			end
			neonStrip(a, b, EMBER, h + 0.01, 0.5)
		end
		local cpos = Vector3.new(x1 - 3, 0, z0 + 3)
		box("Chimney", Vector3.new(5, 26, 5), CFrame.new(cpos + Vector3.new(0, 13, 0)), Enum.Material.Brick, dark)
		local ember = ball("ChimneyEmber", 1.4, cpos + Vector3.new(0, 26.5, 0), Enum.Material.Neon, EMBER, { CanCollide = false, CanQuery = false, Tags = { "EBPulse" } })
		light(ember, EMBER, 1.5, 20, true)
		-- forge glow inside (the furnace mouth on the back wall)
		local mouth = box("FurnaceMouth", Vector3.new(4, 3, 0.4), CFrame.new(Vector3.new(center.X, 2, z0 + 1.3)), Enum.Material.Neon, Color3.fromRGB(255, 110, 40), { CanCollide = false, CanQuery = false, Tags = { "EBPulse" } })
		light(mouth, EMBER, 2, 22, true)
	end
	-- hall A east of the trench, hall B west of it; the grated trench is the alley between them
	hall(polar(56, 330), 22, 12, { W = true, S = true, N = true })
	hall(polar(62, 296), 12, 20, { E = true, S = true, W = true })
	for _, p in ipairs({ polar(54, 334), polar(58, 322), polar(62, 300) }) do
		box("Anvil", Vector3.new(4, 3, 2.4), CFrame.new(p + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, math.rad(30), 0), Enum.Material.Metal, Color3.fromRGB(60, 60, 66))
	end
	-- metal crates line the alley (cover), one destructible coal crate stack per side
	for _, p in ipairs({ polar(48, 312), polar(74, 318) }) do
		box("Crate", Vector3.new(4, 4, 4), CFrame.new(p + Vector3.new(0, 2, 0)) * CFrame.Angles(0, math.rad(15), 0), Enum.Material.DiamondPlate, Color3.fromRGB(90, 84, 80))
	end
	cover(polar(66, 310), Vector3.new(5, 4.5, 5), Enum.Material.WoodPlanks, Color3.fromRGB(120, 84, 56))
	cover(polar(46, 330), Vector3.new(5, 4.5, 5), Enum.Material.WoodPlanks, Color3.fromRGB(120, 84, 56))
	-- lava trench under walkable grating (the glow is beneath the grate; nothing here hurts)
	local a, b = polar(42, 314), polar(84, 314)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt(mid, b)
	box("LavaGlow", Vector3.new(5, 0.2, len), cf * CFrame.new(0, -0.6, 0), Enum.Material.Neon, Color3.fromRGB(255, 90, 30), { Deco = true, Tags = { "EBPulse" } })
	box("Grate", Vector3.new(6, 0.3, len), cf * CFrame.new(0, 0.12, 0), Enum.Material.DiamondPlate, Color3.fromRGB(70, 66, 64), { Transparency = 0.25 })
	for k = 0, 4 do
		local p = a:Lerp(b, (k + 0.5) / 5) + Vector3.new(0, 1, 0)
		local l = box("GrateLight", Vector3.new(0.2, 0.2, 0.2), CFrame.new(p), Enum.Material.Neon, EMBER, { Deco = true, Transparency = 1 })
		light(l, Color3.fromRGB(255, 110, 50), 0.9, 12, true)
	end
	for _, p in ipairs({ polar(40, 326), polar(40, 302) }) do
		cyl("Brazier", 1.4, 3.6, p, Enum.Material.Metal, Color3.fromRGB(70, 60, 56))
		local bowl = cyl("BrazierBowl", 2, 0.8, p + Vector3.new(0, 3.6, 0), Enum.Material.Metal, Color3.fromRGB(90, 70, 60))
		local f = Instance.new("Fire")
		f.Heat = 6
		f.Size = 4
		f.Color = Color3.fromRGB(255, 140, 60)
		f.SecondaryColor = Color3.fromRGB(255, 60, 20)
		f.Parent = bowl
		light(bowl, EMBER, 1.6, 18, true)
	end
	sign("DistrictSign", Vector3.new(14, 2.4, 0.4), CFrame.lookAt(polar(40, 314, 13), Vector3.new(0, 13, 0)), Enum.NormalId.Front, "EMBER FORGE", EMBER)
end

-- Tidal Cistern (SE: +X, +Z) ----------------------------------------------------------------------------
local function buildCistern()
	local c = polar(63, 45)
	local rimY = 5
	local RIM = 20
	local stone = Color3.fromRGB(110, 120, 132)
	cyl("PoolWater", RIM - 3, 0.5, c + Vector3.new(0, 0.05, 0), Enum.Material.Glass, Color3.fromRGB(60, 150, 200), { Deco = true, Transparency = 0.45, Tags = { "EBBob" } })
	cyl("PoolFloor", RIM - 2, 0.1, c - Vector3.new(0, 0.08, 0), Enum.Material.Slate, Color3.fromRGB(40, 70, 90), { CanCollide = false, CanQuery = false })
	-- raised rim walkway: three-quarter ring, open toward the plaza (the gap faces 225°)
	local startA, span = 250, 310
	local segs = 20
	for k = 0, segs - 1 do
		local a0 = startA + k / segs * span
		local a1 = startA + (k + 1) / segs * span
		local p0, p1 = c + polar(RIM, a0), c + polar(RIM, a1)
		local mid = (p0 + p1) / 2
		local len = (p1 - p0).Magnitude * 1.08
		box("RimWalk", Vector3.new(6, rimY, len), CFrame.lookAt(mid + Vector3.new(0, rimY / 2, 0), p1 + Vector3.new(0, rimY / 2, 0)), Enum.Material.Slate, stone)
		if k % 4 == 0 then
			local post = mid + (mid - c).Unit * 2.4
			cyl("RimLamp", 0.5, 4, post + Vector3.new(0, rimY, 0), Enum.Material.Metal, Color3.fromRGB(80, 90, 100))
			local glow = ball("RimGlow", 0.7, post + Vector3.new(0, rimY + 4.6, 0), Enum.Material.Neon, TIDE, { CanCollide = false, CanQuery = false })
			light(glow, TIDE, 1.1, 16)
		end
	end
	-- ramps up to the rim at both open ends (running along the ring tangent)
	local function rimRamp(angle, dirSign)
		local p = c + polar(RIM, angle)
		local tangent = Vector3.new(-math.sin(math.rad(angle)), 0, math.cos(math.rad(angle))) * dirSign
		ramp("RimRamp", p - tangent * 15, tangent, 15, 6, rimY, Enum.Material.Slate, stone)
	end
	rimRamp(startA, 1)
	rimRamp(startA + span, -1)
	-- bridges across the pool at rim height + arch supports (ground-level cover)
	box("CisternBridge", Vector3.new(6, 1.2, RIM * 2 + 2), CFrame.new(c + Vector3.new(0, rimY - 0.6, 0)), Enum.Material.WoodPlanks, Color3.fromRGB(110, 86, 64))
	box("CisternBridge", Vector3.new(RIM * 2 + 2, 1.2, 6), CFrame.new(c + Vector3.new(0, rimY - 0.6, 6)), Enum.Material.WoodPlanks, Color3.fromRGB(110, 86, 64))
	for _, off in ipairs({ Vector3.new(-11, 0, 6), Vector3.new(11, 0, 6), Vector3.new(0, 0, -11), Vector3.new(0, 0, 15) }) do
		box("Arch", Vector3.new(3, rimY - 1.2, 3), CFrame.new(c + off + Vector3.new(0, (rimY - 1.2) / 2, 0)), Enum.Material.Slate, stone)
	end
	cover(c + Vector3.new(-7, 0, -5), Vector3.new(4, 4, 6), Enum.Material.Slate, Color3.fromRGB(96, 104, 116))
	cover(c + Vector3.new(7, 0, 13), Vector3.new(6, 4, 4), Enum.Material.Slate, Color3.fromRGB(96, 104, 116))
	for _, a in ipairs({ 290, 20, 110 }) do
		local p = c + polar(RIM - 2.5, a)
		box("Waterfall", Vector3.new(4, rimY, 0.3), CFrame.lookAt(p + Vector3.new(0, rimY / 2, 0), c + Vector3.new(0, rimY / 2, 0)), Enum.Material.Glass, Color3.fromRGB(150, 210, 240), { Deco = true, Transparency = 0.5 })
	end
	sign("DistrictSign", Vector3.new(14, 2.4, 0.4), CFrame.lookAt(polar(38, 45, 13), Vector3.new(0, 13, 0)), Enum.NormalId.Front, "TIDAL CISTERN", TIDE)
end

-- Verdant Terraces (SW: -X, +Z) ----------------------------------------------------------------------------
local function buildTerraces()
	local grass = Color3.fromRGB(86, 132, 70)
	local soil = Color3.fromRGB(110, 92, 70)
	local wallC = Color3.fromRGB(150, 140, 120)
	local levels = {
		{ y = 4, r0 = 52, r1 = 66 },
		{ y = 8, r0 = 66, r1 = 80 },
	}
	for _, L in ipairs(levels) do
		local segs = 8
		for k = 0, segs - 1 do
			local a0 = 100 + k / segs * 70
			local a1 = 100 + (k + 1) / segs * 70
			local rm = (L.r0 + L.r1) / 2
			local p0, p1 = polar(rm, a0), polar(rm, a1)
			local mid = (p0 + p1) / 2
			local len = (p1 - p0).Magnitude * 1.06
			box("Terrace", Vector3.new(L.r1 - L.r0, L.y, len), CFrame.lookAt(mid + Vector3.new(0, L.y / 2, 0), p1 + Vector3.new(0, L.y / 2, 0)), Enum.Material.Grass, grass)
			wall("TerraceLip", polar(L.r0 - 0.6, a0), polar(L.r0 - 0.6, a1), L.y + 0.4, 1.2, Enum.Material.Cobblestone, wallC)
		end
	end
	-- ramps (radial) up each level; the 4-stud lips are also jumpable
	ramp("TerraceRamp", polar(40, 116), polar(1, 116), 12, 7, 4, Enum.Material.Ground, soil)
	ramp("TerraceRamp", polar(40, 158), polar(1, 158), 12, 7, 4, Enum.Material.Ground, soil)
	ramp("TerraceRamp", polar(54, 137), polar(1, 137), 12, 7, 4, Enum.Material.Ground, soil)
	-- hedges (cover)
	for _, h in ipairs({ { 45, 124, 136 }, { 45, 142, 152 }, { 59, 106, 120 }, { 59, 150, 164 } }) do
		local y = h[1] > 52 and 4 or 0
		wall("Hedge", polar(h[1], h[2], y), polar(h[1], h[3], y), 3, 2, Enum.Material.LeafyGrass, Color3.fromRGB(60, 110, 54))
	end
	-- the great tree on the top terrace
	local tp = polar(73, 136, 8)
	cyl("TreeTrunk", 2.6, 18, tp, Enum.Material.Wood, Color3.fromRGB(96, 70, 52))
	for i, off in ipairs({ Vector3.new(0, 22, 0), Vector3.new(5, 19, 3), Vector3.new(-4, 20, -4), Vector3.new(2, 25, -3) }) do
		ball("Canopy", 7 - i * 0.6, tp + off, Enum.Material.LeafyGrass, Color3.fromRGB(80, 150, 70), { Deco = true, Tags = { "EBSway" } })
	end
	for i = 1, 5 do
		local lp = tp + Vector3.new(math.cos(i * 1.3) * 6, 15 + (i % 2) * 3, math.sin(i * 1.3) * 6)
		local lan = ball("Lantern", 0.6, lp, Enum.Material.Neon, VERDANT, { Deco = true, Tags = { "EBBob" } })
		light(lan, VERDANT, 0.8, 12)
	end
	cover(polar(36, 128), Vector3.new(6, 3.5, 3), Enum.Material.Brick, Color3.fromRGB(130, 96, 80))
	cover(polar(36, 150), Vector3.new(3, 3.5, 6), Enum.Material.Brick, Color3.fromRGB(130, 96, 80))
	sign("DistrictSign", Vector3.new(16, 2.4, 0.4), CFrame.lookAt(polar(50, 135, 14), Vector3.new(0, 14, 0)), Enum.NormalId.Front, "VERDANT TERRACES", VERDANT)
end

-- Storm Spire (NW: -X, -Z) + Gale Bridge -------------------------------------------------------------------------
local function buildSpire()
	local c = polar(64, 225)
	local h = 10
	local stone = Color3.fromRGB(84, 80, 104)
	cyl("SpireBase", 14, h, c, Enum.Material.Basalt, stone)
	cyl("SpireTrim", 14.4, 0.5, c + Vector3.new(0, h - 0.5, 0), Enum.Material.Neon, STORM, { CanCollide = false, CanQuery = false })
	-- main ramp on the west side, rising northward from the west avenue
	-- its high end meets the platform edge flush (edge at dz = sqrt(14^2 - 11^2) from the centre)
	ramp("SpireRamp", Vector3.new(c.X - 11, 0, c.Z + 8.6 + 26), Vector3.new(0, 0, -1), 26, 7, h, Enum.Material.Basalt, stone)
	-- jump route: two stepping blocks on the north-east side (4 and 7.5 studs)
	box("SpireStep", Vector3.new(6, 4, 6), CFrame.new(c + polar(21, 300) + Vector3.new(0, 2, 0)), Enum.Material.Basalt, stone)
	box("SpireStep", Vector3.new(6, 7.5, 6), CFrame.new(c + polar(16.5, 310) + Vector3.new(0, 3.75, 0)), Enum.Material.Basalt, stone)
	-- parapet sections leave the ramp top (~170°), the jump route (~300°) and the bridge (0°) open
	for _, seg in ipairs({ { 30, 70 }, { 82, 118 }, { 200, 255 } }) do
		wall("SpireParapet", c + polar(13, seg[1], h), c + polar(13, seg[2], h), 2.6, 1, Enum.Material.Basalt, Color3.fromRGB(70, 66, 90))
	end
	for _, a in ipairs({ 200, 290 }) do
		local p = c + polar(7, a, h)
		cyl("TeslaCoil", 1.2, 8, p, Enum.Material.Metal, Color3.fromRGB(110, 110, 130))
		cyl("TeslaRing", 2, 0.6, p + Vector3.new(0, 5, 0), Enum.Material.Metal, Color3.fromRGB(150, 120, 90), { Deco = true })
		local orb = ball("TeslaOrb", 1.5, p + Vector3.new(0, 9, 0), Enum.Material.Neon, STORM, { CanCollide = false, CanQuery = false, Tags = { "EBArc" } })
		light(orb, STORM, 1.8, 22, true)
	end
	for _, a in ipairs({ 110, 160, 250 }) do
		local p = c + polar(12, a, h)
		cyl("BannerPole", 0.3, 9, p, Enum.Material.Metal, Color3.fromRGB(80, 80, 90))
		box("Banner", Vector3.new(0.15, 5, 2.4), CFrame.new(p + Vector3.new(0, 6, 1.3)), Enum.Material.Fabric, STORM, { Deco = true, Tags = { "EBSway" } })
	end
	-- Gale Bridge: east off the spire top, over the north avenue, to a landing tower; a ramp descends east
	local from = Vector3.new(c.X + 13, 0, c.Z)
	local landing = Vector3.new(-4, 0, c.Z)
	local mid = (from + landing) / 2
	local len = (landing - from).Magnitude
	box("GaleBridge", Vector3.new(6, 1, len + 2), CFrame.lookAt(mid + Vector3.new(0, h - 0.5, 0), landing + Vector3.new(0, h - 0.5, 0)), Enum.Material.Metal, Color3.fromRGB(96, 96, 120))
	for _, side in ipairs({ -1, 1 }) do
		wall("BridgeRail", from + Vector3.new(0, h, side * 3.2), landing + Vector3.new(0, h, side * 3.2), 1.6, 0.4, Enum.Material.Metal, Color3.fromRGB(140, 130, 160))
	end
	box("GaleLanding", Vector3.new(8, h, 8), CFrame.new(landing + Vector3.new(0, h / 2, 0)), Enum.Material.Basalt, stone)
	neonStrip(landing + Vector3.new(-4, 0, -4), landing + Vector3.new(4, 0, -4), STORM, h, 0.4)
	ramp("GaleRamp", landing + Vector3.new(26, 0, 0), Vector3.new(-1, 0, 0), 22, 6, h, Enum.Material.Basalt, stone)
	sign("DistrictSign", Vector3.new(14, 2.4, 0.4), CFrame.lookAt(c + polar(15, 45, 16), Vector3.new(0, 16, 0)), Enum.NormalId.Front, "STORM SPIRE", STORM)
end

-- Avenues: colonnades and mid-avenue cover break the four long sightlines ---------------------------------------
local function buildAvenues()
	local pillarC = Color3.fromRGB(170, 160, 170)
	for _, ang in ipairs({ 0, 90, 180, 270 }) do
		local d = polar(1, ang)
		local side = Vector3.new(-d.Z, 0, d.X)
		for _, r in ipairs({ 54, 72 }) do
			for _, sd in ipairs({ -1, 1 }) do
				local p = d * r + side * sd * 10
				if not (ang == 270 and r == 54) then
					cyl("Colonnade", 1.8, 12, p, Enum.Material.Marble, pillarC)
					cyl("ColonnadeCap", 2.4, 1, p + Vector3.new(0, 12, 0), Enum.Material.Marble, TRIM, { Deco = true })
				end
			end
			if not (ang == 270 and r == 54) then
				local a, b = d * r - side * 10 + Vector3.new(0, 13, 0), d * r + side * 10 + Vector3.new(0, 13, 0)
				wall("Lintel", a, b, 1.6, 2, Enum.Material.Marble, pillarC, { CanQuery = false })
			end
		end
		-- low wall mid-avenue with open ends (crouch-height cover)
		if ang ~= 90 then
			local p = d * 63
			wall("AvenueWall", p - side * 4, p + side * 4, 3.4, 1.6, Enum.Material.Limestone, Color3.fromRGB(160, 150, 144))
		end
		-- obelisk landmark at the outer end (not on the south gate)
		if ang ~= 90 then
			local o = d * 86
			box("Obelisk", Vector3.new(3, 16, 3), CFrame.new(o + Vector3.new(0, 8, 0)) * CFrame.Angles(0, math.rad(ang + 45), 0), Enum.Material.Granite, Color3.fromRGB(86, 80, 96))
			local gem = ball("ObeliskGem", 1.1, o + Vector3.new(0, 17.2, 0), Enum.Material.Neon, ({ [0] = EMBER, [180] = VERDANT, [270] = STORM })[ang] or TIDE, { CanCollide = false, CanQuery = false, Tags = { "EBPulse" } })
			light(gem, gem.Color, 1.2, 16)
		end
	end
end

-- Spawn alcoves ---------------------------------------------------------------------------------------------
local function buildAlcoves()
	table.clear(Arena.spawns)
	for i = 0, 7 do
		local ang = i * 45 + 22.5
		local out = polar(1, ang)
		local side = Vector3.new(-out.Z, 0, out.X)
		local back = polar(R_ISLAND - 4, ang)
		local front = polar(R_ISLAND - 14, ang)
		local h = 10
		local team = (ang > 0 and ang < 180) and "Sun" or "Moon"
		local accent = team == "Sun" and Color3.fromRGB(255, 180, 90) or Color3.fromRGB(120, 170, 255)
		wall("AlcoveWall", back + side * 6, front + side * 6, h, 1.6, Enum.Material.Limestone, Color3.fromRGB(170, 160, 152))
		wall("AlcoveWall", back - side * 6, front - side * 6, h, 1.6, Enum.Material.Limestone, Color3.fromRGB(170, 160, 152))
		wall("AlcoveBack", back - side * 6.8, back + side * 6.8, h, 1.6, Enum.Material.Limestone, Color3.fromRGB(150, 140, 134))
		local roofC = (back + front) / 2 + Vector3.new(0, h + 0.5, 0)
		box("AlcoveRoof", Vector3.new(14.4, 1, 11), CFrame.lookAt(roofC, roofC + out), Enum.Material.Slate, Color3.fromRGB(80, 74, 86))
		neonStrip(front - side * 6, front + side * 6, accent, FLOOR_Y, 0.5)
		-- protective low wall in front with exits on both sides
		local g0 = front - out * 3
		wall("AlcoveGuard", g0 - side * 3, g0 + side * 3, 3, 1.4, Enum.Material.Limestone, Color3.fromRGB(160, 150, 144))
		local glow = ball("AlcoveGlow", 0.8, back - out * 1.5 + Vector3.new(0, h - 2, 0), Enum.Material.Neon, accent, { CanCollide = false, CanQuery = false })
		light(glow, accent, 1.4, 18)
		local sp = (back + front) / 2 - out * 1
		table.insert(Arena.spawns, { Position = sp, cf = CFrame.lookAt(sp, Vector3.new(0, FLOOR_Y, 0)), team = team })
	end
end

-- Training Annex ---------------------------------------------------------------------------------------------
local function buildAnnex()
	local z0, z1 = 112, 172
	box("AnnexBridge", Vector3.new(14, 2, z0 - R_ISLAND + 8), CFrame.new(0, FLOOR_Y - 1, (R_ISLAND - 4 + z0) / 2), Enum.Material.Slate, Color3.fromRGB(100, 96, 110))
	for _, x in ipairs({ -7.4, 7.4 }) do
		box("AnnexBridgeRail", Vector3.new(0.8, 3, z0 - R_ISLAND + 2), CFrame.new(x, FLOOR_Y + 1.5, (R_ISLAND + z0) / 2), Enum.Material.Limestone, Color3.fromRGB(176, 166, 160))
	end
	box("GateArch", Vector3.new(18, 2, 2), CFrame.new(0, FLOOR_Y + 11, R_ISLAND - 1), Enum.Material.Limestone, TRIM)
	box("GatePier", Vector3.new(2, 11, 2), CFrame.new(-8, FLOOR_Y + 5.5, R_ISLAND - 1), Enum.Material.Limestone, Color3.fromRGB(176, 166, 160))
	box("GatePier", Vector3.new(2, 11, 2), CFrame.new(8, FLOOR_Y + 5.5, R_ISLAND - 1), Enum.Material.Limestone, Color3.fromRGB(176, 166, 160))
	box("AnnexFloor", Vector3.new(76, 4, z1 - z0), CFrame.new(0, FLOOR_Y - 2, (z0 + z1) / 2), Enum.Material.Slate, Color3.fromRGB(74, 72, 86))
	box("AnnexUnder", Vector3.new(60, 14, z1 - z0 - 8), CFrame.new(0, FLOOR_Y - 11, (z0 + z1) / 2), Enum.Material.Rock, Color3.fromRGB(66, 58, 62), { Deco = true })
	local corners = { Vector3.new(-38, 0, z0), Vector3.new(-38, 0, z1), Vector3.new(38, 0, z1), Vector3.new(38, 0, z0) }
	for k = 1, 3 do
		wall("AnnexRail", corners[k], corners[k + 1], 3.4, 1.2, Enum.Material.Limestone, Color3.fromRGB(176, 166, 160))
		wall("Barrier", corners[k] - Vector3.new(0, 2, 0), corners[k + 1] - Vector3.new(0, 2, 0), 60, 2, Enum.Material.ForceField, Color3.new(1, 1, 1), { Transparency = 1, CanQuery = false, CastShadow = false })
	end
	wall("AnnexRail", corners[4], Vector3.new(8, 0, z0), 3.4, 1.2, Enum.Material.Limestone, Color3.fromRGB(176, 166, 160))
	wall("AnnexRail", Vector3.new(-8, 0, z0), corners[1], 3.4, 1.2, Enum.Material.Limestone, Color3.fromRGB(176, 166, 160))
	-- bridge side barriers
	for _, x in ipairs({ -8.5, 8.5 }) do
		wall("Barrier", Vector3.new(x, -2, R_ISLAND - 2), Vector3.new(x, -2, z0), 60, 1, Enum.Material.ForceField, Color3.new(1, 1, 1), { Transparency = 1, CanQuery = false, CastShadow = false })
	end
	-- firing line + distance markers every 5 m (the compendium speaks in metres)
	local fireZ = z0 + 6
	neonStrip(Vector3.new(-30, 0, fireZ), Vector3.new(30, 0, fireZ), Color3.fromRGB(255, 220, 120), FLOOR_Y, 0.5)
	for m = 5, 15, 5 do
		local z = fireZ + m * M
		neonStrip(Vector3.new(-30, 0, z), Vector3.new(16, 0, z), Color3.fromRGB(150, 160, 190), FLOOR_Y, 0.25)
		sign("RangeMark", Vector3.new(3, 1.6, 0.3), CFrame.new(-33, FLOOR_Y + 1.6, z), Enum.NormalId.Back, m .. " m", Color3.fromRGB(230, 230, 240))
	end
	table.clear(Arena.dummySpots)
	for i, m in ipairs({ 5, 8, 11, 15 }) do
		table.insert(Arena.dummySpots, Vector3.new(-24 + i * 9, FLOOR_Y, fireZ + m * M))
	end
	box("RangeCover", Vector3.new(8, 4.5, 2), CFrame.new(-9, FLOOR_Y + 2.25, fireZ + 20), Enum.Material.Limestone, Color3.fromRGB(160, 150, 144))
	sign("AnnexSign", Vector3.new(30, 4, 0.5), CFrame.new(0, FLOOR_Y + 14, z1 - 1), Enum.NormalId.Front, "TRAINING ANNEX — press P for match & practice tools", Color3.fromRGB(255, 220, 170))
	for _, x in ipairs({ -36, 36 }) do
		cyl("AnnexLampPost", 0.5, 7, Vector3.new(x, FLOOR_Y, z0 + 30), Enum.Material.Metal, Color3.fromRGB(80, 80, 90))
		local g = ball("AnnexLamp", 0.9, Vector3.new(x, FLOOR_Y + 7.6, z0 + 30), Enum.Material.Neon, Color3.fromRGB(255, 210, 160), { CanCollide = false, CanQuery = false })
		light(g, Color3.fromRGB(255, 200, 150), 1.4, 26)
	end
	Arena.annex = {
		spawn = CFrame.lookAt(Vector3.new(0, FLOOR_Y, fireZ - 2), Vector3.new(0, FLOOR_Y, z1)),
		dummySpots = Arena.dummySpots,
		dummyFacing = Vector3.new(0, 0, -1),
	}
	-- clear lane on the east side used by tooling (smoke tests)
	Arena.testLane = { origin = Vector3.new(30, FLOOR_Y + 3.2, fireZ), dir = Vector3.new(0, 0, 1) }
end

-- Sky & lighting ------------------------------------------------------------------------------------------------
local function buildSky()
	local dir = Vector3.new(-0.55, 0.22, -0.8).Unit
	local starPos = dir * 900
	ball("ProximaStar", 120, starPos, Enum.Material.Neon, Color3.fromRGB(255, 92, 50), { Deco = true })
	ball("ProximaCorona", 165, starPos, Enum.Material.ForceField, Color3.fromRGB(255, 120, 80), { Deco = true, Transparency = 0.3 })
	ball("CompanionMoon", 26, Vector3.new(0.7, 0.45, -0.55).Unit * 820, Enum.Material.SmoothPlastic, Color3.fromRGB(150, 160, 200), { Deco = true })
	local rng = Random.new(7)
	local accents = { EMBER, TIDE, VERDANT, STORM }
	for i = 1, 14 do
		local a = i / 14 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local r = rng:NextNumber(260, 420)
		local p = Vector3.new(math.cos(a) * r, rng:NextNumber(-80, 60), math.sin(a) * r)
		local s = rng:NextNumber(10, 28)
		local isle = Instance.new("Model")
		isle.Name = "FarIsle"
		cyl("Rock", s, s * 0.5, p, Enum.Material.Rock, Color3.fromRGB(80, 66, 72), { Deco = true, Parent = isle })
		local top = cyl("Top", s * 0.95, 1, p + Vector3.new(0, s * 0.5, 0), Enum.Material.Grass, Color3.fromRGB(70, 96, 70), { Deco = true, Parent = isle })
		if i % 3 == 0 then
			ball("Crystal", s * 0.25, p + Vector3.new(0, s * 0.8, 0), Enum.Material.Neon, accents[i % 4 + 1], { Deco = true, Parent = isle })
		end
		isle.PrimaryPart = top
		isle.Parent = folder
		CollectionService:AddTag(isle, "EBDrift")
	end
	Lighting.ClockTime = 17.4
	Lighting.GeographicLatitude = 18
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(46, 36, 60)
	Lighting.OutdoorAmbient = Color3.fromRGB(118, 92, 116)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 168, 120)
	Lighting.ColorShift_Bottom = Color3.fromRGB(70, 50, 110)
	Lighting.EnvironmentDiffuseScale = 0.55
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.ShadowSoftness = 0.35
	Lighting.GlobalShadows = true
	Lighting.FogEnd = 100000
	local function effect(class, name, props)
		local e = Lighting:FindFirstChild(name)
		if not e then
			e = Instance.new(class)
			e.Name = name
			e.Parent = Lighting
		end
		for k, v in pairs(props) do
			e[k] = v
		end
		return e
	end
	for _, old in ipairs(Lighting:GetChildren()) do
		if (old:IsA("Atmosphere") or old:IsA("PostEffect")) and not old.Name:match("^EB") then
			old:Destroy()
		end
	end
	effect("Atmosphere", "EBAtmosphere", { Density = 0.33, Offset = 0.18, Color = Color3.fromRGB(200, 128, 120), Decay = Color3.fromRGB(96, 62, 118), Glare = 0.45, Haze = 1.7 })
	effect("BloomEffect", "EBBloom", { Intensity = 0.65, Size = 26, Threshold = 1.35 })
	effect("ColorCorrectionEffect", "EBGrade", { Contrast = 0.08, Saturation = 0.06, Brightness = 0.01, TintColor = Color3.fromRGB(255, 242, 236) })
	effect("SunRaysEffect", "EBSunRays", { Intensity = 0.05, Spread = 0.6 })
	local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
	sky.CelestialBodiesShown = false
	sky.StarCount = 3000
	sky.Parent = Lighting
end

function Arena.build()
	folder = S.folders.Arena
	for _, c in ipairs(folder:GetChildren()) do
		c:Destroy()
	end
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	workspace.FallenPartsDestroyHeight = -2000
	workspace.Gravity = 196.2
	S.arenaBounds = { center = Vector3.new(0, FLOOR_Y, 30), half = 140, floorY = FLOOR_Y }
	buildIsland()
	-- district ground tints (flush, non-colliding): each quarter has its own floor material and colour
	for _, g in ipairs({
		{ 315, Enum.Material.Cobblestone, Color3.fromRGB(96, 70, 62) },
		{ 45, Enum.Material.Slate, Color3.fromRGB(78, 98, 116) },
		{ 135, Enum.Material.Ground, Color3.fromRGB(96, 92, 70) },
		{ 225, Enum.Material.Basalt, Color3.fromRGB(78, 70, 104) },
	}) do
		cyl("DistrictFloor", 30, 0.08, polar(63, g[1], FLOOR_Y - 0.03), g[2], g[3], { CanCollide = false, CanQuery = false, CastShadow = false })
	end
	buildPlaza()
	buildForge()
	buildCistern()
	buildTerraces()
	buildSpire()
	buildAvenues()
	buildAlcoves()
	buildAnnex()
	buildSky()
	workspace:SetAttribute("ArenaName", "Proxima Observatory")
end

function Arena.randomSpawn()
	local best, bestScore
	for _, p in ipairs(Arena.spawns) do
		local score = 0
		for _, f in pairs(S.fighters) do
			if S.alive(f) and not f.isSummon then
				score += math.min(60, (f.root.Position - p.Position).Magnitude)
			end
		end
		score += math.random() * 30
		if not bestScore or score > bestScore then
			best, bestScore = p, score
		end
	end
	return (best and best.Position or Vector3.new(0, 0, 0)) + Vector3.new(0, 4, 0)
end

return Arena
