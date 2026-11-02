-- 90 Technology — A small network of readable devices (in-world states only; never fake system alerts)
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local TECH = Color3.fromRGB(0, 170, 255)

local function devices(f)
	local out = {}
	for _, d in ipairs(K.summons(f)) do
		if d.data.device and K.alive(d) then
			table.insert(out, d)
		end
	end
	table.sort(out, function(a, b)
		return (a.data.made or 0) < (b.data.made or 0)
	end)
	return out
end
local function shutDown(f)
	return f.state.shutdownUntil and f.state.shutdownUntil > K.now()
end

local function device(c, opts)
	local f = c.f
	local list = devices(f)
	if #list >= 3 then
		S.Summons.remove(list[1], "replaced")
	end
	opts.ai = "none"
	opts.speed = 0
	opts.color = opts.color or TECH
	opts.shape = "Block"
	opts.material = Enum.Material.Metal
	local d = K.summon(c, opts)
	d.data.device = true
	d.data.made = K.now()
	d.controlImmune = true
	return d
end

-- Passive: Local Network — devices within 8 m share sight of exposed enemies
function Kit.passive.tick(f)
	local list = devices(f)
	K.res(f, "Devices", #list, 3, 1)
	for i = 1, #list do
		for j = i + 1, #list do
			if K.dist(list[i], list[j]) <= 8 then
				K.FX.beam(list[i].root.Position, list[j].root.Position, 0.08, TECH, 0.12, 0.5)
			end
		end
	end
end
local function exposedTo(f, d, rangeM)
	if shutDown(f) then
		return nil
	end
	local best, bd
	for _, t in ipairs(K.enemies(f, 40)) do
		local dist = K.dist(t, d)
		if dist <= rangeM and K.los(d, t) and (not bd or dist < bd) then
			best, bd = t, dist
		end
	end
	return best
end

-- 1 Arc Projector
Kit[1] = function(c)
	local f = c.f
	K.proj(c, {
		range = 18,
		width = 0.4,
		color = TECH,
		hit = function(t)
			local bonus = K.has(t, "Scanned") and 10 or 0
			K.dmg(c, t, 70 + bonus, { projectile = true })
			if c.p60 then
				K.notify(f, t.name .. " shield: " .. math.floor(K.totalShield(t)))
			end
		end,
	})
end

-- 2 Scout Node
Kit[2] = function(c)
	local f = c.f
	local pos = c:aimPoint(14)
	local dir = c:dir()
	local node = device(c, { name = "ScoutNode", pos = pos + Vector3.new(0, 1.5, 0), hp = 90, duration = 10, size = Vector3.new(0.8, 1, 0.8) })
	local range = c.p60 and 15 or 12
	K.every(1, 10, function()
		if not K.alive(node) then
			return false
		end
		if shutDown(f) then
			return true
		end
		K.FX.cone(node.root.Position, dir, K.m(range), 90, TECH, 0.3)
		for _, t in ipairs(K.enemiesCone(f, range, 90, node.root.Position, dir, true)) do
			K.mark(f, t, "Scanned", 1.1, { label = "Scanned", color = TECH })
			K.reveal(f, t, 1)
		end
		return true
	end)
end

-- 3 Sentry Pod
Kit[3] = function(c)
	local f = c.f
	local pos = c:aimPoint(12)
	local sentry = device(c, { name = "SentryPod", pos = pos + Vector3.new(0, 1.5, 0), hp = 140, duration = 7, size = Vector3.new(1, 1.2, 1) })
	local shots = c.p60 and 7 or 6
	local target
	local readyAt = 0
	K.every(0.1, 7, function()
		if not K.alive(sentry) or shots <= 0 then
			return false
		end
		if K.Status.has(sentry, "stun") or shutDown(f) then
			return true
		end
		local now = K.now()
		local hub = f.state.hub
		local acquire = (hub and hub.alive) and 0.4 or 0.5
		local t = exposedTo(f, sentry, 10)
		if t ~= target then
			target = t
			readyAt = now + acquire
		end
		if target and now >= readyAt then
			shots -= 1
			readyAt = now + 0.8
			K.proj(c, { origin = sentry.root.Position, dir = (target.root.Position - sentry.root.Position).Unit, range = 12, speed = 30, width = 0.3, color = TECH, dmg = 20 })
		end
		return true
	end)
end

-- 4 Field Service (modifier relocates instead of repairing)
Kit.requires = {
	[4] = function(c)
		if #devices(c.f) > 0 then
			return true
		end
		return false, "No device"
	end,
}
Kit[4] = function(c)
	local f = c.f
	local aim = c:aimPoint(10)
	local list = devices(f)
	table.sort(list, function(a, b)
		return (a.root.Position - aim).Magnitude < (b.root.Position - aim).Magnitude
	end)
	local d = list[1]
	if not c:channel(1) or not K.alive(d) then
		return
	end
	if c.mod then
		local dest = d.root.Position + K.flat(aim - d.root.Position) * math.min(K.m(4), (aim - d.root.Position).Magnitude)
		if K.Hit.los(d.root.Position, dest) then
			d.root.CFrame = CFrame.new(K.ground(dest) + Vector3.new(0, 1.5, 0))
		end
	else
		K.heal(c, d, 80, { force = true })
	end
end

-- 5 Command Network (ultimate)
Kit[5] = function(c)
	local f = c.f
	local pos = c:aimPoint(18)
	local hub = K.object(c, { name = "CommandHub", pos = pos, size = Vector3.new(1.6, 2, 1.6), hp = 300, duration = 8, isUlt = true, color = TECH, material = Enum.Material.Metal })
	f.state.hub = hub
	for i, d in ipairs(devices(f)) do
		if i <= 3 then
			K.shield(c, d, 40, 8, "Network")
		end
	end
	local pulses = 2
	local function pulse(cc, radius, dmg)
		local at = cc:aimPoint(30)
		K.telegraph(cc, at, radius, 1, TECH)
		task.wait(1)
		K.FX.beam(at + Vector3.new(0, 40, 0), at, K.m(1), TECH, 0.3)
		K.circle(cc, at, radius, { dmg = dmg, color = TECH })
	end
	c:recast(8, function(c2)
		if not hub.alive then
			return nil
		end
		if c.unstable and c2.mod and pulses == 2 then
			-- Emergency Shutdown: merge both pulses, then devices go dark for 4 s
			pulses = 0
			pulse(c2, 6, 170)
			f.state.shutdownUntil = K.now() + 4
			return nil
		end
		pulses -= 1
		pulse(c2, 4, 100)
		if pulses > 0 then
			return "keep"
		end
		return nil
	end)
end

return Kit
