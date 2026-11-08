-- GUI layout (AbsolutePosition/AbsoluteSize) and scene snapshot export for renderers.
local R = ...
local DATA = R.DATA
local v2, v3 = R.v2, R.v3
local min, max = math.min, math.max

local function isGuiObject(obj)
	return R.classIsA(DATA[obj].cls, "GuiObject")
end
local function isLayer(obj)
	return R.classIsA(DATA[obj].cls, "LayerCollector")
end

local cache = nil
function R.layoutBegin()
	cache = {}
end
function R.layoutEnd()
	cache = nil
end

local function layoutOf(obj)
	for _, c in ipairs(DATA[obj].children) do
		local cn = DATA[c].cls.name
		if cn == "UIListLayout" or cn == "UIGridLayout" then
			return c
		end
	end
	return nil
end
local function childOfClass(obj, cn)
	for _, c in ipairs(DATA[obj].children) do
		if DATA[c].cls.name == cn then
			return c
		end
	end
	return nil
end
local function padOf(obj, w, h)
	local p = childOfClass(obj, "UIPadding")
	if not p then
		return 0, 0, 0, 0
	end
	local pp = DATA[p].props
	return pp.PaddingLeft.Scale * w + pp.PaddingLeft.Offset, pp.PaddingTop.Scale * h + pp.PaddingTop.Offset,
		pp.PaddingRight.Scale * w + pp.PaddingRight.Offset, pp.PaddingBottom.Scale * h + pp.PaddingBottom.Offset
end

local guiAbs
local function sortedChildren(obj)
	local list = {}
	for _, c in ipairs(DATA[obj].children) do
		if isGuiObject(c) and DATA[c].props.Visible then
			list[#list + 1] = c
		end
	end
	local lay = layoutOf(obj)
	local byName = lay and DATA[lay].props.SortOrder.Name == "Name"
	table.sort(list, function(a, b)
		local pa, pb = DATA[a].props, DATA[b].props
		if byName then
			return pa.Name < pb.Name
		end
		if pa.LayoutOrder == pb.LayoutOrder then
			return tostring(a) < tostring(b)
		end
		return pa.LayoutOrder < pb.LayoutOrder
	end)
	return list
end

-- raw size of a gui object given its parent content size (before layout placement)
local function rawSize(obj, pw, ph)
	local p = DATA[obj].props
	local s = p.Size
	local sx, sy = pw, ph
	if p.SizeConstraint and p.SizeConstraint.Name == "RelativeXX" then
		sy = pw
	elseif p.SizeConstraint and p.SizeConstraint.Name == "RelativeYY" then
		sx = ph
	end
	local w = s.X.Scale * sx + s.X.Offset
	local h = s.Y.Scale * sy + s.Y.Offset
	local auto = p.AutomaticSize and p.AutomaticSize.Name or "None"
	if auto ~= "None" then
		local cw, ch = 0, 0
		local pl, pt, pr, pb = padOf(obj, w, h)
		local lay = layoutOf(obj)
		if lay then
			local cs = R.layoutContentSize(lay, w - pl - pr, h - pt - pb)
			cw, ch = cs.X, cs.Y
		else
			for _, c in ipairs(DATA[obj].children) do
				if isGuiObject(c) and DATA[c].props.Visible then
					local rw, rh = rawSize(c, w - pl - pr, h - pt - pb)
					local cp = DATA[c].props.Position
					cw = max(cw, cp.X.Offset + rw)
					ch = max(ch, cp.Y.Offset + rh)
				end
			end
		end
		if type(p.Text) == "string" then
			local tb = R.textBounds(p, (auto == "Y") and (w - pl - pr) or nil)
			cw = max(cw, tb.X)
			ch = max(ch, tb.Y)
		end
		if auto == "X" or auto == "XY" then
			w = max(w, cw + pl + pr)
		end
		if auto == "Y" or auto == "XY" then
			h = max(h, ch + pt + pb)
		end
	end
	local sc = childOfClass(obj, "UISizeConstraint")
	if sc then
		local scp = DATA[sc].props
		w = min(max(w, scp.MinSize.X), scp.MaxSize.X)
		h = min(max(h, scp.MinSize.Y), scp.MaxSize.Y)
	end
	local ar = childOfClass(obj, "UIAspectRatioConstraint")
	if ar then
		local r = DATA[ar].props.AspectRatio
		if w / max(h, 1) > r then
			w = h * r
		else
			h = w / r
		end
	end
	return w, h
end
R.guiRawSize = rawSize

function R.textBounds(p, wrapWidth)
	local txt = (p.Text or ""):gsub("<[^>]+>", "")
	local size = p.TextSize or 14
	local cw = size * 0.52
	local lines = 0
	local longest = 0
	for l in (txt .. "\n"):gmatch("([^\n]*)\n") do
		local len = #l * cw
		if wrapWidth and p.TextWrapped and wrapWidth > 0 then
			local n = math.max(1, math.ceil(len / wrapWidth))
			lines = lines + n
			longest = max(longest, min(len, wrapWidth))
		else
			lines = lines + 1
			longest = max(longest, len)
		end
	end
	return v2(longest, lines * size * 1.2)
end

function R.layoutContentSize(lay, pw, ph)
	local parent = DATA[lay].parent
	if not parent then
		return v2(0, 0)
	end
	if not pw then
		local r = guiAbs(parent)
		pw, ph = r[2].X, r[2].Y
	end
	local lp = DATA[lay].props
	local kids = sortedChildren(parent)
	if DATA[lay].cls.name == "UIGridLayout" then
		local cs, cp = lp.CellSize, lp.CellPadding
		local cw, ch = cs.X.Scale * pw + cs.X.Offset, cs.Y.Scale * ph + cs.Y.Offset
		local px, py = cp.X.Scale * pw + cp.X.Offset, cp.Y.Scale * ph + cp.Y.Offset
		local per = max(1, math.floor((pw + px) / (cw + px)))
		local rows = math.ceil(#kids / per)
		return v2(min(#kids, per) * (cw + px) - px, rows * (ch + py) - py)
	end
	local vertical = lp.FillDirection.Name == "Vertical"
	local pad = lp.Padding.Scale * (vertical and ph or pw) + lp.Padding.Offset
	local total, cross = 0, 0
	for i, c in ipairs(kids) do
		local w, h = rawSize(c, pw, ph)
		if vertical then
			total = total + h + (i > 1 and pad or 0)
			cross = max(cross, w)
		else
			total = total + w + (i > 1 and pad or 0)
			cross = max(cross, h)
		end
	end
	return vertical and v2(cross, total) or v2(total, cross)
end

guiAbs = function(obj)
	if cache and cache[obj] then
		return cache[obj]
	end
	local d = DATA[obj]
	local res
	if d.cls.name == "ScreenGui" then
		local inset = d.props.IgnoreGuiInset and 0 or R.guiInset
		res = { v2(0, inset), v2(R.viewport.X, R.viewport.Y - inset) }
	elseif d.cls.name == "BillboardGui" then
		local s = d.props.Size
		res = { v2(0, 0), v2(s.X.Offset, s.Y.Offset) }
	elseif d.cls.name == "SurfaceGui" then
		res = { v2(0, 0), d.props.CanvasSize }
	elseif isGuiObject(obj) then
		local parent = d.parent
		local ppos, psize = v2(0, 0), v2(0, 0)
		if parent and (isGuiObject(parent) or isLayer(parent)) then
			local pr = guiAbs(parent)
			ppos, psize = pr[1], pr[2]
		end
		local pl, pt, prr, pb = 0, 0, 0, 0
		if parent and isGuiObject(parent) then
			pl, pt, prr, pb = padOf(parent, psize.X, psize.Y)
		end
		local cx, cy, cw, ch = ppos.X + pl, ppos.Y + pt, psize.X - pl - prr, psize.Y - pt - pb
		if parent and DATA[parent].cls.name == "ScrollingFrame" then
			local cp = DATA[parent].props.CanvasPosition
			cx, cy = cx - cp.X, cy - cp.Y
		end
		local w, h = rawSize(obj, cw, ch)
		local lay = parent and layoutOf(parent)
		local x, y
		if lay then
			local lp = DATA[lay].props
			local kids = sortedChildren(parent)
			if DATA[lay].cls.name == "UIGridLayout" then
				local cs, cp = lp.CellSize, lp.CellPadding
				local gw, gh = cs.X.Scale * cw + cs.X.Offset, cs.Y.Scale * ch + cs.Y.Offset
				local px, py = cp.X.Scale * cw + cp.X.Offset, cp.Y.Scale * ch + cp.Y.Offset
				local per = max(1, math.floor((cw + px) / (gw + px)))
				local idx = 0
				for i, k in ipairs(kids) do
					if k == obj then
						idx = i - 1
					end
				end
				w, h = gw, gh
				x = cx + (idx % per) * (gw + px)
				y = cy + math.floor(idx / per) * (gh + py)
			else
				local vertical = lp.FillDirection.Name == "Vertical"
				local pad = lp.Padding.Scale * (vertical and ch or cw) + lp.Padding.Offset
				local offs = 0
				local total = 0
				local sizes = {}
				for i, k in ipairs(kids) do
					local kw, kh = rawSize(k, cw, ch)
					sizes[k] = { kw, kh }
					total = total + (vertical and kh or kw) + (i > 1 and pad or 0)
				end
				local start
				if vertical then
					local va = lp.VerticalAlignment.Name
					start = va == "Center" and (ch - total) / 2 or (va == "Bottom" and ch - total or 0)
				else
					local ha = lp.HorizontalAlignment.Name
					start = ha == "Center" and (cw - total) / 2 or (ha == "Right" and cw - total or 0)
				end
				for _, k in ipairs(kids) do
					if k == obj then
						break
					end
					offs = offs + (vertical and sizes[k][2] or sizes[k][1]) + pad
				end
				if vertical then
					y = cy + start + offs
					local ha = lp.HorizontalAlignment.Name
					x = cx + (ha == "Center" and (cw - w) / 2 or (ha == "Right" and cw - w or 0))
				else
					x = cx + start + offs
					local va = lp.VerticalAlignment.Name
					y = cy + (va == "Center" and (ch - h) / 2 or (va == "Bottom" and ch - h or 0))
				end
			end
		else
			local p = d.props
			local pos, ap = p.Position, p.AnchorPoint
			x = cx + pos.X.Scale * cw + pos.X.Offset - ap.X * w
			y = cy + pos.Y.Scale * ch + pos.Y.Offset - ap.Y * h
		end
		res = { v2(x, y), v2(w, h) }
	else
		res = { v2(0, 0), v2(0, 0) }
	end
	if cache then
		cache[obj] = res
	end
	return res
end
R.guiAbs = guiAbs

---------------------------------------------------------------- GUI export
local function colorT(c)
	return { c.R, c.G, c.B }
end
local function visibleChain(obj)
	local o = obj
	while o do
		local d = DATA[o]
		local p = d.props
		if p.Visible == false or p.Enabled == false then
			return false
		end
		if d.cls.name == "ScreenGui" or d.cls.name == "PlayerGui" then
			return true
		end
		o = d.parent
	end
	return true
end
function R.exportGui(playerGui)
	R.layoutBegin()
	local out = {}
	local screens = {}
	for _, sg in ipairs(DATA[playerGui].children) do
		if DATA[sg].cls.name == "ScreenGui" and DATA[sg].props.Enabled then
			screens[#screens + 1] = sg
		end
	end
	table.sort(screens, function(a, b)
		return DATA[a].props.DisplayOrder < DATA[b].props.DisplayOrder
	end)
	local order = 0
	local function walk(obj, clip, depth)
		for _, c in ipairs(DATA[obj].children) do
			local cd = DATA[c]
			if isGuiObject(c) and cd.props.Visible then
				local r = guiAbs(c)
				local p = cd.props
				order = order + 1
				local item = {
					order = order, z = p.ZIndex, depth = depth, cls = cd.cls.name, name = p.Name,
					x = r[1].X, y = r[1].Y, w = r[2].X, h = r[2].Y,
					bg = colorT(p.BackgroundColor3), bgT = p.BackgroundTransparency, clip = clip,
				}
				local corner = childOfClass(c, "UICorner")
				if corner then
					local cr = DATA[corner].props.CornerRadius
					item.radius = cr.Scale * min(item.w, item.h) + cr.Offset
				end
				local stroke = childOfClass(c, "UIStroke")
				if stroke and DATA[stroke].props.Enabled then
					local sp = DATA[stroke].props
					item.stroke = { colorT(sp.Color), sp.Thickness, sp.Transparency }
				end
				local grad = childOfClass(c, "UIGradient")
				if grad and DATA[grad].props.Enabled then
					local gp = DATA[grad].props
					item.grad = { colorT(gp.Color.Keypoints[1].Value), colorT(gp.Color.Keypoints[#gp.Color.Keypoints].Value), gp.Rotation }
				end
				if type(p.Text) == "string" then
					item.text = (p.Text or ""):gsub("<[^>]+>", "")
					item.textColor = colorT(p.TextColor3)
					item.textT = p.TextTransparency
					item.textSize = p.TextSize
					item.scaled = p.TextScaled
					item.wrap = p.TextWrapped
					item.xa = p.TextXAlignment.Name
					item.ya = p.TextYAlignment.Name
					item.strokeT = p.TextStrokeTransparency
					item.font = p.Font.Name
				end
				if p.Image ~= nil and p.Image ~= "" then
					item.image = p.Image
					item.imageColor = colorT(p.ImageColor3)
					item.imageT = p.ImageTransparency
				end
				out[#out + 1] = item
				local nclip = clip
				if p.ClipsDescendants or cd.cls.name == "ScrollingFrame" then
					nclip = { item.x, item.y, item.w, item.h }
				end
				walk(c, nclip, depth + 1)
			end
		end
	end
	for _, sg in ipairs(screens) do
		walk(sg, nil, 0)
	end
	R.layoutEnd()
	return out
end

---------------------------------------------------------------- 3D export
local function rng(seed)
	local s = seed
	return function()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end
function R.exportScene(opts)
	opts = opts or {}
	local parts, beams, particles, lights, labels = {}, {}, {}, {}, {}
	for part in pairs(R.parts) do
		local d = DATA[part]
		local p = d.props
		local tr = p.Transparency + (p.LocalTransparencyModifier or 0)
		if tr < 0.99 then
			local c = d.cf
			parts[#parts + 1] = {
				shape = R.shapeOf(d), cf = { c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12] },
				size = { p.Size.X, p.Size.Y, p.Size.Z }, color = colorT(p.Color), t = tr, mat = p.Material.Name, name = p.Name,
			}
		end
	end
	for _, x in ipairs(R.descendants(R.workspace, {})) do
		local d = DATA[x]
		local cn = d.cls.name
		if cn == "Beam" and d.props.Enabled then
			local a0, a1 = d.props.Attachment0, d.props.Attachment1
			if a0 ~= R.NIL and a1 ~= R.NIL and a0 and a1 and DATA[a0] and DATA[a1] and R.inWorkspace(a0) and R.inWorkspace(a1) then
				local p0, p1 = a0.WorldPosition, a1.WorldPosition
				local col = R.evalColorSequence(d.props.Color, 0.5)
				beams[#beams + 1] = { p0 = { p0.X, p0.Y, p0.Z }, p1 = { p1.X, p1.Y, p1.Z }, w0 = d.props.Width0, w1 = d.props.Width1, color = colorT(col), t = R.evalNumberSequence(d.props.Transparency, 0.5), glow = d.props.LightEmission }
			end
		elseif cn == "ParticleEmitter" and (d.props.Enabled or d.bursts) then
			local parent = d.parent
			local origin, size, cf
			if parent and DATA[parent] then
				local pd = DATA[parent]
				if pd.cls.name == "Attachment" then
					cf = parent.WorldCFrame
					size = v3(0, 0, 0)
				elseif pd.cf then
					cf = pd.cf
					size = pd.props.Size
				end
			end
			if cf then
				local p = d.props
				local life = p.Lifetime.Max
				local r = rng((R.createdIndex and R.createdIndex[x]) or 7 + #particles * 13)
				local function sample(age)
					local o = cf * v3((r() - 0.5) * size.X, (r() - 0.5) * size.Y, (r() - 0.5) * size.Z)
					local en = p.EmissionDirection.Name
					local dirMap = { Top = v3(0, 1, 0), Bottom = v3(0, -1, 0), Front = v3(0, 0, -1), Back = v3(0, 0, 1), Right = v3(1, 0, 0), Left = v3(-1, 0, 0) }
					local dir = cf:VectorToWorldSpace(dirMap[en] or v3(0, 1, 0))
					local sx, sy = math.rad(p.SpreadAngle.X), math.rad(p.SpreadAngle.Y)
					local jitter = v3((r() * 2 - 1) * math.sin(sx), 0, (r() * 2 - 1) * math.sin(sy))
					dir = (dir + jitter)
					if dir.Magnitude > 0 then
						dir = dir.Unit
					end
					local speed = p.Speed.Min + (p.Speed.Max - p.Speed.Min) * r()
					local pos = o + dir * speed * age + p.Acceleration * (0.5 * age * age)
					local f = math.min(1, age / math.max(life, 0.01))
					local col = R.evalColorSequence(p.Color, f)
					particles[#particles + 1] = { pos = { pos.X, pos.Y, pos.Z }, size = R.evalNumberSequence(p.Size, f), t = R.evalNumberSequence(p.Transparency, f), color = colorT(col), glow = p.LightEmission }
				end
				if p.Enabled and p.Rate > 0 then
					local alive = math.min(p.Rate * math.min(life, R.now - (d.created or 0)), opts.maxPerEmitter or 40)
					for _ = 1, math.floor(alive) do
						sample(r() * life)
					end
				end
				for _, b in ipairs(d.bursts or {}) do
					local age = R.now - b.t
					if age >= 0 and age < life then
						for _ = 1, math.min(b.n, opts.maxPerEmitter or 40) do
							sample(age * (0.6 + 0.4 * r()))
						end
					end
				end
			end
		elseif (cn == "PointLight" or cn == "SpotLight" or cn == "SurfaceLight") and d.props.Enabled then
			local parent = d.parent
			local pos
			if parent and DATA[parent] then
				if DATA[parent].cls.name == "Attachment" then
					pos = parent.WorldPosition
				elseif DATA[parent].cf then
					pos = DATA[parent].cf.Position
				end
			end
			if pos then
				lights[#lights + 1] = { pos = { pos.X, pos.Y, pos.Z }, color = colorT(d.props.Color), range = d.props.Range, brightness = d.props.Brightness }
			end
		elseif cn == "BillboardGui" and d.props.Enabled and opts.labels then
			local ad = d.props.Adornee
			if ad == R.NIL then
				ad = nil
			end
			ad = ad or d.parent
			if ad and DATA[ad] and DATA[ad].cf then
				local pos = DATA[ad].cf.Position + d.props.StudsOffset
				local txt = {}
				for _, l in ipairs(R.descendants(x, {})) do
					local ld = DATA[l]
					if ld.props.Text and ld.props.Visible and ld.props.Text ~= "" then
						txt[#txt + 1] = ld.props.Text
					end
				end
				labels[#labels + 1] = { pos = { pos.X, pos.Y, pos.Z }, text = table.concat(txt, " | ") }
			end
		end
	end
	local cam = R.workspace.CurrentCamera
	local c = cam.CFrame
	local L = R.services.Lighting
	return {
		parts = parts, beams = beams, particles = particles, lights = lights, labels = labels,
		camera = { cf = { c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12] }, fov = cam.FieldOfView },
		lighting = L and { ambient = colorT(L.Ambient), outdoor = colorT(L.OutdoorAmbient), clock = L.ClockTime, brightness = L.Brightness, fogColor = colorT(L.FogColor), fogStart = L.FogStart, fogEnd = L.FogEnd } or nil,
		terrain = (function()
			local t = {}
			for _, reg in ipairs(R.terrainRegions) do
				local cc = reg.d.cf
				t[#t + 1] = { shape = reg.shape, cf = { cc[1], cc[2], cc[3], cc[4], cc[5], cc[6], cc[7], cc[8], cc[9], cc[10], cc[11], cc[12] }, size = { reg.d.props.Size.X, reg.d.props.Size.Y, reg.d.props.Size.Z }, mat = reg.material.Name }
			end
			return t
		end)(),
	}
end
