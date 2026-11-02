-- 66 Paper — Folding geometry and fragile utility
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local PAPER = Color3.fromRGB(245, 240, 225)

local function setCreases(f, n)
	f.state.creases = math.clamp(n, 0, 3)
	K.res(f, "Creases", f.state.creases, 3, 1)
end

-- Passive: Crease Memory — a different fold grants a Crease; hold the modifier to spend one for -5 Energy
function Kit.passive.init(f)
	setCreases(f, 0)
	f.state.lastFold = 0
end
function Kit.passive.cast(f, c)
	if c.slot > 4 then
		return
	end
	if c.mod and f.state.creases > 0 then
		setCreases(f, f.state.creases - 1)
		K.addEnergy(f, 5)
	end
	if f.state.prev and f.state.prev ~= c.slot then
		setCreases(f, f.state.creases + 1)
	end
	f.state.prev = c.slot
	f.state.lastFold = K.now()
end
function Kit.passive.tick(f, dt, now)
	if f.state.creases > 0 and now - f.state.lastFold > 8 then
		setCreases(f, 0)
	end
end

local function waterDamage(o)
	o.beforeDamage = function(obj, info)
		if info.src and info.src.kitName == "Water" and not obj.data.wet then
			obj.data.wet = true
			info.amount += 40
		end
	end
end

-- 1 Razor Letter
Kit[1] = function(c)
	K.proj(c, {
		range = 20,
		speed = 28,
		width = 0.15,
		shape = "Block",
		size = Vector3.new(0.8, 0.1, 0.8),
		color = PAPER,
		dmg = 65,
		finish = function(pos, reason)
			if c.p60 and reason == "wall" then
				K.object(c, { name = "PaperMarker", pos = K.ground(pos), size = Vector3.new(1, 0.1, 1), hp = 40, duration = 6, solid = false, queryable = true, color = PAPER })
			end
		end,
	})
end

-- 2 Accordion Wall
Kit[2] = function(c)
	local pos = c:aimPoint(10)
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local panels = {}
	for i = -1, 1 do
		local p = K.ground(pos + side * K.m(i * 1.6) + dir * K.m(i % 2 == 0 and 0 or 0.6))
		local facing = K.rotate(dir, i * 25)
		local panel = K.wall(c, { name = "AccordionPanel", pos = p, dir = facing, width = 1.7, height = 2.4, thick = 0.15, hp = 70, duration = 7, color = PAPER, material = Enum.Material.Fabric, transparency = 0 })
		panel.data.paper = true
		waterDamage(panel)
		table.insert(panels, panel)
	end
	if c.p60 then
		c:recast(7, function()
			for _, p in ipairs(panels) do
				if p.alive then
					p.part.CFrame *= CFrame.Angles(0, math.rad(45), 0)
					break
				end
			end
		end)
	end
end

-- 3 Origami Crane
Kit[3] = function(c)
	local f = c.f
	local rider = c:ally(14, true) or f
	local crane = K.summon(c, { name = "OrigamiCrane", pos = rider.root.Position + Vector3.new(0, 3, 0), hp = 90, duration = 2, speed = 0, size = Vector3.new(2, 0.6, 1.4), shape = "Block", color = PAPER, ai = "none" })
	local start = rider.root.Position
	local dest = K.Hit.clearPath(start + Vector3.new(0, K.m(1.5), 0), c:dir(), K.m(8), 1.2) + Vector3.new(0, K.m(1.5), 0)
	local dismounted = false
	local rc = S.Cast.newCtx(rider, 3, c.def)
	K.spawn(function()
		local t0 = K.now()
		while K.now() - t0 < 1.4 and not dismounted do
			if not K.alive(crane) then
				dismounted = true
				break
			end
			if rider.humanoid and rider.humanoid.Jump and K.now() - t0 > 0.2 then
				dismounted = true
				break
			end
			task.wait(0.05)
		end
	end)
	K.path(rc, function(a)
		if dismounted then
			return rider.root.Position
		end
		local p = start:Lerp(dest, a) + Vector3.new(0, math.sin(a * math.pi) * K.m(1.5), 0)
		if K.alive(crane) then
			crane.root.CFrame = CFrame.new(p + Vector3.new(0, 3, 0))
		end
		return p
	end, 1.4)
	if K.alive(crane) then
		S.Summons.remove(crane, "landed")
	end
	if c.p60 then
		K.hover(rider, 0, 1, 0.1)
	end
end

-- 4 Paper Seal
Kit[4] = function(c)
	K.proj(c, {
		range = 12,
		width = 0.4,
		shape = "Block",
		size = Vector3.new(0.7, 0.1, 0.9),
		color = PAPER,
		hit = function(t)
			local _, result = K.dmg(c, t, 40, { projectile = true })
			if result == "guarded" then
				return -- guarding the seal prevents attachment
			end
			K.mark(c, t, "PaperSeal", 1, { label = "Paper Seal", color = PAPER, onExpire = function(v)
				K.slow(c, v, 0.25, 2, "Ribbons")
				if c.p60 then
					K.reveal(c, v, 2)
				end
			end })
		end,
	})
end

-- 5 Thousand Fold Citadel (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(16)
	local folds = {}
	for i = 0, 5 do
		local a = math.rad(i * 60)
		local d = Vector3.new(math.cos(a), 0, math.sin(a))
		local p = K.ground(center + d * K.m(6))
		local fold
		if i % 2 == 0 then
			fold = K.wall(c, { name = "CitadelFold", pos = p, dir = d, width = 2.5, height = 2.4, thick = 0.15, hp = 120, duration = 8, isUlt = true, color = PAPER, material = Enum.Material.Fabric, transparency = 0 })
		else
			fold = K.object(c, { name = "CitadelFold", cf = CFrame.lookAt(p + Vector3.new(0, K.m(0.8), 0), p + Vector3.new(0, K.m(0.8), 0) - d) * CFrame.Angles(math.rad(25), 0, 0), size = Vector3.new(2.5, 0.2, 3.5), hp = 120, duration = 8, isUlt = true, color = PAPER, material = Enum.Material.Fabric })
		end
		fold.data.paper = true
		waterDamage(fold)
		table.insert(folds, fold)
	end
	local totals = {}
	local function launch(o, c2)
		if not o.alive then
			return
		end
		local from = o.part.Position + Vector3.new(0, 1, 0)
		local t = K.nearestEnemy(f, 20, from)
		local dir = t and (t.root.Position - from).Unit or K.flat(c2:aimPoint(20) - from)
		S.Objects.remove(o, "launched")
		K.FX.sphere(from, 1, PAPER, 0.6, 0.3)
		K.after(0.6, function()
			K.proj(c2, {
				origin = from,
				dir = dir,
				range = 20,
				speed = 22,
				width = 0.8,
				shape = "Block",
				size = Vector3.new(1.6, 0.2, 1),
				color = PAPER,
				homing = t,
				turnRate = 90,
				hit = function(v)
					if (totals[v] or 0) < 3 then
						totals[v] = (totals[v] or 0) + 1
						K.dmg(c2, v, 85)
					end
				end,
			})
		end)
	end
	if c.unstable then
		c:recast(8, function(c2)
			for _, o in ipairs(folds) do
				launch(o, c2)
			end
			for _, o in ipairs(K.owned(f)) do
				if o.data.paper then
					S.Objects.remove(o, "unfolded")
				end
			end
		end)
		return
	end
	local launched = 0
	c:recast(8, function(c2)
		local aim = c2:aimPoint(30)
		local best, bd
		for _, o in ipairs(folds) do
			if o.alive then
				local d = (o.part.Position - aim).Magnitude
				if not bd or d < bd then
					best, bd = o, d
				end
			end
		end
		if best then
			launch(best, c2)
			launched += 1
		end
		if launched < 2 then
			return "keep"
		end
		return nil
	end)
end

return Kit
