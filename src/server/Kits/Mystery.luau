-- 61 Mystery — Deduction and concealed preparation
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local DEEP = Color3.fromRGB(150, 120, 220)
local SYMBOL = { dash = "Dash", guard = "Guard", projectile = "Shot" }

local function subject(f)
	local s = f.state.subject
	if s and K.alive(s) and f.state.subjectUntil > K.now() then
		return s
	end
	return nil
end
local function show(f)
	local clues = {}
	for k in pairs(f.state.clues) do
		table.insert(clues, SYMBOL[k])
	end
	table.sort(clues)
	local s = subject(f)
	K.res(f, "Subject", s and s.name or "none", nil, 1)
	K.res(f, "Clues", #clues > 0 and table.concat(clues, " ") or "-", nil, 2)
end
local function clueCount(f)
	local n = 0
	for _ in pairs(f.state.clues) do
		n += 1
	end
	return n
end

local function setSubject(f, t)
	if f.state.subject ~= t then
		f.state.clues = {}
		if f.state.unhook then
			for _, u in ipairs(f.state.unhook) do
				u()
			end
		end
		f.state.unhook = {}
		f.state.subject = t
		-- witness the subject's dash, guard and projectiles
		table.insert(f.state.unhook, K.hook(t, "dodge", function()
			if K.los(f, t) then
				f.state.clues.dash = true
				S.emit("subjectAction", t, "dash")
				show(f)
			end
		end))
		table.insert(f.state.unhook, K.hook(t, "guarded", function()
			if K.los(f, t) then
				f.state.clues.guard = true
				S.emit("subjectAction", t, "guard")
				show(f)
			end
		end))
	end
	f.state.subjectUntil = K.now() + 10
	show(f)
end

-- Passive: Case File
function Kit.passive.init(f)
	f.state.clues = {}
	f.state.unhook = {}
	f.state.subjectUntil = 0
	f.state.unsub = S.on("cast", function(caster, c)
		if caster == f.state.subject and f.kitName == "Mystery" and K.los(f, caster) and K.dist(f, caster) <= 30 then
			local desc = string.lower(c.def.desc or "")
			if string.find(desc, "projectile") or string.find(desc, "fire") or string.find(desc, "launch") or string.find(desc, "throw") then
				f.state.clues.projectile = true
				S.emit("subjectAction", caster, "projectile")
				show(f)
			end
		end
	end)
	show(f)
end
function Kit.passive.cleanup(f)
	if f.state.unsub then
		f.state.unsub()
	end
	for _, u in ipairs(f.state.unhook or {}) do
		u()
	end
end
function Kit.passive.taken(f, info)
	local src = info.src and (info.src.owner or info.src)
	if src and K.isEnemy(f, src) and not src.isSummon and not subject(f) then
		setSubject(f, src)
	end
end
function Kit.passive.tick(f)
	if f.state.subject and not subject(f) then
		f.state.subject = nil
		f.state.clues = {}
		show(f)
	end
end

-- 1 Question Mark
Kit[1] = function(c)
	local f = c.f
	local returned = {}
	local dir = c:dir3()
	K.proj(c, {
		dir = K.rotate(dir, 12),
		range = 22,
		width = 0.6,
		color = DEEP,
		dmg = 70,
		turnRate = 40,
		homing = c:target(22),
		hit = function(t)
			if t == subject(f) then
				K.reveal(c, t, 3)
			end
		end,
		finish = function(pos)
			if c.p60 then
				K.proj(c, {
					origin = pos,
					dir = (c:chest() - pos).Unit,
					range = 22,
					width = 0.6,
					color = DEEP,
					pierce = true,
					filter = function(t)
						return K.isEnemy(f, t) and not returned[t]
					end,
					hit = function(t)
						returned[t] = true
						K.dmg(c, t, 25)
						return "continue"
					end,
				})
			end
		end,
	})
end

-- 2 Sealed Envelope (modifier = shield envelope, otherwise snare)
Kit[2] = function(c)
	local f = c.f
	local kind = c.mod and "shield" or "snare"
	local pos = c:aimPoint(14)
	local env = K.object(c, { name = "Envelope", pos = pos, size = Vector3.new(1, 0.2, 0.7), hp = 80, duration = 8, solid = false, queryable = true, color = Color3.fromRGB(240, 230, 200), material = Enum.Material.Fabric })
	local opened = false
	local moved = false
	if c.p60 then
		c:recast(8, function(c2)
			if env.alive and not moved and not opened then
				moved = true
				pos = K.ground(pos + K.flat(c2:aimPoint(30) - pos) * K.m(3))
				env.part.CFrame = CFrame.new(pos + Vector3.new(0, 0.2, 0))
			end
		end)
	end
	K.every(0.1, 8, function()
		if opened or not env.alive then
			return false
		end
		if kind == "snare" then
			for _, t in ipairs(K.enemiesIn(f, pos, 1.5)) do
				opened = true
				K.telegraph(c, pos, 1.5, 0.6, DEEP)
				K.after(0.6, function()
					S.Objects.remove(env, "opened")
					K.circle(c, pos, 1.5, { dmg = 70, color = DEEP, hit = function(v)
						K.root(c, v, 0.6)
					end })
				end)
				local _ = t
				return false
			end
		else
			for _, a in ipairs(K.alliesIn(f, pos, 1.5, true)) do
				opened = true
				S.Objects.remove(env, "opened")
				K.shield(c, a, 100, 5, "Envelope")
				return false
			end
		end
		return true
	end)
end

-- 3 Cross Examination
Kit.requires = {
	[3] = function(c)
		if not subject(c.f) then
			return false, "No Subject"
		end
		if clueCount(c.f) == 0 then
			return false, "No Clues"
		end
		return true
	end,
	[5] = function(c)
		if subject(c.f) then
			return true
		end
		return false, "No Subject"
	end,
}
Kit[3] = function(c)
	local f = c.f
	local s = subject(f)
	-- announce the most recently witnessed action type (spending that Clue)
	local kind
	for _, k in ipairs({ "projectile", "dash", "guard" }) do
		if f.state.clues[k] then
			kind = k
			break
		end
	end
	f.state.clues[kind] = nil
	show(f)
	K.announce(f, "PREDICT: " .. SYMBOL[kind], DEEP, 1.5)
	local done = false
	local unsub
	unsub = S.on("subjectAction", function(who, action)
		if done or who ~= s or action ~= kind then
			return
		end
		done = true
		unsub()
		local at = K.feet(s)
		K.telegraph(c, at, 1.5, 0.5, DEEP)
		K.after(0.5, function()
			K.circle(c, at, 1.5, { dmg = 80, color = DEEP })
			if c.p60 then
				K.addEnergy(f, 8)
			end
		end)
	end)
	K.after(3, function()
		if not done then
			done = true
			unsub()
		end
	end)
end

-- 4 Missing Piece
Kit[4] = function(c)
	local f = c.f
	local silhouetteCF = f.root.CFrame
	local sil = K.decoyModel(f, silhouetteCF, DEEP)
	local window = c.p60 and 6 or 4
	game:GetService("Debris"):AddItem(sil, window)
	local side = K.flat(c:dir():Cross(Vector3.yAxis))
	local rel = (f.humanoid and f.humanoid.MoveDirection:Dot(side) or 1) >= 0 and 1 or -1
	K.dash(c, side * rel, 5, 0.2)
	local broken = false
	local rm = K.hook(f, "taken", function(_, info)
		if info.kind == "direct" then
			broken = true
		end
	end, window)
	local _ = rm
	c:recast(window, function(c2)
		if broken then
			K.notify(f, "Return lost (took damage)")
			return
		end
		if K.Hit.los(f.root.Position, silhouetteCF.Position, true) then
			K.blink(c2, silhouetteCF.Position - Vector3.new(0, 2.5, 0))
			sil:Destroy()
		end
	end)
end

-- 5 The Final Deduction (ultimate)
Kit[5] = function(c)
	local f = c.f
	local s = subject(f)
	if not s then
		return
	end
	local spent = clueCount(f)
	f.state.clues = {}
	show(f)
	local base = K.feet(s)
	local circles = {}
	local n = c.unstable and 4 or 3
	for i = 1, n do
		local a = math.rad(i * 360 / 3)
		local offset = (i <= 3) and Vector3.new(math.cos(a), 0, math.sin(a)) * K.m(1.5) or Vector3.zero
		local r = 2 + ((i <= spent) and 0.5 or 0)
		circles[i] = { pos = K.ground(base + offset), r = i == 4 and 3 or r, dmg = i == 4 and 90 or 80 }
	end
	for i, cc in ipairs(circles) do
		K.FX.text(cc.pos + Vector3.new(0, 1, 0), tostring(i), DEEP, 4, 30)
	end
	for i, cc in ipairs(circles) do
		local warn = i == 4 and 0.8 or 0.6
		K.telegraph(c, cc.pos, cc.r, warn, DEEP)
		task.wait(warn)
		K.circle(c, cc.pos, cc.r, { dmg = cc.dmg, color = DEEP })
	end
	if c.unstable and K.alive(s) then
		K.reveal(c, f, 8) -- Unsolved Case: your location is revealed
	end
end

return Kit
