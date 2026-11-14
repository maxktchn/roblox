--!strict
-- Types shared by every weapon config (Starters, Gadgets) and the code that uses them.
-- Types only, no code.
--
-- A weapon's Shape picks how it attacks. WeaponService has one function per shape,
-- so a new weapon only needs a config entry with one of these shapes (PRD §8.5).
--   Arc        - hits everything in a slice in front of the chef (Chef's Knife, Pepper Shaker)
--   Aura       - hits everything in a circle around the chef, every Cooldown (Blender)
--   Orbit      - Count objects circle the chef and hit what they touch (Spinning Forks)
--   Projectile - fires Count shots at the nearest enemies (Toaster)
export type Shape = "Arc" | "Aura" | "Orbit" | "Projectile"

-- Numbers for one weapon level. Levels[1] is Lv 1, Levels[5] is Lv 5.
-- What Cooldown and Range mean depends on the shape:
export type WeaponLevel = {
	Damage: number, -- per hit, before Hot Sauce and crits
	-- Arc / Projectile: seconds between attacks.
	-- Aura: seconds between damage ticks. Orbit: seconds before one enemy can be hit again.
	Cooldown: number,
	-- Arc: reach. Aura: circle radius. Orbit: radius the objects circle at.
	-- Projectile: how far it looks for targets, and how far shots fly.
	Range: number,
	ArcDegrees: number?, -- Arc: width of the slice
	Count: number?, -- Orbit: objects circling. Projectile: shots per attack.
	Speed: number?, -- Orbit: degrees per second. Projectile: studs per second.
	BurnDps: number?, -- optional: burn damage per second after a hit
	BurnSeconds: number?, -- optional: how long the burn lasts
}

return {}
