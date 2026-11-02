-- 54 Love — Chosen bonds and shared defensive costs
local K = require(script.Parent.Parent.Core.K)
local S = K.S

local Kit = { passive = {} }
local PINK = Color3.fromRGB(255, 90, 140)

local function partner(f)
	local p = f.state.partner
	if p and K.alive(p) and not (f.state.brokenUntil and f.state.brokenUntil > K.now()) then
		return p
	end
	return nil
end

local function bond(f, ally)
	if f.state.partnerHook then
		f.state.partnerHook()
		f.state.partnerHook = nil
	end
	f.state.partner = ally
	if ally then
		-- a quarter of healing the partner receives may transfer to the Love player instead (never duplicated)
		f.state.partnerHook = K.hook(ally, "beforeHeal", function(a, info)
			if info.opts.loveTransfer or not K.alive(f) then
				return
			end
			if f.health / f.maxHealth < a.health / a.maxHealth then
				local share = info.amount * 0.25
				info.amount -= share
				K.heal(f, f, share, { loveTransfer = true, noProxima = true })
			end
		end)
		K.FX.beam(f.root.Position, ally.root.Position, 0.2, PINK, 0.6)
	end
	K.res(f, "Bond", ally and ally.name or "none (V to bond)", nil, 1)
end

-- Passive: Mutual Bond — V bonds the ally under your aim (within 18 m)
function Kit.passive.init(f)
	bond(f, nil)
end
function Kit.passive.cleanup(f)
	if f.state.partnerHook then
		f.state.partnerHook()
	end
end
function Kit.action(f)
	local c = S.Cast.newCtx(f, 1, f.kitData.moves[1])
	local a = c:ally(18)
	if a and not a.isSummon then
		bond(f, a)
		K.notify(f, "Bonded with " .. a.name)
	else
		K.notify(f, "No ally to bond within 18 m")
	end
end
function Kit.passive.beforeHeal(f, info)
	local p = partner(f)
	if p and not info.opts.loveTransfer and p.health / p.maxHealth < f.health / f.maxHealth then
		local share = info.amount * 0.25
		info.amount -= share
		K.heal(f, p, share, { loveTransfer = true, noProxima = true })
	end
end
function Kit.passive.tick(f)
	local p = f.state.partner
	if p then
		if not K.alive(p) then
			bond(f, nil)
		elseif K.dist(f, p) > 24 and not (f.state.brokenUntil and f.state.brokenUntil > K.now()) then
			f.state.brokenUntil = K.now() + 2
			K.notify(f, "Bond strained (24 m)")
		end
	end
end

local function needPartner(c)
	if partner(c.f) then
		return true
	end
	return false, "No bonded partner (press V)"
end

-- 1 Heartline
Kit[1] = function(c)
	local f = c.f
	local p = partner(f)
	K.proj(c, {
		range = 18,
		width = 0.6,
		color = PINK,
		dmg = 60,
		allies = true,
		homing = (c.p60 and p and K.los(f, p)) and p or nil,
		turnRate = 60,
		ally = function(t)
			K.heal(c, t, t == p and 70 or 50)
			return nil
		end,
	})
end

-- 2 Come Back Safe
Kit.requires = { [2] = needPartner, [3] = needPartner, [4] = function(c)
	local p = partner(c.f)
	if p and K.dist(c.f, p) <= 12 and K.los(c.f, p) then
		return true
	end
	return false, "Partner must be visible within 12 m"
end }
Kit[2] = function(c)
	local f = c.f
	local p = partner(f)
	K.shield(c, p, 100, 3, "ComeBackSafe")
	local mark = c:feet()
	local beacon = K.FX.sphere(mark + Vector3.new(0, 1, 0), 0.8, PINK, 3, 0.2)
	local _ = beacon
	-- the partner may answer by dodging: their dodge becomes a 6 m dash toward the mark
	local rm
	rm = K.hook(p, "dodge", function(a)
		rm()
		local d = K.flat(mark - a.root.Position)
		S.Fighter.dash(a, d, math.min(K.m(6), K.flatDist(mark, a) * K.M), 0.3)
	end, 3)
	if c.p60 then
		c:recast(3, function(c2)
			local d = K.flat(mark - f.root.Position)
			K.dash(c2, d, math.min(6, K.flatDist(mark, f)), 0.3)
		end)
	end
end

-- 3 Shared Burden
Kit[3] = function(c)
	local f = c.f
	local p = partner(f)
	local budget = 120
	K.res(f, "Burden", budget, 120, 2)
	K.hook(p, "beforeHealth", function(_, info)
		if budget <= 0 or not K.alive(f) or info.opts.tag == "burden" then
			return
		end
		local share = math.min(budget, info.final * 0.25)
		budget -= share
		info.final -= share
		local applied = c.p60 and share * 0.8 or share
		K.Combat.damage(info.src, f, applied, { kind = "true", pierceShield = true, tag = "burden" })
		K.res(f, "Burden", math.floor(budget), 120, 2)
	end, 4)
	K.after(4, function()
		K.clearRes(f, "Burden")
	end)
end

-- 4 Sever the Threat
Kit[4] = function(c)
	local f = c.f
	local p = partner(f)
	K.FX.ring(K.feet(p), K.m(3), PINK, 0.4, 0.5)
	for _, t in ipairs(K.enemiesIn(c, p.root.Position, 3)) do
		K.dmg(c, t, 110, { fromPos = p.root.Position })
		K.knock(c, t, p.root.Position, 2)
	end
	if c.p60 then
		K.cleanse(p, "slow", 1)
	end
end

-- 5 No One Falls Alone (ultimate)
Kit[5] = function(c)
	local f = c.f
	local links = {}
	local p = partner(f)
	if p then
		table.insert(links, p)
	end
	for _, a in ipairs(K.alliesIn(c, f.root.Position, 18, true)) do
		if #links >= 3 then
			break
		end
		if not table.find(links, a) and not a.isSummon then
			table.insert(links, a)
		end
	end
	local pool = c.unstable and 650 or 450
	local function distribute(total)
		local missing = 0
		for _, a in ipairs(links) do
			missing += math.max(1, a.maxHealth - a.health)
		end
		for _, a in ipairs(links) do
			if K.alive(a) then
				local share = total * math.max(1, a.maxHealth - a.health) / missing
				K.Combat.removeShield(a, "NoOneFalls")
				K.shield(c, a, share, 6, "NoOneFalls")
				K.FX.beam(f.root.Position, a.root.Position, 0.2, PINK, 0.5)
			end
		end
	end
	distribute(pool)
	if c.unstable then
		local absorbed = 0
		for _, a in ipairs(links) do
			if a ~= f then
				K.hook(a, "beforeHealth", function(_, info)
					if absorbed < 150 and K.alive(f) then
						local take = math.min(150 - absorbed, info.final)
						absorbed += take
						info.final -= take
						K.Combat.damage(info.src, f, take, { kind = "true", pierceShield = true, tag = "unconditional" })
					end
				end, 6)
			end
		end
	end
	c:recast(6, function()
		local remaining = 0
		for _, a in ipairs(links) do
			for _, sh in ipairs(a.shields) do
				if sh.name == "NoOneFalls" then
					remaining += sh.amount
				end
			end
		end
		distribute(remaining)
	end)
end

return Kit
