-- Class catalog for the emulator. Each property is typed; unknown members raise errors.
local R = ...
local P, def = R.P, R.defineClass
local DATA = R.DATA
local v3, c3 = R.v3, R.c3

local function N(d, f)
	return P("number", d or 0, f)
end
local function S(d)
	return P("string", d or "")
end
local function B(d)
	return P("boolean", d == true)
end
local function V3(d)
	return P("Vector3", d or v3(0, 0, 0))
end
local function V2(d)
	return P("Vector2", d or R.v2(0, 0))
end
local function CF(d)
	return P("CFrame", d or R.CFrame.identity)
end
local function C3(d)
	return P("Color3", d or c3(1, 1, 1))
end
local function U2(d)
	return P("UDim2", d or R.UDim2.new(0, 0, 0, 0))
end
local function I(cls)
	return P("Instance", nil, { class = cls })
end
local function E(en, item)
	return P("Enum:" .. en, R.Enum[en][item])
end
local function NS(a)
	return P("NumberSequence", R.NumberSequence.new(a or 0))
end
local function CS(c)
	return P("ColorSequence", R.ColorSequence.new(c or c3(1, 1, 1)))
end
local function NR(a, b)
	return P("NumberRange", R.NumberRange.new(a or 0, b))
end
local function ANY(d)
	return P("any", d)
end
local function RO(spec, getter)
	spec.readonly = true
	spec.get = getter
	return spec
end

-- generic containers ---------------------------------------------------------
def("DataModel", "Instance", { creatable = false, props = { PlaceId = N(0), GameId = N(0), JobId = S(""), CreatorId = N(0) }, methods = {
	GetService = function(self, name)
		return R.getService(name)
	end,
	FindService = function(self, name)
		return R.services[name]
	end,
	IsLoaded = function()
		return true
	end,
	BindToClose = function() end,
}, events = { "Loaded" } })
for _, n in ipairs({ "Folder", "Configuration" }) do
	def(n, "Instance", {})
end
def("Model", "Instance", {
	props = { PrimaryPart = I("BasePart"), WorldPivot = CF(), LevelOfDetail = ANY(), ModelStreamingMode = ANY() },
	methods = {}, -- filled by physics module
})
def("Actor", "Model", {})
def("WorldModel", "Model", {})

-- values ----------------------------------------------------------------------
def("ValueBase", "Instance", { creatable = false })
def("StringValue", "ValueBase", { props = { Value = S("") } })
def("IntValue", "ValueBase", { props = { Value = N(0) } })
def("NumberValue", "ValueBase", { props = { Value = N(0) } })
def("BoolValue", "ValueBase", { props = { Value = B(false) } })
def("ObjectValue", "ValueBase", { props = { Value = I() } })
def("Vector3Value", "ValueBase", { props = { Value = V3() } })
def("CFrameValue", "ValueBase", { props = { Value = CF() } })
def("Color3Value", "ValueBase", { props = { Value = C3() } })

-- scripts ---------------------------------------------------------------------
def("LuaSourceContainer", "Instance", { creatable = false, props = { Source = S(""), Disabled = B(false), Enabled = B(true), RunContext = ANY() } })
def("Script", "LuaSourceContainer", {})
def("LocalScript", "Script", {})
def("ModuleScript", "LuaSourceContainer", {})

-- remotes / bindables ---------------------------------------------------------
def("RemoteEvent", "Instance", { events = { "OnServerEvent", "OnClientEvent" }, methods = {} })
def("UnreliableRemoteEvent", "RemoteEvent", {})
def("RemoteFunction", "Instance", { props = { OnServerInvoke = ANY(), OnClientInvoke = ANY() }, methods = {} })
def("BindableEvent", "Instance", { events = { "Event" }, methods = {
	Fire = function(self, ...)
		R.fire(R.getSignal(DATA[self], "Event"), ...)
	end,
} })
def("BindableFunction", "Instance", { props = { OnInvoke = ANY() }, methods = {
	Invoke = function(self, ...)
		local f = self.OnInvoke
		return f(...)
	end,
} })

-- teams / players -------------------------------------------------------------
def("Team", "Instance", { props = { TeamColor = P("BrickColor", R.BrickColor.new("Medium stone grey")), AutoAssignable = B(true) }, methods = {
	GetPlayers = function(self)
		local out = {}
		for _, p in ipairs(R.getService("Players"):GetPlayers()) do
			if p.Team == self then
				out[#out + 1] = p
			end
		end
		return out
	end,
} })
def("Player", "Instance", {
	props = {
		DisplayName = S("Player"), UserId = N(1), Character = I("Model"), Team = I("Team"), Neutral = B(true),
		DevEnableMouseLock = B(true), CameraMaxZoomDistance = N(400), CameraMinZoomDistance = N(0.5),
		AccountAge = N(100), MembershipType = ANY(), CameraMode = E("CameraMode", "Classic"),
		AutoJumpEnabled = B(true), HealthDisplayDistance = N(100), NameDisplayDistance = N(100),
		ReplicationFocus = I(), DevComputerMovementMode = ANY(), DevTouchMovementMode = ANY(),
	},
	events = { "CharacterAdded", "CharacterRemoving", "CharacterAppearanceLoaded", "Chatted", "Idled" },
	methods = {},
})
def("PlayerGui", "Instance", { creatable = false, props = { ScreenOrientation = ANY(), SelectionImageObject = I() }, methods = {
	GetTopbarTransparency = function()
		return 0.5
	end,
} })
def("PlayerScripts", "Instance", { creatable = false })
def("Backpack", "Instance", {})
def("StarterGear", "Instance", {})

-- humanoid & animation --------------------------------------------------------
def("HumanoidDescription", "Instance", { props = {
	HeadColor = C3(c3(0.9, 0.75, 0.6)), TorsoColor = C3(c3(0.2, 0.4, 0.8)), LeftArmColor = C3(c3(0.9, 0.75, 0.6)),
	RightArmColor = C3(c3(0.9, 0.75, 0.6)), LeftLegColor = C3(c3(0.2, 0.2, 0.3)), RightLegColor = C3(c3(0.2, 0.2, 0.3)),
	BodyTypeScale = N(0.3), DepthScale = N(1), HeadScale = N(1), HeightScale = N(1), ProportionScale = N(1), WidthScale = N(1),
	Shirt = N(0), Pants = N(0), GraphicTShirt = N(0), Face = N(0), Head = N(0), Torso = N(0), LeftArm = N(0), RightArm = N(0),
	LeftLeg = N(0), RightLeg = N(0), HatAccessory = S(""), HairAccessory = S(""), FaceAccessory = S(""), NeckAccessory = S(""),
	ShouldersAccessory = S(""), FrontAccessory = S(""), BackAccessory = S(""), WaistAccessory = S(""),
	IdleAnimation = N(0), WalkAnimation = N(0), RunAnimation = N(0), JumpAnimation = N(0), FallAnimation = N(0),
	ClimbAnimation = N(0), SwimAnimation = N(0), MoodAnimation = N(0),
} })
def("BodyColors", "Instance", { props = {
	HeadColor3 = C3(), TorsoColor3 = C3(), LeftArmColor3 = C3(), RightArmColor3 = C3(), LeftLegColor3 = C3(), RightLegColor3 = C3(),
} })
def("Animator", "Instance", { methods = {} })
def("Animation", "Instance", { props = { AnimationId = S("") } })
def("Humanoid", "Instance", {
	props = {
		Health = { t = "number", default = 100 }, MaxHealth = N(100), WalkSpeed = N(16), JumpPower = N(50), JumpHeight = N(7.2),
		UseJumpPower = B(true), HipHeight = N(2), AutoRotate = B(true), AutoJumpEnabled = B(true), Jump = B(false),
		Sit = B(false), PlatformStand = B(false), CameraOffset = V3(), RigType = E("HumanoidRigType", "R15"),
		HealthDisplayType = E("HumanoidHealthDisplayType", "DisplayWhenDamaged"),
		DisplayDistanceType = E("HumanoidDisplayDistanceType", "Viewer"), DisplayName = S(""),
		BreakJointsOnDeath = B(true), RequiresNeck = B(true), MaxSlopeAngle = N(89), NameOcclusion = ANY(),
		HealthDisplayDistance = N(100), NameDisplayDistance = N(100), EvaluateStateMachine = B(true),
		WalkToPoint = V3(), WalkToPart = I("BasePart"), TargetPoint = V3(),
		MoveDirection = RO(P("Vector3"), function(_, d)
			return d.moveDir or v3(0, 0, 0)
		end),
		FloorMaterial = RO(P("Enum:Material"), function(_, d)
			return d.floorMaterial or R.Enum.Material.Air
		end),
		RootPart = RO(P("Instance"), function(obj)
			local m = obj.Parent
			return m and m:FindFirstChild("HumanoidRootPart")
		end),
		SeatPart = RO(P("Instance"), function()
			return nil
		end),
	},
	events = { "Died", "Running", "Jumping", "FreeFalling", "StateChanged", "MoveToFinished", "HealthChanged", "Seated", "Touched", "ApplyDescriptionFinished", "AnimationPlayed" },
	methods = {}, -- physics module
})
CLASSES = R.CLASSES
R.CLASSES.Humanoid.P.Health.set = function(obj, d, v)
	local max = d.props.MaxHealth
	if v > max then
		v = max
	end
	if v < 0 then
		v = 0
	end
	if d.props.Health == v then
		return false
	end
	d.props.Health = v
	R.fire(R.getSignal(d, "HealthChanged"), v)
	if v <= 0 and not d.dead then
		d.dead = true
		d.state = R.Enum.HumanoidStateType.Dead
		R.fire(R.getSignal(d, "Died"))
		R.fire(R.getSignal(d, "StateChanged"), R.Enum.HumanoidStateType.Running, R.Enum.HumanoidStateType.Dead)
	end
end

-- joints & constraints ----------------------------------------------------------
def("JointInstance", "Instance", { creatable = false, props = { Part0 = I("BasePart"), Part1 = I("BasePart"), C0 = CF(), C1 = CF(), Enabled = B(true), Active = RO(P("boolean"), function()
	return true
end) } })
def("Motor6D", "JointInstance", { props = { Transform = CF(), MaxVelocity = N(0.1), DesiredAngle = N(0), CurrentAngle = N(0) } })
def("Motor", "JointInstance", { props = { MaxVelocity = N(0.1), DesiredAngle = N(0), CurrentAngle = N(0) } })
def("Weld", "JointInstance", {})
def("ManualWeld", "JointInstance", {})
def("Snap", "JointInstance", {})
def("WeldConstraint", "Instance", { props = { Part0 = I("BasePart"), Part1 = I("BasePart"), Enabled = B(true), Active = RO(P("boolean"), function()
	return true
end) } })
def("NoCollisionConstraint", "Instance", { props = { Part0 = I("BasePart"), Part1 = I("BasePart"), Enabled = B(true) } })
def("Attachment", "Instance", {
	props = {
		CFrame = CF(), Visible = B(false),
		Position = { t = "Vector3", get = function(_, d)
			return d.props.CFrame.Position
		end, set = function(obj, d, v)
			d.props.CFrame = R.CFrame.new(v) * d.props.CFrame.Rotation
		end },
		Orientation = { t = "Vector3", get = function(_, d)
			local x, y, z = d.props.CFrame:ToOrientation()
			return v3(math.deg(x), math.deg(y), math.deg(z))
		end, set = function(obj, d, v)
			d.props.CFrame = R.CFrame.new(d.props.CFrame.Position) * R.CFrame.fromOrientation(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
		end },
		Axis = { t = "Vector3", get = function(_, d)
			return d.props.CFrame.RightVector
		end, set = function() end },
		SecondaryAxis = { t = "Vector3", get = function(_, d)
			return d.props.CFrame.UpVector
		end, set = function() end },
		WorldCFrame = { t = "CFrame", get = function(obj, d)
			local p = d.parent
			if p and DATA[p] and DATA[p].cls.P.Size then
				return p.CFrame * d.props.CFrame
			end
			return d.props.CFrame
		end, set = function(obj, d, v)
			local p = d.parent
			if p and DATA[p] and DATA[p].cls.P.Size then
				d.props.CFrame = p.CFrame:Inverse() * v
			else
				d.props.CFrame = v
			end
		end },
		WorldPosition = { t = "Vector3", get = function(obj)
			return obj.WorldCFrame.Position
		end, set = function(obj, d, v)
			local p = d.parent
			if p and DATA[p] and DATA[p].cls.P.Size then
				d.props.CFrame = R.CFrame.new(p.CFrame:PointToObjectSpace(v)) * d.props.CFrame.Rotation
			else
				d.props.CFrame = R.CFrame.new(v)
			end
		end },
		WorldAxis = RO(P("Vector3"), function(obj)
			return obj.WorldCFrame.RightVector
		end),
		WorldOrientation = RO(P("Vector3"), function(obj)
			return v3(0, 0, 0)
		end),
	},
})
def("Bone", "Attachment", { props = { Transform = CF() } })
def("Constraint", "Instance", { creatable = false, props = { Attachment0 = I("Attachment"), Attachment1 = I("Attachment"), Enabled = B(true), Visible = B(false), Color = P("BrickColor", R.BrickColor.new("Bright blue")) } })
def("LinearVelocity", "Constraint", { props = {
	VectorVelocity = V3(), LineVelocity = N(0), LineDirection = V3(v3(1, 0, 0)), PlaneVelocity = V2(), PrimaryTangentAxis = V3(v3(1, 0, 0)), SecondaryTangentAxis = V3(v3(0, 1, 0)),
	MaxForce = N(1000), MaxAxesForce = V3(v3(1000, 1000, 1000)), MaxPlanarAxesForce = V2(), ForceLimitsEnabled = B(true), ForceLimitMode = E("ForceLimitMode", "Magnitude"),
	RelativeTo = E("ActuatorRelativeTo", "World"), VelocityConstraintMode = E("VelocityConstraintMode", "Vector"),
} })
def("AlignOrientation", "Constraint", { props = { CFrame = CF(), Mode = ANY(), RigidityEnabled = B(false), MaxTorque = N(10000), Responsiveness = N(10), MaxAngularVelocity = N(1e9), PrimaryAxisOnly = B(false), AlignType = ANY() } })
def("AlignPosition", "Constraint", { props = { Position = V3(), Mode = ANY(), RigidityEnabled = B(false), MaxForce = N(10000), Responsiveness = N(10), MaxVelocity = N(1e9), ApplyAtCenterOfMass = B(false) } })
def("VectorForce", "Constraint", { props = { Force = V3(), RelativeTo = E("ActuatorRelativeTo", "Attachment0"), ApplyAtCenterOfMass = B(false) } })
def("RopeConstraint", "Constraint", { props = { Length = N(5), Thickness = N(0.1), Restitution = N(0), WinchEnabled = B(false) } })
def("BodyMover", "Instance", { creatable = false })
def("BodyVelocity", "BodyMover", { props = { Velocity = V3(), MaxForce = V3(v3(4000, 4000, 4000)), P = N(1250) } })
def("BodyPosition", "BodyMover", { props = { Position = V3(), MaxForce = V3(v3(4000, 4000, 4000)), P = N(10000), D = N(1250) } })
def("BodyGyro", "BodyMover", { props = { CFrame = CF(), MaxTorque = V3(v3(400000, 0, 400000)), P = N(3000), D = N(500) } })

-- parts ---------------------------------------------------------------------------
local function partProps(extra)
	local t = {
		Anchored = B(false), CanCollide = B(true), CanQuery = B(true), CanTouch = B(true), CastShadow = B(true), Locked = B(false), Massless = B(false),
		Material = E("Material", "Plastic"), MaterialVariant = S(""), Transparency = N(0), Reflectance = N(0), LocalTransparencyModifier = N(0),
		Color = C3(c3(0.64, 0.64, 0.64)), CollisionGroup = S("Default"), CollisionGroupId = N(0), RootPriority = N(0),
		TopSurface = E("SurfaceType", "Smooth"), BottomSurface = E("SurfaceType", "Smooth"), LeftSurface = E("SurfaceType", "Smooth"),
		RightSurface = E("SurfaceType", "Smooth"), FrontSurface = E("SurfaceType", "Smooth"), BackSurface = E("SurfaceType", "Smooth"),
		CustomPhysicalProperties = P("PhysicalProperties", nil, { nullable = true }), EnableFluidForces = B(true),
		AssemblyLinearVelocity = V3(), AssemblyAngularVelocity = V3(),
		Velocity = { t = "Vector3", get = function(obj)
			return obj.AssemblyLinearVelocity
		end, set = function(obj, d, v)
			d.props.AssemblyLinearVelocity = v
		end },
		RotVelocity = { t = "Vector3", get = function()
			return v3(0, 0, 0)
		end, set = function() end },
		Mass = RO(P("number"), function(obj, d)
			local s = d.props.Size
			return s.X * s.Y * s.Z * 0.7
		end),
		AssemblyMass = RO(P("number"), function(obj, d)
			local s = d.props.Size
			return s.X * s.Y * s.Z * 0.7
		end),
		AssemblyRootPart = RO(P("Instance"), function(obj)
			return R.assemblyRoot and R.assemblyRoot(obj) or obj
		end),
		ResizeIncrement = RO(P("number"), function()
			return 1
		end),
		ExtentsSize = RO(P("Vector3"), function(obj, d)
			return d.props.Size
		end),
		BrickColor = { t = "BrickColor", get = function(obj, d)
			return R.BrickColor.new("Medium stone grey")
		end, set = function(obj, d, v)
			d.props.Color = v.Color
		end },
		CFrame = { t = "CFrame", get = function(_, d)
			return d.cf
		end, set = function(obj, d, v)
			if v[1] ~= v[1] or v[4] ~= v[4] then
				R.log(R.warnings, "NaN CFrame assigned to " .. R.fullName(obj))
				return false
			end
			d.cf = v
			R.partMoved(obj, d)
		end },
		Position = { t = "Vector3", get = function(_, d)
			local c = d.cf
			return v3(c[1], c[2], c[3])
		end, set = function(obj, d, v)
			if v.X ~= v.X then
				R.log(R.warnings, "NaN Position assigned to " .. R.fullName(obj))
				return false
			end
			d.cf = d.cf.Rotation + v
			R.partMoved(obj, d)
		end },
		Orientation = { t = "Vector3", get = function(_, d)
			local x, y, z = d.cf:ToOrientation()
			return v3(math.deg(x), math.deg(y), math.deg(z))
		end, set = function(obj, d, v)
			d.cf = R.CFrame.new(d.cf.Position) * R.CFrame.fromOrientation(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
			R.partMoved(obj, d)
		end },
		Rotation = { t = "Vector3", get = function(_, d)
			local x, y, z = d.cf:ToEulerAnglesXYZ()
			return v3(math.deg(x), math.deg(y), math.deg(z))
		end, set = function(obj, d, v)
			d.cf = R.CFrame.new(d.cf.Position) * R.CFrame.Angles(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
			R.partMoved(obj, d)
		end },
		Size = { t = "Vector3", get = function(_, d)
			return d.props.Size
		end, set = function(obj, d, v)
			if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z then
				R.log(R.warnings, "NaN Size assigned to " .. R.fullName(obj))
				return false
			end
			d.props.Size = v3(math.max(0.001, v.X), math.max(0.001, v.Y), math.max(0.001, v.Z))
			R.partMoved(obj, d)
		end },
	}
	for k, v in pairs(extra or {}) do
		t[k] = v
	end
	return t
end
def("PVInstance", "Instance", { creatable = false })
R.CLASSES.Model.super = R.CLASSES.PVInstance
def("BasePart", "PVInstance", {
	creatable = false,
	props = partProps(),
	events = { "Touched", "TouchEnded", "LocalSimulationTouched" },
	init = function(obj, d)
		d.cf = R.CFrame.identity
		d.props.Size = v3(4, 1, 2)
	end,
	methods = {},
})
R.CLASSES.BasePart.P.Size.default = v3(4, 1, 2)
def("FormFactorPart", "BasePart", { creatable = false })
def("Part", "FormFactorPart", { props = { Shape = E("PartType", "Block") } })
def("WedgePart", "FormFactorPart", {})
def("CornerWedgePart", "BasePart", {})
def("TrussPart", "BasePart", { props = { Style = ANY() }, init = function(obj, d)
	d.props.Size = v3(2, 2, 2)
end })
def("SpawnLocation", "Part", { props = { Enabled = B(true), Neutral = B(true), AllowTeamChangeOnTouch = B(false), Duration = N(10), TeamColor = ANY() } })
def("MeshPart", "BasePart", { props = { MeshId = S(""), TextureID = S(""), DoubleSided = B(false), RenderFidelity = ANY(), CollisionFidelity = ANY() } })
def("Terrain", "BasePart", { creatable = false, props = {
	WaterColor = C3(), WaterReflectance = N(1), WaterTransparency = N(0.3), WaterWaveSize = N(0.15), WaterWaveSpeed = N(10), Decoration = B(false),
	GrassLength = N(0.7), MaterialColors = ANY(),
}, methods = {} })
def("SpecialMesh", "Instance", { props = { MeshType = E("MeshType", "Head"), MeshId = S(""), TextureId = S(""), Scale = V3(v3(1, 1, 1)), Offset = V3(), VertexColor = V3(v3(1, 1, 1)) } })
def("BlockMesh", "Instance", { props = { Scale = V3(v3(1, 1, 1)), Offset = V3() } })
def("Decal", "Instance", { props = { Texture = S(""), Face = E("NormalId", "Front"), Color3 = C3(), Transparency = N(0), ZIndex = N(1), LocalTransparencyModifier = N(0) } })
def("Texture", "Decal", { props = { StudsPerTileU = N(2), StudsPerTileV = N(2), OffsetStudsU = N(0), OffsetStudsV = N(0) } })
def("SurfaceAppearance", "Instance", { creatable = false })

-- effects ---------------------------------------------------------------------------
def("Highlight", "Instance", { props = { Adornee = I(), Enabled = B(true), FillColor = C3(c3(1, 0, 0)), OutlineColor = C3(), FillTransparency = N(0.5), OutlineTransparency = N(0), DepthMode = E("HighlightDepthMode", "AlwaysOnTop") } })
def("ParticleEmitter", "Instance", {
	props = {
		Enabled = B(true), Rate = N(5), Lifetime = NR(5, 10), Speed = NR(5), SpreadAngle = V2(), Rotation = NR(0), RotSpeed = NR(0),
		Size = NS(1), Transparency = NS(0), Color = CS(), LightEmission = N(0), LightInfluence = N(1), Brightness = N(1),
		Texture = S("rbxasset://textures/particles/sparkles_main.dds"), Acceleration = V3(), Drag = N(0), LockedToPart = B(false),
		VelocityInheritance = N(0), ZOffset = N(0), EmissionDirection = E("NormalId", "Top"), Orientation = E("ParticleOrientation", "FacingCamera"),
		Shape = E("ParticleEmitterShape", "Box"), ShapeInOut = E("ParticleEmitterShapeInOut", "Outward"), ShapeStyle = E("ParticleEmitterShapeStyle", "Volume"),
		ShapePartial = N(1), Squash = NS(0), TimeScale = N(1), FlipbookLayout = E("ParticleFlipbookLayout", "None"),
		FlipbookMode = E("ParticleFlipbookMode", "Loop"), FlipbookFramerate = NR(1), FlipbookStartRandom = B(false), WindAffectsDrag = B(false),
	},
	methods = {
		Emit = function(self, n)
			local d = DATA[self]
			d.bursts = d.bursts or {}
			d.bursts[#d.bursts + 1] = { t = R.now, n = n or 16 }
			R.emitCount = (R.emitCount or 0) + (n or 16)
		end,
		Clear = function(self)
			DATA[self].bursts = {}
		end,
	},
	init = function(obj, d)
		d.created = R.now
	end,
})
def("Beam", "Instance", { props = {
	Attachment0 = I("Attachment"), Attachment1 = I("Attachment"), Color = CS(), Enabled = B(true), FaceCamera = B(false), LightEmission = N(0),
	LightInfluence = N(1), Brightness = N(1), Segments = N(10), Texture = S(""), TextureLength = N(1), TextureMode = E("TextureMode", "Stretch"),
	TextureSpeed = N(1), Transparency = NS(0.5), Width0 = N(1), Width1 = N(1), ZOffset = N(0), CurveSize0 = N(0), CurveSize1 = N(0),
} })
def("Trail", "Instance", { props = {
	Attachment0 = I("Attachment"), Attachment1 = I("Attachment"), Color = CS(), Enabled = B(true), FaceCamera = B(false), LightEmission = N(0),
	LightInfluence = N(1), Brightness = N(1), Lifetime = N(2), MaxLength = N(0), MinLength = N(0.1), Texture = S(""), TextureLength = N(1),
	TextureMode = E("TextureMode", "Stretch"), Transparency = NS(0.5), WidthScale = NS(1),
}, methods = { Clear = function() end } })
def("Light", "Instance", { creatable = false, props = { Brightness = N(1), Color = C3(), Enabled = B(true), Shadows = B(false) } })
def("PointLight", "Light", { props = { Range = N(8) } })
def("SpotLight", "Light", { props = { Range = N(16), Angle = N(90), Face = E("NormalId", "Front") } })
def("SurfaceLight", "Light", { props = { Range = N(16), Angle = N(90), Face = E("NormalId", "Front") } })
def("Fire", "Instance", { props = { Color = C3(c3(0.93, 0.5, 0.1)), SecondaryColor = C3(c3(0.55, 0.1, 0)), Heat = N(9), Size = N(5), Enabled = B(true), TimeScale = N(1) } })
def("Smoke", "Instance", { props = { Color = C3(), Opacity = N(0.5), RiseVelocity = N(1), Size = N(1), Enabled = B(true), TimeScale = N(1) } })
def("Sparkles", "Instance", { props = { SparkleColor = C3(), Enabled = B(true), TimeScale = N(1) } })
def("Explosion", "Instance", { props = { Position = V3(), BlastRadius = N(4), BlastPressure = N(500000), DestroyJointRadiusPercent = N(1), ExplosionType = E("ExplosionType", "Craters"), Visible = B(true), TimeScale = N(1) }, events = { "Hit" } })
def("ForceField", "Instance", { props = { Visible = B(true) } })

-- lighting / post-processing -------------------------------------------------------
def("Atmosphere", "Instance", { props = { Density = N(0.3), Offset = N(0), Color = C3(c3(0.78, 0.67, 0.42)), Decay = C3(c3(0.36, 0.24, 0.1)), Glare = N(0), Haze = N(0) } })
def("Sky", "Instance", { props = {
	SkyboxBk = S(""), SkyboxDn = S(""), SkyboxFt = S(""), SkyboxLf = S(""), SkyboxRt = S(""), SkyboxUp = S(""), SunTextureId = S(""), MoonTextureId = S(""),
	CelestialBodiesShown = B(true), StarCount = N(3000), SunAngularSize = N(21), MoonAngularSize = N(11), SkyboxOrientation = V3(),
} })
def("PostEffect", "Instance", { creatable = false, props = { Enabled = B(true) } })
def("BloomEffect", "PostEffect", { props = { Intensity = N(1), Size = N(24), Threshold = N(2) } })
def("ColorCorrectionEffect", "PostEffect", { props = { Brightness = N(0), Contrast = N(0), Saturation = N(0), TintColor = C3() } })
def("SunRaysEffect", "PostEffect", { props = { Intensity = N(0.25), Spread = N(1) } })
def("DepthOfFieldEffect", "PostEffect", { props = { FarIntensity = N(0.75), FocusDistance = N(0.05), InFocusRadius = N(10), NearIntensity = N(0.75) } })
def("BlurEffect", "PostEffect", { props = { Size = N(24) } })
def("Clouds", "Instance", { props = { Cover = N(0.5), Density = N(0.7), Color = C3(), Enabled = B(true) } })

-- sound -------------------------------------------------------------------------------
R.soundPlays = {}
def("Sound", "Instance", {
	props = {
		SoundId = S(""), Volume = N(0.5), PlaybackSpeed = N(1), Pitch = { t = "number", get = function(o, d)
			return d.props.PlaybackSpeed
		end, set = function(o, d, v)
			d.props.PlaybackSpeed = v
		end },
		Looped = B(false), Playing = B(false), TimePosition = N(0), RollOffMaxDistance = N(10000), RollOffMinDistance = N(10),
		RollOffMode = E("RollOffMode", "Inverse"), SoundGroup = I("SoundGroup"), PlayOnRemove = B(false),
		IsPlaying = RO(P("boolean"), function(_, d)
			return d.playing == true
		end),
		IsLoaded = RO(P("boolean"), function()
			return true
		end),
		TimeLength = RO(P("number"), function(_, d)
			return R.soundLength(d.props.SoundId)
		end),
		PlaybackLoudness = RO(P("number"), function()
			return 0
		end),
	},
	events = { "Played", "Ended", "Stopped", "Paused", "Resumed", "Loaded", "DidLoop" },
	methods = {
		Play = function(self)
			local d = DATA[self]
			d.playing = true
			d.playStart = R.now
			d.props.Playing = true
			table.insert(R.soundPlays, { t = R.now, id = d.props.SoundId, vol = d.props.Volume, speed = d.props.PlaybackSpeed, obj = self, group = d.props.SoundGroup })
			R.fire(R.getSignal(d, "Played"), d.props.SoundId)
			if not d.props.Looped then
				local len = R.soundLength(d.props.SoundId) / math.max(0.05, d.props.PlaybackSpeed)
				local token = {}
				d.playToken = token
				R.task.delay(len, function()
					if d.playToken == token and d.playing then
						d.playing = false
						d.props.Playing = false
						R.fire(R.getSignal(d, "Ended"), d.props.SoundId)
					end
				end)
			end
		end,
		Stop = function(self)
			local d = DATA[self]
			d.playing = false
			d.props.Playing = false
			R.fire(R.getSignal(d, "Stopped"), d.props.SoundId)
		end,
		Pause = function(self)
			DATA[self].playing = false
		end,
		Resume = function(self)
			DATA[self].playing = true
		end,
	},
})
def("SoundGroup", "Instance", { props = { Volume = N(0.5) } })
def("SoundEffect", "Instance", { creatable = false, props = { Enabled = B(true), Priority = N(0) } })
def("EqualizerSoundEffect", "SoundEffect", { props = { HighGain = N(0), MidGain = N(0), LowGain = N(0) } })
def("ReverbSoundEffect", "SoundEffect", { props = { DecayTime = N(1.5), Density = N(1), Diffusion = N(1), DryLevel = N(-6), WetLevel = N(0) } })
def("DistortionSoundEffect", "SoundEffect", { props = { Level = N(0.75) } })
def("PitchShiftSoundEffect", "SoundEffect", { props = { Octave = N(1.25) } })
def("ChorusSoundEffect", "SoundEffect", { props = { Depth = N(0.15), Mix = N(0.5), Rate = N(0.5) } })
def("TremoloSoundEffect", "SoundEffect", { props = { Depth = N(1), Duty = N(0.5), Frequency = N(5) } })
def("FlangeSoundEffect", "SoundEffect", { props = { Depth = N(0.45), Mix = N(0.85), Rate = N(5) } })
def("EchoSoundEffect", "SoundEffect", { props = { Delay = N(1), DryLevel = N(0), Feedback = N(0.5), WetLevel = N(0) } })
def("CompressorSoundEffect", "SoundEffect", { props = { Attack = N(0.1), GainMakeup = N(0), Ratio = N(40), Release = N(0.1), Threshold = N(-40), SideChain = I() } })

-- GUI ----------------------------------------------------------------------------------
local function guiBase()
	return {
		Active = B(false), AnchorPoint = V2(), AutomaticSize = E("AutomaticSize", "None"), BackgroundColor3 = C3(c3(0.64, 0.64, 0.64)),
		BackgroundTransparency = N(0), BorderColor3 = C3(c3(0.1, 0.16, 0.2)), BorderMode = E("BorderMode", "Outline"), BorderSizePixel = N(1),
		ClipsDescendants = B(false), LayoutOrder = N(0), Position = U2(), Rotation = N(0), Selectable = B(false), Size = U2(),
		SizeConstraint = E("SizeConstraint", "RelativeXY"), Visible = B(true), ZIndex = N(1), Interactable = B(true), SelectionOrder = N(0),
		AbsolutePosition = RO(P("Vector2"), function(obj)
			return R.guiAbs(obj)[1]
		end),
		AbsoluteSize = RO(P("Vector2"), function(obj)
			return R.guiAbs(obj)[2]
		end),
		AbsoluteRotation = RO(P("number"), function()
			return 0
		end),
		GuiState = ANY(),
	}
end
def("GuiBase2d", "Instance", { creatable = false })
def("LayerCollector", "GuiBase2d", { creatable = false, props = { Enabled = B(true), ResetOnSpawn = B(true), ZIndexBehavior = E("ZIndexBehavior", "Sibling") } })
def("ScreenGui", "LayerCollector", { props = {
	IgnoreGuiInset = B(false), DisplayOrder = N(0), ScreenInsets = E("ScreenInsets", "CoreUISafeInsets"), ClipToDeviceSafeArea = B(true),
	SafeAreaCompatibility = E("SafeAreaCompatibility", "FullscreenExtension"),
	AbsoluteSize = RO(P("Vector2"), function(obj)
		return R.guiAbs(obj)[2]
	end),
	AbsolutePosition = RO(P("Vector2"), function(obj)
		return R.guiAbs(obj)[1]
	end),
} })
def("BillboardGui", "LayerCollector", { props = {
	Adornee = I(), AlwaysOnTop = B(false), Size = U2(), StudsOffset = V3(), StudsOffsetWorldSpace = V3(), ExtentsOffset = V3(),
	ExtentsOffsetWorldSpace = V3(), LightInfluence = N(1), MaxDistance = N(math.huge), SizeOffset = V2(), ClipsDescendants = B(false),
	Brightness = N(1), Active = B(false), DistanceLowerLimit = N(0), DistanceUpperLimit = N(-1), DistanceStep = N(0),
	AbsoluteSize = RO(P("Vector2"), function(obj, d)
		local s = d.props.Size
		return R.v2(s.X.Offset, s.Y.Offset)
	end),
	AbsolutePosition = RO(P("Vector2"), function()
		return R.v2(0, 0)
	end),
} })
def("SurfaceGui", "LayerCollector", { props = {
	Adornee = I(), Face = E("NormalId", "Front"), AlwaysOnTop = B(false), CanvasSize = V2(R.v2(800, 600)), LightInfluence = N(1),
	SizingMode = ANY(), PixelsPerStud = N(50), Brightness = N(1), ClipsDescendants = B(true), Active = B(true), ZOffset = N(0),
	AbsoluteSize = RO(P("Vector2"), function(obj, d)
		return d.props.CanvasSize
	end),
	AbsolutePosition = RO(P("Vector2"), function()
		return R.v2(0, 0)
	end),
} })
def("GuiObject", "GuiBase2d", { creatable = false, props = guiBase(), events = { "InputBegan", "InputEnded", "InputChanged", "MouseEnter", "MouseLeave", "MouseMoved", "SelectionGained", "SelectionLost", "TouchTap" } })
def("Frame", "GuiObject", { props = { Style = ANY() } })
def("CanvasGroup", "GuiObject", { props = { GroupColor3 = C3(), GroupTransparency = N(0) } })
local function textProps()
	return {
		Text = S("Label"), TextColor3 = C3(c3(0.1, 0.1, 0.1)), TextSize = N(14), TextScaled = B(false), TextWrapped = B(false), TextTransparency = N(0),
		TextStrokeColor3 = C3(c3(0, 0, 0)), TextStrokeTransparency = N(1), TextXAlignment = E("TextXAlignment", "Center"),
		TextYAlignment = E("TextYAlignment", "Center"), TextTruncate = E("TextTruncate", "None"), Font = E("Font", "Legacy"),
		FontFace = P("Font", R.Font.new("Legacy")), RichText = B(false), LineHeight = N(1), MaxVisibleGraphemes = N(-1),
		TextDirection = ANY(), TextFits = RO(P("boolean"), function()
			return true
		end),
		TextBounds = RO(P("Vector2"), function(obj, d)
			local txt = d.props.Text:gsub("<[^>]+>", "")
			local longest = 0
			local lines = 0
			for l in (txt .. "\n"):gmatch("([^\n]*)\n") do
				longest = math.max(longest, #l)
				lines = lines + 1
			end
			return R.v2(longest * d.props.TextSize * 0.52, lines * d.props.TextSize * 1.15)
		end),
		ContentText = RO(P("string"), function(_, d)
			return (d.props.Text:gsub("<[^>]+>", ""))
		end),
	}
end
local function merge(a, b)
	for k, v in pairs(b) do
		a[k] = v
	end
	return a
end
def("TextLabel", "GuiObject", { props = textProps() })
def("GuiButton", "GuiObject", { creatable = false, props = { AutoButtonColor = B(true), Modal = B(false), Selected = B(false), Style = ANY() }, events = { "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseButton2Click" } })
def("TextButton", "GuiButton", { props = textProps() })
def("TextBox", "GuiObject", { props = merge(textProps(), { ClearTextOnFocus = B(true), PlaceholderText = S(""), PlaceholderColor3 = C3(c3(0.7, 0.7, 0.7)), MultiLine = B(false), TextEditable = B(true), CursorPosition = N(1), ShowNativeInput = B(true) }), events = { "FocusLost", "Focused", "ReturnPressedFromOnScreenKeyboard" }, methods = {
	CaptureFocus = function() end,
	ReleaseFocus = function() end,
	IsFocused = function()
		return false
	end,
} })
local function imageProps()
	return { Image = S(""), ImageColor3 = C3(), ImageTransparency = N(0), ImageRectOffset = V2(), ImageRectSize = V2(), ScaleType = E("ScaleType", "Stretch"), SliceCenter = P("Rect", R.Rect.new(0, 0, 0, 0)), SliceScale = N(1), TileSize = U2(R.UDim2.fromScale(1, 1)), ResampleMode = E("ResamplerMode", "Default"), IsLoaded = RO(P("boolean"), function()
		return true
	end) }
end
def("ImageLabel", "GuiObject", { props = imageProps() })
def("ImageButton", "GuiButton", { props = merge(imageProps(), { HoverImage = S(""), PressedImage = S("") }) })
def("ScrollingFrame", "GuiObject", { props = {
	CanvasSize = U2(R.UDim2.new(0, 0, 2, 0)), CanvasPosition = V2(), AutomaticCanvasSize = E("AutomaticSize", "None"), ScrollBarThickness = N(12),
	ScrollingDirection = E("ScrollingDirection", "XY"), ScrollingEnabled = B(true), ScrollBarImageColor3 = C3(), ScrollBarImageTransparency = N(0),
	ElasticBehavior = E("ElasticBehavior", "WhenScrollable"), VerticalScrollBarInset = E("ScrollBarInset", "None"), HorizontalScrollBarInset = E("ScrollBarInset", "None"),
	TopImage = S(""), MidImage = S(""), BottomImage = S(""), ScrollBarImageColor = ANY(),
	AbsoluteCanvasSize = RO(P("Vector2"), function(obj)
		return R.guiAbs(obj)[2]
	end),
	AbsoluteWindowSize = RO(P("Vector2"), function(obj)
		return R.guiAbs(obj)[2]
	end),
} })
def("ViewportFrame", "GuiObject", { props = { CurrentCamera = I("Camera"), ImageColor3 = C3(), ImageTransparency = N(0), Ambient = C3(), LightColor = C3(), LightDirection = V3(v3(-1, -1, -1)) } })
def("UIComponent", "Instance", { creatable = false })
def("UIConstraint", "UIComponent", { creatable = false })
def("UIGridStyleLayout", "UIComponent", { creatable = false, props = {
	FillDirection = E("FillDirection", "Horizontal"), HorizontalAlignment = E("HorizontalAlignment", "Left"), VerticalAlignment = E("VerticalAlignment", "Top"),
	SortOrder = E("SortOrder", "LayoutOrder"),
	AbsoluteContentSize = RO(P("Vector2"), function(obj)
		return R.layoutContentSize(obj)
	end),
} })
def("UIListLayout", "UIGridStyleLayout", { props = { Padding = P("UDim", R.UDim.new(0, 0)), Wraps = B(false), HorizontalFlex = ANY(), VerticalFlex = ANY(), ItemLineAlignment = ANY() } })
def("UIGridLayout", "UIGridStyleLayout", { props = { CellSize = U2(R.UDim2.fromOffset(100, 100)), CellPadding = U2(R.UDim2.fromOffset(5, 5)), FillDirectionMaxCells = N(0), StartCorner = ANY() } })
def("UIPageLayout", "UIGridStyleLayout", {})
def("UITableLayout", "UIGridStyleLayout", {})
def("UICorner", "UIComponent", { props = { CornerRadius = P("UDim", R.UDim.new(0, 8)) } })
def("UIStroke", "UIComponent", { props = { Color = C3(c3(0, 0, 0)), Thickness = N(1), Transparency = N(0), ApplyStrokeMode = E("ApplyStrokeMode", "Contextual"), LineJoinMode = E("LineJoinMode", "Round"), Enabled = B(true) } })
def("UIPadding", "UIComponent", { props = { PaddingLeft = P("UDim", R.UDim.new()), PaddingRight = P("UDim", R.UDim.new()), PaddingTop = P("UDim", R.UDim.new()), PaddingBottom = P("UDim", R.UDim.new()) } })
def("UIGradient", "UIComponent", { props = { Color = CS(), Transparency = NS(0), Offset = V2(), Rotation = N(0), Enabled = B(true) } })
def("UIScale", "UIComponent", { props = { Scale = N(1) } })
def("UIAspectRatioConstraint", "UIConstraint", { props = { AspectRatio = N(1), AspectType = E("AspectType", "FitWithinMaxSize"), DominantAxis = E("DominantAxis", "Width") } })
def("UISizeConstraint", "UIConstraint", { props = { MaxSize = V2(R.v2(math.huge, math.huge)), MinSize = V2() } })
def("UITextSizeConstraint", "UIConstraint", { props = { MaxTextSize = N(100), MinTextSize = N(1) } })
def("UIFlexItem", "UIComponent", { props = { FlexMode = ANY(), GrowRatio = N(0), ShrinkRatio = N(0) } })

-- camera ---------------------------------------------------------------------------------
def("Camera", "Instance", {
	props = {
		CFrame = CF(R.CFrame.new(0, 20, 20)), Focus = CF(), FieldOfView = N(70), CameraType = E("CameraType", "Custom"), CameraSubject = I(),
		HeadLocked = B(true), HeadScale = N(1), DiagonalFieldOfView = N(80), MaxAxisFieldOfView = N(70), FieldOfViewMode = ANY(),
		NearPlaneZ = RO(P("number"), function()
			return -0.1
		end),
		ViewportSize = RO(P("Vector2"), function()
			return R.viewport
		end),
	},
	methods = {},
})

-- misc -------------------------------------------------------------------------------
def("ClickDetector", "Instance", { props = { MaxActivationDistance = N(32), CursorIcon = S("") }, events = { "MouseClick", "MouseHoverEnter", "MouseHoverLeave" } })
def("ProximityPrompt", "Instance", { props = { ActionText = S("Interact"), ObjectText = S(""), HoldDuration = N(0), MaxActivationDistance = N(10), Enabled = B(true), KeyboardKeyCode = E("KeyCode", "E"), RequiresLineOfSight = B(true), Style = ANY(), UIOffset = V2(), GamepadKeyCode = ANY(), ClickablePrompt = B(true), Exclusivity = ANY() }, events = { "Triggered", "TriggerEnded", "PromptShown", "PromptHidden", "PromptButtonHoldBegan", "PromptButtonHoldEnded" } })
def("PathfindingModifier", "Instance", { props = { Label = S(""), PassThrough = B(false) } })
def("Tool", "Model", { props = { RequiresHandle = B(true), CanBeDropped = B(true), ToolTip = S(""), TextureId = S(""), Grip = CF(), ManualActivationOnly = B(false), Enabled = B(true) }, events = { "Activated", "Deactivated", "Equipped", "Unequipped" } })
def("Accessory", "Instance", { props = { AttachmentPoint = CF(), AccessoryType = ANY() } })
def("Shirt", "Instance", { props = { ShirtTemplate = S(""), Color3 = C3() } })
def("Pants", "Instance", { props = { PantsTemplate = S(""), Color3 = C3() } })
