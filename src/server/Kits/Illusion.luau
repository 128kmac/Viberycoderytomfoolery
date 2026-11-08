-- 47 Illusion — False information with truthful rules
-- Illusions deceive about in-world objects only: never health, gauges, controls or consent.
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local LILAC = Color3.fromRGB(220, 140, 255)
local RunService = game:GetService("RunService")

local function setDeception(f, n)
	f.state.deception = math.clamp(n, 0, 3)
	K.res(f, "Deception", f.state.deception, 3, 1)
end

-- a decoy: a hittable 1-hit body with a cosmetic copy of the caster
local function decoy(c, cf, duration, opts)
	local f = c.f
	opts = opts or {}
	local model = K.decoyModel(f, cf)
	local hit = K.object(c, {
		name = "Illusion",
		cf = cf,
		size = Vector3.new(1.4, 4.4, 1),
		hp = opts.hp or 1,
		duration = duration,
		solid = false,
		blocks = opts.blocks ~= false,
		transparency = 1,
		noLabel = true,
		isUlt = opts.isUlt,
	})
	hit.data.model = model
	hit.data.illusion = true
	hit.onDamage = function(obj, _, src)
		if src and K.isEnemy(f, src) and not obj.data.tested then
			obj.data.tested = true
			setDeception(f, (f.state.deception or 0) + 1)
			if opts.onReveal then
				opts.onReveal(obj)
			end
		end
	end
	hit.cleanup = function()
		if model.Parent then
			for _, p in ipairs(model:GetChildren()) do
				if p:IsA("BasePart") then
					p.Transparency = 0.8
				end
			end
			game:GetService("Debris"):AddItem(model, 0.2)
		end
	end
	-- spend Deception to extend an ordinary illusion by 1 s
	if not opts.isUlt and (f.state.deception or 0) > 0 and opts.extend then
		setDeception(f, f.state.deception - 1)
		hit.expires += 1
	end
	return hit
end

local function moveDecoy(d, cf)
	if d.alive then
		d.part.CFrame = cf
		if d.data.model and d.data.model.Parent then
			d.data.model:PivotTo(cf)
		end
	end
end

local function illusions(f)
	local out = {}
	for _, o in ipairs(K.owned(f, "Illusion")) do
		table.insert(out, o)
	end
	return out
end

function Kit.passive.init(f)
	setDeception(f, 0)
	f.state.hist = {}
end
function Kit.passive.tick(f, dt, now)
	table.insert(f.state.hist, { t = now, cf = f.root.CFrame })
	while #f.state.hist > 0 and now - f.state.hist[1].t > 1.2 do
		table.remove(f.state.hist, 1)
	end
end

-- 1 False Spear (the real spear carries a bright notch)
Kit[1] = function(c)
	local realFirst = not c.mod
	local dir = c:dir3()
	for i = 1, 2 do
		local real = (i == 1) == realFirst
		local opts = {
			dir = dir,
			range = 20,
			width = 0.4,
			shape = "Block",
			size = Vector3.new(0.4, 0.4, 2.4),
			color = LILAC,
		}
		if real then
			opts.dmg = 75
			opts.step = function(p)
				if p.part and not p.data.notched then
					p.data.notched = true
					local notch = K.FX.base({ size = Vector3.new(0.5, 0.5, 0.5), cf = p.part.CFrame * CFrame.new(0, 0, -1.2), color = Color3.fromRGB(255, 255, 255) })
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = p.part
					weld.Part1 = notch
					weld.Parent = notch
					notch.Anchored = false
					game:GetService("Debris"):AddItem(notch, 2)
				end
			end
		else
			opts.filter = function()
				return false
			end
			opts.noObjects = false
			if c.p60 then
				local t = c:target(20)
				opts.homing = t
				opts.turnRate = 60
			end
		end
		K.proj(c, opts)
		if i == 1 then
			task.wait(0.3)
		end
	end
end

-- 2 Stage Double — replays the caster's last second of movement
Kit[2] = function(c)
	local f = c.f
	local hist = table.clone(f.state.hist)
	local start = hist[1] and hist[1].cf or f.root.CFrame
	local d = decoy(c, start, 4, { extend = true, onReveal = function(obj)
		S.Objects.remove(obj, "revealed")
	end })
	K.FX.spawnCtx(function()
		local t0 = K.now()
		local base = hist[1] and hist[1].t or t0
		while d.alive do
			local elapsed = (K.now() - t0) % 1.1
			local cf = start
			for _, h in ipairs(hist) do
				if h.t - base <= elapsed then
					cf = h.cf
				end
			end
			-- after the recording, continue forward along the last heading
			if K.now() - t0 > 1.1 then
				cf = d.part.CFrame + K.flat(d.part.CFrame.LookVector) * (K.m(6) * 0.03)
			end
			moveDecoy(d, cf)
			RunService.Heartbeat:Wait()
		end
	end)
end

-- 3 False Door (collision never changes)
Kit[3] = function(c)
	local f = c.f
	local pos = c:aimPoint(14)
	local dir = c:dir()
	local fake = K.FX.base({ size = Vector3.new(K.m(3), K.m(2.6), K.m(0.4)), cf = CFrame.lookAt(pos + Vector3.new(0, K.m(1.3), 0), pos + Vector3.new(0, K.m(1.3), 0) + dir), color = Color3.fromRGB(120, 85, 70), transparency = 0, material = Enum.Material.Brick })
	game:GetService("Debris"):AddItem(fake, 5)
	K.every(0.1, 5, function()
		if not fake.Parent then
			return false
		end
		local near = false
		for _, t in ipairs(K.Hit.cylinder(pos, K.m(2), function()
			return true
		end)) do
			near = true
			local _ = t
		end
		fake.Transparency = near and 0.7 or 0
		return true
	end)
	local _ = f
end

-- 4 Curtain Call
Kit[4] = function(c)
	local f = c.f
	local list = illusions(f)
	local extra = math.min(3, f.state.deception or 0)
	setDeception(f, (f.state.deception or 0) - extra)
	local dmg = math.min(130, 100 + 10 * extra)
	local centers = {}
	for _, o in ipairs(list) do
		table.insert(centers, K.ground(o.part.Position))
		S.Objects.remove(o, "curtain")
	end
	if #centers == 0 then
		table.insert(centers, c:aimPoint(12))
	end
	local hit = {}
	for _, p in ipairs(centers) do
		K.FX.burst(p + Vector3.new(0, 1.5, 0), K.m(4), Color3.fromRGB(255, 255, 255), 0.4)
		for _, t in ipairs(K.enemiesIn(c, p, 4)) do
			if not hit[t] then
				hit[t] = true
				K.dmg(c, t, dmg, { fromPos = p })
			end
		end
	end
	if c.p60 then
		local p = centers[1]
		decoy(c, CFrame.new(p + Vector3.new(0, 3, 0)) * f.root.CFrame.Rotation, 3, {})
	end
end

-- 5 The Audience Is Wrong (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	local list = {}
	for i = 1, 5 do
		local a = math.rad(i * 72)
		local p = K.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(4)) + Vector3.new(0, 3, 0)
		list[i] = decoy(c, CFrame.lookAt(p, Vector3.new(center.X, p.Y, center.Z)), 6, {
			isUlt = true,
			onReveal = function(obj)
				if c.unstable then
					K.reveal(c, f, 1) -- Broken Masquerade
				end
				S.Objects.remove(obj, "revealed")
			end,
		})
	end
	local swaps = c.unstable and 3 or 2
	c:recast(6, function(c2)
		local aim = c2:aimPoint(30)
		local best, bd
		for _, d in ipairs(list) do
			if d.alive then
				local dist = (d.part.Position - aim).Magnitude
				if not bd or dist < bd then
					best, bd = d, dist
				end
			end
		end
		if not best then
			return nil
		end
		-- destination shows the real-tip notch 0.5 s before arrival
		K.FX.sphere(best.part.Position + Vector3.new(0, 3, 0), 0.7, Color3.fromRGB(255, 255, 255), 0.5, 0)
		task.wait(0.5)
		if best.alive then
			local myCF = f.root.CFrame
			local dest = best.part.Position
			S.Fighter.teleport(f, dest)
			moveDecoy(best, myCF)
		end
		swaps -= 1
		if swaps > 0 then
			return "keep"
		end
		return nil
	end)
end

return Kit
