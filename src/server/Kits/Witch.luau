-- 99 Witch — Prepared curses and a vulnerable familiar
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local VIOLET = Color3.fromRGB(110, 60, 150)

local function hex(f, t, n)
	if t.isSummon then
		return
	end
	local st = K.debuff(f, t, "Hex", { duration = 6, stacks = n or 1, max = 3, category = "curse", label = "Hex", data = { cleanseAll = true } })
	if st then
		st.data.cleanseAll = true
	end
end

-- Passive: Three Hex Marks
function Kit.passive.dealt(f, target, info)
	local c = info.opts.cast
	if c and info.kind == "direct" and not info.opts.noHex then
		hex(f, target, 1)
	end
end

local function familiar(f)
	for _, s in ipairs(K.summons(f, "Familiar")) do
		if K.alive(s) then
			return s
		end
	end
	return nil
end

-- 1 Needle Hex (curves at most 15 degrees toward the aim point during its first half)
Kit[1] = function(c)
	local aim = c:aimPoint(18) + Vector3.new(0, 2, 0)
	local dir = c:dir3()
	local turned = 0
	K.proj(c, {
		dir = K.rotate(dir, 8),
		range = 18,
		width = 0.3,
		shape = "Block",
		size = Vector3.new(0.25, 0.25, 1.2),
		color = VIOLET,
		dmg = 65,
		step = function(p)
			if p.traveled < K.m(9) and turned < 15 then
				local want = (aim - p.pos)
				if want.Magnitude > 1 then
					local cur = p.vel.Unit
					local ang = math.deg(math.acos(math.clamp(cur:Dot(want.Unit), -1, 1)))
					local stepA = math.min(ang, 2, 15 - turned)
					if stepA > 0.01 and ang > 0.01 then
						turned += stepA
						p.vel = cur:Lerp(want.Unit, stepA / ang).Unit * p.speed
					end
				end
			end
		end,
		finish = function(pos, reason)
			if c.p60 and reason ~= "hit" then
				K.FX.disc(K.ground(pos), K.m(1), VIOLET, 3, 0.5) -- harmless ritual marker
			end
		end,
	})
end

-- 2 Familiar Watch
Kit[2] = function(c)
	local f = c.f
	local old = familiar(f)
	if old then
		S.Summons.remove(old, "replaced")
	end
	local center = c:aimPoint(12)
	local fam = K.summon(c, { name = "Familiar", pos = center + Vector3.new(0, 2, 0), hp = 100, duration = 7, speed = 7, size = Vector3.new(0.8, 0.8, 1.2), shape = "Block", color = Color3.fromRGB(30, 20, 40), flying = 1.5, ai = "none" })
	local moved = false
	local seen = {}
	K.every(0.1, 7, function(i)
		if not K.alive(fam) then
			return false
		end
		local a = i * 0.12
		local p = center + Vector3.new(math.cos(a) * K.m(4), 2, math.sin(a) * K.m(4))
		fam.root.CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a)))
		for _, t in ipairs(K.enemiesIn(f, center, 5)) do
			if not seen[t] and K.los(fam, t) then
				seen[t] = true
				K.mark(f, t, "Watched", 1, { label = "Watched", color = VIOLET })
				K.reveal(f, t, 1)
			end
		end
		for t in pairs(seen) do
			if not K.alive(t) or K.flatDist(t, center) > 5 then
				seen[t] = nil
			end
		end
		return true
	end)
	if c.p60 then
		c:recast(7, function(c2)
			if not moved then
				moved = true
				center = K.ground(center + K.flat(c2:aimPoint(30) - center) * K.m(3))
			end
		end)
	end
end

-- 3 Conditional Curse (modifier = Shelter, otherwise Haste)
Kit.requires = {
	[3] = function(c)
		if c:target(14, { filter = function(t)
			return K.stacks(t, "Hex") >= 2
		end }) then
			return true
		end
		return false, "Needs a target with two Hexes"
	end,
}
Kit[3] = function(c)
	local f = c.f
	local t = c:target(14, { filter = function(t)
		return K.stacks(t, "Hex") >= 2
	end })
	if not t then
		return
	end
	K.S.Status.removeStacks(t, "Hex", 2)
	local condition = c.mod and "Shelter" or "Haste"
	K.mark(c, t, "Condition", 3, { label = "Condition: " .. condition, color = VIOLET })
	K.FX.text(t.root, condition, VIOLET, 3, 28)
	local fired = false
	local function trigger()
		if fired then
			return
		end
		fired = true
		K.unmark(t, "Condition")
		if c.p60 then
			hex(f, t, 1)
		end
	end
	if condition == "Haste" then
		local unsub
		unsub = S.on("dashed", function(who)
			if who == t and not fired then
				unsub()
				trigger()
				local at = K.feet(t)
				K.telegraph(c, at, 1.5, 0.5, VIOLET)
				K.after(0.5, function()
					K.circle(c, at, 1.5, { dmg = 80, color = VIOLET })
				end)
			end
		end)
		K.after(3, function()
			if not fired then
				fired = true
				unsub()
			end
		end)
	else
		K.every(0.05, 3, function()
			if fired or not K.alive(t) then
				return false
			end
			if t.guarding then
				trigger()
				t.guard = math.max(0, t.guard - 35)
				if t.guard <= 0 then
					K.Combat.guardBreak(t, f)
				end
				return false
			end
			return true
		end)
	end
end

-- 4 Broom Crossing
Kit[4] = function(c)
	local f = c.f
	if c.p60 then
		K.shield(c, f, 40, 1, "Broom")
	end
	local start = f.root.Position
	local dir = c:dir()
	local dest = K.Hit.clearPath(start + Vector3.new(0, K.m(2), 0), dir, K.m(8), 1.2)
	K.path(c, function(a)
		if not c:valid() then
			return f.root.Position
		end
		local p = (start + Vector3.new(0, K.m(2), 0)):Lerp(dest, a)
		if a > 0.85 then
			p -= Vector3.new(0, K.m(2) * (a - 0.85) / 0.15, 0)
		end
		return p
	end, 1)
	if c.p60 then
		K.Combat.removeShield(f, "Broom")
	end
end

-- 5 The Third Bell (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(18)
	local bell = K.object(c, { name = "RitualBell", pos = center, size = Vector3.new(1.4, 2, 1.4), hp = 250, duration = 5, isUlt = true, color = VIOLET, material = Enum.Material.Metal })
	K.FX.ring(center, K.m(7), VIOLET, 4.5, 0.3)
	for toll = 1, 3 do
		task.wait(1.2)
		if not bell.alive then
			return -- destroying the bell cancels remaining tolls
		end
		if c.unstable and toll == 3 then
			local fam = familiar(f)
			if fam then
				-- the familiar carries the bell 3 m with a full 1 s destination warning
				local dest = K.ground(center + K.flat(c:aimPoint(30) - center) * K.m(3))
				K.telegraph(c, dest, 7, 1, VIOLET)
				task.wait(1)
				if not bell.alive or not K.alive(fam) then
					return
				end
				bell.hp = math.min(bell.hp, fam.health)
				center = dest
				bell.part.CFrame = CFrame.new(dest + Vector3.new(0, K.m(1), 0))
			end
		end
		K.FX.sound(bell.part.Position, "ping", 1)
		K.FX.burst(center + Vector3.new(0, 1, 0), K.m(7), VIOLET, 0.35)
		for _, t in ipairs(K.enemiesIn(c, center, 7)) do
			if toll == 1 then
				hex(f, t, 1)
			elseif toll == 2 then
				K.dmg(c, t, 90, { fromPos = center, noHex = true })
			else
				local n = math.min(3, K.stacks(t, "Hex"))
				if n > 0 then
					K.Status.remove(t, "Hex", "consumed")
					K.dmg(c, t, 35 * n, { fromPos = center, noHex = true })
				end
			end
		end
	end
end

return Kit
