-- UI helpers and palette.
local Theme = {}

Theme.bg = Color3.fromRGB(18, 20, 28)
Theme.panel = Color3.fromRGB(28, 31, 42)
Theme.panel2 = Color3.fromRGB(38, 42, 56)
Theme.text = Color3.fromRGB(236, 238, 245)
Theme.dim = Color3.fromRGB(160, 165, 182)
Theme.accent = Color3.fromRGB(110, 190, 255)
Theme.health = Color3.fromRGB(90, 220, 110)
Theme.shield = Color3.fromRGB(140, 200, 255)
Theme.energy = Color3.fromRGB(80, 200, 255)
Theme.heat = Color3.fromRGB(255, 120, 50)
Theme.proxima = Color3.fromRGB(200, 120, 255)
Theme.guard = Color3.fromRGB(230, 230, 160)

function Theme.new(class, props, children)
	local o = Instance.new(class)
	if class == "Frame" or class == "TextLabel" or class == "TextButton" or class == "ScrollingFrame" or class == "TextBox" or class == "ImageLabel" then
		o.BorderSizePixel = 0
	end
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			o[k] = v
		end
	end
	for _, ch in ipairs(children or {}) do
		ch.Parent = o
	end
	if props and props.Parent then
		o.Parent = props.Parent
	end
	return o
end

function Theme.corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 6)
	c.Parent = parent
	return c
end

function Theme.stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(1, 1, 1)
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0.6
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function Theme.pad(parent, px)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.Parent = parent
	return p
end

function Theme.label(props)
	local defaults = {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextColor3 = Theme.text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	}
	for k, v in pairs(props) do
		defaults[k] = v
	end
	return Theme.new("TextLabel", defaults)
end

function Theme.button(props)
	local defaults = {
		BackgroundColor3 = Theme.panel2,
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.text,
		TextSize = 14,
		AutoButtonColor = true,
	}
	for k, v in pairs(props) do
		defaults[k] = v
	end
	local b = Theme.new("TextButton", defaults)
	Theme.corner(b, 6)
	return b
end

return Theme
