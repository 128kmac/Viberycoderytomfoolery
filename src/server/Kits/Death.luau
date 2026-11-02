-- 21 Death — Attrition marks and a contestable execution
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local PALE = Color3.fromRGB(190, 210, 190)

local function omen(c, t, extra)
	return K.debuff(c, t, "Omen", { duration = 7 + (extra or 0), stacks = 1, max = 4, category = "curse", label = "Omen" })
end

-- Passive: Mortal Ledger
function Kit.passive.dealt(f, target, info)
	local c = info.opts.cast
	if c and info.kind == "direct" and not c.data.omened and not info.opts.isBasic and not target.isSummon and not info.opts.noOmen then
		c.data.omened = true
		omen(f, target, c.data.omenExtra)
	end
end
function Kit.passive.tick(f)
	f.state.hp = f.state.hp or {}
	for _, t in ipairs(K.enemies(f, 60)) do
		if K.has(t, "Omen") then
			local last = f.state.hp[t]
			if last and t.health > last and t.health >= t.maxHealth * 0.7 then
				K.S.Status.removeStacks(t, "Omen", 1)
			end
			f.state.hp[t] = t.health
		end
	end
end

-- 1 Pale Crescent
Kit[1] = function(c)
	local aim = c:aimPoint(17) + Vector3.new(0, 2, 0)
	local dir = c:dir3()
	local start = K.rotate(dir, 25)
	if c.p60 then
		c.data.omenExtra = 2
	end
	local turned = false
	K.proj(c, {
		dir = start,
		speed = 18,
		range = 17,
		width = 0.8,
		shape = "Block",
		size = Vector3.new(2.4, 0.3, 0.6),
		color = PALE,
		dmg = 75,
		step = function(p)
			if not turned and p.traveled >= K.m(4) then
				turned = true
				local to = aim - p.pos
				if to.Magnitude > 1 then
					p.vel = to.Unit * p.speed
				end
			end
		end,
	})
end

-- 2 Grave Step
Kit[2] = function(c)
	local f = c.f
	local seal = K.object(c, { name = "GraveSeal", pos = c:feet(), size = Vector3.new(1.4, 0.3, 1.4), hp = 70, duration = 3.2, solid = false, color = PALE, material = Enum.Material.Slate })
	K.dash(c, c:dir(), 6, 0.25)
	c:recast(3, function(c2)
		if seal.alive and K.Hit.spaceFree(K.Hit.standAt(K.ground(seal.part.Position))) then
			K.blink(c2, seal.part.Position, { throughWalls = true })
			S.Objects.remove(seal, "returned")
			if c2.p60 then
				K.shield(c2, f, 60, 3, "GraveStep")
			end
		end
	end)
end

-- 3 Last Toll
Kit.requires = {
	[3] = function(c)
		local t = c:target(12, { filter = function(t)
			return K.has(t, "Omen")
		end })
		if t then
			return true
		end
		return false, "Needs an Omen-marked target"
	end,
	[5] = function(c)
		local t = c:target(14, { filter = function(t)
			return K.stacks(t, "Omen") >= 4
		end })
		if t then
			return true
		end
		return false, "Needs a four-Omen target"
	end,
}
Kit[3] = function(c)
	local f = c.f
	local t = c:target(12, { filter = function(t)
		return K.has(t, "Omen")
	end })
	if not t then
		return
	end
	K.FX.ring(K.feet(t), K.m(1.5), PALE, 1, 0.3)
	K.FX.sound(t.root, "ping", 0.8)
	if c.p60 then
		K.slow(c, t, 0.2, 1, "Tolling")
	end
	task.wait(1)
	local n = K.stacks(t, "Omen")
	if n > 0 and K.alive(t) then
		K.unmark(t, "Omen")
		K.dmg(c, t, 35 * n, { noOmen = true, unblockable = false })
		if c.p60 and f.state.debt and f.state.debt.pending > 0 then
			f.state.debt.pending = math.max(0, f.state.debt.pending - 40)
		end
	end
end

-- 4 Borrowed Breath
Kit[4] = function(c)
	local f = c.f
	local deferred = 0
	local debt = { pending = 0 }
	f.state.debt = debt
	K.buff(f, "BorrowedBreath", { duration = 3, label = "Borrowed Breath" })
	local rm = K.hook(f, "beforeHealth", function(_, info)
		local room = 120 - deferred
		if room > 0 then
			local d = math.min(room, info.final)
			deferred += d
			info.final -= d
			K.res(f, "Debt", math.floor(deferred / 2), nil, 2)
		end
	end, 3)
	local _ = rm
	K.after(3, function()
		debt.pending = deferred / 2 -- the other half is prevented
		local per = debt.pending / 8
		K.every(0.5, 4, function()
			if debt.pending <= 0 or not K.alive(f) then
				K.clearRes(f, "Debt")
				return false
			end
			local d = math.min(per, debt.pending)
			debt.pending -= d
			K.Combat.damage(nil, f, d, { kind = "true", tag = "debt" })
			K.res(f, "Debt", math.floor(debt.pending), nil, 2)
			return true
		end)
	end)
end

-- 5 Reaper's Hearing (ultimate)
Kit[5] = function(c)
	local f = c.f
	local t = c:target(14, { filter = function(t)
		return K.stacks(t, "Omen") >= 4
	end })
	if not t then
		return
	end
	local threshold = c.unstable and 0.2 or 0.15
	K.mark(c, t, "Hearing", 2, { label = "REAPER'S HEARING", color = PALE })
	K.announce(t, "HEARING", PALE, 2)
	local broken = false
	local t0 = K.now()
	while K.now() - t0 < 2 do
		task.wait(0.1)
		if not K.alive(t) or K.dist(f, t) > 14 or not K.los(f, t) or not K.alive(f) then
			broken = true
			break
		end
	end
	if broken then
		if c.unstable and K.alive(f) then
			K.Combat.damage(nil, f, 150, { kind = "true", tag = "backlash" })
		end
		return
	end
	K.FX.beam(t.root.Position + Vector3.new(0, 10, 0), t.root.Position, 1.5, PALE, 0.3)
	K.dmg(c, t, 260, { noOmen = true })
	if K.alive(t) and t.health < t.maxHealth * threshold and not t.isBoss then
		K.dmg(c, t, 150, { noOmen = true })
	end
end

return Kit
