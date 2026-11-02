-- World objects / constructs with durability, reinforcement layers, lifetimes and owner caps.
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local S = require(script.Parent.S)

local Objects = {}
S.Objects = Objects

local Config = S.Config
local list = {} -- [id] = obj
local byPart = {}
local nextId = 0

Objects.list = list

--[[ opts:
	owner (fighter or nil = neutral), name, cf, size (studs), shape ("Block"|"Ball"|"Cylinder"), hp, duration,
	solid (CanCollide, default true), blocks (blocks projectiles / LOS, default = solid), color, material,
	transparency, element, tags (set), onDestroy(obj, src), onExpire(obj), onDamage(obj, amt, src),
	allyPass, noCap (exempt from 8-object cap), isUlt, prop (non-hittable decoration), anchored
]]
function Objects.create(opts)
	nextId += 1
	local p = Instance.new(opts.class or "Part")
	p.Anchored = true
	p.CanCollide = opts.solid ~= false
	local blocks = opts.blocks
	if blocks == nil then
		blocks = opts.solid ~= false
	end
	p.CanQuery = blocks or opts.queryable == true
	p.CanTouch = false
	p.Size = opts.size or Vector3.new(4, 4, 4)
	p.CFrame = opts.cf or CFrame.new()
	p.Color = opts.color or Color3.fromRGB(200, 200, 200)
	p.Material = opts.material or Enum.Material.SmoothPlastic
	p.Transparency = opts.transparency or 0
	if p:IsA("TrussPart") then
		-- trusses are climbable; nothing else to configure
	elseif opts.shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif opts.shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Name = opts.name or "Construct"
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts.allyPass then
		p.CanCollide = false
	end
	local hp = opts.hp or Config.OBJECT_DURABILITY
	local obj = {
		id = nextId,
		owner = opts.owner,
		part = p,
		hp = hp,
		maxHp = hp,
		layers = {},
		element = opts.element or (opts.owner and opts.owner.kitName),
		tags = opts.tags or {},
		name = opts.name or "Construct",
		alive = true,
		blocks = blocks,
		solid = opts.solid ~= false,
		created = S.now(),
		expires = opts.duration and (S.now() + opts.duration) or nil,
		onDestroy = opts.onDestroy,
		onExpire = opts.onExpire,
		onDamage = opts.onDamage,
		allyPass = opts.allyPass,
		isUlt = opts.isUlt,
		data = opts.data or {},
		upgrades = {},
		invulnerable = opts.invulnerable,
	}
	p.Parent = (blocks and not opts.prop) and S.folders.Constructs or S.folders.Props
	list[obj.id] = obj
	byPart[p] = obj
	p:SetAttribute("Durability", math.floor(hp))
	p:SetAttribute("Owner", opts.owner and opts.owner.name or "neutral")
	-- durability label for readability
	if not opts.noLabel then
		local bb = Instance.new("BillboardGui")
		bb.Name = "HP"
		bb.Size = UDim2.fromOffset(70, 16)
		bb.StudsOffset = Vector3.new(0, p.Size.Y / 2 + 0.8, 0)
		bb.MaxDistance = 60
		bb.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.TextColor3 = Color3.new(1, 1, 1)
		t.TextStrokeTransparency = 0.3
		t.Text = tostring(math.floor(hp))
		t.Parent = bb
		bb.Parent = p
		obj.label = t
	end
	-- owner cap
	if opts.owner and not opts.noCap and not opts.isUlt then
		local owned = opts.owner.objects
		table.insert(owned, obj)
		local count = 0
		for _, o in ipairs(owned) do
			if o.alive then
				count += 1
			end
		end
		if count > Config.MAX_OBJECTS_PER_CASTER then
			for _, o in ipairs(owned) do
				if o.alive and o ~= obj then
					Objects.remove(o, "replaced")
					break
				end
			end
		end
	elseif opts.owner then
		table.insert(opts.owner.objects, obj)
	end
	return obj
end

local function refreshLabel(obj)
	if obj.label then
		local bonus = 0
		for _, l in ipairs(obj.layers) do
			bonus += l.amount
		end
		obj.label.Text = tostring(math.floor(obj.hp + 0.5)) .. (bonus > 0 and (" +" .. math.floor(bonus)) or "")
	end
	if obj.part then
		obj.part:SetAttribute("Durability", math.floor(obj.hp))
	end
end

function Objects.fromPart(part)
	return part and byPart[part]
end

function Objects.damage(obj, amount, src, opts)
	if not obj or not obj.alive or amount <= 0 or obj.invulnerable then
		return 0
	end
	opts = opts or {}
	local info = { amount = amount, src = src, opts = opts }
	if obj.beforeDamage then
		obj.beforeDamage(obj, info)
		if info.cancel then
			return 0
		end
	end
	amount = info.amount
	-- reinforcement layers absorb first
	while amount > 0 and #obj.layers > 0 do
		local l = obj.layers[#obj.layers]
		if l.amount > amount then
			l.amount -= amount
			amount = 0
		else
			amount -= l.amount
			table.remove(obj.layers)
		end
	end
	obj.hp -= amount
	if obj.onDamage then
		S.safe(obj.onDamage, obj, amount, src)
	end
	refreshLabel(obj)
	if obj.part and amount > 0 then
		S.Combat.pop(obj.part.Position, tostring(math.floor(amount + 0.5)), Color3.fromRGB(200, 200, 200), "object")
	end
	if obj.hp <= 0 then
		Objects.destroy(obj, src)
	end
	return amount
end

function Objects.reinforce(obj, amount, src)
	if not obj.alive then
		return false
	end
	local total = 0
	for _, l in ipairs(obj.layers) do
		total += l.amount
	end
	if #obj.layers >= Config.MAX_REINFORCE_LAYERS then
		return false
	end
	amount = math.min(amount, Config.MAX_REINFORCE - total)
	if amount <= 0 then
		return false
	end
	table.insert(obj.layers, { amount = amount, src = src })
	refreshLabel(obj)
	return true
end

function Objects.stripLayer(obj)
	if obj.alive and #obj.layers > 0 then
		table.remove(obj.layers)
		refreshLabel(obj)
		return true
	end
	return false
end

function Objects.heal(obj, amount)
	if obj.data.noRepairUntil and obj.data.noRepairUntil > S.now() then
		return
	end
	if obj.alive then
		obj.hp = math.min(obj.maxHp, obj.hp + amount)
		refreshLabel(obj)
	end
end

function Objects.remove(obj, reason)
	if not obj.alive then
		return
	end
	obj.alive = false
	list[obj.id] = nil
	if obj.part then
		byPart[obj.part] = nil
		local p = obj.part
		p.CanCollide = false
		p.CanQuery = false
		TweenService:Create(p, TweenInfo.new(0.25), { Transparency = 1 }):Play()
		Debris:AddItem(p, 0.3)
	end
	if obj.cleanup then
		S.safe(obj.cleanup, obj, reason)
	end
end

function Objects.destroy(obj, src)
	if not obj.alive then
		return
	end
	local pos = obj.part and obj.part.Position
	Objects.remove(obj, "destroyed")
	if pos then
		S.FX.burst(pos, math.max(2, obj.part.Size.Magnitude / 3), obj.part.Color, 0.3)
	end
	if obj.onDestroy then
		S.safe(obj.onDestroy, obj, src)
	end
	S.emit("objectDestroyed", obj, src)
end

function Objects.inRadius(pos, r, filter)
	local out = {}
	for _, o in pairs(list) do
		if o.alive and o.part then
			local p = o.part
			local half = p.Size.Magnitude / 2
			if (p.Position - pos).Magnitude <= r + half * 0.6 and (filter == nil or filter(o)) then
				table.insert(out, o)
			end
		end
	end
	return out
end

function Objects.owned(f, name)
	local out = {}
	for _, o in ipairs(f.objects) do
		if o.alive and (name == nil or o.name == name) then
			table.insert(out, o)
		end
	end
	return out
end

function Objects.removeOwned(f, name)
	for _, o in ipairs(f.objects) do
		if o.alive and (name == nil or o.name == name) then
			Objects.remove(o, "owner")
		end
	end
	if name == nil then
		table.clear(f.objects)
	end
end

function Objects.update(now)
	for _, o in pairs(list) do
		if o.alive then
			if o.expires and now >= o.expires then
				Objects.remove(o, "expired")
				if o.onExpire then
					S.safe(o.onExpire, o)
				end
			elseif o.allyPass and o.owner and o.part then
				-- ally-pass barriers physically stop enemies by pushing them back out
				local part = o.part
				for _, f in pairs(S.fighters) do
					if S.alive(f) and S.isEnemy(o.owner, f) and not f.isSummon then
						local lp = part.CFrame:PointToObjectSpace(f.root.Position)
						local half = part.Size / 2 + Vector3.new(1.2, 2, 1.2)
						if math.abs(lp.X) < half.X and math.abs(lp.Y) < half.Y and math.abs(lp.Z) < half.Z then
							local out = part.CFrame:VectorToWorldSpace(Vector3.new(0, 0, lp.Z >= 0 and 1 or -1))
							S.Fighter.teleport(f, f.root.Position + out * (half.Z - math.abs(lp.Z) + 0.5))
						end
					end
				end
			end
		end
	end
end

return Objects
