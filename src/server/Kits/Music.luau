-- 60 Music — Rhythm windows and deliberate phrases (visual cues carry all timing information)
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local PINK = Color3.fromRGB(255, 120, 220)
local BEAT = 0.6

local function setNotes(f, n)
	f.state.notes = math.clamp(n, 0, 4)
	K.res(f, "Notes", f.state.notes, 4, 1)
end
local function onBeat(f)
	local t = (K.now() - f.state.beat0) % BEAT
	return t <= 0.12 or t >= BEAT - 0.12
end

-- Passive: Four Beat Measure
function Kit.passive.init(f)
	f.state.beat0 = K.now()
	setNotes(f, 0)
	f.model:SetAttribute("BeatEpoch", f.state.beat0)
end
function Kit.passive.tick(f)
	local beatIndex = math.floor((K.now() - f.state.beat0) / BEAT)
	if beatIndex ~= f.state.lastBeat then
		f.state.lastBeat = beatIndex
		K.FX.ring(K.feet(f), beatIndex % 4 == 0 and 2.4 or 1.6, PINK, 0.15, 0.15)
	end
end
function Kit.passive.cast(f, c)
	c.data.onBeat = onBeat(f)
	if c.data.onBeat and not (f.state.sealedUntil and f.state.sealedUntil > K.now()) then
		setNotes(f, f.state.notes + 1)
	end
end

-- 1 Staccato
Kit[1] = function(c)
	local dir = c:dir3()
	for i = 1, 3 do
		local spread = c.data.onBeat and 0 or (math.random() - 0.5) * 12
		K.proj(c, { dir = K.rotate(dir, spread), range = 20, speed = 30, width = 0.4, color = PINK, dmg = 25 })
		if i < 3 then
			task.wait(0.2)
		end
	end
end

-- 2 Legato Path
Kit[2] = function(c)
	local f = c.f
	local start = c:feet()
	local dir = c:dir()
	local ends = {}
	for i, p in ipairs({ start, start + dir * K.m(8) }) do
		ends[i] = K.object(c, { name = "EndNote", pos = p, size = 0.8, shape = "Ball", hp = 80, duration = 5, color = PINK, material = Enum.Material.Neon })
	end
	local radiusBonus = K.partner(c, "Sound", 20) and 1 or 0
	local shielded = {}
	K.zone(c, {
		shape = "rect",
		pos = start,
		dir = dir,
		width = 2 + radiusBonus,
		length = 8,
		duration = 5,
		tick = 0.25,
		immediate = true,
		targets = "allies",
		includeOwner = true,
		color = PINK,
		transparency = 0.6,
		tickFn = function(z, list)
			if not (ends[1].alive or ends[2].alive) then
				z:remove("notes destroyed")
				return
			end
			for _, a in ipairs(list) do
				if K.isAlly(f, a) and not a.isSummon then
					K.speed(a, 0.12, 0.4, "Legato")
					if c.p60 and not shielded[a] then
						local lp = CFrame.lookAt(z.pos, z.pos + z.dir):PointToObjectSpace(a.root.Position)
						if -lp.Z >= K.m(7) then
							shielded[a] = true
							K.shield(c, a, 40, 3, "Legato")
						end
					end
				end
			end
		end,
	})
end

-- 3 Dissonant Chord
Kit[3] = function(c)
	local f = c.f
	local spent = math.min(3, f.state.notes or 0)
	setNotes(f, f.state.notes - spent)
	K.cone(c, {
		range = 10,
		angle = c.p60 and 75 or 60,
		dmg = 60 + 20 * spent,
		color = PINK,
		hit = function(t)
			if spent >= 3 then
				K.interrupt(t, "dissonance")
				K.stun(c, t, 0.25)
			end
		end,
	})
end

-- 4 Rest Measure (one full measure = four beats)
Kit[4] = function(c)
	local f = c.f
	local interrupted = false
	local rm = K.hook(f, "taken", function(_, info)
		if info.kind == "direct" then
			interrupted = true
		end
	end, BEAT * 4)
	local ok = c:channel(BEAT * 4, {
		stationary = not c.p60,
		halfSpeed = c.p60,
		tick = 0.05,
		onTick = function()
			if interrupted then
				return false
			end
		end,
	})
	rm()
	if ok and not interrupted then
		K.addEnergy(f, 20)
		f.heat = math.max(0, f.heat - 15)
		if (f.state.notes or 0) > 0 then
			setNotes(f, f.state.notes - 1)
			K.heal(c, f, 50)
		end
	end
end

-- 5 Symphony of Four Movements (ultimate)
Kit[5] = function(c)
	local f = c.f
	local center = c:aimPoint(20)
	local dir = c:dir()
	K.FX.disc(center, K.m(7), PINK, 6, 0.8)
	local movements = {
		function()
			K.telegraph(c, center, 7, 0.6, PINK)
			task.wait(0.6)
			K.circle(c, center, 7, { dmg = 80, color = PINK })
		end,
		function()
			K.telegraph(c, center, 7, 0.6, Color3.fromRGB(140, 200, 255))
			task.wait(0.6)
			for _, a in ipairs(K.alliesIn(c, center, 7, true)) do
				K.shield(c, a, 80, 4, "Symphony")
			end
		end,
		function()
			K.telegraphLine(c, center - dir * K.m(7), dir, 14, 2.5, 0.6, PINK)
			task.wait(0.6)
			K.line(c, center - dir * K.m(7), dir, 14, 2.5, { dmg = 90, color = PINK })
		end,
		function()
			K.FX.ring(center, K.m(7), PINK, 0.6, K.m(1.5))
			task.wait(0.6)
			K.ringHit(c, center, 5.5, 7, { dmg = 100, color = PINK })
		end,
	}
	for i, m in ipairs(movements) do
		m()
		local gap = 0.6
		if not c.unstable or i < 2 then
			gap = 0.9
		end
		task.wait(gap)
	end
	if c.unstable then
		f.state.sealedUntil = K.now() + 6
	end
end

return Kit
