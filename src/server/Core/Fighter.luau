-- A Fighter is any damageable combatant: players, bots, training dummies and summons.
local Players = game:GetService("Players")
local S = require(script.Parent.S)
local Status = require(script.Parent.Status)

local Fighter = {}
S.Fighter = Fighter

local Config = S.Config
local M = Config.METRE

function Fighter.get(model)
	return S.byModel[model]
end

function Fighter.fromPart(part)
	local m = part
	while m and m ~= workspace do
		local f = S.byModel[m]
		if f then
			return f
		end
		m = m.Parent
	end
	return nil
end

function Fighter.new(model, opts)
	opts = opts or {}
	S.nextId += 1
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	local hum = model:FindFirstChildOfClass("Humanoid")
	local maxHealth = opts.maxHealth or Config.MAX_HEALTH
	local now = S.now()
	local f = {
		id = S.nextId,
		model = model,
		root = root,
		humanoid = hum,
		player = opts.player,
		isBot = opts.isBot,
		isDummy = opts.isDummy,
		isSummon = opts.isSummon,
		owner = opts.owner,
		team = opts.team,
		name = opts.name or model.Name,
		maxHealth = maxHealth,
		health = maxHealth,
		energy = Config.MAX_ENERGY,
		heat = 0,
		proxima = 0,
		guard = Config.MAX_GUARD,
		dodgeCharges = Config.DODGE_CHARGES,
		dodgeRechargeAt = 0,
		lastEnergySpend = 0,
		lastAbilityUse = 0,
		lastGuardHit = 0,
		lastHit = 0,
		lastDirectHit = 0,
		lastContest = 0,
		contest = {},
		shields = {},
		statuses = {},
		controlLog = {},
		cooldowns = { 0, 0, 0, 0, 0 },
		recasts = {},
		holds = {},
		res = {},
		state = {},
		hooks = {},
		objects = {},
		summons = {},
		zones = {},
		stationary = 0,
		invulnCount = 0,
		untargetable = 0,
		hitScale = 1,
		speedMult = 1,
		jumpMult = 1,
		lastBasic = 0,
		spawnTime = now,
		attrCache = {},
		aim = nil,
		radius = opts.radius,
	}
	S.fighters[f.id] = f
	S.byModel[model] = f
	if hum then
		hum.MaxHealth = maxHealth
		hum.Health = maxHealth
		hum.UseJumpPower = false
		hum.JumpHeight = Config.JUMP_HEIGHT * M
		hum.WalkSpeed = Config.RUN_SPEED * M
		hum.BreakJointsOnDeath = false
		hum:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	if root then
		f.lastLegal = root.Position
	end
	model:SetAttribute("FighterId", f.id)
	model:SetAttribute("MaxHealth", maxHealth)
	if opts.kit then
		Fighter.setKit(f, opts.kit)
	end
	Fighter.attachNameplate(f)
	return f
end

function Fighter.setKit(f, kitName)
	local kits = S.Kits
	local kit = kits and kits.get(kitName)
	if not kit then
		warn("[EB] unknown kit " .. tostring(kitName))
		kitName = Config.DEFAULT_KIT
		kit = kits.get(kitName)
	end
	-- teardown previous kit state
	if f.kit and f.kit.passive and f.kit.passive.cleanup then
		S.safe(f.kit.passive.cleanup, f)
	end
	f.kitName = kitName
	f.kit = kit
	f.kitData = kits.data(kitName)
	f.hooks = {}
	f.extraHooks = {}
	f.state = {}
	f.res = {}
	f.overrides = {}
	f.cooldowns = { 0, 0, 0, 0, 0 }
	if kit.passive then
		for k, v in pairs(kit.passive) do
			if type(v) == "function" and k ~= "init" and k ~= "tick" and k ~= "cleanup" then
				f.hooks[k] = v
			end
		end
		if kit.passive.init then
			S.safe(kit.passive.init, f)
		end
	end
	f.model:SetAttribute("Kit", kitName)
	f.resDirty = true
end

-- Resource bar for kit-specific counters (shown on the HUD).
function Fighter.setRes(f, key, value, max, order)
	local r = f.res[key]
	if not r then
		r = { order = order or 10 }
		f.res[key] = r
	end
	if r.value ~= value or r.max ~= max then
		r.value = value
		r.max = max
		f.resDirty = true
	end
end

function Fighter.clearRes(f, key)
	if f.res[key] then
		f.res[key] = nil
		f.resDirty = true
	end
end

local function resString(f)
	local items = {}
	for k, r in pairs(f.res) do
		local v = r.value
		local txt
		if type(v) == "number" then
			txt = k .. " " .. S.Util.fmt(v) .. (r.max and ("/" .. S.Util.fmt(r.max)) or "")
		else
			txt = k .. ": " .. tostring(v)
		end
		table.insert(items, { o = r.order or 10, t = txt })
	end
	table.sort(items, function(a, b)
		if a.o == b.o then
			return a.t < b.t
		end
		return a.o < b.o
	end)
	local out = {}
	for _, it in ipairs(items) do
		table.insert(out, it.t)
	end
	return table.concat(out, "   ")
end

local function setAttr(f, key, value)
	if f.attrCache[key] ~= value then
		f.attrCache[key] = value
		f.model:SetAttribute(key, value)
	end
end
Fighter.setAttr = setAttr

function Fighter.syncHealth(f)
	if f.health > f.maxHealth then
		f.health = f.maxHealth
	end
	if f.humanoid and not f.dead then
		f.humanoid.MaxHealth = f.maxHealth
		f.humanoid.Health = math.max(f.health, 0.01)
	end
	setAttr(f, "Health", math.max(0, math.floor(f.health + 0.5)))
	setAttr(f, "Shield", math.floor(S.Combat.totalShield(f) + 0.5))
end

function Fighter.attachNameplate(f)
	if not f.root then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "EBPlate"
	bb.Size = UDim2.fromOffset(150, 46)
	bb.StudsOffset = Vector3.new(0, f.isSummon and 2.5 or 3.6, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 120
	bb.LightInfluence = 0
	bb.Adornee = f.model:FindFirstChild("Head") or f.root
	local name = Instance.new("TextLabel")
	name.Name = "NameLabel"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 16)
	name.Font = Enum.Font.GothamBold
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.3
	name.Text = f.name
	name.Parent = bb
	local back = Instance.new("Frame")
	back.Name = "Bar"
	back.Position = UDim2.fromOffset(0, 18)
	back.Size = UDim2.new(1, 0, 0, 8)
	back.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	back.BorderSizePixel = 0
	back.Parent = bb
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 220, 90)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local sh = Instance.new("Frame")
	sh.Name = "ShieldFill"
	sh.Size = UDim2.fromScale(0, 1)
	sh.BackgroundColor3 = Color3.fromRGB(140, 200, 255)
	sh.BackgroundTransparency = 0.2
	sh.BorderSizePixel = 0
	sh.Parent = back
	local st = Instance.new("TextLabel")
	st.Name = "Status"
	st.BackgroundTransparency = 1
	st.Position = UDim2.fromOffset(0, 28)
	st.Size = UDim2.new(1, 0, 0, 16)
	st.Font = Enum.Font.Gotham
	st.TextScaled = true
	st.TextColor3 = Color3.fromRGB(255, 220, 160)
	st.TextStrokeTransparency = 0.4
	st.Text = ""
	st.Parent = bb
	bb.Parent = f.root
	f.plate = bb
end

local function updatePlate(f)
	local bb = f.plate
	if not bb then
		return
	end
	local fill = bb.Bar.Fill
	local pct = math.clamp(f.health / f.maxHealth, 0, 1)
	fill.Size = UDim2.fromScale(pct, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 70, 70):Lerp(Color3.fromRGB(90, 220, 90), pct)
	local shv = math.clamp(S.Combat.totalShield(f) / f.maxHealth, 0, 1)
	bb.Bar.ShieldFill.Size = UDim2.fromScale(shv, 1)
	local lbl = f.statusText or ""
	if f.kitName and not f.isSummon then
		bb.NameLabel.Text = f.name .. "  [" .. f.kitName .. "]"
	end
	bb.Status.Text = lbl
end

-- Movement ----------------------------------------------------------------------
function Fighter.canMove(f)
	local s = f.statuses
	return not (s.stun or s.root or s.sleep or s.lift or s.guardbreak or s.lock) and f.stationary <= 0
end

function Fighter.canAct(f)
	local s = f.statuses
	return not (s.stun or s.sleep or s.guardbreak or s.lock) and not f.dead
end

function Fighter.applyMovement(f)
	local hum = f.humanoid
	if not hum or f.dead then
		return
	end
	local speed = Config.RUN_SPEED * M
	local mult = (1 - Status.slow(f)) * (1 + Status.speedBonus(f)) * (f.speedMult or 1)
	if f.guarding then
		mult *= Config.GUARD_MOVE_MULT
	end
	local a = f.action
	if a and a.phase == "windup" and not a.moveFree then
		mult *= 0.5
	elseif a and a.halfSpeed then
		mult *= 0.5
	end
	if f.isDummy then
		mult = 0
	end
	local s = f.statuses
	local jump = Config.JUMP_HEIGHT * M * (f.jumpMult or 1)
	if s.stun or s.root or s.sleep or s.lift or s.guardbreak or s.lock or f.stationary > 0 then
		mult = 0
		jump = 0
	end
	local ws = speed * mult
	if math.abs(hum.WalkSpeed - ws) > 0.05 then
		hum.WalkSpeed = ws
	end
	if math.abs(hum.JumpHeight - jump) > 0.05 then
		hum.JumpHeight = jump
	end
end

-- velocity-based displacement (works for client-owned characters)
function Fighter.displace(f, dirUnit, dist, time, up)
	if not S.alive(f) or dist <= 0 then
		return
	end
	if f.isSummon then
		local target = S.Hit.clearPath(f.root.Position, dirUnit, dist, 1)
		f.root.CFrame = CFrame.new(target) * f.root.CFrame.Rotation
		return
	end
	time = math.max(0.08, time or 0.2)
	-- clip to walls
	local endPos = S.Hit.clearPath(f.root.Position, dirUnit, dist, 1.3)
	local real = (endPos - f.root.Position).Magnitude
	if real < 0.2 then
		return
	end
	local att = f.root:FindFirstChild("EBMoveAtt")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "EBMoveAtt"
		att.Parent = f.root
	end
	local old = f.root:FindFirstChild("EBDisplace")
	if old then
		old:Destroy()
	end
	local lv = Instance.new("LinearVelocity")
	lv.Name = "EBDisplace"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 1e7
	lv.VectorVelocity = dirUnit * (real / time) + Vector3.new(0, up or 0, 0)
	lv.Parent = f.root
	f.displacedUntil = S.now() + time
	task.delay(time, function()
		if lv.Parent then
			lv:Destroy()
		end
	end)
end

-- dash used by movement abilities and dodge; returns final travel distance (studs)
function Fighter.dash(f, dirUnit, dist, time, opts)
	opts = opts or {}
	if not S.alive(f) then
		return 0
	end
	local flat = Vector3.new(dirUnit.X, opts.allowY and dirUnit.Y or 0, dirUnit.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(f.root.CFrame.LookVector.X, 0, f.root.CFrame.LookVector.Z)
	end
	flat = flat.Unit
	local endPos = S.Hit.clearPath(f.root.Position, flat, dist, 1.3)
	local real = (endPos - f.root.Position).Magnitude
	if real < 0.2 then
		return 0
	end
	if f.isSummon then
		f.root.CFrame = CFrame.new(endPos) * f.root.CFrame.Rotation
		return real
	end
	Fighter.displace(f, flat, real, time, opts.up)
	return real
end

function Fighter.teleport(f, pos, keepFacing)
	if not S.alive(f) then
		return false
	end
	local rot = f.root.CFrame.Rotation
	if f.model.PrimaryPart or f.humanoid then
		f.model:PivotTo(CFrame.new(pos) * (keepFacing ~= false and rot or CFrame.new()))
	else
		f.root.CFrame = CFrame.new(pos) * rot
	end
	return true
end

function Fighter.applyLift(f, height, dur)
	if not S.alive(f) or f.isSummon then
		return
	end
	local att = f.root:FindFirstChild("EBMoveAtt")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "EBMoveAtt"
		att.Parent = f.root
	end
	local old = f.root:FindFirstChild("EBLift")
	if old then
		old:Destroy()
	end
	local lv = Instance.new("LinearVelocity")
	lv.Name = "EBLift"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 1e7
	local riseT = math.min(0.25, dur * 0.5)
	lv.VectorVelocity = Vector3.new(0, height / riseT, 0)
	lv.Parent = f.root
	task.delay(riseT, function()
		if lv.Parent then
			lv.VectorVelocity = Vector3.zero
		end
	end)
	task.delay(dur, function()
		if lv.Parent then
			lv:Destroy()
		end
	end)
end

-- Guard / dodge / basic -------------------------------------------------------------
function Fighter.setGuard(f, on)
	if not on then
		f.guarding = false
		return
	end
	if f.dead or f.noGuard or f.guard <= 0 then
		return
	end
	if not Fighter.canAct(f) then
		return
	end
	if S.Cast and S.Cast.isBusy(f) then
		return
	end
	if f.ultHold then
		S.Cast.abandonHold(f)
	end
	if not f.guarding then
		f.guarding = true
		f.guardStart = S.now()
	end
end

function Fighter.dodge(f, moveDir)
	if f.dead or f.dodgeCharges <= 0 or f.noDodge then
		return false
	end
	local s = f.statuses
	if s.root or s.stun or s.sleep or s.lift or s.guardbreak or s.lock then
		return false
	end
	if f.ultHold then
		S.Cast.abandonHold(f)
		return false
	end
	if S.Cast and S.Cast.isBusy(f) then
		return false
	end
	f.dodgeCharges -= 1
	if f.dodgeRechargeAt <= S.now() then
		f.dodgeRechargeAt = S.now() + Config.DODGE_RECHARGE
	end
	f.guarding = false
	local dir = moveDir
	if not dir or dir.Magnitude < 0.1 then
		dir = f.root.CFrame.LookVector
	end
	local now = S.now()
	task.delay(Config.DODGE_IFRAME_START, function()
		f.iframeUntil = S.now() + Config.DODGE_IFRAME_LEN
	end)
	f.dodgingUntil = now + Config.DODGE_TIME
	Fighter.dash(f, dir, Config.DODGE_DISTANCE * M, Config.DODGE_TIME)
	S.FX.trail(f.root, Color3.fromRGB(220, 220, 255), 0.4)
	S.Combat.hook(f, "dodge", dir)
	S.Combat.extraHooks(f, "dodge", dir)
	return true
end

function Fighter.basic(f)
	if f.dead or not Fighter.canAct(f) then
		return
	end
	if S.Cast and S.Cast.isBusy(f) then
		return
	end
	if f.noBasic then
		return
	end
	local now = S.now()
	local interval = f.basicInterval or Config.BASIC_INTERVAL
	if now - f.lastBasic < interval then
		return
	end
	f.lastBasic = now
	f.guarding = false
	if f.basicOverride then
		S.safe(f.basicOverride, f)
		return
	end
	if f.kit and f.kit.basic then
		S.safe(f.kit.basic, f)
		return
	end
	Fighter.defaultBasic(f, Config.BASIC_DAMAGE, Config.BASIC_RANGE)
end

function Fighter.defaultBasic(f, dmg, rangeM, opts)
	opts = opts or {}
	local look = f.root.CFrame.LookVector
	if f.aim and f.aim.dir then
		look = Vector3.new(f.aim.dir.X, 0, f.aim.dir.Z)
		if look.Magnitude > 0.01 then
			look = look.Unit
			if f.humanoid and not f.isBot then
				f.root.CFrame = CFrame.lookAt(f.root.Position, f.root.Position + look)
			end
		else
			look = f.root.CFrame.LookVector
		end
	end
	local hits = S.Hit.cone(f.root.Position, look, rangeM * M, Config.BASIC_ARC, function(t)
		return t ~= f and S.isEnemy(f, t)
	end, true)
	S.FX.cone(f.root.Position, look, rangeM * M, 70, opts.color or Color3.fromRGB(255, 255, 255), 0.12)
	S.FX.sound(f.root, "swing", 0.3)
	local any = false
	for _, t in ipairs(hits) do
		any = true
		S.Combat.damage(f, t, dmg, { isBasic = true, melee = true, element = f.kitName })
		if opts.onHit then
			opts.onHit(t)
		end
	end
	-- basics also chip constructs in front
	local objs = S.Objects and S.Objects.inRadius(f.root.Position + look * M * 1.5, M * 1.5, function(o)
		return o.owner == nil or S.isEnemy(f, o.owner)
	end) or {}
	for _, o in ipairs(objs) do
		S.Objects.damage(o, dmg, f)
	end
	return any
end

-- Defeat ----------------------------------------------------------------------------
function Fighter.kill(f, src)
	if f.dead then
		return
	end
	f.dead = true
	f.health = 0
	f.guarding = false
	if f.action then
		f.action.interrupted = true
		f.action.interruptReason = "defeat"
	end
	if f.ultHold then
		f.ultHold = nil
	end
	setAttr(f, "Health", 0)
	-- owner-dependent summons vanish
	for _, sm in ipairs(table.clone(f.summons)) do
		if S.Summons then
			S.Summons.remove(sm, "owner defeated")
		end
	end
	if f.kit and f.kit.passive and f.kit.passive.cleanup then
		S.safe(f.kit.passive.cleanup, f)
	end
	if f.humanoid then
		f.humanoid.Health = 0
	end
	local killer = src and (src.owner or src) or f.lastDamager
	S.emit("defeated", f, killer)
end

function Fighter.remove(f)
	S.fighters[f.id] = nil
	S.byModel[f.model] = nil
	f.dead = true
	for _, sm in ipairs(table.clone(f.summons)) do
		if S.Summons then
			S.Summons.remove(sm, "removed")
		end
	end
	if S.Objects then
		S.Objects.removeOwned(f)
	end
	if S.Zones then
		S.Zones.removeOwned(f)
	end
end

-- Per-tick update (called at ~10 Hz) -------------------------------------------------
function Fighter.tick(f, dt, now)
	if f.dead or not f.root or not f.root.Parent then
		return
	end
	local burnout = f.burnoutUntil and f.burnoutUntil > now
	-- energy
	if now - f.lastEnergySpend >= Config.ENERGY_REGEN_DELAY and not f.noEnergyRegen then
		f.energy = math.min(Config.MAX_ENERGY, f.energy + Config.ENERGY_REGEN * dt * (f.energyRegenMult or 1))
	end
	-- heat
	if not f.rupturePending and not burnout and now - f.lastAbilityUse >= Config.HEAT_COOL_DELAY then
		f.heat = math.max(0, f.heat - Config.HEAT_COOL * dt)
	end
	-- burnout end
	if f.burnoutUntil and not burnout and f.burnoutActive then
		f.burnoutActive = false
		f.heat = Config.BURNOUT_END_HEAT
		setAttr(f, "Burnout", 0)
	end
	-- proxima
	if not f.isSummon then
		local best = 0
		local myPos = f.root.Position
		for other, t in pairs(f.contest) do
			if now - t > Config.CONTEST_WINDOW or not S.alive(other) then
				f.contest[other] = nil
			else
				local d = (other.root.Position - myPos).Magnitude / M
				if d <= Config.P_FAR_RANGE and S.Hit.los(myPos, other.root.Position, true) then
					local rate = d <= Config.P_NEAR_RANGE and Config.P_NEAR_RATE or Config.P_FAR_RATE
					if rate > best then
						best = rate
					end
				end
			end
		end
		if best > 0 and not f.rupturePending then
			S.Combat.addProxima(f, best * dt, "proximity")
		end
		if now - f.lastContest > Config.P_DECAY_DELAY and now - (f.lastHit or 0) > Config.P_DECAY_DELAY then
			f.proxima = math.max(0, f.proxima - Config.P_DECAY_RATE * dt)
		end
	end
	-- guard
	if f.guarding then
		f.guard -= Config.GUARD_DRAIN * dt
		if f.guard <= 0 then
			f.guard = 0
			S.Combat.guardBreak(f, nil)
		end
		if not Fighter.canAct(f) then
			f.guarding = false
		end
	elseif now - f.lastGuardHit >= Config.GUARD_RECOVER_DELAY and now - f.lastDirectHit >= Config.GUARD_RECOVER_DELAY then
		if not (f.guardBrokenUntil and f.guardBrokenUntil > now) then
			f.guard = math.min(Config.MAX_GUARD, f.guard + Config.GUARD_RECOVER * dt)
		end
	end
	-- dodge recharge (sequential)
	if f.dodgeCharges < Config.DODGE_CHARGES and now >= f.dodgeRechargeAt and f.dodgeRechargeAt > 0 then
		f.dodgeCharges += 1
		if f.dodgeCharges < Config.DODGE_CHARGES then
			f.dodgeRechargeAt = now + Config.DODGE_RECHARGE
		else
			f.dodgeRechargeAt = 0
		end
	end
	-- shields expiry
	for i = #f.shields, 1, -1 do
		if f.shields[i].expires <= now then
			table.remove(f.shields, i)
		end
	end
	Status.update(f, now)
	-- unstable hold
	if f.ultHold and S.Cast then
		S.Cast.updateHold(f, now)
	end
	-- rupture when idle
	if f.rupturePending and S.Cast and not S.Cast.isBusy(f) and not f.formActive then
		S.Cast.rupture(f)
	end
	-- kit passive tick
	if f.kit and f.kit.passive and f.kit.passive.tick then
		S.safe(f.kit.passive.tick, f, dt, now)
	end
	Fighter.applyMovement(f)
	-- out of bounds / last legal ground
	if f.humanoid and not f.isSummon then
		local pos = f.root.Position
		local bounds = S.arenaBounds
		if bounds then
			local out = pos.Y < bounds.floorY - 30
				or math.abs(pos.X - bounds.center.X) > bounds.half + 80
				or math.abs(pos.Z - bounds.center.Z) > bounds.half + 80
			if out then
				Fighter.outOfBounds(f)
			elseif f.humanoid.FloorMaterial ~= Enum.Material.Air then
				f.legalTimer = (f.legalTimer or 0) + dt
				if f.legalTimer > 0.5 then
					f.legalTimer = 0
					if math.abs(pos.X - bounds.center.X) < bounds.half and math.abs(pos.Z - bounds.center.Z) < bounds.half then
						f.lastLegal = pos
					end
				end
			end
		end
	end
	-- attributes
	setAttr(f, "Energy", math.floor(f.energy + 0.5))
	setAttr(f, "Heat", math.floor(f.heat + 0.5))
	setAttr(f, "Proxima", math.floor(f.proxima))
	setAttr(f, "Guard", math.floor(f.guard + 0.5))
	setAttr(f, "Guarding", f.guarding == true)
	setAttr(f, "Dodge", f.dodgeCharges)
	setAttr(f, "Rupture", f.rupturePending == true)
	setAttr(f, "Shield", math.floor(S.Combat.totalShield(f) + 0.5))
	setAttr(f, "CCImmune", (f.ccImmuneUntil and f.ccImmuneUntil > now) and f.ccImmuneUntil or 0)
	if f.statusDirty then
		f.statusDirty = false
		f.statusText = Status.label(f)
		setAttr(f, "Statuses", f.statusText)
	end
	if f.resDirty then
		f.resDirty = false
		setAttr(f, "KitRes", resString(f))
	end
	updatePlate(f)
end

function Fighter.outOfBounds(f)
	local now = S.now()
	local back = f.lastLegal or (S.arenaBounds and S.arenaBounds.center + Vector3.new(0, 6, 0))
	if f.root:FindFirstChild("EBDisplace") then
		f.root.EBDisplace:Destroy()
	end
	f.root.AssemblyLinearVelocity = Vector3.zero
	Fighter.teleport(f, back + Vector3.new(0, 1, 0))
	if not f.lastOOB or now - f.lastOOB > 8 then
		f.lastOOB = now
		S.Combat.damage(f.lastDamager, f, Config.OOB_PENALTY, { kind = "true", tag = "oob" })
		S.Combat.control(f, "lock", Config.OOB_LOCK, nil, { force = true })
	end
end

function Fighter.forPlayer(player)
	local ch = player.Character
	return ch and S.byModel[ch]
end

Players.PlayerRemoving:Connect(function(p)
	local ch = p.Character
	local f = ch and S.byModel[ch]
	if f then
		Fighter.remove(f)
	end
end)

return Fighter
