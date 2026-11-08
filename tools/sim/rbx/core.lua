-- Core of the Roblox emulator: typeof, scheduler (task library), signals, Instance system.
local R = ...

R.errors = {}
R.warnings = {}
R.output = {}
R.maxLog = 4000

local function log(list, msg)
	if #list < R.maxLog then
		list[#list + 1] = { t = R.now or 0, msg = msg }
	end
end
R.log = log

---------------------------------------------------------------- typeof
local DATA = setmetatable({}, { __mode = "k" })
R.DATA = DATA
function R.typeof(v)
	if DATA[v] then
		return "Instance"
	end
	local mt = getmetatable(v)
	if mt and R.TYPE[mt] then
		return R.TYPE[mt]
	end
	return type(v)
end
function R.isInstance(v)
	return DATA[v] ~= nil
end

---------------------------------------------------------------- scheduler
R.now = 0
local Sched = { timers = {}, deferred = {}, seq = 0 }
R.Sched = Sched
local PEER = setmetatable({}, { __mode = "k" }) -- coroutine -> "server" | "client"
local NAME = setmetatable({}, { __mode = "k" }) -- coroutine -> script name (for diagnostics)
local CANCELLED = setmetatable({}, { __mode = "k" })
R.PEER = PEER
R.currentPeer = "server"
R.currentScript = nil

function R.peer()
	local co = coroutine.running()
	return PEER[co] or R.currentPeer
end

local function report(co, err)
	local tb = debug.traceback(co, tostring(err))
	log(R.errors, tb)
end
R.report = report

local function resume(co, ...)
	if CANCELLED[co] or coroutine.status(co) ~= "suspended" then
		return
	end
	local prevPeer = R.currentPeer
	R.currentPeer = PEER[co] or prevPeer
	local ok, err = coroutine.resume(co, ...)
	R.currentPeer = prevPeer
	if not ok then
		report(co, err)
	end
end
R.resume = resume

local function newThread(fn, peer, name)
	local co = coroutine.create(fn)
	PEER[co] = peer or R.peer()
	NAME[co] = name
	return co
end
R.newThread = newThread

local function schedule(co, at, args)
	Sched.seq = Sched.seq + 1
	Sched.timers[#Sched.timers + 1] = { co = co, at = at, seq = Sched.seq, args = args, start = R.now }
end

local task = {}
function task.wait(t)
	t = tonumber(t) or 0
	if t < 1 / 60 then
		t = 1 / 60
	end
	local co, main = coroutine.running()
	if main then
		error("attempt to yield from the main thread", 2)
	end
	schedule(co, R.now + t, nil)
	return coroutine.yield()
end
function task.spawn(f, ...)
	local co
	if type(f) == "thread" then
		co = f
	else
		if type(f) ~= "function" then
			error("invalid argument #1 to 'spawn' (function or thread expected)", 2)
		end
		co = newThread(f)
	end
	resume(co, ...)
	return co
end
function task.defer(f, ...)
	local co = type(f) == "thread" and f or newThread(f)
	Sched.deferred[#Sched.deferred + 1] = { co = co, args = table.pack(...) }
	return co
end
function task.delay(t, f, ...)
	local co = type(f) == "thread" and f or newThread(f)
	schedule(co, R.now + math.max(0, tonumber(t) or 0), table.pack(...))
	return co
end
function task.cancel(co)
	CANCELLED[co] = true
	if coroutine.status(co) == "suspended" then
		coroutine.close(co)
	end
end
function task.synchronize() end
function task.desynchronize() end
R.task = task

-- run due timers (called once per frame)
function Sched.runTimers()
	local due = {}
	local keep = {}
	for _, e in ipairs(Sched.timers) do
		if e.at <= R.now + 1e-9 then
			due[#due + 1] = e
		else
			keep[#keep + 1] = e
		end
	end
	Sched.timers = keep
	table.sort(due, function(a, b)
		if a.at == b.at then
			return a.seq < b.seq
		end
		return a.at < b.at
	end)
	for _, e in ipairs(due) do
		if e.args then
			resume(e.co, table.unpack(e.args, 1, e.args.n))
		else
			resume(e.co, R.now - e.start, R.now)
		end
	end
end
function Sched.runDeferred()
	local guard = 0
	while #Sched.deferred > 0 and guard < 50 do
		guard = guard + 1
		local list = Sched.deferred
		Sched.deferred = {}
		for _, e in ipairs(list) do
			resume(e.co, table.unpack(e.args, 1, e.args.n))
		end
	end
end
function Sched.count()
	return #Sched.timers
end

---------------------------------------------------------------- signals
local ConnMT = {}
R.TYPE[ConnMT] = "RBXScriptConnection"
local ConnM = {}
ConnMT.__index = function(c, k)
	if k == "Connected" then
		return rawget(c, "_on")
	end
	local m = ConnM[k]
	if m then
		return m
	end
	error(tostring(k) .. " is not a valid member of RBXScriptConnection", 2)
end
function ConnM.Disconnect(c)
	if not rawget(c, "_on") then
		return
	end
	rawset(c, "_on", false)
	local sig = rawget(c, "_sig")
	for i, x in ipairs(sig._conns) do
		if x == c then
			table.remove(sig._conns, i)
			break
		end
	end
	R.connCount = R.connCount - 1
end
R.connCount = 0

local SigMT = {}
R.TYPE[SigMT] = "RBXScriptSignal"
local SigM = {}
SigMT.__index = function(_, k)
	local m = SigM[k]
	if m then
		return m
	end
	error(tostring(k) .. " is not a valid member of RBXScriptSignal", 2)
end
function R.newSignal(name)
	return setmetatable({ _conns = {}, _waiters = {}, _name = name }, SigMT)
end
function SigM.Connect(sig, fn)
	if type(fn) ~= "function" then
		error("Attempt to connect failed: Passed value is not a function", 2)
	end
	local c = setmetatable({ _sig = sig, _fn = fn, _on = true, _peer = R.peer() }, ConnMT)
	sig._conns[#sig._conns + 1] = c
	R.connCount = R.connCount + 1
	return c
end
function SigM.Once(sig, fn)
	local c
	c = SigM.Connect(sig, function(...)
		c:Disconnect()
		fn(...)
	end)
	return c
end
SigM.ConnectParallel = SigM.Connect
function SigM.Wait(sig)
	local co, main = coroutine.running()
	if main then
		error("attempt to yield from the main thread", 2)
	end
	sig._waiters[#sig._waiters + 1] = co
	return coroutine.yield()
end
function R.fire(sig, ...)
	if #sig._conns == 0 and #sig._waiters == 0 then
		return
	end
	local list = table.pack(table.unpack(sig._conns))
	for i = 1, list.n do
		local c = list[i]
		if rawget(c, "_on") then
			local co = newThread(c._fn, c._peer)
			resume(co, ...)
		end
	end
	if #sig._waiters > 0 then
		local w = sig._waiters
		sig._waiters = {}
		for _, co in ipairs(w) do
			resume(co, ...)
		end
	end
end
function R.disconnectAll(sig)
	for _, c in ipairs(sig._conns) do
		rawset(c, "_on", false)
		R.connCount = R.connCount - 1
	end
	sig._conns = {}
end

---------------------------------------------------------------- Instance system
local NIL = {}
R.NIL = NIL
local CLASSES = {}
R.CLASSES = CLASSES

-- property spec helper: P(type, default, flags)
function R.P(t, default, flags)
	local s = { t = t, default = default }
	if flags then
		for k, v in pairs(flags) do
			s[k] = v
		end
	end
	return s
end

function R.defineClass(name, super, def)
	local cls = { name = name, super = super and CLASSES[super], P = {}, M = {}, E = {}, creatable = def.creatable ~= false, service = def.service }
	if super and not CLASSES[super] then
		error("unknown superclass " .. super)
	end
	local s = cls.super
	if s then
		for k, v in pairs(s.P) do
			cls.P[k] = v
		end
		for k, v in pairs(s.M) do
			cls.M[k] = v
		end
		for k, v in pairs(s.E) do
			cls.E[k] = v
		end
		cls.init = s.init
	end
	for k, v in pairs(def.props or {}) do
		cls.P[k] = v
	end
	for k, v in pairs(def.methods or {}) do
		cls.M[k] = v
	end
	for _, e in ipairs(def.events or {}) do
		cls.E[e] = true
	end
	if def.init then
		local parentInit = cls.init
		local own = def.init
		cls.init = function(obj, d)
			if parentInit then
				parentInit(obj, d)
			end
			own(obj, d)
		end
	end
	CLASSES[name] = cls
	return cls
end

local function isA(cls, name)
	while cls do
		if cls.name == name then
			return true
		end
		cls = cls.super
	end
	return false
end
R.classIsA = isA

local InstMT = {}
R.InstMT = InstMT
R.TYPE[InstMT] = "Instance"

local function fullName(obj)
	local parts = {}
	local o = obj
	local guard = 0
	while o and guard < 50 do
		local d = DATA[o]
		if not d or d.cls.name == "DataModel" then
			break
		end
		table.insert(parts, 1, d.props.Name)
		o = d.parent
		guard = guard + 1
	end
	return table.concat(parts, ".")
end
R.fullName = fullName

local function getSignal(d, key)
	local s = d.signals[key]
	if not s then
		s = R.newSignal(key)
		d.signals[key] = s
	end
	return s
end
R.getSignal = getSignal

InstMT.__index = function(obj, key)
	local d = DATA[obj]
	local cls = d.cls
	local spec = cls.P[key]
	if spec then
		if spec.get then
			return spec.get(obj, d)
		end
		local v = d.props[key]
		if v == NIL then
			return nil
		end
		return v
	end
	local m = cls.M[key]
	if m then
		return m
	end
	if cls.E[key] then
		return getSignal(d, key)
	end
	if type(key) == "string" then
		for _, c in ipairs(d.children) do
			if DATA[c].props.Name == key then
				return c
			end
		end
	end
	error(tostring(key) .. " is not a valid member of " .. cls.name .. ' "' .. fullName(obj) .. '"', 2)
end

local function typeOk(spec, v)
	local t = spec.t
	if t == "any" then
		return true, v
	end
	if v == nil then
		if t == "Instance" or spec.nullable then
			return true, v
		end
		return false
	end
	if t == "number" then
		if type(v) == "number" then
			if v ~= v and not spec.nan then
				R.log(R.warnings, "NaN assigned to number property")
			end
			return true, v
		end
		if type(v) == "string" and tonumber(v) then
			return true, tonumber(v)
		end
		return false
	elseif t == "string" then
		if type(v) == "string" then
			return true, v
		elseif type(v) == "number" then
			return true, tostring(v)
		end
		return false
	elseif t == "boolean" then
		return type(v) == "boolean", v
	elseif t == "Instance" then
		if not DATA[v] then
			return false
		end
		if spec.class and not isA(DATA[v].cls, spec.class) then
			return false
		end
		return true, v
	elseif t:sub(1, 5) == "Enum:" then
		local en = t:sub(6)
		if R.isEnumItem(v) then
			return v.EnumType._name == en, v
		elseif type(v) == "string" then
			local item = R.Enum[en]:FromName(v)
			return item ~= nil, item
		elseif type(v) == "number" then
			local item = R.Enum[en]:FromValue(v)
			return item ~= nil, item
		end
		return false
	else
		return R.typeof(v) == t, v
	end
end
R.typeOk = typeOk

InstMT.__newindex = function(obj, key, value)
	local d = DATA[obj]
	local cls = d.cls
	local spec = cls.P[key]
	if not spec then
		error(tostring(key) .. " is not a valid member of " .. cls.name .. ' "' .. fullName(obj) .. '"', 2)
	end
	if spec.readonly then
		error("Unable to assign property " .. key .. ". Property is read only", 2)
	end
	local ok, conv = typeOk(spec, value)
	if not ok then
		error("Unable to assign property " .. key .. ". " .. spec.t .. " expected, got " .. R.typeof(value), 2)
	end
	value = conv
	if spec.set then
		if spec.set(obj, d, value) == false then
			return
		end
	else
		local old = d.props[key]
		if old == NIL then
			old = nil
		end
		if old == value then
			return
		end
		d.props[key] = value == nil and NIL or value
	end
	R.changed(obj, d, key)
end

function R.changed(obj, d, key)
	local s = d.propSignals and d.propSignals[key]
	if s then
		R.fire(s)
	end
	local c = d.signals.Changed
	if c then
		R.fire(c, key)
	end
end

InstMT.__tostring = function(obj)
	return DATA[obj].props.Name
end

R.instanceCount = 0
R.createdCount = 0
function R.new(className, parent)
	local cls = CLASSES[className]
	if not cls then
		error('Unable to create an Instance of type "' .. tostring(className) .. '"', 2)
	end
	local obj = setmetatable({}, InstMT)
	local d = { cls = cls, props = {}, children = {}, attrs = {}, tags = {}, signals = {}, parent = nil, peer = R.peer() }
	for k, spec in pairs(cls.P) do
		if not spec.get then
			local v = spec.default
			if type(v) == "function" then
				v = v()
			end
			d.props[k] = v == nil and NIL or v
		end
	end
	d.props.Name = cls.name
	DATA[obj] = d
	R.instanceCount = R.instanceCount + 1
	R.createdCount = R.createdCount + 1
	if cls.init then
		cls.init(obj, d)
	end
	if parent ~= nil then
		obj.Parent = parent
	end
	return obj
end
function R.newInstance(className, parent)
	local cls = CLASSES[className]
	if not cls or not cls.creatable then
		error('Unable to create an Instance of type "' .. tostring(className) .. '"', 2)
	end
	return R.new(className, parent)
end

-- hierarchy -----------------------------------------------------------------
R.hooks = { added = {}, removing = {} } -- engine hooks (part registry, tags...)

local function descendants(obj, out)
	for _, c in ipairs(DATA[obj].children) do
		out[#out + 1] = c
		descendants(c, out)
	end
	return out
end
R.descendants = descendants

local function inDataModel(obj)
	local o = obj
	while o do
		local d = DATA[o]
		if d.cls.name == "DataModel" then
			return true
		end
		o = d.parent
	end
	return false
end
R.inDataModel = inDataModel

local function setParent(obj, d, newParent)
	if d.locked then
		error("The Parent property of " .. d.props.Name .. " is locked, current parent: NULL, new parent " .. tostring(newParent and DATA[newParent].props.Name), 3)
	end
	local old = d.parent
	if old == newParent then
		return false
	end
	if newParent then
		local o = newParent
		while o do
			if o == obj then
				error("Attempt to set " .. fullName(obj) .. " as its own parent", 3)
			end
			o = DATA[o].parent
		end
	end
	local wasIn = old and inDataModel(old)
	if old then
		local od = DATA[old]
		-- DescendantRemoving fires on ancestors before removal
		local list = { obj }
		descendants(obj, list)
		local a = old
		while a do
			local ad = DATA[a]
			if ad.signals.DescendantRemoving then
				for _, x in ipairs(list) do
					R.fire(ad.signals.DescendantRemoving, x)
				end
			end
			a = ad.parent
		end
		if wasIn then
			for _, x in ipairs(list) do
				for _, h in ipairs(R.hooks.removing) do
					h(x)
				end
			end
		end
		for i, c in ipairs(od.children) do
			if c == obj then
				table.remove(od.children, i)
				break
			end
		end
		d.parent = nil
		if od.signals.ChildRemoved then
			R.fire(od.signals.ChildRemoved, obj)
		end
	end
	d.parent = newParent
	if newParent then
		local nd = DATA[newParent]
		nd.children[#nd.children + 1] = obj
	end
	-- AncestryChanged on self and descendants
	local list = { obj }
	descendants(obj, list)
	for _, x in ipairs(list) do
		local xd = DATA[x]
		if xd.signals.AncestryChanged then
			R.fire(xd.signals.AncestryChanged, obj, newParent)
		end
	end
	if newParent then
		local nd = DATA[newParent]
		if nd.signals.ChildAdded then
			R.fire(nd.signals.ChildAdded, obj)
		end
		local a = newParent
		while a do
			local ad = DATA[a]
			if ad.signals.DescendantAdded then
				for _, x in ipairs(list) do
					R.fire(ad.signals.DescendantAdded, x)
				end
			end
			a = ad.parent
		end
		if inDataModel(newParent) then
			for _, x in ipairs(list) do
				for _, h in ipairs(R.hooks.added) do
					h(x)
				end
			end
		end
	end
end
R.setParent = setParent

local function destroy(obj)
	local d = DATA[obj]
	if d.destroyed then
		return
	end
	if d.signals.Destroying then
		R.fire(d.signals.Destroying)
	end
	for _, c in ipairs(table.pack(table.unpack(d.children))) do
		destroy(c)
	end
	if d.parent then
		setParent(obj, d, nil)
	end
	d.locked = true
	d.destroyed = true
	for _, s in pairs(d.signals) do
		R.disconnectAll(s)
	end
	if d.propSignals then
		for _, s in pairs(d.propSignals) do
			R.disconnectAll(s)
		end
	end
	if d.attrSignals then
		for _, s in pairs(d.attrSignals) do
			R.disconnectAll(s)
		end
	end
	if d.onDestroy then
		d.onDestroy(obj, d)
	end
	R.instanceCount = R.instanceCount - 1
end
R.destroy = destroy

-- attribute value validation (Roblox rejects tables, Instances, functions...)
local ATTR_TYPES = {
	string = true, boolean = true, number = true, UDim = true, UDim2 = true, BrickColor = true, Color3 = true,
	Vector2 = true, Vector3 = true, CFrame = true, NumberSequence = true, ColorSequence = true, NumberRange = true,
	Rect = true, Font = true, EnumItem = true,
}

local base = {}
function base.FindFirstChild(obj, name, recursive)
	if type(name) ~= "string" then
		error("Argument 1 missing or nil", 2)
	end
	for _, c in ipairs(DATA[obj].children) do
		if DATA[c].props.Name == name then
			return c
		end
	end
	if recursive then
		for _, c in ipairs(DATA[obj].children) do
			local r = base.FindFirstChild(c, name, true)
			if r then
				return r
			end
		end
	end
	return nil
end
function base.FindFirstChildOfClass(obj, cn)
	for _, c in ipairs(DATA[obj].children) do
		if DATA[c].cls.name == cn then
			return c
		end
	end
	return nil
end
function base.FindFirstChildWhichIsA(obj, cn, recursive)
	for _, c in ipairs(DATA[obj].children) do
		if isA(DATA[c].cls, cn) then
			return c
		end
	end
	if recursive then
		for _, c in ipairs(DATA[obj].children) do
			local r = base.FindFirstChildWhichIsA(c, cn, true)
			if r then
				return r
			end
		end
	end
	return nil
end
function base.FindFirstAncestor(obj, name)
	local o = DATA[obj].parent
	while o do
		if DATA[o].props.Name == name then
			return o
		end
		o = DATA[o].parent
	end
	return nil
end
function base.FindFirstAncestorOfClass(obj, cn)
	local o = DATA[obj].parent
	while o do
		if DATA[o].cls.name == cn then
			return o
		end
		o = DATA[o].parent
	end
	return nil
end
function base.FindFirstAncestorWhichIsA(obj, cn)
	local o = DATA[obj].parent
	while o do
		if isA(DATA[o].cls, cn) then
			return o
		end
		o = DATA[o].parent
	end
	return nil
end
function base.WaitForChild(obj, name, timeout)
	local c = base.FindFirstChild(obj, name)
	if c then
		return c
	end
	local co, main = coroutine.running()
	if main then
		error("WaitForChild from main thread", 2)
	end
	local start = R.now
	local limit = timeout or 5
	while true do
		task.wait(0.03)
		c = base.FindFirstChild(obj, name)
		if c then
			return c
		end
		if R.now - start > limit then
			if not timeout then
				R.log(R.warnings, "Infinite yield possible on '" .. fullName(obj) .. ":WaitForChild(\"" .. name .. "\")'")
				start = R.now + 1e9 -- warn once, keep waiting
			else
				return nil
			end
		end
	end
end
function base.GetChildren(obj)
	local out = {}
	for i, c in ipairs(DATA[obj].children) do
		out[i] = c
	end
	return out
end
function base.GetDescendants(obj)
	return descendants(obj, {})
end
function base.IsA(obj, cn)
	return isA(DATA[obj].cls, cn)
end
function base.IsDescendantOf(obj, other)
	if other == nil then
		return false
	end
	local o = DATA[obj].parent
	while o do
		if o == other then
			return true
		end
		o = DATA[o].parent
	end
	return false
end
function base.IsAncestorOf(obj, other)
	return base.IsDescendantOf(other, obj)
end
function base.Destroy(obj)
	destroy(obj)
end
base.Remove = base.Destroy
function base.ClearAllChildren(obj)
	for _, c in ipairs(table.pack(table.unpack(DATA[obj].children))) do
		destroy(c)
	end
end
function base.GetFullName(obj)
	return fullName(obj)
end
function base.Clone(obj)
	local d = DATA[obj]
	if d.props.Archivable == false then
		return nil
	end
	local copy = R.new(d.cls.name)
	local cd = DATA[copy]
	for k, v in pairs(d.props) do
		if k ~= "Parent" then
			cd.props[k] = v
		end
	end
	for k, v in pairs(d.attrs) do
		cd.attrs[k] = v
	end
	for k in pairs(d.tags) do
		cd.tags[k] = true
	end
	local hc = d.cls
	while hc do
		if hc.cloneHook then
			hc.cloneHook(obj, copy, d, cd)
			break
		end
		hc = hc.super
	end
	for _, c in ipairs(d.children) do
		local cc = base.Clone(c)
		if cc then
			cc.Parent = copy
		end
	end
	if d.cls.afterClone then
		d.cls.afterClone(obj, copy)
	end
	return copy
end
function base.GetAttribute(obj, name)
	return DATA[obj].attrs[name]
end
function base.SetAttribute(obj, name, value)
	if type(name) ~= "string" or #name == 0 or #name > 100 or not name:match("^[%w_]+$") or name:sub(1, 3) == "RBX" then
		error("Invalid attribute name '" .. tostring(name) .. "'", 2)
	end
	if value ~= nil and not ATTR_TYPES[R.typeof(value)] then
		error("Invalid attribute value type for '" .. name .. "': " .. R.typeof(value), 2)
	end
	if type(value) == "number" and value ~= value then
		R.log(R.warnings, "NaN attribute " .. name .. " on " .. fullName(obj))
	end
	local d = DATA[obj]
	if d.attrs[name] == value then
		return
	end
	d.attrs[name] = value
	if d.attrSignals and d.attrSignals[name] then
		R.fire(d.attrSignals[name])
	end
	if d.signals.AttributeChanged then
		R.fire(d.signals.AttributeChanged, name)
	end
end
function base.GetAttributes(obj)
	local out = {}
	for k, v in pairs(DATA[obj].attrs) do
		out[k] = v
	end
	return out
end
function base.GetAttributeChangedSignal(obj, name)
	local d = DATA[obj]
	d.attrSignals = d.attrSignals or {}
	local s = d.attrSignals[name]
	if not s then
		s = R.newSignal("Attr:" .. name)
		d.attrSignals[name] = s
	end
	return s
end
function base.GetPropertyChangedSignal(obj, prop)
	local d = DATA[obj]
	if not d.cls.P[prop] then
		error(tostring(prop) .. " is not a valid property name.", 2)
	end
	d.propSignals = d.propSignals or {}
	local s = d.propSignals[prop]
	if not s then
		s = R.newSignal("Prop:" .. prop)
		d.propSignals[prop] = s
	end
	return s
end
function base.AddTag(obj, tag)
	R.addTag(obj, tag)
end
function base.RemoveTag(obj, tag)
	R.removeTag(obj, tag)
end
function base.HasTag(obj, tag)
	return DATA[obj].tags[tag] == true
end
function base.GetTags(obj)
	local out = {}
	for k in pairs(DATA[obj].tags) do
		out[#out + 1] = k
	end
	return out
end
function base.GetActor()
	return nil
end

R.defineClass("Instance", nil, {
	creatable = false,
	props = {
		Name = R.P("string", "Instance"),
		Archivable = R.P("boolean", true),
		ClassName = { t = "string", readonly = true, get = function(_, d)
			return d.cls.name
		end },
		Parent = { t = "Instance", get = function(_, d)
			return d.parent
		end, set = function(obj, d, v)
			return setParent(obj, d, v)
		end },
	},
	methods = base,
	events = { "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AncestryChanged", "Changed", "AttributeChanged", "Destroying" },
})
