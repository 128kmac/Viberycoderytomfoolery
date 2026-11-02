-- 79 Shadow — Connections between visible patches of shade (never through arbitrary walls)
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local SHADE = Color3.fromRGB(30, 30, 40)

local function anchors(f, includeUlt)
	local out = {}
	for _, o in ipairs(K.owned(f, "ShadowAnchor")) do
		if includeUlt or not o.isUlt then
			table.insert(out, o)
		end
	end
	table.sort(out, function(a, b)
		return a.created < b.created
	end)
	return out
end
local function suppressed(o)
	for _, z in ipairs(K.zonesNear(o.part.Position, 0.5)) do
		if z.element == "Light" and z.owner and not z.owner.dead then
			return true
		end
	end
	return false
end

-- Passive: Three Anchors
local function anchor(c, pos, isUlt)
	local f = c.f
	if not isUlt then
		local list = anchors(f)
		if #list >= 3 then
			S.Objects.remove(list[1], "replaced")
		end
	end
	return K.object(c, { name = "ShadowAnchor", pos = pos, size = Vector3.new(1.6, 0.1, 1.6), hp = 60, duration = 8, solid = false, queryable = true, color = SHADE, material = Enum.Material.SmoothPlastic, isUlt = isUlt, noCap = true })
end
function Kit.passive.tick(f)
	K.res(f, "Anchors", #anchors(f), 3, 1)
end

-- 1 Shade Cut
Kit[1] = function(c)
	K.proj(c, {
		origin = c:feet() + Vector3.new(0, 0.6, 0),
		dir = c:dir(),
		range = c.p60 and 12 or 10,
		speed = 22,
		width = 1,
		ground = true,
		shape = "Block",
		size = Vector3.new(2, 0.2, 0.8),
		color = SHADE,
		dmg = 75,
		finish = function(pos)
			local g = K.Hit.ground(pos + Vector3.new(0, 2, 0), 8)
			if g then
				anchor(c, g)
			end
		end,
	})
end

-- 2 Umbra Passage
Kit.requires = {
	[2] = function(c)
		for _, o in ipairs(anchors(c.f, true)) do
			if K.dist(o.part.Position, c.f) <= 14 and not suppressed(o) then
				return true
			end
		end
		return false, "No anchor in range"
	end,
	[4] = function(c)
		if #anchors(c.f) >= 2 then
			return true
		end
		return false, "Needs two anchors"
	end,
}
Kit[2] = function(c)
	local f = c.f
	local aim = c:aimPoint(14)
	local best, bd
	for _, o in ipairs(anchors(f, true)) do
		local d = (o.part.Position - aim).Magnitude
		if K.dist(o.part.Position, f) <= 14 and not suppressed(o) and (not bd or d < bd) then
			best, bd = o, d
		end
	end
	if not best then
		return
	end
	local dest = best.part.Position
	if not K.Hit.los(f.root.Position, dest + Vector3.new(0, 2, 0), true) then
		K.notify(f, "Route blocked")
		return
	end
	K.FX.beam(K.feet(f), dest, 0.4, SHADE, 0.5, 0.2)
	if not c:wait(0.5) then
		return
	end
	K.untargetable(f, 0.15)
	K.blink(c, dest)
	if not c.p60 then
		S.Objects.remove(best, "consumed")
	end
end

-- 3 Borrowed Silhouette
Kit[3] = function(c)
	K.proj(c, {
		range = 12,
		width = 0.4,
		color = SHADE,
		dmg = 40,
		hit = function(t)
			local facing = K.flat(t.root.CFrame.LookVector)
			local origin = t.root.Position
			K.after(0.6, function()
				-- the swing location locks 0.4 s before contact
				local spot = K.ground(origin + facing * K.m(1.5))
				K.telegraph(c, spot, 1.6, 0.4, SHADE)
				K.after(0.4, function()
					K.circle(c, spot, 1.6, { dmg = 60, color = SHADE })
					if c.p60 then
						anchor(c, spot)
					end
				end)
			end)
		end,
	})
end

-- 4 Long Evening
Kit[4] = function(c)
	local f = c.f
	local list = anchors(f)
	local aim = c:aimPoint(16)
	table.sort(list, function(a, b)
		return (a.part.Position - aim).Magnitude < (b.part.Position - aim).Magnitude
	end)
	local a, b = list[1], list[2]
	local hit = {}
	K.every(0.05, 4, function()
		if not (a.alive and b.alive) then
			return false
		end
		local pa, pb = a.part.Position + Vector3.new(0, 0.3, 0), b.part.Position + Vector3.new(0, 0.3, 0)
		K.FX.beam(pa, pb, K.m(0.8), SHADE, 0.08, 0.3)
		for _, h in ipairs(K.Hit.segment(pa, pb, K.m(0.4), K.enemyFilter(c))) do
			if not hit[h.f] then
				hit[h.f] = true
				K.dmg(c, h.f, 80, { kind = "field" })
				K.slow(c, h.f, 0.2, 1, "Long Evening")
			end
		end
		return true
	end)
end

-- 5 Court of Moving Shadows (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(18)
	local court = {}
	for i = 0, 3 do
		local a = math.rad(i * 90 + 45)
		court[i + 1] = anchor(c, K.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(5)), true)
	end
	local totals = {}
	local function slash(from, to, cc)
		if not (from.alive and to.alive) then
			return
		end
		local pa, pb = from.part.Position + Vector3.new(0, 1.5, 0), to.part.Position + Vector3.new(0, 1.5, 0)
		K.FX.beam(pa, pb, 0.6, Color3.fromRGB(200, 80, 200), 0.7, 0.5)
		task.wait(0.7)
		if not (from.alive and to.alive) then
			return
		end
		K.FX.beam(pa, pb, 1.2, SHADE, 0.2)
		for _, h in ipairs(K.Hit.segment(pa, pb, K.m(0.8), K.enemyFilter(cc))) do
			if (totals[h.f] or 0) < 3 then
				totals[h.f] = (totals[h.f] or 0) + 1
				K.dmg(cc, h.f, 90, { fromPos = pa })
			end
		end
		S.Objects.remove(from, "slashed")
	end
	if c.unstable then
		local seq = { { 1, 3 }, { 2, 4 }, { 3, 1 }, { 4, 2 } }
		for _, pr in ipairs(seq) do
			slash(court[pr[1]], court[pr[2]], c)
		end
		for _, o in ipairs(anchors(f, true)) do
			S.Objects.remove(o, "midnight")
		end
		return
	end
	local slashes = 0
	c:recast(6, function(c2)
		local aim = c2:aimPoint(30)
		local from, bd
		for _, o in ipairs(court) do
			if o.alive then
				local d = (o.part.Position - aim).Magnitude
				if not bd or d < bd then
					from, bd = o, d
				end
			end
		end
		-- connect to the farthest surviving anchor (displayed route)
		local to, td
		for _, o in ipairs(court) do
			if o.alive and o ~= from then
				local d = (o.part.Position - from.part.Position).Magnitude
				if not td or d > td then
					to, td = o, d
				end
			end
		end
		if from and to then
			slash(from, to, c2)
			slashes += 1
		end
		if slashes < 3 then
			return "keep"
		end
		return nil
	end)
end

return Kit
