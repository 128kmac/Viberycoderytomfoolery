-- 32 Energy — Storage and efficient release
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local GREEN = Color3.fromRGB(80, 255, 220)

local function setCell(f, v)
	f.state.cell = math.clamp(v, 0, 100)
	K.res(f, "Cell", math.floor(f.state.cell), 100, 1)
end

-- Passive: Reserve Cell — every 10 unused Energy regenerated adds 5 Cell (max 15 Cell per 5 s)
function Kit.passive.init(f)
	setCell(f, 0)
	f.state.lastEnergy = f.energy
	f.state.acc = 0
	f.state.window = { t = K.now(), n = 0 }
end
function Kit.passive.tick(f, dt, now)
	local regen = 0
	if f.energy > f.state.lastEnergy then
		regen = f.energy - f.state.lastEnergy
	elseif f.energy >= 100 and now - f.lastEnergySpend >= 1.25 then
		regen = 12 * dt -- regeneration wasted at full Energy
	end
	f.state.lastEnergy = f.energy
	f.state.acc += regen
	if now - f.state.window.t >= 5 then
		f.state.window = { t = now, n = 0 }
	end
	while f.state.acc >= 10 do
		f.state.acc -= 10
		if f.state.window.n < 15 then
			local add = math.min(5, 15 - f.state.window.n)
			f.state.window.n += add
			setCell(f, f.state.cell + add)
		end
	end
end
function Kit.passive.cast(f)
	f.state.lastEnergy = f.energy
end

-- 1 Kinetic Pellet
Kit[1] = function(c)
	local f = c.f
	local held = c:hold(0.5)
	local charged = held >= 0.45 and f.state.cell >= 20
	if charged then
		setCell(f, f.state.cell - 20)
	end
	local pierced = false
	K.proj(c, {
		range = 22,
		speed = charged and 16 or 26,
		width = charged and 0.8 or 0.5,
		color = GREEN,
		dmg = charged and 100 or 65,
		hit = function(t)
			if charged then
				K.knock(c, t, f.root.Position, 1)
			end
		end,
		step = function(p)
			if charged and c.p60 and not pierced then
				for _, ep in ipairs(K.enemyProj(c, p.pos, 1)) do
					if ep.kind ~= "ultimate" and (ep.dmg or 60) <= 60 then
						pierced = true
						S.Proj.stop(ep, "pierced")
						break
					end
				end
			end
		end,
	})
end

-- 2 Capacitor Shell
Kit[2] = function(c)
	local f = c.f
	local spent = math.min(40, f.state.cell)
	if spent <= 0 then
		K.notify(f, "No Cell")
		return
	end
	setCell(f, f.state.cell - spent)
	local amount = spent * 3
	local ally
	if c.p60 then
		for _, a in ipairs(K.alliesIn(c, f.root.Position, 6, false)) do
			ally = a
			break
		end
	end
	if ally then
		K.shield(c, f, amount / 2, 4, "Capacitor")
		K.shield(c, ally, amount / 2, 4, "Capacitor")
	else
		K.shield(c, f, amount, 4, "Capacitor")
	end
	K.after(3.95, function()
		for _, sh in ipairs(f.shields) do
			if sh.name == "Capacitor" then
				setCell(f, f.state.cell + spent / 2 * math.clamp(sh.amount / amount, 0, 1))
			end
		end
	end)
end

-- 3 Vector Vent
Kit[3] = function(c)
	local f = c.f
	local full = f.state.cell >= 15
	if full then
		setCell(f, f.state.cell - 15)
	end
	local dir = c:dir()
	local behind = f.root.Position
	local hits = K.cone(c, { origin = behind, dir = -dir, range = 4, angle = 80, dmg = full and 70 or 35, color = GREEN })
	if c.p60 and #hits > 0 then
		f.heat = math.max(0, f.heat - 10)
	end
	K.dash(c, dir, full and 6 or 3, 0.2)
end

-- 4 Overcharge Relay
Kit[4] = function(c)
	local f = c.f
	local deposit = math.min(30, f.state.cell)
	setCell(f, f.state.cell - deposit)
	local pos = c:aimPoint(12)
	local relay = K.object(c, { name = "Relay", pos = pos, size = 1.2, hp = 120, duration = 5, color = GREEN, material = Enum.Material.Neon })
	relay.data.cell = deposit
	K.every(0.1, 5, function()
		if not relay.alive then
			return false
		end
		for _, a in ipairs(K.alliesIn(c, pos, 1.5, false)) do
			K.addEnergy(a, math.min(20, 10 + relay.data.cell))
			if c.p60 then
				K.shield(c, a, 40, 3, "Relay")
			end
			S.Objects.remove(relay, "collected")
			return false
		end
		local engine = K.partner(c, "Engine", 2, pos)
		if engine then
			engine.state.torque = (engine.state.torque or 0) + 20
			S.Objects.remove(relay, "collected")
			return false
		end
		return true
	end)
	c:recast(5, function(c2)
		if relay.alive then
			local d = 60 + relay.data.cell
			S.Objects.remove(relay, "detonated")
			K.circle(c2, pos, 3, { dmg = d, color = GREEN })
		end
	end)
end

-- 5 Total Discharge (ultimate)
Kit[5] = function(c)
	local f = c.f
	local stored = math.min(100, f.state.cell)
	setCell(f, f.state.cell - stored)
	local per = 50 + stored / 4
	local dir = c:dir3()
	c:channel(2, {
		tick = 0.5,
		onTick = function()
			-- turning limited to 20 degrees per second
			local want = c:dir3()
			local ang = math.deg(math.acos(math.clamp(dir:Dot(want), -1, 1)))
			if ang > 0.1 then
				dir = dir:Lerp(want, math.min(1, 10 / ang)).Unit
			end
			c:face(dir)
			K.beam(c, { dir = dir, length = 20, width = 1.2, dmg = per, color = GREEN, dur = 0.45 })
		end,
	})
	if c.unstable then
		K.beam(c, { dir = dir, length = 20, width = 2, dmg = 120, color = Color3.fromRGB(200, 255, 240), dur = 0.5 })
		f.energy = 0
		f.noEnergyRegen = true
		K.after(3, function()
			f.noEnergyRegen = nil
		end)
	end
end

return Kit
