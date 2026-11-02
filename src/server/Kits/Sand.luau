-- 77 Sand — Loose terrain and shifting visibility
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local SAND = Color3.fromRGB(230, 200, 130)

local function sandZone(c, opts)
	opts.tags = opts.tags or {}
	opts.tags.sand = true
	opts.color = opts.color or SAND
	return K.zone(c, opts)
end

-- Passive: Loose Footing — each full second in your sand adds Drift (5% slow each, max 3)
function Kit.passive.init(f)
	f.state.contact = {}
end
function Kit.passive.tick(f, dt)
	local inside = {}
	for _, z in ipairs(K.ownedZones(f, "sand")) do
		for t in pairs(z.inside) do
			if K.isEnemy(f, t) then
				inside[t] = true
			end
		end
	end
	for t in pairs(inside) do
		f.state.contact[t] = (f.state.contact[t] or 0) + dt
		if f.state.contact[t] >= 1 then
			f.state.contact[t] = 0
			local n = math.min(3, K.stacks(t, "Drift") + 1)
			K.debuff(f, t, "Drift", { duration = 1, setStacks = n, max = 3, slow = 0.05 * n, category = "slow", label = "Drift" })
		elseif K.has(t, "Drift") then
			-- stays refreshed while in sand; fades 1 s after leaving
			local st = K.Status.get(t, "Drift")
			st.expires = math.max(st.expires, K.now() + 1)
		end
	end
	for t in pairs(f.state.contact) do
		if not inside[t] then
			f.state.contact[t] = nil
		end
	end
end

-- 1 Abrasive Stream
Kit[1] = function(c)
	local ticks = 0
	c:channel(0.8, {
		stationary = false,
		halfSpeed = true,
		tick = 0.2,
		onTick = function()
			ticks += 1
			local range = 12 + ((c.p60 and ticks >= 3) and 2 or 0)
			K.beam(c, { dir = c:dir3(), length = range, width = 0.7, dmg = 20, color = SAND, dur = 0.2 })
		end,
	})
end

-- 2 Dune Rise
Kit[2] = function(c)
	local pos = c:aimPoint(14)
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local dune = K.object(c, { name = "Dune", cf = CFrame.lookAt(pos - Vector3.new(0, K.m(2), 0), pos - Vector3.new(0, K.m(2), 0) + side) * CFrame.Angles(0, math.rad(90), 0), size = Vector3.new(5, 10, 10), shape = "Cylinder", hp = 200, duration = 8, color = SAND, material = Enum.Material.Sand })
	-- rises over 1 second
	local final = dune.part.CFrame
	dune.part.CFrame = final - Vector3.new(0, K.m(3), 0)
	K.every(0.05, 1, function(i)
		if dune.alive then
			dune.part.CFrame = final - Vector3.new(0, K.m(3) * (1 - i / 20), 0)
		end
		return i < 20
	end)
	-- steep faces slow climbers 20% (a shallow allied face with P60)
	sandZone(c, {
		pos = pos,
		radius = 3.5,
		duration = 8,
		tick = 0.25,
		immediate = true,
		targets = c.p60 and "enemies" or "all",
		transparency = 0.9,
		tickFn = function(_, list)
			for _, t in ipairs(list) do
				K.slow(c, t, 0.2, 0.4, "Dune Climb")
			end
		end,
	})
end

-- 3 Sifting Step
Kit[3] = function(c)
	local f = c.f
	if c.p60 then
		K.cleanse(f, "slow", 1)
	end
	local start = c:feet()
	local dir = c:dir()
	local restore = K.conceal(f, 0.5, 0.6)
	local d = K.dash(c, dir, 7, 0.45)
	restore()
	K.FX.rect(CFrame.lookAt(start + dir * K.m(d / 2) + Vector3.new(0, 0.1, 0), start + dir * K.m(d)), K.m(1), K.m(math.max(1, d)), 3, SAND, 0.4)
end

-- 4 Burial Circle
Kit[4] = function(c)
	local f = c.f
	local pos = c:aimPoint(16)
	local rooted = {}
	sandZone(c, {
		pos = pos,
		radius = 4,
		duration = 3,
		dmg = 25,
		above = 1,
		tickFn = function(_, list)
			for _, t in ipairs(list) do
				if K.isEnemy(f, t) and not rooted[t] and K.stacks(t, "Drift") >= 3 then
					rooted[t] = true
					K.root(c, t, 0.6)
					if c.p60 then
						K.debuff(c, t, "Drift", { duration = 1, setStacks = 1, max = 3, slow = 0.05, category = "slow", label = "Drift" })
					else
						K.Status.remove(t, "Drift")
					end
				end
			end
		end,
	})
end

-- 5 March of the Dunes (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local totals = {}
	local function march(offset, reverse, delay)
		task.wait(delay or 0)
		local start = center - dir * K.m(5) + side * K.m(offset)
		local wall = K.FX.base({ size = Vector3.new(K.m(5), K.m(2.5), K.m(1.5)), cf = CFrame.lookAt(start, start + dir), color = SAND, transparency = 0.1, material = Enum.Material.Sand })
		local hit = {}
		local steps = 25
		for s = 0, steps do
			local a = s / steps
			if reverse then
				a = 1 - a
			end
			local p = start + dir * K.m(10) * a + Vector3.new(0, K.m(1), 0)
			wall.CFrame = CFrame.lookAt(p, p + dir)
			for _, t in ipairs(K.Hit.box(wall.CFrame, wall.Size, K.enemyFilter(c))) do
				if not hit[t] and (totals[t] or 0) < 3 then
					hit[t] = true
					totals[t] = (totals[t] or 0) + 1
					K.dmg(c, t, 80, { fromPos = p })
					K.push(c, t, reverse and -dir or dir, 1.5)
				end
			end
			task.wait(0.2)
		end
		wall:Destroy()
	end
	if c.unstable then
		K.spawn(march, -2.5, false)
		K.spawn(march, 2.5, false)
		K.telegraphLine(c, center + dir * K.m(5), -dir, 10, 5, 0.8, SAND)
		K.spawn(march, 0, true, 0.8)
	else
		for i = -1, 1 do
			K.spawn(march, i * 5, false, (i + 1) * 0.3)
		end
	end
	local _ = f
end

return Kit
