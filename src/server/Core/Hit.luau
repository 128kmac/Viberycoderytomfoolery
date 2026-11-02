-- Geometry queries against fighter capsules, world line-of-sight and legal placement.
-- All inputs here are in studs.
local S = require(script.Parent.S)

local Hit = {}
S.Hit = Hit

local Config = S.Config

local worldParams = RaycastParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Include
worldParams.FilterDescendantsInstances = { S.folders.Arena, S.folders.Constructs }
worldParams.IgnoreWater = true
Hit.worldParams = worldParams

local arenaParams = RaycastParams.new()
arenaParams.FilterType = Enum.RaycastFilterType.Include
arenaParams.FilterDescendantsInstances = { S.folders.Arena }
arenaParams.IgnoreWater = true
Hit.arenaParams = arenaParams

-- capsule of a fighter: returns bottom point, top point, radius
function Hit.capsule(f)
	local p = f.root.Position
	local sc = f.hitScale or 1
	if f.isSummon then
		local r = (f.radius or 1.2) * sc
		return p - Vector3.new(0, r * 0.5, 0), p + Vector3.new(0, r * 0.5, 0), r
	end
	return p - Vector3.new(0, Config.BODY_DOWN * sc, 0), p + Vector3.new(0, Config.BODY_UP * sc, 0), Config.BODY_RADIUS * sc
end

local function clamp01(x)
	if x < 0 then
		return 0
	elseif x > 1 then
		return 1
	end
	return x
end

-- closest distance between segments p1q1 and p2q2; also returns s (param along first)
function Hit.segSeg(p1, q1, p2, q2)
	local d1 = q1 - p1
	local d2 = q2 - p2
	local r = p1 - p2
	local a = d1:Dot(d1)
	local e = d2:Dot(d2)
	local f = d2:Dot(r)
	local s, t
	if a <= 1e-8 and e <= 1e-8 then
		return (p1 - p2).Magnitude, 0
	end
	if a <= 1e-8 then
		s = 0
		t = clamp01(f / e)
	else
		local c = d1:Dot(r)
		if e <= 1e-8 then
			t = 0
			s = clamp01(-c / a)
		else
			local b = d1:Dot(d2)
			local denom = a * e - b * b
			if denom ~= 0 then
				s = clamp01((b * f - c * e) / denom)
			else
				s = 0
			end
			t = (b * s + f) / e
			if t < 0 then
				t = 0
				s = clamp01(-c / a)
			elseif t > 1 then
				t = 1
				s = clamp01((b - c) / a)
			end
		end
	end
	local c1 = p1 + d1 * s
	local c2 = p2 + d2 * t
	return (c1 - c2).Magnitude, s
end

function Hit.pointSeg(p, a, b)
	local ab = b - a
	local denom = ab:Dot(ab)
	local t = 0
	if denom > 1e-8 then
		t = clamp01((p - a):Dot(ab) / denom)
	end
	return (p - (a + ab * t)).Magnitude
end

local function eachCandidate(filter, fn)
	for _, f in pairs(S.fighters) do
		if S.alive(f) and (filter == nil or filter(f)) then
			fn(f)
		end
	end
end
Hit.eachCandidate = eachCandidate

-- swept sphere a->b of radius r; returns list of {f=, s=} sorted along the segment
function Hit.segment(a, b, r, filter)
	local out = {}
	eachCandidate(filter, function(f)
		local ca, cb, cr = Hit.capsule(f)
		local d, s = Hit.segSeg(a, b, ca, cb)
		if d <= r + cr then
			table.insert(out, { f = f, s = s })
		end
	end)
	table.sort(out, function(x, y)
		return x.s < y.s
	end)
	return out
end

function Hit.sphere(center, r, filter)
	local out = {}
	eachCandidate(filter, function(f)
		local ca, cb, cr = Hit.capsule(f)
		if Hit.pointSeg(center, ca, cb) <= r + cr then
			table.insert(out, f)
		end
	end)
	return out
end

-- ground cylinder: horizontal radius r, vertical extent [center.Y - below, center.Y + above]
function Hit.cylinder(center, r, filter, above, below)
	above = above or S.m(4)
	below = below or S.m(2)
	local out = {}
	eachCandidate(filter, function(f)
		local ca, cb, cr = Hit.capsule(f)
		local p = f.root.Position
		local dx = Vector3.new(p.X - center.X, 0, p.Z - center.Z).Magnitude
		if dx <= r + cr * 0.6 and cb.Y >= center.Y - below and ca.Y <= center.Y + above then
			table.insert(out, f)
		end
	end)
	return out
end

-- ring between inner and outer radius
function Hit.ring(center, inner, outer, filter)
	local out = {}
	for _, f in ipairs(Hit.cylinder(center, outer, filter)) do
		local p = f.root.Position
		local dx = Vector3.new(p.X - center.X, 0, p.Z - center.Z).Magnitude
		if dx >= inner - Config.BODY_RADIUS * 0.6 then
			table.insert(out, f)
		end
	end
	return out
end

-- oriented box (cf at centre, size full extents)
function Hit.box(cf, size, filter)
	local out = {}
	local half = size / 2
	eachCandidate(filter, function(f)
		local _, _, cr = Hit.capsule(f)
		local lp = cf:PointToObjectSpace(f.root.Position)
		if math.abs(lp.X) <= half.X + cr and math.abs(lp.Z) <= half.Z + cr and math.abs(lp.Y) <= half.Y + Config.BODY_DOWN then
			table.insert(out, f)
		end
	end)
	return out
end

-- cone: origin, flat dir, length, full angle in degrees; requires line of sight from origin
function Hit.cone(origin, dir, length, angle, filter, needLos)
	local out = {}
	local d = Vector3.new(dir.X, 0, dir.Z)
	if d.Magnitude < 1e-4 then
		return out
	end
	d = d.Unit
	local cosHalf = math.cos(math.rad(angle / 2))
	eachCandidate(filter, function(f)
		local p = f.root.Position
		local v = Vector3.new(p.X - origin.X, 0, p.Z - origin.Z)
		local dist = v.Magnitude
		if dist <= length + Config.BODY_RADIUS and math.abs(p.Y - origin.Y) < S.m(4) then
			if dist < Config.BODY_RADIUS * 1.5 or v.Unit:Dot(d) >= cosHalf then
				if needLos == false or Hit.los(origin, p) then
					table.insert(out, f)
				end
			end
		end
	end)
	return out
end

-- line of sight between two points (world + blocking constructs)
function Hit.los(a, b, ignoreConstructs)
	local dir = b - a
	if dir.Magnitude < 0.05 then
		return true
	end
	local res = workspace:Raycast(a, dir, ignoreConstructs and arenaParams or worldParams)
	return res == nil
end

function Hit.raycast(a, dir, ignoreConstructs)
	return workspace:Raycast(a, dir, ignoreConstructs and arenaParams or worldParams)
end

-- ground below a point (returns position, or nil if over the void)
function Hit.ground(pos, maxDown)
	local res = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -(maxDown or 80), 0), worldParams)
	if res then
		return res.Position, res.Instance
	end
	return nil
end

-- furthest reachable point travelling from `from` along `dir` (unit) for `dist` studs at body height
function Hit.clearPath(from, dir, dist, radius)
	radius = radius or 1.2
	if dist <= 0 then
		return from, nil
	end
	local res = workspace:Spherecast(from, radius, dir * dist, worldParams)
	if res then
		local d = math.max(0, res.Distance - 0.25)
		return from + dir * d, res
	end
	return from + dir * dist, nil
end

-- is a body-sized space free at pos (root height)?
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
overlap.FilterDescendantsInstances = { S.folders.Arena, S.folders.Constructs }
function Hit.spaceFree(pos, scale)
	scale = scale or 1
	local parts = workspace:GetPartBoundsInBox(CFrame.new(pos), Vector3.new(2, 4.2, 2) * scale, overlap)
	for _, p in ipairs(parts) do
		if p.CanCollide then
			return false
		end
	end
	return true
end

-- legal standing destination: free space + ground within 12 studs below
function Hit.legal(pos, scale)
	if not Hit.spaceFree(pos, scale) then
		return false
	end
	local g = Hit.ground(pos, 14)
	return g ~= nil
end

-- snap a ground point to stand position (root height above ground)
function Hit.standAt(groundPos)
	return groundPos + Vector3.new(0, Config.BODY_DOWN + 0.4, 0)
end

-- find a legal stand position near `pos`, searching outward
function Hit.findLegal(pos, scale)
	local g = Hit.ground(pos + Vector3.new(0, 6, 0), 40)
	if g then
		local st = Hit.standAt(g)
		if Hit.spaceFree(st, scale) then
			return st
		end
	end
	for r = 2, 12, 2 do
		for i = 0, 7 do
			local a = i * math.pi / 4
			local p = pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			local gg = Hit.ground(p + Vector3.new(0, 6, 0), 40)
			if gg then
				local st = Hit.standAt(gg)
				if Hit.spaceFree(st, scale) then
					return st
				end
			end
		end
	end
	return nil
end

return Hit
