-- Bespoke choreography for the eight showcase powers (filled in Stage 3). Hooks return true when they
-- fully handled a cue so the family defaults are skipped.
local Showcase = {}
local ctx

function Showcase.cast(_d, _st)
	return false
end

function Showcase.release(_d, _st, _hand)
	return false
end

function Showcase.init(c)
	ctx = c
	local _ = ctx
end

return Showcase
