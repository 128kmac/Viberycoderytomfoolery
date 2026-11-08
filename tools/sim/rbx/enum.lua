-- Enum emulation. Unknown enums/items raise errors exactly like Roblox, so typos are caught.
local R = ...

local DEFS = {
	Material = "Plastic SmoothPlastic Neon Wood WoodPlanks Marble Slate Concrete Granite Brick Pebble Cobblestone CorrodedMetal DiamondPlate Foil Metal Grass LeafyGrass Sand Fabric Ice Glacier Snow Sandstone Mud Basalt Ground CrackedLava Asphalt Limestone Pavement Salt Rock Glass ForceField Air Water Cardboard Carpet CeramicTiles ClayRoofTiles RoofShingles Leather Plaster Rubber",
	PartType = "Ball Block Cylinder Wedge CornerWedge",
	SurfaceType = "Smooth Glue Weld Studs Inlet Universal Hinge Motor SteppingMotor SmoothNoOutlines",
	Font = "Legacy Arial ArialBold SourceSans SourceSansBold SourceSansLight SourceSansItalic Bodoni Garamond Cartoon Code Highway SciFi Arcade Fantasy Antique SourceSansSemibold Gotham GothamMedium GothamBold GothamBlack AmaticSC Bangers Creepster DenkOne Fondamento FredokaOne GrenzeGotisch IndieFlower JosefinSans Jura Kalam LuckiestGuy Merriweather Michroma Nunito Oswald PatrickHand PermanentMarker Roboto RobotoCondensed RobotoMono Sarpanch SpecialElite TitilliumWeb Ubuntu BuilderSans BuilderSansMedium BuilderSansBold BuilderSansExtraBold Montserrat MontserratMedium MontserratBold MontserratBlack",
	TextXAlignment = "Left Right Center",
	TextYAlignment = "Top Center Bottom",
	TextTruncate = "None AtEnd SplitWord",
	AutomaticSize = "None X Y XY",
	SortOrder = "Name Custom LayoutOrder",
	FillDirection = "Horizontal Vertical",
	HorizontalAlignment = "Center Left Right",
	VerticalAlignment = "Center Top Bottom",
	ZIndexBehavior = "Global Sibling",
	ApplyStrokeMode = "Contextual Border",
	ScrollingDirection = "X Y XY",
	ScrollBarInset = "None ScrollBar Always",
	ElasticBehavior = "WhenScrollable Always Never",
	ScaleType = "Stretch Slice Tile Fit Crop",
	ResamplerMode = "Default Pixelated",
	SizeConstraint = "RelativeXY RelativeXX RelativeYY",
	AspectType = "FitWithinMaxSize ScaleWithParentSize",
	DominantAxis = "Width Height",
	EasingStyle = "Linear Sine Back Quad Quart Quint Bounce Elastic Exponential Circular Cubic",
	EasingDirection = "In Out InOut",
	PlaybackState = "Begin Delayed Playing Paused Completed Cancelled",
	KeyCode = "Unknown Backspace Tab Clear Return Pause Escape Space QuotedDouble Hash Dollar Percent Ampersand Quote LeftParenthesis RightParenthesis Asterisk Plus Comma Minus Period Slash Zero One Two Three Four Five Six Seven Eight Nine Colon Semicolon LessThan Equals GreaterThan Question At LeftBracket BackSlash RightBracket Caret Underscore Backquote A B C D E F G H I J K L M N O P Q R S T U V W X Y Z LeftCurly Pipe RightCurly Tilde Delete Up Down Right Left Insert Home End PageUp PageDown LeftShift RightShift LeftMeta RightMeta LeftAlt RightAlt LeftControl RightControl CapsLock NumLock ScrollLock F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12 ButtonX ButtonY ButtonA ButtonB ButtonR1 ButtonL1 ButtonR2 ButtonL2 ButtonR3 ButtonL3 ButtonStart ButtonSelect DPadLeft DPadRight DPadUp DPadDown Thumbstick1 Thumbstick2",
	UserInputType = "MouseButton1 MouseButton2 MouseButton3 MouseWheel MouseMovement Touch Keyboard Focus Accelerometer Gyro Gamepad1 Gamepad2 Gamepad3 Gamepad4 TextInput InputMethod None",
	UserInputState = "Begin Change End Cancel None",
	MouseBehavior = "Default LockCenter LockCurrentPosition",
	ContextActionResult = "Pass Sink",
	ContextActionPriority = "Low Medium Default High",
	CameraType = "Fixed Attach Watch Track Follow Custom Scriptable Orbital",
	CameraMode = "Classic LockFirstPerson",
	RenderPriority = "First Input Camera Character Last",
	HumanoidRigType = "R6 R15",
	HumanoidStateType = "FallingDown Ragdoll GettingUp Jumping Swimming Freefall Flying Landed Running RunningNoPhysics StrafingNoPhysics Climbing Seated PlatformStanding Dead Physics None",
	HumanoidHealthDisplayType = "DisplayWhenDamaged AlwaysOn AlwaysOff",
	HumanoidDisplayDistanceType = "Viewer Subject None",
	HighlightDepthMode = "AlwaysOnTop Occluded",
	ActuatorRelativeTo = "Attachment0 Attachment1 World",
	VelocityConstraintMode = "Line Plane Vector",
	ForceLimitMode = "Magnitude PerAxis",
	RaycastFilterType = "Exclude Include Blacklist Whitelist",
	NormalId = "Right Top Back Left Bottom Front",
	Technology = "Legacy Voxel Compatibility ShadowMap Future",
	SignalBehavior = "Default Immediate Deferred AncestryDeferred",
	ParticleOrientation = "FacingCamera FacingCameraWorldUp VelocityParallel VelocityPerpendicular",
	ParticleEmitterShape = "Box Sphere Cylinder Disc",
	ParticleEmitterShapeInOut = "Outward Inward InAndOut",
	ParticleEmitterShapeStyle = "Volume Surface",
	ParticleFlipbookLayout = "None Grid2x2 Grid4x4 Grid8x8",
	ParticleFlipbookMode = "Loop OneShot PingPong Random",
	ParticleEmitterLightInfluence = "None",
	TextureMode = "Stretch Wrap Static",
	RollOffMode = "Inverse Linear LinearSquare InverseTapered",
	ReverbType = "NoReverb GenericReverb PaddedCell Room Bathroom LivingRoom StoneRoom Auditorium ConcertHall Cave Arena Hangar CarpettedHallway Hallway StoneCorridor Alley Forest City Mountains Quarry Plain ParkingLot SewerPipe UnderWater",
	ExplosionType = "NoCraters Craters",
	Limb = "Head Torso LeftArm RightArm LeftLeg RightLeg Unknown",
	BodyPart = "Head Torso LeftArm RightArm LeftLeg RightLeg",
	CoreGuiType = "PlayerList Health Backpack Chat All EmotesMenu SelfView Captures",
	ScreenInsets = "None DeviceSafeInsets CoreUISafeInsets TopbarSafeInsets",
	SafeAreaCompatibility = "None FullscreenExtension",
	PathStatus = "Success ClosestNoPath ClosestOutOfRange FailStartNotEmpty FailFinishNotEmpty NoPath",
	PathWaypointAction = "Walk Jump Custom",
	CollisionFidelity = "Default Hull Box PreciseConvexDecomposition",
	RenderFidelity = "Automatic Precise Performance",
	MeshType = "Head Torso Wedge Prism Pyramid ParallelRamp RightAngleRamp CornerWedge Brick Sphere Cylinder FileMesh",
	AnimationPriority = "Idle Movement Action Action2 Action3 Action4 Core",
	FontWeight = "Thin ExtraLight Light Regular Medium SemiBold Bold ExtraBold Heavy",
	FontStyle = "Normal Italic",
	SelectionBehavior = "Escape Stop",
	ModifierKey = "Alt Ctrl Meta Shift",
	TeleportType = "ToPlace ToInstance ToReservedServer",
	DevComputerMovementMode = "UserChoice KeyboardMouse ClickToMove Scriptable",
	DevTouchMovementMode = "UserChoice Thumbstick DPad Thumbpad ClickToMove Scriptable DynamicThumbstick",
	DevCameraOcclusionMode = "Zoom Invisicam",
	DevComputerCameraMovementMode = "UserChoice Classic Follow Orbital CameraToggle",
	CharacterControlMode = "Default Legacy NoCharacterController LuaCharacterController",
	FramerateManagerMode = "Automatic On Off",
	SavedQualitySetting = "Automatic QualityLevel1 QualityLevel2 QualityLevel3 QualityLevel4 QualityLevel5 QualityLevel6 QualityLevel7 QualityLevel8 QualityLevel9 QualityLevel10",
	AlphaMode = "Overlay Transparency",
	StudsOffsetType = "Default",
	LineJoinMode = "Round Bevel Miter",
	BorderMode = "Outline Middle Inset",
	ButtonStyle = "Custom RobloxButtonDefault RobloxButton RobloxRoundButton RobloxRoundDefaultButton RobloxRoundDropdownButton",
	TextDirection = "Auto LeftToRight RightToLeft",
	AutoSkin = "AutoSkin",
	InfluenceBy = "None",
}

local EnumItemMT = {}
R.TYPE[EnumItemMT] = "EnumItem"
EnumItemMT.__index = function(item, k)
	if k == "IsA" then
		return function(self, name)
			return self.EnumType._name == name
		end
	end
	error(tostring(k) .. " is not a valid member of EnumItem", 2)
end
EnumItemMT.__tostring = function(item)
	return "Enum." .. rawget(item, "EnumType")._name .. "." .. rawget(item, "Name")
end

local EnumMT = {}
R.TYPE[EnumMT] = "Enum"
EnumMT.__index = function(e, k)
	if k == "GetEnumItems" then
		return function(self)
			local out = {}
			for _, it in ipairs(rawget(self, "_items")) do
				table.insert(out, it)
			end
			return out
		end
	elseif k == "FromName" then
		return function(self, n)
			return rawget(self, "_byname")[n]
		end
	elseif k == "FromValue" then
		return function(self, v)
			for _, it in ipairs(rawget(self, "_items")) do
				if it.Value == v then
					return it
				end
			end
			return nil
		end
	end
	error(tostring(k) .. " is not a valid EnumItem of Enum." .. rawget(e, "_name"), 2)
end
EnumMT.__tostring = function(e)
	return rawget(e, "_name")
end

local Enums = {}
for name, list in pairs(DEFS) do
	local e = setmetatable({ _name = name, _items = {}, _byname = {} }, EnumMT)
	local i = 0
	for itemName in list:gmatch("%S+") do
		local item = setmetatable({ Name = itemName, Value = i, EnumType = e }, EnumItemMT)
		rawset(e, itemName, item)
		e._items[#e._items + 1] = item
		e._byname[itemName] = item
		i = i + 1
	end
	Enums[name] = e
end

R.Enum = setmetatable({}, {
	__index = function(_, k)
		local e = Enums[k]
		if not e then
			error(tostring(k) .. " is not a valid member of Enums", 2)
		end
		return e
	end,
})
function R.isEnumItem(v)
	return getmetatable(v) == EnumItemMT
end
