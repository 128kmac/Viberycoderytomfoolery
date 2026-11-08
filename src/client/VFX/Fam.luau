-- Family renderers: how each element family looks and moves. Every function takes a resolved style
-- (Shared/Styles) so all 100 powers get distinct shape / motion / material / particles / light / sound
-- language by family, tinted by their own colours. Showcase powers layer bespoke choreography on top
-- (VFX/Showcase) through the hooks at the bottom of this file.
local V = require(script.Parent)

local Fam = {}
local ctx, Settings, Audio
local rng = V.rng
local Styles = V.Styles
local Poses = V.Poses

local function scaleFor(amount)
	return math.clamp((amount or 60) / 90, 0.45, 2.2)
end

local function rootOf(model)
	return model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
end

-- Impacts --------------------------------------------------------------------------------------------
-- pos, style, scale (1 = normal hit), normal (surface normal for terrain hits), what ("body"|"terrain"|"aoe")
function Fam.impact(pos, st, s, normal, what)
	s = s or 1
	local imp = st.impact
	local col, glow, deep = st.color, st.glow, st.deep
	if imp == "blast" then
		V.flash(pos, glow, 3 * s, 0.16)
		V.ball(pos, 0.6 * s, 3.2 * s, glow, 0.35, { tr0 = 0.05, material = Enum.Material.Neon })
		V.ball(pos, 1 * s, 4 * s, deep, 0.6, { tr0 = 0.45, material = Enum.Material.SmoothPlastic })
		V.burstParticles(pos, "flame", st, 18 * s, s)
		V.burstParticles(pos, "spark", st, 10 * s, s * 0.8)
		V.burstParticles(pos, "dust", Styles.of("Ash"), 6 * s, s)
		if what ~= "body" then
			V.mark(pos, 2.4 * s, Color3.fromRGB(25, 18, 14), 4)
		end
	elseif imp == "shatter" then
		V.flash(pos, st.pale, 2 * s, 0.12)
		V.debris(pos, 7 * s, st.pale, { material = Enum.Material.Glass, shape = Enum.PartType.Wedge, size = 0.7 * s, speed = 24, normal = normal, life = 1.1, tr = 0.15 })
		V.ring(pos - Vector3.new(0, 1.5, 0), 0.5, 4 * s, Color3.new(1, 1, 1):Lerp(col, 0.3), 0.4, { width = 0.25, tr0 = 0.1 })
		V.burstParticles(pos, "frost", st, 16 * s, s)
		if what ~= "body" then
			V.mark(pos, 2.2 * s, st.pale, 3.5, Enum.Material.Ice)
		end
	elseif imp == "arc" then
		V.flash(pos, glow, 3.2 * s, 0.1)
		for _ = 1, math.max(2, math.floor(4 * s)) do
			local d = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.4, 1), rng:NextNumber(-1, 1)).Unit
			V.ribbon(pos, pos + d * rng:NextNumber(2.5, 5) * s, 0.18, glow, 0.16, { jitter = 0.6 * s, segments = 4, core = Color3.new(1, 1, 1) })
		end
		V.burstParticles(pos, "spark", st, 22 * s, s)
		V.ring(pos - Vector3.new(0, 1.2, 0), 0.3, 3.2 * s, glow, 0.22, { width = 0.15, tr0 = 0.1 })
	elseif imp == "splash" then
		V.ball(pos, 0.8 * s, 2.6 * s, st.pale, 0.3, { tr0 = 0.35, material = Enum.Material.Glass })
		V.burstParticles(pos, "drip", st, 20 * s, s)
		local g = pos - Vector3.new(0, 1.8, 0)
		V.ring(g, 0.5, 3.5 * s, st.pale, 0.55, { width = 0.22, tr0 = 0.2 })
		task.delay(0.12, function()
			V.ring(g, 0.3, 2.4 * s, col, 0.5, { width = 0.18, tr0 = 0.3 })
		end)
		if what ~= "body" then
			V.mark(pos, 2 * s, deep, 3, Enum.Material.Glass)
		end
	elseif imp == "gust" then
		local tilt = CFrame.Angles(rng:NextNumber(-0.3, 0.3), 0, rng:NextNumber(-0.3, 0.3))
		V.ring(pos, 0.5, 4.5 * s, st.pale, 0.3, { width = 0.18, tr0 = 0.2, rot = tilt, y = 0 })
		V.ring(pos, 0.3, 3 * s, Color3.new(1, 1, 1), 0.25, { width = 0.12, tr0 = 0.35, rot = tilt * CFrame.Angles(0.4, 0, 0), y = 0.4 })
		V.burstParticles(pos, "streak", st, 16 * s, s)
		V.burstParticles(pos, "dust", Styles.of("Sand"), 4 * s, s * 0.6)
	elseif imp == "quake" then
		V.debris(pos, 8 * s, col:Lerp(Color3.fromRGB(110, 100, 90), 0.4), { size = 0.9 * s, speed = 26, normal = normal or Vector3.yAxis, material = st.material })
		V.burstParticles(pos, "dust", st, 12 * s, s * 1.2)
		V.ring(pos - Vector3.new(0, 1.2, 0), 0.5, 4 * s, deep, 0.4, { width = 0.5, tr0 = 0.3, material = Enum.Material.Slate })
		if what ~= "body" then
			V.mark(pos, 2.6 * s, Color3.fromRGB(40, 34, 30), 4.5, Enum.Material.Slate)
		end
	elseif imp == "implode" then
		V.ball(pos, 2.6 * s, 0.2, glow, 0.22, { tr0 = 0.4, material = Enum.Material.ForceField, ease = V.inQuad })
		V.burstParticles(pos, "mote", st, 18 * s, s * 1.4)
		task.delay(0.2, function()
			V.flash(pos, glow, 2.6 * s, 0.14)
			V.ring(pos - Vector3.new(0, 1, 0), 0.4, 4 * s, deep:Lerp(glow, 0.4), 0.35, { width = 0.3, tr0 = 0.15 })
		end)
	elseif imp == "flare" then
		V.flash(pos, glow, 3.6 * s, 0.18)
		local pillar = V.part(Enum.PartType.Cylinder, Enum.Material.Neon, glow, Vector3.new(8 * s, 0.6 * s, 0.6 * s), CFrame.new(pos + Vector3.new(0, 3 * s, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.2)
		V.effect({
			life = 0.3,
			parts = { pillar },
			update = function(e, a)
				pillar.Transparency = 0.2 + 0.8 * a
				pillar.Size = Vector3.new(8 * s * (1 + a), 0.6 * s * (1 - a * 0.7), 0.6 * s * (1 - a * 0.7))
			end,
		})
		V.burstParticles(pos, "glint", st, 16 * s, s)
		V.ring(pos - Vector3.new(0, 1.2, 0), 0.4, 3.4 * s, glow, 0.35, { width = 0.2, tr0 = 0.1 })
	elseif imp == "bloom" then
		for i = 1, 6 do
			local ang = i / 6 * math.pi * 2
			local petal = V.part(Enum.PartType.Ball, Enum.Material.SmoothPlastic, st.glow, Vector3.new(0.3, 0.8 * s, 1.6 * s), CFrame.new(pos), 0.1)
			V.effect({
				life = 0.5,
				parts = { petal },
				update = function(e, a)
					local r = 2.4 * s * V.outQuad(a)
					petal.CFrame = CFrame.new(pos + Vector3.new(math.cos(ang) * r, 0.4 - a, math.sin(ang) * r)) * CFrame.Angles(0, -ang, 0.6 + a)
					petal.Transparency = 0.1 + 0.9 * a
				end,
			})
		end
		V.burstParticles(pos, "leaf", st, 14 * s, s)
		V.ring(pos - Vector3.new(0, 1.2, 0), 0.4, 3 * s, col, 0.4, { width = 0.25, tr0 = 0.2 })
	else -- glyph
		V.ring(pos - Vector3.new(0, 1, 0), 2.6 * s, 2.2 * s, glow, 0.45, { width = 0.22, dashed = true, spin = 4, tr0 = 0.05 })
		local dia = V.part(Enum.PartType.Block, Enum.Material.Neon, glow, Vector3.new(2 * s, 0.1, 2 * s), CFrame.new(pos), 0.2)
		V.effect({
			life = 0.4,
			parts = { dia },
			update = function(e, a)
				dia.CFrame = CFrame.new(pos) * CFrame.Angles(math.pi / 2, a * 3, math.pi / 4)
				dia.Size = Vector3.new(2 * s * (1 - a * 0.5), 0.1, 2 * s * (1 - a * 0.5))
				dia.Transparency = 0.2 + 0.8 * a
			end,
		})
		V.burstParticles(pos, "wisp", st, 10 * s, s)
	end
end

-- AoE detonation (server FX.burst): the family impact scaled to the real radius + an exact-radius ring
function Fam.burst(pos, r, st, dur, color)
	local s = math.clamp(r / 4, 0.5, 3)
	Fam.impact(pos, st, s, Vector3.yAxis, "aoe")
	V.ring(pos - Vector3.new(0, 0.85, 0), r * 0.3, r, color or st.glow, math.max(0.25, dur or 0.35), { width = math.clamp(r * 0.06, 0.25, 0.8), tr0 = 0.05 })
	Audio.family(st, "impact", pos, math.clamp(s, 0.6, 1.4))
	V.shake(pos, 0.25 * s * st.shake)
end

function Fam.sphere(pos, r, st, dur, color, tr, id)
	local mat = (st.family == "frost" or st.family == "tide") and Enum.Material.Glass or ((st.family == "gale" or st.family == "gravity") and Enum.Material.ForceField or Enum.Material.Neon)
	local e = V.ball(pos, r * 0.92, r, color or st.color, dur or 0.4, { tr0 = math.max(tr or 0.45, mat == Enum.Material.Neon and 0.6 or 0.2), tr1 = 1, material = mat, id = id })
	if e then
		e.move = function(p)
			pos = p
			for _, part in ipairs(e.parts) do
				part.CFrame = CFrame.new(p)
			end
		end
	end
	V.burstParticles(pos, st.particle, st, math.clamp(r * 2, 4, 20), math.clamp(r / 3, 0.5, 2))
end

function Fam.disc(pos, r, st, dur, color)
	local res = workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -10, 0), V.worldParams)
	local g = res and res.Position or pos
	local p = V.part(Enum.PartType.Cylinder, Enum.Material.Neon, color or st.color, Vector3.new(0.08, r * 2, r * 2), CFrame.new(g + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.6)
	V.effect({
		life = dur or 0.6,
		parts = { p },
		update = function(e, a)
			p.Transparency = 0.6 + 0.4 * a
		end,
	})
	V.ring(g, r, r, color or st.glow, dur or 0.6, { width = 0.25, tr0 = 0.2, hold = 0.5 })
end

-- Beams: per-family look over the exact hit line ----------------------------------------------------
function Fam.beam(a, b, w, st, dur, color, id)
	dur = dur or 0.2
	local col = color or st.color
	local fam = st.family
	local len = (b - a).Magnitude
	local e
	if fam == "storm" then
		e = V.ribbon(a, b, math.max(0.2, w * 0.5), st.glow, dur + 0.05, { jitter = math.clamp(len / 18, 0.4, 1.6), segments = math.clamp(math.floor(len / 4), 3, 12), core = Color3.new(1, 1, 1) })
		V.ribbon(a, b, math.max(0.1, w * 0.25), st.glow, dur, { jitter = math.clamp(len / 14, 0.5, 2), segments = math.clamp(math.floor(len / 5), 3, 10), glow = false })
		V.burstParticles(b, "spark", st, 12, 0.8)
		V.flash(b, st.glow, 1.6, 0.1)
	elseif fam == "radiant" then
		e = V.ribbon(a, b, math.max(0.35, w), st.glow, dur + 0.1, { core = Color3.new(1, 1, 0.95), taper = true })
		V.burstParticles(b, "glint", st, 10, 0.8)
		V.flash(b, st.glow, 2, 0.14)
		V.flash(a, st.glow, 1.2, 0.1)
	elseif fam == "flame" then
		e = V.ribbon(a, b, math.max(0.4, w), st.glow, dur + 0.1, { core = Color3.new(1, 0.95, 0.7), taper = true })
		local n = math.clamp(math.floor(len / 6), 1, 6)
		for i = 1, n do
			V.burstParticles(a:Lerp(b, i / n), "flame", st, 5, 0.8)
		end
	elseif fam == "frost" then
		e = V.ribbon(a, b, math.max(0.3, w * 0.8), st.pale, dur + 0.1, { core = Color3.new(1, 1, 1) })
		V.debris(b, 4, st.pale, { material = Enum.Material.Glass, shape = Enum.PartType.Wedge, size = 0.5, speed = 16, life = 0.8, tr = 0.2 })
		V.burstParticles(b, "frost", st, 10, 0.8)
	elseif fam == "tide" then
		e = V.ribbon(a, b, math.max(0.4, w), st.pale, dur + 0.15, { core = col, taper = false })
		V.burstParticles(b, "drip", st, 12, 0.8)
	elseif fam == "gravity" then
		e = V.ribbon(a, b, math.max(0.35, w), st.glow, dur + 0.1, { core = st.deep })
		local n = math.clamp(math.floor(len / 8), 1, 5)
		for i = 1, n do
			local p = a:Lerp(b, i / (n + 1))
			V.ball(p, 1.2, 0.2, st.glow, 0.3, { tr0 = 0.5, material = Enum.Material.ForceField, ease = V.inQuad })
		end
		V.burstParticles(b, "mote", st, 10, 1)
	elseif fam == "verdant" then
		e = V.ribbon(a, b, math.max(0.25, w * 0.7), st.color, dur + 0.15, { core = st.deep, glow = false, lightEmission = 0.2 })
		V.burstParticles(b, "leaf", st, 8, 0.8)
	elseif fam == "gale" then
		e = V.ribbon(a, b, math.max(0.3, w), st.pale, dur + 0.1, { core = Color3.new(1, 1, 1), tr0 = 0.3, taper = true })
		V.burstParticles(b, "streak", st, 10, 0.8)
	elseif fam == "stone" then
		e = V.ribbon(a, b, math.max(0.3, w), col, dur + 0.05, { core = st.pale, glow = false, lightEmission = 0.1 })
		V.burstParticles(b, "dust", st, 6, 0.8)
	else
		e = V.ribbon(a, b, math.max(0.3, w), st.glow, dur + 0.1, { core = st.pale })
		V.burstParticles(b, "wisp", st, 8, 0.8)
	end
	if e then
		e.id = id
		if id then
			V.byId[id] = e
		end
	end
end

-- cone sweep: ribbons fan across the real angle, particles along the edge
function Fam.cone(pos, dir, l, angle, st, dur, color)
	dur = dur or 0.3
	local n = math.clamp(math.floor(angle / 12), 3, 12)
	local base = Vector3.new(dir.X, 0, dir.Z).Unit
	local col = color or st.glow
	for i = 0, n do
		local ang = math.rad(-angle / 2 + angle * i / n)
		local d = CFrame.Angles(0, ang, 0):VectorToWorldSpace(base)
		local delay = i / n * dur * 0.4
		task.delay(delay, function()
			V.ribbon(pos, pos + d * l, 0.3, col, dur * 0.8, { core = st.pale, taper = true, glow = i % 2 == 0, jitter = st.family == "storm" and 0.5 or nil, segments = 4 })
			if i % 2 == 0 then
				V.burstParticles(pos + d * l * 0.85, st.particle, st, 4, 0.7)
			end
		end)
	end
end

-- Projectiles -----------------------------------------------------------------------------------------
local loops = 0
local function addTrail(part, st, width, life)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, width / 2, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -width / 2, 0)
	a1.Parent = part
	local tr = Instance.new("Trail")
	tr.Attachment0 = a0
	tr.Attachment1 = a1
	tr.FaceCamera = true
	tr.Lifetime = life or st.trail
	tr.LightEmission = st.light > 0 and 1 or 0.2
	tr.LightInfluence = 0
	tr.Color = ColorSequence.new(st.glow, st.color)
	tr.Transparency = NumberSequence.new(0.25, 1)
	tr.WidthScale = NumberSequence.new(1, 0.1)
	tr.Parent = part
	return tr
end

function Fam.projectileBody(pr)
	local st = pr.style
	local r = math.max(0.3, pr.r)
	local col = pr.color or st.color
	local glow = pr.color and pr.color:Lerp(Color3.new(1, 1, 1), 0.35) or st.glow
	local shape = st.shape
	local cf = CFrame.new(pr.pos)
	local parts = pr.parts
	local core
	if pr.size or pr.shape == "Block" then
		-- kit-specified body (e.g. Earth chunks, arrows): honour size, dress by family
		local size = pr.size or Vector3.new(r * 2, r * 2, r * 4)
		core = V.part(pr.shape == "Block" and Enum.PartType.Block or Enum.PartType.Ball, shape == "chunk" and st.material or Enum.Material.Neon, col, size, cf, 0)
		if st.family == "stone" then
			core.Material = st.material
		end
		table.insert(parts, core)
	elseif shape == "shard" then
		core = V.part(Enum.PartType.Wedge, Enum.Material.Glass, st.pale, Vector3.new(r * 1.2, r * 1.2, r * 4), cf, 0.1)
		table.insert(parts, core)
	elseif shape == "drop" then
		core = V.part(Enum.PartType.Ball, Enum.Material.Glass, col, Vector3.new(r * 1.8, r * 1.8, r * 2.6), cf, 0.15)
		table.insert(parts, core)
	elseif shape == "crescent" then
		core = V.part(Enum.PartType.Ball, Enum.Material.ForceField, st.pale, Vector3.new(r * 4, r * 0.5, r * 1.6), cf, 0.05)
		table.insert(parts, core)
	elseif shape == "chunk" then
		core = V.part(Enum.PartType.Block, st.material, col, Vector3.new(r * 2, r * 1.7, r * 2.2), cf, 0)
		table.insert(parts, core)
	elseif shape == "ray" then
		core = V.part(Enum.PartType.Block, Enum.Material.Neon, glow, Vector3.new(r * 0.8, r * 0.8, r * 6), cf, 0)
		table.insert(parts, core)
	elseif shape == "rune" then
		core = V.part(Enum.PartType.Block, Enum.Material.Neon, glow, Vector3.new(r * 2.2, r * 2.2, 0.15), cf, 0.1)
		table.insert(parts, core)
	elseif shape == "seed" then
		core = V.part(Enum.PartType.Ball, Enum.Material.SmoothPlastic, col, Vector3.one * r * 1.8, cf, 0)
		table.insert(parts, core)
	else -- orb, bolt, well
		core = V.part(Enum.PartType.Ball, shape == "well" and Enum.Material.SmoothPlastic or Enum.Material.Neon, shape == "well" and st.deep or glow, Vector3.one * r * (shape == "bolt" and 1.2 or 2), cf, 0)
		table.insert(parts, core)
	end
	-- outer shell for glowing families
	local shell
	if shape == "orb" or shape == "well" or shape == "bolt" then
		shell = V.part(Enum.PartType.Ball, shape == "well" and Enum.Material.ForceField or Enum.Material.Neon, shape == "well" and glow or col, Vector3.one * r * 3.2, cf, shape == "well" and 0.1 or 0.65)
		table.insert(parts, shell)
	end
	-- seed: orbiting leaves
	local orbit = {}
	if shape == "seed" then
		for i = 1, 3 do
			local leaf = V.part(Enum.PartType.Block, Enum.Material.SmoothPlastic, st.glow, Vector3.new(r * 0.3, r * 0.08, r * 1.1), cf, 0)
			orbit[i] = leaf
			table.insert(parts, leaf)
		end
	end
	if Settings.get("Quality") >= 2 or shape ~= "chunk" then
		addTrail(core, st, math.max(0.4, r * 1.6), st.trail)
	end
	V.emitter(core, st.particle, st, shape == "bolt" and 40 or 22, math.clamp(r * 1.2, 0.5, 1.6))
	if st.light > 0 then
		V.light(core, glow, 1.5 * st.light, math.clamp(r * 10, 8, 18))
	end
	-- bolt tail: crackling ribbons trailing behind the head
	local tail
	if shape == "bolt" then
		tail = {}
		for i = 1, 2 do
			local holder = V.part(Enum.PartType.Block, Enum.Material.SmoothPlastic, Color3.new(), Vector3.one * 0.1, cf, 1)
			table.insert(parts, holder)
			local ats = {}
			for j = 0, 4 do
				local at = Instance.new("Attachment")
				at.Parent = holder
				ats[j] = at
			end
			for j = 1, 4 do
				local bm = Instance.new("Beam")
				bm.Attachment0 = ats[j - 1]
				bm.Attachment1 = ats[j]
				bm.FaceCamera = true
				bm.Width0 = 0.18 * (5 - j) / 4
				bm.Width1 = 0.18 * (4 - j) / 4
				bm.LightEmission = 1
				bm.LightInfluence = 0
				bm.Color = ColorSequence.new(i == 1 and Color3.new(1, 1, 1) or glow)
				bm.Transparency = NumberSequence.new(0.1)
				bm.Parent = holder
			end
			tail[i] = ats
		end
	end
	-- travel sound for nearby / own projectiles (capped)
	local snd
	local cam = workspace.CurrentCamera
	if loops < 6 and (pr.owner == V.myId() or (cam.CFrame.Position - pr.pos).Magnitude < 70) then
		snd = Audio.loop(st, core, 0.8)
		if snd then
			loops += 1
		end
	end
	local spin = 0
	local flick = 0
	pr.render = function(p, pos, dt)
		local v = p.vel
		local look = v.Magnitude > 0.05 and CFrame.lookAt(pos, pos + v) or CFrame.new(pos)
		spin += dt
		local m = st.motion
		local c = look
		if shape == "shard" or shape == "rune" then
			c = look * CFrame.Angles(0, 0, spin * 12)
		elseif shape == "chunk" then
			c = look * CFrame.Angles(spin * 7, spin * 4, 0)
		elseif shape == "drop" then
			local k = 1 + 0.12 * math.sin(spin * 22)
			core.Size = Vector3.new(r * 1.8 / k, r * 1.8 * k, r * 2.6)
		elseif shape == "crescent" then
			c = look * CFrame.Angles(0, 0, math.sin(spin * 6) * 0.25)
		end
		if m == "flicker" and shell then
			shell.Size = Vector3.one * r * (3 + 0.5 * math.sin(spin * 30) + rng:NextNumber(-0.2, 0.2))
		elseif m == "orbit" and shell then
			shell.Size = Vector3.one * r * (3.2 + 0.8 * math.sin(spin * 9))
		end
		core.CFrame = c
		if shell then
			shell.CFrame = look
		end
		for i, leaf in ipairs(orbit) do
			local ang = spin * 8 + i * 2.1
			leaf.CFrame = look * CFrame.new(math.cos(ang) * r * 1.4, math.sin(ang) * r * 1.4, 0) * CFrame.Angles(0, 0, ang)
		end
		if tail then
			flick += dt
			if flick > 0.04 then
				flick = 0
				local back = v.Magnitude > 0.05 and -v.Unit or Vector3.new(0, 0, 1)
				local side = back:Cross(Vector3.yAxis)
				if side.Magnitude < 1e-3 then
					side = Vector3.xAxis
				end
				side = side.Unit
				for _, ats in ipairs(tail) do
					for j = 0, 4 do
						local off = j == 0 and Vector3.zero or (side * rng:NextNumber(-0.5, 0.5) + Vector3.yAxis * rng:NextNumber(-0.5, 0.5)) * j * 0.4
						ats[j].WorldPosition = pos + back * j * 1.4 + off
					end
				end
			end
		end
	end
	pr.cleanup = function()
		if snd then
			snd:Destroy()
			loops -= 1
		end
	end
end

function Fam.projectileEnd(pr, pos, why)
	local st = pr.style
	local s = math.clamp(pr.r / 0.6, 0.5, 2)
	if why == "hit" then
		V.burstParticles(pos, st.particle, st, 8 * s, s * 0.8)
		return
	end
	if why == "wall" or why == "intercepted" or why == "gap" then
		local dir = pr.vel.Magnitude > 0.1 and pr.vel.Unit or Vector3.new(0, -1, 0)
		local res = workspace:Raycast(pos - dir * 2, dir * 4, V.worldParams)
		local normal = res and res.Normal or -dir
		Fam.impact(pos, st, 0.7 * s, normal, "terrain")
		Audio.family(st, "impact", pos, 0.7)
		return
	end
	-- fizzle at max range: shrink and puff, no impact flash (reads as a miss)
	V.ball(pos, pr.r * 1.6, 0.05, st.glow, 0.22, { tr0 = 0.3, ease = V.inQuad })
	V.burstParticles(pos, st.particle, st, 5 * s, s * 0.6)
end

-- Hits (server "hit" cue): layered by result category --------------------------------------------------
function Fam.hit(d)
	local model = d.t
	local root = rootOf(model)
	local pos = root and root.Position or d.p
	local st = Styles.of(d.k)
	local cat = d.cat
	local amt = d.amt or 0
	local me = V.myModel()
	local mine = d.o and d.o == V.myId()
	local victimIsMe = me ~= nil and model == me
	local fromDir = d.from and (pos - d.from) or (root and -root.CFrame.LookVector) or Vector3.zAxis
	fromDir = Vector3.new(fromDir.X, 0, fromDir.Z)
	fromDir = fromDir.Magnitude > 0.01 and fromDir.Unit or Vector3.zAxis
	local s = scaleFor(amt) * (d.ult and 1.35 or 1)
	local facePos = pos - fromDir * 1.1 + Vector3.new(0, 0.6, 0)
	local showNum = Settings.get("DamageNumbers")
	if cat == "evade" then
		V.text(nil, pos + Vector3.new(0, 3.2, 0), "EVADE", Color3.fromRGB(210, 215, 230), 0.8, 24, 1.5)
		Audio.play("evade", pos)
		return
	elseif cat == "heal" then
		V.burstParticles(pos, "glint", Styles.of("Heal"), 10, 1)
		if showNum then
			V.text(nil, pos + Vector3.new(rng:NextNumber(-0.8, 0.8), 3.4, 0), "+" .. amt, Color3.fromRGB(120, 255, 150), 0.9, 24, 2)
		end
		return
	elseif cat == "guard" or cat == "perfect" then
		local gcol = cat == "perfect" and Color3.fromRGB(255, 230, 110) or Color3.fromRGB(130, 180, 255)
		-- shield plate facing the attacker
		local plate = V.part(Enum.PartType.Cylinder, Enum.Material.ForceField, gcol, Vector3.new(0.3, 5, 5), CFrame.lookAt(facePos, facePos - fromDir) * CFrame.Angles(0, math.rad(90), 0), 0)
		V.effect({
			life = cat == "perfect" and 0.35 or 0.22,
			parts = { plate },
			update = function(e, a)
				plate.Transparency = a
				plate.Size = Vector3.new(0.3, 5 + a * 2, 5 + a * 2)
			end,
		})
		V.burstParticles(facePos, "spark", Styles.of(cat == "perfect" and "Gold" or "Steel"), cat == "perfect" and 24 or 12, 1)
		if cat == "perfect" then
			V.ring(pos - Vector3.new(0, 2.4, 0), 0.5, 6, gcol, 0.4, { width = 0.3, tr0 = 0 })
			V.text(nil, pos + Vector3.new(0, 3.6, 0), "PERFECT", gcol, 0.9, 30, 1.8)
			Audio.play("perfect", pos)
			if victimIsMe then
				ctx.Camera.punch(0.6)
			end
		else
			Audio.play("block", pos, math.clamp(s, 0.6, 1.3))
		end
		if showNum and amt > 0 then
			V.text(nil, pos + Vector3.new(rng:NextNumber(-1, 1), 3, 0), tostring(amt), gcol, 0.7, 20, 1.4)
		end
		if ctx.Animator then
			ctx.Animator.flinch(model, fromDir, 0.3)
		end
		if victimIsMe then
			V.shake(pos, 0.12 * s, true)
		end
		return
	elseif cat == "shield" then
		if model then
			local bubble = V.part(Enum.PartType.Ball, Enum.Material.ForceField, Color3.fromRGB(150, 210, 255), Vector3.one * 7, CFrame.new(pos), 0)
			V.effect({
				life = 0.3,
				parts = { bubble },
				update = function(e, a)
					bubble.Transparency = a
					bubble.CFrame = CFrame.new(root and root.Position or pos)
				end,
			})
		end
		Audio.play("shieldHit", pos)
		if showNum then
			V.text(nil, pos + Vector3.new(rng:NextNumber(-1, 1), 3, 0), tostring(amt), Color3.fromRGB(150, 210, 255), 0.7, 20, 1.4)
		end
		return
	end
	-- direct / tick damage
	if cat == "tick" then
		V.burstParticles(pos, st.particle, st, 4, 0.7)
		if showNum and amt > 0 then
			V.text(nil, pos + Vector3.new(rng:NextNumber(-1.2, 1.2), 2.6, 0), tostring(amt), st.glow:Lerp(Color3.new(1, 1, 1), 0.4), 0.6, 16, 1)
		end
		return
	end
	Fam.impact(facePos, st, s * 0.8, -fromDir, "body")
	Audio.family(st, "impact", pos, math.clamp(s, 0.6, 1.6))
	if d.ult or amt >= 150 then
		Audio.play("hit", pos, 1.2, 0.6)
	end
	if model then
		V.tint(model, Color3.new(1, 1, 1), 0.08, 0.35)
	end
	if ctx.Animator then
		ctx.Animator.flinch(model, fromDir, math.clamp(amt / 120, 0.25, 1.4))
	end
	if showNum then
		local big = amt >= 150 or d.ult
		local col = big and Color3.fromRGB(255, 200, 70) or Color3.fromRGB(255, 245, 225)
		V.text(nil, pos + Vector3.new(rng:NextNumber(-1.2, 1.2), 3.2, rng:NextNumber(-0.5, 0.5)), tostring(amt), col, big and 1.1 or 0.8, big and 38 or 26, big and 2.6 or 2)
	end
	if mine then
		Audio.play("hitmarker", nil, 1)
		if ctx.HUD and ctx.HUD.hitmarker then
			ctx.HUD.hitmarker(amt >= 150 or d.ult)
		end
	end
	if victimIsMe then
		V.shake(pos, math.clamp(amt / 260, 0.12, 0.9) * st.shake, true)
		if ctx.HUD and ctx.HUD.damaged then
			ctx.HUD.damaged(amt, fromDir)
		end
	elseif d.ult or amt >= 150 then
		V.shake(pos, 0.25 * st.shake)
	end
end

-- Caster moments --------------------------------------------------------------------------------------
local charges = {} -- model -> effect

local function endCharge(model)
	local e = charges[model]
	if e then
		e.dead = true
		charges[model] = nil
	end
end

function Fam.cast(d)
	local model = d.a
	if not model or not model.Parent then
		return
	end
	local st = Styles.of(d.k)
	local hand = Poses.handFor(d.slot)
	local w = d.w or 0
	local mine = d.o == V.myId()
	local root = rootOf(model)
	if d.p60 and root then
		V.burstParticles(root.Position, "glint", Styles.of("Gold"), 12, 1)
	end
	if ctx.Showcase and ctx.Showcase.cast(d, st) then
		return
	end
	if w < 0.05 and not d.ult then
		return
	end
	endCharge(model)
	-- gathering energy at the casting hand
	local core = V.part(Enum.PartType.Ball, Enum.Material.Neon, st.glow, Vector3.one * 0.2, CFrame.new(V.handPos(model, hand) or Vector3.zero), 0.2)
	local holder = V.part(Enum.PartType.Ball, Enum.Material.SmoothPlastic, Color3.new(), Vector3.one * 2.4, core.CFrame, 1)
	local pe = Instance.new("ParticleEmitter")
	V.configure(pe, "mote", st, d.ult and 1.4 or 0.8)
	pe.Rate = (d.ult and 60 or 30) * Settings.density()
	pe.Parent = holder
	local l = V.light(core, st.glow, 0.5, 10)
	local maxR = d.ult and 1.1 or 0.55
	local life = math.max(w, 0.3) + 0.6
	local e = V.effect({
		life = life,
		parts = { core, holder },
		prio = 2,
		update = function(e, a, dt, t)
			if not model.Parent then
				e.dead = true
				return
			end
			local hp = V.handPos(model, hand)
			if hp then
				core.CFrame = CFrame.new(hp)
				holder.CFrame = core.CFrame
			end
			local k = math.min(1, t / math.max(0.1, w))
			local r = maxR * k * (1 + 0.12 * math.sin(t * 25))
			core.Size = Vector3.one * math.max(0.1, r * 2)
			if l then
				l.Brightness = (0.5 + 2.5 * k) * Settings.flash()
			end
			if d.unstable then
				core.Color = st.glow:Lerp(Color3.fromRGB(255, 80, 30), 0.5 + 0.5 * math.sin(t * 30))
			end
		end,
	})
	charges[model] = e
	Audio.family(st, "charge", root and root.Position or nil, d.ult and 1.4 or 0.9)
	if d.ult then
		Audio.play("ultCharge", root and root.Position or nil)
		if root then
			-- ground sigil + rising column (buildup)
			local g = root.Position - Vector3.new(0, 3, 0)
			V.ring(g, 7, 5, st.glow, w + 0.4, { width = 0.35, dashed = true, spin = 2.5, tr0 = 0.1, tr1 = 0.1, hold = 0.95, follow = function()
				return root.Parent and root.Position - Vector3.new(0, 3, 0) or nil
			end, prio = 2 })
			V.ring(g, 3.2, 3.2, st.color, w + 0.4, { width = 0.2, spin = -4, tr0 = 0.25, tr1 = 0.25, hold = 0.95, follow = function()
				return root.Parent and root.Position - Vector3.new(0, 3, 0) or nil
			end, prio = 2 })
			local col = V.emitter(holder, st.particle, st, 30, 1.2)
			local _ = col
		end
		if mine and ctx.Camera then
			ctx.Camera.fov(-7, w + 0.3)
		end
	end
end

function Fam.release(d)
	local model = d.a
	if not model or not model.Parent then
		return
	end
	endCharge(model)
	local st = Styles.of(d.k)
	local hand = Poses.handFor(d.slot)
	local hp = V.handPos(model, hand)
	local mine = d.o == V.myId()
	if ctx.Showcase and ctx.Showcase.release(d, st, hp) then
		return
	end
	if hp then
		V.flash(hp, st.glow, d.ult and 3 or 1.4, 0.12, 2)
		V.burstParticles(hp, st.particle, st, d.ult and 16 or 7, d.ult and 1.2 or 0.7, 2)
	end
	local root = rootOf(model)
	Audio.family(st, "release", hp or (root and root.Position), d.ult and 1.3 or 1)
	if d.ult then
		Audio.play("ultRelease", root and root.Position or hp)
		if root then
			local g = root.Position - Vector3.new(0, 2.8, 0)
			V.ring(g, 1, 12, st.glow, 0.5, { width = 0.6, tr0 = 0 })
			V.flash(root.Position, st.glow, 5, 0.2)
		end
		V.shake(root and root.Position, 0.5 * st.shake, mine)
		if mine and ctx.Camera then
			ctx.Camera.fov(10, 0.35)
		end
	elseif mine and ctx.Camera then
		ctx.Camera.kick(0.12)
	end
end

-- dash / dodge: silhouette afterimages along the path
local GHOST_PARTS = { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }
local function ghost(model, color, tr, life)
	if not V.allow(1) then
		return
	end
	local parts = {}
	for _, n in ipairs(GHOST_PARTS) do
		local src = model:FindFirstChild(n)
		if src and src:IsA("BasePart") then
			local p = V.part(Enum.PartType.Block, Enum.Material.Neon, color, src.Size, src.CFrame, tr)
			table.insert(parts, p)
		end
	end
	V.effect({
		life = life,
		parts = parts,
		update = function(e, a)
			for _, p in ipairs(parts) do
				p.Transparency = tr + (1 - tr) * a
			end
		end,
	})
end

function Fam.dash(d)
	local model = d.a
	if not model or not model.Parent then
		return
	end
	local st = Styles.of(d.k or model:GetAttribute("Kit"))
	local root = rootOf(model)
	local col = d.dodge and Color3.fromRGB(200, 220, 255) or st.glow
	local dur = math.max(0.15, d.d or 0.3)
	local n = d.dodge and 3 or 4
	for i = 0, n - 1 do
		task.delay(dur * i / n, function()
			if model.Parent then
				ghost(model, col, 0.55, 0.3)
			end
		end)
	end
	if root then
		V.burstParticles(root.Position - Vector3.new(0, 2.4, 0), d.dodge and "dust" or st.particle, d.dodge and Styles.of("Sand") or st, 6, 0.7)
	end
	Audio.play(d.dodge and "dodge" or "dash", root and root.Position)
end

function Fam.death(d)
	local model = d.a
	local pos = d.p or (rootOf(model) and rootOf(model).Position)
	if not pos then
		return
	end
	endCharge(model)
	local vst = Styles.of(d.victimKit)
	if d.summon then
		Fam.impact(pos, vst, 0.8, Vector3.yAxis, "aoe")
		return
	end
	local kst = Styles.of(d.k or d.victimKit)
	V.flash(pos, kst.glow, 4, 0.2)
	V.burstParticles(pos, kst.particle, kst, 24, 1.3, 2)
	V.ring(pos - Vector3.new(0, 2.6, 0), 1, 9, kst.glow, 0.6, { width = 0.4, tr0 = 0.1, prio = 2 })
	Audio.play("death", pos)
	if model == V.myModel() then
		ctx.Camera.impulse(0.5)
	end
	-- dissolve the body into the victim's element after a beat
	task.delay(1.6, function()
		if not model or not model.Parent then
			return
		end
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
				V.burstParticles(p.Position, "wisp", vst, 2, 0.6, 0)
			end
		end
		local parts = {}
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") or p:IsA("Decal") then
				table.insert(parts, p)
			end
		end
		V.effect({
			life = 0.9,
			update = function(e, a)
				for _, p in ipairs(parts) do
					if p.Parent then
						p.LocalTransparencyModifier = a
					end
				end
			end,
		})
	end)
end

function Fam.spawn(d)
	local model = d.a
	task.wait(0.05)
	local root = rootOf(model)
	if not root then
		return
	end
	local st = Styles.of(d.k)
	local base = root.Position - Vector3.new(0, 3, 0)
	local col = V.part(Enum.PartType.Cylinder, Enum.Material.Neon, st.glow, Vector3.new(14, 0.4, 0.4), CFrame.new(base + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.1)
	V.effect({
		life = 0.7,
		parts = { col },
		update = function(e, a)
			col.Size = Vector3.new(14, 0.4 + 3.5 * V.outQuad(a), 0.4 + 3.5 * V.outQuad(a))
			col.Transparency = 0.1 + 0.9 * a
		end,
	})
	V.ring(base, 0.5, 6, st.glow, 0.6, { width = 0.35, tr0 = 0.1 })
	V.burstParticles(base + Vector3.new(0, 2, 0), "glint", st, 16, 1.2)
	Audio.play("respawn", root.Position)
	-- spawn protection shimmer
	local untilT = model:GetAttribute("SpawnProtected") or 0
	local now = workspace:GetServerTimeNow()
	if untilT > now then
		V.tint(model, Color3.fromRGB(230, 240, 255), untilT - now, 0.8)
	end
end

-- Persistent server visuals ("EBVis") --------------------------------------------------------------------
local function aliveInst(inst)
	return inst.Parent ~= nil
end

function Fam.dress(inst)
	if not inst:IsA("BasePart") then
		return
	end
	local kind = inst:GetAttribute("VisKind") or "base"
	local st = Styles.of(inst:GetAttribute("Kit"))
	local owner = inst:GetAttribute("Owner")
	local rel = V.relation(owner)
	if kind == "disc" or kind == "rect" then
		local harmful = inst:GetAttribute("Harmful")
		local hostile = harmful ~= false and (rel == "enemy" or rel == "neutral")
		inst.Material = Enum.Material.Neon
		inst.Transparency = math.max(inst.Transparency, 0.78)
		-- edge: hostile zones get spiked, pulsing rails; friendly zones a thin dashed line
		local edgeCol = hostile and st.color:Lerp(V.HOSTILE, 0.4) or st.glow:Lerp(V.FRIEND, rel == "ally" and 0.4 or 0)
		if kind == "disc" then
			local r = inst.Size.Y / 2
			V.ring(inst.Position, r, r, edgeCol, 3600, {
				width = hostile and 0.35 or 0.2,
				spikes = hostile and harmful == true,
				dashed = rel == "ally",
				tr0 = hostile and 0.15 or 0.35,
				tr1 = hostile and 0.15 or 0.35,
				hold = 0.999,
				pulse = (hostile and not Settings.get("ReducedFlash")) and 3 or nil,
				prio = 3,
				follow = function()
					return aliveInst(inst) and inst.Position or nil
				end,
			})
			-- rising element particles over the area
			local rate = math.clamp(r * r * 0.25, 4, 30)
			V.emitter(inst, st.particle, st, rate, math.clamp(r / 6, 0.5, 1.4))
		else
			V.emitter(inst, st.particle, st, math.clamp(inst.Size.X * inst.Size.Z * 0.04, 4, 24), 0.8)
		end
	elseif kind == "sphere" then
		local r = inst.Size.X / 2
		V.emitter(inst, st.particle, st, math.clamp(r * 3, 4, 26), math.clamp(r / 4, 0.6, 1.6))
		if st.light > 0 then
			V.light(inst, st.glow, 0.8 * st.light, math.clamp(r * 2.5, 8, 30))
		end
	elseif kind == "ring" then
		inst.LocalTransparencyModifier = 1
		local r = inst.Size.Y / 2
		V.ring(inst.Position - Vector3.new(0, 0.15, 0), r, r, inst.Color, 3600, {
			width = inst:GetAttribute("Thickness") or 0.35,
			tr0 = 0.15,
			tr1 = 0.15,
			hold = 0.999,
			prio = 2,
			follow = function()
				return aliveInst(inst) and (inst.Position - Vector3.new(0, 0.15, 0)) or nil
			end,
		})
	elseif kind == "beam" then
		inst.Transparency = math.max(inst.Transparency, 0.55)
		local a0 = Instance.new("Attachment")
		local a1 = Instance.new("Attachment")
		local function place()
			a0.Position = Vector3.new(0, 0, -inst.Size.Z / 2)
			a1.Position = Vector3.new(0, 0, inst.Size.Z / 2)
		end
		place()
		a0.Parent = inst
		a1.Parent = inst
		inst:GetPropertyChangedSignal("Size"):Connect(place)
		local bm = Instance.new("Beam")
		bm.Attachment0 = a0
		bm.Attachment1 = a1
		bm.FaceCamera = true
		bm.Width0 = math.max(0.3, inst.Size.X * 1.6)
		bm.Width1 = bm.Width0
		bm.LightEmission = 1
		bm.LightInfluence = 0
		bm.Color = ColorSequence.new(st.glow)
		bm.Transparency = NumberSequence.new(0.35)
		bm.Parent = inst
	elseif kind == "base" then
		if inst.Material == Enum.Material.Neon and st.light > 0 and inst.Size.Magnitude > 2 then
			V.light(inst, inst.Color, 0.6, 10)
		end
	end
end

function Fam.init(c)
	ctx = c
	Settings = c.Settings
	Audio = c.Audio
	local H = V.handlers
	H.hit = Fam.hit
	H.cast = Fam.cast
	H.release = Fam.release
	H.dash = Fam.dash
	H.death = Fam.death
	H.spawn = function(d)
		task.spawn(Fam.spawn, d)
	end
end

return Fam
