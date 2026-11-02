-- 88 Steel — Tempering and durable combat tools
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local STEEL = Color3.fromRGB(170, 180, 190)

local function setTemper(f, n)
	f.state.temper = math.clamp(n, 0, 3)
	K.res(f, "Temper", f.state.temper, 3, 1)
end
local function tempered(c)
	if c.f.state.temper >= 3 then
		setTemper(c.f, 0)
		return true
	end
	return false
end

-- Passive: Tempered Edge
function Kit.passive.init(f)
	setTemper(f, 0)
end
function Kit.passive.dealt(f, target, info)
	local c = info.opts.cast
	if c and c.slot <= 3 and not c.data.tempered and not c.data.temperGained then
		c.data.temperGained = true
		setTemper(f, f.state.temper + 1)
	end
end
function Kit.passive.guarded(f)
	local now = K.now()
	if not f.state.lastGuardTemper or now - f.state.lastGuardTemper > 0.5 then
		f.state.lastGuardTemper = now
		setTemper(f, f.state.temper + 1)
	end
end
function Kit.passive.tick(f, dt, now)
	if f.state.temper > 0 and now - (f.lastContest or 0) > 8 then
		setTemper(f, 0)
	end
	-- an allied Fire hit can grant one Temper per 6 s (Synergy)
end
function Kit.passive.cast(f, c)
	if c.slot <= 3 then
		c.data.tempered = tempered(c)
	end
end

-- 1 Forged Spear
Kit[1] = function(c)
	local f = c.f
	local t3 = c.data.tempered
	K.proj(c, {
		range = 16,
		width = 0.4,
		shape = "Block",
		size = Vector3.new(0.4, 0.4, 3),
		color = STEEL,
		kind = "physical",
		dmg = 85,
		guardDmg = t3 and 30 or 0,
		finish = function(pos, reason)
			if t3 and reason ~= "hit" then
				local spear = K.object(c, { name = "PlantedSpear", cf = CFrame.new(K.ground(pos) + Vector3.new(0, K.m(1), 0)), size = Vector3.new(0.3, 2, 0.3), hp = 100, duration = 5, color = STEEL, material = Enum.Material.Metal })
				spear.data.forged = true
				if c.p60 then
					K.every(0.1, 5, function()
						if not spear.alive then
							return false
						end
						if K.flatDist(spear.part.Position, f) <= 3 and f.humanoid and f.humanoid.Jump then
							S.Objects.remove(spear, "retrieved")
							K.addEnergy(f, 8)
							return false
						end
						return true
					end)
				end
			end
		end,
	})
end

-- 2 Plate Mantle
Kit[2] = function(c)
	local f = c.f
	local t3 = c.data.tempered
	K.shield(c, f, t3 and 180 or 130, 5, "PlateMantle")
	K.after(c.p60 and 1.5 or 0, function()
		K.debuff(c, f, "PlateWeight", { duration = c.p60 and 3.5 or 5, slow = 0.1, removable = false, label = "Plate (-10%)" })
	end)
	if t3 then
		local rm
		rm = K.hook(f, "beforeDisplace", function(_, info)
			if info.dist <= K.m(2.5) then
				info.cancel = true
				rm()
			end
		end, 5)
	end
end

-- 3 Rivet Line
Kit[3] = function(c)
	local t3 = c.data.tempered
	local origin = c:feet()
	local dir = c:dir()
	local totals = {}
	for i = 1, 4 do
		local p = K.ground(origin + dir * K.m(i * 2))
		K.FX.beam(p + Vector3.new(0, 2, 0), p, 0.4, STEEL, 0.2)
		for _, t in ipairs(K.enemiesIn(c, p, 1.2)) do
			if (totals[t] or 0) < 3 then
				totals[t] = (totals[t] or 0) + 1
				K.dmg(c, t, 25, { fromPos = p })
			end
		end
		if i == 4 and t3 then
			local brace = K.wall(c, { name = "RivetBrace", pos = p, dir = dir, width = 2.5, height = 1, thick = 0.4, hp = 100, duration = c.p60 and 6 or 4, color = STEEL, material = Enum.Material.Metal, transparency = 0 })
			brace.data.forged = true
		end
		task.wait(0.08)
	end
end

-- 4 Reforge (not a forging ability for Temper consumption)
Kit[4] = function(c)
	local f = c.f
	local ok = c:channel(1, { stationary = not c.p60, halfSpeed = c.p60 })
	if not ok then
		return
	end
	for _, o in ipairs(K.owned(f)) do
		if o.data.forged and K.flatDist(o.part.Position, f) <= 5 then
			S.Objects.heal(o, 70)
			K.FX.highlight(o.part, Color3.fromRGB(255, 200, 120), 0.5, 0.3)
			return
		end
	end
	for _, sh in ipairs(f.shields) do
		if sh.name == "PlateMantle" then
			sh.amount = math.min(180, sh.amount + 60)
			return
		end
	end
	K.notify(f, "Nothing to reforge nearby")
end

-- 5 Foundry Champion (ultimate)
Kit[5] = function(c)
	local f = c.f
	K.shield(c, f, 160, 8, "Foundry")
	local swings = 3
	local done = false
	local form = c:form(8, {
		onEnd = function()
			done = true
		end,
	})
	K.FX.highlight(f.model, STEEL, 8, 0.7)
	c:recast(8, function(c2)
		if done then
			return nil
		end
		if c.unstable and c2.mod then
			-- Quenched Too Fast: expend all remaining swings in one 160-damage anvil drop
			K.Combat.removeShield(f, "Foundry")
			local pos = c2:aimPoint(8)
			K.telegraph(c2, pos, 4, 1, STEEL)
			task.wait(1)
			K.FX.beam(pos + Vector3.new(0, 20, 0), pos, K.m(3), STEEL, 0.3)
			K.circle(c2, pos, 4, { dmg = 160, color = STEEL })
			swings = 0
			form.finish("anvil")
			return nil
		end
		K.FX.highlight(f.model, Color3.fromRGB(255, 255, 255), 0.6, 0.6)
		if not c2:wait(0.6) then
			return "keep"
		end
		K.melee(c2, { range = 5, arc = 140, dmg = 110, color = STEEL })
		swings -= 1
		if swings > 0 then
			return "keep"
		end
		form.finish("swings spent")
		return nil
	end)
end

return Kit
