-- 56 Magic — Flexible spell choices and preparation
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local VIOLET = Color3.fromRGB(190, 80, 255)
local PAGE = { [1] = "Bolt", [2] = "Ward", [3] = "Trick" }

-- Passive: Prepared Pages — Bolt, Ward and Trick in sequence restore 10 Energy once per cycle
function Kit.passive.init(f)
	f.state.seq = {}
	f.state.revised = {}
end
function Kit.passive.cast(f, c)
	if f.state.sealedUntil and f.state.sealedUntil > K.now() then
		return
	end
	local page = PAGE[c.slot]
	if not page then
		return
	end
	f.state.lastPage = c.slot
	table.insert(f.state.seq, page)
	if #f.state.seq > 3 then
		table.remove(f.state.seq, 1)
	end
	local s = f.state.seq
	if #s == 3 and s[1] ~= s[2] and s[2] ~= s[3] and s[1] ~= s[3] then
		K.addEnergy(f, 10)
		f.state.seq = {}
	end
	c.data.revised = f.state.revised[c.slot]
	f.state.revised[c.slot] = nil
	if f.state.p60Page == c.slot then
		f.state.p60Page = nil
		K.reduceCd(f, c.slot, 2)
	end
	local rv = {}
	for slot, on in pairs(f.state.revised) do
		if on then
			table.insert(rv, PAGE[slot])
		end
	end
	K.res(f, "Revised", #rv > 0 and table.concat(rv, ",") or "-", nil, 1)
end

Kit.requires = {
	[1] = function(c)
		if c.f.state.carrying then
			return false, "Carrying the ward"
		end
		return true
	end,
}

-- 1 Spellbolt (modifier = three 25-damage sparks)
Kit[1] = function(c)
	if c.data.revised then
		K.lob(c, { range = 22, speed = 20, width = 0.8, color = VIOLET, dmg = 90, land = function(pos)
			K.circle(c, pos, 1.5, { dmg = 0, color = VIOLET })
		end })
		return
	end
	if c.mod then
		local dir = c:dir3()
		for i = -1, 1 do
			K.proj(c, { dir = K.rotate(dir, i * 8), range = 22, width = 0.35, color = VIOLET, dmg = 25 })
		end
	else
		K.proj(c, { range = 22, width = 0.6, color = VIOLET, dmg = 75 })
	end
end

-- 2 Portable Ward (carried at walking speed; P60 recast drops it)
Kit[2] = function(c)
	local f = c.f
	if c.data.revised then
		local a = c:ally(10, true) or f
		K.every(0.5, 4, function()
			K.heal(c, a, 10)
			return true
		end)
		return
	end
	local plate = K.object(c, { name = "WardPlate", size = Vector3.new(3, 2.4, 0.3), hp = 150, duration = 4, color = VIOLET, material = Enum.Material.ForceField, transparency = 0.25 })
	f.state.carrying = true
	f.speedMult = 0.7
	local dropped = false
	local function drop()
		if dropped then
			return
		end
		dropped = true
		f.state.carrying = nil
		f.speedMult = 1
	end
	K.every(0.03, 4, function()
		if not plate.alive or not K.alive(f) then
			drop()
			return false
		end
		if not dropped then
			local d = K.flat(f.root.CFrame.LookVector)
			local p = f.root.Position + d * K.m(1.3)
			plate.part.CFrame = CFrame.lookAt(p, p + d)
		end
		return true
	end)
	K.after(4, drop)
	if c.p60 then
		c:recast(4, function()
			drop()
		end)
	end
end

-- 3 Rabbit Turn
Kit[3] = function(c)
	local f = c.f
	if c.data.revised then
		for _, t in ipairs(K.enemiesIn(c, f.root.Position, 3)) do
			K.knock(c, t, f.root.Position, 2)
		end
		K.FX.burst(f.root.Position, K.m(3), VIOLET, 0.3)
		return
	end
	local start = c:feet()
	local rabbit = K.object(c, { name = "RabbitDecoy", pos = start, size = Vector3.new(0.6, 0.8, 0.9), hp = 1, duration = 2, solid = false, color = Color3.fromRGB(245, 245, 245) })
	local side = K.flat(c:dir():Cross(Vector3.yAxis))
	local rel = (f.humanoid and f.humanoid.MoveDirection:Dot(side) or 1) >= 0 and 1 or -1
	K.dash(c, side * rel, 4, 0.2)
	K.FX.highlight(f.model, Color3.fromRGB(255, 255, 255), 0.3, 0.6)
	if c.p60 then
		local aim = c:aimPoint(6)
		K.after(0.2, function()
			if rabbit.alive then
				rabbit.part.CFrame = CFrame.new(K.ground(start:Lerp(aim, 0.5)) + Vector3.new(0, 0.4, 0))
			end
		end)
	end
end

-- 4 Spellbook Revision (modifier picks the next page in order instead of the last used one)
Kit[4] = function(c)
	local f = c.f
	local slot = f.state.lastPage or 1
	if c.mod then
		slot = slot % 3 + 1
	end
	f.state.revised[slot] = true
	K.setCd(f, slot, 0)
	if c.p60 then
		f.state.p60Page = slot
	end
	K.announce(f, PAGE[slot] .. " revised", VIOLET, 1)
	K.res(f, "Revised", PAGE[slot], nil, 1)
end

-- 5 Five Page Finale (ultimate)
Kit[5] = function(c)
	local f = c.f
	local pages = {
		function(cc)
			K.proj(cc, { range = 22, width = 0.7, color = VIOLET, dmg = 80 })
		end,
		function(cc)
			K.proj(cc, { range = 22, width = 0.7, color = VIOLET, dmg = 80 })
		end,
		function(cc)
			K.shield(cc, f, 120, 4, "FinaleWard")
		end,
		function(cc)
			K.FX.telegraph(cc:feet(), K.m(3), 0.3, VIOLET)
			task.wait(0.3)
			K.circle(cc, cc:feet(), 3, { dmg = 90, color = VIOLET })
		end,
		function(cc)
			K.dash(cc, cc:dir(), 4, 0.2)
		end,
	}
	if c.unstable then
		-- choose the order: each recast casts the next chosen page (modifier = defensive pages first)
		local remaining = { 1, 2, 3, 4, 5 }
		c:recast(5, function(c2)
			local idx = 1
			if c2.mod then
				for i, p in ipairs(remaining) do
					if p == 3 or p == 5 then
						idx = i
						break
					end
				end
			end
			local p = table.remove(remaining, idx)
			pages[p](c2)
			if #remaining > 0 then
				return "keep"
			end
			f.state.sealedUntil = K.now() + 4
			f.disabled = { [1] = true, [2] = true, [3] = true, [4] = true }
			K.after(4, function()
				f.disabled = nil
			end)
			return nil
		end, {
			onExpire = function()
				f.state.sealedUntil = K.now() + 4
				f.disabled = { [1] = true, [2] = true, [3] = true, [4] = true }
				K.after(4, function()
					f.disabled = nil
				end)
			end,
		})
		return
	end
	for _, page in ipairs(pages) do
		if not c:wait(0.8) then
			return -- interruption ends unused pages
		end
		page(c)
	end
end

return Kit
