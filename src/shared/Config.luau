--!nocheck
-- EB: Proxima — shared combat constants (values from the Ability Compendium "Combat foundation").
-- All gameplay distances in the compendium are metres; METRE converts them to studs.

local Config = {}

Config.METRE = 3 -- studs per metre

-- Health / resources
Config.MAX_HEALTH = 1000
Config.MAX_ENERGY = 100
Config.ENERGY_REGEN = 12 -- per second
Config.ENERGY_REGEN_DELAY = 1.25
Config.MAX_HEAT = 100
Config.HEAT_COOL = 8 -- per second
Config.HEAT_COOL_DELAY = 1.25
Config.HEAT_STRESS = 70
Config.MAX_PROXIMA = 100
Config.P60 = 60
Config.P60_EXTRA_HEAT = 6
Config.ULT_HEAT = 30
Config.UNSTABLE_MIN_HEAT = 60
Config.UNSTABLE_HOLD = 1.0
Config.UNSTABLE_EXTRA_HEAT = 40
Config.BURNOUT_TIME = 3
Config.BURNOUT_END_HEAT = 40

-- Proxima gain / loss
-- PACING TUNE (deviation from the compendium, documented in README): compendium values were
-- CONTEST_WINDOW 4, P_DECAY_DELAY 3, P_DECAY_RATE 6. Softened so sustained fights reliably reach ultimates.
Config.CONTEST_WINDOW = 6
Config.P_NEAR_RANGE = 6 -- metres
Config.P_NEAR_RATE = 4
Config.P_FAR_RANGE = 12
Config.P_FAR_RATE = 2
Config.P_HIT_GAIN = 3
Config.P_PERFECT_GUARD_GAIN = 5
Config.P_PERFECT_GUARD_ICD = 2
Config.P_SUPPORT_GAIN = 3
Config.P_MAX_PER_SECOND = 10
Config.P_DECAY_DELAY = 5
Config.P_DECAY_RATE = 3

-- Movement (metres / second)
Config.RUN_SPEED = 6
Config.JUMP_HEIGHT = 2
Config.MAX_SLOW = 0.40
Config.MAX_SPEED_BONUS = 0.25

-- Basic attack
Config.BASIC_RANGE = 2.5
Config.BASIC_DAMAGE = 60
Config.BASIC_INTERVAL = 0.65
Config.BASIC_ARC = 100

-- Dodge
Config.DODGE_CHARGES = 2
Config.DODGE_DISTANCE = 5
Config.DODGE_TIME = 0.3
Config.DODGE_RECHARGE = 5
Config.DODGE_IFRAME_START = 0.06
Config.DODGE_IFRAME_LEN = 0.12

-- Guard
Config.MAX_GUARD = 100
Config.GUARD_REDUCTION = 0.70
Config.GUARD_ARC = 120
Config.GUARD_DRAIN = 4
Config.GUARD_HIT_DRAIN = 0.20
Config.GUARD_RECOVER_DELAY = 1.5
Config.GUARD_RECOVER = 20
Config.GUARD_BREAK_TIME = 0.7
Config.GUARD_BREAK_RETURN = 30
Config.PERFECT_GUARD_WINDOW = 0.2
Config.PERFECT_GUARD_REDUCTION = 0.90
Config.MAX_COMBINED_REDUCTION = 0.85
Config.GUARD_MOVE_MULT = 0.75

-- Casting
Config.DEFAULT_RECOVERY = 0.35
Config.MOVE_RECOVERY = 0.25
Config.ULT_INTERRUPT_REFUND_P = 50
Config.ULT_INTERRUPT_CD = 20

-- Protection / healing / control
Config.MAX_SHIELD = 400
Config.HEAL_CAP_PER_SECOND = 250
Config.MAX_REINFORCE_LAYERS = 2
Config.MAX_REINFORCE = 100
Config.CONTROL_BUDGET = 2
Config.CONTROL_WINDOW = 6
Config.CONTROL_IMMUNITY = 2

-- Projectiles / objects
Config.PROJ_SPEED = 24
Config.PROJ_WIDTH = 0.3
Config.FIELD_TICK = 1
Config.OBJECT_DURABILITY = 100
Config.OBJECT_LIFETIME = 6
Config.MAX_OBJECTS_PER_CASTER = 8
Config.SUMMON_SPEED = 6

-- Out of bounds
Config.OOB_PENALTY = 150
Config.OOB_LOCK = 1

-- Match
Config.RESPAWN_TIME = 4
Config.SPAWN_PROTECTION = 2.5
Config.DEFAULT_KIT = "Acid"
Config.DUMMIES_COUNT_AS_REAL = true -- training dummies and bots can feed Proxima for practice
Config.START_SYNERGY = true
Config.MAX_BOTS = 8

-- Body hitbox (studs)
Config.BODY_RADIUS = 1.5
Config.BODY_DOWN = 2.6
Config.BODY_UP = 2.0

return Config
