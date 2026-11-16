--!strict
-- Types shared by every weapon config (Starters, Gadgets, Recipes, BossPowers) and the code that uses them.
-- Types only, no code.
--
-- A weapon's Shape picks how it attacks. WeaponService has one function per shape,
-- so a new weapon only needs a config entry with one of these shapes (PRD §8.5).
--   Arc        - hits everything in a slice in front of the chef (Chef's Knife, Pepper Shaker)
--   Aura       - hits everything in a circle around the chef, every Cooldown (no Phase 1 weapon
--                uses it since the Blender was removed, #83; kept for later gadgets)
--   Orbit      - Count objects circle the chef and hit what they touch (Spinning Forks)
--   Projectile - fires Count shots at the nearest enemies (Toaster)
--   Pulse      - every Cooldown, a ring grows out from where the chef stands, hitting each
--                enemy once as it passes and knocking it back (Microwave Pulse, a boss power)
export type Shape = "Arc" | "Aura" | "Orbit" | "Projectile" | "Pulse"

-- Numbers for one weapon level. Levels[1] is Lv 1, Levels[5] is Lv 5.
-- What Cooldown and Range mean depends on the shape:
export type WeaponLevel = {
	Damage: number, -- per hit, before Hot Sauce and crits
	-- Arc / Projectile / Pulse: seconds between attacks.
	-- Aura: seconds between damage ticks. Orbit: seconds before one enemy can be hit again.
	Cooldown: number,
	-- Arc: reach. Aura: circle radius. Orbit: radius the objects circle at.
	-- Pulse: how far the ring grows.
	-- Projectile: how far it looks for targets, and how far shots fly.
	Range: number,
	ArcDegrees: number?, -- Arc: width of the slice
	Count: number?, -- Orbit: objects circling. Projectile: shots per attack.
	Speed: number?, -- Orbit: degrees per second. Projectile / Pulse: studs per second.
	BurnDps: number?, -- optional: burn damage per second after a hit
	BurnSeconds: number?, -- optional: how long the burn lasts
	CritBonus: number?, -- optional: extra crit chance for this weapon only (0.25 = +25%)
	Knockback: number?, -- optional: studs each hit pushes an enemy away (Pulse; bosses aren't pushed)
	-- optional: pulls enemies within Range toward the chef, in studs per second
	-- (no Phase 1 weapon since Smoothie Vortex was removed, #83). Works with any shape.
	-- Bosses are too heavy to pull.
	PullStrength: number?,
}

return {}
