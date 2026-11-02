-- 74 Rainbow — Seven chosen hues and a restrained spectrum (every hue also has a number and symbol)
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local HUES = {
	{ name = "Red", sym = "1", color = Color3.fromRGB(255, 60, 60) },
	{ name = "Orange", sym = "2", color = Color3.fromRGB(255, 150, 40) },
	{ name = "Yellow", sym = "3", color = Color3.fromRGB(255, 235, 60) },
	{ name = "Green", sym = "4", color = Color3.fromRGB(80, 220, 90) },
	{ name = "Blue", sym = "5", color = Color3.fromRGB(70, 140, 255) },
	{ name = "Indigo", sym = "6", color = Color3.fromRGB(90, 70, 200) },
	{ name = "Violet", sym = "7", color = Color3.fromRGB(190, 90, 255) },
}

local function hue(f)
	if f.state.whiteUntil and f.state.whiteUntil > K.now() then
		return nil
	end
	return HUES[f.state.hue]
end
local function show(f)
	local h = hue(f)
	K.res(f, "Hue", h and (h.sym .. " " .. h.name) or "White (locked)", nil, 1)
	local chosen = HUES[f.state.chosen or 1]
	K.res(f, "Balance to", chosen.sym .. " " .. chosen.name, nil, 2)
end
local function advance(f, n)
	f.state.hue = (f.state.hue - 1 + (n or 1)) % 7 + 1
	show(f)
end

-- apply the hue property once per cast to a struck enemy (defensive hues only on real enemy hits)
local function applyHue(c, t, h)
	if not h or c.data.hueApplied then
		return
	end
	c.data.hueApplied = true
	local f = c.f
	if h.name == "Green" and K.isReal(t) then
		K.heal(c, f, 15)
	elseif h.name == "Blue" and K.isReal(t) then
		K.shield(c, f, 20, 3, "BlueHue")
	elseif h.name == "Indigo" then
		K.reveal(c, t, 1)
	elseif h.name == "Violet" then
		K.slow(c, t, 0.1, 1, "VioletHue")
	end
end

-- Passive: Seven Hue Wheel
function Kit.passive.init(f)
	f.state.hue = 1
	f.state.chosen = 1
	show(f)
end
function Kit.passive.cast(f, c)
	c.data.hue = hue(f)
end
function Kit.passive.beforeDeal(f, target, info)
	local c = info.opts.cast
	local h = c and (c.data.laneHue or c.data.hue)
	if h and not c.data.offenseApplied and info.kind == "direct" then
		if h.name == "Red" then
			c.data.offenseApplied = true
			info.amount += 15
		elseif h.name == "Orange" then
			c.data.offenseApplied = true
			info.guardDmg = (info.guardDmg or 0) + 10
		end
	end
end
function Kit.passive.dealt(f, target, info)
	local c = info.opts.cast
	if c and c.data.hue and not c.data.laneHue then
		applyHue(c, target, c.data.hue)
	end
end
-- V chooses the hue White Balance will reset to
function Kit.action(f)
	f.state.chosen = (f.state.chosen % 7) + 1
	show(f)
end

local function finish(c)
	if c.slot <= 4 and c.slot ~= 4 then
		advance(c.f, 1)
	end
end

-- 1 Spectrum Bolt
Kit[1] = function(c)
	local h = c.data.hue
	local range = 20 + ((h and h.name == "Yellow") and 2 or 0)
	K.proj(c, { range = range, width = 0.45, color = h and h.color or Color3.new(1, 1, 1), dmg = 65, tags = { spectrum = true }, data = { hue = h } })
	finish(c)
end

-- 2 Prism Skip (hold 0.4 s to skip one extra hue)
Kit[2] = function(c)
	local f = c.f
	local held = c:hold(0.4)
	if held >= 0.38 then
		advance(f, 1)
		c.data.hue = hue(f)
	end
	local h = c.data.hue
	K.dash(c, c:dir(), 5, 0.2)
	if h and h.name == "Green" then
		K.heal(c, f, 15)
	elseif h and h.name == "Blue" then
		K.shield(c, f, 20, 3, "BlueHue")
	end
	if c.p60 then
		-- 0.5 s of slow resistance after landing
		K.every(0.05, 0.5, function()
			K.cleanse(f, "slow", 3)
			return true
		end)
	end
	finish(c)
end

-- 3 Colour Panel — one own Spectrum Bolt passing through splits into two 40-damage rays
Kit[3] = function(c)
	local f = c.f
	local pos = c:aimPoint(12)
	local h = c.data.hue
	local dir = c:dir()
	local cf = CFrame.lookAt(pos + Vector3.new(0, K.m(1.2), 0), pos + Vector3.new(0, K.m(1.2), 0) + dir)
	local panel = K.object(c, { name = "ColourPanel", cf = cf, size = Vector3.new(2.5, 2.4, 0.2), hp = 130, duration = 6, color = h and h.color or Color3.new(1, 1, 1), material = Enum.Material.Glass, transparency = 0.35 })
	local used = false
	panel.onProjectile = function(obj, p)
		if used or p.owner ~= f or not p.tags.spectrum then
			return nil
		end
		used = true
		local struck = {}
		local base = p.vel.Unit
		local from = obj.part.Position + base * K.m(0.6)
		for _, a in ipairs({ -12, 12 }) do
			K.proj(c, {
				origin = from,
				dir = K.rotate(base, a),
				range = 16,
				width = 0.35,
				color = obj.part.Color,
				filter = function(t)
					return K.isEnemy(f, t) and not struck[t]
				end,
				hit = function(t)
					struck[t] = true
					K.dmg(c, t, 40)
					applyHue(c, t, h)
				end,
			})
		end
		return "stop"
	end
	finish(c)
end

-- 4 White Balance (does not apply or advance a hue)
Kit[4] = function(c)
	local f = c.f
	f.state.hue = f.state.chosen or 1
	f.state.whiteUntil = nil
	show(f)
	K.shield(c, f, 80, 3, "WhiteBalance")
	if c.p60 then
		K.cleanse(f, "slow", 1)
	end
	c.recovery = 0.8
end

-- 5 Sevenfold Horizon (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(18)
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local totals = {}
	local order = { 1, 2, 3, 4, 5, 6, 7 }
	if c.unstable then
		order = { 1, 2, 3, 4, 7, 6, 5 }
	end
	for n, i in ipairs(order) do
		local h = HUES[i]
		local laneCenter = center + side * K.m((i - 4) * 1)
		local from = laneCenter - dir * K.m(3.5)
		if c.unstable and n == 5 then
			task.wait(0.8) -- clear pause before the reversed lanes
		end
		K.telegraphLine(c, from, dir, 7, 0.9, 0.5, h.color)
		K.FX.text(from + Vector3.new(0, 2, 0), h.sym, h.color, 0.8, 24)
		task.wait(0.5)
		local first = true
		for _, t in ipairs(K.enemiesLine(c, from, dir, 7, 0.9)) do
			if (totals[t] or 0) < 4 then
				totals[t] = (totals[t] or 0) + 1
				c.data.laneHue = h
				c.data.offenseApplied = false
				K.dmg(c, t, 45, { fromPos = from })
				if first then
					first = false
					c.data.hueApplied = false
					applyHue(c, t, h)
				end
			end
		end
	end
	c.data.laneHue = nil
	if c.unstable then
		f.state.whiteUntil = K.now() + 5
		show(f)
		K.after(5, show, f)
	end
end

return Kit
