-- Server visual API. Gameplay code describes WHAT happened (a burst here, a beam there, a telegraph with
-- this exact radius); clients decide HOW it looks. Short-lived effects are sent as batched "cues" over
-- one remote per frame and rendered client-side with the caster's element style (Shared/Styles).
-- Long-lived visuals that gameplay code keeps a handle to (zone floors, domes, persistent beams) stay
-- real instances, tagged "EBVis" with Kit/VisKind attributes so clients can dress them.
-- Every cue carries the element context of the code that produced it (thread-local, see FX.bind).
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local S = require(script.Parent.S)

local FX = {}
S.FX = FX

local WHITE = Color3.new(1, 1, 1)
local PERSIST_AFTER = 1.5 -- effects living longer than this become instances
local remote
local queue = {}
local nextId = 0

function FX.init(r)
	remote = r.Cue
end

-- Element context ------------------------------------------------------------------------------------
-- FX.current is a synchronous override (callbacks); threadCtx follows yielding kit coroutines.
local threadCtx = setmetatable({}, { __mode = "k" })
FX.current = nil

local function ctxNow()
	if FX.current then
		return FX.current
	end
	return threadCtx[coroutine.running()]
end
FX.ctx = ctxNow

-- cached context table for a fighter (summons render in their owner's style)
function FX.ctxOf(f)
	if not f then
		return nil
	end
	local real = f.owner or f
	local c = f._fxctx
	if not c or c.kit ~= real.kitName then
		c = { kit = real.kitName, owner = real.id, team = real.team }
		f._fxctx = c
	end
	return c
end

-- bind the running thread to a fighter (kit + owner id)
function FX.bindThread(f)
	if f then
		threadCtx[coroutine.running()] = FX.ctxOf(f)
	end
end

-- run fn with a synchronous context (does not survive yields)
function FX.with(f, fn, ...)
	local prev = FX.current
	FX.current = FX.ctxOf(f)
	local ok, a, b = pcall(fn, ...)
	FX.current = prev
	if not ok then
		error(a, 0)
	end
	return a, b
end

-- spawn helpers that carry the current context into new threads
function FX.spawnCtx(fn, ...)
	local c = ctxNow()
	return task.spawn(function(...)
		threadCtx[coroutine.running()] = c
		fn(...)
	end, ...)
end
function FX.delayCtx(t, fn, ...)
	local c = ctxNow()
	return task.delay(t, function(...)
		threadCtx[coroutine.running()] = c
		fn(...)
	end, ...)
end

-- Cue transport --------------------------------------------------------------------------------------
local function cue(kind, data)
	local c = ctxNow()
	if c then
		data.k = data.k or c.kit
		data.o = data.o or c.owner
	end
	nextId += 1
	data.id = nextId
	queue[#queue + 1] = { kind, data }
	return nextId
end
FX.cue = cue

RunService.Heartbeat:Connect(function()
	if #queue == 0 then
		return
	end
	local batch = queue
	queue = {}
	if remote then
		remote:FireAllClients(batch)
	end
end)

-- Handles for cue effects: gameplay code may keep them, set properties or Destroy them early.
local Ghost = {}
local function ghostDestroy(self)
	if not rawget(self, "_dead") then
		rawset(self, "_dead", true)
		cue("kill", { target = rawget(self, "_id") })
	end
end
local noop = function() end
Ghost.__index = function(self, key)
	if key == "Destroy" or key == "Remove" then
		return ghostDestroy
	end
	if key == "Parent" then
		return not rawget(self, "_dead") and S.folders.FX or nil
	end
	local props = rawget(self, "_props")
	local v = props and props[key]
	if v ~= nil then
		return v
	end
	if key == "IsA" or key == "GetAttribute" or key == "SetAttribute" or key == "FindFirstChild" or key == "PivotTo" then
		return noop
	end
	return nil
end
Ghost.__newindex = function(self, key, value)
	if key == "Parent" and value == nil then
		ghostDestroy(self)
		return
	end
	local props = rawget(self, "_props")
	if props then
		props[key] = value
	end
	if key == "Position" or key == "CFrame" then
		cue("move", { target = rawget(self, "_id"), p = typeof(value) == "CFrame" and value.Position or value })
	end
end
local function ghost(id, props)
	return setmetatable({ _id = id, _props = props or {} }, Ghost)
end
FX.ghost = ghost

-- Persistent instances ---------------------------------------------------------------------------------
local function base(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = props.material or Enum.Material.Neon
	p.Color = props.color or WHITE
	p.Transparency = props.transparency or 0.3
	p.Shape = props.shape or Enum.PartType.Block
	p.Size = props.size or Vector3.new(1, 1, 1)
	p.CFrame = props.cf or CFrame.new()
	p.Name = props.name or "FX"
	local c = ctxNow()
	if c then
		p:SetAttribute("Kit", c.kit)
		p:SetAttribute("Owner", c.owner)
	end
	p:SetAttribute("VisKind", props.visKind or "base")
	CollectionService:AddTag(p, "EBVis")
	p.Parent = props.parent or S.folders.FX
	return p
end
FX.base = base

local function lifetime(p, dur)
	if dur then
		Debris:AddItem(p, dur)
	end
end

local function persistent(dur)
	return dur == nil or dur == false or dur > PERSIST_AFTER
end

-- Shapes -------------------------------------------------------------------------------------------------
function FX.sphere(pos, radius, color, dur, transparency)
	if persistent(dur) then
		local p = base({
			shape = Enum.PartType.Ball,
			size = Vector3.one * radius * 2,
			cf = CFrame.new(pos),
			color = color,
			transparency = transparency or 0.45,
			visKind = "sphere",
			material = Enum.Material.ForceField,
		})
		lifetime(p, dur)
		return p
	end
	local id = cue("sphere", { p = pos, r = radius, c = color, d = dur or 0.4, t = transparency })
	return ghost(id, { Position = pos, Size = Vector3.one * radius * 2, Color = color })
end

function FX.burst(pos, radius, color, dur)
	local id = cue("burst", { p = pos, r = radius, c = color, d = dur or 0.35 })
	return ghost(id, { Position = pos })
end

function FX.disc(pos, radius, color, dur, transparency, height)
	if persistent(dur) then
		local p = base({
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(height or 0.25, radius * 2, radius * 2),
			cf = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
			color = color,
			transparency = transparency or 0.6,
			material = Enum.Material.ForceField,
			visKind = "disc",
		})
		lifetime(p, dur)
		return p
	end
	local id = cue("disc", { p = pos, r = radius, c = color, d = dur, t = transparency })
	return ghost(id, { Position = pos })
end

function FX.ring(pos, radius, color, dur, thickness)
	if persistent(dur) then
		local p = base({
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(0.2, radius * 2, radius * 2),
			cf = CFrame.new(pos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			color = color,
			transparency = 0.85,
			material = Enum.Material.ForceField,
			visKind = "ring",
		})
		p:SetAttribute("Thickness", thickness or 0.35)
		lifetime(p, dur)
		return p
	end
	local id = cue("ring", { p = pos, r = radius, c = color, d = dur or 0.4, w = thickness or 0.35 })
	return ghost(id, { Position = pos })
end

-- Telegraphs always show the exact affected shape. `owner` lets each client draw hostile warnings
-- (spiked, pulsing) differently from friendly ones (thin, dashed).
function FX.telegraph(pos, radius, dur, color, owner)
	local id = cue("tele", { p = pos, r = radius, d = dur, c = color or Color3.fromRGB(255, 80, 80), o = owner and owner.id or nil })
	return ghost(id, { Position = pos })
end

function FX.rect(cf, width, length, dur, color, transparency)
	if persistent(dur) then
		local p = base({
			size = Vector3.new(width, 0.2, length),
			cf = cf,
			color = color or Color3.fromRGB(255, 80, 80),
			transparency = transparency or 0.55,
			material = Enum.Material.ForceField,
			visKind = "rect",
		})
		lifetime(p, dur)
		return p
	end
	local id = cue("rect", { cf = cf, w = width, l = length, d = dur, c = color, t = transparency })
	return ghost(id, { CFrame = cf })
end

function FX.lineTelegraph(origin, dir, length, width, dur, color, owner)
	local d = Vector3.new(dir.X, 0, dir.Z)
	if d.Magnitude < 1e-3 then
		d = Vector3.new(0, 0, -1)
	end
	d = d.Unit
	local id = cue("teleLine", { p = origin, dir = d, l = length, w = width, d = dur, c = color or Color3.fromRGB(255, 80, 80), o = owner and owner.id or nil })
	return ghost(id, { Position = origin })
end

function FX.beam(a, b, width, color, dur, transparency)
	local len = (b - a).Magnitude
	if len < 0.05 then
		return nil
	end
	if dur == false or (dur and dur > PERSIST_AFTER) then
		local p = base({
			size = Vector3.new(width, width, len),
			cf = CFrame.lookAt((a + b) / 2, b),
			color = color,
			transparency = transparency or 0.2,
			visKind = "beam",
		})
		if dur then
			lifetime(p, dur)
		end
		return p
	end
	local id = cue("beam", { a = a, b = b, w = width, c = color, d = dur or 0.2 })
	return ghost(id, { Position = (a + b) / 2, Size = Vector3.new(width, width, len) })
end

function FX.cone(origin, dir, length, angle, color, dur)
	local d = Vector3.new(dir.X, 0, dir.Z)
	if d.Magnitude < 1e-3 then
		d = Vector3.new(0, 0, -1)
	end
	local id = cue("cone", { p = origin, dir = d.Unit, l = length, a = angle, c = color, d = dur or 0.3 })
	return ghost(id, { Position = origin })
end

function FX.text(adornee, text, color, dur, size)
	local data = { text = tostring(text), c = color or WHITE, d = dur or 1.5, s = size or 36 }
	if typeof(adornee) == "Vector3" then
		data.p = adornee
	else
		data.a = adornee
	end
	local id = cue("text", data)
	return ghost(id, {})
end

-- tint a model/part for a while (client keeps one pooled Highlight per target, under the 31 cap)
function FX.highlight(model, color, dur, fill, mode)
	if not model then
		return nil
	end
	local id = cue("tint", { a = model, c = color or WHITE, d = dur or 1, f = fill or 0.65, m = mode })
	return ghost(id, {})
end

function FX.trail(part, color, dur)
	local id = cue("trail", { a = part, c = color or WHITE, d = dur or 0.4 })
	return ghost(id, {})
end

function FX.sound(where, name, volume)
	local data = { n = name, v = volume or 0.4 }
	if typeof(where) == "Vector3" then
		data.p = where
	else
		data.a = where
	end
	cue("sfx", data)
end

-- Gameplay moments -----------------------------------------------------------------------------------
-- impact on a fighter: cat = "hit" | "guard" | "perfect" | "shield" | "evade" | "heal" | "true"
function FX.hit(target, amount, cat, src, info)
	if not target or not target.root then
		return
	end
	local real = src and (src.owner or src)
	cue("hit", {
		t = target.model,
		p = target.root.Position,
		from = info and info.fromPos or (src and src.root and src.root.Position) or nil,
		amt = math.floor((amount or 0) + 0.5),
		cat = cat or "hit",
		k = src and src.kitName or (real and real.kitName) or nil,
		o = real and real.id or nil,
		kind = info and info.kind or nil,
		ult = info and info.isUlt or nil,
		proj = info and info.projectile and true or nil,
		melee = info and info.melee and true or nil,
	})
end

function FX.pop(pos, text, color, kind)
	cue("pop", { p = pos, text = text, c = color, kind = kind })
end

-- caster moments: windup start, release (hands), ultimate stages
function FX.castStart(f, slot, def, c)
	cue("cast", {
		a = f.model,
		k = f.kitName,
		o = f.id,
		slot = slot,
		w = def.windup or 0,
		ult = slot == 5 or nil,
		unstable = c and c.unstable or nil,
		p60 = c and c.p60 or nil,
		name = def.name,
	})
end

function FX.release(f, slot, c)
	cue("release", { a = f.model, k = f.kitName, o = f.id, slot = slot, ult = slot == 5 or nil, unstable = c and c.unstable or nil })
end

function FX.event(kind, data)
	return cue(kind, data)
end

return FX
