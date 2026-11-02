-- 24 Destruction — Structural breaking and committed burst
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local ORANGE = Color3.fromRGB(255, 100, 0)

-- Passive: Fracture Stress — objects accumulate Stress; players gain a single 5% vulnerability
local function stress(c, o)
	if not o or not o.alive then
		return 0
	end
	local s = (o.data.stress or 0) + 1
	o.data.stress = s
	if o.label then
		o.label.Text = tostring(math.floor(o.hp)) .. "  [STRESS " .. math.min(3, s) .. "]"
	end
	return s
end
local function hitObject(c, o, amount)
	local bonus = 0
	if (o.data.stress or 0) >= 3 then
		bonus = 100
		o.data.stress = 0
	else
		stress(c, o)
	end
	return K.objDmg(c, o, amount + bonus)
end
function Kit.passive.dealt(f, target, info)
	if info.kind == "direct" and not target.isSummon then
		K.vuln(f, target, 0.05, 2, "Fractured")
	end
end

-- 1 Ruin Knuckle
Kit[1] = function(c)
	local f = c.f
	local dir = c:dir()
	local front = f.root.Position + dir * K.m(2)
	if c.p60 then
		for _, o in ipairs(K.enemyObjects(c, front, 2)) do
			if o.hp <= 60 then
				S.Objects.destroy(o, f)
				break
			end
		end
	end
	local hits = K.melee(c, { range = 4, arc = 80, dmg = 95, color = ORANGE, objDmg = false })
	for _, o in ipairs(K.enemyObjects(c, front, 2)) do
		hitObject(c, o, 180)
	end
	-- ground crack 2 m beyond the hit for 30 to additional targets
	local primary = {}
	for _, t in ipairs(hits) do
		primary[t] = true
	end
	K.line(c, f.root.Position + dir * K.m(4), dir, 2, 1.5, {
		color = ORANGE,
		hit = function(t)
			if not primary[t] then
				K.dmg(c, t, 30)
			end
		end,
	})
end

-- 2 Demolition Line
Kit[2] = function(c)
	local origin = c:feet()
	local dir = c:dir()
	local len = 18
	K.telegraphLine(c, origin, dir, len, 2, 0.7, ORANGE)
	task.wait(0.7)
	local broke = false
	local function detonate(from, length)
		K.line(c, from, dir, length, 2, { dmg = 130, color = ORANGE })
		local mid = from + dir * K.m(length / 2)
		for _, o in ipairs(K.enemyObjects(c, mid, length / 2)) do
			local lp = CFrame.lookAt(from, from + dir):PointToObjectSpace(o.part.Position)
			if math.abs(lp.X) <= K.m(1) + o.part.Size.X / 2 and -lp.Z >= 0 and -lp.Z <= K.m(length) then
				if not o.tags.protected then
					hitObject(c, o, 150)
					if not o.alive then
						broke = true
					end
				end
			end
		end
	end
	detonate(origin, len)
	if c.p60 and broke then
		K.telegraphLine(c, origin + dir * K.m(len), dir, 4, 2, 0.3, ORANGE)
		task.wait(0.3)
		detonate(origin + dir * K.m(len), 4)
	end
end

-- 3 Shatterguard
Kit[3] = function(c)
	local f = c.f
	local caught = false
	K.FX.highlight(f.model, ORANGE, 0.6, 0.6)
	K.hook(f, "beforeTake", function(_, info)
		if caught or not info.opts.melee or info.opts.isUlt or info.kind ~= "direct" then
			return
		end
		local src = info.src
		if not src or not K.isEnemy(f, src) then
			return
		end
		caught = true
		info.cancel = true
		K.dmg(c, src, 70, { fromPos = f.root.Position })
		for _, sm in ipairs(src.summons or {}) do
			if K.alive(sm) and sm.model.Name:lower():find("weapon") then
				K.dmg(c, sm, 80)
				break
			end
		end
		if c.p60 then
			for _, o in ipairs(K.objects(c, src.root.Position, 6, function(o)
				return o.owner == src
			end)) do
				stress(c, o)
				break
			end
		end
	end, 0.6)
	c:channel(0.6, { stationary = false })
end

-- 4 Collapse Point
Kit.requires = {
	[4] = function(c)
		local pos = c:aimPoint(14)
		for _, o in ipairs(K.objects(c, pos, 3)) do
			if not o.tags.protected and not o.invulnerable then
				return true
			end
		end
		return false, "No breakable structure there"
	end,
}
Kit[4] = function(c)
	local pos = c:aimPoint(14)
	local target
	for _, o in ipairs(K.objects(c, pos, 3)) do
		if not o.tags.protected then
			target = o
			break
		end
	end
	if not target then
		return
	end
	local dir = c:dir()
	local hl = K.FX.highlight(target.part, ORANGE, 4, 0.4)
	local _ = hl
	local armed = true
	local prevDestroy = target.onDestroy
	target.onDestroy = function(obj, src)
		if prevDestroy then
			prevDestroy(obj, src)
		end
		if armed then
			armed = false
			local from = K.ground(obj.part.Position)
			local width = (K.partner(c, "Rock", 20) and 1 or 0)
			K.cone(c, { origin = from, dir = dir, range = 4 + width, angle = 70, dmg = 140, color = ORANGE })
		end
	end
	if c.p60 then
		c:recast(4, function(c2)
			dir = c2:dir()
		end)
	end
	K.after(4, function()
		armed = false
	end)
end

-- 5 Nothing Remains (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	local bands = { { 6, 9 }, { 3, 6 }, { 0, 3 } }
	for i, b in ipairs(bands) do
		K.FX.ring(center, K.m(b[2]), ORANGE, 0.6, 0.3)
		if b[1] > 0 then
			K.FX.ring(center, K.m(b[1]), ORANGE, 0.6, 0.3)
		end
		task.wait(0.6)
		local final = i == 3
		local list = (final and c.unstable) and K.Hit.ring(center, 0, K.m(b[2]), function()
			return true
		end) or K.enemiesRing(c, center, b[1], b[2])
		for _, t in ipairs(list) do
			local dmg = (t == f) and 180 or 90
			K.Combat.damage(f, t, dmg, { cast = c, isUlt = true, fromPos = center, element = "Destruction" })
		end
		for _, o in ipairs(K.enemyObjects(c, center, b[2])) do
			if not o.tags.protected then
				local d = K.flatDist(o.part.Position, center)
				if d >= b[1] - 0.5 then
					K.objDmg(c, o, 200)
				end
			end
		end
		K.FX.ring(center, K.m(b[2]), ORANGE, 0.3, K.m(b[2] - b[1]))
		task.wait(0.3)
	end
	if c.unstable then
		for _, o in ipairs(K.objects(c, center, 9)) do
			if not o.tags.protected and not o.isUlt then
				S.Objects.remove(o, "erased")
			end
		end
	end
end

return Kit
