-- 58 Mist — Soft concealment and moisture trails (never hides attack markers or hitboxes)
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local MIST = Color3.fromRGB(200, 210, 220)

local function mistZones(f)
	return K.ownedZones(f, "mist")
end

-- Passive: Condensation Trace — enemies moving through owned mist leave footprints (within 12 m)
function Kit.passive.tick(f)
	for _, z in ipairs(mistZones(f)) do
		for t in pairs(z.inside) do
			if K.isEnemy(f, t) and t.humanoid and t.humanoid.MoveDirection.Magnitude > 0.1 and K.dist(f, t) <= 12 then
				K.reveal(f, t, 2)
			end
		end
	end
end

local function mist(c, opts)
	opts.tags = opts.tags or {}
	opts.tags.mist = true
	opts.targets = "all"
	opts.color = MIST
	opts.transparency = 0.7
	local z = K.zone(c, opts)
	local vis = K.FX.sphere(z.pos + Vector3.new(0, K.m(0.8), 0), z.radius, MIST, opts.duration, 0.6)
	vis.Material = Enum.Material.SmoothPlastic
	z.data.vis = vis
	local oldMove = z.move
	function z:move(pos)
		oldMove(self, pos)
		if vis.Parent then
			vis.Position = pos + Vector3.new(0, K.m(0.8), 0)
		end
	end
	return z
end

-- 1 Dew Needle
Kit[1] = function(c)
	K.proj(c, {
		range = 20,
		width = 0.35,
		color = Color3.fromRGB(230, 240, 255),
		dmg = 65,
		hit = function(t)
			if c.p60 then
				K.reveal(c, t, 2)
			end
			mist(c, { pos = K.feet(t), radius = 1.5, duration = 3 })
		end,
		finish = function(pos, reason)
			if reason ~= "hit" then
				mist(c, { pos = K.ground(pos), radius = 1.5, duration = 3 })
			end
		end,
	})
end

-- 2 Veil Drift (P60: recast stops halfway, leaving the full trail)
Kit[2] = function(c)
	local f = c.f
	local start = c:feet()
	local dir = c:dir()
	K.zone(c, { shape = "rect", pos = start, dir = dir, width = 3, length = 6, duration = 4, targets = "all", color = MIST, transparency = 0.6, tags = { mist = true } })
	if c.p60 then
		c:recast(0.3, function()
			local lv = f.root:FindFirstChild("EBDisplace")
			if lv then
				lv:Destroy()
			end
		end)
	end
	K.dash(c, dir, 6, 0.4)
end

-- 3 Low Fog — breaks target lock for occupants
Kit[3] = function(c)
	local pos = c:aimPoint(16)
	local moved = false
	local z = mist(c, {
		pos = pos,
		radius = 6,
		duration = 6,
		above = 2,
		enter = function(_, t)
			t.untargetable += 1
		end,
		exit = function(_, t)
			t.untargetable = math.max(0, t.untargetable - 1)
		end,
		finish = function(zz)
			for t in pairs(zz.inside) do
				t.untargetable = math.max(0, t.untargetable - 1)
			end
		end,
	})
	if c.p60 then
		c:recast(6, function(c2)
			if not moved and z.alive then
				moved = true
				z:move(z.pos + K.flat(c2:aimPoint(30) - z.pos) * K.m(2))
			end
		end)
	end
end

-- 4 Condense and Fall
Kit.requires = {
	[4] = function(c)
		if #mistZones(c.f) > 0 then
			return true
		end
		return false, "No mist patch"
	end,
}
Kit[4] = function(c)
	local f = c.f
	local aim = c:aimPoint(14)
	local best, bd
	for _, z in ipairs(mistZones(f)) do
		local d = (z.pos - aim).Magnitude
		if not bd or d < bd then
			best, bd = z, d
		end
	end
	if not best then
		return
	end
	local pos = best.pos
	K.telegraph(c, pos, 3, 0.7, MIST)
	task.wait(0.7)
	best:remove("condensed")
	K.circle(c, pos, 3, {
		dmg = 120,
		color = Color3.fromRGB(150, 190, 255),
		hit = function(t)
			K.slow(c, t, 0.2, 2, "Rain")
		end,
	})
	if c.p60 then
		for _, a in ipairs(K.alliesIn(c, pos, 3, true)) do
			if K.cleanse(a, "burn", 1) > 0 then
				break
			end
		end
	end
end

-- 5 The Vanishing Shore (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	mist(c, { pos = center, radius = 9, duration = 7 })
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local hitBy = { {}, {}, {} }
	for front = 1, 3 do
		local offset = (front - 2) * K.m(5)
		local reverse = c.unstable and front == 2
		K.spawn(function()
			local start = center - dir * K.m(9) + side * offset
			local steps = 18
			for s = 0, steps do
				local alpha = s / steps
				if reverse and alpha > 0.5 then
					alpha = 1 - alpha
				end
				local p = start + dir * K.m(18) * alpha
				K.FX.rect(CFrame.lookAt(p, p + dir), K.m(4), K.m(0.8), 0.15, Color3.fromRGB(240, 250, 255), 0.2)
				for _, t in ipairs(K.enemiesLine(c, p - side * K.m(2), side, 4, 1.2)) do
					if not hitBy[front][t] then
						hitBy[front][t] = true
						K.dmg(c, t, 80, { fromPos = p })
					end
				end
				task.wait(0.25)
			end
		end)
		task.wait(1)
	end
	if c.unstable then
		K.reveal(c, f, 6)
	end
end

return Kit
