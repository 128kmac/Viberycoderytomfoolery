-- 75 Reptile — Scale management and deliberate shedding
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local GREEN = Color3.fromRGB(80, 140, 60)

local function setPlates(f, n)
	local maxP = f.state.form and 6 or 4
	f.state.plates = math.clamp(n, 0, maxP)
	K.res(f, "Plates", f.state.plates, maxP, 1)
end

-- Passive: Scale Plates
function Kit.passive.init(f)
	setPlates(f, 4)
	f.state.lastPlate = 0
end
function Kit.passive.beforeTake(f, info)
	if info.kind ~= "direct" then
		return
	end
	local now = K.now()
	if f.state.plates > 0 and now - f.state.lastPlate >= 1.5 then
		f.state.lastPlate = now
		setPlates(f, f.state.plates - 1)
		info.amount = math.max(0, info.amount - 15)
	end
end
function Kit.passive.tick(f, dt, now)
	if f.state.form then
		return -- lost Plates do not regenerate during the form
	end
	if now - (f.lastHit or 0) >= 3 and f.state.plates < 4 then
		f.state.regen = (f.state.regen or 0) + dt
		if f.state.regen >= 3 then
			f.state.regen = 0
			setPlates(f, f.state.plates + 1)
		end
	else
		f.state.regen = 0
	end
end

-- 1 Tail Sweep (front of the chest is a safe gap)
Kit[1] = function(c)
	local f = c.f
	local reach = c.p60 and 5 or 4
	local fwd = K.flat(f.root.CFrame.LookVector)
	local dmg = 80 + (f.state.form and 20 or 0)
	K.FX.ring(c:feet(), K.m(reach), GREEN, 0.3, K.m(0.8))
	for _, t in ipairs(K.enemiesIn(c, f.root.Position, reach)) do
		local to = K.flat(t.root.Position - f.root.Position)
		if to:Dot(fwd) < 0.2 then
			K.dmg(c, t, dmg, { melee = true })
			K.knock(c, t, f.root.Position, 1.5)
		end
	end
end

-- 2 Wall Grip
local function wallAhead(c)
	return K.Hit.raycast(c:chest(), K.flat(c.f.root.CFrame.LookVector) * K.m(2))
end
Kit.requires = {
	[2] = function(c)
		if wallAhead(c) then
			return true
		end
		return false, "No wall to grip"
	end,
}
Kit[2] = function(c)
	local f = c.f
	local res = wallAhead(c)
	if not res then
		return
	end
	local released = false
	local h = K.hover(f, 5, 3, 1)
	local rm
	rm = K.hook(f, "taken", function(_, info)
		if info.kind == "direct" and not released then
			released = true
			h.stop()
			rm()
		end
	end, 3)
	f.noBasic = true
	f.disabled = { [1] = true, [3] = true, [4] = true }
	K.after(3, function()
		released = true
		f.noBasic = nil
		f.disabled = nil
		if c.p60 then
			K.setCd(f, 1, 0)
		end
	end)
	c:recast(3, function()
		if not released then
			released = true
			h.stop()
			f.noBasic = nil
			f.disabled = nil
			if c.p60 then
				K.setCd(f, 1, 0)
			end
		end
	end)
end

-- 3 Shed Skin
Kit[3] = function(c)
	local f = c.f
	local n = f.state.plates
	setPlates(f, 0)
	if K.cleanse(f, "slow", 1) == 0 then
		K.cleanse(f, "poison", 1)
	end
	local skin = K.object(c, { name = "ShedSkin", pos = c:feet(), size = Vector3.new(1.4, 2.6, 1.4), hp = 80, duration = 4, solid = false, color = GREEN, material = Enum.Material.Glass, transparency = 0.5 })
	skin.onProjectile = function(obj)
		S.Objects.destroy(obj, nil)
		return "stop"
	end
	if c.p60 then
		skin.onDestroy = function()
			setPlates(f, f.state.plates + 1)
		end
	end
	if n > 0 then
		K.shield(c, f, 15 * n, 3, "ShedSkin")
	end
end

-- 4 Basking Rush
Kit[4] = function(c)
	local f = c.f
	local bonus = f.state.plates >= 3
	local rm = K.hook(f, "taken", function()
		bonus = false
	end, 0.8)
	K.FX.highlight(f.model, Color3.fromRGB(255, 220, 120), 0.8, 0.6)
	if not c:channel(0.8) then
		rm()
		return
	end
	rm()
	local struck = false
	K.dash(c, c:dir(), 7, 0.3, {
		passWidth = 1.8,
		onPass = function(t)
			if not struck then
				struck = true
				K.dmg(c, t, bonus and 130 or 110, { melee = true })
			end
		end,
	})
end

-- 5 Ancient Scale Form (ultimate)
Kit[5] = function(c)
	local f = c.f
	f.state.form = true
	local savedPlates = f.state.plates
	setPlates(f, 6)
	f.hitScale = 1.15
	pcall(function()
		f.model:ScaleTo(1.15)
	end)
	K.FX.highlight(f.model, GREEN, 8, 0.7)
	local form
	local function endForm()
		f.state.form = nil
		f.hitScale = 1
		pcall(function()
			f.model:ScaleTo(1)
		end)
		setPlates(f, math.min(4, savedPlates))
	end
	form = c:form(8, { onEnd = endForm })
	if c.unstable then
		c:recast(8, function(c2)
			-- Brittle Renewal: all six Plates shed at once into a 150-damage ring
			setPlates(f, 0)
			K.ringHit(c2, c2:feet(), 0, 4, { dmg = 150, color = GREEN })
			form.finish("shed")
		end)
	end
end

return Kit
