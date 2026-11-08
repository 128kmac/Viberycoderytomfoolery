-- Client VFX core. Renders the server's cues (see server/Core/FX.luau) with each power's style:
--   * pooled parts + one update loop for every effect (no per-effect tweens / threads)
--   * primitives: balls, segmented rings, camera-facing ribbons, debris, particle bursts, flashes, lights
--   * friend / foe relation per viewer (telegraph shapes differ, not only colours)
--   * client-simulated projectiles with server corrections
--   * dressing of persistent server visuals (tag "EBVis") and impact layering by result category
-- Quality, reduced-flash and reduced-motion settings are honoured everywhere.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Styles = require(Shared:WaitForChild("Styles"))
local Poses = require(Shared:WaitForChild("Poses"))

local V = {}
V.Styles = Styles
V.Poses = Poses

local ctx, Settings, Audio
local player = Players.LocalPlayer
local rng = Random.new()
V.rng = rng

local folder = Instance.new("Folder")
folder.Name = "EBClientFX"
V.folder = folder

local FAR = CFrame.new(0, -10000, 0)
local TEX = {
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	spark = "rbxasset://textures/particles/fire_sparks_main.dds",
}
V.TEX = TEX

-- Fighters (for relations, hands, attachments) ------------------------------------------------------
local fighters = {} -- id -> model
V.fighters = fighters

local function track(model)
	local id = model:GetAttribute("FighterId")
	if id then
		fighters[id] = model
	end
end

function V.myModel()
	return player.Character
end

function V.myId()
	local ch = player.Character
	return ch and ch:GetAttribute("FighterId") or -1
end

function V.myTeam()
	local ch = player.Character
	local t = ch and ch:GetAttribute("Team") or ""
	return t ~= "" and t or nil
end

-- "self" | "ally" | "enemy" | "neutral" for an owner fighter id, relative to the local player
function V.relation(ownerId)
	if not ownerId or ownerId == 0 then
		return "neutral"
	end
	local me = V.myId()
	if ownerId == me then
		return "self"
	end
	local m = fighters[ownerId]
	if m and m.Parent then
		local oid = m:GetAttribute("OwnerId")
		if oid and oid ~= 0 then
			if oid == me then
				return "self"
			end
			m = fighters[oid] or m
		end
		local team = m:GetAttribute("Team")
		local mine = V.myTeam()
		if mine and team == mine then
			return "ally"
		end
	end
	return "enemy"
end

function V.modelOf(id)
	local m = id and fighters[id]
	if m and m.Parent then
		return m
	end
	return nil
end

-- world position of a model's hand (falls back to the shared emission point)
function V.handPos(model, hand)
	if not model then
		return nil
	end
	if hand == "both" then
		local l, r = model:FindFirstChild("LeftHand"), model:FindFirstChild("RightHand")
		if l and r then
			local root = model:FindFirstChild("HumanoidRootPart")
			local mid = (l.Position + r.Position) / 2
			if root then
				mid += root.CFrame.LookVector * 0.6
			end
			return mid
		end
	end
	local name = hand == "left" and "LeftHand" or "RightHand"
	local h = model:FindFirstChild(name)
	if h then
		return h.Position
	end
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if root then
		return Poses.handWorld(root.Position, root.CFrame.LookVector, hand or "right")
	end
	return nil
end

-- Pools -------------------------------------------------------------------------------------------------
local free = {}
local liveParts = 0
function V.part(shape, material, color, size, cf, transparency)
	local p = table.remove(free)
	if not p then
		p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Name = "fx"
		p.Parent = folder
	end
	p.Shape = shape or Enum.PartType.Ball
	p.Material = material or Enum.Material.Neon
	p.Color = color or Color3.new(1, 1, 1)
	p.Size = size or Vector3.one
	p.CFrame = cf or CFrame.new()
	p.Transparency = transparency or 0
	p.Reflectance = 0
	liveParts += 1
	return p
end

function V.freePart(p)
	if not p then
		return
	end
	for _, c in ipairs(p:GetChildren()) do
		c:Destroy()
	end
	p.CFrame = FAR
	p.Transparency = 1
	liveParts -= 1
	if #free < 500 then
		table.insert(free, p)
	else
		p:Destroy()
	end
end

-- Effect loop ------------------------------------------------------------------------------------------
local effects = {}
local byId = {}
V.byId = byId

function V.count()
	return #effects
end

-- e = { life, update(e, a, dt, t), finish(e), parts = {}, prio (0 ambient .. 3 critical), id }
function V.effect(e)
	e.parts = e.parts or {}
	e.t0 = os.clock()
	e.life = math.max(0.03, e.life or 0.5)
	table.insert(effects, e)
	if e.id then
		byId[e.id] = e
	end
	return e
end

-- budget gate: low-priority effects are skipped when the scene is saturated
function V.allow(prio)
	local n = #effects
	local max = Settings.maxEffects()
	if prio and prio >= 2 then
		return n < max * 1.6
	end
	return n < max
end

local function endEffect(e)
	if e.finish then
		local ok, err = pcall(e.finish, e)
		if not ok then
			warn("[EB fx] finish: " .. tostring(err))
		end
	end
	for _, p in ipairs(e.parts) do
		V.freePart(p)
	end
	e.parts = {}
	if e.id and byId[e.id] == e then
		byId[e.id] = nil
	end
end

local function stepEffects(dt)
	local now = os.clock()
	local i = 1
	while i <= #effects do
		local e = effects[i]
		local t = now - e.t0
		local a = t / e.life
		if a >= 1 or e.dead then
			effects[i] = effects[#effects]
			effects[#effects] = nil
			endEffect(e)
		else
			if e.update then
				local ok, err = pcall(e.update, e, a, dt, t)
				if not ok then
					warn("[EB fx] update: " .. tostring(err))
					e.dead = true
				end
			end
			i += 1
		end
	end
end

-- easing
local function outQuad(a)
	return 1 - (1 - a) * (1 - a)
end
local function outCubic(a)
	return 1 - (1 - a) ^ 3
end
local function inQuad(a)
	return a * a
end
V.outQuad, V.outCubic, V.inQuad = outQuad, outCubic, inQuad

-- Particles -----------------------------------------------------------------------------------------
local function seq(a, b)
	return NumberSequence.new(a, b)
end
local function seq3(a, b, c)
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(0.35, b), NumberSequenceKeypoint.new(1, c) })
end
local function cseq(a, b, c)
	if c then
		return ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(0.45, b), ColorSequenceKeypoint.new(1, c) })
	end
	return ColorSequence.new(a, b or a)
end
V.seq, V.seq3, V.cseq = seq, seq3, cseq

-- configure an emitter for a particle kind in a style
local function configure(pe, kind, style, scale)
	scale = scale or 1
	local glow, col, deep = style.glow, style.color, style.deep
	pe.Rate = 0
	pe.LightInfluence = 0
	pe.Shape = Enum.ParticleEmitterShape.Sphere
	pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rotation = NumberRange.new(0, 360)
	if kind == "flame" then
		pe.Texture = TEX.fire
		pe.Lifetime = NumberRange.new(0.3, 0.65)
		pe.Size = seq3(1.1 * scale, 1.4 * scale, 0.1)
		pe.Speed = NumberRange.new(3 * scale, 8 * scale)
		pe.Acceleration = Vector3.new(0, 10, 0)
		pe.Drag = 3
		pe.LightEmission = 1
		pe.RotSpeed = NumberRange.new(-90, 90)
		pe.Color = cseq(Color3.new(1, 1, 0.8), glow, deep)
		pe.Transparency = seq3(0.2, 0.3, 1)
	elseif kind == "frost" then
		pe.Texture = TEX.sparkle
		pe.Lifetime = NumberRange.new(0.5, 1.1)
		pe.Size = seq(0.55 * scale, 0)
		pe.Speed = NumberRange.new(3 * scale, 9 * scale)
		pe.Acceleration = Vector3.new(0, -5, 0)
		pe.Drag = 2
		pe.LightEmission = 0.6
		pe.RotSpeed = NumberRange.new(-200, 200)
		pe.Color = cseq(Color3.new(1, 1, 1), style.pale)
		pe.Transparency = seq(0, 1)
	elseif kind == "spark" then
		pe.Texture = TEX.spark
		pe.Lifetime = NumberRange.new(0.12, 0.32)
		pe.Size = seq(0.35 * scale, 0)
		pe.Speed = NumberRange.new(18 * scale, 36 * scale)
		pe.Acceleration = Vector3.new(0, -30, 0)
		pe.Drag = 1
		pe.LightEmission = 1
		pe.Orientation = Enum.ParticleOrientation.VelocityParallel
		pe.Color = cseq(Color3.new(1, 1, 1), glow)
		pe.Transparency = seq(0, 0.6)
	elseif kind == "drip" then
		pe.Texture = TEX.sparkle
		pe.Lifetime = NumberRange.new(0.4, 0.85)
		pe.Size = seq(0.5 * scale, 0.15)
		pe.Speed = NumberRange.new(7 * scale, 16 * scale)
		pe.Acceleration = Vector3.new(0, -55, 0)
		pe.LightEmission = 0.25
		pe.Color = cseq(style.pale, col)
		pe.Transparency = seq(0.1, 0.8)
	elseif kind == "streak" then
		pe.Texture = TEX.sparkle
		pe.Lifetime = NumberRange.new(0.2, 0.45)
		pe.Size = seq(0.4 * scale, 0)
		pe.Speed = NumberRange.new(16 * scale, 30 * scale)
		pe.Drag = 4
		pe.LightEmission = 0.4
		pe.Orientation = Enum.ParticleOrientation.VelocityParallel
		pe.Squash = seq(-1.5, -1.5)
		pe.Color = cseq(Color3.new(1, 1, 1), style.pale)
		pe.Transparency = seq(0.2, 1)
	elseif kind == "dust" then
		pe.Texture = TEX.smoke
		pe.Lifetime = NumberRange.new(0.8, 1.6)
		pe.Size = seq(1.6 * scale, 4.5 * scale)
		pe.Speed = NumberRange.new(3 * scale, 8 * scale)
		pe.Acceleration = Vector3.new(0, 1.5, 0)
		pe.Drag = 4
		pe.LightEmission = 0
		pe.RotSpeed = NumberRange.new(-40, 40)
		pe.Color = cseq(style.color:Lerp(Color3.fromRGB(150, 140, 125), 0.5), style.deep)
		pe.Transparency = seq3(0.35, 0.55, 1)
	elseif kind == "mote" then
		pe.Texture = TEX.sparkle
		pe.Lifetime = NumberRange.new(0.45, 0.85)
		pe.Size = seq(0.45 * scale, 0)
		pe.Speed = NumberRange.new(7 * scale, 12 * scale)
		pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		pe.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		pe.LightEmission = 1
		pe.Color = cseq(glow, style.pale)
		pe.Transparency = seq(0, 1)
	elseif kind == "glint" then
		pe.Texture = TEX.sparkle
		pe.Lifetime = NumberRange.new(0.4, 0.9)
		pe.Size = seq3(0.2, 0.8 * scale, 0)
		pe.Speed = NumberRange.new(2 * scale, 7 * scale)
		pe.Drag = 2
		pe.LightEmission = 1
		pe.RotSpeed = NumberRange.new(-120, 120)
		pe.Color = cseq(Color3.new(1, 1, 1), glow)
		pe.Transparency = seq3(0.5, 0, 1)
	elseif kind == "leaf" then
		pe.Texture = TEX.sparkle
		pe.Lifetime = NumberRange.new(0.7, 1.3)
		pe.Size = seq(0.6 * scale, 0.2)
		pe.Speed = NumberRange.new(5 * scale, 11 * scale)
		pe.Acceleration = Vector3.new(0, -8, 0)
		pe.Drag = 3
		pe.LightEmission = 0.1
		pe.RotSpeed = NumberRange.new(-300, 300)
		pe.Color = cseq(style.glow, style.deep)
		pe.Transparency = seq(0, 1)
	else -- wisp
		pe.Texture = TEX.smoke
		pe.Lifetime = NumberRange.new(0.6, 1.2)
		pe.Size = seq(0.8 * scale, 2.4 * scale)
		pe.Speed = NumberRange.new(1 * scale, 4 * scale)
		pe.Acceleration = Vector3.new(0, 3, 0)
		pe.Drag = 2
		pe.LightEmission = 0.7
		pe.RotSpeed = NumberRange.new(-60, 60)
		pe.Color = cseq(glow, col)
		pe.Transparency = seq3(0.4, 0.5, 1)
	end
	return pe
end
V.configure = configure

-- one-shot particle burst at a point (or around a part)
function V.burstParticles(pos, kind, style, count, scale, prio)
	if not V.allow(prio or 1) then
		return
	end
	local n = math.max(1, math.floor((count or 12) * Settings.density() + 0.5))
	local holder = V.part(Enum.PartType.Ball, Enum.Material.SmoothPlastic, Color3.new(), Vector3.one * math.max(0.5, (scale or 1) * 0.8), CFrame.new(pos), 1)
	local pe = Instance.new("ParticleEmitter")
	configure(pe, kind, style, scale)
	pe.Parent = holder
	pe:Emit(n)
	V.effect({ life = pe.Lifetime.Max + 0.1, parts = { holder }, prio = 0 })
end

-- continuous emitter on a part (destroyed with the part)
function V.emitter(parent, kind, style, rate, scale)
	local pe = Instance.new("ParticleEmitter")
	configure(pe, kind, style, scale)
	pe.Rate = (rate or 10) * Settings.density()
	pe.Parent = parent
	return pe
end

function V.light(parent, color, brightness, range)
	if not Settings.lightsOn() then
		return nil
	end
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = (brightness or 2) * Settings.flash()
	l.Range = range or 12
	l.Shadows = false
	l.Parent = parent
	return l
end

-- Primitives ----------------------------------------------------------------------------------------------
-- growing / fading ball
function V.ball(pos, r0, r1, color, life, opts)
	opts = opts or {}
	if not V.allow(opts.prio or 1) then
		return nil
	end
	local p = V.part(Enum.PartType.Ball, opts.material or Enum.Material.Neon, color, Vector3.one * r0 * 2, CFrame.new(pos), opts.tr0 or 0.15)
	local tr0, tr1 = opts.tr0 or 0.15, opts.tr1 or 1
	local ease = opts.ease or outQuad
	local l = opts.light and V.light(p, color, opts.light, r1 * 3)
	local lb = l and l.Brightness
	return V.effect({
		life = life,
		parts = { p },
		prio = opts.prio,
		id = opts.id,
		update = function(e, a)
			local k = ease(a)
			local r = r0 + (r1 - r0) * k
			p.Size = Vector3.one * math.max(0.05, r * 2)
			if opts.follow then
				p.CFrame = CFrame.new(opts.follow())
			end
			p.Transparency = tr0 + (tr1 - tr0) * (opts.fadeEase or k)
			if l then
				l.Brightness = lb * (1 - a)
			end
		end,
	})
end

-- segmented flat ring (exact radius), optionally spiked (hostile) or dashed (friendly)
function V.ring(pos, r0, r1, color, life, opts)
	opts = opts or {}
	if not V.allow(opts.prio or 1) then
		return nil
	end
	local segs = opts.segments or math.clamp(math.floor(math.max(r0, r1) * 1.1), 12, 40)
	local width = opts.width or 0.35
	local parts = {}
	local segIndex = {}
	local dashed = opts.dashed
	local rot = opts.rot or CFrame.new()
	for i = 1, segs do
		if not dashed or i % 2 == 1 then
			local p = V.part(Enum.PartType.Block, opts.material or Enum.Material.Neon, color, Vector3.one, FAR, opts.tr0 or 0.1)
			segIndex[p] = i
			table.insert(parts, p)
		end
	end
	local spikes = {}
	if opts.spikes then
		local n = math.clamp(math.floor(math.max(r0, r1) * 0.6), 6, 18)
		for i = 1, n do
			local p = V.part(Enum.PartType.Wedge, Enum.Material.Neon, color, Vector3.one, FAR, opts.tr0 or 0.1)
			spikes[i] = p
			table.insert(parts, p)
		end
	end
	local tr0, tr1 = opts.tr0 or 0.1, opts.tr1 or 1
	local y = opts.y or 0.15
	local center = pos
	local function layout(r, tr)
		pos = center
		local span = opts.arc and math.abs(opts.arc[2] - opts.arc[1]) / 360 or 1
		local segLen = 2 * math.pi * r * span / segs * (dashed and 0.6 or 1.06)
		for _, p in ipairs(parts) do
			local i = segIndex[p]
			if i then
				local ang
				if opts.arc then
					ang = math.rad(opts.arc[1] + (opts.arc[2] - opts.arc[1]) * (i - 0.5) / segs)
				else
					ang = (i - 0.5) / segs * math.pi * 2
				end
				ang += (opts.spin and os.clock() * opts.spin or 0)
				local off = Vector3.new(math.cos(ang) * r, y, math.sin(ang) * r)
				p.Size = Vector3.new(width, 0.12, math.max(0.1, segLen))
				p.CFrame = CFrame.new(pos) * rot * CFrame.new(off) * CFrame.Angles(0, -ang, 0)
				p.Transparency = tr
			end
		end
		for i, p in ipairs(spikes) do
			local ang = (i - 0.5) / #spikes * math.pi * 2
			local off = Vector3.new(math.cos(ang) * (r - 0.55), y + 0.05, math.sin(ang) * (r - 0.55))
			p.Size = Vector3.new(0.12, 0.6, 1.1)
			-- wedge pointing inward toward the centre
			p.CFrame = CFrame.new(pos) * rot * CFrame.new(off) * CFrame.Angles(0, -ang + math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
			p.Transparency = tr
		end
	end
	layout(r0, tr0)
	return V.effect({
		life = life,
		parts = parts,
		prio = opts.prio,
		id = opts.id,
		move = function(p)
			center = p
		end,
		update = function(e, a, dt, t)
			if opts.follow then
				local fp = opts.follow()
				if not fp then
					e.dead = true
					return
				end
				center = fp
			end
			local k = (opts.ease or outQuad)(a)
			local r = r0 + (r1 - r0) * k
			local tr = tr0 + (tr1 - tr0) * (opts.hold and math.max(0, (a - opts.hold) / (1 - opts.hold)) or k)
			if opts.pulse then
				tr = tr + (1 - tr) * 0.35 * (0.5 + 0.5 * math.sin(t * opts.pulse))
			end
			layout(r, tr)
		end,
	})
end

-- camera-facing ribbon between points; jitter > 0 makes a crackling bolt
function V.ribbon(a, b, width, color, life, opts)
	opts = opts or {}
	if not V.allow(opts.prio or 1) then
		return nil
	end
	local n = opts.jitter and (opts.segments or 6) or 1
	local anchors = {}
	local beams = {}
	local holder = V.part(Enum.PartType.Block, Enum.Material.SmoothPlastic, Color3.new(), Vector3.one * 0.2, CFrame.new(), 1)
	for i = 0, n do
		local at = Instance.new("Attachment")
		at.Parent = holder
		anchors[i] = at
	end
	for i = 1, n do
		local bm = Instance.new("Beam")
		bm.Attachment0 = anchors[i - 1]
		bm.Attachment1 = anchors[i]
		bm.FaceCamera = true
		bm.Width0 = width
		bm.Width1 = width
		bm.Segments = 1
		bm.LightEmission = opts.lightEmission or 1
		bm.LightInfluence = 0
		bm.Color = ColorSequence.new(opts.core or color)
		bm.Transparency = NumberSequence.new(opts.tr0 or 0)
		bm.Parent = holder
		beams[i] = bm
	end
	local glow
	if opts.glow ~= false then
		glow = Instance.new("Beam")
		glow.Attachment0 = anchors[0]
		glow.Attachment1 = anchors[n]
		glow.FaceCamera = true
		glow.Width0 = width * 3
		glow.Width1 = width * 3
		glow.LightEmission = 1
		glow.LightInfluence = 0
		glow.Color = ColorSequence.new(color)
		glow.Transparency = NumberSequence.new(0.7)
		glow.Parent = holder
	end
	local function layout(aa, bb, jit)
		local d = bb - aa
		local side = d:Cross(Vector3.yAxis)
		if side.Magnitude < 1e-3 then
			side = Vector3.xAxis
		end
		side = side.Unit
		local up = side:Cross(d.Unit)
		for i = 0, n do
			local t = i / n
			local p = aa + d * t
			if jit > 0 and i > 0 and i < n then
				p += side * rng:NextNumber(-jit, jit) + up * rng:NextNumber(-jit, jit)
			end
			anchors[i].WorldPosition = p
		end
	end
	layout(a, b, opts.jitter or 0)
	local flick = 0
	return V.effect({
		life = life,
		parts = { holder },
		prio = opts.prio,
		id = opts.id,
		update = function(e, al, dt)
			local aa, bb = a, b
			if opts.from then
				aa = opts.from() or aa
			end
			if opts.to then
				bb = opts.to() or bb
			end
			flick += dt
			if opts.jitter and flick > (Settings.get("ReducedFlash") and 0.09 or 0.035) then
				flick = 0
				layout(aa, bb, opts.jitter)
			elseif not opts.jitter and (opts.from or opts.to) then
				layout(aa, bb, 0)
			end
			local tr = (opts.tr0 or 0) + (1 - (opts.tr0 or 0)) * (opts.fade == false and 0 or outQuad(al))
			local w = width * (opts.taper and (1 - al * 0.8) or 1)
			for _, bm in ipairs(beams) do
				bm.Transparency = NumberSequence.new(tr)
				bm.Width0 = w
				bm.Width1 = w
			end
			if glow then
				glow.Transparency = NumberSequence.new(0.7 + 0.3 * al)
			end
		end,
	})
end

-- tumbling debris chunks with gravity, bouncing once on the ground they started near
function V.debris(pos, n, color, opts)
	opts = opts or {}
	if not V.allow(opts.prio or 0) then
		return nil
	end
	n = math.max(1, math.floor(n * Settings.density() + 0.5))
	local chunks = {}
	local parts = {}
	local groundY = pos.Y - 3
	local res = workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), V.worldParams)
	if res then
		groundY = res.Position.Y
	end
	for i = 1, n do
		local s = (opts.size or 0.8) * rng:NextNumber(0.6, 1.3)
		local shape = opts.shape or Enum.PartType.Block
		local p = V.part(shape, opts.material or Enum.Material.Slate, color, Vector3.new(s, s * rng:NextNumber(0.6, 1), s * rng:NextNumber(0.7, 1.4)), CFrame.new(pos), opts.tr or 0)
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.3, 1) * (opts.up or 1), rng:NextNumber(-1, 1))
		if opts.normal then
			dir = (dir + opts.normal * 1.2)
		end
		if dir.Magnitude < 0.05 then
			dir = Vector3.yAxis
		end
		chunks[i] = {
			p = p,
			vel = dir.Unit * (opts.speed or 22) * rng:NextNumber(0.5, 1.1),
			rot = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12)),
			pos = pos,
			ang = CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)),
			bounced = false,
		}
		parts[i] = p
	end
	local g = opts.gravity or 70
	local life = opts.life or 1.4
	return V.effect({
		life = life,
		parts = parts,
		prio = opts.prio,
		update = function(e, a, dt)
			for _, c in ipairs(chunks) do
				c.vel -= Vector3.new(0, g * dt, 0)
				c.pos += c.vel * dt
				if c.pos.Y < groundY + 0.3 then
					c.pos = Vector3.new(c.pos.X, groundY + 0.3, c.pos.Z)
					if not c.bounced then
						c.bounced = true
						c.vel = Vector3.new(c.vel.X * 0.4, -c.vel.Y * 0.3, c.vel.Z * 0.4)
					else
						c.vel = Vector3.new(c.vel.X * 0.8, 0, c.vel.Z * 0.8)
						c.rot *= 0.9
					end
				end
				c.ang = c.ang * CFrame.Angles(c.rot.X * dt, c.rot.Y * dt, c.rot.Z * dt)
				c.p.CFrame = CFrame.new(c.pos) * c.ang
				c.p.Transparency = a > 0.7 and (a - 0.7) / 0.3 or (opts.tr or 0)
			end
		end,
	})
end

-- bright flash (capped by reduced-flash)
function V.flash(pos, color, size, life, prio)
	local f = Settings.flash()
	V.ball(pos, size * 0.3, size, Color3.new(1, 1, 1):Lerp(color, 0.35), life or 0.18, { tr0 = 1 - 0.85 * f, tr1 = 1, light = 6 * f, prio = prio or 1 })
end

-- scorch / aftermath mark that lingers and fades
function V.mark(pos, radius, color, life, material)
	if not V.allow(0) then
		return
	end
	local res = workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -8, 0), V.worldParams)
	if not res then
		return
	end
	local p = V.part(Enum.PartType.Cylinder, material or Enum.Material.SmoothPlastic, color, Vector3.new(0.05, radius * 2, radius * 2), CFrame.new(res.Position + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.35)
	V.effect({
		life = life or 4,
		parts = { p },
		prio = 0,
		update = function(e, a)
			p.Transparency = 0.35 + 0.65 * (a > 0.6 and (a - 0.6) / 0.4 or 0)
		end,
	})
end

-- camera reaction scaled by distance to the local camera
function V.shake(pos, amount, mine)
	if not ctx.Camera then
		return
	end
	local cam = workspace.CurrentCamera
	local d = pos and (cam.CFrame.Position - pos).Magnitude or 0
	local k = math.clamp(1 - d / 90, 0, 1)
	if mine then
		k = math.max(k, 0.7)
	end
	if k > 0 then
		ctx.Camera.impulse(amount * k)
	end
end

-- world raycast params for client effects (arena + constructs only)
V.worldParams = RaycastParams.new()
V.worldParams.FilterType = Enum.RaycastFilterType.Include

-- Text billboards --------------------------------------------------------------------------------------
function V.text(adornee, pos, text, color, life, size, rise)
	local holder
	if not adornee then
		holder = V.part(Enum.PartType.Block, Enum.Material.SmoothPlastic, Color3.new(), Vector3.one * 0.2, CFrame.new(pos), 1)
		adornee = holder
	end
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, size or 34)
	bb.StudsOffset = Vector3.new(0, holder and 0 or 4.6, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 160
	bb.Adornee = adornee
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextScaled = true
	lbl.TextColor3 = color or Color3.new(1, 1, 1)
	lbl.TextStrokeTransparency = 0.25
	lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
	lbl.Text = text
	lbl.Parent = bb
	bb.Parent = holder or player:WaitForChild("PlayerGui")
	return V.effect({
		life = life or 1.4,
		parts = holder and { holder } or {},
		prio = 2,
		update = function(e, a)
			if rise then
				bb.StudsOffset = Vector3.new(0, (holder and 0 or 4.6) + rise * outQuad(a), 0)
			end
			if a > 0.75 then
				local k = (a - 0.75) / 0.25
				lbl.TextTransparency = k
				lbl.TextStrokeTransparency = 0.25 + 0.75 * k
			end
		end,
		finish = function()
			bb:Destroy()
		end,
	})
end

-- Tints (pooled highlights, one per target) ------------------------------------------------------------
local tints = {} -- target -> { hl, stack = { {c, until, fill, top} } }
local function refreshTint(target)
	local t = tints[target]
	if not t then
		return
	end
	local now = os.clock()
	local best
	for i = #t.stack, 1, -1 do
		local s = t.stack[i]
		if s.untilT <= now then
			table.remove(t.stack, i)
		elseif not best then
			best = s
		end
	end
	if not best or not target.Parent then
		if t.hl then
			t.hl:Destroy()
		end
		tints[target] = nil
		return
	end
	if not t.hl then
		local hl = Instance.new("Highlight")
		hl.OutlineTransparency = 0
		hl.Adornee = target
		hl.Parent = folder
		t.hl = hl
	end
	t.hl.FillColor = best.c
	t.hl.OutlineColor = best.c
	t.hl.FillTransparency = 1 - (1 - best.fill) * Settings.flash()
	t.hl.DepthMode = best.top and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
end
function V.tint(target, color, dur, fill, top, id)
	if not target then
		return
	end
	local t = tints[target]
	if not t then
		t = { stack = {} }
		tints[target] = t
	end
	local entry = { c = color, untilT = os.clock() + dur, fill = fill or 0.65, top = top, id = id }
	table.insert(t.stack, entry)
	refreshTint(target)
	return entry
end
function V.untint(id)
	for target, t in pairs(tints) do
		for i = #t.stack, 1, -1 do
			if t.stack[i].id == id then
				table.remove(t.stack, i)
				refreshTint(target)
				return
			end
		end
	end
end

-- Cue dispatch ------------------------------------------------------------------------------------------
V.handlers = {}
local H = V.handlers

local function styleOf(d)
	return Styles.of(d.k)
end
V.styleOf = styleOf

function V.dispatch(kind, d)
	local h = H[kind]
	if h then
		local ok, err = pcall(h, d)
		if not ok then
			warn("[EB fx] cue " .. tostring(kind) .. ": " .. tostring(err))
		end
	end
end

-- Projectiles ------------------------------------------------------------------------------------------
local projs = {}
V.projs = projs

function V.projCount()
	local n = 0
	for _ in pairs(projs) do
		n += 1
	end
	return n
end

local function stepProjectiles(dt)
	for id, pr in pairs(projs) do
		pr.age += dt
		if pr.age > (pr.life or 12) + 1 then
			V.endProjectile(id, pr.pos, "lifetime")
		else
			if pr.g then
				pr.vel -= Vector3.new(0, pr.g * dt, 0)
			end
			if pr.homing and pr.homing.Parent then
				local root = pr.homing:FindFirstChild("HumanoidRootPart") or pr.homing.PrimaryPart
				if root then
					local to = root.Position - pr.pos
					local sp = pr.vel.Magnitude
					if to.Magnitude > 0.1 and sp > 0.1 then
						local cur = pr.vel.Unit
						local want = to.Unit
						local ang = math.acos(math.clamp(cur:Dot(want), -1, 1))
						local maxA = math.rad(pr.turnRate or 180) * dt
						if ang > 1e-3 then
							local nd = cur:Lerp(want, math.min(1, maxA / ang))
							if nd.Magnitude > 1e-3 then
								pr.vel = nd.Unit * sp
							end
						end
					end
				end
			end
			pr.pos += pr.vel * dt
			if pr.ground then
				local res = workspace:Raycast(pr.pos + Vector3.new(0, 2.5, 0), Vector3.new(0, -10, 0), V.worldParams)
				if res then
					pr.pos = Vector3.new(pr.pos.X, res.Position.Y + pr.r + 0.3, pr.pos.Z)
				end
			end
			-- correction offset decays toward zero (smooths server syncs)
			pr.err *= math.max(0, 1 - dt * 10)
			local shown = pr.pos + pr.err
			if pr.render then
				pr.render(pr, shown, dt)
			end
		end
	end
end

function V.spawnProjectile(d)
	local style = styleOf(d)
	local lat = ctx.latency or 0.05
	local pr = {
		id = d.pid,
		pos = d.p + d.v * lat,
		vel = d.v,
		g = d.g,
		r = d.r or 0.45,
		style = style,
		kind = d.kind,
		size = d.sz,
		shape = d.sh,
		color = d.c,
		ground = d.gr,
		homing = d.ho,
		turnRate = d.tr,
		owner = d.o,
		life = d.life,
		age = 0,
		err = Vector3.zero,
		parts = {},
	}
	projs[d.pid] = pr
	if ctx.Fam then
		ctx.Fam.projectileBody(pr)
	end
	return pr
end

function V.syncProjectile(id, pos, vel)
	local pr = projs[id]
	if not pr then
		return
	end
	local lat = ctx.latency or 0.05
	local target = pos + vel * lat
	pr.err = (pr.pos + pr.err) - target
	if pr.err.Magnitude > 12 then
		pr.err = Vector3.zero
	end
	pr.pos = target
	pr.vel = vel
end

function V.endProjectile(id, pos, why)
	local pr = projs[id]
	if not pr then
		return
	end
	projs[id] = nil
	if pr.cleanup then
		pcall(pr.cleanup, pr)
	end
	for _, p in ipairs(pr.parts) do
		V.freePart(p)
	end
	if ctx.Fam then
		ctx.Fam.projectileEnd(pr, pos or pr.pos, why)
	end
end

H.proj = function(d)
	V.spawnProjectile(d)
end
H.projEnd = function(d)
	V.endProjectile(d.pid, d.p, d.why)
end
H.projSync = function(d)
	local pr = projs[d.pid]
	if pr and d.k then
		local st = Styles.of(d.k)
		if st ~= pr.style and d.reflect then
			-- reflected: rebuild in the new owner's style
			for _, p in ipairs(pr.parts) do
				V.freePart(p)
			end
			if pr.cleanup then
				pcall(pr.cleanup, pr)
			end
			pr.parts = {}
			pr.style = st
			pr.color = nil
			ctx.Fam.projectileBody(pr)
			V.flash(d.p, st.glow, 2, 0.15)
		end
	end
	V.syncProjectile(d.pid, d.p, d.v)
end
H.projBounce = function(d)
	local st = styleOf(d)
	V.burstParticles(d.p, st.particle, st, 6, 0.6)
end

-- Generic cue handlers ----------------------------------------------------------------------------------
H.kill = function(d)
	local e = byId[d.target]
	if e then
		e.dead = true
	end
	V.untint(d.target)
end
H.move = function(d)
	local e = byId[d.target]
	if e and e.move then
		e.move(d.p)
	end
end

H.sfx = function(d)
	Audio.legacy(d.n, d.p or d.a, d.v)
end

H.text = function(d)
	local a = d.a
	if a and not a.Parent then
		return
	end
	local e = V.text(a, d.p, d.text, d.c, d.d, d.s, 0.6)
	if e then
		e.id = d.id
		byId[d.id] = e
	end
end

H.pop = function(d)
	if not Settings.get("DamageNumbers") and d.kind ~= "info" then
		return
	end
	V.text(nil, d.p + Vector3.new(rng:NextNumber(-1, 1), 3.5, rng:NextNumber(-1, 1)), d.text, d.c, 0.9, 26, 2)
end

H.tint = function(d)
	if d.a and d.a.Parent then
		V.tint(d.a, d.c, d.d, d.f, d.m == "top", d.id)
	end
end

H.trail = function(d)
	local part = d.a
	if not part or not part.Parent then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.9, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.9, 0)
	a1.Parent = part
	local tr = Instance.new("Trail")
	tr.Attachment0 = a0
	tr.Attachment1 = a1
	tr.Color = ColorSequence.new(d.c)
	tr.Lifetime = 0.25
	tr.LightEmission = 0.7
	tr.Transparency = NumberSequence.new(0.3, 1)
	tr.Parent = part
	V.effect({
		life = d.d or 0.4,
		finish = function()
			tr:Destroy()
			a0:Destroy()
			a1:Destroy()
		end,
	})
end

-- Telegraphs: exact affected shape. Hostile = red-shifted, spiked, pulsing fill; ally = thin dashed
-- outline; self = thin solid outline. Ends with an impact pulse at the moment of resolution.
local HOSTILE = Color3.fromRGB(255, 70, 60)
local FRIEND = Color3.fromRGB(90, 210, 255)
V.HOSTILE, V.FRIEND = HOSTILE, FRIEND

local function teleColors(d)
	local rel = V.relation(d.o)
	local base = d.c or HOSTILE
	if rel == "enemy" or rel == "neutral" then
		return rel, base:Lerp(HOSTILE, 0.55)
	elseif rel == "ally" then
		return rel, base:Lerp(FRIEND, 0.5)
	end
	return rel, base:Lerp(Color3.new(1, 1, 1), 0.35)
end

local function groundAt(pos)
	local res = workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), V.worldParams)
	return res and res.Position or pos
end

H.tele = function(d)
	local rel, col = teleColors(d)
	local pos = groundAt(d.p)
	local hostile = rel == "enemy" or rel == "neutral"
	local dur = d.d or 1
	local outline = V.ring(pos, d.r, d.r, col, dur, {
		width = hostile and 0.45 or 0.22,
		dashed = rel == "ally",
		spikes = hostile,
		tr0 = hostile and 0.05 or 0.35,
		tr1 = hostile and 0.05 or 0.35,
		hold = 0.98,
		pulse = hostile and (Settings.get("ReducedFlash") and 0 or 9) or nil,
		prio = 3,
		y = 0.18,
	})
	if outline then
		outline.id = d.id
		byId[d.id] = outline
	end
	-- fill grows to the edge exactly at impact time (reads as a countdown)
	if hostile or rel == "self" then
		local fill = V.part(Enum.PartType.Cylinder, Enum.Material.Neon, col, Vector3.new(0.06, 0.2, 0.2), CFrame.new(pos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.65)
		V.effect({
			life = dur,
			parts = { fill },
			prio = 3,
			update = function(e, a)
				local r = d.r * a
				fill.Size = Vector3.new(0.06, r * 2, r * 2)
				fill.Transparency = hostile and (0.72 - 0.2 * a) or 0.85
			end,
			finish = function()
				if hostile then
					V.ring(pos, d.r * 0.95, d.r * 1.08, col, 0.25, { width = 0.6, tr0 = 0.1, prio = 2 })
				end
			end,
		})
	end
end

H.teleLine = function(d)
	local rel, col = teleColors(d)
	local hostile = rel == "enemy" or rel == "neutral"
	local dir = d.dir
	local origin = d.p
	local dur = d.d or 1
	local cf = CFrame.lookAt(origin, origin + dir)
	local parts = {}
	-- outline: two side rails + end cap at the exact width / length
	local railW = hostile and 0.4 or 0.2
	local function rail(offX, len, z)
		local p = V.part(Enum.PartType.Block, Enum.Material.Neon, col, Vector3.new(railW, 0.12, len), cf * CFrame.new(offX, 0.05, z), hostile and 0.05 or 0.4)
		table.insert(parts, p)
		return p
	end
	rail(-d.w / 2, d.l, -d.l / 2)
	rail(d.w / 2, d.l, -d.l / 2)
	local cap = V.part(Enum.PartType.Block, Enum.Material.Neon, col, Vector3.new(d.w, 0.12, railW), cf * CFrame.new(0, 0.05, -d.l), hostile and 0.05 or 0.4)
	table.insert(parts, cap)
	local fill = V.part(Enum.PartType.Block, Enum.Material.Neon, col, Vector3.new(d.w, 0.06, 0.1), cf, 0.7)
	table.insert(parts, fill)
	-- hostile chevrons point along the strike direction
	local chev = {}
	if hostile then
		local n = math.clamp(math.floor(d.l / 6), 2, 8)
		for i = 1, n do
			local p = V.part(Enum.PartType.Wedge, Enum.Material.Neon, col, Vector3.new(math.min(d.w * 0.6, 3), 0.1, 1.2), FAR, 0.3)
			chev[i] = p
			table.insert(parts, p)
		end
	end
	local e = V.effect({
		life = dur,
		parts = parts,
		prio = 3,
		update = function(e, a, dt, t)
			local len = d.l * a
			fill.Size = Vector3.new(d.w, 0.06, math.max(0.1, len))
			fill.CFrame = cf * CFrame.new(0, 0.04, -len / 2)
			for i, p in ipairs(chev) do
				local z = ((i - 1) / #chev + t * 0.6) % 1 * d.l
				p.CFrame = cf * CFrame.new(0, 0.08, -z) * CFrame.Angles(0, math.pi, 0)
			end
		end,
	})
	e.id = d.id
	byId[d.id] = e
end

-- generic shapes (styled by the family module)
H.burst = function(d)
	ctx.Fam.burst(d.p, d.r, styleOf(d), d.d, d.c)
end
H.sphere = function(d)
	ctx.Fam.sphere(d.p, d.r, styleOf(d), d.d, d.c, d.t, d.id)
end
H.disc = function(d)
	ctx.Fam.disc(d.p, d.r, styleOf(d), d.d, d.c)
end
H.ring = function(d)
	local st = styleOf(d)
	local e = V.ring(groundAt(d.p), d.r * 0.85, d.r, d.c or st.color, d.d or 0.4, { width = math.max(0.2, d.w or 0.35), tr0 = 0.1 })
	if e then
		e.id = d.id
		byId[d.id] = e
	end
end
H.rect = function(d)
	local st = styleOf(d)
	local cf = d.cf
	local p = V.part(Enum.PartType.Block, Enum.Material.Neon, d.c or st.color, Vector3.new(d.w, 0.1, d.l), cf, 0.4)
	V.effect({
		life = d.d or 0.3,
		parts = { p },
		update = function(e, a)
			p.Transparency = 0.4 + 0.6 * a
		end,
	})
	V.burstParticles(cf.Position, st.particle, st, 8, 0.8)
end
-- partial ring (gameplay sectors): exact radius and angles
H.arc = function(d)
	local st = styleOf(d)
	local span = math.abs((d.a1 or 0) - (d.a0 or 0))
	local e = V.ring(groundAt(d.p), d.r, d.r, d.c or st.glow, d.d or 0.3, {
		width = math.max(0.25, d.w or 0.4),
		arc = { d.a0, d.a1 },
		segments = math.clamp(math.floor(span / 8), 3, 24),
		tr0 = 0.1,
		hold = 0.6,
	})
	if e then
		e.id = d.id
		byId[d.id] = e
	end
	if span >= 30 and st.particle then
		local mid = math.rad((d.a0 + d.a1) / 2)
		V.burstParticles(d.p + Vector3.new(math.cos(mid) * d.r, 1, math.sin(mid) * d.r), st.particle, st, 3, 0.6, 0)
	end
end
H.phase = function(d)
	if ctx.Showcase and ctx.Showcase.phase then
		ctx.Showcase.phase(d)
	end
end
H.beam = function(d)
	ctx.Fam.beam(d.a, d.b, d.w, styleOf(d), d.d, d.c, d.id)
end
H.cone = function(d)
	ctx.Fam.cone(d.p, d.dir, d.l, d.a, styleOf(d), d.d, d.c)
end

-- persistent server visuals ("EBVis") get dressed by the family module
local function dress(inst)
	if ctx.Fam then
		local ok, err = pcall(ctx.Fam.dress, inst)
		if not ok then
			warn("[EB fx] dress: " .. tostring(err))
		end
	end
end

function V.stats()
	return { effects = #effects, liveParts = liveParts, pooled = #free, projectiles = V.projCount() }
end

function V.init(c)
	ctx = c
	Settings = c.Settings
	Audio = c.Audio
	folder.Parent = workspace
	V.worldParams.FilterDescendantsInstances = {
		workspace:WaitForChild("Arena"),
		workspace:WaitForChild("Constructs"),
	}
	for _, m in ipairs(CollectionService:GetTagged("EBFighter")) do
		track(m)
	end
	CollectionService:GetInstanceAddedSignal("EBFighter"):Connect(track)
	ctx.remotes.Cue.OnClientEvent:Connect(function(batch)
		for _, item in ipairs(batch) do
			V.dispatch(item[1], item[2])
		end
	end)
	ctx.remotes.ProjSync.OnClientEvent:Connect(function(batch)
		for _, s in ipairs(batch) do
			V.syncProjectile(s[1], s[2], s[3])
		end
	end)
	for _, inst in ipairs(CollectionService:GetTagged("EBVis")) do
		dress(inst)
	end
	CollectionService:GetInstanceAddedSignal("EBVis"):Connect(dress)
	RunService.RenderStepped:Connect(function(dt)
		stepProjectiles(dt)
		stepEffects(dt)
	end)
	-- expire tints
	task.spawn(function()
		while true do
			task.wait(0.2)
			for target in pairs(tints) do
				refreshTint(target)
			end
		end
	end)
end

return V
