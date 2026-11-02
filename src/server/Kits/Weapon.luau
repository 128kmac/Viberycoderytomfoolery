-- 97 Weapon — A deliberately limited conjured arsenal
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local STEEL = Color3.fromRGB(190, 190, 210)
local STANCES = { "Blade", "Shield", "Bow" }

local function setStance(f, name)
	local prevMax = f.maxGuard or 100
	local frac = f.guard / prevMax
	f.state.stance = name
	f.maxGuard = name == "Shield" and 115 or 100
	-- preserve the fraction already missing
	f.guard = frac * f.maxGuard
	K.res(f, "Stance", name, nil, 1)
end

-- Passive: Three Tool Rack
function Kit.passive.init(f)
	setStance(f, "Blade")
end
function Kit.passive.cleanup(f)
	f.maxGuard = nil
end
function Kit.basic(f)
	local st = f.state.stance
	if st == "Bow" then
		f.basicInterval = 0.8
		local c = S.Cast.newCtx(f, 1, f.kitData.moves[1])
		K.proj(c, { range = 18, speed = 30, width = 0.3, shape = "Block", size = Vector3.new(0.2, 0.2, 1.4), color = STEEL, kind = "physical", dmg = 45, isBasic = true, noProxima = true })
		return
	end
	f.basicInterval = nil
	S.Fighter.defaultBasic(f, 60, st == "Blade" and 3 or 2.5)
end
function Kit.passive.cast(f, c)
	local arm = f.state.armory
	if arm and c.slot == 1 then
		K.addEnergy(f, c.def.energy or 10) -- Arsenal Shift costs no Energy during the window
	end
end

-- 1 Arsenal Shift
Kit[1] = function(c)
	local f = c.f
	local i = table.find(STANCES, f.state.stance) or 1
	local nextStance = STANCES[(c.mod and (i - 2) or i) % 3 + 1]
	setStance(f, nextStance)
	K.FX.highlight(f.model, STEEL, 0.25, 0.5)
	if c.p60 then
		K.shield(c, f, 20, 1, "Arsenal")
	end
end

-- 2 Signature Action
local function signature(c, enhanced)
	local f = c.f
	local st = f.state.stance
	if st == "Blade" then
		K.melee(c, { range = 4, arc = 120, dmg = enhanced and 125 or 95, guardDmg = c.p60 and 15 or 0, color = STEEL })
	elseif st == "Shield" then
		K.melee(c, {
			range = 3,
			arc = 80,
			dmg = enhanced and 90 or 65,
			color = STEEL,
			hit = function(t)
				K.push(c, t, c:dir(), c.p60 and 3 or 2)
			end,
		})
	else
		K.proj(c, { range = c.p60 and 25 or 22, speed = 36, width = 0.4, shape = "Block", size = Vector3.new(0.3, 0.3, 2), color = STEEL, kind = "physical", dmg = enhanced and 120 or 90 })
	end
end
Kit[2] = function(c)
	local f = c.f
	local arm = f.state.armory
	local enhanced = false
	if arm and not arm.used[f.state.stance] then
		arm.used[f.state.stance] = true
		enhanced = true
	end
	signature(c, enhanced)
	if arm then
		K.setCd(f, 2, 2)
	end
end

-- 3 Planted Standard
Kit[3] = function(c)
	local f = c.f
	local pos = c:aimPoint(12)
	local standard = K.object(c, { name = "PlantedStandard", pos = pos, size = Vector3.new(0.4, 3, 0.4), hp = 150, duration = 7, color = STEEL, material = Enum.Material.Metal })
	if K.partner(c, "Steel", 15) then
		S.Objects.reinforce(standard, 40)
	end
	local radius = c.p60 and 4 or 3
	local buffed = {}
	K.zone(c, {
		pos = pos,
		radius = radius,
		duration = 7,
		targets = "allies",
		includeOwner = true,
		color = STEEL,
		transparency = 0.85,
		enter = function(_, a)
			buffed[a] = true
			a.guardRecoverMult = 1.08
		end,
		exit = function(_, a)
			buffed[a] = nil
			a.guardRecoverMult = nil
		end,
		finish = function()
			for a in pairs(buffed) do
				a.guardRecoverMult = nil
			end
		end,
		tickFn = function(z)
			if not standard.alive then
				z:remove("standard gone")
			end
		end,
	})
	c:recast(7, function()
		if standard.alive and K.flatDist(standard.part.Position, f) <= 5 then
			S.Objects.remove(standard, "retrieved")
			K.addEnergy(f, 6)
		else
			return "keep"
		end
	end)
end

-- 4 Countertool
Kit[4] = function(c)
	local f = c.f
	local st = f.state.stance
	if st == "Bow" then
		K.dash(c, -c:dir(), c.p60 and 5 or 4, 0.2)
		return
	end
	local done = false
	local window = st == "Blade" and 0.25 or 0.5
	K.FX.highlight(f.model, STEEL, window, 0.5)
	if st == "Blade" then
		K.hook(f, "beforeTake", function(_, info)
			if done or not info.opts.melee or K.Combat.facingAngle(f, info.fromPos) > 60 then
				return
			end
			done = true
			info.cancel = true
			K.announce(f, "PARRY", STEEL, 0.6)
			if c.p60 then
				K.shield(c, f, 30, 3, "Countertool")
			end
		end, window)
	else
		K.every(0.02, window, function()
			if done then
				return false
			end
			for _, p in ipairs(K.enemyProj(c, f.root.Position, 2.2)) do
				if p.kind ~= "ultimate" then
					done = true
					S.Proj.stop(p, "blocked")
					if c.p60 then
						K.shield(c, f, 30, 3, "Countertool")
					end
					return false
				end
			end
			return true
		end)
	end
	c:channel(window, { stationary = false })
end

-- 5 Armory in Motion (ultimate)
Kit[5] = function(c)
	local f = c.f
	local arm = { used = {} }
	f.state.armory = arm
	K.setCd(f, 2, 0)
	local form = c:form(8, {
		onEnd = function()
			f.state.armory = nil
		end,
	})
	K.FX.highlight(f.model, STEEL, 8, 0.7)
	if c.unstable then
		c:recast(8, function(c2)
			-- Empty Rack: release the unspent enhancements as spectral tools along one marked lane
			local dir = c2:dir()
			local origin = c2:feet()
			K.telegraphLine(c2, origin, dir, 14, 2, 0.6 * 3, STEEL)
			form.finish("released")
			for _, name in ipairs(STANCES) do
				if not arm.used[name] then
					arm.used[name] = true
					task.wait(0.6)
					local dmg = name == "Blade" and 125 or (name == "Shield" and 90 or 120)
					K.line(c2, origin, dir, 14, 2, { dmg = dmg, color = STEEL })
				end
			end
		end)
	end
end

return Kit
