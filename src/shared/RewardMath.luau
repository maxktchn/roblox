--!strict
-- Run reward sums (P2-5 #106, design: docs/superpowers/specs/2026-11-21-run-rewards-design.md).
-- Shared so the server (RewardService) and the run-over banner read materials the same way.
-- Pure functions: no services, no state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gear = require(ReplicatedStorage.Config.Gear)
local RunRewards = require(ReplicatedStorage.Config.RunRewards)
local RunRules = require(ReplicatedStorage.Config.RunRules)

export type Payout = { Gold: number, Xp: number, MaterialDrops: number }

local RewardMath = {}

-- The 5 gear materials, sorted, so a seeded Random always rolls the same.
local MATERIALS: { string } = {}
for _, slot in Gear.Slots do
	table.insert(MATERIALS, slot.Material)
end
table.sort(MATERIALS)

-- What a run pays: seconds survived (capped at the run length; bad values count as 0), whether
-- it was won, and the chapter's RewardScale. Worked out, scaled, then rounded down.
function RewardMath.payout(seconds: number, won: boolean, scale: number): Payout
	local t = if type(seconds) == "number" and seconds == seconds and seconds > 0 then seconds else 0
	t = math.min(t, RunRules.RunLengthSeconds)
	local minutes = t / 60
	local gold = RunRewards.GoldPerMinute * minutes
	local xp = RunRewards.XpPerMinute * minutes
	local drops = RunRewards.MaterialDropsPerMinute * (t // 60)
	if won then
		gold += RunRewards.ClearBonus.Gold
		xp += RunRewards.ClearBonus.Xp
		drops += RunRewards.ClearBonus.MaterialDrops
	end
	return {
		Gold = math.floor(gold * scale),
		Xp = math.floor(xp * scale),
		MaterialDrops = math.max(math.floor(drops * scale), RunRewards.MinMaterialDrops),
	}
end

-- Roll `drops` materials, each one of the 5 with equal chance. Only rolled materials are keys.
function RewardMath.rollMaterials(drops: number, rng: Random): { [string]: number }
	local got: { [string]: number } = {}
	for _ = 1, drops do
		local material = MATERIALS[rng:NextInteger(1, #MATERIALS)]
		got[material] = (got[material] or 0) + 1
	end
	return got
end

-- Materials as attribute text, "HatPattern=3,Sharpener=4" (sorted); "" for none.
function RewardMath.formatMaterials(materials: { [string]: number }): string
	local parts = {}
	for material, count in materials do
		table.insert(parts, `{material}={count}`)
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

-- The other way: attribute text back to a table. Parts that aren't "Name=number" are skipped.
function RewardMath.parseMaterials(text: string): { [string]: number }
	local materials: { [string]: number } = {}
	for material, count in string.gmatch(text, "(%a+)=(%d+)") do
		materials[material] = tonumber(count) :: number
	end
	return materials
end

return RewardMath
