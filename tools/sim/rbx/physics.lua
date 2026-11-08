-- Geometry queries, simple character physics, joint kinematics, rigs, camera math.
local R = ...
local DATA = R.DATA
local v3, CFrame = R.v3, R.CFrame
local abs, sqrt, huge, min, max = math.abs, math.sqrt, math.huge, math.min, math.max

---------------------------------------------------------------- part registry
R.parts = {} -- BasePart -> true (inside Workspace)
-- broadphase: anchored queryable parts live in a uniform XZ grid; everything else is "loose" (brute force)
R.loose = {}
R.inGrid = {}
R.gridDirty = true
R.joints = {} -- joint instances inside Workspace
R.humanoids = {}
local function inWorkspace(obj)
	local o = DATA[obj].parent
	while o do
		if o == R.workspace then
			return true
		end
		o = DATA[o].parent
	end
	return false
end
R.inWorkspace = inWorkspace
local function isPart(obj)
	return DATA[obj].cls.P.Size ~= nil and R.classIsA(DATA[obj].cls, "BasePart")
end
R.isPart = isPart
table.insert(R.hooks.added, function(x)
	if not inWorkspace(x) then
		return
	end
	local cn = DATA[x].cls.name
	if isPart(x) and cn ~= "Terrain" then
		R.parts[x] = true
		DATA[x].aabb = nil
		local pr = DATA[x].props
		if pr.Anchored and pr.CanQuery then
			R.gridDirty = true
		else
			R.loose[x] = true
		end
	elseif cn == "Motor6D" or cn == "Weld" or cn == "WeldConstraint" or cn == "ManualWeld" then
		R.joints[x] = true
	elseif cn == "Humanoid" then
		R.humanoids[x] = true
	end
end)
table.insert(R.hooks.removing, function(x)
	R.parts[x] = nil
	R.loose[x] = nil
	R.joints[x] = nil
	R.humanoids[x] = nil
end)
function R.partMoved(obj, d)
	d.aabb = nil
	if R.inGrid[obj] then
		R.gridDirty = true
	end
	if d.cls.name == "Terrain" then
		return
	end
end

local function shapeOf(d)
	local cn = d.cls.name
	if cn == "WedgePart" then
		return "Wedge"
	elseif cn == "Part" or cn == "SpawnLocation" then
		local s = d.props.Shape
		if s then
			return s.Name
		end
	end
	return "Block"
end
R.shapeOf = shapeOf

local function aabb(d)
	local a = d.aabb
	if a then
		return a
	end
	local c, s = d.cf, d.props.Size
	local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
	local ex = abs(c[4]) * hx + abs(c[5]) * hy + abs(c[6]) * hz
	local ey = abs(c[7]) * hx + abs(c[8]) * hy + abs(c[9]) * hz
	local ez = abs(c[10]) * hx + abs(c[11]) * hy + abs(c[12]) * hz
	a = { c[1] - ex, c[2] - ey, c[3] - ez, c[1] + ex, c[2] + ey, c[3] + ez }
	d.aabb = a
	return a
end
R.aabb = aabb

local function rayAabb(a, ox, oy, oz, dx, dy, dz, inflate)
	local tmin, tmax = 0, 1
	local mins = { a[1] - inflate, a[2] - inflate, a[3] - inflate }
	local maxs = { a[4] + inflate, a[5] + inflate, a[6] + inflate }
	local o = { ox, oy, oz }
	local dd = { dx, dy, dz }
	for i = 1, 3 do
		if abs(dd[i]) < 1e-12 then
			if o[i] < mins[i] or o[i] > maxs[i] then
				return false
			end
		else
			local t1 = (mins[i] - o[i]) / dd[i]
			local t2 = (maxs[i] - o[i]) / dd[i]
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			if t1 > tmin then
				tmin = t1
			end
			if t2 < tmax then
				tmax = t2
			end
			if tmin > tmax then
				return false
			end
		end
	end
	return true
end

-- convex local-space intersection: planes {nx,ny,nz,d} meaning n.p <= d
local function rayPlanes(planes, o, dir)
	local tin, tout = -huge, huge
	local nin
	for _, pl in ipairs(planes) do
		local nx, ny, nz, dd = pl[1], pl[2], pl[3], pl[4]
		local num = dd - (nx * o.X + ny * o.Y + nz * o.Z)
		local den = nx * dir.X + ny * dir.Y + nz * dir.Z
		if abs(den) < 1e-12 then
			if num < 0 then
				return nil
			end
		else
			local t = num / den
			if den < 0 then
				if t > tin then
					tin = t
					nin = pl
				end
			else
				if t < tout then
					tout = t
				end
			end
		end
		if tin > tout then
			return nil
		end
	end
	if tout < 0 then
		return nil
	end
	if tin < 0 then
		return 0, nin -- origin inside
	end
	return tin, nin
end

local function boxPlanes(hx, hy, hz, inflate)
	hx, hy, hz = hx + inflate, hy + inflate, hz + inflate
	return {
		{ 1, 0, 0, hx }, { -1, 0, 0, hx }, { 0, 1, 0, hy }, { 0, -1, 0, hy }, { 0, 0, 1, hz }, { 0, 0, -1, hz },
	}
end
local function wedgePlanes(sx, sy, sz, inflate)
	local hx, hy, hz = sx / 2, sy / 2, sz / 2
	-- slope: y/sy <= z/sz  ->  (sz) y - (sy) z <= 0  (rises toward +Z/back)
	local n = sqrt(sz * sz + sy * sy)
	return {
		{ 1, 0, 0, hx + inflate }, { -1, 0, 0, hx + inflate }, { 0, -1, 0, hy + inflate }, { 0, 0, 1, hz + inflate }, { 0, 0, -1, hz + inflate },
		{ 0, sz / n, -sy / n, inflate },
	}
end

-- returns t in [0,1] along dir and world normal, or nil
local function rayPart(d, origin, dir, inflate)
	local c, s = d.cf, d.props.Size
	local shape = shapeOf(d)
	local lo = R.pointToObject(c, origin)
	local ld = R.vecToObject(c, dir)
	if shape == "Ball" then
		local r = min(s.X, s.Y, s.Z) / 2 + inflate
		local b = lo.X * ld.X + lo.Y * ld.Y + lo.Z * ld.Z
		local a = ld.X * ld.X + ld.Y * ld.Y + ld.Z * ld.Z
		local cc = lo.X * lo.X + lo.Y * lo.Y + lo.Z * lo.Z - r * r
		if cc <= 0 then
			return 0, -dir.Unit
		end
		local disc = b * b - a * cc
		if disc < 0 then
			return nil
		end
		local t = (-b - sqrt(disc)) / a
		if t < 0 or t > 1 then
			return nil
		end
		local hp = lo + ld * t
		return t, R.vecToWorld(c, hp.Unit)
	elseif shape == "Cylinder" then
		local r = min(s.Y, s.Z) / 2 + inflate
		local h = s.X / 2 + inflate
		local best, bn
		-- side
		local a = ld.Y * ld.Y + ld.Z * ld.Z
		local b = lo.Y * ld.Y + lo.Z * ld.Z
		local cc = lo.Y * lo.Y + lo.Z * lo.Z - r * r
		if cc <= 0 and abs(lo.X) <= h then
			return 0, -dir.Unit
		end
		if a > 1e-12 then
			local disc = b * b - a * cc
			if disc >= 0 then
				local t = (-b - sqrt(disc)) / a
				if t >= 0 and t <= 1 then
					local x = lo.X + ld.X * t
					if abs(x) <= h then
						best = t
						bn = v3(0, lo.Y + ld.Y * t, lo.Z + ld.Z * t).Unit
					end
				end
			end
		end
		-- caps
		if abs(ld.X) > 1e-12 then
			for _, cx in ipairs({ h, -h }) do
				local t = (cx - lo.X) / ld.X
				if t >= 0 and t <= 1 and (not best or t < best) then
					local y, z = lo.Y + ld.Y * t, lo.Z + ld.Z * t
					if y * y + z * z <= r * r then
						best = t
						bn = v3(cx > 0 and 1 or -1, 0, 0)
					end
				end
			end
		end
		if best then
			return best, R.vecToWorld(c, bn)
		end
		return nil
	end
	local planes = shape == "Wedge" and wedgePlanes(s.X, s.Y, s.Z, inflate) or boxPlanes(s.X / 2, s.Y / 2, s.Z / 2, inflate)
	local t, pl = rayPlanes(planes, lo, ld)
	if not t or t > 1 then
		return nil
	end
	local n = pl and v3(pl[1], pl[2], pl[3]) or v3(0, 1, 0)
	if t == 0 then
		return 0, -dir.Unit
	end
	return t, R.vecToWorld(c, n)
end
R.rayPart = rayPart

-- filters
local function filterSet(params)
	if not params then
		return nil, "Exclude"
	end
	local list = params.FilterDescendantsInstances or {}
	local set = {}
	for _, x in ipairs(list) do
		set[x] = true
	end
	local ft = params.FilterType
	local mode = (ft == R.Enum.RaycastFilterType.Include or ft == R.Enum.RaycastFilterType.Whitelist) and "Include" or "Exclude"
	return set, mode
end
local function passes(part, set, mode)
	if not set then
		return true
	end
	local o = part
	local hit = false
	while o do
		if set[o] then
			hit = true
			break
		end
		o = DATA[o].parent
	end
	if mode == "Include" then
		return hit
	end
	return not hit
end
R.filterPasses = passes

local RRMT = {}
R.TYPE[RRMT] = "RaycastResult"
RRMT.__index = function(_, k)
	error(tostring(k) .. " is not a valid member of RaycastResult", 2)
end

local CELL = 24
local grid = {}
local function cellKey(i, j)
	return i * 65536 + j
end
local function rebuildGrid()
	grid = {}
	R.inGrid = {}
	R.loose = {}
	for part in pairs(R.parts) do
		local d = DATA[part]
		local pr = d.props
		if pr.Anchored and pr.CanQuery then
			R.inGrid[part] = true
			local a = aabb(d)
			for i = math.floor(a[1] / CELL), math.floor(a[4] / CELL) do
				for j = math.floor(a[3] / CELL), math.floor(a[6] / CELL) do
					local k = cellKey(i, j)
					local l = grid[k]
					if not l then
						l = {}
						grid[k] = l
					end
					l[#l + 1] = part
				end
			end
		else
			R.loose[part] = true
		end
	end
	R.gridDirty = false
end
local stamp = 0
local seen = {}
-- collects candidate parts for an XZ rectangle (cells) into out
local function gatherRect(x0, z0, x1, z1, out)
	if R.gridDirty then
		rebuildGrid()
	end
	stamp = stamp + 1
	local n = 0
	for i = math.floor(min(x0, x1) / CELL), math.floor(max(x0, x1) / CELL) do
		for j = math.floor(min(z0, z1) / CELL), math.floor(max(z0, z1) / CELL) do
			local l = grid[cellKey(i, j)]
			if l then
				for q = 1, #l do
					local part = l[q]
					if seen[part] ~= stamp then
						seen[part] = stamp
						n = n + 1
						out[n] = part
					end
				end
			end
		end
	end
	for part in pairs(R.loose) do
		n = n + 1
		out[n] = part
	end
	return n
end
-- candidates along a ray: walk the XZ cells the (inflated) segment crosses
local function gatherRay(ox, oz, dx, dz, inflate, out)
	local len = sqrt(dx * dx + dz * dz)
	if len < CELL * 4 then
		return gatherRect(min(ox, ox + dx) - inflate, min(oz, oz + dz) - inflate, max(ox, ox + dx) + inflate, max(oz, oz + dz) + inflate, out)
	end
	if R.gridDirty then
		rebuildGrid()
	end
	stamp = stamp + 1
	local n = 0
	local steps = math.ceil(len / (CELL * 0.5))
	local pad = inflate + 1
	local lastI, lastJ
	for st = 0, steps do
		local t = st / steps
		local px, pz = ox + dx * t, oz + dz * t
		for i = math.floor((px - pad) / CELL), math.floor((px + pad) / CELL) do
			for j = math.floor((pz - pad) / CELL), math.floor((pz + pad) / CELL) do
				-- neighbours too: a half-cell step can clip a corner
				for di = -1, 1 do
					for dj = -1, 1 do
						local l = grid[cellKey(i + di, j + dj)]
						if l then
							for q = 1, #l do
								local part = l[q]
								if seen[part] ~= stamp then
									seen[part] = stamp
									n = n + 1
									out[n] = part
								end
							end
						end
					end
				end
			end
		end
	end
	for part in pairs(R.loose) do
		n = n + 1
		out[n] = part
	end
	return n
end
local candBuf = {}

local function cast(origin, dir, params, inflate)
	if R.typeof(origin) ~= "Vector3" or R.typeof(dir) ~= "Vector3" then
		error("Raycast expects Vector3 origin and direction", 3)
	end
	if dir.X ~= dir.X or origin.X ~= origin.X then
		R.log(R.warnings, "Raycast with NaN vector")
		return nil
	end
	R.rayCount = (R.rayCount or 0) + 1
	local set, mode = filterSet(params)
	local respect = params and params.RespectCanCollide
	local ignoreWater = params and params.IgnoreWater
	local ox, oy, oz, dx, dy, dz = origin.X, origin.Y, origin.Z, dir.X, dir.Y, dir.Z
	local bestT, bestPart, bestN = huge, nil, nil
	local nc = gatherRay(ox, oz, dx, dz, inflate or 0, candBuf)
	for ci = 1, nc do
		local part = candBuf[ci]
		candBuf[ci] = nil
		local d = DATA[part]
		local pr = d.props
		-- physics probes collide on CanCollide alone (CanQuery only affects spatial queries)
		local eligible
		if params and params.EBPhysics then
			eligible = pr.CanCollide
		else
			eligible = pr.CanQuery and (not respect or pr.CanCollide)
		end
		if R.parts[part] and eligible then
			if rayAabb(aabb(d), ox, oy, oz, dx, dy, dz, inflate) and passes(part, set, mode) then
				local t, n = rayPart(d, origin, dir, inflate)
				if t and t < bestT then
					bestT, bestPart, bestN = t, part, n
				end
			end
		end
	end
	-- terrain regions
	if R.terrain and (not set or passes(R.terrain, set, mode)) then
		for _, reg in ipairs(R.terrainRegions) do
			if not (ignoreWater and reg.material == R.Enum.Material.Water) then
				local t, n = rayPart(reg.d, origin, dir, inflate)
				if t and t < bestT then
					bestT, bestPart, bestN = t, R.terrain, n
					R.lastTerrainMaterial = reg.material
				end
			end
		end
	end
	if not bestPart then
		return nil
	end
	local material = bestPart == R.terrain and R.lastTerrainMaterial or DATA[bestPart].props.Material
	local pos = v3(ox + dx * bestT, oy + dy * bestT, oz + dz * bestT)
	return setmetatable({ Instance = bestPart, Position = pos, Normal = bestN, Distance = dir.Magnitude * bestT, Material = material }, RRMT)
end
R.cast = cast

-- RaycastParams / OverlapParams datatypes
local RPMT = {}
R.TYPE[RPMT] = "RaycastParams"
RPMT.__index = { AddToFilter = function(self, x)
	local l = self.FilterDescendantsInstances
	if type(x) == "table" and not DATA[x] then
		for _, y in ipairs(x) do
			l[#l + 1] = y
		end
	else
		l[#l + 1] = x
	end
end }
R.RaycastParams = { new = function()
	return setmetatable({ FilterType = R.Enum.RaycastFilterType.Exclude, FilterDescendantsInstances = {}, IgnoreWater = false, CollisionGroup = "Default", RespectCanCollide = false, BruteForceAllSlow = false }, RPMT)
end }
local OPMT = {}
R.TYPE[OPMT] = "OverlapParams"
OPMT.__index = RPMT.__index
R.OverlapParams = { new = function()
	return setmetatable({ FilterType = R.Enum.RaycastFilterType.Exclude, FilterDescendantsInstances = {}, CollisionGroup = "Default", RespectCanCollide = false, MaxParts = 0, BruteForceAllSlow = false }, OPMT)
end }

-- OBB overlap (SAT)
local function obbOverlap(c1, s1, c2, s2)
	local A = { v3(c1[4], c1[7], c1[10]), v3(c1[5], c1[8], c1[11]), v3(c1[6], c1[9], c1[12]) }
	local B = { v3(c2[4], c2[7], c2[10]), v3(c2[5], c2[8], c2[11]), v3(c2[6], c2[9], c2[12]) }
	local ea = { s1.X / 2, s1.Y / 2, s1.Z / 2 }
	local eb = { s2.X / 2, s2.Y / 2, s2.Z / 2 }
	local T = v3(c2[1] - c1[1], c2[2] - c1[2], c2[3] - c1[3])
	local axes = {}
	for i = 1, 3 do
		axes[#axes + 1] = A[i]
		axes[#axes + 1] = B[i]
		for j = 1, 3 do
			local cr = A[i]:Cross(B[j])
			if cr.Magnitude > 1e-6 then
				axes[#axes + 1] = cr.Unit
			end
		end
	end
	for _, L in ipairs(axes) do
		local ra = ea[1] * abs(A[1]:Dot(L)) + ea[2] * abs(A[2]:Dot(L)) + ea[3] * abs(A[3]:Dot(L))
		local rb = eb[1] * abs(B[1]:Dot(L)) + eb[2] * abs(B[2]:Dot(L)) + eb[3] * abs(B[3]:Dot(L))
		if abs(T:Dot(L)) > ra + rb then
			return false
		end
	end
	return true
end
R.obbOverlap = obbOverlap

local function overlapBox(cf, size, params)
	local set, mode = filterSet(params)
	local out = {}
	local probe = { cf = cf, props = { Size = size } }
	local a = aabb(probe)
	local nc = gatherRect(a[1], a[3], a[4], a[6], candBuf)
	for ci = 1, nc do
		local part = candBuf[ci]
		candBuf[ci] = nil
		local d = DATA[part]
		if R.parts[part] and d.props.CanQuery and (not (params and params.RespectCanCollide) or d.props.CanCollide) then
			local b = aabb(d)
			if not (b[1] > a[4] or b[4] < a[1] or b[2] > a[5] or b[5] < a[2] or b[3] > a[6] or b[6] < a[3]) and passes(part, set, mode) then
				if obbOverlap(cf, size, d.cf, d.props.Size) then
					out[#out + 1] = part
				end
			end
		end
	end
	return out
end
R.overlapBox = overlapBox

local WS = R.CLASSES.Workspace.M
function WS.Raycast(self, origin, dir, params)
	return cast(origin, dir, params, 0)
end
function WS.Spherecast(self, origin, radius, dir, params)
	local r = cast(origin, dir, params, radius)
	if r then
		rawset(r, "Position", origin + dir * (r.Distance / dir.Magnitude))
	end
	return r
end
function WS.Blockcast(self, cf, size, dir, params)
	return cast(cf.Position, dir, params, math.min(size.X, size.Y, size.Z) / 2)
end
function WS.Shapecast(self, part, dir, params)
	return cast(part.Position, dir, params, 1)
end
function WS.GetPartBoundsInBox(self, cf, size, params)
	return overlapBox(cf, size, params)
end
function WS.GetPartBoundsInRadius(self, pos, r, params)
	return overlapBox(CFrame.new(pos), v3(r * 2, r * 2, r * 2), params)
end
function WS.GetPartsInPart(self, part, params)
	return overlapBox(part.CFrame, part.Size, params)
end
function WS.FindPartOnRay() error("FindPartOnRay is deprecated; use Raycast", 2) end

---------------------------------------------------------------- terrain
R.terrainRegions = {}
local TM = R.CLASSES.Terrain.M
function TM.FillBlock(self, cf, size, material)
	table.insert(R.terrainRegions, { d = { cf = cf, props = { Size = size, Shape = nil }, cls = { name = "Part" } }, material = material, shape = "Block" })
end
function TM.FillBall(self, center, r, material)
	table.insert(R.terrainRegions, { d = { cf = CFrame.new(center), props = { Size = v3(r * 2, r * 2, r * 2), Shape = R.Enum.PartType.Ball }, cls = { name = "Part" } }, material = material, shape = "Ball" })
end
function TM.FillCylinder(self, cf, height, r, material)
	table.insert(R.terrainRegions, { d = { cf = cf * CFrame.Angles(0, 0, math.pi / 2), props = { Size = v3(height, r * 2, r * 2), Shape = R.Enum.PartType.Cylinder }, cls = { name = "Part" } }, material = material, shape = "Cylinder" })
end
function TM.FillWedge(self, cf, size, material)
	TM.FillBlock(self, cf, size, material)
end
function TM.Clear()
	R.terrainRegions = {}
end
function TM.ReplaceMaterial() end
function TM.SetMaterialColor() end
function TM.GetMaterialColor()
	return R.c3(0.5, 0.5, 0.5)
end

---------------------------------------------------------------- BasePart methods
local BP = R.CLASSES.BasePart.M
for _, cls in pairs(R.CLASSES) do
	if R.classIsA(cls, "BasePart") then
		local M = cls.M
		M.SetNetworkOwner = function(self, p)
			DATA[self].owner = p
		end
		M.GetNetworkOwner = function(self)
			return DATA[self].owner
		end
		M.SetNetworkOwnershipAuto = function() end
		M.CanSetNetworkOwnership = function()
			return true
		end
		M.GetMass = function(self)
			return self.Mass
		end
		M.ApplyImpulse = function(self, imp)
			self.AssemblyLinearVelocity = self.AssemblyLinearVelocity + imp / math.max(1, self.Mass)
		end
		M.ApplyAngularImpulse = function() end
		M.GetTouchingParts = function(self)
			return overlapBox(self.CFrame, self.Size + v3(0.1, 0.1, 0.1), nil)
		end
		M.GetConnectedParts = function(self)
			return { self }
		end
		M.BreakJoints = function() end
		M.GetJoints = function()
			return {}
		end
		M.GetRootPart = function(self)
			return self
		end
		M.SubtractAsync = function()
			error("CSG is not supported in the harness", 2)
		end
		M.UnionAsync = M.SubtractAsync
		M.GetPivot = function(self)
			return self.CFrame
		end
		M.PivotTo = function(self, cf)
			self.CFrame = cf
		end
	end
end

---------------------------------------------------------------- Model methods
local MM = R.CLASSES.Model.M
local function modelParts(model)
	local out = {}
	for _, x in ipairs(R.descendants(model, {})) do
		if isPart(x) then
			out[#out + 1] = x
		end
	end
	return out
end
R.modelParts = modelParts
local function boundingBox(model)
	local parts = modelParts(model)
	if #parts == 0 then
		return CFrame.identity, v3(0, 0, 0)
	end
	local mn = { huge, huge, huge }
	local mx = { -huge, -huge, -huge }
	for _, p in ipairs(parts) do
		local a = aabb(DATA[p])
		for i = 1, 3 do
			mn[i] = min(mn[i], a[i])
			mx[i] = max(mx[i], a[i + 3])
		end
	end
	return CFrame.new((mn[1] + mx[1]) / 2, (mn[2] + mx[2]) / 2, (mn[3] + mx[3]) / 2), v3(mx[1] - mn[1], mx[2] - mn[2], mx[3] - mn[3])
end
function MM.GetPivot(self)
	local pp = self.PrimaryPart
	if pp then
		return pp.CFrame
	end
	return (boundingBox(self))
end
function MM.PivotTo(self, cf)
	local pivot = MM.GetPivot(self)
	local delta = cf * pivot:Inverse()
	for _, p in ipairs(modelParts(self)) do
		local d = DATA[p]
		d.cf = delta * d.cf
		R.partMoved(p, d)
	end
end
function MM.SetPrimaryPartCFrame(self, cf)
	MM.PivotTo(self, cf)
end
function MM.GetPrimaryPartCFrame(self)
	return MM.GetPivot(self)
end
function MM.GetBoundingBox(self)
	return boundingBox(self)
end
function MM.GetExtentsSize(self)
	local _, s = boundingBox(self)
	return s
end
function MM.MoveTo(self, pos)
	local pivot = MM.GetPivot(self)
	MM.PivotTo(self, pivot.Rotation + pos)
end
function MM.TranslateBy(self, delta)
	MM.PivotTo(self, MM.GetPivot(self) + delta)
end
function MM.GetScale(self)
	return DATA[self].scale or 1
end
function MM.ScaleTo(self, s)
	if type(s) ~= "number" or s <= 0 then
		error("ScaleTo expects a positive number", 2)
	end
	local d = DATA[self]
	local cur = d.scale or 1
	local k = s / cur
	d.scale = s
	local pivot = MM.GetPivot(self)
	for _, p in ipairs(modelParts(self)) do
		local pd = DATA[p]
		local rel = pivot:Inverse() * pd.cf
		pd.cf = pivot * (rel.Rotation + rel.Position * k)
		pd.props.Size = pd.props.Size * k
		R.partMoved(p, pd)
	end
	for _, j in ipairs(R.descendants(self, {})) do
		local jd = DATA[j]
		if jd.cls.name == "Motor6D" or jd.cls.name == "Weld" then
			jd.props.C0 = jd.props.C0.Rotation + jd.props.C0.Position * k
			jd.props.C1 = jd.props.C1.Rotation + jd.props.C1.Position * k
		end
	end
	for _, c in ipairs(R.descendants(self, {})) do
		if DATA[c].cls.name == "Humanoid" then
			DATA[c].props.HipHeight = DATA[c].props.HipHeight * k
		end
	end
end
function MM.BreakJoints() end
function MM.MakeJoints() end

---------------------------------------------------------------- Humanoid
local HM = R.CLASSES.Humanoid.M
function HM.MoveTo(self, pos, part)
	local d = DATA[self]
	if R.typeof(pos) ~= "Vector3" then
		error("MoveTo expects a Vector3", 2)
	end
	d.moveTarget = pos
	d.moveStart = R.now
end
function HM.Move(self, dir, relative)
	local d = DATA[self]
	d.moveTarget = nil
	if relative and R.workspace.CurrentCamera then
		local cam = R.workspace.CurrentCamera.CFrame
		local look = cam.LookVector
		local fl = v3(look.X, 0, look.Z)
		if fl.Magnitude > 1e-3 then
			fl = fl.Unit
			local right = v3(-fl.Z, 0, fl.X)
			dir = right * dir.X + fl * (-dir.Z)
		end
	end
	local f = v3(dir.X, 0, dir.Z)
	d.moveDir = f.Magnitude > 1 and f.Unit or f
end
function HM.ChangeState(self, st)
	local d = DATA[self]
	if st == R.Enum.HumanoidStateType.Jumping then
		d.props.Jump = true
	elseif st == R.Enum.HumanoidStateType.Dead then
		self.Health = 0
	end
end
function HM.GetState(self)
	return DATA[self].state or R.Enum.HumanoidStateType.Running
end
function HM.SetStateEnabled() end
function HM.GetStateEnabled()
	return true
end
function HM.TakeDamage(self, n)
	self.Health = self.Health - n
end
function HM.ApplyDescription() end
function HM.ApplyDescriptionReset() end
function HM.GetAppliedDescription()
	return R.new("HumanoidDescription")
end
function HM.UnequipTools() end
function HM.EquipTool() end
function HM.GetPlayingAnimationTracks()
	return {}
end
function HM.LoadAnimation()
	error("Humanoid:LoadAnimation is deprecated; use Animator", 2)
end
local AM = R.CLASSES.Animator.M
function AM.GetPlayingAnimationTracks()
	return {}
end
function AM.LoadAnimation(self, anim)
	local t = { Length = 1, IsPlaying = false, Speed = 1, Looped = false, Priority = R.Enum.AnimationPriority.Action, TimePosition = 0, WeightCurrent = 0 }
	t.Stopped = R.newSignal("Stopped")
	t.Ended = R.newSignal("Ended")
	t.KeyframeReached = R.newSignal("KeyframeReached")
	function t:Play()
		self.IsPlaying = true
	end
	function t:Stop()
		self.IsPlaying = false
	end
	function t:AdjustSpeed(s)
		self.Speed = s
	end
	function t:AdjustWeight() end
	function t:GetMarkerReachedSignal()
		return R.newSignal("Marker")
	end
	return t
end

---------------------------------------------------------------- R15 rig
local R15 = {
	{ "HumanoidRootPart", v3(2, 2, 1), v3(0, 3, 0) },
	{ "LowerTorso", v3(2, 0.4, 1), v3(0, 2.2, 0), "Root", "HumanoidRootPart", v3(0, 2.2, 0), "Torso" },
	{ "UpperTorso", v3(2, 1.6, 1), v3(0, 3.2, 0), "Waist", "LowerTorso", v3(0, 2.4, 0), "Torso" },
	{ "Head", v3(1.2, 1.2, 1.2), v3(0, 4.6, 0), "Neck", "UpperTorso", v3(0, 4.0, 0), "Head" },
	{ "RightUpperArm", v3(1, 1.1, 1), v3(1.5, 3.3, 0), "RightShoulder", "UpperTorso", v3(1.25, 3.85, 0), "RightArm" },
	{ "RightLowerArm", v3(1, 1.0, 1), v3(1.5, 2.25, 0), "RightElbow", "RightUpperArm", v3(1.5, 2.75, 0), "RightArm" },
	{ "RightHand", v3(1, 0.3, 1), v3(1.5, 1.6, 0), "RightWrist", "RightLowerArm", v3(1.5, 1.75, 0), "RightArm" },
	{ "LeftUpperArm", v3(1, 1.1, 1), v3(-1.5, 3.3, 0), "LeftShoulder", "UpperTorso", v3(-1.25, 3.85, 0), "LeftArm" },
	{ "LeftLowerArm", v3(1, 1.0, 1), v3(-1.5, 2.25, 0), "LeftElbow", "LeftUpperArm", v3(-1.5, 2.75, 0), "LeftArm" },
	{ "LeftHand", v3(1, 0.3, 1), v3(-1.5, 1.6, 0), "LeftWrist", "LeftLowerArm", v3(-1.5, 1.75, 0), "LeftArm" },
	{ "RightUpperLeg", v3(1, 0.85, 1), v3(0.5, 1.575, 0), "RightHip", "LowerTorso", v3(0.5, 2.0, 0), "RightLeg" },
	{ "RightLowerLeg", v3(1, 0.85, 1), v3(0.5, 0.725, 0), "RightKnee", "RightUpperLeg", v3(0.5, 1.15, 0), "RightLeg" },
	{ "RightFoot", v3(1, 0.3, 1), v3(0.5, 0.15, 0), "RightAnkle", "RightLowerLeg", v3(0.5, 0.3, 0), "RightLeg" },
	{ "LeftUpperLeg", v3(1, 0.85, 1), v3(-0.5, 1.575, 0), "LeftHip", "LowerTorso", v3(-0.5, 2.0, 0), "LeftLeg" },
	{ "LeftLowerLeg", v3(1, 0.85, 1), v3(-0.5, 0.725, 0), "LeftKnee", "LeftUpperLeg", v3(-0.5, 1.15, 0), "LeftLeg" },
	{ "LeftFoot", v3(1, 0.3, 1), v3(-0.5, 0.15, 0), "LeftAnkle", "LeftLowerLeg", v3(-0.5, 0.3, 0), "LeftLeg" },
}
function R.buildRig(desc, rigType)
	local model = R.new("Model")
	local colors = {
		Head = desc and desc.HeadColor or R.c3(0.9, 0.75, 0.6),
		Torso = desc and desc.TorsoColor or R.c3(0.3, 0.4, 0.8),
		RightArm = desc and desc.RightArmColor or R.c3(0.9, 0.75, 0.6),
		LeftArm = desc and desc.LeftArmColor or R.c3(0.9, 0.75, 0.6),
		RightLeg = desc and desc.RightLegColor or R.c3(0.2, 0.2, 0.3),
		LeftLeg = desc and desc.LeftLegColor or R.c3(0.2, 0.2, 0.3),
	}
	local parts = {}
	for _, row in ipairs(R15) do
		local p = R.new("MeshPart")
		p.Name = row[1]
		p.Size = row[2]
		p.CFrame = CFrame.new(row[3])
		p.Anchored = false
		if row[1] == "HumanoidRootPart" then
			p.Transparency = 1
			p.CanCollide = false
		else
			p.Color = colors[row[7]]
		end
		p.Parent = model
		parts[row[1]] = p
		if row[4] then
			local m = R.new("Motor6D")
			m.Name = row[4]
			local p0 = parts[row[5]]
			local jw = CFrame.new(row[6])
			m.Part0 = p0
			m.Part1 = p
			m.C0 = p0.CFrame:Inverse() * jw
			m.C1 = p.CFrame:Inverse() * jw
			m.Parent = p
			local a = R.new("Attachment")
			a.Name = row[4] .. "RigAttachment"
			a.CFrame = m.C1
			a.Parent = p
		end
	end
	local function att(part, name, pos)
		local a = R.new("Attachment")
		a.Name = name
		a.Position = pos
		a.Parent = parts[part]
	end
	att("RightHand", "RightGripAttachment", v3(0, -0.15, 0))
	att("LeftHand", "LeftGripAttachment", v3(0, -0.15, 0))
	att("Head", "HairAttachment", v3(0, 0.6, 0))
	att("Head", "FaceFrontAttachment", v3(0, 0, -0.6))
	att("UpperTorso", "BodyFrontAttachment", v3(0, 0, -0.5))
	att("UpperTorso", "BodyBackAttachment", v3(0, 0, 0.5))
	att("HumanoidRootPart", "RootAttachment", v3(0, 0, 0))
	local face = R.new("Decal")
	face.Name = "face"
	face.Parent = parts.Head
	local hum = R.new("Humanoid")
	hum.HipHeight = 2
	hum.RigType = R.Enum.HumanoidRigType.R15
	hum.MaxHealth = 100
	hum.Health = 100
	hum.Parent = model
	local animator = R.new("Animator")
	animator.Parent = hum
	if desc then
		local dc = desc:Clone()
		dc.Parent = hum
	end
	model.PrimaryPart = parts.HumanoidRootPart
	return model
end

---------------------------------------------------------------- camera math
local CM = R.CLASSES.Camera.M
local function camRay(cam, x, y)
	local cf = cam.CFrame
	local W, H = R.viewport.X, R.viewport.Y
	local tanv = math.tan(math.rad(cam.FieldOfView) / 2)
	local nx = (x / W) * 2 - 1
	local ny = 1 - (y / H) * 2
	local dir = (cf.LookVector + cf.RightVector * (nx * tanv * W / H) + cf.UpVector * (ny * tanv)).Unit
	return R.Ray.new(cf.Position, dir)
end
function CM.ViewportPointToRay(self, x, y)
	return camRay(self, x, y)
end
function CM.ScreenPointToRay(self, x, y)
	return camRay(self, x, y + R.guiInset)
end
local function project(cam, p)
	local cf = cam.CFrame
	local l = cf:PointToObjectSpace(p)
	local depth = -l.Z
	local W, H = R.viewport.X, R.viewport.Y
	local tanv = math.tan(math.rad(cam.FieldOfView) / 2)
	if depth <= 0.01 then
		return v3(-1, -1, depth), false
	end
	local x = (l.X / (depth * tanv * W / H) + 1) / 2 * W
	local y = (1 - l.Y / (depth * tanv)) / 2 * H
	return v3(x, y, depth), x >= 0 and x <= W and y >= 0 and y <= H
end
R.project = project
function CM.WorldToViewportPoint(self, p)
	return project(self, p)
end
function CM.WorldToScreenPoint(self, p)
	local v, on = project(self, p)
	return v3(v.X, v.Y - R.guiInset, v.Z), on
end
function CM.GetPartsObscuringTarget()
	return {}
end
function CM.ZoomToExtents() end

---------------------------------------------------------------- simulation step
local CHAR_RADIUS = 1.0
local excludeParams = R.RaycastParams.new()
excludeParams.EBPhysics = true

local function constraintsOf(root)
	local out = {}
	for _, c in ipairs(DATA[root].children) do
		local cd = DATA[c]
		if cd.cls.name == "LinearVelocity" and cd.props.Enabled ~= false then
			out[#out + 1] = c
		end
	end
	return out
end

function R.stepHumanoids(dt)
	local g = R.workspace.Gravity
	for hum in pairs(R.humanoids) do
		local hd = DATA[hum]
		local model = hd.parent
		local root = model and DATA[model] and DATA[model].props.PrimaryPart
		if root == R.NIL then
			root = nil
		end
		root = root or (model and model:FindFirstChild("HumanoidRootPart"))
		if root and DATA[root] and not DATA[root].destroyed and not DATA[root].props.Anchored and R.parts[root] then
			local rd = DATA[root]
			local pos = rd.cf.Position
			local vel = rd.props.AssemblyLinearVelocity
			local dead = hd.dead
			-- MoveTo steering
			if hd.moveTarget and not dead then
				local to = v3(hd.moveTarget.X - pos.X, 0, hd.moveTarget.Z - pos.Z)
				if to.Magnitude < 1.2 then
					hd.moveTarget = nil
					hd.moveDir = v3(0, 0, 0)
					R.fire(R.getSignal(hd, "MoveToFinished"), true)
				elseif R.now - (hd.moveStart or R.now) > 8 then
					hd.moveTarget = nil
					hd.moveDir = v3(0, 0, 0)
					R.fire(R.getSignal(hd, "MoveToFinished"), false)
				else
					hd.moveDir = to.Unit
				end
			end
			local md = (not dead and not hd.props.PlatformStand) and (hd.moveDir or v3(0, 0, 0)) or v3(0, 0, 0)
			local ws = hd.props.WalkSpeed
			local vx, vy, vz = md.X * ws, vel.Y, md.Z * ws
			local grounded = hd.grounded
			if hd.props.Jump then
				hd.props.Jump = false
				local h = hd.props.UseJumpPower and (hd.props.JumpPower ^ 2 / (2 * g)) or hd.props.JumpHeight
				if grounded and h > 0 and not dead then
					vy = sqrt(2 * g * h)
					grounded = false
					hd.state = R.Enum.HumanoidStateType.Jumping
					R.fire(R.getSignal(hd, "Jumping"), true)
				end
			end
			if not grounded then
				vy = vy - g * dt
			end
			-- constraints override
			local lineDir, lineVel
			for _, c in ipairs(constraintsOf(root)) do
				local cd = DATA[c]
				local mode = cd.props.VelocityConstraintMode.Name
				if mode == "Vector" then
					local vv = cd.props.VectorVelocity
					vx, vy, vz = vv.X, vv.Y, vv.Z
				elseif mode == "Line" then
					lineDir, lineVel = cd.props.LineDirection.Unit, cd.props.LineVelocity
					local cur = vx * lineDir.X + vy * lineDir.Y + vz * lineDir.Z
					local dv = lineVel - cur
					vx, vy, vz = vx + lineDir.X * dv, vy + lineDir.Y * dv, vz + lineDir.Z * dv
				end
			end
			excludeParams.FilterDescendantsInstances = { model }
			excludeParams.RespectCanCollide = true
			-- horizontal move with wall sliding
			local hv = v3(vx, 0, vz) * dt
			for _ = 1, 2 do
				local len = hv.Magnitude
				if len < 1e-6 then
					break
				end
				local dir = hv / len
				local bestDist, bestN = huge, nil
				for _, h in ipairs({ -1.3, 0, 1.6 }) do
					local res = cast(pos + v3(0, h, 0), dir * (len + CHAR_RADIUS), excludeParams, 0)
					if res and res.Distance < bestDist then
						-- ignore walkable slopes for the lowest probe
						if not (h < -1 and res.Normal.Y > 0.6) then
							bestDist, bestN = res.Distance, res.Normal
						end
					end
				end
				if bestN then
					local allowed = math.max(0, bestDist - CHAR_RADIUS)
					pos = pos + dir * math.min(allowed, len)
					local rem = hv - dir * math.min(allowed, len)
					local n = v3(bestN.X, 0, bestN.Z)
					if n.Magnitude > 1e-3 then
						n = n.Unit
						rem = rem - n * rem:Dot(n)
					end
					hv = rem
				else
					pos = pos + hv
					hv = v3(0, 0, 0)
				end
			end
			-- vertical
			local rootHalf = rd.props.Size.Y / 2
			local hip = hd.props.HipHeight
			local stand = hip + rootHalf
			local landed = false
			if vy <= 0 then
				local probe = stand + math.max(0, -vy * dt) + (grounded and 1.1 or 0.05)
				local res = cast(pos + v3(0, 1.0, 0), v3(0, -(probe + 1.0), 0), excludeParams, 0)
				if res then
					local target = res.Position.Y + stand
					if target - pos.Y <= 2.3 then
						pos = v3(pos.X, target, pos.Z)
						if not grounded then
							landed = true
						end
						grounded = true
						vy = 0
						hd.floorMaterial = res.Material
						hd.floorPart = res.Instance
					else
						grounded = false
					end
				else
					grounded = false
					pos = pos + v3(0, vy * dt, 0)
				end
			else
				local res = cast(pos, v3(0, 2.6 + vy * dt, 0), excludeParams, 0)
				if res then
					vy = 0
				else
					pos = pos + v3(0, vy * dt, 0)
				end
				grounded = false
			end
			if not grounded then
				hd.floorMaterial = R.Enum.Material.Air
				hd.floorPart = nil
				if hd.state ~= R.Enum.HumanoidStateType.Freefall and vy < 0 then
					hd.state = R.Enum.HumanoidStateType.Freefall
					R.fire(R.getSignal(hd, "FreeFalling"), true)
				end
			elseif landed then
				hd.state = R.Enum.HumanoidStateType.Landed
				R.fire(R.getSignal(hd, "StateChanged"), R.Enum.HumanoidStateType.Freefall, R.Enum.HumanoidStateType.Landed)
			end
			hd.grounded = grounded
			-- auto-rotate toward movement
			local rot = rd.cf.Rotation
			if hd.props.AutoRotate and md.Magnitude > 0.1 and not dead then
				rot = CFrame.lookAt(v3(0, 0, 0), v3(md.X, 0, md.Z)).Rotation
			end
			rd.cf = rot + pos
			rd.aabb = nil
			rd.props.AssemblyLinearVelocity = v3((pos.X - rd.lastPos.X) / dt, vy, (pos.Z - rd.lastPos.Z) / dt)
			if pos.Y < R.workspace.FallenPartsDestroyHeight then
				R.destroy(model)
			end
		end
		if root and DATA[root] then
			DATA[root].lastPos = DATA[root].cf.Position
		end
	end
end
-- initialise lastPos lazily
setmetatable(R.DATA, { __mode = "k" })
local origStep = R.stepHumanoids
R.stepHumanoids = function(dt)
	for hum in pairs(R.humanoids) do
		local model = DATA[hum].parent
		local root = model and model:FindFirstChild("HumanoidRootPart")
		if root and not DATA[root].lastPos then
			DATA[root].lastPos = DATA[root].cf.Position
		end
	end
	origStep(dt)
end

-- free unanchored parts (no joints, not part of a character): fall under gravity
function R.stepFreeParts(dt)
	local jointed = {}
	for j in pairs(R.joints) do
		local jd = DATA[j]
		local p1 = jd.props.Part1
		if p1 ~= R.NIL and p1 then
			jointed[p1] = true
		end
	end
	for part in pairs(R.parts) do
		local d = DATA[part]
		if not d.props.Anchored and not jointed[part] then
			local m = d.parent
			local isChar = m and DATA[m] and m:FindFirstChildOfClass("Humanoid")
			if not isChar then
				local v = d.props.AssemblyLinearVelocity
				local vy = v.Y - R.workspace.Gravity * dt
				local pos = d.cf.Position
				local res = cast(pos, v3(0, vy * dt - d.props.Size.Y / 2, 0), (function()
					local p = R.RaycastParams.new()
					p.FilterDescendantsInstances = { part }
					p.RespectCanCollide = true
					return p
				end)(), 0)
				if res and vy < 0 then
					d.cf = d.cf.Rotation + v3(pos.X, res.Position.Y + d.props.Size.Y / 2, pos.Z)
					d.props.AssemblyLinearVelocity = v3(0, 0, 0)
				else
					d.cf = d.cf + v3(v.X * dt, vy * dt, v.Z * dt)
					d.props.AssemblyLinearVelocity = v3(v.X, vy, v.Z)
				end
				R.partMoved(part, d)
				if d.cf.Y < R.workspace.FallenPartsDestroyHeight then
					R.destroy(part)
				end
			end
		end
	end
end

-- joint solve: propagate CFrames from anchored/root parts through joints
function R.assemblyRoot(part)
	return part
end
function R.solveJoints()
	local solved = {}
	for part in pairs(R.parts) do
		if DATA[part].props.Anchored then
			solved[part] = true
		end
	end
	for hum in pairs(R.humanoids) do
		local model = DATA[hum].parent
		local root = model and model:FindFirstChild("HumanoidRootPart")
		if root then
			solved[root] = true
		end
	end
	local pending = {}
	for j in pairs(R.joints) do
		local jd = DATA[j]
		if jd.props.Enabled ~= false then
			pending[#pending + 1] = j
		end
	end
	local progress = true
	local guard = 0
	while progress and #pending > 0 and guard < 30 do
		guard = guard + 1
		progress = false
		local rest = {}
		for _, j in ipairs(pending) do
			local jd = DATA[j]
			local p0, p1 = jd.props.Part0, jd.props.Part1
			if p0 == R.NIL then
				p0 = nil
			end
			if p1 == R.NIL then
				p1 = nil
			end
			if not p0 or not p1 or not DATA[p0] or not DATA[p1] or DATA[p0].destroyed or DATA[p1].destroyed then
				-- dangling joint: ignore
			else
				local cn = jd.cls.name
				local rel
				if cn == "WeldConstraint" then
					if not jd.offset then
						jd.offset = DATA[p0].cf:Inverse() * DATA[p1].cf
					end
					rel = jd.offset
				elseif cn == "Motor6D" then
					rel = jd.props.C0 * jd.props.Transform * jd.props.C1:Inverse()
				else
					rel = jd.props.C0 * jd.props.C1:Inverse()
				end
				if solved[p0] and not solved[p1] then
					if not DATA[p1].props.Anchored then
						DATA[p1].cf = DATA[p0].cf * rel
						DATA[p1].aabb = nil
					end
					solved[p1] = true
					progress = true
				elseif solved[p1] and not solved[p0] then
					if not DATA[p0].props.Anchored then
						DATA[p0].cf = DATA[p1].cf * rel:Inverse()
						DATA[p0].aabb = nil
					end
					solved[p0] = true
					progress = true
				elseif not solved[p0] and not solved[p1] then
					rest[#rest + 1] = j
				end
			end
		end
		pending = rest
	end
end
