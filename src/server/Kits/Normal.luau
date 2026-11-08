-- 64 Normal — Fundamentals and economical adaptation
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local GREY = Color3.fromRGB(220, 220, 220)

-- Passive: Good Fundamentals — a different ability from the previous cast refunds 4 Energy afterwards
function Kit.passive.cast(f, c)
	if c.slot == 5 then
		return
	end
	local prev = f.state.prevSlot
	f.state.prevSlot = c.slot
	if prev and prev ~= c.slot then
		local energyMark = c
		K.FX.spawnCtx(function()
			while f.action == energyMark do
				task.wait(0.05)
			end
			if not energyMark.interrupted and K.alive(f) then
				K.addEnergy(f, 4)
			end
		end)
	end
	-- Perfect Execution discount
	if f.state.perfect then
		K.addEnergy(f, 6)
	end
end

local function perfectTrigger(f, slot)
	local pe = f.state.perfect
	if not pe or pe.used[slot] then
		return
	end
	pe.used[slot] = true
	-- reduce the cooldown of a different normal ability by 2 s
	local best, left = nil, 0
	for s = 1, 4 do
		if s ~= slot then
			local l = K.cdLeft(f, s)
			if l > left then
				best, left = s, l
			end
		end
	end
	if best then
		K.reduceCd(f, best, 2)
	end
end
function Kit.passive.guarded(f)
	if f.state.perfect and f.state.lastSlot then
		perfectTrigger(f, f.state.lastSlot)
	end
end
function Kit.passive.dealt(f, target, info)
	local c = info.opts.cast
	if c and c.slot <= 4 then
		f.state.lastSlot = c.slot
		perfectTrigger(f, c.slot)
	end
end

-- 1 Straight Strike
Kit[1] = function(c)
	K.melee(c, { range = 3, arc = 70, dmg = 80, guardDmg = c.p60 and 25 or 0, color = GREY })
	c.recovery = 0.25
end

-- 2 Practical Step (facing stays unchanged)
Kit[2] = function(c)
	local f = c.f
	local dir = f.humanoid and f.humanoid.MoveDirection or Vector3.zero
	if dir.Magnitude < 0.1 then
		dir = -K.flat(f.root.CFrame.LookVector)
	end
	local slow = K.Status.slow(f)
	local _ = slow
	K.dash(c, K.flat(dir), 4, 0.2)
	c.recovery = c.p60 and 0.15 or 0.3
end

-- 3 Firm Guard
Kit[3] = function(c)
	local f = c.f
	local used = false
	K.FX.highlight(f.model, GREY, 0.8, 0.6)
	K.hook(f, "beforeTake", function(_, info)
		if used or info.kind ~= "direct" then
			return
		end
		if K.Combat.facingAngle(f, info.fromPos) <= 60 then
			used = true
			info.amount *= 0.4
			f.guard = math.min(100, f.guard + 15)
			if c.p60 then
				K.hook(f, "beforeDisplace", function(_, d)
					d.cancel = true
				end, 0.1)
			end
		end
	end, 0.8)
	c:channel(0.8, { stationary = false, halfSpeed = true })
end

-- 4 Opportunist
Kit[4] = function(c)
	local struck = false
	local dir = c:dir()
	K.dash(c, dir, 3, 0.15, {
		passWidth = 1.6,
		stopOnHit = true,
		onPass = function(t)
			if not struck then
				struck = true
				local inRecovery = t.lockUntil and t.lockUntil > K.now() and not t.action
				K.dmg(c, t, inRecovery and 135 or 90, { melee = true })
				if c.p60 and inRecovery then
					K.mark(c, t, "Punished", 2, { label = "Punished", color = GREY })
				end
			end
		end,
	})
	if not struck then
		K.melee(c, { range = 2, arc = 70, dmg = 90, color = GREY })
	end
end

-- 5 Perfect Execution (ultimate)
Kit[5] = function(c)
	local f = c.f
	f.state.perfect = { used = {} }
	if c.unstable then
		K.setCd(f, 2, 0)
		f.noEnergyRegen = true
	end
	K.FX.highlight(f.model, Color3.fromRGB(255, 255, 255), 8, 0.85)
	c:form(8, {
		onEnd = function()
			f.state.perfect = nil
			f.noEnergyRegen = nil
		end,
	})
	local _ = S
end

return Kit
