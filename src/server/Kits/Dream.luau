-- 26 Dream — Lucidity and temporary imagined objects
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local PASTEL = Color3.fromRGB(200, 170, 255)

local function setTokens(f, n)
	f.state.tokens = math.clamp(n, 0, 4)
	K.res(f, "Lucid", f.state.tokens, 4, 1)
end
local function spendTokens(f, n)
	if (f.state.tokens or 0) >= n then
		setTokens(f, f.state.tokens - n)
		return true
	end
	return false
end
-- three different normal Dream skills used successfully grant two tokens
local function qualify(f, slot)
	f.state.qualified[slot] = true
	local n = 0
	for _ in pairs(f.state.qualified) do
		n += 1
	end
	if n >= 3 then
		f.state.qualified = {}
		setTokens(f, f.state.tokens + 2)
		K.announce(f, "LUCID +2", PASTEL, 1)
	end
end

function Kit.passive.init(f)
	f.state.qualified = {}
	setTokens(f, 2)
end
function Kit.passive.dealt(f, target, info)
	local c = info.opts.cast
	if c and c.slot <= 4 and info.kind == "direct" then
		qualify(f, c.slot)
	end
end

local function dreamObject(c, opts, solid)
	local f = c.f
	opts.color = opts.color or PASTEL
	opts.material = Enum.Material.Glass
	if not solid then
		-- without a token it is an obvious translucent decoy with no collision
		opts.solid = false
		opts.blocks = false
		opts.prop = true
		opts.transparency = 0.75
	else
		opts.transparency = opts.transparency or 0.2
	end
	local o = K.object(c, opts)
	o.data.dream = true
	if solid and opts.slotQualify then
		qualify(f, opts.slotQualify)
	end
	return o
end

-- 1 Sleepwalking Star
Kit[1] = function(c)
	local f = c.f
	local function star(origin, dir, canSplit)
		K.proj(c, {
			origin = origin,
			dir = dir,
			range = 20,
			speed = 14,
			width = 0.7,
			color = PASTEL,
			dmg = 65,
			hit = function(t)
				K.debuff(c, t, "Drowsy", { duration = 3, slow = 0.15, category = "slow", label = "Drowsy" })
			end,
			step = function(p)
				if canSplit and c.p60 and not p.data.split then
					for _, o in ipairs(K.owned(f)) do
						if o.data.dream and (o.part.Position - p.pos).Magnitude < K.m(1.5) then
							p.data.split = true
							S.Proj.stop(p, "split")
							for _, a in ipairs({ -25, 25 }) do
								star(p.pos, K.rotate(p.vel.Unit, a), false)
							end
							break
						end
					end
				end
			end,
		})
	end
	star(nil, c:dir3(), true)
end

-- 2 Imaginary Stair
Kit[2] = function(c)
	local f = c.f
	local solid = spendTokens(f, 1)
	local pos = c:aimPoint(12)
	local dir = c:dir()
	local cf, size
	if c.p60 and c.mod then
		cf = CFrame.lookAt(pos + Vector3.new(0, K.m(2), 0), pos + Vector3.new(0, K.m(2), 0) + dir)
		size = Vector3.new(2.5, 0.4, 5)
	else
		cf = CFrame.lookAt(pos + Vector3.new(0, K.m(2), 0), pos + Vector3.new(0, K.m(2), 0) + dir) * CFrame.Angles(math.rad(30), 0, 0)
		size = Vector3.new(2.5, 0.4, 8)
	end
	dreamObject(c, { name = "DreamStair", cf = cf, size = size, hp = 100, duration = 5, slotQualify = 2 }, solid)
end

-- 3 Soft Landing
Kit[3] = function(c)
	local f = c.f
	local pos = c:aimPoint(10)
	local helped = {}
	K.zone(c, {
		pos = pos,
		radius = 3,
		duration = 3,
		targets = "allies",
		includeOwner = true,
		color = Color3.fromRGB(255, 230, 250),
		enter = function(_, a)
			if helped[a] or a.isSummon then
				return
			end
			helped[a] = true
			K.shield(c, a, 60, 3, "SoftLanding")
			local rm
			rm = K.hook(a, "beforeDisplace", function(_, info)
				info.dist *= 0.5
				qualify(f, 3)
				rm()
			end, 4)
			if c.p60 and a.humanoid then
				K.every(0.1, 3, function()
					if a.humanoid.Jump then
						S.Fighter.displace(a, Vector3.yAxis, K.m(3), 0.3)
						return false
					end
					return true
				end)
			end
		end,
	})
end

-- 4 Lucid Monster
Kit.requires = {
	[4] = function(c)
		if (c.f.state.tokens or 0) >= 2 then
			return true
		end
		return false, "Need two Lucid tokens"
	end,
}
Kit[4] = function(c)
	local f = c.f
	spendTokens(f, 2)
	local dir = c:dir()
	local start = f.root.Position + dir * K.m(1.5)
	local beast = K.summon(c, { name = "DreamBeast", pos = start, hp = 160, duration = 5, speed = 9, size = Vector3.new(1.4, 1.2, 2), shape = "Block", color = PASTEL, ai = "none" })
	local goal = start + dir * K.m(14)
	S.Summons.moveTo(beast, goal)
	beast.sm.ai = "stay"
	local bit = false
	if c.p60 then
		c:recast(4, function(c2)
			if K.alive(beast) then
				local d = K.flat(c2:aimPoint(20) - beast.root.Position)
				local cur = K.flat(goal - beast.root.Position)
				local ang = math.deg(math.acos(math.clamp(d:Dot(cur), -1, 1)))
				if ang > 45 then
					local sign = cur:Cross(d).Y >= 0 and 1 or -1
					d = K.rotate(cur, -45 * sign)
				end
				goal = beast.root.Position + d * K.m(10)
				S.Summons.moveTo(beast, goal)
			end
		end)
	end
	K.every(0.1, 5, function()
		if not K.alive(beast) or bit then
			return false
		end
		for _, t in ipairs(K.enemiesIn(f, beast.root.Position, 1.6)) do
			bit = true
			K.dmg(c, t, 130, { fromPos = beast.root.Position })
			qualify(f, 4)
			S.Summons.remove(beast, "bit")
			return false
		end
		if beast.sm.goal == nil then
			S.Summons.moveTo(beast, goal)
		end
		return true
	end)
end

-- 5 A World Before Waking (ultimate)
local ROLES = { "stair", "beast", "shelter" }
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	local count = c.unstable and 6 or 3
	local dur = c.unstable and 4 or 7
	K.FX.disc(center, K.m(8), PASTEL, dur, 0.75)
	local items = {}
	local function makeRole(role, pos, hp)
		if role == "stair" then
			local cf = CFrame.lookAt(pos + Vector3.new(0, K.m(1.5), 0), pos + Vector3.new(0, K.m(1.5), 0) + c:dir()) * CFrame.Angles(math.rad(25), 0, 0)
			return { kind = "object", obj = K.object(c, { name = "DreamStair", cf = cf, size = Vector3.new(2.5, 0.4, 6), hp = hp, duration = dur, isUlt = true, color = PASTEL, material = Enum.Material.Glass }) }
		elseif role == "shelter" then
			return { kind = "object", obj = K.wall(c, { name = "DreamShelter", pos = pos, dir = c:dir(), width = 3, height = 2.5, hp = hp, duration = dur, isUlt = true, color = PASTEL }) }
		end
		local b = K.summon(c, {
			name = "DreamBeast",
			pos = pos + Vector3.new(0, 2, 0),
			hp = hp,
			duration = dur,
			speed = 7,
			size = Vector3.new(1.4, 1.2, 2),
			shape = "Block",
			color = PASTEL,
			ai = "chase",
			aggro = 8,
			leash = 30,
			attack = { range = 2, dmg = 40, interval = 1.2 },
		})
		return { kind = "summon", obj = b }
	end
	for i = 1, count do
		local a = math.rad(i * 360 / count)
		local pos = K.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(4))
		local role = ROLES[(i - 1) % 3 + 1]
		local it = makeRole(role, pos, 140)
		it.role = role
		it.pos = pos
		table.insert(items, it)
	end
	local function hpOf(it)
		if it.kind == "object" then
			return it.obj.alive and it.obj.hp or 0
		end
		return K.alive(it.obj) and it.obj.health or 0
	end
	local function removeIt(it)
		if it.kind == "object" then
			S.Objects.remove(it.obj, "swapped")
		else
			S.Summons.remove(it.obj, "swapped")
		end
	end
	c:recast(dur, function(c2)
		local aim = c2:aimPoint(30)
		local best, bd
		for _, it in ipairs(items) do
			if hpOf(it) > 0 then
				local d = (it.pos - aim).Magnitude
				if not bd or d < bd then
					best, bd = it, d
				end
			end
		end
		if best then
			local hp = hpOf(best)
			removeIt(best)
			local nextRole = ROLES[(table.find(ROLES, best.role) or 1) % 3 + 1]
			local it = makeRole(nextRole, best.pos, hp)
			best.kind, best.obj, best.role = it.kind, it.obj, nextRole
		end
		return "keep"
	end)
end

return Kit
