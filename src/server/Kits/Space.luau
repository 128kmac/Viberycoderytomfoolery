-- 86 Space — Paired locations and visible traversal (no splitting bodies, duplicating shots or loops)
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local SPACE = Color3.fromRGB(110, 80, 220)

-- a linked aperture pair. opts: allyLimit, projLimit, duration, hp, isUlt, symbol
local function makePair(c, a, dirA, b, dirB, opts)
	local f = c.f
	local function aperture(pos, dir)
		local cf = CFrame.lookAt(pos + Vector3.new(0, K.m(1.2), 0), pos + Vector3.new(0, K.m(1.2), 0) + dir)
		local o = K.object(c, { name = "Aperture", cf = cf, size = Vector3.new(1.8, 2.4, 0.2), hp = opts.hp or 130, duration = opts.duration, solid = false, blocks = false, queryable = true, color = SPACE, material = Enum.Material.Neon, transparency = 0.35, isUlt = opts.isUlt })
		if opts.symbol then
			K.FX.text(cf.Position + Vector3.new(0, 2.5, 0), opts.symbol, Color3.fromRGB(255, 255, 255), opts.duration, 26)
		end
		return o
	end
	local pair = { a = aperture(a, dirA), b = aperture(b, dirB), allies = opts.allyLimit or 2, projs = opts.projLimit or 0, used = {} }
	pair.a.data.pair, pair.b.data.pair = pair, pair
	local cooldown = {}
	local function exitOf(o)
		return o == pair.a and pair.b or pair.a
	end
	K.every(0.03, opts.duration, function()
		if not (pair.a.alive and pair.b.alive) then
			if pair.a.alive then
				S.Objects.remove(pair.a, "unpaired")
			end
			if pair.b.alive then
				S.Objects.remove(pair.b, "unpaired")
			end
			return false
		end
		for _, o in ipairs({ pair.a, pair.b }) do
			local pos = o.part.Position
			-- willing allied characters (never enemies)
			if pair.allies > 0 then
				for _, t in ipairs(K.alliesIn(f, K.ground(pos), 1, true)) do
					if not t.isSummon and (not cooldown[t] or K.now() - cooldown[t] > 1.2) then
						local ex = exitOf(o)
						local dest = K.Hit.findLegal(ex.part.Position + ex.part.CFrame.LookVector * K.m(1.2), t.hitScale)
						if dest then
							cooldown[t] = K.now()
							pair.allies -= 1
							S.Fighter.teleport(t, dest)
							K.FX.burst(dest, 3, SPACE, 0.25)
						end
						break
					end
				end
			end
			-- allied projectiles keep damage and remaining range; one portal pair per shot
			if pair.projs > 0 then
				for _, p in ipairs(K.projNear(pos, 1.2, function(p)
					return p.owner and K.isAlly(f, p.owner) and not p.data.portaled
				end)) do
					local ex = exitOf(o)
					p.data.portaled = true
					p.pos = ex.part.Position + ex.part.CFrame.LookVector * K.m(0.8)
					p.vel = ex.part.CFrame.LookVector * p.speed
					if p.data.portalBonus then
						p.range += K.m(p.data.portalBonus)
					end
					pair.projs -= 1
					break
				end
			end
		end
		return true
	end)
	return pair
end
Kit.makePair = makePair

-- Passive: Spatial Survey — the HUD shows whether your aim is a legal anchor within 20 m
function Kit.passive.tick(f)
	local a = f.aim and f.aim.hit
	if a and (a - f.root.Position).Magnitude <= K.m(20) then
		K.res(f, "Anchor", K.Hit.legal(K.Hit.standAt(K.ground(a))) and "legal" or "blocked", nil, 1)
	else
		K.res(f, "Anchor", "out of range", nil, 1)
	end
end

-- 1 Fold Dart (an own portal pair admits it once, preserving remaining range; P60 adds 3 m after traversal)
Kit[1] = function(c)
	K.proj(c, { range = 22, width = 0.35, color = SPACE, dmg = 75, data = { portalBonus = c.p60 and 3 or nil } })
end

-- 2 Paired Door
Kit[2] = function(c)
	local f = c.f
	local a = K.forward(c, 2)
	local b = c:aimPoint(14)
	if (b - a).Magnitude > K.m(12) then
		b = a + K.flat(b - a) * K.m(12)
		b = K.ground(b)
	end
	if not K.Hit.los(a + Vector3.new(0, 3, 0), b + Vector3.new(0, 3, 0)) then
		K.notify(f, "Both doors need line of sight")
		return
	end
	local d = K.flat(b - a)
	makePair(c, a, d, b, d, { allyLimit = c.p60 and 3 or 2, projLimit = 1, duration = 6 })
end

-- 3 Short Fold
Kit[3] = function(c)
	local f = c.f
	local dest = c:aimPoint(6, 6)
	K.FX.sphere(dest + Vector3.new(0, 2, 0), 1.2, SPACE, 0.4, 0.2)
	if not c:wait(0.4) then
		return
	end
	if K.blink(c, dest) then
		c.recovery = 0.25
		if c.p60 then
			K.shield(c, f, 30, 1, "ShortFold")
		end
	end
end

-- 4 Distance Lens
Kit[4] = function(c)
	local f = c.f
	local pos = c:aimPoint(14)
	K.FX.sphere(pos + Vector3.new(0, K.m(1.5), 0), K.m(4), SPACE, 4, 0.8)
	local slowed = {}
	K.every(0.03, 4, function()
		for _, p in pairs(S.Proj.list) do
			if p.alive and p.owner and K.isEnemy(f, p.owner) and p.kind ~= "ultimate" then
				local inside = (p.pos - (pos + Vector3.new(0, K.m(1.5), 0))).Magnitude <= K.m(4)
				if inside and not slowed[p] then
					slowed[p] = p.speed
					p.speed *= 0.75
					p.vel = p.vel.Unit * p.speed
					if c.p60 then
						K.FX.beam(p.pos, p.pos + p.vel.Unit * K.m(6), 0.1, Color3.fromRGB(200, 180, 255), 0.4, 0.5)
					end
				elseif not inside and slowed[p] then
					p.speed = slowed[p]
					p.vel = p.vel.Unit * p.speed
					slowed[p] = nil
				end
			end
		end
		return true
	end)
	K.after(4.05, function()
		for p, sp in pairs(slowed) do
			if p.alive then
				p.speed = sp
				p.vel = p.vel.Unit * sp
			end
		end
	end)
end

-- 5 Atlas of Open Doors (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(22)
	local pairs_ = {}
	local symbols = { "I", "II", "III" }
	for i = 0, 2 do
		local a1 = math.rad(i * 120)
		local a2 = math.rad(i * 120 + 180)
		local pa = K.ground(center + Vector3.new(math.cos(a1), 0, math.sin(a1)) * K.m(9))
		local pb = K.ground(center + Vector3.new(math.cos(a2), 0, math.sin(a2)) * K.m(4))
		pairs_[i + 1] = makePair(c, pa, K.flat(center - pa), pb, K.flat(pb - center), { allyLimit = 2, projLimit = 3, duration = 7, hp = 150, isUlt = true, symbol = symbols[i + 1] })
	end
	if c.unstable then
		c:recast(7, function(c2)
			local p = pairs_[1]
			if not p.b.alive then
				return
			end
			local target = c2:aimPoint(30)
			local from = p.b.part.Position
			local to = K.ground(from + K.flat(target - from) * math.min(K.m(4), (target - from).Magnitude))
			K.FX.sphere(to + Vector3.new(0, 2, 0), 1.2, SPACE, 1, 0.3)
			task.wait(1)
			if p.b.alive then
				p.b.part.CFrame = CFrame.new(to + Vector3.new(0, K.m(1.2), 0)) * p.b.part.CFrame.Rotation
			end
			for i = 2, 3 do
				for _, o in ipairs({ pairs_[i].a, pairs_[i].b }) do
					if o.alive then
						S.Objects.remove(o, "collapsed")
					end
				end
			end
		end)
	end
	local _ = f
end

return Kit
