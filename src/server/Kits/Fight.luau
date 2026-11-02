-- 37 Fight — Technical melee and stance reads
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local ORANGE = Color3.fromRGB(230, 120, 60)

local function setFocus(f, n)
	f.state.focus = math.clamp(n, 0, 2)
	K.res(f, "Focus", f.state.focus, 2, 1)
end
-- landing a strike, evading and guarding within 5 s earns Focus (Perfect Round: any two different)
local function action(f, kind)
	local now = K.now()
	f.state.acts[kind] = now
	local need = f.state.round and 2 or 3
	local n = 0
	for _, t in pairs(f.state.acts) do
		if now - t <= 5 then
			n += 1
		end
	end
	if n >= need then
		f.state.acts = {}
		setFocus(f, f.state.focus + 1)
	end
end

-- Passive: Clean Technique
function Kit.passive.init(f)
	f.state.acts = {}
	setFocus(f, 0)
end
function Kit.passive.dealt(f, target, info)
	if info.kind == "direct" and info.opts.melee then
		action(f, "strike")
	end
end
function Kit.passive.evaded(f)
	action(f, "evade")
end
function Kit.passive.guarded(f, src, info)
	action(f, "guard")
end
function Kit.passive.cast(f, c)
	if c.slot <= 4 and (f.state.focus or 0) > 0 then
		setFocus(f, f.state.focus - 1)
		c.recoveryBonus = 0.15
	end
end

-- 1 Three Point Combination
Kit[1] = function(c)
	local hits = K.melee(c, { range = 3, arc = 80, dmg = 20, color = ORANGE })
	local stage = 1
	local secondLanded = false
	local _ = hits
	c:recast(0.5, function(c2)
		stage += 1
		if stage == 2 then
			local h = K.melee(c2, { range = 3, arc = 80, dmg = 30, color = ORANGE })
			secondLanded = #h > 0
			c2.recovery = c.p60 and 0 or 0.2
			-- the kick window reopens only after the body blow
			c:recast(0.5, function(c3)
				if not secondLanded then
					K.notify(c.f, "Kick needs a landed body blow")
				end
				K.melee(c3, {
					range = 3.2,
					arc = 90,
					dmg = 45,
					color = ORANGE,
					hit = function(t)
						K.push(c3, t, c3:dir(), 2)
					end,
				})
			end)
		end
	end)
end

-- 2 Shoulder Entry
Kit[2] = function(c)
	local blocked = false
	local struck = false
	K.dash(c, c:dir(), 4, 0.22, {
		passWidth = 1.8,
		stopOnHit = true,
		onPass = function(t)
			if not struck then
				struck = true
				local _, result = K.dmg(c, t, 80, { melee = true, guardDmg = c.p60 and 30 or 0 })
				blocked = result == "guarded"
			end
		end,
	})
	c.recovery = blocked and 0.5 or 0.3
end

-- 3 Counterhand
Kit[3] = function(c)
	local f = c.f
	local done = false
	K.FX.highlight(f.model, ORANGE, 0.4, 0.6)
	K.hook(f, "beforeTake", function(_, info)
		if done or not info.opts.melee or info.opts.grab or not info.src or not K.isEnemy(f, info.src) then
			return
		end
		done = true
		info.cancel = true
		local src = info.src
		K.dmg(c, src, 100, { melee = true })
		if src.humanoid and src.root then
			src.root.CFrame *= CFrame.Angles(0, math.rad(45), 0)
		end
		action(f, "guard")
		if c.p60 then
			setFocus(f, f.state.focus + 1)
		end
	end, 0.4)
	c:channel(0.4, { stationary = false })
end

-- 4 Hip Throw
Kit[4] = function(c)
	local f = c.f
	local target
	for _, t in ipairs(K.enemiesCone(c, 2.2, 100)) do
		local hum = t.humanoid
		if not t.isSummon and (not hum or hum.FloorMaterial ~= Enum.Material.Air) then
			target = t
			break
		end
	end
	if not target then
		c.recovery = 0.5
		return
	end
	if K.Combat.isInvulnerable(target) then
		K.dmg(c, target, 1)
		return
	end
	local side = K.flat(f.root.CFrame.RightVector)
	if c.p60 and c.mod then
		side = -side
	end
	local dir = (c:dir() * 0.4 + side).Unit
	K.dmg(c, target, 110, { melee = true, unblockable = true, grab = true })
	K.push(c, target, dir, 4, { up = 15 })
end

-- 5 Perfect Round (ultimate)
Kit[5] = function(c)
	local f = c.f
	f.state.round = true
	if c.unstable then
		f.noGuard = true
		f.guarding = false
	end
	K.FX.highlight(f.model, ORANGE, 6, 0.7)
	local used = false
	local form = c:form(6, {
		onEnd = function()
			f.state.round = nil
			f.noGuard = nil
		end,
	})
	c:recast(6, function(c2)
		if used then
			return
		end
		used = true
		local focus = f.state.focus
		setFocus(f, 0)
		-- a separate, dodgeable 0.4 s uppercut
		K.FX.highlight(f.model, Color3.fromRGB(255, 220, 120), 0.4, 0.4)
		if not c2:wait(0.4) then
			return
		end
		local dmg = c.unstable and 260 or math.min(200, 120 + 40 * focus)
		K.melee(c2, {
			range = 3,
			arc = 80,
			dmg = dmg,
			color = ORANGE,
			hit = function(t)
				K.lift(c2, t, 0.4, 2)
			end,
		})
		if not c.unstable then
			form.finish("uppercut")
		end
	end)
end

return Kit
