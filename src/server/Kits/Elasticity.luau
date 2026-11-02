-- 30 Elasticity — Stored tension and recoverable recoil
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local ORANGE = Color3.fromRGB(255, 170, 80)

local function setTension(f, v)
	f.state.tension = math.clamp(v, 0, 100)
	K.res(f, "Tension", math.floor(f.state.tension), 100, 1)
end

-- Passive: Tension Bank
function Kit.passive.init(f)
	setTension(f, 0)
end
function Kit.passive.beforeDisplace(f, info)
	if f.guarding and info.kind ~= "pull" then
		setTension(f, f.state.tension + info.dist / K.M * 10)
		info.dist *= 0.5
	end
end
function Kit.passive.tick(f, dt, now)
	if now - (f.lastContest or 0) > 4 and f.state.tension > 0 then
		setTension(f, f.state.tension - 10 * dt)
	end
end

-- 1 Rubber Knuckle
Kit[1] = function(c)
	local f = c.f
	local reach = 8
	if c.mod and f.state.tension >= 20 then
		setTension(f, f.state.tension - 20)
		reach += 3
	end
	local dir = c:dir3()
	local origin = c:chest()
	local endPos, struck, res = K.beam(c, { origin = origin, dir = dir, length = reach, width = 0.8, dmg = 85, color = ORANGE, dur = 0.35 })
	if c.p60 and #struck == 0 and res then
		local n = res.Normal
		local rd = dir - 2 * dir:Dot(n) * n
		local remaining = math.max(1, reach - (endPos - origin).Magnitude / K.M)
		K.beam(c, { origin = endPos + n * 0.5, dir = rd, length = remaining, width = 0.8, dmg = 85, color = ORANGE, dur = 0.35 })
	end
	-- the extended arm's visible line can be struck: enemies crossing it during extension hurt the caster
	local armEnd = endPos
	K.every(0.05, 0.35, function()
		for _, h in ipairs(K.Hit.segment(origin, armEnd, K.m(0.4), K.enemyFilter(c))) do
			if h.f.action and h.f.action.active then
				K.Combat.damage(h.f, f, 40, { kind = "direct", fromPos = h.f.root.Position })
				return false
			end
		end
		return true
	end)
end

-- 2 Slingshot Anchor
Kit[2] = function(c)
	local f = c.f
	local anchorPos = c:aimPoint(14)
	local anchor = K.object(c, { name = "SlingAnchor", pos = anchorPos, size = Vector3.new(0.6, 1.2, 0.6), hp = 100, duration = 3, color = ORANGE, material = Enum.Material.Neon })
	local lineDir = K.flat(anchorPos - f.root.Position)
	-- pull backward up to 4 metres (hold to stretch, release early on P60 without extra recovery)
	local held = c:hold(0.8)
	local back = math.clamp(held / 0.8 * 4, 1, 4)
	K.dash(c, -lineDir, back, 0.3)
	if not anchor.alive then
		return
	end
	K.FX.beam(f.root.Position, anchor.part.Position, 0.25, ORANGE, 0.3)
	local dist = K.flatDist(anchorPos, f) + 1
	local struck = false
	K.dash(c, lineDir, dist, 0.3, {
		passWidth = 1.8,
		onPass = function(t)
			if not struck then
				struck = true
				K.dmg(c, t, 100, { melee = true })
			end
		end,
	})
	S.Objects.remove(anchor, "released")
	c.recovery = c.p60 and 0.1 or 0.35
end

-- 3 Rebound Guard
Kit[3] = function(c)
	local f = c.f
	local used = false
	K.FX.highlight(f.model, ORANGE, 0.7, 0.6)
	K.hook(f, "beforeTake", function(_, info)
		if used or info.kind ~= "direct" or info.opts.pierce or info.opts.beam then
			return
		end
		local physical = info.opts.melee or (info.opts.projectile and info.opts.cast and true)
		if not physical then
			return
		end
		used = true
		info.amount *= 0.5
		setTension(f, f.state.tension + 30)
		local dir = c.mod and c.p60 and K.flat(f.root.CFrame.RightVector) or nil
		for _, t in ipairs(K.enemiesIn(c, f.root.Position, 3)) do
			K.dmg(c, t, 70)
			if dir then
				K.push(c, t, dir, 2)
			else
				K.knock(c, t, f.root.Position, 2)
			end
		end
	end, 0.7)
end

-- 4 Springboard Skin
Kit[4] = function(c)
	local f = c.f
	local pos = c:aimPoint(12)
	local launchDir = c:dir()
	local mat = K.object(c, { name = "Springboard", pos = pos, size = Vector3.new(3, 0.3, 3), hp = 140, duration = 6, solid = false, queryable = true, color = ORANGE, material = Enum.Material.Rubber })
	mat.data.springboard = true
	if c.p60 then
		c:recast(6, function(c2)
			launchDir = c2:dir()
		end)
	end
	local lastBounce = {}
	K.every(0.1, 6, function()
		if not mat.alive then
			return false
		end
		for _, t in ipairs(K.Hit.cylinder(pos, K.m(1.6), function()
			return true
		end)) do
			if K.isAlly(f, t) and t.humanoid and t.humanoid.Jump and (not lastBounce[t] or K.now() - lastBounce[t] > 1) then
				lastBounce[t] = K.now()
				S.Fighter.displace(t, (launchDir + Vector3.new(0, 0.8, 0)).Unit, K.m(6), 0.5)
			elseif K.isEnemy(f, t) and (not lastBounce[t] or K.now() - lastBounce[t] > 2) and K.flatDist(t, pos) < 1 then
				lastBounce[t] = K.now()
				K.FX.burst(pos, K.m(1.5), ORANGE, 0.3)
				K.after(0.3, function()
					K.knock(c, t, pos, 2, { up = 20 })
				end)
			end
		end
		return true
	end)
end

-- 5 World Snapback (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(18)
	local anchors = {}
	for q = 0, 3 do
		local a = math.rad(q * 90 + 45)
		anchors[q + 1] = K.object(c, {
			name = "SnapAnchor",
			pos = K.ground(center + Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(7)),
			size = Vector3.new(0.7, 1.6, 0.7),
			hp = 90,
			duration = 3,
			isUlt = true,
			color = ORANGE,
			material = Enum.Material.Neon,
		})
	end
	task.wait(2)
	local pullDist = c.unstable and 8 or 4
	for q, anc in ipairs(anchors) do
		if anc.alive then
			local from = (q - 1) * 90
			K.FX.beam(anc.part.Position, center, 0.4, ORANGE, 0.3)
			for _, t in ipairs(K.enemiesIn(c, center, 8)) do
				if K.inSector(K.angleOf(center, t.root.Position), from, 90) and K.Hit.los(anc.part.Position, t.root.Position) then
					K.dmg(c, t, 50, { fromPos = anc.part.Position })
					K.pull(c, t, center, pullDist)
				end
			end
		end
	end
	if c.unstable then
		K.pull(c, f, center, pullDist)
		for _, o in ipairs(K.owned(f, "Springboard")) do
			S.Objects.remove(o, "snapped")
		end
	end
	task.wait(0.35)
	K.circle(c, center, 3, { dmg = 100, color = ORANGE })
end

return Kit
