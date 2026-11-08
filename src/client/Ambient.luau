-- Restrained environmental motion, all client-side: orrery rings turn, canopy and banners sway, lanterns
-- and water bob, far isles drift, fires flicker, the core pulses, tesla coils arc now and then.
-- Reduced motion stops sway / bob / drift and slows the rings; reduced flash calms flicker and arcs.
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Ambient = {}
local ctx, Settings

local items = {} -- inst -> { kind, base, phase, ... }

local function add(kind, inst)
	if items[inst] then
		return
	end
	local rec = { kind = kind, phase = math.random() * 10 }
	if inst:IsA("Model") then
		rec.base = inst:GetPivot()
		-- remember each part relative to the pivot; posing from these never accumulates error
		rec.rel = {}
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				rec.rel[d] = rec.base:ToObjectSpace(d.CFrame)
			end
		end
	elseif inst:IsA("BasePart") then
		rec.base = inst.CFrame
		rec.size = inst.Size
	elseif inst:IsA("Light") then
		rec.bright = inst.Brightness
	end
	items[inst] = rec
end

local function step(dt)
	local t = os.clock()
	local reducedMotion = Settings.get("ReducedMotion")
	local reducedFlash = Settings.get("ReducedFlash")
	for inst, r in pairs(items) do
		if not inst.Parent then
			items[inst] = nil
		elseif r.kind == "spin" then
			local speed = (inst:GetAttribute("SpinSpeed") or 4) * (reducedMotion and 0.3 or 1)
			r.angle = ((r.angle or 0) + math.rad(speed) * dt) % (math.pi * 2)
			local cf = r.base * CFrame.Angles(0, r.angle, 0)
			for part, rel in pairs(r.rel) do
				part.CFrame = cf * rel
			end
		elseif r.kind == "sway" and not reducedMotion then
			local a = math.sin(t * 0.9 + r.phase) * 0.05 + math.sin(t * 2.3 + r.phase) * 0.015
			inst.CFrame = r.base * CFrame.Angles(a, 0, a * 0.6)
		elseif r.kind == "bob" and not reducedMotion then
			inst.CFrame = r.base + Vector3.new(0, math.sin(t * 1.1 + r.phase) * 0.12, 0)
		elseif r.kind == "drift" and not reducedMotion then
			local off = Vector3.new(math.sin(t * 0.05 + r.phase) * 6, math.sin(t * 0.13 + r.phase) * 3, math.cos(t * 0.04 + r.phase) * 6)
			local cf = r.base + off
			for part, rel in pairs(r.rel) do
				part.CFrame = cf * rel
			end
		elseif r.kind == "flicker" then
			local k = reducedFlash and 0.04 or 0.18
			inst.Brightness = r.bright * (1 + math.noise(t * 6, r.phase) * k * 2)
		elseif r.kind == "pulse" then
			local k = reducedFlash and 0.03 or 0.08
			local s = 1 + math.sin(t * 1.6 + r.phase) * k
			inst.Size = r.size * s
		elseif r.kind == "arc" then
			r.next = r.next or (t + math.random() * 4)
			if t >= r.next and ctx.VFX and not reducedFlash then
				r.next = t + 2.5 + math.random() * 4
				local p = inst.Position
				local d = Vector3.new(math.random() - 0.5, -math.random() * 0.6, math.random() - 0.5).Unit
				ctx.VFX.ribbon(p, p + d * (5 + math.random() * 5), 0.12, Color3.fromRGB(200, 170, 255), 0.12, { jitter = 0.9, segments = 5, core = Color3.new(1, 1, 1), prio = 0 })
			end
		end
	end
end

function Ambient.init(c)
	ctx = c
	Settings = c.Settings
	local kinds = { EBSpin = "spin", EBSway = "sway", EBBob = "bob", EBDrift = "drift", EBFlicker = "flicker", EBPulse = "pulse", EBArc = "arc" }
	for tag, kind in pairs(kinds) do
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			add(kind, inst)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
			add(kind, inst)
		end)
	end
	RunService.RenderStepped:Connect(step)
end

function Ambient.count()
	local n = 0
	for _ in pairs(items) do
		n += 1
	end
	return n
end

return Ambient
