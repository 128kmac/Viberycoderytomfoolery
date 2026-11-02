-- 22 Defensive — Interception and disciplined protection
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local BLUE = Color3.fromRGB(90, 140, 200)

local function setResolve(f, n)
	f.state.resolve = math.clamp(n, 0, 3)
	K.res(f, "Resolve", f.state.resolve, 3, 1)
end

-- Passive: Bastion Rhythm
function Kit.passive.init(f)
	setResolve(f, 0)
end
function Kit.passive.perfectGuard(f, src, info)
	if info.kind ~= "direct" or src == f or info.opts.area then
		return
	end
	f.guard = math.min(100, f.guard + 12)
	setResolve(f, f.state.resolve + 1)
end
function Kit.passive.cast(f, c)
	if (f.state.resolve or 0) > 0 and not c.data.noResolve then
		setResolve(f, f.state.resolve - 1)
		K.shield(f, f, 20, 4, "Resolve")
	end
end

-- 1 Shield Check
Kit[1] = function(c)
	local hits = K.melee(c, {
		range = 3,
		arc = 90,
		color = BLUE,
		hit = function(t)
			local windup = t.action and t.action.phase == "windup"
			K.dmg(c, t, 65, { melee = true, guardDmg = windup and 25 or 0 })
			K.push(c, t, c:dir(), 2)
		end,
	})
	if #hits > 0 and c.p60 then
		K.dash(c, c:dir(), 1, 0.1)
	end
	c.recovery = #hits > 0 and 0.2 or 0.35
end

-- 2 Bulwark Panel
Kit[2] = function(c)
	local panel = K.wall(c, {
		name = "BulwarkPanel",
		pos = c:aimPoint(10),
		dir = c:dir(),
		width = 3.5,
		height = 2.6,
		hp = 260,
		duration = 5,
		allyPass = true,
		color = BLUE,
		material = Enum.Material.ForceField,
	})
	if c.p60 then
		c:recast(5, function()
			if panel.alive then
				panel.part.CFrame *= CFrame.Angles(0, math.rad(90), 0)
			end
		end)
	end
end

-- 3 Intercept Line
Kit[3] = function(c)
	local f = c.f
	local ally = c:ally(10)
	local dest = ally and ally.root.Position or c:aimPoint(10)
	local dir = K.flat(dest - f.root.Position)
	local dist = math.min(10, K.flatDist(dest, f) - (ally and 1.2 or 0))
	local intercepted = false
	task.spawn(function()
		local t0 = K.now()
		while K.now() - t0 < 0.4 and not intercepted do
			for _, p in ipairs(K.enemyProj(c, f.root.Position, 1.6)) do
				if p.kind ~= "ultimate" then
					intercepted = true
					S.Proj.stop(p, "intercepted")
					K.FX.burst(f.root.Position, 3, BLUE, 0.25)
					break
				end
			end
			task.wait(0.03)
		end
	end)
	K.dash(c, dir, math.max(0.5, dist), 0.35)
	if c.p60 and ally then
		K.shield(c, ally, 100, 2, "Intercept")
	else
		K.shield(c, f, 100, 2, "Intercept")
	end
end

-- 4 Hold the Gate
Kit[4] = function(c)
	local f = c.f
	local stopped = {}
	K.buff(f, "HoldTheGate", { duration = 4, label = "Hold the Gate" })
	K.hook(f, "beforeTake", function(_, info)
		if K.Combat.facingAngle(f, info.fromPos) <= 60 then
			info.amount *= 0.6
		end
	end, 4)
	K.FX.cone(f.root.Position, K.flat(f.root.CFrame.LookVector), K.m(5), 90, BLUE, 4)
	c:channel(4, {
		tick = 0.05,
		onTick = function()
			for _, t in ipairs(K.enemiesCone(c, 5, 90, f.root.Position, K.flat(f.root.CFrame.LookVector), false)) do
				local lv = t.root:FindFirstChild("EBDisplace")
				if lv and not stopped[t] then
					stopped[t] = true
					lv:Destroy()
					t.root.AssemblyLinearVelocity = Vector3.zero
					K.slow(c, t, 0.35, 1.5, "Gate")
					K.FX.burst(t.root.Position, 2, BLUE, 0.2)
					if c.p60 then
						setResolve(f, f.state.resolve + 1)
					end
				end
			end
		end,
	})
end

-- 5 Citadel Stance (ultimate)
Kit[5] = function(c)
	local f = c.f
	local base = c:feet()
	local panels = {}
	for i = 0, 3 do
		local a = math.rad(i * 90)
		local d = Vector3.new(math.cos(a), 0, math.sin(a))
		panels[i + 1] = K.wall(c, {
			name = "CitadelPanel",
			pos = K.ground(base + d * K.m(3)),
			dir = d,
			width = 4,
			height = 3,
			hp = 220,
			duration = 7,
			isUlt = true,
			allyPass = true,
			color = BLUE,
			material = Enum.Material.ForceField,
		})
	end
	c:recast(7, function(c2)
		local alive = 0
		for _, p in ipairs(panels) do
			if p.alive then
				alive += 1
				S.Objects.remove(p, "folded")
			end
		end
		local per = c.unstable and 120 or 60
		local amount = math.min(c.unstable and 360 or 180, per * alive)
		for _, a in ipairs(K.alliesIn(c2, f.root.Position, 7, true)) do
			K.shield(c2, a, amount, 5, c.unstable and "CitadelUnstable" or "Citadel")
		end
		K.FX.burst(f.root.Position, K.m(7), BLUE, 0.4)
		if c.unstable then
			f.guard = 0
			K.Combat.control(f, "root", 2, f, { force = true })
		end
	end)
end

return Kit
