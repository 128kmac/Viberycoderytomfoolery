-- Roblox datatypes for the headless harness: Vector3, Vector2, CFrame, Color3, UDim, UDim2,
-- NumberSequence, ColorSequence, NumberRange, TweenInfo, Random, BrickColor, Rect, Ray, Font...
local R = ...
local sqrt, abs, sin, cos, atan2, asin, acos, floor = math.sqrt, math.abs, math.sin, math.cos, math.atan, math.asin, math.acos, math.floor
local NaN = 0 / 0

local TYPE = setmetatable({}, { __mode = "k" }) -- metatable -> typeof name
R.TYPE = TYPE

local function num(x, what)
	if type(x) ~= "number" then
		error((what or "argument") .. " must be a number, got " .. type(x), 3)
	end
	return x
end

---------------------------------------------------------------- Vector3
local V3 = {}
local V3MT = {}
TYPE[V3MT] = "Vector3"
local function v3(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z }, V3MT)
end
R.v3 = v3
local function isV3(v)
	return getmetatable(v) == V3MT
end
R.isV3 = isV3

V3MT.__index = function(v, k)
	if k == "Magnitude" then
		return sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return v3(v.X / m, v.Y / m, v.Z / m)
	elseif k == "x" then
		return v.X
	elseif k == "y" then
		return v.Y
	elseif k == "z" then
		return v.Z
	end
	local m = V3[k]
	if m then
		return m
	end
	error(tostring(k) .. " is not a valid member of Vector3", 2)
end
V3MT.__newindex = function(_, k)
	error(tostring(k) .. " cannot be assigned to", 2)
end
V3MT.__add = function(a, b)
	if not isV3(a) or not isV3(b) then
		error("invalid argument to Vector3 +: " .. R.typeof(a) .. " + " .. R.typeof(b), 2)
	end
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3MT.__sub = function(a, b)
	if not isV3(a) or not isV3(b) then
		error("invalid argument to Vector3 -: " .. R.typeof(a) .. " - " .. R.typeof(b), 2)
	end
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3MT.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	elseif isV3(a) and isV3(b) then
		return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
	end
	error("invalid argument to Vector3 *: " .. R.typeof(a) .. " * " .. R.typeof(b), 2)
end
V3MT.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	elseif isV3(a) and isV3(b) then
		return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
	elseif type(a) == "number" and isV3(b) then
		return v3(a / b.X, a / b.Y, a / b.Z)
	end
	error("invalid argument to Vector3 /", 2)
end
V3MT.__idiv = function(a, b)
	return v3(floor(a.X / b), floor(a.Y / b), floor(a.Z / b))
end
V3MT.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3MT.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3MT.__tostring = function(v)
	return string.format("%g, %g, %g", v.X, v.Y, v.Z)
end
function V3.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3.Lerp(a, b, t)
	num(t, "alpha")
	return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
end
function V3.Abs(a)
	return v3(abs(a.X), abs(a.Y), abs(a.Z))
end
function V3.Min(a, ...)
	local x, y, z = a.X, a.Y, a.Z
	for _, b in ipairs({ ... }) do
		x, y, z = math.min(x, b.X), math.min(y, b.Y), math.min(z, b.Z)
	end
	return v3(x, y, z)
end
function V3.Max(a, ...)
	local x, y, z = a.X, a.Y, a.Z
	for _, b in ipairs({ ... }) do
		x, y, z = math.max(x, b.X), math.max(y, b.Y), math.max(z, b.Z)
	end
	return v3(x, y, z)
end
function V3.Floor(a)
	return v3(floor(a.X), floor(a.Y), floor(a.Z))
end
function V3.Ceil(a)
	return v3(math.ceil(a.X), math.ceil(a.Y), math.ceil(a.Z))
end
function V3.Sign(a)
	return v3(R.sign(a.X), R.sign(a.Y), R.sign(a.Z))
end
function V3.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	return abs(a.X - b.X) <= eps and abs(a.Y - b.Y) <= eps and abs(a.Z - b.Z) <= eps
end
function V3.Angle(a, b, axis)
	local d = (a.X * b.X + a.Y * b.Y + a.Z * b.Z) / (a.Magnitude * b.Magnitude)
	return acos(math.max(-1, math.min(1, d)))
end

function R.sign(x)
	if x > 0 then
		return 1
	elseif x < 0 then
		return -1
	end
	return 0
end

local Vector3 = {
	new = function(x, y, z)
		return v3(x or 0, y or 0, z or 0)
	end,
	zero = v3(0, 0, 0),
	one = v3(1, 1, 1),
	xAxis = v3(1, 0, 0),
	yAxis = v3(0, 1, 0),
	zAxis = v3(0, 0, 1),
	FromNormalId = function(n)
		local map = { Right = v3(1, 0, 0), Left = v3(-1, 0, 0), Top = v3(0, 1, 0), Bottom = v3(0, -1, 0), Back = v3(0, 0, 1), Front = v3(0, 0, -1) }
		return map[n.Name]
	end,
}
R.Vector3 = Vector3

---------------------------------------------------------------- Vector2
local V2 = {}
local V2MT = {}
TYPE[V2MT] = "Vector2"
local function v2(x, y)
	return setmetatable({ X = x, Y = y }, V2MT)
end
R.v2 = v2
V2MT.__index = function(v, k)
	if k == "Magnitude" then
		return sqrt(v.X * v.X + v.Y * v.Y)
	elseif k == "Unit" then
		local m = sqrt(v.X * v.X + v.Y * v.Y)
		return v2(v.X / m, v.Y / m)
	end
	local m = V2[k]
	if m then
		return m
	end
	error(tostring(k) .. " is not a valid member of Vector2", 2)
end
V2MT.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
V2MT.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
V2MT.__mul = function(a, b)
	if type(a) == "number" then
		return v2(a * b.X, a * b.Y)
	elseif type(b) == "number" then
		return v2(a.X * b, a.Y * b)
	end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2MT.__div = function(a, b)
	if type(b) == "number" then
		return v2(a.X / b, a.Y / b)
	end
	return v2(a.X / b.X, a.Y / b.Y)
end
V2MT.__unm = function(a)
	return v2(-a.X, -a.Y)
end
V2MT.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
V2MT.__tostring = function(v)
	return string.format("%g, %g", v.X, v.Y)
end
function V2.Dot(a, b)
	return a.X * b.X + a.Y * b.Y
end
function V2.Lerp(a, b, t)
	return v2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t)
end
function V2.Cross(a, b)
	return a.X * b.Y - a.Y * b.X
end
R.Vector2 = {
	new = function(x, y)
		return v2(x or 0, y or 0)
	end,
	zero = v2(0, 0),
	one = v2(1, 1),
	xAxis = v2(1, 0),
	yAxis = v2(0, 1),
}

---------------------------------------------------------------- CFrame
-- stored as position p and rotation matrix rows m = {r00..r22}
local CF = {}
local CFMT = {}
TYPE[CFMT] = "CFrame"
local function cf(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	return setmetatable({ x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 }, CFMT)
end
R.cf = cf
local function isCF(c)
	return getmetatable(c) == CFMT
end
R.isCF = isCF

CFMT.__index = function(c, k)
	if k == "Position" or k == "p" then
		return v3(c[1], c[2], c[3])
	elseif k == "X" or k == "x" then
		return c[1]
	elseif k == "Y" or k == "y" then
		return c[2]
	elseif k == "Z" or k == "z" then
		return c[3]
	elseif k == "LookVector" or k == "lookVector" then
		return v3(-c[6], -c[9], -c[12])
	elseif k == "RightVector" or k == "rightVector" or k == "XVector" then
		return v3(c[4], c[7], c[10])
	elseif k == "UpVector" or k == "upVector" or k == "YVector" then
		return v3(c[5], c[8], c[11])
	elseif k == "ZVector" then
		return v3(c[6], c[9], c[12])
	elseif k == "Rotation" then
		return cf(0, 0, 0, c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
	end
	local m = CF[k]
	if m then
		return m
	end
	error(tostring(k) .. " is not a valid member of CFrame", 2)
end
CFMT.__newindex = function(_, k)
	error(tostring(k) .. " cannot be assigned to", 2)
end

local function mul(a, b)
	local a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12 = a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12]
	local b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12 = b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12]
	return cf(
		a4 * b1 + a5 * b2 + a6 * b3 + a1,
		a7 * b1 + a8 * b2 + a9 * b3 + a2,
		a10 * b1 + a11 * b2 + a12 * b3 + a3,
		a4 * b4 + a5 * b7 + a6 * b10,
		a4 * b5 + a5 * b8 + a6 * b11,
		a4 * b6 + a5 * b9 + a6 * b12,
		a7 * b4 + a8 * b7 + a9 * b10,
		a7 * b5 + a8 * b8 + a9 * b11,
		a7 * b6 + a8 * b9 + a9 * b12,
		a10 * b4 + a11 * b7 + a12 * b10,
		a10 * b5 + a11 * b8 + a12 * b11,
		a10 * b6 + a11 * b9 + a12 * b12
	)
end
local function pointToWorld(c, v)
	return v3(c[4] * v.X + c[5] * v.Y + c[6] * v.Z + c[1], c[7] * v.X + c[8] * v.Y + c[9] * v.Z + c[2], c[10] * v.X + c[11] * v.Y + c[12] * v.Z + c[3])
end
local function vecToWorld(c, v)
	return v3(c[4] * v.X + c[5] * v.Y + c[6] * v.Z, c[7] * v.X + c[8] * v.Y + c[9] * v.Z, c[10] * v.X + c[11] * v.Y + c[12] * v.Z)
end
local function inverse(c)
	-- rotation is orthonormal: inverse = transpose
	local r00, r01, r02, r10, r11, r12, r20, r21, r22 = c[4], c[7], c[10], c[5], c[8], c[11], c[6], c[9], c[12]
	local x, y, z = c[1], c[2], c[3]
	return cf(-(r00 * x + r01 * y + r02 * z), -(r10 * x + r11 * y + r12 * z), -(r20 * x + r21 * y + r22 * z), r00, r01, r02, r10, r11, r12, r20, r21, r22)
end
R.cfInverse = inverse
R.pointToWorld = pointToWorld
R.vecToWorld = vecToWorld
local function pointToObject(c, v)
	local dx, dy, dz = v.X - c[1], v.Y - c[2], v.Z - c[3]
	return v3(c[4] * dx + c[7] * dy + c[10] * dz, c[5] * dx + c[8] * dy + c[11] * dz, c[6] * dx + c[9] * dy + c[12] * dz)
end
local function vecToObject(c, v)
	return v3(c[4] * v.X + c[7] * v.Y + c[10] * v.Z, c[5] * v.X + c[8] * v.Y + c[11] * v.Z, c[6] * v.X + c[9] * v.Y + c[12] * v.Z)
end
R.pointToObject = pointToObject
R.vecToObject = vecToObject

CFMT.__mul = function(a, b)
	if isCF(b) then
		return mul(a, b)
	elseif isV3(b) then
		return pointToWorld(a, b)
	end
	error("invalid argument #2 to CFrame * (" .. R.typeof(b) .. ")", 2)
end
CFMT.__add = function(a, b)
	if not isV3(b) then
		error("invalid argument to CFrame + (expected Vector3, got " .. R.typeof(b) .. ")", 2)
	end
	return cf(a[1] + b.X, a[2] + b.Y, a[3] + b.Z, a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12])
end
CFMT.__sub = function(a, b)
	if not isV3(b) then
		error("invalid argument to CFrame - (expected Vector3, got " .. R.typeof(b) .. ")", 2)
	end
	return cf(a[1] - b.X, a[2] - b.Y, a[3] - b.Z, a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12])
end
CFMT.__eq = function(a, b)
	for i = 1, 12 do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end
CFMT.__tostring = function(c)
	return string.format("%g, %g, %g, %g, %g, %g, %g, %g, %g, %g, %g, %g", table.unpack(c))
end

function CF.Inverse(c)
	return inverse(c)
end
function CF.PointToWorldSpace(c, v)
	return pointToWorld(c, v)
end
function CF.PointToObjectSpace(c, v)
	return pointToObject(c, v)
end
function CF.VectorToWorldSpace(c, v)
	return vecToWorld(c, v)
end
function CF.VectorToObjectSpace(c, v)
	return vecToObject(c, v)
end
function CF.ToWorldSpace(c, o)
	return mul(c, o)
end
function CF.ToObjectSpace(c, o)
	return mul(inverse(c), o)
end
function CF.GetComponents(c)
	return table.unpack(c)
end
CF.components = CF.GetComponents

local function fromMatrixRows(x, y, z, r)
	return cf(x, y, z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
end

-- quaternion helpers for Lerp
local function toQuat(c)
	local m00, m01, m02, m10, m11, m12, m20, m21, m22 = c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12]
	local tr = m00 + m11 + m22
	local w, x, y, z
	if tr > 0 then
		local s = sqrt(tr + 1) * 2
		w = 0.25 * s
		x = (m21 - m12) / s
		y = (m02 - m20) / s
		z = (m10 - m01) / s
	elseif m00 > m11 and m00 > m22 then
		local s = sqrt(1 + m00 - m11 - m22) * 2
		w = (m21 - m12) / s
		x = 0.25 * s
		y = (m01 + m10) / s
		z = (m02 + m20) / s
	elseif m11 > m22 then
		local s = sqrt(1 + m11 - m00 - m22) * 2
		w = (m02 - m20) / s
		x = (m01 + m10) / s
		y = 0.25 * s
		z = (m12 + m21) / s
	else
		local s = sqrt(1 + m22 - m00 - m11) * 2
		w = (m10 - m01) / s
		x = (m02 + m20) / s
		y = (m12 + m21) / s
		z = 0.25 * s
	end
	return w, x, y, z
end
local function fromQuat(px, py, pz, w, x, y, z)
	local n = sqrt(w * w + x * x + y * y + z * z)
	w, x, y, z = w / n, x / n, y / n, z / n
	return cf(px, py, pz,
		1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w),
		2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
		2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y))
end
R.toQuat = toQuat
function CF.Lerp(a, b, t)
	local aw, ax, ay, az = toQuat(a)
	local bw, bx, by, bz = toQuat(b)
	local d = aw * bw + ax * bx + ay * by + az * bz
	if d < 0 then
		bw, bx, by, bz, d = -bw, -bx, -by, -bz, -d
	end
	local w, x, y, z
	if d > 0.9995 then
		w, x, y, z = aw + (bw - aw) * t, ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t
	else
		local th = acos(d)
		local s = sin(th)
		local wa, wb = sin((1 - t) * th) / s, sin(t * th) / s
		w, x, y, z = aw * wa + bw * wb, ax * wa + bx * wb, ay * wa + by * wb, az * wa + bz * wb
	end
	return fromQuat(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, w, x, y, z)
end
function CF.ToEulerAnglesXYZ(c)
	local r02 = c[6]
	local ry = asin(math.max(-1, math.min(1, r02)))
	local rx = atan2(-c[9], c[12])
	local rz = atan2(-c[5], c[4])
	return rx, ry, rz
end
CF.toEulerAnglesXYZ = CF.ToEulerAnglesXYZ
function CF.ToEulerAnglesYXZ(c)
	local r12 = c[9]
	local rx = asin(math.max(-1, math.min(1, -r12)))
	local ry = atan2(c[6], c[12])
	local rz = atan2(c[7], c[8])
	return rx, ry, rz
end
CF.ToOrientation = CF.ToEulerAnglesYXZ
CF.toOrientation = CF.ToEulerAnglesYXZ
function CF.ToAxisAngle(c)
	local w, x, y, z = toQuat(c)
	local angle = 2 * acos(math.max(-1, math.min(1, w)))
	local s = sqrt(1 - w * w)
	if s < 1e-6 then
		return v3(1, 0, 0), 0
	end
	return v3(x / s, y / s, z / s), angle
end
function CF.Orthonormalize(c)
	return c
end
function CF.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	for i = 1, 12 do
		if abs(a[i] - b[i]) > eps then
			return false
		end
	end
	return true
end

local function rotX(a)
	local c, s = cos(a), sin(a)
	return { 1, 0, 0, 0, c, -s, 0, s, c }
end
local function rotY(a)
	local c, s = cos(a), sin(a)
	return { c, 0, s, 0, 1, 0, -s, 0, c }
end
local function rotZ(a)
	local c, s = cos(a), sin(a)
	return { c, -s, 0, s, c, 0, 0, 0, 1 }
end
local function m3mul(a, b)
	return {
		a[1] * b[1] + a[2] * b[4] + a[3] * b[7], a[1] * b[2] + a[2] * b[5] + a[3] * b[8], a[1] * b[3] + a[2] * b[6] + a[3] * b[9],
		a[4] * b[1] + a[5] * b[4] + a[6] * b[7], a[4] * b[2] + a[5] * b[5] + a[6] * b[8], a[4] * b[3] + a[5] * b[6] + a[6] * b[9],
		a[7] * b[1] + a[8] * b[4] + a[9] * b[7], a[7] * b[2] + a[8] * b[5] + a[9] * b[8], a[7] * b[3] + a[8] * b[6] + a[9] * b[9],
	}
end

local identity = cf(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
local function lookAt(at, target, up)
	up = up or v3(0, 1, 0)
	local lx, ly, lz = target.X - at.X, target.Y - at.Y, target.Z - at.Z
	local lm = sqrt(lx * lx + ly * ly + lz * lz)
	if lm < 1e-9 then
		return cf(at.X, at.Y, at.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	lx, ly, lz = lx / lm, ly / lm, lz / lm
	-- right = look x up
	local rx, ry, rz = ly * up.Z - lz * up.Y, lz * up.X - lx * up.Z, lx * up.Y - ly * up.X
	local rm = sqrt(rx * rx + ry * ry + rz * rz)
	if rm < 1e-6 then
		-- looking straight up/down: pick a stable right vector
		rx, ry, rz = 1, 0, 0
		if abs(lx) > 0.9 then
			rx, ry, rz = 0, 0, 1
		end
		local d = rx * lx + ry * ly + rz * lz
		rx, ry, rz = rx - d * lx, ry - d * ly, rz - d * lz
		rm = sqrt(rx * rx + ry * ry + rz * rz)
	end
	rx, ry, rz = rx / rm, ry / rm, rz / rm
	-- up = right x look
	local ux, uy, uz = ry * lz - rz * ly, rz * lx - rx * lz, rx * ly - ry * lx
	return cf(at.X, at.Y, at.Z, rx, ux, -lx, ry, uy, -ly, rz, uz, -lz)
end
R.lookAt = lookAt

local CFrame = {}
CFrame.identity = identity
function CFrame.new(a, b, c, ...)
	local n = select("#", ...)
	if a == nil then
		return identity
	elseif isV3(a) then
		if b ~= nil then
			if not isV3(b) then
				error("CFrame.new: second argument must be a Vector3", 2)
			end
			return lookAt(a, b)
		end
		return cf(a.X, a.Y, a.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	elseif n == 9 then
		local r = { ... }
		return cf(a, b, c, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
	elseif n == 4 then
		-- quaternion form
		local qx, qy, qz, qw = ...
		return fromQuat(a, b, c, qw, qx, qy, qz)
	end
	num(a, "x")
	num(b, "y")
	num(c, "z")
	return cf(a, b, c, 1, 0, 0, 0, 1, 0, 0, 0, 1)
end
function CFrame.lookAt(at, target, up)
	if not isV3(at) or not isV3(target) then
		error("CFrame.lookAt expects Vector3 arguments", 2)
	end
	return lookAt(at, target, up)
end
CFrame.lookAlong = function(at, dir, up)
	return lookAt(at, at + dir, up)
end
function CFrame.Angles(rx, ry, rz)
	num(rx, "rx")
	num(ry, "ry")
	num(rz, "rz")
	return fromMatrixRows(0, 0, 0, m3mul(m3mul(rotX(rx), rotY(ry)), rotZ(rz)))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromEulerAnglesYXZ(rx, ry, rz)
	return fromMatrixRows(0, 0, 0, m3mul(m3mul(rotY(ry), rotX(rx)), rotZ(rz)))
end
CFrame.fromOrientation = CFrame.fromEulerAnglesYXZ
function CFrame.fromAxisAngle(axis, a)
	local u = axis.Unit
	local s = sin(a / 2)
	return fromQuat(0, 0, 0, cos(a / 2), u.X * s, u.Y * s, u.Z * s)
end
function CFrame.fromMatrix(pos, vx, vy, vz)
	vz = vz or vx:Cross(vy)
	return cf(pos.X, pos.Y, pos.Z, vx.X, vy.X, vz.X, vx.Y, vy.Y, vz.Y, vx.Z, vy.Z, vz.Z)
end
R.CFrame = CFrame

---------------------------------------------------------------- Color3
local C3 = {}
local C3MT = {}
TYPE[C3MT] = "Color3"
local function c3(r, g, b)
	return setmetatable({ R = r, G = g, B = b }, C3MT)
end
R.c3 = c3
C3MT.__index = function(_, k)
	if k == "r" or k == "g" or k == "b" then
		return nil
	end
	local m = C3[k]
	if m then
		return m
	end
	error(tostring(k) .. " is not a valid member of Color3", 2)
end
C3MT.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
C3MT.__tostring = function(c)
	return string.format("%g, %g, %g", c.R, c.G, c.B)
end
function C3.Lerp(a, b, t)
	return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
function C3.ToHex(c)
	return string.format("%02X%02X%02X", floor(c.R * 255 + 0.5), floor(c.G * 255 + 0.5), floor(c.B * 255 + 0.5))
end
local function toHSV(c)
	local r, g, b = c.R, c.G, c.B
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local h, s, v = 0, 0, mx
	local d = mx - mn
	if mx > 0 then
		s = d / mx
	end
	if d > 0 then
		if mx == r then
			h = (g - b) / d % 6
		elseif mx == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h = h / 6
	end
	return h, s, v
end
function C3.ToHSV(c)
	return toHSV(c)
end
local Color3 = {
	new = function(r, g, b)
		return c3(r or 0, g or 0, b or 0)
	end,
	fromRGB = function(r, g, b)
		return c3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
	end,
	fromHSV = function(h, s, v)
		h = (h % 1) * 6
		local i = floor(h)
		local f = h - i
		local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
		local r, g, b
		if i == 0 then
			r, g, b = v, t, p
		elseif i == 1 then
			r, g, b = q, v, p
		elseif i == 2 then
			r, g, b = p, v, t
		elseif i == 3 then
			r, g, b = p, q, v
		elseif i == 4 then
			r, g, b = t, p, v
		else
			r, g, b = v, p, q
		end
		return c3(r, g, b)
	end,
	toHSV = toHSV,
	fromHex = function(hex)
		hex = hex:gsub("#", "")
		return c3(tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255)
	end,
}
R.Color3 = Color3

---------------------------------------------------------------- BrickColor (minimal)
local BCMT = {}
TYPE[BCMT] = "BrickColor"
BCMT.__index = function(b, k)
	if k == "Color" then
		return rawget(b, "_c")
	elseif k == "Name" then
		return rawget(b, "_n")
	end
	error(tostring(k) .. " is not a valid member of BrickColor", 2)
end
local NAMED = {
	["Bright orange"] = c3(0.85, 0.52, 0.25), ["Bright blue"] = c3(0.05, 0.41, 0.67), ["Bright red"] = c3(0.77, 0.16, 0.11),
	["Medium stone grey"] = c3(0.64, 0.64, 0.64), ["Institutional white"] = c3(0.97, 0.97, 0.97), ["Really black"] = c3(0.07, 0.07, 0.07),
}
R.BrickColor = {
	new = function(x)
		if type(x) == "string" then
			return setmetatable({ _c = NAMED[x] or c3(0.64, 0.64, 0.64), _n = x }, BCMT)
		end
		return setmetatable({ _c = c3(0.64, 0.64, 0.64), _n = "Medium stone grey" }, BCMT)
	end,
	Random = function()
		return setmetatable({ _c = c3(math.random(), math.random(), math.random()), _n = "Random" }, BCMT)
	end,
}

---------------------------------------------------------------- UDim / UDim2
local UDMT = {}
TYPE[UDMT] = "UDim"
local function udim(s, o)
	return setmetatable({ Scale = s, Offset = o }, UDMT)
end
UDMT.__add = function(a, b)
	return udim(a.Scale + b.Scale, a.Offset + b.Offset)
end
UDMT.__sub = function(a, b)
	return udim(a.Scale - b.Scale, a.Offset - b.Offset)
end
UDMT.__eq = function(a, b)
	return a.Scale == b.Scale and a.Offset == b.Offset
end
UDMT.__index = function(_, k)
	error(tostring(k) .. " is not a valid member of UDim", 2)
end
R.UDim = {
	new = function(s, o)
		return udim(s or 0, o or 0)
	end,
}
local U2 = {}
local U2MT = {}
TYPE[U2MT] = "UDim2"
local function udim2(xs, xo, ys, yo)
	return setmetatable({ X = udim(xs, xo), Y = udim(ys, yo) }, U2MT)
end
U2MT.__index = function(u, k)
	if k == "Width" then
		return rawget(u, "X")
	elseif k == "Height" then
		return rawget(u, "Y")
	end
	local m = U2[k]
	if m then
		return m
	end
	error(tostring(k) .. " is not a valid member of UDim2", 2)
end
U2MT.__add = function(a, b)
	return udim2(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
U2MT.__sub = function(a, b)
	return udim2(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset)
end
U2MT.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
U2MT.__tostring = function(u)
	return string.format("{%g, %g}, {%g, %g}", u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset)
end
function U2.Lerp(a, b, t)
	return udim2(a.X.Scale + (b.X.Scale - a.X.Scale) * t, a.X.Offset + (b.X.Offset - a.X.Offset) * t, a.Y.Scale + (b.Y.Scale - a.Y.Scale) * t, a.Y.Offset + (b.Y.Offset - a.Y.Offset) * t)
end
R.UDim2 = {
	new = function(xs, xo, ys, yo)
		if getmetatable(xs) == UDMT then
			return setmetatable({ X = xs, Y = xo }, U2MT)
		end
		return udim2(xs or 0, xo or 0, ys or 0, yo or 0)
	end,
	fromScale = function(x, y)
		return udim2(x or 0, 0, y or 0, 0)
	end,
	fromOffset = function(x, y)
		return udim2(0, x or 0, 0, y or 0)
	end,
}

---------------------------------------------------------------- Rect, NumberRange
local RectMT = {}
TYPE[RectMT] = "Rect"
RectMT.__index = function(r, k)
	if k == "Width" then
		return r.Max.X - r.Min.X
	elseif k == "Height" then
		return r.Max.Y - r.Min.Y
	end
	error(tostring(k) .. " is not a valid member of Rect", 2)
end
R.Rect = {
	new = function(a, b, c, d)
		if type(a) == "number" then
			return setmetatable({ Min = v2(a, b), Max = v2(c, d) }, RectMT)
		end
		return setmetatable({ Min = a or v2(0, 0), Max = b or v2(0, 0) }, RectMT)
	end,
}
local NRMT = {}
TYPE[NRMT] = "NumberRange"
NRMT.__index = function(_, k)
	error(tostring(k) .. " is not a valid member of NumberRange", 2)
end
R.NumberRange = {
	new = function(a, b)
		num(a, "min")
		return setmetatable({ Min = a, Max = b or a }, NRMT)
	end,
}

---------------------------------------------------------------- sequences
local NSKMT = {}
TYPE[NSKMT] = "NumberSequenceKeypoint"
NSKMT.__index = function(_, k)
	error(tostring(k) .. " is not a valid member of NumberSequenceKeypoint", 2)
end
R.NumberSequenceKeypoint = {
	new = function(t, v, e)
		num(t, "time")
		num(v, "value")
		return setmetatable({ Time = t, Value = v, Envelope = e or 0 }, NSKMT)
	end,
}
local NSMT = {}
TYPE[NSMT] = "NumberSequence"
NSMT.__index = function(_, k)
	error(tostring(k) .. " is not a valid member of NumberSequence", 2)
end
R.NumberSequence = {
	new = function(a, b)
		local kps
		if type(a) == "number" then
			kps = { R.NumberSequenceKeypoint.new(0, a), R.NumberSequenceKeypoint.new(1, b or a) }
		elseif type(a) == "table" then
			kps = a
			if #kps < 2 or kps[1].Time ~= 0 or kps[#kps].Time ~= 1 then
				error("NumberSequence: keypoints must start at time 0 and end at time 1", 2)
			end
			for i = 2, #kps do
				if kps[i].Time < kps[i - 1].Time then
					error("NumberSequence: keypoints must be ordered by time", 2)
				end
			end
		else
			error("NumberSequence.new: bad argument", 2)
		end
		return setmetatable({ Keypoints = kps }, NSMT)
	end,
}
local CSKMT = {}
TYPE[CSKMT] = "ColorSequenceKeypoint"
CSKMT.__index = function(_, k)
	error(tostring(k) .. " is not a valid member of ColorSequenceKeypoint", 2)
end
R.ColorSequenceKeypoint = {
	new = function(t, c)
		num(t, "time")
		if getmetatable(c) ~= C3MT then
			error("ColorSequenceKeypoint.new: Color3 expected", 2)
		end
		return setmetatable({ Time = t, Value = c }, CSKMT)
	end,
}
local CSMT = {}
TYPE[CSMT] = "ColorSequence"
CSMT.__index = function(_, k)
	error(tostring(k) .. " is not a valid member of ColorSequence", 2)
end
R.ColorSequence = {
	new = function(a, b)
		local kps
		if getmetatable(a) == C3MT then
			kps = { R.ColorSequenceKeypoint.new(0, a), R.ColorSequenceKeypoint.new(1, b or a) }
		elseif type(a) == "table" then
			kps = a
			if #kps < 2 or kps[1].Time ~= 0 or kps[#kps].Time ~= 1 then
				error("ColorSequence: keypoints must start at time 0 and end at time 1", 2)
			end
		else
			error("ColorSequence.new: bad argument", 2)
		end
		return setmetatable({ Keypoints = kps }, CSMT)
	end,
}
function R.evalNumberSequence(ns, t)
	local k = ns.Keypoints
	for i = 2, #k do
		if t <= k[i].Time then
			local a, b = k[i - 1], k[i]
			local span = b.Time - a.Time
			local f = span > 0 and (t - a.Time) / span or 0
			return a.Value + (b.Value - a.Value) * f
		end
	end
	return k[#k].Value
end
function R.evalColorSequence(cs, t)
	local k = cs.Keypoints
	for i = 2, #k do
		if t <= k[i].Time then
			local a, b = k[i - 1], k[i]
			local span = b.Time - a.Time
			local f = span > 0 and (t - a.Time) / span or 0
			return a.Value:Lerp(b.Value, f)
		end
	end
	return k[#k].Value
end

---------------------------------------------------------------- TweenInfo
local TIMT = {}
TYPE[TIMT] = "TweenInfo"
TIMT.__index = function(_, k)
	error(tostring(k) .. " is not a valid member of TweenInfo", 2)
end
R.TweenInfo = {
	new = function(time, style, dir, repeatCount, reverses, delay)
		return setmetatable({
			Time = time or 1,
			EasingStyle = style or R.Enum.EasingStyle.Quad,
			EasingDirection = dir or R.Enum.EasingDirection.Out,
			RepeatCount = repeatCount or 0,
			Reverses = reverses or false,
			DelayTime = delay or 0,
		}, TIMT)
	end,
}

---------------------------------------------------------------- Random
local RandMT = {}
TYPE[RandMT] = "Random"
local RandM = {}
RandMT.__index = RandM
local function rnext(r)
	-- xorshift-ish LCG on doubles, deterministic per seed
	r._s = (r._s * 1103515245 + 12345) % 2147483648
	return r._s / 2147483648
end
function RandM.NextNumber(r, a, b)
	local x = rnext(r)
	if a then
		return a + (b - a) * x
	end
	return x
end
function RandM.NextInteger(r, a, b)
	if math.type(a) ~= "integer" and a ~= floor(a) then
		error("NextInteger expects integers", 2)
	end
	return floor(a + rnext(r) * (b - a + 1))
end
function RandM.NextUnitVector(r)
	local z = rnext(r) * 2 - 1
	local t = rnext(r) * 2 * math.pi
	local s = sqrt(1 - z * z)
	return v3(s * cos(t), s * sin(t), z)
end
function RandM.Shuffle(r, t)
	for i = #t, 2, -1 do
		local j = RandM.NextInteger(r, 1, i)
		t[i], t[j] = t[j], t[i]
	end
end
function RandM.Clone(r)
	return setmetatable({ _s = r._s }, RandMT)
end
R.RandomSeed = 1
R.Random = {
	new = function(seed)
		R.RandomSeed = R.RandomSeed + 7919
		return setmetatable({ _s = floor((seed or R.RandomSeed) * 9301 + 49297) % 2147483648 }, RandMT)
	end,
}

---------------------------------------------------------------- Ray (legacy) / Font / PhysicalProperties / Axes
local RayMT = {}
TYPE[RayMT] = "Ray"
RayMT.__index = function(r, k)
	if k == "Unit" then
		return setmetatable({ Origin = r.Origin, Direction = r.Direction.Unit }, RayMT)
	end
	error(tostring(k) .. " is not a valid member of Ray", 2)
end
R.Ray = {
	new = function(o, d)
		return setmetatable({ Origin = o, Direction = d }, RayMT)
	end,
}
local FontMT = {}
TYPE[FontMT] = "Font"
R.Font = {
	new = function(family, weight, style)
		return setmetatable({ Family = family, Weight = weight, Style = style }, FontMT)
	end,
	fromEnum = function(e)
		return setmetatable({ Family = e.Name }, FontMT)
	end,
	fromName = function(n)
		return setmetatable({ Family = n }, FontMT)
	end,
}
local PPMT = {}
TYPE[PPMT] = "PhysicalProperties"
R.PhysicalProperties = {
	new = function(d, f, e, fw, ew)
		return setmetatable({ Density = d, Friction = f, Elasticity = e, FrictionWeight = fw, ElasticityWeight = ew }, PPMT)
	end,
}
R.NaN = NaN
