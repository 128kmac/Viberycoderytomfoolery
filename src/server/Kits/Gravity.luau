-- 45 Gravity — Local attraction and vector control
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local VIOLET = Color3.fromRGB(100, 60, 160)

-- Passive: Mass Debt — Weight reduces jump height by 8% per stack (never running speed)
local function weigh(f, t)
	if t.isSummon then
		return
	end
	K.debuff(f, t, "Weight", {
		duration = 4,
		stacks = 1,
		max = 3,
		category = "weight",
		label = "Weight",
		onRemove = function(tt)
			tt.jumpMult = 1
		end,
	})
	t.jumpMult = 1 - 0.08 * K.stacks(t, "Weight")
end
function Kit.passive.init(f)
	f.state.weigh = weigh
end

local function gravPull(c, t, to, distM)
	K.pull(c, t, to, distM)
	weigh(c.f, t)
end
local function gravPush(c, t, dir, distM)
	K.push(c, t, dir, distM)
	weigh(c.f, t)
end

-- 1 Falling Pebble
Kit[1] = function(c)
	local bendAt = 12
	if c.p60 and c.mod then
		bendAt = math.clamp(K.flatDist(c:aimPoint(22), c.f), 3, 20)
	end
	K.proj(c, {
		range = 30,
		speed = 24,
		width = 0.5,
		color = VIOLET,
		dmg = 80,
		hit = function(t)
			weigh(c.f, t)
		end,
		step = function(p)
			if not p.gravity and p.traveled >= K.m(bendAt) then
				p.gravity = K.m(40)
			end
		end,
	})
end

-- 2 Local Down
Kit[2] = function(c)
	local pos = c:aimPoint(14)
	local center = pos
	local core = K.object(c, { name = "WellCore", pos = pos, size = 1, shape = "Ball", hp = 110, duration = 4, color = VIOLET, material = Enum.Material.Neon })
	local z = K.zone(c, {
		pos = pos,
		radius = 3,
		duration = 4,
		tick = 0.1,
		immediate = true,
		color = VIOLET,
		transparency = 0.75,
		tickFn = function(zz, list)
			if not core.alive then
				zz:remove("core destroyed")
				return
			end
			for _, t in ipairs(list) do
				if K.isEnemy(c.f, t) and t.humanoid and t.humanoid.FloorMaterial ~= Enum.Material.Air then
					if K.flatDist(t, center) > 0.6 then
						S.Fighter.displace(t, K.flat(center - t.root.Position), K.m(0.1), 0.1)
					end
					if not t.state.wellWeighed then
						t.state.wellWeighed = true
						weigh(c.f, t)
						K.after(4, function()
							t.state.wellWeighed = nil
						end)
					end
				end
			end
		end,
	})
	if c.p60 then
		c:recast(4, function(c2)
			if core.alive then
				local d = K.flat(c2:aimPoint(20) - center)
				center = center + d * K.m(2)
				core.part.CFrame = CFrame.new(center + Vector3.new(0, K.m(0.5), 0))
				z:move(center)
			end
		end)
	end
end

-- 3 Vector Reversal
Kit[3] = function(c)
	local f = c.f
	local done = false
	if c.p60 then
		local rm
		rm = K.hook(f, "beforeDisplace", function(_, info)
			info.cancel = true
			rm()
		end, 0.6)
	end
	K.FX.sphere(f.root.Position, K.m(6), VIOLET, 0.6, 0.85)
	K.every(0.03, 0.6, function()
		if done then
			return false
		end
		for _, p in ipairs(K.enemyProj(c, f.root.Position, 6)) do
			if p.kind ~= "ultimate" and not p.reflected and not p.tags.beam then
				done = true
				p.data.dmgMult = (p.data.dmgMult or 1) * 0.7
				S.Proj.reflect(p, f, -p.vel)
				K.FX.burst(p.pos, 2, VIOLET, 0.2)
				return false
			end
		end
		return true
	end)
end

-- 4 Weight of Arrival
Kit.requires = {
	[4] = function(c)
		if c:target(16) then
			return true
		end
		return false, "No target"
	end,
}
Kit[4] = function(c)
	local t = c:target(16)
	if not t then
		return
	end
	local mark = K.feet(t)
	K.telegraph(c, mark, 3, 0.8, VIOLET)
	task.wait(0.8)
	K.FX.beam(mark + Vector3.new(0, K.m(c.p60 and 7 or 4), 0), mark, K.m(3), VIOLET, 0.3, 0.5)
	local list = K.enemiesIn(c, mark, 3, { above = c.p60 and 7 or 4 })
	for _, v in ipairs(list) do
		local w = K.stacks(v, "Weight")
		K.dmg(c, v, math.min(160, 130 + 10 * w), { fromPos = mark + Vector3.new(0, 10, 0) })
		if w > 0 then
			K.unmark(v, "Weight")
			v.jumpMult = 1
		end
	end
end

-- 5 The Falling Kingdom (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(22)
	local core = K.object(c, { name = "KingdomCore", pos = center, size = 1.6, shape = "Ball", hp = 240, duration = 5, isUlt = true, color = VIOLET, material = Enum.Material.Neon })
	K.FX.ring(center, K.m(8), VIOLET, 4.5, 0.4)
	for cycle = 1, 2 do
		if not core.alive then
			return
		end
		-- upward force
		for _, t in ipairs(K.enemiesIn(c, center, 8)) do
			K.lift(c, t, 0.5, 1.5)
			weigh(f, t)
		end
		K.FX.burst(center + Vector3.new(0, 3, 0), K.m(8), Color3.fromRGB(170, 140, 230), 0.3)
		task.wait(1)
		if not core.alive then
			return
		end
		-- downward pulse
		K.telegraph(c, center, 8, 0.3, VIOLET)
		task.wait(0.3)
		for _, t in ipairs(K.enemiesIn(c, center, 8, { above = 8 })) do
			K.dmg(c, t, 100, { fromPos = center + Vector3.new(0, 12, 0) })
			gravPush(c, t, Vector3.new(0, -1, 0) + K.flat(center - t.root.Position) * 0.01, 0.5)
		end
		K.FX.burst(center, K.m(8), VIOLET, 0.3)
		task.wait(0.7)
		local _ = cycle
	end
	if c.unstable and core.alive then
		-- Singularity Debt: a finite pull draws the caster in too
		for _, t in ipairs(K.Hit.cylinder(center, K.m(10), function()
			return true
		end)) do
			gravPull(c, t, center, 2)
		end
		task.wait(0.4)
		for _, t in ipairs(K.Hit.cylinder(center, K.m(8), function()
			return true
		end)) do
			K.Combat.damage(f, t, 140, { cast = c, isUlt = true, fromPos = center, element = "Gravity" })
		end
		K.FX.burst(center, K.m(8), Color3.fromRGB(40, 0, 80), 0.5)
	end
end

return Kit
