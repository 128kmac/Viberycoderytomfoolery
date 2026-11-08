-- Registry of telegraphed hazards (pending AoEs, line strikes) so bots can read the same warnings players
-- see. Entries carry their real affected shape and the time of impact. Damaging zones and projectiles are
-- queried live from Zones/Proj.
local S = require(script.Parent.S)

local Danger = {}
S.Danger = Danger

local list = {}
local nextId = 0
Danger.list = list

--[[ entry: shape "circle" | "line", pos (ground), radius | dir, length, width, t1 (impact time), owner ]]
function Danger.add(e)
	nextId += 1
	e.id = nextId
	e.t0 = S.now()
	e.t1 = e.t1 or (e.t0 + 1)
	list[nextId] = e
	return nextId
end

function Danger.remove(id)
	if id then
		list[id] = nil
	end
end

local function contains(e, p, margin)
	if e.shape == "line" then
		local d = Vector3.new(e.dir.X, 0, e.dir.Z)
		if d.Magnitude < 1e-3 then
			return false
		end
		d = d.Unit
		local rel = Vector3.new(p.X - e.pos.X, 0, p.Z - e.pos.Z)
		local along = rel:Dot(d)
		local side = math.abs(rel:Dot(Vector3.new(-d.Z, 0, d.X)))
		return along >= -margin and along <= e.length + margin and side <= e.width / 2 + margin
	end
	local dx, dz = p.X - e.pos.X, p.Z - e.pos.Z
	return math.sqrt(dx * dx + dz * dz) <= e.radius + margin and math.abs(p.Y - e.pos.Y) < 12
end

-- escape direction (flat unit vector) out of an entry for a point inside it
local function escape(e, p)
	if e.shape == "line" then
		local d = Vector3.new(e.dir.X, 0, e.dir.Z).Unit
		local n = Vector3.new(-d.Z, 0, d.X)
		local rel = Vector3.new(p.X - e.pos.X, 0, p.Z - e.pos.Z)
		return rel:Dot(n) >= 0 and n or -n
	end
	local rel = Vector3.new(p.X - e.pos.X, 0, p.Z - e.pos.Z)
	if rel.Magnitude < 0.2 then
		local a = math.random() * math.pi * 2
		return Vector3.new(math.cos(a), 0, math.sin(a))
	end
	return rel.Unit
end

-- Worst threat to fighter f at position p (defaults to f's position). Returns
-- { timeLeft, escapeDir, distanceOut, source } or nil. `noticeDelay` hides hazards younger than the bot's
-- reaction time.
function Danger.threat(f, p, noticeDelay, margin)
	p = p or f.root.Position
	margin = margin or 1.5
	local now = S.now()
	local worst
	for id, e in pairs(list) do
		if now > e.t1 + 0.25 then
			list[id] = nil
		elseif now - e.t0 >= (noticeDelay or 0) and (e.owner == nil or S.isEnemy(e.owner, f)) and contains(e, p, margin) then
			local tl = e.t1 - now
			if not worst or tl < worst.timeLeft then
				local out
				if e.shape == "line" then
					out = e.width / 2 + margin + 1
				else
					local dx, dz = p.X - e.pos.X, p.Z - e.pos.Z
					out = e.radius + margin + 1 - math.sqrt(dx * dx + dz * dz)
				end
				worst = { timeLeft = tl, escapeDir = escape(e, p), distanceOut = math.max(1, out), source = e }
			end
		end
	end
	-- harmful enemy fields
	for _, z in pairs(S.Zones.list) do
		if z.alive and z.harmful and z.owner and S.isEnemy(z.owner, f) and z:containsPoint(p, margin) then
			if not worst then
				local dir
				if z.shape == "rect" then
					local d = z.dir
					local n = Vector3.new(-d.Z, 0, d.X)
					local rel = Vector3.new(p.X - z.pos.X, 0, p.Z - z.pos.Z)
					dir = rel:Dot(n) >= 0 and n or -n
				else
					local rel = Vector3.new(p.X - z.pos.X, 0, p.Z - z.pos.Z)
					dir = rel.Magnitude > 0.2 and rel.Unit or Vector3.new(1, 0, 0)
				end
				worst = { timeLeft = 0.5, escapeDir = dir, distanceOut = z.radius + 2, source = z, field = true }
			end
		end
	end
	return worst
end

-- is a point unsafe for f (used to penalise path nodes)
function Danger.unsafe(f, p)
	return Danger.threat(f, p, 0, 0.5) ~= nil
end

-- the most urgent enemy projectile on a collision course with f within `horizon` seconds
function Danger.incoming(f, horizon)
	local pos = f.root.Position
	local best, bt
	for _, p in pairs(S.Proj.list) do
		if p.alive and p.owner and S.isEnemy(p.owner, f) then
			local rel = pos - p.pos
			local v = p.vel
			local sp = v.Magnitude
			if sp > 1 then
				local t = rel:Dot(v) / (sp * sp)
				if t > 0 and t < horizon then
					local closest = (p.pos + v * t - pos).Magnitude
					if closest < p.radius + 2.2 and (not bt or t < bt) then
						best, bt = p, t
					end
				end
			end
		end
	end
	return best, bt
end

return Danger
