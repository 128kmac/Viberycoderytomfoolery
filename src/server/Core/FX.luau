-- Server-side readable visuals: telegraphs, beams, bursts, labels. All parts are non-colliding and
-- non-queryable so they never interfere with hit detection. Warnings always precede damage.
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local S = require(script.Parent.S)

local FX = {}
S.FX = FX

local WHITE = Color3.new(1, 1, 1)

local function base(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = props.material or Enum.Material.Neon
	p.Color = props.color or WHITE
	p.Transparency = props.transparency or 0.3
	p.Shape = props.shape or Enum.PartType.Block
	p.Size = props.size or Vector3.new(1, 1, 1)
	p.CFrame = props.cf or CFrame.new()
	p.Name = props.name or "FX"
	p.Parent = props.parent or S.folders.FX
	return p
end
FX.base = base

local function fadeAndDestroy(p, dur, fade)
	if dur == nil then
		return
	end
	if fade ~= false and dur > 0.1 then
		task.delay(math.max(0, dur * 0.6), function()
			if p.Parent then
				TweenService:Create(p, TweenInfo.new(dur * 0.4), { Transparency = 1 }):Play()
			end
		end)
	end
	Debris:AddItem(p, dur)
end

-- sphere at pos, radius in studs
function FX.sphere(pos, radius, color, dur, transparency)
	local p = base({
		shape = Enum.PartType.Ball,
		size = Vector3.one * radius * 2,
		cf = CFrame.new(pos),
		color = color,
		transparency = transparency or 0.45,
	})
	fadeAndDestroy(p, dur or 0.4)
	return p
end

-- expanding burst
function FX.burst(pos, radius, color, dur)
	dur = dur or 0.35
	local p = base({
		shape = Enum.PartType.Ball,
		size = Vector3.one * 0.5,
		cf = CFrame.new(pos),
		color = color,
		transparency = 0.25,
	})
	TweenService:Create(p, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * radius * 2,
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, dur + 0.05)
	return p
end

-- flat disc on the ground (radius studs)
function FX.disc(pos, radius, color, dur, transparency, height)
	local p = base({
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(height or 0.25, radius * 2, radius * 2),
		cf = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
		color = color,
		transparency = transparency or 0.6,
		material = Enum.Material.ForceField,
	})
	if dur then
		fadeAndDestroy(p, dur)
	end
	return p
end

-- ring outline made of a thin cylinder shell approximated by 24 segments
function FX.ring(pos, radius, color, dur, thickness)
	thickness = thickness or 0.35
	local model = Instance.new("Model")
	model.Name = "Ring"
	local segs = 24
	local segLen = 2 * math.pi * radius / segs * 1.05
	for i = 1, segs do
		local a = (i / segs) * math.pi * 2
		local cf = CFrame.new(pos + Vector3.new(math.cos(a) * radius, 0.15, math.sin(a) * radius))
			* CFrame.Angles(0, -a, 0)
		base({ size = Vector3.new(thickness, 0.2, segLen), cf = cf, color = color, transparency = 0.15, parent = model })
	end
	model.Parent = S.folders.FX
	if dur then
		Debris:AddItem(model, dur)
	end
	return model
end

-- telegraph: outline ring + a disc that fills over `dur`; returns the model
function FX.telegraph(pos, radius, dur, color)
	color = color or Color3.fromRGB(255, 80, 80)
	local m = FX.ring(pos, radius, color, dur + 0.05, 0.3)
	local fill = base({
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.2, 0.2, 0.2),
		cf = CFrame.new(pos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color = color,
		transparency = 0.55,
		parent = m,
	})
	TweenService:Create(fill, TweenInfo.new(dur, Enum.EasingStyle.Linear), {
		Size = Vector3.new(0.2, radius * 2, radius * 2),
	}):Play()
	return m
end

-- rectangle telegraph along the ground
function FX.rect(cf, width, length, dur, color, transparency)
	local p = base({
		size = Vector3.new(width, 0.2, length),
		cf = cf,
		color = color or Color3.fromRGB(255, 80, 80),
		transparency = transparency or 0.55,
		material = Enum.Material.ForceField,
	})
	if dur then
		Debris:AddItem(p, dur)
	end
	return p
end

function FX.lineTelegraph(origin, dir, length, width, dur, color)
	local d = Vector3.new(dir.X, 0, dir.Z)
	if d.Magnitude < 1e-3 then
		d = Vector3.new(0, 0, -1)
	end
	d = d.Unit
	local mid = origin + d * (length / 2)
	return FX.rect(CFrame.lookAt(mid, mid + d), width, length, dur, color, 0.5)
end

-- straight beam between two points
function FX.beam(a, b, width, color, dur, transparency)
	local len = (b - a).Magnitude
	if len < 0.05 then
		return nil
	end
	local p = base({
		size = Vector3.new(width, width, len),
		cf = CFrame.lookAt((a + b) / 2, b),
		color = color,
		transparency = transparency or 0.2,
	})
	fadeAndDestroy(p, dur or 0.2)
	return p
end

-- cone fan visual
function FX.cone(origin, dir, length, angle, color, dur)
	local d = Vector3.new(dir.X, 0, dir.Z)
	if d.Magnitude < 1e-3 then
		d = Vector3.new(0, 0, -1)
	end
	d = d.Unit
	local n = math.max(3, math.floor(angle / 15))
	for i = 0, n do
		local a = -angle / 2 + angle * i / n
		local dd = CFrame.Angles(0, math.rad(a), 0):VectorToWorldSpace(d)
		FX.beam(origin, origin + dd * length, 0.3, color, dur or 0.3, 0.4)
	end
end

-- floating label (used for announcements such as Chaos outcomes or status pops)
function FX.text(adornee, text, color, dur, size)
	local holder
	if typeof(adornee) == "Vector3" then
		holder = base({ size = Vector3.new(0.2, 0.2, 0.2), cf = CFrame.new(adornee), transparency = 1 })
		adornee = holder
	end
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(240, size or 36)
	bb.StudsOffset = Vector3.new(0, 4.5, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 140
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextScaled = true
	lbl.TextColor3 = color or WHITE
	lbl.TextStrokeTransparency = 0.2
	lbl.Text = text
	lbl.Parent = bb
	bb.Adornee = adornee
	bb.Parent = holder or adornee
	Debris:AddItem(holder or bb, dur or 1.5)
	return bb
end

-- coloured highlight on a model for `dur`
function FX.highlight(model, color, dur, fill)
	if not model then
		return nil
	end
	local h = Instance.new("Highlight")
	h.FillColor = color or WHITE
	h.OutlineColor = color or WHITE
	h.FillTransparency = fill or 0.65
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = model
	if dur then
		Debris:AddItem(h, dur)
	end
	return h
end

function FX.trail(part, color, dur)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.5, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.5, 0)
	a1.Parent = part
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Color = ColorSequence.new(color)
	t.Lifetime = 0.25
	t.LightEmission = 0.6
	t.Transparency = NumberSequence.new(0.2, 1)
	t.Parent = part
	if dur then
		Debris:AddItem(t, dur)
		Debris:AddItem(a0, dur)
		Debris:AddItem(a1, dur)
	end
	return t
end

local SOUNDS = {
	swing = "rbxasset://sounds/swordslash.wav",
	lunge = "rbxasset://sounds/swordlunge.wav",
	shoot = "rbxasset://sounds/Rocket shot.wav",
	hit = "rbxasset://sounds/collide.wav",
	ping = "rbxasset://sounds/electronicpingshort.wav",
	unsheath = "rbxasset://sounds/unsheath.wav",
}
function FX.sound(where, name, volume)
	local id = SOUNDS[name]
	if not id then
		return
	end
	local holder = where
	if typeof(where) == "Vector3" then
		holder = base({ size = Vector3.new(0.2, 0.2, 0.2), cf = CFrame.new(where), transparency = 1 })
		Debris:AddItem(holder, 2)
	end
	if not holder then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.4
	s.RollOffMaxDistance = 120
	s.Parent = holder
	s:Play()
	Debris:AddItem(s, 2)
end

return FX
