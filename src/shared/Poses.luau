--!nocheck
-- Shared emission points. The server spawns projectiles/beams from these hand positions and the client
-- animator reaches the matching hand to the same point, so effects leave the hands, not the torso.
-- Offsets are in the caster's aim frame: X right, Y up, Z forward (studs, relative to the root).
local Poses = {}

Poses.HAND = {
	right = Vector3.new(1.05, 0.55, 1.75),
	left = Vector3.new(-1.05, 0.55, 1.75),
	both = Vector3.new(0, 0.7, 2.0),
	low = Vector3.new(0.6, -1.4, 1.6), -- ground strikes (stomp / slam)
}

-- which hand leads each slot (1-4 moves, 5 ultimate); basic attacks alternate in the animator
Poses.SLOT_HAND = { "right", "left", "right", "both", "both" }

function Poses.handFor(slot)
	return Poses.SLOT_HAND[slot or 1] or "right"
end

-- world position of a hand given root position and a flat aim direction
function Poses.handWorld(rootPos, aimFlat, hand)
	local f = Vector3.new(aimFlat.X, 0, aimFlat.Z)
	if f.Magnitude < 1e-3 then
		f = Vector3.new(0, 0, -1)
	end
	f = f.Unit
	local r = f:Cross(Vector3.yAxis)
	local o = Poses.HAND[hand] or Poses.HAND.right
	return rootPos + r * o.X + Vector3.yAxis * o.Y + f * o.Z
end

return Poses
