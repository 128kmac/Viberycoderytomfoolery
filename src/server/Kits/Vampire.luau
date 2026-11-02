-- 94 Vampire — Recoverable aggression and a costly retreat (no resurrection)
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local CRIMSON = Color3.fromRGB(140, 0, 40)

-- Passive: Living Hunger — 12% of actual health damage, capped at 40 per cast
function Kit.passive.dealt(f, target, info)
	local c = info.opts.cast
	if not c or info.kind ~= "direct" or info.final <= 0 or target.isSummon or info.opts.noHunger then
		return
	end
	if f.burnoutUntil and f.burnoutUntil > K.now() then
		return
	end
	if f.state.court and f.state.court.noPassive then
		return
	end
	local got = c.data.hunger or 0
	local h = math.min(40 - got, info.final * 0.12)
	if h > 0 then
		c.data.hunger = got + h
		K.heal(f, f, h, { noProxima = true })
	end
end

-- 1 Crimson Bite
Kit[1] = function(c)
	local f = c.f
	local struck
	K.dash(c, c:dir(), c.p60 and 3 or 2, 0.15, {
		passWidth = 1.6,
		stopOnHit = true,
		onPass = function(t)
			struck = struck or t
		end,
	})
	local hits = K.melee(c, { range = 3, arc = 70, color = CRIMSON, hit = function(t)
		local low = t.health < t.maxHealth * 0.5
		K.dmg(c, t, 85, { melee = true })
		if low then
			K.heal(c, f, 15)
		end
	end })
	local _ = struck
	local __ = hits
end

-- 2 Bat Passage
Kit[2] = function(c)
	local f = c.f
	if c.p60 then
		K.cleanse(f, "slow", 1)
	end
	K.dr(f, 0.2, 0.7, "Bat Swarm")
	f.hitScale = 0.6
	local restore = K.conceal(f, 0.7, 0.85)
	K.FX.highlight(f.model, CRIMSON, 0.7, 0.4)
	K.dash(c, c:dir(), 7, 0.7)
	restore()
	f.hitScale = 1
end

-- 3 Sanguine Tether
Kit[3] = function(c)
	local f = c.f
	K.proj(c, {
		range = 12,
		width = 0.4,
		color = CRIMSON,
		dmg = 40,
		hit = function(t)
			local broken = false
			local grace = c.p60 and 0.2 or 0
			local blind = 0
			local rm = K.hook(f, "taken", function(_, info)
				if info.kind == "direct" then
					broken = true
				end
			end, 2.1)
			local n = 0
			K.every(0.1, 2.1, function(i)
				if broken or not K.alive(t) or not K.alive(f) or K.dist(f, t) > 12 then
					return false
				end
				if not K.los(f, t) then
					blind += 0.1
					if blind > grace + 0.01 then
						return false
					end
				else
					blind = 0
				end
				K.FX.beam(c:chest(), t.root.Position, 0.12, CRIMSON, 0.12)
				if i % 7 == 0 and n < 3 then
					n += 1
					K.dmg(c, t, 25, { kind = "field", noHunger = true })
					K.heal(c, f, 15)
				end
				return true
			end)
			local _ = rm
		end,
	})
end

-- 4 Night Feast (passive healing cap is shared across all victims)
Kit[4] = function(c)
	local f = c.f
	local hits = K.melee(c, { range = 6, arc = 100, dmg = 100, color = CRIMSON })
	local real = 0
	for _, t in ipairs(hits) do
		if K.isReal(t) then
			real += 1
		end
	end
	if real >= 2 then
		K.shield(c, f, 50, c.p60 and 4 or 3, "NightFeast")
	end
end

-- 5 Crimson Court (ultimate)
Kit[5] = function(c)
	local f = c.f
	local court = { lunges = c.unstable and 4 or 3, used = 0, last = 0 }
	f.state.court = court
	K.speed(f, 0.15, 7, "Crimson Court")
	K.FX.highlight(f.model, CRIMSON, 7, 0.6)
	f.basicOverride = function(ff)
		if court.used >= court.lunges or K.now() - court.last < 1 then
			return
		end
		court.used += 1
		court.last = K.now()
		local cc = S.Cast.newCtx(ff, 5, c.def)
		cc.isUlt = true
		local struck = false
		local dir = cc:dir()
		K.dash(cc, dir, 5, 0.22, {
			passWidth = 1.8,
			onPass = function(t)
				if not struck then
					struck = true
					K.dmg(cc, t, 90, { melee = true, noHunger = true })
					-- Hunger Without Rest: no self-healing after the third lunge
					if court.used <= 3 then
						K.heal(cc, ff, 35)
					end
				end
			end,
		})
	end
	f.basicInterval = 0.3
	c:form(7, {
		onEnd = function()
			f.basicOverride = nil
			f.basicInterval = nil
			f.state.court = nil
		end,
	})
end

return Kit
