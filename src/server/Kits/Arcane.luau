-- 06 Arcane — Geometric spell construction
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local VIOLET = Color3.fromRGB(160, 90, 255)

local function vertices(f)
	local out = {}
	for _, v in ipairs(f.state.verts or {}) do
		if v.alive then
			table.insert(out, v)
		end
	end
	f.state.verts = out
	return out
end

local function vpos(v)
	return K.ground(v.part.Position)
end

local function redrawLines(f)
	if f.state.lineModel then
		f.state.lineModel:Destroy()
	end
	local vs = vertices(f)
	local m = Instance.new("Model")
	m.Name = "LeyLines"
	for i = 1, #vs do
		local j = i % #vs + 1
		if #vs == 2 and i == 2 then
			break
		end
		if #vs >= 2 and i ~= j then
			local a, b = vpos(vs[i]) + Vector3.new(0, 0.4, 0), vpos(vs[j]) + Vector3.new(0, 0.4, 0)
			local p = K.FX.beam(a, b, 0.25, VIOLET, false, 0.3)
			if p then
				p.Parent = m
			end
		end
	end
	m.Parent = S.folders.FX
	f.state.lineModel = m
	K.res(f, "Vertices", #vs, 3)
end

local function addVertex(f, pos)
	local vs = vertices(f)
	if #vs >= 3 then
		S.Objects.remove(vs[1], "replaced")
	end
	local v = K.object(f, {
		name = "Vertex",
		pos = pos,
		size = Vector3.new(0.6, 1.4, 0.6),
		hp = 60,
		duration = 8,
		solid = false,
		blocks = true,
		color = VIOLET,
		material = Enum.Material.Neon,
		noCap = true,
		onDestroy = function()
			redrawLines(f)
		end,
		onExpire = function()
			redrawLines(f)
		end,
	})
	table.insert(f.state.verts, v)
	redrawLines(f)
	return v
end

local function lines(f)
	local vs = vertices(f)
	local out = {}
	if #vs == 2 then
		table.insert(out, { vs[1], vs[2] })
	elseif #vs == 3 then
		table.insert(out, { vs[1], vs[2] })
		table.insert(out, { vs[2], vs[3] })
		table.insert(out, { vs[3], vs[1] })
	end
	return out
end

local function pointInTri(p, a, b, c)
	local function sign(p1, p2, p3)
		return (p1.X - p3.X) * (p2.Z - p3.Z) - (p2.X - p3.X) * (p1.Z - p3.Z)
	end
	local d1, d2, d3 = sign(p, a, b), sign(p, b, c), sign(p, c, a)
	local neg = d1 < 0 or d2 < 0 or d3 < 0
	local pos = d1 > 0 or d2 > 0 or d3 > 0
	return not (neg and pos)
end

function Kit.passive.init(f)
	f.state.verts = {}
end
function Kit.passive.cleanup(f)
	if f.state.lineModel then
		f.state.lineModel:Destroy()
	end
end

-- 1 Axiom Bolt
Kit[1] = function(c)
	local f = c.f
	local bent = false
	K.proj(c, {
		range = 24,
		width = 0.4,
		color = VIOLET,
		dmg = 65,
		hit = function(t)
			addVertex(f, K.feet(t))
		end,
		wall = function(pos)
			addVertex(f, K.ground(pos))
		end,
		step = function(p)
			if c.p60 and not bent then
				for _, v in ipairs(vertices(f)) do
					if (v.part.Position - p.pos).Magnitude < K.m(1.2) then
						local best, bestAng
						for _, t in ipairs(K.enemies(f, 30)) do
							local to = (t.root.Position - p.pos)
							local ang = math.deg(math.acos(math.clamp(to.Unit:Dot(p.vel.Unit), -1, 1)))
							if ang <= 60 and (not bestAng or ang < bestAng) and K.los(p.pos, t.root.Position) then
								best, bestAng = t, ang
							end
						end
						if best then
							bent = true
							p.vel = (best.root.Position - p.pos).Unit * p.speed
						end
						break
					end
				end
			end
		end,
	})
end

-- 2 Transversal
Kit.requires = {
	[2] = function(c)
		if #lines(c.f) > 0 then
			return true
		end
		return false, "Needs a ley line (two vertices)"
	end,
	[3] = function(c)
		if #vertices(c.f) == 3 then
			return true
		end
		return false, "Needs a triangle (three vertices)"
	end,
	[4] = function(c)
		if #lines(c.f) > 0 then
			return true
		end
		return false, "Needs a ley line"
	end,
}
Kit[2] = function(c)
	local f = c.f
	local my = f.root.Position
	local aim = c:aimPoint(16)
	-- pick the line nearest to the caster, slide toward the end nearest the aim
	local best, bd
	for _, ln in ipairs(lines(f)) do
		local d = K.Hit.pointSeg(my, vpos(ln[1]), vpos(ln[2]))
		if not bd or d < bd then
			best, bd = ln, d
		end
	end
	if not best then
		return
	end
	local a, b = vpos(best[1]), vpos(best[2])
	if (b - aim).Magnitude > (a - aim).Magnitude then
		a, b = b, a
	end
	if not K.Hit.los(a + Vector3.new(0, 1.5, 0), b + Vector3.new(0, 1.5, 0)) then
		K.notify(f, "Line blocked by cover")
		return
	end
	K.FX.sphere(b + Vector3.new(0, 1, 0), 1.2, VIOLET, 0.4, 0.2)
	if c.p60 then
		local decoy = K.decoyModel(f, f.root.CFrame, VIOLET)
		game:GetService("Debris"):AddItem(decoy, 1)
	end
	local start = f.root.Position
	local stand = K.Hit.standAt(b)
	local hit = {}
	K.path(c, function(alpha)
		return start:Lerp(stand, alpha)
	end, 0.35)
	for _, h in ipairs(K.Hit.segment(start, stand, K.m(0.9), K.enemyFilter(c))) do
		if not hit[h.f] then
			hit[h.f] = true
			K.dmg(c, h.f, 80, { melee = true })
		end
	end
end

-- 3 Proof of Containment
Kit[3] = function(c)
	local f = c.f
	local vs = vertices(f)
	if #vs < 3 then
		return
	end
	if c.p60 then
		local aim = c:aimPoint(20)
		local nearest, nd
		for _, v in ipairs(vs) do
			local d = (vpos(v) - aim).Magnitude
			if not nd or d < nd then
				nearest, nd = v, d
			end
		end
		local p = vpos(nearest)
		local move = K.flat(aim - p) * math.min(K.m(2), nd)
		nearest.part.Position += move
		redrawLines(f)
	end
	local inside = {}
	local last = {}
	K.FX.highlight(f.state.lineModel, VIOLET, 4, 0.2)
	K.every(0.1, 4, function()
		local cur = vertices(f)
		if #cur < 3 then
			return false
		end
		local a, b, cc = vpos(cur[1]), vpos(cur[2]), vpos(cur[3])
		for _, t in ipairs(K.enemies(f, 40)) do
			local now = pointInTri(t.root.Position, a, b, cc)
			if inside[t] ~= nil and inside[t] ~= now then
				if not last[t] or K.now() - last[t] >= 1 then
					last[t] = K.now()
					K.dmg(c, t, 45, { kind = "field" })
					K.root(c, t, 0.3)
				end
			end
			inside[t] = now
		end
		return true
	end)
end

-- 4 Counterformula
Kit[4] = function(c)
	local f = c.f
	local consumed = false
	K.every(0.05, 0.7, function()
		if consumed then
			return false
		end
		for _, ln in ipairs(lines(f)) do
			local a, b = vpos(ln[1]) + Vector3.new(0, 1.5, 0), vpos(ln[2]) + Vector3.new(0, 1.5, 0)
			for _, p in pairs(S.Proj.list) do
				if p.alive and p.owner and K.isEnemy(f, p.owner) and p.kind ~= "ultimate" and K.Hit.pointSeg(p.pos, a, b) < K.m(1.2) then
					if p.kind == "physical" then
						p.data.weakened = true
					else
						consumed = true
						local at = p.pos
						S.Proj.stop(p, "dissolved")
						K.addEnergy(f, 15)
						K.FX.burst(at, K.m(1), VIOLET, 0.25)
						if c.p60 then
							addVertex(f, K.ground(at))
						end
						return false
					end
				end
			end
		end
		return true
	end)
end

-- 5 Grand Theorem (ultimate)
Kit[5] = function(c)
	local f = c.f
	local vs = vertices(f)
	local center, radius
	local owners = {}
	if #vs == 3 then
		local a, b, cc = vpos(vs[1]), vpos(vs[2]), vpos(vs[3])
		center = (a + b + cc) / 3
		radius = math.max(6, math.max((a - center).Magnitude, (b - center).Magnitude, (cc - center).Magnitude) / K.M)
		for i = 1, 6 do
			owners[i] = vs[math.floor((i - 1) / 2) + 1]
		end
	else
		center = c:aimPoint(24)
		radius = 5
	end
	local hex = {}
	for i = 0, 5 do
		local a = math.rad(i * 60)
		hex[i + 1] = center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(radius)
	end
	K.FX.ring(center, K.m(radius), VIOLET, 5.2, 0.3)
	local taken = {}
	local rot = 0
	for i = 1, 6 do
		local a, b = hex[i], hex[i % 6 + 1]
		if c.unstable then
			rot += 15
			local cf = CFrame.Angles(0, math.rad(rot), 0)
			a = center + cf:VectorToWorldSpace(a - center)
			b = center + cf:VectorToWorldSpace(b - center)
		end
		local open = owners[i] and not owners[i].alive
		K.FX.beam(a + Vector3.new(0, 0.5, 0), b + Vector3.new(0, 0.5, 0), 0.6, open and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 80, 120), 0.6)
		task.wait(0.7)
		if not open then
			for _, t in ipairs(K.enemiesIn(c, center, radius)) do
				if (taken[t] or 0) < 4 then
					taken[t] = (taken[t] or 0) + 1
					K.dmg(c, t, 60, { fromPos = (a + b) / 2 })
				end
			end
			K.FX.beam(a + Vector3.new(0, 1, 0), center + Vector3.new(0, 1, 0), 1, VIOLET, 0.2)
		end
	end
	if c.unstable then
		-- Forbidden Geometry: central collapse hits the caster too and destroys all vertices
		K.warn(c, center, 3, 0.5, Color3.fromRGB(255, 60, 160))
		for _, t in ipairs(K.Hit.cylinder(center, K.m(3), function()
			return true
		end)) do
			K.Combat.damage(f, t, 100, { cast = c, isUlt = true, fromPos = center, element = "Arcane" })
		end
		for _, v in ipairs(vertices(f)) do
			S.Objects.remove(v, "collapse")
		end
		redrawLines(f)
	end
end

return Kit
