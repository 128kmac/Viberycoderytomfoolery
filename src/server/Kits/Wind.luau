-- 98 Wind — Directional acceleration and pressure lanes
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local GUST = Color3.fromRGB(190, 255, 230)

-- Passive: Tailwind — 3 m in one direction over 1 s adds 1 m to the next Wind movement ability
function Kit.passive.init(f)
	f.state.trail = {}
end
function Kit.passive.tick(f, dt, now)
	local hum = f.humanoid
	if not hum then
		return
	end
	if K.has(f, "root") then
		f.state.tailwind = false
	end
	local md = hum.MoveDirection
	if md.Magnitude > 0.1 then
		if f.state.lastDir and f.state.lastDir:Dot(md.Unit) < -0.3 then
			f.state.tailwind = false -- sharp reversal
			f.state.trail = {}
		end
		f.state.lastDir = md.Unit
	end
	table.insert(f.state.trail, { t = now, p = f.root.Position })
	while #f.state.trail > 0 and now - f.state.trail[1].t > 1 do
		table.remove(f.state.trail, 1)
	end
	local first = f.state.trail[1]
	if first and now - first.t >= 0.9 and K.flatDist(first.p, f) >= 3 then
		f.state.tailwind = true
	end
	K.res(f, "Tailwind", f.state.tailwind and "ready" or "-", nil, 1)
end
local function useTailwind(f)
	if f.state.tailwind then
		f.state.tailwind = false
		return 1
	end
	return 0
end

-- 1 Air Cutter
Kit[1] = function(c)
	K.proj(c, { range = 18, speed = 30, width = c.p60 and 0.7 or 0.4, shape = "Block", size = Vector3.new(c.p60 and 2.1 or 1.4, 0.2, 0.6), color = GUST, dmg = 70 })
end

-- 2 Gale Step (once in the air before landing)
Kit.requires = {
	[2] = function(c)
		local f = c.f
		local airborne = f.humanoid and f.humanoid.FloorMaterial == Enum.Material.Air
		if airborne and f.state.airDashUsed then
			return false, "Already used in the air"
		end
		return true
	end,
}
Kit[2] = function(c)
	local f = c.f
	if f.humanoid and f.humanoid.FloorMaterial == Enum.Material.Air then
		f.state.airDashUsed = true
		K.FX.spawnCtx(function()
			while K.alive(f) and f.humanoid.FloorMaterial == Enum.Material.Air do
				task.wait(0.1)
			end
			f.state.airDashUsed = nil
		end)
	end
	if c.p60 then
		K.cleanse(f, "slow", 1)
	end
	local dir = f.humanoid and f.humanoid.MoveDirection.Magnitude > 0.1 and K.flat(f.humanoid.MoveDirection) or c:dir()
	K.dash(c, dir, 6 + useTailwind(f), 0.22)
end

-- 3 Updraft Pillar
Kit[3] = function(c)
	local f = c.f
	local pos = c:aimPoint(14)
	local pillar = K.FX.base({ shape = Enum.PartType.Cylinder, size = Vector3.new(K.m(6), K.m(6), K.m(6)), cf = CFrame.new(pos + Vector3.new(0, K.m(3), 0)) * CFrame.Angles(0, 0, math.rad(90)), color = GUST, transparency = 0.8, material = Enum.Material.ForceField })
	game:GetService("Debris"):AddItem(pillar, 4)
	local used = {}
	K.every(0.1, 4, function()
		for _, t in ipairs(K.Hit.cylinder(pos, K.m(3), function()
			return true
		end)) do
			if not used[t] then
				if K.isEnemy(f, t) then
					used[t] = true
					K.dmg(c, t, 50, { fromPos = pos })
					K.lift(c, t, 0.5, 2)
				elseif t.humanoid and t.humanoid.Jump then
					used[t] = true
					S.Fighter.displace(t, Vector3.yAxis, K.m(4), 0.5)
					if c.p60 then
						K.after(0.6, function()
							K.hover(t, 0, 1, 0.1)
						end)
					end
				end
			end
		end
		return true
	end)
end

-- 4 Crosswind
Kit[4] = function(c)
	local f = c.f
	local dir = c:dir()
	local side = K.flat(dir:Cross(Vector3.yAxis))
	local rel = (c:aimPoint(20) - f.root.Position):Dot(side) >= 0 and side or -side
	K.line(c, f.root.Position + dir * K.m(1), dir, 8, 6, {
		dmg = 85,
		color = GUST,
		hit = function(t)
			K.push(c, t, rel, 2)
		end,
	})
	local allowance = c.p60 and 3 or 2
	for _, p in ipairs(K.projNear(f.root.Position + dir * K.m(5), 5)) do
		if allowance <= 0 then
			break
		end
		if p.kind ~= "ultimate" and not p.tags.windTurned then
			p.tags.windTurned = true
			allowance -= 1
			local sign = K.flat(p.vel):Cross(rel).Y >= 0 and 1 or -1
			p.vel = CFrame.Angles(0, math.rad(30 * sign), 0):VectorToWorldSpace(p.vel)
		end
	end
end

-- 5 Eye of the Gale (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(18)
	K.FX.ring(center, K.m(8), GUST, 6, 0.3)
	K.FX.ring(center, K.m(3), Color3.fromRGB(255, 255, 255), 6, 0.2)
	local totals = {}
	local revolutions = 3
	local dirSign = 1
	K.phase(c, "begin", { p = center, r = K.m(8) })
	for rev = 1, revolutions do
		local final = rev == revolutions
		if c.unstable and final then
			K.FX.text(center + Vector3.new(0, 4, 0), "REVERSE", GUST, 1, 28)
			task.wait(1)
			dirSign = -1
		end
		local hitRev = {}
		K.phase(c, "rev", { p = center, r = K.m(8), rev = rev, sign = dirSign })
		local t0 = K.now()
		while K.now() - t0 < 1.6 do
			local base = (K.now() - t0) / 1.6 * 360 * dirSign
			for i = 0, 2 do
				local from = base + i * 120
				K.arcFX(center, 5.5, from, from + 60, GUST, 0.1, 5)
				for _, t in ipairs(K.enemiesRing(c, center, 3, 8)) do
					if K.inSector(K.angleOf(center, t.root.Position), from % 360, 60) and not hitRev[t] then
						hitRev[t] = true
						if c.unstable and final then
							-- Air Runs Out: no damage, stronger 3 m pushes
							K.push(c, t, K.flat(t.root.Position - center):Cross(Vector3.yAxis) * dirSign, 3)
						elseif (totals[t] or 0) < 3 then
							totals[t] = (totals[t] or 0) + 1
							K.dmg(c, t, 80, { fromPos = center })
							K.push(c, t, K.flat(t.root.Position - center):Cross(Vector3.yAxis) * dirSign, 1.5)
						end
					end
				end
			end
			task.wait(0.08)
		end
	end
	K.phase(c, "finish", { p = center })
	local _ = f
end

return Kit
