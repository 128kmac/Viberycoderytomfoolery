-- 67 Phoenix — Recovery windows and one vulnerable rebirth
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local FLAME = Color3.fromRGB(255, 120, 30)

local function setEmbers(f, v)
	f.state.embers = math.clamp(v, 0, 50)
	K.res(f, "Embers", math.floor(f.state.embers), 50, 1)
end

-- Passive: Ember Reserve
function Kit.passive.init(f)
	setEmbers(f, 0)
end
function Kit.passive.dealt(f, target, info)
	local c = info.opts.cast
	if c and info.kind == "direct" and not c.data.embered then
		c.data.embered = true
		setEmbers(f, f.state.embers + 10)
	end
end
function Kit.passive.tick(f, dt, now)
	if now - (f.lastHit or 0) >= 3 and f.state.embers > 0 and f.health < f.maxHealth then
		local use = math.min(f.state.embers, 10 * dt)
		setEmbers(f, f.state.embers - use)
		K.heal(f, f, use * 1.5, { noProxima = true })
	end
end

-- 1 Cinder Wing
Kit[1] = function(c)
	local f = c.f
	local start = c:feet()
	K.cone(c, { range = 6, angle = 70, dmg = 75, color = FLAME })
	K.dash(c, -c:dir(), 3, 0.18)
	if c.p60 then
		K.delayed(c, start, 1.5, 0.7, function(p)
			K.circle(c, p, 1.5, { dmg = 30, color = FLAME })
		end, FLAME)
	end
end

-- 2 Ashen Ascent
Kit.requires = {
	[5] = function(c)
		if c.f.state.airborne then
			return false, "Cannot rebirth while airborne"
		end
		return true
	end,
}
Kit[2] = function(c)
	local f = c.f
	f.state.airborne = true
	local h = K.hover(f, 4, 2.4, 0.4)
	K.after(2.4, function()
		h.stop()
		f.state.airborne = nil
		K.FX.ring(K.feet(f), K.m(1.5), Color3.fromRGB(120, 110, 100), 1, 0.3)
	end)
end

-- 3 Warmth of Return
Kit[3] = function(c)
	local f = c.f
	local spent = math.min(30, f.state.embers or 0)
	setEmbers(f, f.state.embers - spent)
	local pos = c:aimPoint(10)
	local feather = K.object(c, { name = "WarmFeather", pos = pos, size = Vector3.new(0.4, 1.4, 0.4), hp = 120, duration = 6, solid = false, color = FLAME, material = Enum.Material.Neon })
	K.every(0.1, 6, function()
		if not feather.alive then
			return false
		end
		for _, a in ipairs(K.alliesIn(c, pos, 1.5, true)) do
			if not a.isSummon then
				K.heal(c, a, 60 + 2 * spent)
				if c.p60 then
					K.cleanse(a, "burn", 1)
				end
				S.Objects.remove(feather, "claimed")
				return false
			end
		end
		return true
	end)
end

-- 4 Searing Descent
Kit[4] = function(c)
	local f = c.f
	local target = c:aimPoint(12)
	local g = K.Hit.ground(f.root.Position, 40)
	local elevated = g and (f.root.Position.Y - g.Y) >= K.m(3) + 3 or false
	K.telegraph(c, target, 3, 0.5, FLAME)
	local start = f.root.Position
	local stand = K.Hit.standAt(target)
	K.path(c, function(a)
		return start:Lerp(stand, a * a) + Vector3.new(0, (1 - a) * K.m(1), 0)
	end, 0.5)
	local hits = K.circle(c, target, 3, { dmg = elevated and 130 or 100, color = FLAME })
	if c.p60 and elevated and #hits > 0 then
		setEmbers(f, f.state.embers + 10)
	end
end

-- 5 Second Dawn (ultimate) — one rescue per ultimate; the cocoon can be destroyed
Kit[5] = function(c)
	local f = c.f
	local restore = c.unstable and 400 or 250
	local cocoonHp = c.unstable and 150 or 250
	local pos = c:feet()
	local cocoon = K.object(c, { name = "Cocoon", pos = pos, size = Vector3.new(1.6, 2.4, 1.6), shape = "Ball", hp = cocoonHp, duration = 6, isUlt = true, color = FLAME, material = Enum.Material.Neon, transparency = 0.15 })
	local used = false
	local rm
	rm = K.hook(f, "beforeDefeat", function()
		if used or not cocoon.alive or (cocoon.part.Position - f.root.Position).Magnitude > K.m(10) then
			return false
		end
		used = true
		rm()
		-- become the cocoon for 2 seconds
		f.health = 1
		f.invulnCount += 1
		local restoreVis = K.conceal(f, 2.1, 1)
		S.Fighter.teleport(f, cocoon.part.Position + Vector3.new(0, 1, 0))
		f.stationary += 1
		K.announce(f, "SECOND DAWN", FLAME, 2)
		K.after(2, function()
			f.invulnCount = math.max(0, f.invulnCount - 1)
			f.stationary = math.max(0, f.stationary - 1)
			restoreVis()
			if cocoon.alive then
				S.Objects.remove(cocoon, "rebirth")
				f.health = restore
				S.Fighter.syncHealth(f)
				K.FX.burst(f.root.Position, K.m(4), FLAME, 0.5)
				if c.unstable then
					K.Combat.control(f, "root", 1, f, { force = true })
				end
				-- Ashbound Rebirth: Burnout follows emergence
				f.rupturePending = true
			else
				f.health = 0
				K.Combat.defeat(f, nil, nil)
			end
		end)
		return true
	end, 6)
	-- the cocoon itself absorbs damage aimed at the hidden Phoenix while it is the body
	-- while the Phoenix is the cocoon, only the cocoon itself can be damaged
	cocoon.cleanup = function()
		if not used then
			rm()
		end
	end
end

return Kit
