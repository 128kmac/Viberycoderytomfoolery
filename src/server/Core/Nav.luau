-- Navigation graph for bots, generated from the arena geometry at startup.
-- Columns on a CELL grid are probed top-down for walkable surfaces (several levels per column);
-- neighbouring nodes are linked as walk, jump-up or drop-down edges after clearance checks.
-- A* over the graph gives bots routes around cover, up ramps and across bridges.
local S = require(script.Parent.S)

local Nav = {}
S.Nav = Nav

local CELL = 6
local MAX_STEP = 1.6 -- walkable height change between neighbours (studs)
local MAX_JUMP = 5.0 -- jump-up edge limit (JumpHeight is 6 studs)
local MAX_DROP = 26
local BODY_H = 5

Nav.nodes = {}
Nav.ready = false
local buckets = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.RespectCanCollide = true
rayParams.IgnoreWater = true

local boxParams = OverlapParams.new()
boxParams.FilterType = Enum.RaycastFilterType.Include
boxParams.RespectCanCollide = true

local function key(i, j)
	return i * 4096 + j
end

local function cellOf(pos)
	return math.floor(pos.X / CELL + 0.5), math.floor(pos.Z / CELL + 0.5)
end

local function halfHeight(part)
	local cf, sz = part.CFrame, part.Size
	local r = cf.RightVector
	local u = cf.UpVector
	local l = cf.LookVector
	return math.abs(r.Y) * sz.X / 2 + math.abs(u.Y) * sz.Y / 2 + math.abs(l.Y) * sz.Z / 2
end

local function clearance(p)
	local parts = workspace:GetPartBoundsInBox(CFrame.new(p + Vector3.new(0, 0.6 + BODY_H / 2, 0)), Vector3.new(2.2, BODY_H, 2.2), boxParams)
	return #parts == 0
end

local function lineClear(a, b, h)
	local o = a + Vector3.new(0, h, 0)
	local d = (b + Vector3.new(0, h, 0)) - o
	if d.Magnitude < 0.01 then
		return true
	end
	return workspace:Raycast(o, d, rayParams) == nil
end

local function groundAt(pos, maxDown)
	local res = workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -(maxDown + 2), 0), rayParams)
	return res and res.Position or nil
end

-- build(bounds): bounds = { center = Vector3, half = studs, floorY = y, top = y }
function Nav.build(bounds, roots)
	Nav.ready = false
	table.clear(Nav.nodes)
	table.clear(buckets)
	rayParams.FilterDescendantsInstances = roots or { S.folders.Arena }
	boxParams.FilterDescendantsInstances = roots or { S.folders.Arena }
	local c = bounds.center
	local half = bounds.half
	local top = bounds.top or (bounds.floorY + 90)
	local bottom = bounds.floorY - 25
	local nodes = Nav.nodes
	local i0, j0 = math.floor((c.X - half) / CELL), math.floor((c.Z - half) / CELL)
	local i1, j1 = math.ceil((c.X + half) / CELL), math.ceil((c.Z + half) / CELL)
	local probes = 0
	for i = i0, i1 do
		for j = j0, j1 do
			local x, z = i * CELL, j * CELL
			local y = top
			for _ = 1, 5 do
				local res = workspace:Raycast(Vector3.new(x, y, z), Vector3.new(0, bottom - y, 0), rayParams)
				if not res then
					break
				end
				local p = res.Position
				if res.Normal.Y > 0.72 and clearance(p) then
					local n = { id = #nodes + 1, pos = p, edges = {}, i = i, j = j }
					nodes[n.id] = n
					local k = key(i, j)
					buckets[k] = buckets[k] or {}
					table.insert(buckets[k], n)
				end
				-- continue below the part that was hit
				local inst = res.Instance
				local below = inst.Position.Y - halfHeight(inst) - 0.05
				y = math.min(p.Y - 0.05, below)
				if y <= bottom then
					break
				end
			end
			probes += 1
			if probes % 300 == 0 then
				task.wait()
			end
		end
	end
	-- edges
	local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
	for idx, a in ipairs(nodes) do
		for _, d in ipairs(DIRS) do
			local list = buckets[key(a.i + d[1], a.j + d[2])]
			if list then
				for _, b in ipairs(list) do
					local dy = b.pos.Y - a.pos.Y
					local kind
					if math.abs(dy) <= MAX_STEP then
						kind = "walk"
					elseif dy > MAX_STEP and dy <= MAX_JUMP then
						kind = "jump"
					elseif dy < -MAX_STEP and dy >= -MAX_DROP then
						kind = "drop"
					end
					if kind then
						local hi = math.max(a.pos.Y, b.pos.Y)
						local ah = Vector3.new(a.pos.X, hi, a.pos.Z)
						local bh = Vector3.new(b.pos.X, hi, b.pos.Z)
						local ok = lineClear(ah, bh, 2.4) and lineClear(ah, bh, 4.4)
						if ok and kind == "walk" then
							-- no gap between the two cells
							local mid = (a.pos + b.pos) / 2
							local g = groundAt(mid + Vector3.new(0, 1, 0), 3.5)
							ok = g ~= nil
						end
						if ok and kind == "jump" then
							ok = lineClear(a.pos + Vector3.new(0, 1, 0), a.pos + Vector3.new(0, 7, 0), 0)
						end
						if ok then
							local dist = (b.pos - a.pos).Magnitude
							local cost = dist * (kind == "jump" and 1.6 or kind == "drop" and 1.1 or 1)
							table.insert(a.edges, { to = b.id, cost = cost, kind = kind })
						end
					end
				end
			end
		end
		if idx % 250 == 0 then
			task.wait()
		end
	end
	-- prune islands smaller than 6 nodes (pillar tops, ledges) from start-node lookup
	local comp = {}
	local sizes = {}
	local cid = 0
	for _, n in ipairs(nodes) do
		if not comp[n.id] then
			cid += 1
			local stack = { n.id }
			comp[n.id] = cid
			local size = 0
			while #stack > 0 do
				local cur = table.remove(stack)
				size += 1
				for _, e in ipairs(nodes[cur].edges) do
					if not comp[e.to] then
						comp[e.to] = cid
						table.insert(stack, e.to)
					end
				end
			end
			sizes[cid] = size
		end
	end
	for _, n in ipairs(nodes) do
		n.comp = comp[n.id]
		n.major = sizes[n.comp] >= 6
	end
	Nav.ready = true
	workspace:SetAttribute("NavNodes", #nodes)
	return #nodes
end

-- nearest node to a position (prefers nodes with a clear line and similar height)
function Nav.nearest(pos, maxDist)
	maxDist = maxDist or 18
	local ci, cj = cellOf(pos)
	local best, bd
	local r = math.ceil(maxDist / CELL)
	for di = -r, r do
		for dj = -r, r do
			local list = buckets[key(ci + di, cj + dj)]
			if list then
				for _, n in ipairs(list) do
					if n.major then
						local dv = n.pos - pos
						local d = Vector3.new(dv.X, 0, dv.Z).Magnitude + math.abs(dv.Y) * 2.5
						if d < maxDist and (not bd or d < bd) then
							best, bd = n, d
						end
					end
				end
			end
		end
	end
	return best
end

-- binary heap keyed by f-score
local function push(heap, item, score)
	table.insert(heap, { item, score })
	local i = #heap
	while i > 1 do
		local p = i // 2
		if heap[p][2] <= heap[i][2] then
			break
		end
		heap[p], heap[i] = heap[i], heap[p]
		i = p
	end
end
local function pop(heap)
	local top = heap[1]
	local last = table.remove(heap)
	if #heap > 0 then
		heap[1] = last
		local i = 1
		local n = #heap
		while true do
			local l, r = i * 2, i * 2 + 1
			local m = i
			if l <= n and heap[l][2] < heap[m][2] then
				m = l
			end
			if r <= n and heap[r][2] < heap[m][2] then
				m = r
			end
			if m == i then
				break
			end
			heap[m], heap[i] = heap[i], heap[m]
			i = m
		end
	end
	return top[1]
end

-- A* path between positions; costFn(node) may add penalties (danger, exposure). Returns list of nodes.
function Nav.path(fromPos, toPos, costFn, maxExpand)
	if not Nav.ready then
		return nil
	end
	local a = Nav.nearest(fromPos)
	local b = Nav.nearest(toPos, 30)
	if not a or not b then
		return nil
	end
	if a.comp ~= b.comp then
		return nil
	end
	local nodes = Nav.nodes
	local g = { [a.id] = 0 }
	local came = {}
	local closed = {}
	local heap = {}
	push(heap, a.id, (b.pos - a.pos).Magnitude)
	local expanded = 0
	maxExpand = maxExpand or 1500
	while #heap > 0 do
		local cur = pop(heap)
		if cur == b.id then
			local out = {}
			local x = cur
			while x do
				table.insert(out, 1, nodes[x])
				x = came[x]
			end
			return out
		end
		if not closed[cur] then
			closed[cur] = true
			expanded += 1
			if expanded > maxExpand then
				return nil
			end
			local cn = nodes[cur]
			for _, e in ipairs(cn.edges) do
				if not closed[e.to] then
					local extra = costFn and costFn(nodes[e.to]) or 0
					local ng = g[cur] + e.cost + extra
					if g[e.to] == nil or ng < g[e.to] then
						g[e.to] = ng
						came[e.to] = cur
						push(heap, e.to, ng + (b.pos - nodes[e.to].pos).Magnitude)
					end
				end
			end
		end
	end
	return nil
end

-- the edge kind between two consecutive path nodes
function Nav.edgeKind(a, b)
	for _, e in ipairs(a.edges) do
		if e.to == b.id then
			return e.kind
		end
	end
	return "walk"
end

-- random reachable node within a radius band of a point (for flanking / repositioning)
function Nav.randomNear(pos, minR, maxR, filter)
	local ci, cj = cellOf(pos)
	local r = math.ceil(maxR / CELL)
	local cands = {}
	for di = -r, r do
		for dj = -r, r do
			local list = buckets[key(ci + di, cj + dj)]
			if list then
				for _, n in ipairs(list) do
					local d = (n.pos - pos).Magnitude
					if n.major and d >= minR and d <= maxR and (not filter or filter(n)) then
						table.insert(cands, n)
					end
				end
			end
		end
	end
	if #cands == 0 then
		return nil
	end
	return cands[math.random(1, #cands)]
end

function Nav.walkableLine(a, b)
	return lineClear(a, b, 2.4) and lineClear(a, b, 4.4)
end

return Nav
