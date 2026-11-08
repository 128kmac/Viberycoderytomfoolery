-- Showcase choreography for the eight showcase powers: Fire, Ice, Electric, Gravity, Water, Wind,
-- Earth, Light. Each gets a bespoke anticipation (windup) and release motif per slot, and its ultimate
-- is staged as buildup -> escalation -> climax -> release, driven by "phase" beats the server emits at
-- the exact gameplay moments (see K.phase in the showcase kits). Gravity's ultimate, The Falling Kingdom,
-- is the signature sequence: the floor tears loose, a black crown forms overhead and slams the debris
-- down twice before collapsing.
--
-- Everything here is client-side, pooled through the VFX core, and scaled by quality / reduced-flash /
-- reduced-motion settings. Hooks return true when they fully handled a cue (family default skipped).
local Lighting = game:GetService("Lighting")
local V = require(script.Parent)

local Showcase = {}
local ctx, Settings, Audio
local rng = V.rng
local Styles = V.Styles

-- Shared helpers ---------------------------------------------------------------------------------------
local function rootOf(model)
	return model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
end

local function groundAt(pos, up)
	local res = workspace:Raycast(pos + Vector3.new(0, up or 4, 0), Vector3.new(0, -((up or 4) + 14), 0), V.worldParams)
	return res and res.Position or pos
end

local function isMine(d)
	return d.o ~= nil and d.o == V.myId()
end

-- screen grade (local ColorCorrection) with stacked weights so overlapping ultimates blend
local grade
local gradeStack = {}
local function pushGrade(id, tint, sat, bright, dur, ease)
	if not grade then
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "EBShowcaseGrade"
		grade.Parent = Lighting
	end
	local k = Settings.get("ReducedFlash") and 0.45 or 1
	gradeStack[id] = { tint = tint, sat = sat * k, bright = bright * k, t0 = os.clock(), dur = dur, ease = ease or 0.4 }
end
local function popGrade(id)
	local g = gradeStack[id]
	if g then
		g.release = os.clock()
	end
end
local function stepGrade()
	if not grade then
		return
	end
	local now = os.clock()
	local tint, sat, bright, w = Color3.new(1, 1, 1), 0, 0, 0
	for id, g in pairs(gradeStack) do
		local inK = math.clamp((now - g.t0) / g.ease, 0, 1)
		local outK = g.release and math.clamp(1 - (now - g.release) / 0.9, 0, 1) or 1
		if now - g.t0 > g.dur then
			outK = math.min(outK, math.clamp(1 - (now - g.t0 - g.dur) / 0.9, 0, 1))
		end
		local k = inK * outK
		if k <= 0 and (g.release or now - g.t0 > g.dur) then
			gradeStack[id] = nil
		else
			tint = tint:Lerp(g.tint, k)
			sat += g.sat * k
			bright += g.bright * k
			w = math.max(w, k)
		end
	end
	grade.TintColor = tint
	grade.Saturation = sat
	grade.Brightness = bright
	grade.Enabled = w > 0.001
end

-- a part animated by fn(part, a, t) over life
local function animPart(shape, mat, color, size, cf, tr, life, fn, prio)
	local p = V.part(shape, mat, color, size, cf, tr)
	return V.effect({
		life = life,
		parts = { p },
		prio = prio or 2,
		update = function(e, a, dt, t)
			fn(p, a, t, dt, e)
		end,
	})
end

-- ring of n tumbling chunks orbiting a point (anticipation for Earth / Gravity)
local function orbiters(center, n, radius, color, mat, life, size, rise)
	local list = {}
	for i = 1, n do
		list[i] = { ang = i / n * math.pi * 2, h = rng:NextNumber(-0.4, 0.4), spin = rng:NextNumber(3, 7) }
	end
	local parts = {}
	for i = 1, n do
		parts[i] = V.part(Enum.PartType.Block, mat, color, Vector3.one * (size or 0.6) * rng:NextNumber(0.7, 1.3), CFrame.new(center()), 0)
	end
	return V.effect({
		life = life,
		parts = parts,
		prio = 2,
		update = function(e, a, dt, t)
			local c = center()
			if not c then
				e.dead = true
				return
			end
			local r = radius * (1 - a * 0.65)
			for i, o in ipairs(list) do
				local ang = o.ang + t * 2.6
				local y = o.h + (rise or 0) * a
				parts[i].CFrame = CFrame.new(c + Vector3.new(math.cos(ang) * r, y, math.sin(ang) * r)) * CFrame.Angles(t * o.spin, t * o.spin * 0.7, 0)
			end
		end,
	})
end

-- jagged bolt from the sky
local function skyBolt(target, color, width)
	local top = target + Vector3.new(rng:NextNumber(-6, 6), 70, rng:NextNumber(-6, 6))
	V.ribbon(top, target, width or 0.5, color, 0.22, { jitter = 2.4, segments = 10, core = Color3.new(1, 1, 1), prio = 2 })
	V.ribbon(top, target, (width or 0.5) * 0.4, color, 0.18, { jitter = 3, segments = 8, glow = false, prio = 1 })
	V.flash(target, color, 5, 0.2, 2)
	V.burstParticles(target, "spark", Styles.of("Electric"), 24, 1.2, 2)
end

-- Per-power motifs ---------------------------------------------------------------------------------------
local M = {}

-- FIRE: embers spiral into a palm fireball; releases blast with a backdraft puff --------------------------
M.Fire = {
	cast = function(d, st, model, hand, w)
		local hp = function()
			return model.Parent and V.handPos(model, hand) or nil
		end
		local life = math.max(w, 0.25) + 0.15
		local core = animPart(Enum.PartType.Ball, Enum.Material.Neon, st.glow, Vector3.one * 0.2, CFrame.new(hp() or Vector3.zero), 0.1, life, function(p, a, t)
			local h = hp()
			if not h then
				return
			end
			local k = math.min(1, t / math.max(0.1, w))
			p.CFrame = CFrame.new(h)
			p.Size = Vector3.one * (0.3 + 0.9 * k * (d.ult and 1.6 or 1)) * (1 + 0.15 * math.sin(t * 40))
			p.Color = st.glow:Lerp(Color3.new(1, 1, 0.85), 0.5 + 0.5 * math.sin(t * 25))
		end)
		local holder = core.parts[1]
		local pe = Instance.new("ParticleEmitter")
		V.configure(pe, "flame", st, 0.6)
		pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		pe.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		pe.Rate = 40 * Settings.density()
		pe.Parent = holder
		V.light(holder, st.glow, 2, 14)
		Audio.family(st, "charge", hp(), d.ult and 1.4 or 1)
		return true
	end,
	release = function(d, st, hp, model)
		if not hp then
			return false
		end
		local root = rootOf(model)
		local fwd = root and root.CFrame.LookVector or Vector3.zAxis
		V.flash(hp, st.glow, d.slot == 2 and 3 or 2, 0.12, 2)
		V.burstParticles(hp, "flame", st, 14, 0.9, 2)
		-- backdraft: smoke ring puffs behind the hand
		V.burstParticles(hp - fwd * 1.2, "dust", Styles.of("Ash"), 6, 0.7, 1)
		if d.slot == 2 and root then
			-- Flamewheel: a ring of fire wraps the body
			V.ring(root.Position - Vector3.new(0, 2.8, 0), 1.5, 4.5, st.glow, 0.45, { width = 0.6, tr0 = 0, prio = 2 })
			V.burstParticles(root.Position, "flame", st, 26, 1.3, 2)
		elseif d.slot == 4 and root then
			-- Furnace Wall: both palms throw fire upward
			for _, h in ipairs({ "left", "right" }) do
				local p = V.handPos(model, h)
				if p then
					V.burstParticles(p, "flame", st, 12, 1.1, 2)
				end
			end
		end
		Audio.family(st, "release", hp, 1.1)
		return true
	end,
}

-- ICE: shards assemble around the hand in a tightening crown; releases with frost breath ----------------------
M.Ice = {
	cast = function(d, st, model, hand, w)
		local hp = function()
			return model.Parent and V.handPos(model, hand) or nil
		end
		local life = math.max(w, 0.25) + 0.2
		local n = d.ult and 8 or 5
		local shards = {}
		for i = 1, n do
			shards[i] = V.part(Enum.PartType.Wedge, Enum.Material.Glass, st.pale, Vector3.new(0.18, 0.5, 1.1), CFrame.new(hp() or Vector3.zero), 0.15)
		end
		V.effect({
			life = life,
			parts = shards,
			prio = 2,
			update = function(e, a, dt, t)
				local h = hp()
				if not h then
					e.dead = true
					return
				end
				local k = math.min(1, t / math.max(0.1, w))
				local r = 2.4 - 1.7 * k
				for i, p in ipairs(shards) do
					local ang = i / n * math.pi * 2 + t * 3
					local pos = h + Vector3.new(math.cos(ang) * r, math.sin(ang * 2) * 0.3, math.sin(ang) * r)
					p.CFrame = CFrame.lookAt(pos, h)
				end
			end,
		})
		V.burstParticles(hp() or Vector3.zero, "frost", st, 10, 0.6, 1)
		Audio.family(st, "charge", hp(), d.ult and 1.4 or 1)
		return true
	end,
	release = function(d, st, hp, model)
		if not hp then
			return false
		end
		V.flash(hp, st.pale, 1.8, 0.1, 2)
		V.debris(hp, 5, st.pale, { material = Enum.Material.Glass, shape = Enum.PartType.Wedge, size = 0.35, speed = 14, life = 0.7, tr = 0.2, prio = 1 })
		V.burstParticles(hp, "frost", st, 16, 0.9, 2)
		local root = rootOf(model)
		if d.slot == 2 and root then
			-- Skate Cut: frost bloom where the slide starts
			V.ring(root.Position - Vector3.new(0, 2.9, 0), 0.5, 4, st.pale, 0.5, { width = 0.35, tr0 = 0.1, prio = 2 })
		elseif d.slot == 3 and root then
			V.mark(root.Position + root.CFrame.LookVector * 6, 3, st.pale, 3, Enum.Material.Ice)
		end
		Audio.family(st, "release", hp, 1.1)
		return true
	end,
}

-- ELECTRIC: arcs leap between the fingers; release cracks like thunder ----------------------------------------
M.Electric = {
	cast = function(d, st, model, hand, w)
		local life = math.max(w, 0.2) + 0.15
		local acc = 0
		V.effect({
			life = life,
			prio = 2,
			update = function(e, a, dt, t)
				if not model.Parent then
					e.dead = true
					return
				end
				acc += dt
				local every = Settings.get("ReducedFlash") and 0.12 or 0.05
				if acc >= every then
					acc = 0
					local h = V.handPos(model, hand)
					if h then
						local other = V.handPos(model, hand == "left" and "right" or "left") or (h + Vector3.yAxis)
						local target = d.ult and other or (h + Vector3.new(rng:NextNumber(-1.4, 1.4), rng:NextNumber(-0.6, 1.4), rng:NextNumber(-1.4, 1.4)))
						V.ribbon(h, target, 0.08, st.glow, 0.06, { jitter = 0.5, segments = 4, core = Color3.new(1, 1, 1), glow = false, prio = 1 })
					end
				end
			end,
		})
		Audio.family(st, "charge", V.handPos(model, hand), d.ult and 1.4 or 1)
		return true
	end,
	release = function(d, st, hp, model)
		if not hp then
			return false
		end
		V.flash(hp, st.glow, 2.4, 0.08, 2)
		for _ = 1, 3 do
			local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 1), rng:NextNumber(-1, 1)).Unit
			V.ribbon(hp, hp + dir * rng:NextNumber(2, 3.5), 0.1, st.glow, 0.1, { jitter = 0.5, segments = 4, core = Color3.new(1, 1, 1), prio = 1 })
		end
		V.burstParticles(hp, "spark", st, 18, 0.9, 2)
		local root = rootOf(model)
		if d.slot == 2 and root then
			V.ring(root.Position - Vector3.new(0, 2.9, 0), 0.5, 3.5, st.glow, 0.25, { width = 0.2, tr0 = 0, prio = 2 })
		end
		Audio.family(st, "release", hp, 1.1)
		return true
	end,
}

-- GRAVITY: a dark mote condenses at the hand while pebbles lift around the caster ------------------------------
M.Gravity = {
	cast = function(d, st, model, hand, w)
		local hp = function()
			return model.Parent and V.handPos(model, hand) or nil
		end
		local life = math.max(w, 0.25) + 0.15
		animPart(Enum.PartType.Ball, Enum.Material.SmoothPlastic, Color3.fromRGB(14, 6, 26), Vector3.one * 0.2, CFrame.new(hp() or Vector3.zero), 0, life, function(p, a, t)
			local h = hp()
			if h then
				local k = math.min(1, t / math.max(0.1, w))
				p.CFrame = CFrame.new(h)
				p.Size = Vector3.one * (0.25 + 0.75 * k * (d.ult and 1.5 or 1))
			end
		end)
		animPart(Enum.PartType.Ball, Enum.Material.ForceField, st.glow, Vector3.one * 2.4, CFrame.new(hp() or Vector3.zero), 0.2, life, function(p, a, t)
			local h = hp()
			if h then
				p.CFrame = CFrame.new(h)
				p.Size = Vector3.one * (2.6 - 1.4 * a + 0.2 * math.sin(t * 12))
			end
		end)
		local root = rootOf(model)
		if root then
			orbiters(function()
				return root.Parent and (root.Position - Vector3.new(0, 2.4, 0)) or nil
			end, d.ult and 10 or 5, d.ult and 6 or 3.5, Color3.fromRGB(90, 84, 104), Enum.Material.Slate, life, 0.5, d.ult and 3.5 or 1.6)
		end
		Audio.family(st, "charge", hp(), d.ult and 1.6 or 1)
		return true
	end,
	release = function(d, st, hp, model)
		if not hp then
			return false
		end
		V.ball(hp, 2.2, 0.2, st.glow, 0.18, { tr0 = 0.3, material = Enum.Material.ForceField, ease = V.inQuad, prio = 2 })
		task.delay(0.12, function()
			V.flash(hp, st.glow, 1.8, 0.1, 2)
		end)
		V.burstParticles(hp, "mote", st, 14, 1, 2)
		Audio.family(st, "release", hp, 1.1)
		if d.slot == 4 and isMine(d) then
			ctx.Camera.kick(0.2)
		end
		return true
	end,
}

-- WATER: a globe gathers and churns at the hand; release splashes forward ---------------------------------------
M.Water = {
	cast = function(d, st, model, hand, w)
		local hp = function()
			return model.Parent and V.handPos(model, hand) or nil
		end
		local life = math.max(w, 0.25) + 0.15
		animPart(Enum.PartType.Ball, Enum.Material.Glass, st.pale, Vector3.one * 0.2, CFrame.new(hp() or Vector3.zero), 0.25, life, function(p, a, t)
			local h = hp()
			if h then
				local k = math.min(1, t / math.max(0.1, w))
				local r = (0.3 + 0.8 * k * (d.ult and 1.5 or 1))
				p.CFrame = CFrame.new(h) * CFrame.Angles(t * 3, t * 5, 0)
				p.Size = Vector3.new(r * 2 * (1 + 0.12 * math.sin(t * 18)), r * 2 * (1 - 0.1 * math.sin(t * 18)), r * 2)
			end
		end)
		V.burstParticles(hp() or Vector3.zero, "drip", st, 8, 0.6, 1)
		Audio.family(st, "charge", hp(), d.ult and 1.4 or 1)
		return true
	end,
	release = function(d, st, hp, model)
		if not hp then
			return false
		end
		V.ball(hp, 0.6, 2.2, st.pale, 0.25, { tr0 = 0.35, material = Enum.Material.Glass, prio = 2 })
		V.burstParticles(hp, "drip", st, 18, 1, 2)
		local root = rootOf(model)
		if d.slot == 3 and root then
			V.ring(root.Position - Vector3.new(0, 2.8, 0), 0.5, 5, st.pale, 0.5, { width = 0.3, tr0 = 0.2, prio = 2 })
		end
		Audio.family(st, "release", hp, 1.1)
		return true
	end,
}

-- WIND: streaks spiral up the arm; release is a pressure ring --------------------------------------------------
M.Wind = {
	cast = function(d, st, model, hand, w)
		local root = rootOf(model)
		local life = math.max(w, 0.2) + 0.15
		local acc = 0
		V.effect({
			life = life,
			prio = 2,
			update = function(e, a, dt, t)
				if not model.Parent or not root then
					e.dead = true
					return
				end
				acc += dt
				if acc > 0.07 then
					acc = 0
					local ang = t * 9
					local r = d.ult and 3.5 or 2
					local p0 = root.Position + Vector3.new(math.cos(ang) * r, -2 + a * 4, math.sin(ang) * r)
					local p1 = root.Position + Vector3.new(math.cos(ang + 0.9) * r, -1.4 + a * 4, math.sin(ang + 0.9) * r)
					V.ribbon(p0, p1, 0.12, st.pale, 0.2, { core = Color3.new(1, 1, 1), tr0 = 0.3, taper = true, glow = false, prio = 1 })
				end
			end,
		})
		if root then
			V.burstParticles(root.Position - Vector3.new(0, 2.6, 0), "dust", Styles.of("Sand"), 5, 0.6, 1)
		end
		Audio.family(st, "charge", root and root.Position, d.ult and 1.4 or 1)
		return true
	end,
	release = function(d, st, hp, model)
		if not hp then
			return false
		end
		local root = rootOf(model)
		local fwd = root and root.CFrame.LookVector or Vector3.zAxis
		local rot = CFrame.lookAt(Vector3.zero, fwd) * CFrame.Angles(math.pi / 2, 0, 0)
		V.ring(hp, 0.4, 2.6, st.pale, 0.22, { width = 0.15, tr0 = 0.1, rot = rot.Rotation, y = 0, prio = 2 })
		V.burstParticles(hp, "streak", st, 14, 1, 2)
		if d.slot == 2 and root then
			V.burstParticles(root.Position - Vector3.new(0, 2.6, 0), "dust", Styles.of("Sand"), 8, 0.8, 1)
		end
		Audio.family(st, "release", hp, 1.1)
		return true
	end,
}

-- EARTH: stones tear loose and orbit the caster; release stamps the ground -------------------------------------------
M.Earth = {
	cast = function(d, st, model, hand, w)
		local root = rootOf(model)
		if not root then
			return false
		end
		local life = math.max(w, 0.25) + 0.15
		orbiters(function()
			return root.Parent and (root.Position - Vector3.new(0, 2.2, 0)) or nil
		end, d.ult and 9 or 5, d.ult and 5 or 3, st.color, Enum.Material.Slate, life, d.ult and 1 or 0.7, d.ult and 2 or 1.2)
		V.mark(root.Position, d.ult and 4 or 2, Color3.fromRGB(46, 38, 32), life + 1.5, Enum.Material.Slate)
		Audio.family(st, "charge", root.Position, d.ult and 1.5 or 1)
		if d.ult and isMine(d) then
			ctx.Camera.impulse(0.15)
		end
		return true
	end,
	release = function(d, st, hp, model)
		local root = rootOf(model)
		if not root then
			return false
		end
		local feet = root.Position - Vector3.new(0, 2.9, 0)
		V.ring(feet, 0.6, 5, st.deep, 0.35, { width = 0.6, tr0 = 0.2, material = Enum.Material.Slate, prio = 2 })
		V.debris(feet + Vector3.new(0, 0.5, 0), 6, st.color, { size = 0.6, speed = 16, life = 0.9, prio = 1 })
		V.burstParticles(feet, "dust", st, 10, 1, 1)
		Audio.family(st, "release", feet, 1.2)
		V.shake(feet, 0.12, isMine(d))
		return true
	end,
}

-- LIGHT: a halo blooms behind the hand and rays converge; release is a lens flare -------------------------------------
M.Light = {
	cast = function(d, st, model, hand, w)
		local root = rootOf(model)
		local hp = function()
			return model.Parent and V.handPos(model, hand) or nil
		end
		local life = math.max(w, 0.25) + 0.15
		local h0 = hp()
		if h0 and root then
			local face = root.CFrame.LookVector
			local rot = CFrame.lookAt(Vector3.zero, face) * CFrame.Angles(math.pi / 2, 0, 0)
			V.ring(h0 - face * 0.6, d.ult and 3.2 or 1.8, d.ult and 1.4 or 0.7, st.glow, life, { width = 0.12, tr0 = 0.1, tr1 = 0.3, rot = rot.Rotation, y = 0, spin = 2, prio = 2, follow = function()
				local h = hp()
				return h and (h - root.CFrame.LookVector * 0.6) or nil
			end })
		end
		animPart(Enum.PartType.Ball, Enum.Material.Neon, Color3.new(1, 1, 0.92), Vector3.one * 0.2, CFrame.new(h0 or Vector3.zero), 0, life, function(p, a, t)
			local h = hp()
			if h then
				p.CFrame = CFrame.new(h)
				p.Size = Vector3.one * (0.2 + 0.6 * math.min(1, t / math.max(0.1, w)))
			end
		end)
		Audio.family(st, "charge", h0, d.ult and 1.4 or 1)
		return true
	end,
	release = function(d, st, hp, model)
		if not hp then
			return false
		end
		V.flash(hp, st.glow, 2.6, 0.12, 2)
		local cam = workspace.CurrentCamera
		local right = cam.CFrame.RightVector
		local up = cam.CFrame.UpVector
		-- anamorphic streak (camera-facing cross)
		V.ribbon(hp - right * 3, hp + right * 3, 0.15, st.glow, 0.14, { core = Color3.new(1, 1, 1), taper = true, prio = 1 })
		V.ribbon(hp - up * 1.2, hp + up * 1.2, 0.1, st.glow, 0.12, { core = Color3.new(1, 1, 1), taper = true, glow = false, prio = 1 })
		V.burstParticles(hp, "glint", st, 12, 1, 2)
		Audio.family(st, "release", hp, 1.1)
		return true
	end,
}

-- Ultimates ------------------------------------------------------------------------------------------------------------
local ults = {} -- key "owner:kit" -> state

local function key(d)
	return tostring(d.o) .. ":" .. tostring(d.k)
end

-- distance-scaled shake + FOV punch for viewers near the climax
local function climax(pos, amount, d)
	V.shake(pos, amount, isMine(d))
	local cam = workspace.CurrentCamera
	if (cam.CFrame.Position - pos).Magnitude < 60 then
		ctx.Camera.punch(math.min(1, amount))
	end
end

local U = {}

-- GRAVITY · The Falling Kingdom (signature) ----------------------------------------------------------------------------
U.Gravity = {}
function U.Gravity.begin(d)
	local st = Styles.of("Gravity")
	local center = groundAt(d.p)
	local R = d.r or 24
	local crownY = 22
	local s = { center = center, R = R, mode = "rise", modeT = os.clock(), parts = {}, chunks = {}, alive = true }
	ults[key(d)] = s
	pushGrade(key(d), Color3.fromRGB(215, 200, 255), -0.35, -0.05, 6, 0.6)
	-- fracture ring on the floor at the exact edge
	V.ring(center, R, R, st.glow, 4.6, { width = 0.5, tr0 = 0.1, tr1 = 0.1, hold = 0.95, pulse = Settings.get("ReducedFlash") and 0 or 5, prio = 3 })
	V.ring(center, R * 0.55, R * 0.55, st.deep:Lerp(st.glow, 0.4), 4.6, { width = 0.25, dashed = true, spin = -0.8, tr0 = 0.3, tr1 = 0.3, hold = 0.95, prio = 2 })
	-- the Crown: black core, lensing shell and three tilted rings (echoes the arena's orrery)
	local crownPos = center + Vector3.new(0, crownY, 0)
	local core = V.part(Enum.PartType.Ball, Enum.Material.SmoothPlastic, Color3.fromRGB(8, 2, 16), Vector3.one * 1, CFrame.new(crownPos), 0)
	local shell = V.part(Enum.PartType.Ball, Enum.Material.ForceField, st.glow, Vector3.one * 2, CFrame.new(crownPos), 0.1)
	V.light(shell, st.glow, 3, 50)
	s.core, s.shell = core, shell
	for i = 1, 3 do
		local tilt = CFrame.Angles(math.rad(25 * i - 50), 0, math.rad(15 * i))
		V.ring(crownPos, 6 + i * 2.2, 6 + i * 2.2, i == 2 and st.pale or st.glow, 4.6, {
			width = 0.25,
			rot = tilt,
			y = 0,
			spin = (i % 2 == 0 and -1 or 1) * (1.2 + i * 0.4),
			tr0 = 0.15,
			tr1 = 0.15,
			hold = 0.95,
			prio = 2,
		})
	end
	-- floor chunks tear loose inside the field (they stay flush until the first upward pulse)
	local n = math.floor(18 * Settings.density() + 0.5) + 4
	local floorCol = Color3.fromRGB(96, 90, 104)
	for i = 1, n do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = math.sqrt(rng:NextNumber(0.02, 1)) * (R - 2)
		local g = groundAt(center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
		local sz = Vector3.new(rng:NextNumber(1.2, 3), rng:NextNumber(0.6, 1.4), rng:NextNumber(1.2, 3))
		local p = V.part(Enum.PartType.Block, Enum.Material.Slate, floorCol:Lerp(st.deep, rng:NextNumber(0, 0.35)), sz, CFrame.new(g), 0)
		table.insert(s.chunks, { p = p, base = g, lift = rng:NextNumber(7, 15), ang = CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)), spin = Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(-2, 2), rng:NextNumber(-2, 2)), y = 0 })
	end
	local all = { core, shell }
	for _, c in ipairs(s.chunks) do
		table.insert(all, c.p)
	end
	s.effect = V.effect({
		life = 6.5,
		parts = all,
		prio = 3,
		update = function(e, a, dt, t)
			if not s.alive and not s.collapsing and t > (s.endT or 99) + 1.2 then
				e.dead = true
				return
			end
			local now = os.clock()
			local mt = now - s.modeT
			-- crown breathing: pulls in during rises, flares on slams
			local crownR = 2.2 + math.min(t, 1.5) * 1.2
			if s.mode == "rise" then
				crownR *= 0.9
			elseif s.mode == "slam" then
				crownR *= 1 + 0.35 * math.max(0, 1 - mt / 0.3)
			elseif s.mode == "end" then
				crownR *= math.max(0, 1 - mt / 0.35)
			end
			core.Size = Vector3.one * math.max(0.05, crownR)
			shell.Size = Vector3.one * math.max(0.1, crownR * 2.6 + math.sin(t * 9) * 0.3)
			local cy = crownY
			if s.mode == "slam" then
				cy = crownY - 6 * math.max(0, 1 - mt / 0.4)
			end
			core.CFrame = CFrame.new(center + Vector3.new(0, cy, 0))
			shell.CFrame = core.CFrame
			-- debris choreography
			for _, c in ipairs(s.chunks) do
				local target
				if s.mode == "rise" then
					target = c.lift * V.outCubic(math.min(1, mt / 0.9))
				elseif s.mode == "hold" then
					target = c.lift + math.sin(now * 40 + c.lift) * 0.15
				elseif s.mode == "slam" then
					target = c.lift * math.max(0, 1 - (mt / 0.16) ^ 2)
				else
					target = 0
				end
				if s.mode ~= "slam" then
					c.y += (target - c.y) * math.min(1, dt * 12)
				else
					c.y = target
				end
				local spinK = s.mode == "rise" and 1 or (s.mode == "hold" and 0.2 or 0)
				c.ang = c.ang * CFrame.Angles(c.spin.X * dt * spinK, c.spin.Y * dt * spinK, c.spin.Z * dt * spinK)
				local pull = (s.mode == "collapse") and math.min(1, mt / 0.4) or 0
				local pos = c.base:Lerp(center + Vector3.new(0, crownY * 0.6, 0), pull)
				c.p.CFrame = CFrame.new(pos + Vector3.new(0, c.y, 0)) * c.ang
				if s.mode == "end" then
					c.p.Transparency = math.min(1, mt / 1.0)
				end
			end
		end,
	})
	Audio.family(st, "release", center, 1.4)
	Audio.play("ultRelease", center, 1.1, 0.7)
end
function U.Gravity.up(d)
	local s = ults[key(d)]
	if not s then
		return
	end
	local st = Styles.of("Gravity")
	s.mode, s.modeT = "rise", os.clock()
	-- upward gravity wave: rings climb the field, dust spirals up
	for i = 0, 2 do
		task.delay(i * 0.12, function()
			V.ring(s.center + Vector3.new(0, 1 + i * 3, 0), s.R * 0.9, s.R * 0.6, st.glow, 0.6, { width = 0.3, tr0 = 0.3, prio = 2, y = 0 })
		end)
	end
	V.burstParticles(s.center, "mote", st, 24, 2.5, 2)
	V.burstParticles(s.center, "dust", Styles.of("Rock"), 10, 2, 1)
	Audio.play("ultCharge", s.center, 0.9, 1 + (d.cycle or 1) * 0.15)
	V.shake(s.center, 0.15, isMine(d))
end
function U.Gravity.downWarn(d)
	local s = ults[key(d)]
	if not s then
		return
	end
	local st = Styles.of("Gravity")
	s.mode, s.modeT = "hold", os.clock()
	-- the crown flashes: everything freezes, trembling, a beat before the slam
	V.flash(s.center + Vector3.new(0, 22, 0), st.pale, 6, 0.25, 3)
	Audio.play("ping", s.center + Vector3.new(0, 20, 0), 1.2, 0.5)
end
function U.Gravity.down(d)
	local s = ults[key(d)]
	if not s then
		return
	end
	local st = Styles.of("Gravity")
	local cycle = d.cycle or 1
	s.mode, s.modeT = "slam", os.clock()
	local c = s.center
	-- the column of force from the crown to the floor
	V.ribbon(c + Vector3.new(0, 22, 0), c, 7 + cycle * 2, st.glow, 0.35, { core = Color3.new(1, 1, 1), taper = true, prio = 3 })
	-- impacts land a beat after the slam starts (debris falls 0.16 s)
	task.delay(0.15, function()
		V.ring(c, 2, s.R * (1.15 + cycle * 0.1), st.glow, 0.55, { width = 1.2, tr0 = 0, prio = 3 })
		V.ring(c, 1, s.R * 0.8, Color3.new(1, 1, 1), 0.35, { width = 0.5, tr0 = 0.2, prio = 3 })
		for _, ch in ipairs(s.chunks) do
			if rng:NextNumber() < 0.5 * Settings.density() + 0.2 then
				V.burstParticles(ch.base, "dust", Styles.of("Rock"), 3, 1.2, 0)
			end
		end
		V.burstParticles(c, "dust", Styles.of("Rock"), 20, 3, 2)
		V.burstParticles(c, "mote", st, 18, 2, 2)
		Audio.family(st, "impact", c, 1.6)
		Audio.play("ultRelease", c, 1.2, 0.55 + cycle * 0.05)
		climax(c, 0.55 + cycle * 0.2, d)
		for _ = 1, 4 + cycle * 2 do
			local a = rng:NextNumber(0, math.pi * 2)
			V.mark(c + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(2, s.R - 2), rng:NextNumber(1.5, 3), Color3.fromRGB(30, 18, 40), 4.5, Enum.Material.Slate)
		end
	end)
end
function U.Gravity.collapse(d)
	local s = ults[key(d)]
	if not s then
		return
	end
	local st = Styles.of("Gravity")
	s.collapsing = true
	s.mode, s.modeT = "collapse", os.clock()
	pushGrade(key(d) .. "c", Color3.fromRGB(150, 120, 220), -0.6, -0.12, 0.9, 0.2)
	V.ball(s.center + Vector3.new(0, 13, 0), 0.5, s.R * 0.8, Color3.fromRGB(10, 0, 20), 0.4, { tr0 = 0.2, tr1 = 0.6, material = Enum.Material.SmoothPlastic, prio = 3 })
	task.delay(0.4, function()
		V.flash(s.center, st.glow, 14, 0.3, 3)
		V.ring(s.center, 2, s.R * 1.4, st.glow, 0.6, { width = 1.5, tr0 = 0, prio = 3 })
		climax(s.center, 1.0, d)
		Audio.play("ultRelease", s.center, 1.4, 0.45)
		s.mode, s.modeT = "end", os.clock()
		popGrade(key(d) .. "c")
	end)
end
function U.Gravity.finish(d)
	local s = ults[key(d)]
	if not s then
		return
	end
	local st = Styles.of("Gravity")
	s.alive = false
	s.endT = os.clock() - s.effect.t0
	if not d.unstable then
		s.mode, s.modeT = "end", os.clock()
		-- release: the crown implodes to a point and lets go
		local cp = s.center + Vector3.new(0, 22, 0)
		task.delay(0.3, function()
			V.flash(cp, st.pale, 5, 0.18, 2)
			V.ring(cp, 0.5, 10, st.glow, 0.5, { width = 0.4, tr0 = 0, y = 0, rot = CFrame.Angles(math.rad(90), 0, 0), prio = 2 })
			Audio.play("ping", cp, 1, 0.4)
		end)
	end
	popGrade(key(d))
	task.delay(2, function()
		if ults[key(d)] == s then
			ults[key(d)] = nil
		end
	end)
end

-- FIRE · Cremation Horizon -------------------------------------------------------------------------------------------
U.Fire = {}
function U.Fire.begin(d)
	local st = Styles.of(d.unstable and "Solar" or "Fire")
	ults[key(d)] = { st = st }
	pushGrade(key(d), Color3.fromRGB(255, 225, 200), 0.1, 0.02, 3.2, 0.5)
	V.burstParticles(groundAt(d.p), "flame", st, 20, 2, 2)
end
function U.Fire.warn(d)
	local s = ults[key(d)]
	local st = s and s.st or Styles.of("Fire")
	-- the line smoulders: embers rise along the exact front
	local n = 6
	for i = 0, n do
		local p = groundAt(d.a:Lerp(d.b, i / n))
		V.burstParticles(p, "flame", st, 3, 0.7, 1)
	end
	Audio.family(st, "charge", d.a:Lerp(d.b, 0.5), 1.2)
end
function U.Fire.strike(d)
	local s = ults[key(d)]
	local st = s and s.st or Styles.of("Fire")
	local n = math.floor(7 * Settings.density() + 0.5) + 3
	for i = 0, n do
		local p = groundAt(d.a:Lerp(d.b, i / n))
		local h = rng:NextNumber(7, 12) * (d.unstable and 1.3 or 1)
		local w = rng:NextNumber(1.6, 2.6)
		-- a wall of flame columns erupts then collapses
		animPart(Enum.PartType.Ball, Enum.Material.Neon, st.glow, Vector3.new(w, 0.5, w), CFrame.new(p), 0.05, 0.55, function(part, a)
			local k = a < 0.3 and V.outQuad(a / 0.3) or (1 - (a - 0.3) / 0.7)
			part.Size = Vector3.new(w * (1 - a * 0.4), math.max(0.2, h * k), w * (1 - a * 0.4))
			part.CFrame = CFrame.new(p + Vector3.new(0, h * k / 2, 0))
			part.Color = st.glow:Lerp(st.deep, a)
			part.Transparency = 0.05 + 0.9 * a * a
		end, 2)
		V.burstParticles(p, "flame", st, 6, 1.2, 1)
		V.mark(p, 1.8, Color3.fromRGB(26, 16, 12), 5)
	end
	local mid = d.a:Lerp(d.b, 0.5)
	V.flash(mid + Vector3.new(0, 3, 0), st.glow, 7, 0.2, 2)
	Audio.family(st, "impact", mid, 1.5)
	Audio.play("ultRelease", mid, 0.9, 0.8 + (d.i or 1) * 0.08)
	climax(mid, 0.35 + (d.i or 1) * 0.1, d)
end
function U.Fire.finish(d)
	local s = ults[key(d)]
	local st = s and s.st or Styles.of("Fire")
	V.burstParticles(groundAt(d.p), "dust", Styles.of("Ash"), 24, 3, 1)
	V.burstParticles(groundAt(d.p), "flame", st, 10, 2, 1)
	popGrade(key(d))
	ults[key(d)] = nil
end

-- ICE · Winter Cathedral -------------------------------------------------------------------------------------------------
U.Ice = {}
function U.Ice.begin(d)
	local st = Styles.of("Ice")
	local c = groundAt(d.p)
	local s = { spires = {} }
	ults[key(d)] = s
	pushGrade(key(d), Color3.fromRGB(215, 235, 255), -0.25, 0.03, 5, 0.6)
	-- snowfall over the cathedral
	local holder = V.part(Enum.PartType.Block, Enum.Material.SmoothPlastic, Color3.new(), Vector3.new(d.r * 2, 1, d.r * 2), CFrame.new(c + Vector3.new(0, 26, 0)), 1)
	local pe = Instance.new("ParticleEmitter")
	V.configure(pe, "frost", st, 1)
	pe.Shape = Enum.ParticleEmitterShape.Box
	pe.EmissionDirection = Enum.NormalId.Bottom
	pe.SpreadAngle = Vector2.new(10, 10)
	pe.Speed = NumberRange.new(4, 8)
	pe.Lifetime = NumberRange.new(3, 4)
	pe.Acceleration = Vector3.new(0, -2, 0)
	pe.Rate = 60 * Settings.density()
	pe.Parent = holder
	-- crystal spires crown the six pillars (exact pillar ring)
	local parts = { holder }
	for i = 0, 5 do
		local a = math.rad(i * 60)
		local base = groundAt(c + Vector3.new(math.cos(a), 0, math.sin(a)) * d.r) + Vector3.new(0, 10.5, 0)
		local sp = V.part(Enum.PartType.Wedge, Enum.Material.Glass, st.pale, Vector3.new(1.6, 0.2, 1.6), CFrame.new(base), 0.15)
		table.insert(parts, sp)
		table.insert(s.spires, { p = sp, base = base })
	end
	-- an aurora ribbon arcs over the zone
	local auroraA = c + Vector3.new(-d.r, 24, 0)
	local auroraB = c + Vector3.new(d.r, 24, 0)
	V.ribbon(auroraA, auroraB, 3, Color3.fromRGB(140, 255, 210), 5, { core = Color3.fromRGB(120, 200, 255), tr0 = 0.55, fade = false, prio = 1 })
	s.effect = V.effect({
		life = 5.5,
		parts = parts,
		prio = 3,
		update = function(e, a, dt, t)
			for i, sp in ipairs(s.spires) do
				local h = 6 * V.outCubic(math.min(1, t / 0.6 + i * 0.05))
				sp.p.Size = Vector3.new(1.6, math.max(0.2, h), 1.6)
				sp.p.CFrame = CFrame.new(sp.base + Vector3.new(0, h / 2, 0))
				if s.shatter then
					sp.p.Transparency = 1
				end
			end
			if a > 0.85 then
				pe.Rate = 0
			end
		end,
	})
	Audio.family(st, "release", c, 1.4)
	Audio.play("ultRelease", c, 0.9, 1.3)
end
function U.Ice.warn(d)
	local st = Styles.of("Ice")
	if d.open then
		return
	end
	local n = 6
	for i = 1, n - 1 do
		V.burstParticles(d.a:Lerp(d.b, i / n), "frost", st, 3, 0.8, 1)
	end
	Audio.play("ping", d.a:Lerp(d.b, 0.5), 0.8, 1.6)
end
function U.Ice.strike(d)
	local st = Styles.of("Ice")
	local n = math.floor(8 * Settings.density() + 0.5) + 3
	for i = 0, n do
		local p = groundAt(d.a:Lerp(d.b, i / n))
		local tilt = CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4))
		local h = rng:NextNumber(4, 7)
		-- ice lances spike up along the lane then shatter
		animPart(Enum.PartType.Wedge, Enum.Material.Glass, st.pale, Vector3.new(1, 0.2, 1.4), CFrame.new(p) * tilt, 0.1, 0.6, function(part, a)
			local k = a < 0.2 and V.outQuad(a / 0.2) or 1
			part.Size = Vector3.new(1, math.max(0.2, h * k), 1.4)
			part.CFrame = CFrame.new(p) * tilt * CFrame.new(0, h * k / 2, 0)
			part.Transparency = a > 0.75 and (a - 0.75) / 0.25 or 0.1
		end, 2)
	end
	local mid = d.a:Lerp(d.b, 0.5)
	task.delay(0.45, function()
		V.debris(mid + Vector3.new(0, 2, 0), 10, st.pale, { material = Enum.Material.Glass, shape = Enum.PartType.Wedge, size = 0.6, speed = 18, life = 1, tr = 0.2 })
		Audio.family(st, "impact", mid, 1.3)
	end)
	V.flash(mid + Vector3.new(0, 2, 0), st.pale, 5, 0.15, 2)
	climax(mid, 0.4, d)
end
function U.Ice.shatter(d)
	local s = ults[key(d)]
	if s then
		s.shatter = true
		for _, sp in ipairs(s.spires) do
			V.debris(sp.base + Vector3.new(0, 3, 0), 6, Styles.of("Ice").pale, { material = Enum.Material.Glass, shape = Enum.PartType.Wedge, size = 0.7, speed = 22, life = 1.2, tr = 0.2 })
		end
	end
	climax(groundAt(d.p), 0.8, d)
end
function U.Ice.finish(d)
	popGrade(key(d))
	task.delay(1.5, function()
		ults[key(d)] = nil
	end)
end

-- ELECTRIC · Heavens Circuit -----------------------------------------------------------------------------------------
U.Electric = {}
function U.Electric.begin(d)
	local st = Styles.of("Electric")
	local c = groundAt(d.p)
	pushGrade(key(d), Color3.fromRGB(220, 225, 255), -0.3, -0.06, 4.5, 0.4)
	-- storm clouds roil above the triangle
	local clouds = {}
	for i = 1, math.floor(8 * Settings.density()) + 3 do
		local p = c + Vector3.new(rng:NextNumber(-16, 16), rng:NextNumber(30, 36), rng:NextNumber(-16, 16))
		clouds[i] = V.part(Enum.PartType.Ball, Enum.Material.SmoothPlastic, Color3.fromRGB(46, 46, 66), Vector3.new(rng:NextNumber(10, 18), rng:NextNumber(5, 8), rng:NextNumber(10, 18)), CFrame.new(p), 0.25)
	end
	V.effect({
		life = 4.6,
		parts = clouds,
		prio = 2,
		update = function(e, a, dt, t)
			for i, cl in ipairs(clouds) do
				cl.Transparency = 0.25 + 0.75 * math.max(0, (a - 0.8) / 0.2)
				cl.CFrame = cl.CFrame * CFrame.new(math.sin(t + i) * dt * 2, 0, math.cos(t * 0.7 + i) * dt * 2)
			end
		end,
	})
	-- each rod is struck from the sky as it lands
	for i, rp in ipairs(d.rods or {}) do
		task.delay((i - 1) * 0.12, function()
			skyBolt(rp + Vector3.new(0, 3.5, 0), st.glow, 0.7)
			Audio.family(st, "impact", rp, 1.4)
		end)
	end
	climax(c, 0.4, d)
end
function U.Electric.surge(d)
	local st = Styles.of("Electric")
	V.ribbon(d.a, d.b, 0.45, st.glow, 0.18, { jitter = 1.2, segments = 9, core = Color3.new(1, 1, 1), prio = 2 })
	if rng:NextNumber() < 0.5 then
		local mid = d.a:Lerp(d.b, rng:NextNumber(0.3, 0.7))
		V.ribbon(mid, groundAt(mid + Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4))), 0.12, st.glow, 0.12, { jitter = 0.8, segments = 4, prio = 1 })
	end
	V.burstParticles(d.b, "spark", st, 10, 1, 1)
	Audio.family(st, "impact", d.a:Lerp(d.b, 0.5), 0.9)
end
function U.Electric.overload(d)
	local st = Styles.of("Electric")
	local c = groundAt(d.p)
	for _ = 1, 3 do
		task.delay(rng:NextNumber(0, 0.45), function()
			skyBolt(c + Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4)), st.glow, 0.9)
		end)
	end
	task.delay(0.5, function()
		climax(c, 0.8, d)
	end)
end
function U.Electric.finish(d)
	popGrade(key(d))
end

-- WATER · Tide of the Returning Sea ----------------------------------------------------------------------------------
U.Water = {}
local function wave(d, dur)
	local st = Styles.of("Water")
	local dir = Vector3.new(d.dir.X, 0, d.dir.Z).Unit
	local side = dir:Cross(Vector3.yAxis)
	local start = groundAt(d.p)
	local n = 7
	local parts = {}
	for i = 1, n do
		parts[i] = V.part(Enum.PartType.Ball, Enum.Material.Glass, st.pale, Vector3.new(d.w / n * 1.8, 6, 3.5), CFrame.new(start), 0.25)
	end
	local foam = V.part(Enum.PartType.Block, Enum.Material.SmoothPlastic, Color3.new(), Vector3.new(d.w, 1, 1), CFrame.new(start), 1)
	local pe = Instance.new("ParticleEmitter")
	V.configure(pe, "drip", st, 1.2)
	pe.Shape = Enum.ParticleEmitterShape.Box
	pe.Rate = 90 * Settings.density()
	pe.Parent = foam
	table.insert(parts, foam)
	V.effect({
		life = dur,
		parts = parts,
		prio = 3,
		update = function(e, a, dt, t)
			local front = start + dir * d.len * math.min(1, t / (dur * 0.95))
			for i, p in ipairs(parts) do
				if p ~= foam then
					local off = (i - (n + 1) / 2) / n * d.w
					local crest = 5 + math.sin(t * 9 + i) * 0.6
					p.Size = Vector3.new(d.w / n * 1.9, crest, 3.5)
					p.CFrame = CFrame.lookAt(front + side * off + Vector3.new(0, crest / 2 - 0.5, 0), front + side * off + dir + Vector3.new(0, crest / 2 - 0.5, 0)) * CFrame.Angles(-0.35, 0, 0)
				end
			end
			foam.CFrame = CFrame.lookAt(front + Vector3.new(0, 4.5, 0), front + Vector3.new(0, 4.5, 0) + dir)
		end,
	})
	Audio.family(st, "release", start, 1.5)
	Audio.play("ultRelease", start, 0.8, 1.2)
end
function U.Water.begin(d)
	pushGrade(key(d), Color3.fromRGB(205, 230, 255), -0.1, 0, 3.5, 0.4)
	wave(d, 1.25)
end
function U.Water.pause(d)
	local st = Styles.of("Water")
	-- the sea hangs, dripping, before it returns
	V.burstParticles(groundAt(d.p) + Vector3.new(0, 4, 0), "drip", st, 30, 2.2, 2)
	Audio.play("ultCharge", d.p, 0.7, 1.5)
end
U.Water["return"] = function(d)
	wave(d, 1.25)
	climax(d.p, 0.35, d)
end
function U.Water.finish(d)
	popGrade(key(d))
	V.mark(d.p, 6, Color3.fromRGB(40, 80, 110), 4, Enum.Material.Glass)
end

-- WIND · Eye of the Gale -------------------------------------------------------------------------------------------------
U.Wind = {}
function U.Wind.begin(d)
	local st = Styles.of("Wind")
	local c = groundAt(d.p)
	local s = { c = c, r = d.r }
	ults[key(d)] = s
	-- a rotating wall of wind at the exact ring: stacked spinning dashed rings
	for i = 0, 4 do
		V.ring(c, d.r, d.r, st.pale, 6.2, { width = 0.18, dashed = true, spin = (i % 2 == 0 and 1 or -1) * (1.5 + i * 0.3), y = 1 + i * 2.2, tr0 = 0.4 + i * 0.08, tr1 = 0.4 + i * 0.08, hold = 0.95, prio = 2 })
	end
	-- debris orbiting inside the eye
	orbiters(function()
		return c + Vector3.new(0, 3, 0)
	end, math.floor(10 * Settings.density()) + 3, d.r * 0.8, Color3.fromRGB(110, 150, 90), Enum.Material.Grass, 6.2, 0.4, 4)
	Audio.family(st, "release", c, 1.4)
end
function U.Wind.rev(d)
	local st = Styles.of("Wind")
	local s = ults[key(d)]
	if not s then
		return
	end
	V.burstParticles(s.c + Vector3.new(0, 2, 0), "streak", st, 20, 2.4, 1)
	Audio.play("dash", s.c, 1.2, 0.7)
	if (d.rev or 1) >= 3 and d.unstable then
		climax(s.c, 0.5, d)
	end
end
function U.Wind.finish(d)
	local s = ults[key(d)]
	if s then
		V.ring(s.c, s.r, s.r * 1.6, Styles.of("Wind").pale, 0.5, { width = 0.3, tr0 = 0.2, prio = 2 })
	end
	ults[key(d)] = nil
end

-- EARTH · Continental Verdict ---------------------------------------------------------------------------------------
U.Earth = {}
function U.Earth.begin(d)
	local st = Styles.of("Earth")
	local c = groundAt(d.p)
	ults[key(d)] = { c = c }
	-- fault lines crack outward across the zone
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local len = d.r * rng:NextNumber(0.7, 1)
		local mid = c + Vector3.new(math.cos(a), 0, math.sin(a)) * len / 2
		animPart(Enum.PartType.Block, Enum.Material.Slate, Color3.fromRGB(30, 24, 20), Vector3.new(0.5, 0.08, 0.1), CFrame.lookAt(mid, mid + Vector3.new(math.cos(a), 0, math.sin(a))) + Vector3.new(0, 0.04, 0), 0, 5, function(p, al, t)
			local k = V.outQuad(math.min(1, t / 0.5))
			p.Size = Vector3.new(0.5, 0.08, math.max(0.1, len * k))
		end, 1)
	end
	V.burstParticles(c, "dust", st, 14, 2.5, 1)
	climax(c, 0.25, d)
end
function U.Earth.warn(d)
	local st = Styles.of("Earth")
	local s = ults[key(d)]
	if not s then
		return
	end
	local a = math.rad((d.a0 or 0) + 45)
	local mid = s.c + Vector3.new(math.cos(a), 0, math.sin(a)) * d.r * 0.4
	V.burstParticles(mid, "dust", st, 8, 1.4, 1)
	Audio.play("land", mid, 1.2, 0.5)
	V.shake(mid, 0.12, isMine(d))
end
function U.Earth.rise(d)
	local st = Styles.of("Earth")
	local s = ults[key(d)]
	if not s then
		return
	end
	local a = math.rad((d.a0 or 0) + 45)
	local mid = s.c + Vector3.new(math.cos(a), 0, math.sin(a)) * d.r * 0.4
	V.debris(mid + Vector3.new(0, 1, 0), 10, st.color, { size = 1.1, speed = 26, life = 1.3 })
	V.burstParticles(mid, "dust", st, 18, 2.2, 2)
	V.ring(mid, 1, 9, st.deep, 0.5, { width = 0.8, tr0 = 0.2, material = Enum.Material.Slate, prio = 2 })
	Audio.family(st, "impact", mid, 1.5)
	climax(mid, 0.4 + (d.q or 0) * 0.08, d)
end
function U.Earth.drop(d)
	local s = ults[key(d)]
	if s then
		task.delay(0.6, function()
			V.debris(s.c + Vector3.new(0, 2, 0), 16, Styles.of("Earth").color, { size = 1.3, speed = 30, life = 1.4 })
			climax(s.c, 0.9, d)
		end)
	end
end
function U.Earth.finish(d)
	task.delay(1.5, function()
		ults[key(d)] = nil
	end)
end

-- LIGHT · Day Without Shadow -----------------------------------------------------------------------------------------
U.Light = {}
function U.Light.begin(d)
	local st = Styles.of("Light")
	local c = groundAt(d.p)
	local dur = d.d or 6
	local s = {}
	ults[key(d)] = s
	pushGrade(key(d), Color3.fromRGB(255, 248, 225), 0.1, 0.08, dur, 0.5)
	local sun = V.part(Enum.PartType.Ball, Enum.Material.Neon, Color3.new(1, 0.97, 0.85), Vector3.one * 2, CFrame.new(c + Vector3.new(0, 18, 0)), 0)
	V.light(sun, st.glow, 4, 60)
	local corona = V.part(Enum.PartType.Ball, Enum.Material.ForceField, st.glow, Vector3.one * 8, CFrame.new(c + Vector3.new(0, 18, 0)), 0.1)
	s.sun = sun
	V.effect({
		life = dur + 0.3,
		parts = { sun, corona },
		prio = 3,
		update = function(e, a, dt, t)
			local k = V.outCubic(math.min(1, t / 0.8)) * (a > 0.92 and (1 - (a - 0.92) / 0.08) or 1)
			sun.Size = Vector3.one * (6 * k + 0.1)
			corona.Size = Vector3.one * (13 * k + 0.2 + math.sin(t * 3) * 0.6)
			if s.flare then
				sun.Size *= 1.6
			end
		end,
	})
	V.ring(c + Vector3.new(0, 18, 0), 9, 9, st.glow, dur, { width = 0.2, rot = CFrame.Angles(math.rad(90), 0, 0), y = 0, spin = 1, tr0 = 0.3, tr1 = 0.3, hold = 0.97, prio = 2 })
	-- god rays fall around the disc edge
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		local base = c + Vector3.new(math.cos(a), 0, math.sin(a)) * d.r
		V.ribbon(c + Vector3.new(0, 18, 0), base, 0.6, st.glow, dur, { core = Color3.new(1, 1, 0.9), tr0 = 0.75, fade = false, glow = false, prio = 1 })
	end
	V.flash(c + Vector3.new(0, 10, 0), st.glow, 9, 0.3, 3)
	Audio.family(st, "release", c, 1.4)
	Audio.play("ultRelease", c, 0.9, 1.5)
end
function U.Light.flare(d)
	local s = ults[key(d)]
	if s then
		s.flare = true
	end
	local st = Styles.of("Light")
	task.delay(0.5, function()
		V.flash(groundAt(d.p) + Vector3.new(0, 4, 0), st.glow, 16, 0.35, 3)
		climax(d.p, 0.7, d)
	end)
end
function U.Light.finish(d)
	popGrade(key(d))
	task.delay(1, function()
		ults[key(d)] = nil
	end)
end

-- Ultimate buildup (windup) shared by all showcase powers: escalating aura + ground sigil + grade -------------------
local function ultBuildup(d, st, model)
	local root = rootOf(model)
	if not root then
		return
	end
	local w = math.max(0.3, d.w or 1)
	local feet = function()
		return root.Parent and (root.Position - Vector3.new(0, 2.95, 0)) or nil
	end
	V.ring(feet(), 8, 4.5, st.glow, w + 0.25, { width = 0.35, dashed = true, spin = 2.5, tr0 = 0.1, tr1 = 0.1, hold = 0.95, follow = feet, prio = 3 })
	V.ring(feet(), 2.5, 6.5, st.color, w + 0.25, { width = 0.2, spin = -3, tr0 = 0.3, tr1 = 0.3, hold = 0.95, follow = feet, prio = 2 })
	-- rising column of the element around the caster
	local holder = V.part(Enum.PartType.Cylinder, Enum.Material.SmoothPlastic, Color3.new(), Vector3.new(0.2, 7, 7), CFrame.new(feet()) * CFrame.Angles(0, 0, math.rad(90)), 1)
	local pe = Instance.new("ParticleEmitter")
	V.configure(pe, st.particle, st, 1.1)
	pe.Shape = Enum.ParticleEmitterShape.Disc
	pe.EmissionDirection = Enum.NormalId.Right
	pe.SpreadAngle = Vector2.new(8, 8)
	pe.Rate = 70 * Settings.density()
	pe.Parent = holder
	V.effect({
		life = w + 0.3,
		parts = { holder },
		prio = 3,
		update = function(e, a)
			local f = feet()
			if f then
				holder.CFrame = CFrame.new(f) * CFrame.Angles(0, 0, math.rad(90))
			end
			pe.Rate = 70 * Settings.density() * (0.4 + a)
		end,
	})
	if d.k ~= "Gravity" then
		pushGrade(key(d) .. "b", st.pale, -0.12, -0.02, w + 0.2, w * 0.8)
	else
		pushGrade(key(d) .. "b", Color3.fromRGB(210, 195, 255), -0.3, -0.04, w + 0.2, w * 0.9)
	end
	task.delay(w + 0.2, function()
		popGrade(key(d) .. "b")
	end)
	Audio.play("ultCharge", root.Position)
	if isMine(d) then
		ctx.Camera.fov(-8, w + 0.3)
	end
end

-- Hooks ------------------------------------------------------------------------------------------------------------------------
function Showcase.cast(d, st)
	local motif = M[d.k]
	if not motif or not d.a or not d.a.Parent then
		return false
	end
	local hand = V.Poses.handFor(d.slot)
	if d.ult then
		ultBuildup(d, st, d.a)
	end
	if (d.w or 0) < 0.05 and not d.ult then
		return true
	end
	local ok, handled = pcall(motif.cast, d, st, d.a, hand, d.w or 0)
	if not ok then
		warn("[EB showcase] cast " .. tostring(d.k) .. ": " .. tostring(handled))
		return false
	end
	return handled ~= false
end

function Showcase.release(d, st, hp)
	local motif = M[d.k]
	if not motif then
		return false
	end
	local ok, handled = pcall(motif.release, d, st, hp, d.a)
	if not ok then
		warn("[EB showcase] release " .. tostring(d.k) .. ": " .. tostring(handled))
		return false
	end
	if d.ult and handled then
		local root = rootOf(d.a)
		if root then
			V.ring(root.Position - Vector3.new(0, 2.8, 0), 1, 12, st.glow, 0.5, { width = 0.6, tr0 = 0, prio = 3 })
		end
		if isMine(d) then
			ctx.Camera.fov(9, 0.35)
		end
	end
	return handled ~= false
end

function Showcase.phase(d)
	local u = U[d.k]
	local fn = u and u[d.phase]
	if fn then
		local ok, err = pcall(fn, d)
		if not ok then
			warn("[EB showcase] " .. tostring(d.k) .. "." .. tostring(d.phase) .. ": " .. tostring(err))
		end
	end
end

function Showcase.active()
	local n = 0
	for _ in pairs(ults) do
		n += 1
	end
	return n
end

function Showcase.init(c)
	ctx = c
	Settings = c.Settings
	Audio = c.Audio
	game:GetService("RunService").RenderStepped:Connect(stepGrade)
end

return Showcase
