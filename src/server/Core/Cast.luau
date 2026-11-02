-- Ability casting (Compendium: "Commitment and recovery", "Proxima and Heat", "Unstable mutation and Rupture").
local S = require(script.Parent.S)
local Combat = require(script.Parent.Combat)

local Cast = {}
S.Cast = Cast

local Config = S.Config
local M = Config.METRE

local remotes
function Cast.init(r)
	remotes = r
end

local function notify(f, text)
	if f.player and remotes then
		remotes.Notice:FireClient(f.player, text)
	end
end
Cast.notify = notify

-- Cast context -------------------------------------------------------------------------
local Ctx = {}
Ctx.__index = Ctx
Cast.Ctx = Ctx

local function newCtx(f, slot, def)
	return setmetatable({
		f = f,
		slot = slot,
		def = def,
		isUlt = slot == 5,
		p60 = false,
		unstable = false,
		mod = false,
		interrupted = false,
		active = false,
		phase = "pending",
		startTime = S.now(),
		data = {},
	}, Ctx)
end
Cast.newCtx = newCtx

function Ctx:valid()
	return not self.interrupted and S.alive(self.f)
end

-- yields; returns false when the cast was interrupted or the caster died
function Ctx:wait(t)
	local f = self.f
	local endT = S.now() + (t or 0)
	if (t or 0) <= 0 then
		task.wait()
		return self:valid()
	end
	while S.now() < endT do
		if not self:valid() then
			return false
		end
		task.wait(math.min(0.05, endT - S.now()))
	end
	return self:valid() and S.alive(f)
end

function Ctx:origin()
	return self.f.root.Position
end

function Ctx:chest()
	return self.f.root.Position + Vector3.new(0, 0.8, 0)
end

function Ctx:feet()
	local g = S.Hit.ground(self.f.root.Position)
	return g or (self.f.root.Position - Vector3.new(0, Config.BODY_DOWN, 0))
end

local function aimOf(f)
	return f.aim
end

-- flat unit direction toward aim
function Ctx:dir()
	local f = self.f
	local a = aimOf(f)
	if self.lockedDir then
		return self.lockedDir
	end
	if a and a.hit then
		local v = a.hit - f.root.Position
		v = Vector3.new(v.X, 0, v.Z)
		if v.Magnitude > 2 then
			return v.Unit
		end
	end
	if a and a.dir then
		local v = Vector3.new(a.dir.X, 0, a.dir.Z)
		if v.Magnitude > 0.01 then
			return v.Unit
		end
	end
	local lv = f.root.CFrame.LookVector
	return Vector3.new(lv.X, 0, lv.Z).Unit
end

-- 3D direction from chest toward aim point
function Ctx:dir3()
	local f = self.f
	local a = aimOf(f)
	if a and a.hit then
		local v = a.hit - self:chest()
		if v.Magnitude > 2 then
			return v.Unit
		end
	end
	return self:dir()
end

-- ground point at aim, clamped to range (metres)
function Ctx:aimPoint(rangeM, minM)
	local f = self.f
	local a = aimOf(f)
	local origin = f.root.Position
	local target = a and a.hit or (origin + self:dir() * (rangeM or 10) * M)
	local flat = Vector3.new(target.X - origin.X, 0, target.Z - origin.Z)
	local maxS = (rangeM or self.def.range or 10) * M
	local d = flat.Magnitude
	if d > maxS then
		flat = flat.Unit * maxS
	elseif minM and d < minM * M then
		flat = (d > 0.01 and flat.Unit or self:dir()) * minM * M
	end
	local p = Vector3.new(origin.X + flat.X, math.max(target.Y, origin.Y - 30), origin.Z + flat.Z)
	local g = S.Hit.ground(Vector3.new(p.X, math.max(p.Y, origin.Y) + 8, p.Z), 60)
	if g then
		return g
	end
	return Vector3.new(p.X, origin.Y - Config.BODY_DOWN, p.Z)
end

local function scoreTarget(self, t, rangeS, rayOrigin, rayDir)
	local to = t.root.Position - rayOrigin
	local dist = (t.root.Position - self.f.root.Position).Magnitude
	if dist > rangeS + Config.BODY_RADIUS then
		return nil
	end
	local ang = math.deg(math.acos(math.clamp(to.Unit:Dot(rayDir), -1, 1)))
	return ang
end

-- enemy (or ally) under / near the aim. rangeM metres. opts: allies, includeSelf, needLos (default true), cone
function Ctx:target(rangeM, opts)
	opts = opts or {}
	local f = self.f
	local rangeS = (rangeM or self.def.range or 15) * M
	local a = aimOf(f)
	local function ok(t)
		if not S.alive(t) or t.untargetable > 0 then
			return false
		end
		if opts.allies then
			if t == f then
				return opts.includeSelf == true
			end
			if not S.isAlly(f, t) then
				return false
			end
			if t.isSummon and not opts.summons then
				return false
			end
		else
			if not S.isEnemy(f, t) then
				return false
			end
			if t.isSummon and opts.noSummons then
				return false
			end
		end
		if opts.filter and not opts.filter(t) then
			return false
		end
		if (t.root.Position - f.root.Position).Magnitude > rangeS + Config.BODY_RADIUS then
			return false
		end
		if opts.needLos ~= false and not S.Hit.los(self:chest(), t.root.Position) then
			return false
		end
		return true
	end
	if a and a.target then
		local t = S.byModel[a.target]
		if t and ok(t) then
			return t
		end
	end
	local rayOrigin = (a and a.origin) or self:chest()
	local rayDir = (a and a.dir) or self:dir()
	if a and a.hit then
		local v = a.hit - rayOrigin
		if v.Magnitude > 0.5 then
			rayDir = v.Unit
		end
	end
	local best, bestAng
	local cone = opts.cone or 14
	for _, t in pairs(S.fighters) do
		if ok(t) then
			local ang = scoreTarget(self, t, rangeS, rayOrigin, rayDir)
			if ang and ang <= cone and (not bestAng or ang < bestAng) then
				best, bestAng = t, ang
			end
		end
	end
	if not best and a and a.hit then
		-- fallback: closest to aim point
		local bd
		for _, t in pairs(S.fighters) do
			if ok(t) then
				local d = (t.root.Position - a.hit).Magnitude
				if d < M * 3 and (not bd or d < bd) then
					best, bd = t, d
				end
			end
		end
	end
	if not best and opts.allies and opts.includeSelf then
		return f
	end
	return best
end

function Ctx:ally(rangeM, includeSelf)
	return self:target(rangeM, { allies = true, includeSelf = includeSelf })
end

function Ctx:face(dir)
	local f = self.f
	local d = Vector3.new(dir.X, 0, dir.Z)
	if d.Magnitude > 0.01 and f.root then
		if f.humanoid then
			f.root.CFrame = CFrame.lookAt(f.root.Position, f.root.Position + d.Unit)
		end
	end
end

-- stationary channel. opts: tick (interval), onTick(elapsed) -> return false to stop, cancelOnMove, moveFree
function Ctx:channel(dur, opts)
	opts = opts or {}
	local f = self.f
	self.phase = "channel"
	if opts.stationary ~= false then
		f.stationary += 1
	end
	if opts.halfSpeed then
		self.halfSpeed = true
	end
	local start = S.now()
	local startPos = f.root.Position
	local nextTick = start + (opts.tick or math.huge)
	local completed = true
	while S.now() - start < dur do
		if not self:valid() then
			completed = false
			break
		end
		if self.endChannel then
			completed = opts.earlyIsComplete or false
			break
		end
		if opts.cancelOnMove and (f.root.Position - startPos).Magnitude > 1.5 then
			completed = false
			break
		end
		if opts.onTick and S.now() >= nextTick then
			nextTick += opts.tick
			local r = opts.onTick(S.now() - start)
			if r == false then
				break
			end
		end
		task.wait(0.05)
	end
	if opts.stationary ~= false then
		f.stationary -= 1
	end
	self.halfSpeed = false
	self.endChannel = false
	return completed and self:valid()
end

-- waits for the cast key to be released (or maxT). Returns held seconds.
function Ctx:hold(maxT)
	local f = self.f
	if not f.player then
		local t = maxT * (0.4 + math.random() * 0.5)
		self:wait(t)
		return t
	end
	local h = { released = false }
	f.holds[self.slot] = h
	local start = S.now()
	while S.now() - start < maxT and not h.released and self:valid() do
		task.wait(0.03)
	end
	if f.holds[self.slot] == h then
		f.holds[self.slot] = nil
	end
	return math.min(maxT, S.now() - start)
end

-- open a recast window. fn(c2) runs when the slot is pressed again; return "keep" to keep the window.
function Ctx:recast(window, fn, opts)
	opts = opts or {}
	local f = self.f
	local r = {
		expires = S.now() + window,
		fn = fn,
		parent = self,
		onExpire = opts.onExpire,
		uses = opts.uses or 1,
	}
	f.recasts[self.slot] = r
	if f.model then
		f.model:SetAttribute("RC" .. self.slot, r.expires)
	end
	task.delay(window, function()
		if f.recasts[self.slot] == r then
			f.recasts[self.slot] = nil
			if f.model then
				f.model:SetAttribute("RC" .. self.slot, 0)
			end
			if r.onExpire then
				S.safe(r.onExpire)
			end
		end
	end)
	return r
end

function Ctx:closeRecast()
	local f = self.f
	local r = f.recasts[self.slot]
	if r then
		f.recasts[self.slot] = nil
		if f.model then
			f.model:SetAttribute("RC" .. self.slot, 0)
		end
	end
end

function Ctx:deferCooldown()
	local f = self.f
	f.cooldowns[self.slot] = math.huge
	if f.model then
		f.model:SetAttribute("CD" .. self.slot, -1)
	end
end

function Ctx:startCooldown(seconds)
	Cast.setCooldown(self.f, self.slot, seconds or self.def.cd)
end

-- transformation / timed form: Rupture waits for it. opts.onEnd(reason). Returns form handle.
function Ctx:form(duration, opts)
	opts = opts or {}
	local f = self.f
	local form = { alive = true, ends = S.now() + duration, c = self }
	local conn
	f.formActive = (f.formActive or 0) + 1
	if opts.deferCooldown ~= false and self.isUlt then
		self:deferCooldown()
	end
	f.model:SetAttribute("FormEnd", form.ends)
	function form.finish(reason)
		if not form.alive then
			return
		end
		form.alive = false
		if conn then
			conn()
			conn = nil
		end
		f.formActive = math.max(0, (f.formActive or 1) - 1)
		if f.formActive == 0 then
			f.formActive = nil
		end
		f.model:SetAttribute("FormEnd", 0)
		if opts.deferCooldown ~= false and self.isUlt then
			self:startCooldown()
		end
		if opts.onEnd then
			S.safe(opts.onEnd, reason or "ended")
		end
	end
	task.delay(duration, function()
		form.finish("expired")
	end)
	conn = S.on("defeated", function(df)
		if df == f then
			form.finish("defeated")
		end
	end)
	return form
end

-- Cooldowns -----------------------------------------------------------------------------
function Cast.setCooldown(f, slot, seconds)
	local ready = S.now() + (seconds or 0)
	f.cooldowns[slot] = ready
	if f.model then
		f.model:SetAttribute("CD" .. slot, ready)
		f.model:SetAttribute("CDLen" .. slot, seconds or 0)
	end
end

function Cast.reduceCooldown(f, slot, seconds)
	local cur = f.cooldowns[slot] or 0
	if cur == math.huge then
		return
	end
	local ready = math.max(S.now(), cur - seconds)
	f.cooldowns[slot] = ready
	if f.model then
		f.model:SetAttribute("CD" .. slot, ready)
	end
end

function Cast.cooldownLeft(f, slot)
	local cur = f.cooldowns[slot] or 0
	return math.max(0, cur - S.now())
end

-- State -------------------------------------------------------------------------------------
function Cast.isBusy(f)
	if f.action ~= nil or f.ultHold ~= nil then
		return true
	end
	return f.lockUntil ~= nil and f.lockUntil > S.now()
end

local function moveFn(f, slot)
	if f.overrides and f.overrides[slot] then
		return f.overrides[slot]
	end
	return f.kit and f.kit[slot]
end

local function canStart(f, slot, unstable)
	if not S.alive(f) then
		return false, "defeated"
	end
	if not f.kit or not f.kitData then
		return false, "no kit"
	end
	if not S.Fighter.canAct(f) then
		return false, "controlled"
	end
	if f.statuses.silence then
		return false, "silenced"
	end
	local now = S.now()
	if f.burnoutUntil and f.burnoutUntil > now then
		return false, "Burnout"
	end
	if Cast.isBusy(f) then
		return false, "busy"
	end
	if f.disabled and f.disabled[slot] then
		return false, "unavailable"
	end
	local def = f.kitData.moves[slot]
	if not def or not moveFn(f, slot) then
		return false, "no move"
	end
	if (f.cooldowns[slot] or 0) > now then
		return false, "cooldown"
	end
	local cost = (def.energy or 0) * (f.energyCostMult or 1)
	local credit = f.kit.energyCredit and f.kit.energyCredit(f, slot) or 0
	if f.energy + credit < cost then
		return false, "Energy"
	end
	if slot == 5 and f.proxima < Config.MAX_PROXIMA then
		return false, "Proxima"
	end
	if unstable and f.heat < Config.UNSTABLE_MIN_HEAT then
		return false, "Heat"
	end
	return true, def
end
Cast.canStart = canStart

function Cast.begin(f, slot, unstable, mod)
	local ok, def = canStart(f, slot, unstable)
	if not ok then
		if def ~= "busy" and def ~= "cooldown" then
			notify(f, tostring(def))
		end
		return false, def
	end
	local fn = moveFn(f, slot)
	local c = newCtx(f, slot, def)
	c.unstable = unstable == true and slot == 5
	c.mod = mod == true
	c.p60 = slot ~= 5 and f.proxima >= Config.P60
	-- kit pre-commit checks (an invalid target costs nothing)
	local req = f.kit.requires and f.kit.requires[slot]
	if req then
		local okR, reason = req(c)
		if not okR then
			notify(f, reason or "invalid")
			return false, reason
		end
	end
	-- commit
	local cost = (def.energy or 0) * (f.energyCostMult or 1)
	if f.energy < cost then
		local borrowed = cost - f.energy
		f.energy = 0
		f.lastEnergySpend = S.now()
		Combat.hook(f, "borrowEnergy", borrowed, c)
	else
		Combat.spendEnergy(f, cost)
	end
	local heat = def.heat or 0
	if c.p60 then
		heat += Config.P60_EXTRA_HEAT
	end
	if c.unstable then
		heat += Config.UNSTABLE_EXTRA_HEAT
	end
	if slot == 5 then
		f.proxima = 0
	end
	Combat.addHeat(f, heat * (f.heatMult or 1))
	f.lastAbilityUse = S.now()
	Cast.setCooldown(f, slot, def.cd)
	f.action = c
	f.guarding = false
	c.phase = "windup"
	c.energyPaid = cost
	Combat.hook(f, "cast", c)
	Combat.extraHooks(f, "cast", c)
	S.emit("cast", f, c)
	local model = f.model
	model:SetAttribute("Casting", slot)
	model:SetAttribute("CastEnd", S.now() + (def.windup or 0))
	local color = S.Util.color(f.kitName)
	if slot == 5 then
		S.FX.text(f.root, (c.unstable and "UNSTABLE " or "") .. string.upper(def.name), c.unstable and Color3.fromRGB(255, 90, 40) or color, math.max(1.2, def.windup or 1), 40)
	elseif c.p60 then
		S.FX.highlight(model, Color3.fromRGB(255, 240, 120), math.max(0.2, def.windup or 0.2), 0.8)
	end
	if (def.windup or 0) > 0 then
		S.FX.highlight(model, color, def.windup, 0.75)
	end
	local stationaryWindup = f.kit.stationaryWindup and f.kit.stationaryWindup[slot]
	task.spawn(function()
		local okW = true
		if (def.windup or 0) > 0 then
			if stationaryWindup then
				f.stationary += 1
			end
			okW = c:wait(def.windup)
			if stationaryWindup then
				f.stationary -= 1
			end
		end
		if okW then
			c.phase = "active"
			c.active = true
			model:SetAttribute("CastEnd", 0)
			local okRun, err = pcall(fn, c)
			if not okRun then
				warn("[EB] " .. tostring(f.kitName) .. " move " .. slot .. " error: " .. tostring(err))
			end
		elseif c.isUlt and not c.active then
			-- interrupted ultimate before its first active effect
			f.proxima = math.min(Config.MAX_PROXIMA, f.proxima + Config.ULT_INTERRUPT_REFUND_P)
			Combat.addEnergy(f, (c.energyPaid or 0) / 2)
			Cast.setCooldown(f, 5, Config.ULT_INTERRUPT_CD)
			notify(f, "Ultimate interrupted")
		end
		if f.action == c then
			f.action = nil
		end
		if S.alive(f) then
			model:SetAttribute("Casting", 0)
			model:SetAttribute("CastEnd", 0)
			local rec = c.recovery
			if rec == nil then
				rec = Config.DEFAULT_RECOVERY
			end
			rec = math.max(0, rec - (c.recoveryBonus or 0))
			f.lockUntil = S.now() + rec
			-- buffered input
			local buf = f.buffer
			if buf and S.now() - buf.t < 0.35 + rec then
				f.buffer = nil
				task.delay(rec, function()
					if S.alive(f) and not Cast.isBusy(f) then
						Cast.press(f, buf.slot, true, buf.mod)
					end
				end)
			end
		end
	end)
	return true
end

-- run a recast for slot
local function runRecast(f, slot, mod)
	local r = f.recasts[slot]
	if not r or r.expires < S.now() then
		return false
	end
	if not S.Fighter.canAct(f) then
		return false
	end
	local parent = r.parent
	r.uses -= 1
	if r.uses <= 0 then
		f.recasts[slot] = nil
		f.model:SetAttribute("RC" .. slot, 0)
	end
	local c2 = newCtx(f, slot, parent.def)
	c2.parent = parent
	c2.isRecast = true
	c2.p60 = parent.p60
	c2.unstable = parent.unstable
	c2.mod = mod
	c2.active = true
	c2.phase = "active"
	c2.data = parent.data
	c2.pGranted = parent.pGranted
	local concurrent = f.action == parent or (f.action ~= nil and f.action.parent == parent)
	if not concurrent then
		if Cast.isBusy(f) then
			-- restore and buffer
			if r.uses <= 0 then
				r.uses = 1
				f.recasts[slot] = r
				f.model:SetAttribute("RC" .. slot, r.expires)
			else
				r.uses += 1
			end
			f.buffer = { slot = slot, t = S.now(), mod = mod }
			return true
		end
		f.action = c2
	end
	task.spawn(function()
		local okRun, res = pcall(r.fn, c2)
		if not okRun then
			warn("[EB] recast error: " .. tostring(res))
		elseif res == "keep" and r.expires > S.now() then
			r.uses = math.max(r.uses, 1)
			f.recasts[slot] = r
			f.model:SetAttribute("RC" .. slot, r.expires)
		end
		if f.action == c2 then
			f.action = nil
			f.lockUntil = S.now() + (c2.recovery or Config.MOVE_RECOVERY)
		end
	end)
	return true
end

-- Input entry points ---------------------------------------------------------------------
function Cast.press(f, slot, down, mod)
	if not S.alive(f) then
		return
	end
	if type(slot) ~= "number" or slot < 1 or slot > 5 then
		return
	end
	if down then
		if f.recasts[slot] then
			if runRecast(f, slot, mod) then
				return
			end
		end
		if f.holds[slot] then
			return
		end
		if slot == 5 and f.heat >= Config.UNSTABLE_MIN_HEAT and f.player then
			local ok, why = canStart(f, 5, true)
			if ok then
				f.ultHold = { start = S.now(), mod = mod }
				f.model:SetAttribute("UltHold", S.now())
				f.holdFX = S.FX.text(f.root, "UNSTABLE HOLD", Color3.fromRGB(255, 120, 40), Config.UNSTABLE_HOLD + 0.2, 34)
				return
			elseif why == "busy" then
				f.buffer = { slot = slot, t = S.now(), mod = mod }
				return
			end
		end
		local ok, why = Cast.begin(f, slot, false, mod)
		if not ok and why == "busy" then
			f.buffer = { slot = slot, t = S.now(), mod = mod }
		end
	else
		local h = f.holds[slot]
		if h then
			h.released = true
		end
		if slot == 5 and f.ultHold then
			-- released before the extra second: ordinary ultimate
			local hold = f.ultHold
			f.ultHold = nil
			f.model:SetAttribute("UltHold", 0)
			if f.holdFX then
				f.holdFX:Destroy()
				f.holdFX = nil
			end
			Cast.begin(f, 5, false, hold.mod)
		end
	end
end

function Cast.updateHold(f, now)
	local h = f.ultHold
	if not h then
		return
	end
	if not S.Fighter.canAct(f) or f.dead then
		Cast.abandonHold(f)
		return
	end
	if now - h.start >= Config.UNSTABLE_HOLD then
		f.ultHold = nil
		f.model:SetAttribute("UltHold", 0)
		f.holdFX = nil
		Cast.begin(f, 5, true, h.mod)
	end
end

function Cast.abandonHold(f)
	if f.ultHold then
		f.ultHold = nil
		f.model:SetAttribute("UltHold", 0)
		if f.holdFX then
			f.holdFX:Destroy()
			f.holdFX = nil
		end
		notify(f, "Unstable hold abandoned")
	end
end

function Cast.rupture(f)
	if not f.rupturePending then
		return
	end
	f.rupturePending = false
	f.proxima = 0
	f.burnoutUntil = S.now() + Config.BURNOUT_TIME
	f.burnoutActive = true
	f.model:SetAttribute("Burnout", f.burnoutUntil)
	S.FX.text(f.root, "BURNOUT", Color3.fromRGB(255, 70, 30), Config.BURNOUT_TIME, 40)
	S.FX.burst(f.root.Position, M * 3, Color3.fromRGB(255, 90, 30), 0.5)
	Combat.hook(f, "rupture")
	Combat.extraHooks(f, "rupture")
end

function Cast.kitAction(f, arg)
	if not S.alive(f) or not f.kit or not f.kit.action then
		return
	end
	if not S.Fighter.canAct(f) then
		return
	end
	S.safe(f.kit.action, f, arg)
end

return Cast
