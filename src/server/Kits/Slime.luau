-- 82 Slime — Viscosity changes and a conserved body
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local GEL = Color3.fromRGB(90, 255, 120)

local function setMode(f, mode)
	f.state.mode = mode
	f.speedMult = mode == "Fluid" and 1.1 or 0.9
	K.res(f, "Viscosity", mode, nil, 1)
	for _, p in ipairs(f.model:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			p.Material = mode == "Fluid" and Enum.Material.Glass or Enum.Material.Rubber
		end
	end
end

-- Passive: Viscosity — hold guard for 0.6 s without taking damage to switch
function Kit.passive.init(f)
	setMode(f, "Fluid")
end
function Kit.passive.cleanup(f)
	f.speedMult = 1
end
function Kit.passive.tick(f, dt, now)
	if f.guarding and now - (f.lastHit or 0) > 0.6 then
		f.state.guardHeld = (f.state.guardHeld or 0) + dt
		if f.state.guardHeld >= 0.6 and not f.state.switched then
			f.state.switched = true
			setMode(f, f.state.mode == "Fluid" and "Dense" or "Fluid")
		end
	else
		f.state.guardHeld = 0
		f.state.switched = false
	end
end
function Kit.passive.beforeTake(f, info)
	if info.kind == "direct" then
		info.amount *= f.state.mode == "Fluid" and 1.1 or 0.9
	end
end

-- 1 Gel Jab
Kit[1] = function(c)
	local fluid = c.f.state.mode == "Fluid"
	K.beam(c, { length = fluid and 7 or 4, width = 0.8, dmg = fluid and 70 or 90, color = GEL, dur = 0.3 })
	c.recovery = c.p60 and 0.2 or 0.35
end

-- 2 Sticky Patch (P60: recast while touching it to reclaim for 8 Energy)
Kit[2] = function(c)
	local f = c.f
	local pos = c:aimPoint(14)
	local core = K.object(c, { name = "StickyPatch", pos = pos, size = Vector3.new(1, 0.2, 1), hp = 100, duration = 6, solid = false, queryable = true, color = GEL, noLabel = false })
	local z = K.zone(c, {
		pos = pos,
		radius = 3,
		duration = 6,
		tick = 0.25,
		immediate = true,
		targets = "all",
		color = GEL,
		transparency = 0.4,
		tickFn = function(zz, list)
			if not core.alive then
				zz:remove("destroyed")
				return
			end
			for _, t in ipairs(list) do
				if K.isEnemy(f, t) then
					K.slow(c, t, 0.2, 0.4, "Sticky")
				elseif t == f and f.state.mode == "Fluid" then
					K.speed(f, 0.15, 0.4, "Slick")
				end
			end
		end,
	})
	if c.p60 then
		c:recast(6, function()
			if z.alive and z:contains(f) then
				z:remove("reclaimed")
				S.Objects.remove(core, "reclaimed")
				K.addEnergy(f, 8)
			else
				return "keep"
			end
		end)
	end
end

-- 3 Separate Self
Kit[3] = function(c)
	local f = c.f
	local pos = c:aimPoint(10)
	local blob = K.summon(c, { name = "SlimeBlob", pos = f.root.Position, hp = 100, duration = 5, speed = 9, size = Vector3.new(1.6, 1.2, 1.6), color = GEL, ai = "none" })
	S.Summons.moveTo(blob, K.Hit.standAt(pos))
	blob.sm.ai = "stay"
	if c.p60 then
		K.after(1, function()
			if K.alive(blob) then
				S.Summons.moveTo(blob, K.Hit.standAt(pos) + K.flat(pos - f.root.Position) * K.m(3))
			end
		end)
	end
	c:recast(5, function(c2)
		if not K.alive(blob) then
			return
		end
		local bp = blob.root.Position
		if K.Hit.los(f.root.Position, bp, true) then
			local mine = f.root.Position
			S.Summons.remove(blob, "swapped")
			K.blink(c2, K.ground(bp))
			K.FX.burst(mine, 3, GEL, 0.3)
		end
	end)
end

-- 4 Impact Reservoir (Dense only)
Kit.requires = {
	[4] = function(c)
		if c.f.state.mode == "Dense" then
			return true
		end
		return false, "Dense mode only"
	end,
}
Kit[4] = function(c)
	local f = c.f
	local stored = 0
	local used = false
	K.FX.highlight(f.model, GEL, 1, 0.5)
	K.hook(f, "beforeTake", function(_, info)
		if used or K.Combat.facingAngle(f, info.fromPos) > 60 then
			return
		end
		used = true
		local before = info.amount
		info.amount *= 0.5
		stored = math.min(80, before - info.amount)
	end, 1)
	c:recast(c.p60 and 3 or 2, function(c2)
		K.cone(c2, { range = 4, angle = 70, dmg = 40 + stored, color = GEL })
	end)
end

-- 5 Great Gel Tide (ultimate)
Kit[5] = function(c)
	local f = c.f
	local totals = {}
	local function waveHit(t, dmg, src, dir)
		if (totals[t] or 0) >= 2 then
			return
		end
		totals[t] = (totals[t] or 0) + 1
		K.Combat.damage(src, t, dmg, { cast = c, isUlt = true, fromPos = src.root.Position, element = "Slime" })
		K.push(c, t, dir, 2)
	end
	if not c.unstable then
		K.shield(c, f, 150, 5, "GelTide")
	end
	local sides = {}
	if c.unstable then
		for _, s in ipairs({ -1, 1 }) do
			local w = K.summon(c, { name = "SideWave", pos = f.root.Position + K.flat(f.root.CFrame.RightVector) * K.m(3 * s), hp = 80, duration = 5, speed = 7, size = Vector3.new(3, 1.2, 1.6), color = GEL, ai = "none" })
			w.data.side = s
			table.insert(sides, w)
		end
	end
	local hitMain, hitSide = {}, {}
	local t0 = K.now()
	f.hitScale = 1.3
	while K.now() - t0 < 5 and K.alive(f) do
		local fwd = K.flat(f.root.CFrame.LookVector)
		for _, t in ipairs(K.enemiesLine(c, f.root.Position - fwd * K.m(0.5), fwd, 2, 3)) do
			if not hitMain[t] then
				hitMain[t] = true
				waveHit(t, 110, f, fwd)
			end
		end
		for _, w in ipairs(sides) do
			if K.alive(w) then
				local p = f.root.Position + K.flat(f.root.CFrame.RightVector) * K.m(3 * w.data.side)
				w.root.CFrame = CFrame.lookAt(p, p + fwd)
				for _, t in ipairs(K.enemiesIn(f, p, 1.6)) do
					if not hitSide[t] then
						hitSide[t] = true
						waveHit(t, 70, w, fwd)
					end
				end
			end
		end
		task.wait(0.05)
	end
	f.hitScale = 1
end

return Kit
