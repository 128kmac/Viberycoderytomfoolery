-- 53 Light — Revelation and directional radiance
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local LIGHT = Color3.fromRGB(255, 255, 180)

-- Passive: Revealing Contact
function Kit.passive.beforeDeal(f, target, info)
	local c = info.opts.cast
	if c and info.kind == "direct" and K.has(target, "Revealed") and not c.data.refunded then
		c.data.refunded = true
		K.addEnergy(f, 4)
	end
end
function Kit.passive.dealt(f, target, info)
	if info.kind == "direct" and info.opts.cast then
		K.reveal(f, target, 2)
	end
end

local function removeIllusionsAlong(c, a, b, limit)
	local n = 0
	for _, o in pairs(S.Objects.list) do
		if n >= limit then
			break
		end
		if o.alive and o.data.illusion and o.owner and K.isEnemy(c.f, o.owner) and K.Hit.pointSeg(o.part.Position, a, b) < K.m(1) then
			S.Objects.remove(o, "dispelled")
			n += 1
		end
	end
end

-- 1 Dawn Ray (windup stays readable at 0.35 s)
Kit[1] = function(c)
	local origin = c:chest()
	local dir = c:dir3()
	local length = 24
	-- Angel synergy: beams through a friendly Sanctuary Wing gain 2 m and consume 30 durability
	for _, o in pairs(S.Objects.list) do
		if o.alive and o.tags.angelWing and o.owner and K.isAlly(c.f, o.owner) and K.Hit.pointSeg(o.part.Position, origin, origin + dir * K.m(length)) < K.m(1.5) then
			length += 2
			K.objDmg(c, o, 30)
			break
		end
	end
	local endPos = K.beam(c, { origin = origin, dir = dir, length = length, width = 0.6, dmg = 75, color = LIGHT, dur = 0.3 })
	K.FX.beam(origin, endPos, K.m(2), LIGHT, 0.5, 0.85)
	if c.p60 then
		removeIllusionsAlong(c, origin, endPos, 1)
	end
end

-- 2 Luminous Step
Kit[2] = function(c)
	local f = c.f
	local after = K.decoyModel(f, f.root.CFrame, LIGHT)
	game:GetService("Debris"):AddItem(after, 1)
	K.dash(c, c:dir(), 6, 0.2)
	K.FX.burst(f.root.Position, K.m(3), LIGHT, 0.3)
	local revealed = false
	for _, t in ipairs(K.enemiesIn(c, f.root.Position, 3)) do
		K.reveal(c, t, 2)
		revealed = true
	end
	if c.p60 and revealed then
		K.shield(c, f, 50, 3, "Luminous")
	end
end

-- 3 Prism Veil — blocks the far side's energy projectiles; physical shots pass
Kit[3] = function(c)
	local f = c.f
	local pos = c:aimPoint(10)
	local dir = c:dir()
	local cf = CFrame.lookAt(pos + Vector3.new(0, K.m(1.3), 0), pos + Vector3.new(0, K.m(1.3), 0) + dir)
	local plane = K.object(c, { name = "PrismVeil", cf = cf, size = Vector3.new(4, 2.6, 0.15), hp = 160, duration = 4, solid = false, blocks = false, color = LIGHT, material = Enum.Material.ForceField, transparency = 0.3 })
	local stripe = K.FX.base({ size = Vector3.new(K.m(4), 0.2, 0.3), cf = cf * CFrame.new(0, -K.m(1.3), -0.2), color = Color3.fromRGB(255, 200, 60) })
	game:GetService("Debris"):AddItem(stripe, 4)
	local crossed = {}
	K.every(0.03, 4, function()
		if not plane.alive then
			return false
		end
		for _, p in ipairs(K.enemyProj(c, plane.part.Position, 3)) do
			if p.kind == "energy" then
				local lp = plane.part.CFrame:PointToObjectSpace(p.pos)
				if math.abs(lp.X) < plane.part.Size.X / 2 and math.abs(lp.Y) < plane.part.Size.Y / 2 and math.abs(lp.Z) < 1.2 and lp.Z < 0 then
					K.objDmg(c, plane, p.dmg or 40)
					S.Proj.stop(p, "veil")
				end
			end
		end
		if c.p60 then
			for _, a in ipairs(K.alliesIn(c, pos, 2, true)) do
				if not crossed[a] then
					crossed[a] = true
					K.cleanse(a, "reveal", 1)
					K.buff(a, "RevealResist", { duration = 1, label = "Reveal resistant" })
				end
			end
		end
		return true
	end)
end

-- 4 Noon Brand
Kit.requires = {
	[4] = function(c)
		if c:target(16) then
			return true
		end
		return false, "No visible enemy"
	end,
}
Kit[4] = function(c)
	local t = c:target(16)
	if not t then
		return
	end
	local locked = K.feet(t)
	K.mark(c, t, "NoonBrand", 3, { label = "Noon Brand", color = LIGHT })
	K.reveal(c, t, 3)
	K.telegraph(c, locked, 1.5, 0.9, LIGHT)
	task.wait(0.9)
	K.FX.beam(locked + Vector3.new(0, K.m(10), 0), locked, K.m(3), LIGHT, 0.3)
	local hits = K.enemiesIn(c, locked, 1.5, { above = 6 })
	for _, v in ipairs(hits) do
		K.dmg(c, v, 130, { fromPos = locked + Vector3.new(0, 12, 0) })
		if c.p60 and v.concealed and v.concealed > 0 then
			v.concealed = 1
			K.reveal(c, v, 2)
		end
	end
end

-- 5 Day Without Shadow (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(22)
	local core = K.object(c, { name = "SunCore", pos = center, size = 1.6, shape = "Ball", hp = 220, duration = 6.2, isUlt = true, color = LIGHT, material = Enum.Material.Neon })
	K.FX.disc(center, K.m(8), LIGHT, 6, 0.75)
	local totals = {}
	local lastHit = {}
	local t0 = K.now()
	while K.now() - t0 < 6 and core.alive do
		local rot = (K.now() - t0) * 60
		for _, t in ipairs(K.enemiesIn(c, center, 8)) do
			K.reveal(c, t, 0.4)
		end
		for i = 0, 2 do
			local a = math.rad(rot + i * 120)
			local d = Vector3.new(math.cos(a), 0, math.sin(a))
			local from = center + Vector3.new(0, K.m(1), 0)
			local to = from + d * K.m(8)
			K.FX.beam(from, to, 0.6, LIGHT, 0.12, 0.2)
			for _, h in ipairs(K.Hit.segment(from, to, K.m(0.6), K.enemyFilter(c))) do
				local t = h.f
				if not lastHit[t] or K.now() - lastHit[t] >= 1.5 then
					local dm = math.min(80, 250 - (totals[t] or 0))
					if dm > 0 then
						lastHit[t] = K.now()
						totals[t] = (totals[t] or 0) + dm
						K.dmg(c, t, dm, { fromPos = from })
					end
				end
			end
		end
		task.wait(0.1)
	end
	if c.unstable and core.alive then
		K.telegraph(c, center, 8, 0.5, LIGHT)
		task.wait(0.5)
		K.circle(c, center, 8, { dmg = 120, color = LIGHT })
		-- Unshielded Radiance: the caster is revealed through cover afterward
		K.reveal(c, f, 4)
	end
	if core.alive then
		S.Objects.remove(core, "ended")
	end
end

return Kit
