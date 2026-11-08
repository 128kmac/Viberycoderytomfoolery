-- Persistent fields (circles, rectangles, rings). Tick clocks never restart when a zone moves.
local Debris = game:GetService("Debris")
local S = require(script.Parent.S)

local Zones = {}
S.Zones = Zones

local list = {}
local nextId = 0
Zones.list = list

local Zone = {}
Zone.__index = Zone

--[[ opts:
	owner, cast, pos (studs, ground point), radius, shape ("circle" | "rect" | "ring"), width, length, dir (rect),
	inner (ring), duration, tick (default 1), immediate (first tick at once), targets ("enemies"|"allies"|"all"|fn),
	onTick(zone, list), onEnter(zone, f), onExit(zone, f), onEnd(zone), color, transparency, element,
	above (height studs), follow (fighter), noVisual, tags, data, includeOwner
]]
function Zones.create(opts)
	nextId += 1
	local now = S.now()
	local z = setmetatable({
		id = nextId,
		owner = opts.owner,
		cast = opts.cast,
		pos = opts.pos,
		radius = opts.radius or S.m(3),
		shape = opts.shape or "circle",
		width = opts.width,
		length = opts.length,
		dir = opts.dir and Vector3.new(opts.dir.X, 0, opts.dir.Z).Unit or Vector3.new(0, 0, -1),
		inner = opts.inner or 0,
		expires = now + (opts.duration or 5),
		tick = opts.tick or S.Config.FIELD_TICK,
		nextTick = opts.immediate and now or (now + (opts.tick or S.Config.FIELD_TICK)),
		targetMode = opts.targets or "enemies",
		onTick = opts.onTick,
		onEnter = opts.onEnter,
		onExit = opts.onExit,
		onEnd = opts.onEnd,
		element = opts.element or (opts.owner and opts.owner.kitName),
		above = opts.above or S.m(4),
		follow = opts.follow,
		inside = {},
		entered = {},
		alive = true,
		tags = opts.tags or {},
		data = opts.data or {},
		includeOwner = opts.includeOwner,
		created = now,
		color = opts.color or (opts.owner and S.Util.color(opts.owner.kitName)) or Color3.new(1, 1, 1),
	}, Zone)
	if not opts.noVisual then
		z:buildVisual(opts.transparency)
	end
	list[z.id] = z
	if opts.owner then
		table.insert(opts.owner.zones, z)
	end
	return z
end

function Zone:buildVisual(transparency)
	if self.visual then
		self.visual:Destroy()
	end
	local tr = transparency or 0.65
	if self.shape == "rect" then
		local mid = self.pos + self.dir * (self.length / 2)
		self.visual = S.FX.rect(CFrame.lookAt(mid, mid + self.dir), self.width, self.length, nil, self.color, tr)
	else
		self.visual = S.FX.disc(self.pos + Vector3.new(0, 0.05, 0), self.radius, self.color, nil, tr, 0.2)
	end
	if self.shape == "ring" and self.inner > 0 then
		local hole = S.FX.disc(self.pos + Vector3.new(0, 0.12, 0), self.inner, Color3.new(0, 0, 0), nil, 0.85, 0.22)
		hole.Parent = self.visual
	end
end

function Zone:contains(f)
	return self:containsPoint(f.root.Position)
end

function Zone:containsPoint(p, margin)
	margin = margin or 0.8
	if p.Y > self.pos.Y + self.above + S.Config.BODY_DOWN or p.Y < self.pos.Y - S.m(2) then
		return false
	end
	if self.shape == "rect" then
		local cf = CFrame.lookAt(self.pos, self.pos + self.dir)
		local lp = cf:PointToObjectSpace(p)
		return math.abs(lp.X) <= self.width / 2 + margin and -lp.Z >= -margin and -lp.Z <= self.length + margin
	end
	local d = Vector3.new(p.X - self.pos.X, 0, p.Z - self.pos.Z).Magnitude
	if self.shape == "ring" then
		return d <= self.radius + margin and d >= self.inner - margin
	end
	return d <= self.radius + margin
end

function Zone:filter(f)
	local mode = self.targetMode
	if type(mode) == "function" then
		return mode(f, self)
	end
	local o = self.owner
	if not o then
		return true
	end
	if f == o and not self.includeOwner then
		return mode == "allies" or mode == "allIncludingOwner"
	end
	if mode == "enemies" then
		return S.isEnemy(o, f) or (self.includeOwner and f == o)
	elseif mode == "allies" then
		return S.isAlly(o, f)
	end
	return true
end

function Zone:targets()
	local out = {}
	for _, f in pairs(S.fighters) do
		if S.alive(f) and self:filter(f) and self:contains(f) then
			table.insert(out, f)
		end
	end
	return out
end

function Zone:move(pos)
	self.pos = pos
	if self.visual then
		if self.shape == "rect" then
			local mid = pos + self.dir * (self.length / 2)
			self.visual.CFrame = CFrame.lookAt(mid, mid + self.dir)
		else
			self.visual:PivotTo(CFrame.new(pos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)))
		end
	end
end

function Zone:resize(radius)
	self.radius = radius
	self:buildVisual()
end

function Zone:remove(reason)
	if not self.alive then
		return
	end
	self.alive = false
	list[self.id] = nil
	if self.visual then
		local v = self.visual
		Debris:AddItem(v, 0)
	end
	if self.onEnd then
		S.safe(self.onEnd, self, reason or "removed")
	end
end

function Zone:extend(seconds)
	self.expires += seconds
end

function Zone:remaining()
	return math.max(0, self.expires - S.now())
end

function Zones.update(now)
	for _, z in pairs(list) do
		S.FX.current = S.FX.ctxOf(z.owner)
		if z.alive then
			if z.follow then
				if S.alive(z.follow) then
					local g = S.Hit.ground(z.follow.root.Position) or z.follow.root.Position
					z:move(g)
				else
					z:remove("follow lost")
				end
			end
			if z.alive then
				local current = {}
				for _, f in ipairs(z:targets()) do
					current[f] = true
					if not z.inside[f] then
						z.inside[f] = true
						if z.onEnter then
							S.safe(z.onEnter, z, f, not z.entered[f])
						end
						z.entered[f] = true
					end
				end
				for f in pairs(z.inside) do
					if not current[f] then
						z.inside[f] = nil
						if z.onExit then
							S.safe(z.onExit, z, f)
						end
					end
				end
				if now >= z.nextTick then
					z.nextTick += z.tick
					if z.onTick then
						local t = {}
						for f in pairs(current) do
							table.insert(t, f)
						end
						S.safe(z.onTick, z, t)
					end
				end
				if now >= z.expires then
					z:remove("expired")
				end
			end
		end
	end
end

function Zones.near(pos, r, filter)
	local out = {}
	for _, z in pairs(list) do
		if z.alive then
			local d = Vector3.new(z.pos.X - pos.X, 0, z.pos.Z - pos.Z).Magnitude
			if d <= r + (z.radius or 0) and (filter == nil or filter(z)) then
				table.insert(out, z)
			end
		end
	end
	return out
end

function Zones.owned(f, tag)
	local out = {}
	for _, z in ipairs(f.zones) do
		if z.alive and (tag == nil or z.tags[tag]) then
			table.insert(out, z)
		end
	end
	return out
end

function Zones.removeOwned(f)
	for _, z in ipairs(f.zones) do
		z:remove("owner")
	end
	table.clear(f.zones)
end

return Zones
