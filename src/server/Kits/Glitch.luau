-- 43 Glitch — Short positional discontinuities and fake states
-- In-world power only: it never imitates crashes, disconnects or system prompts.
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local CODE = Color3.fromRGB(0, 255, 140)

-- Passive: Desync Echo
local function echo(c, pos, grantsEnergy)
	local f = c.f
	local e = K.object(c, { name = "Echo", pos = pos, size = Vector3.new(1.2, 2.5, 0.8), hp = 1, duration = 1, solid = false, color = CODE, material = Enum.Material.Neon, transparency = 0.5, noLabel = true })
	e.onDamage = function(_, _, src)
		if grantsEnergy and src and K.isEnemy(f, src) then
			local last = f.state.lastEcho or 0
			if K.now() - last >= 5 then
				f.state.lastEcho = K.now()
				K.addEnergy(f, 8)
			end
		end
	end
	return e
end

local function flash(pos)
	local p = K.FX.base({ size = Vector3.new(3, 3, 3), cf = CFrame.new(pos + Vector3.new(0, 1.5, 0)), color = CODE, transparency = 0.4 })
	game:GetService("Debris"):AddItem(p, 0.3)
end

-- 1 Missing Frame
Kit[1] = function(c)
	local skip = c.p60 and 3 or 2
	K.proj(c, {
		range = 18,
		width = 0.5,
		shape = "Block",
		size = Vector3.new(0.8, 0.8, 0.8),
		color = CODE,
		dmg = 70,
		step = function(p)
			if not p.data.skipped and p.traveled >= K.m(9) then
				p.data.skipped = true
				local dir = p.vel.Unit
				local to = p.pos + dir * K.m(skip)
				flash(p.pos)
				if K.Hit.los(p.pos, to) then
					-- the skipped segment still checks bodies along it
					for _, h in ipairs(K.Hit.segment(p.pos, to, p.radius, function(t)
						return K.isEnemy(c.f, t)
					end)) do
						K.dmg(c, h.f, 70, { projectile = true })
						S.Proj.stop(p, "hit")
						return
					end
					p.pos = to
					p.traveled += K.m(skip)
				end
			end
		end,
	})
end

-- 2 Packet Jump
Kit[2] = function(c)
	local f = c.f
	local start = c:feet()
	local dest = c:aimPoint(6, 6)
	flash(start)
	flash(dest)
	if K.blink(c, dest) then
		echo(c, start, true)
		if c.p60 then
			echo(c, start + K.flat(c:dir():Cross(Vector3.yAxis)) * K.m(1.5), false)
		end
	end
end

-- 3 Error Tile
Kit[3] = function(c)
	local f = c.f
	local pos = c:aimPoint(14)
	local exitDir = c:dir()
	local arrow = K.FX.base({ size = Vector3.new(0.6, 0.2, K.m(2)), cf = CFrame.lookAt(pos + Vector3.new(0, 0.3, 0), pos + Vector3.new(0, 0.3, 0) + exitDir) * CFrame.new(0, 0, -K.m(1)), color = Color3.fromRGB(255, 255, 255) })
	game:GetService("Debris"):AddItem(arrow, 5)
	local used = false
	local z
	z = K.zone(c, {
		pos = pos,
		radius = 1.5,
		duration = 5,
		color = CODE,
		transparency = 0.5,
		enter = function(_, t)
			if used or not K.isEnemy(f, t) then
				return
			end
			used = true
			local dest = K.Hit.findLegal(t.root.Position + exitDir * K.m(2))
			if dest then
				flash(t.root.Position)
				S.Fighter.teleport(t, dest)
				K.dmg(c, t, 85, { kind = "direct", fromPos = pos })
			end
			arrow:Destroy()
			z:remove("used")
		end,
	})
	if c.p60 then
		c:recast(5, function(c2)
			if not used then
				exitDir = c2:dir()
				arrow.CFrame = CFrame.lookAt(pos + Vector3.new(0, 0.3, 0), pos + Vector3.new(0, 0.3, 0) + exitDir) * CFrame.new(0, 0, -K.m(1))
			end
		end)
	end
end

-- 4 Rollback Decoy
Kit[4] = function(c)
	local f = c.f
	local recordPos = f.root.Position
	local node = K.object(c, { name = "RecordNode", pos = c:feet(), size = Vector3.new(0.8, 0.8, 0.8), hp = 100, duration = 3, color = CODE, material = Enum.Material.Neon })
	c:recast(3, function(c2)
		if not node.alive then
			K.notify(f, "Record node destroyed")
			return
		end
		local depart = c2:feet()
		if c2.p60 then
			K.delayed(c2, depart, 2, 0.4, function(p)
				K.circle(c2, p, 2, { dmg = 60, color = CODE })
			end, CODE)
		end
		echo(c2, depart, true)
		flash(depart)
		local stand = K.Hit.findLegal(recordPos)
		if stand then
			S.Fighter.teleport(f, stand)
		end
		S.Objects.remove(node, "used")
	end)
end

-- 5 Reality Exception (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	local tiles = {}
	for i, off in ipairs({ Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1) }) do
		tiles[i] = K.ground(center + off * K.m(3))
		K.FX.rect(CFrame.new(tiles[i] + Vector3.new(0, 0.1, 0)), K.m(3), K.m(3), 6, CODE, 0.6)
	end
	local function occupants(i)
		return K.Hit.box(CFrame.new(tiles[i]), Vector3.new(K.m(3), K.m(5), K.m(3)), function(t)
			return not t.isSummon
		end)
	end
	local function swap(pairs_, includeCaster)
		local moves = {}
		for _, pr in ipairs(pairs_) do
			local a, b = pr[1], pr[2]
			for _, t in ipairs(occupants(a)) do
				if includeCaster or t ~= f then
					table.insert(moves, { t = t, to = tiles[b] + (t.root.Position - tiles[a]) })
				end
			end
		end
		for _, m in ipairs(moves) do
			local stand = K.Hit.findLegal(m.to)
			-- invalid destinations cancel movement and damage together
			if stand then
				flash(m.t.root.Position)
				S.Fighter.teleport(m.t, stand)
				if K.isEnemy(f, m.t) then
					K.dmg(c, m.t, 70, { fromPos = stand })
				end
			end
		end
	end
	if c.unstable then
		for _ = 1, 3 do
			for i = 1, 4 do
				K.FX.rect(CFrame.new(tiles[i] + Vector3.new(0, 0.2, 0)), K.m(3), K.m(3), 0.6, Color3.fromRGB(255, 80, 80), 0.4)
			end
			task.wait(0.6)
			swap({ { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 } }, true)
			task.wait(0.9)
		end
		K.FX.burst(center, K.m(6), CODE, 0.4)
		for _, t in ipairs(K.Hit.cylinder(center, K.m(6), function()
			return true
		end)) do
			K.Combat.damage(f, t, 100, { cast = c, isUlt = true, fromPos = center, element = "Glitch" })
		end
		return
	end
	local schedule = { { 1, 3 }, { 2, 4 }, { 1, 2 }, { 3, 4 } }
	for _, pr in ipairs(schedule) do
		K.FX.rect(CFrame.new(tiles[pr[1]] + Vector3.new(0, 0.2, 0)), K.m(3), K.m(3), 0.6, Color3.fromRGB(255, 220, 80), 0.4)
		K.FX.rect(CFrame.new(tiles[pr[2]] + Vector3.new(0, 0.2, 0)), K.m(3), K.m(3), 0.6, Color3.fromRGB(255, 220, 80), 0.4)
		task.wait(0.6)
		swap({ { pr[1], pr[2] }, { pr[2], pr[1] } }, false)
		task.wait(0.9)
	end
end

return Kit
