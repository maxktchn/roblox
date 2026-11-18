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
--   Projectile - fires Count shots at the nearest enemies (Toaster). Optional: Pierce (a shot
--                hits that many enemies before it stops), Spread (shots fan out from the
--                nearest enemy's direction instead), Slow/Freeze on hit, Slick (Ice Cube Tray,
--                Deep Freeze, Buttered Barrage, #132)
--   Pulse      - every Cooldown, a ring grows out from where the chef stands, hitting each
--                enemy once as it passes and knocking it back (Microwave Pulse, a boss power)
--   Lob        - every Cooldown, lobs Count eggs at the nearest enemies; each lands where its
--                enemy was (RunRules.LobFlightSeconds later) and splashes everything within
--                Radius (Egg Grenade, #129)
--   Bounce     - every Cooldown, throws Count discs at the nearest enemies; after each hit a
--                disc flies on to the nearest enemy it hasn't hit within BounceRange, up to
--                Bounces times. All discs of one throw share one hit list (Pizza Cutter, #130)
--   Trail      - while the chef walks, drops a flat splat behind them every Cooldown; enemies
--                on any splat are slowed by Slow and take Damage every RunRules.TrailTickSeconds
--                (Squeeze Bottle, #131). Always on, like Orbit.
export type Shape = "Arc" | "Aura" | "Orbit" | "Projectile" | "Pulse" | "Lob" | "Bounce" | "Trail"

-- Projectile only: a butter slick left wherever a shot hits (Buttered Barrage, #132). It's a
-- splat like a Trail's, with no damage.
export type Slick = {
	Width: number,
	Seconds: number,
	Slow: number,
}

-- Lob only: when an egg lands, Count mini-eggs pop out evenly round it, land Distance studs
-- away (RunRules.LobClusterSeconds later) and splash again (Breakfast Bomb, #129).
export type Cluster = {
	Count: number,
	Distance: number,
	Damage: number,
	Radius: number,
}

-- Numbers for one weapon level. Levels[1] is Lv 1, Levels[5] is Lv 5.
-- What Cooldown and Range mean depends on the shape:
export type WeaponLevel = {
	Damage: number, -- per hit, before Hot Sauce and crits
	-- Arc / Projectile / Pulse / Lob / Bounce: seconds between attacks. Trail: seconds between splats.
	-- Aura: seconds between damage ticks. Orbit: seconds before one enemy can be hit again.
	Cooldown: number,
	-- Arc: reach. Aura: circle radius. Orbit: radius the objects circle at.
	-- Pulse: how far the ring grows.
	-- Projectile: how far it looks for targets, and how far shots fly.
	Range: number,
	ArcDegrees: number?, -- Arc: width of the slice
	Count: number?, -- Orbit: objects circling. Projectile: shots per attack. Lob: eggs. Bounce: discs.
	Speed: number?, -- Orbit: degrees per second. Projectile / Pulse / Bounce: studs per second.
	BurnDps: number?, -- optional: burn damage per second after a hit
	BurnSeconds: number?, -- optional: how long the burn lasts
	CritBonus: number?, -- optional: extra crit chance for this weapon only (0.25 = +25%)
	Knockback: number?, -- optional: studs each hit pushes an enemy away (Pulse; bosses aren't pushed)
	-- optional: pulls enemies within Range toward the chef, in studs per second
	-- (no Phase 1 weapon since Smoothie Vortex was removed, #83). Works with any shape.
	-- Bosses are too heavy to pull.
	PullStrength: number?,
	Radius: number?, -- Lob: splash radius, measured to each enemy's edge
	Cluster: Cluster?, -- Lob: mini-eggs when an egg lands (see Cluster above)
	Bounces: number?, -- Bounce: how many times a disc flies on to another enemy after its first hit
	BounceRange: number?, -- Bounce: how far (to the next enemy's edge) a disc can fly on
	Width: number?, -- Trail: studs across one splat
	Seconds: number?, -- Trail: how long a splat stays
	Slow: number?, -- Trail: how much slower enemies on a splat move (0.3 = 30%). Projectile: slow on hit.
	SlowSeconds: number?, -- Projectile: how long its Slow lasts (1.5 if left out)
	Pierce: number?, -- Projectile: how many enemies one shot hits before it stops (1 if left out)
	PierceFalloff: number?, -- Projectile: each later enemy a shot hits takes this much less (0.4 = 100%, 60%, 36%)
	Spread: number?, -- Projectile: degrees between shots fanned toward the nearest enemy
	Freeze: number?, -- Projectile: seconds each enemy hit is frozen (Deep Freeze)
	FrozenBonus: number?, -- Projectile: extra damage frozen enemies take from everything (0.25 = +25%)
	Slick: Slick?, -- Projectile: a butter slick where each shot hits
	StillEvery: number?, -- Trail: also drop a splat this often while the chef stands still
	CanCrit: boolean?, -- Trail: its damage ticks can crit (burns and plain trails can't)
}

return {}
