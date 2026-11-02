-- 57 Mirror — Orientation and bounded reflection (one reflection per projectile, ever)
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local SILVER = Color3.fromRGB(220, 230, 240)

local function mirrors(f)
	return K.owned(f, "Mirror")
end

-- Passive: True Surface — fronts reflect eligible enemy projectiles; rears take normal damage
local function makeMirror(c, cf, hp, duration, opts)
	local f = c.f or c
	opts = opts or {}
	local list = mirrors(f)
	if #list >= 3 and not opts.isUlt then
		S.Objects.remove(list[1], "replaced")
	end
	local o = K.object(c, {
		name = "Mirror",
		cf = cf,
		size = opts.size or Vector3.new(2, 2.4, 0.2),
		hp = hp or 100,
		duration = duration or 6,
		color = SILVER,
		material = Enum.Material.Glass,
		transparency = 0.1,
		isUlt = opts.isUlt,
		noCap = true,
	})
	o.part.Reflectance = 0.6
	o.onProjectile = function(obj, p, normal)
		local front = obj.part.CFrame.LookVector
		if normal:Dot(front) > 0.3 and not p.reflected and p.kind ~= "ultimate" and p.owner and K.isEnemy(f, p.owner) then
			local v = p.vel
			local newDir = (v - 2 * v:Dot(front) * front).Unit
			S.Proj.reflect(p, f, newDir)
			p.data.dmgMult = (p.data.dmgMult or 1)
			K.FX.burst(p.pos, 1.5, SILVER, 0.2)
			return "consumed"
		end
		return nil
	end
	return o
end
Kit.makeMirror = makeMirror

function Kit.passive.tick(f)
	K.res(f, "Mirrors", #mirrors(f), 3, 1)
end

-- 1 Silver Shard
Kit[1] = function(c)
	local dir = c:dir()
	K.proj(c, {
		range = 22,
		width = 0.35,
		shape = "Block",
		size = Vector3.new(0.5, 0.5, 1),
		color = SILVER,
		dmg = 70,
		finish = function(pos, reason)
			if reason == "wall" or reason == "range" then
				local g = K.ground(pos) - dir * K.m(0.4)
				local p = g + Vector3.new(0, K.m(1.2), 0)
				makeMirror(c, CFrame.lookAt(p, p - dir), 100 + (c.p60 and 40 or 0), 5)
			end
		end,
	})
end

-- 2 Reflecting Guard
Kit[2] = function(c)
	local f = c.f
	local done = false
	K.FX.highlight(f.model, SILVER, 0.6, 0.5)
	K.every(0.02, 0.6, function()
		if done then
			return false
		end
		for _, p in ipairs(K.enemyProj(c, f.root.Position, 2.2)) do
			if not p.reflected and p.kind ~= "ultimate" then
				done = true
				local dir = -p.vel.Unit
				if c.p60 then
					local want = c:dir3()
					local ang = math.deg(math.acos(math.clamp(want:Dot(dir), -1, 1)))
					dir = ang <= 30 and want or dir:Lerp(want, 30 / ang).Unit
				end
				p.data.dmgMult = 0.75
				S.Proj.reflect(p, f, dir)
				return false
			end
		end
		return true
	end)
	c:channel(0.6, { stationary = false })
end

-- 3 Looking Glass Step
Kit.requires = {
	[3] = function(c)
		if #mirrors(c.f) >= 2 then
			return true
		end
		return false, "Needs two mirrors"
	end,
}
Kit[3] = function(c)
	local f = c.f
	local list = mirrors(f)
	table.sort(list, function(a, b)
		return (a.part.Position - f.root.Position).Magnitude < (b.part.Position - f.root.Position).Magnitude
	end)
	local entry, exit = list[1], list[#list]
	K.FX.beam(entry.part.Position, exit.part.Position, 0.3, SILVER, 0.4)
	task.wait(0.4)
	if not (entry.alive and exit.alive) then
		return
	end
	local exitPos = exit.part.Position + exit.part.CFrame.LookVector * K.m(1.2)
	local ok = K.blink(c, K.ground(exitPos), { throughWalls = true })
	S.Objects.remove(entry, "traversed")
	S.Objects.remove(exit, "traversed")
	if ok and c.p60 then
		local p = f.root.Position + K.flat(f.root.CFrame.LookVector) * K.m(1.5)
		makeMirror(c, CFrame.lookAt(p, p + K.flat(f.root.CFrame.LookVector)), 50, 5)
	end
end

-- 4 Reverse Image
Kit[4] = function(c)
	local f = c.f
	local pos = c:aimPoint(14)
	K.telegraph(c, pos, 3, 0.8, SILVER)
	task.wait(0.8)
	local ally
	for _, a in ipairs(K.alliesIn(c, pos, 3, false)) do
		ally = a
		break
	end
	if ally then
		local a, b = f.root.Position, ally.root.Position
		S.Fighter.teleport(f, b)
		S.Fighter.teleport(ally, a)
		if c.p60 then
			K.shield(c, f, 40, 3, "ReverseImage")
			K.shield(c, ally, 40, 3, "ReverseImage")
		end
	else
		K.circle(c, pos, 3, { dmg = 110, color = SILVER })
	end
end

-- 5 Hall of Reflections (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	local hall = {}
	for i = 0, 5 do
		local a = math.rad(i * 60)
		local p = K.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(7)) + Vector3.new(0, K.m(1.2), 0)
		hall[i + 1] = makeMirror(c, CFrame.lookAt(p, Vector3.new(center.X, p.Y, center.Z)), 130, 6, { isUlt = true, size = Vector3.new(2.5, 2.6, 0.25) })
	end
	local rays = c.unstable and 4 or 3
	c:recast(6, function(c2)
		local aim = c2:aimPoint(40)
		local best, bd
		for _, m in ipairs(hall) do
			if m.alive then
				local d = (m.part.Position - aim).Magnitude
				if not bd or d < bd then
					best, bd = m, d
				end
			end
		end
		if best then
			local from = c2:chest()
			local mp = best.part.Position
			local first = (mp - from)
			-- unstable reflected rays are neutral and can hit the caster
			local filter = c.unstable and function()
				return true
			end or K.enemyFilter(c2)
			K.beam(c2, { origin = from, dir = first.Unit, length = first.Magnitude / K.M, width = 0.6, dmg = 90, color = SILVER, filter = K.enemyFilter(c2), throughWalls = true })
			if best.alive then
				-- reflects once at most; destroying the destination cancels the branch
				local n = best.part.CFrame.LookVector
				local rd = first.Unit - 2 * first.Unit:Dot(n) * n
				K.beam(c2, { origin = mp + n, dir = rd, length = 16, width = 0.6, dmg = 90, color = SILVER, filter = filter })
			end
		end
		rays -= 1
		if rays > 0 then
			return "keep"
		end
		return nil
	end)
end

return Kit
