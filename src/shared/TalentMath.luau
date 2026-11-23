--!strict
-- The talent path's sums (P2-7b #162), from Config/Talents. Used by the server (buying, effects)
-- and the client (the TALENTS tab, the run-over banner), so both always agree.
--
-- Nodes are bought in order, so "Bought" (how many) says exactly which ones are owned.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Talents = require(ReplicatedStorage.Config.Talents)

local TalentMath = {}

export type Node = {
	Number: number,
	Kind: Talents.Kind,
	Amount: number,
	Text: string,
	Special: boolean,
	Cost: number,
}

-- What every kind adds up to (all 0 with nothing bought).
export type Totals = {
	Attack: number,
	MaxHp: number,
	Armor: number,
	PieHealing: number,
	Reroll: number,
	StartingPie: number,
	FreePick: number,
	PickupRange: number,
	MoveSpeed: number,
}

-- Gold to buy node `number`.
function TalentMath.cost(number: number): number
	return Talents.Cost.Base + Talents.Cost.Step * (number - 1)
end

-- Node `number` (1 to Talents.MaxLevel), or nil if there's no such node.
function TalentMath.node(number: number): Node?
	if number < 1 or number > Talents.MaxLevel or number % 1 ~= 0 then
		return nil
	end
	local config = Talents.Specials[number]
	local special = config ~= nil
	if not config then
		-- Standard nodes before this one (specials skipped) pick the cycle entry.
		local standard = number - math.floor(number / Talents.SpecialEvery)
		config = Talents.StandardCycle[(standard - 1) % #Talents.StandardCycle + 1]
	end
	assert(config, "TalentMath.node: no config")
	return {
		Number = number,
		Kind = config.Kind,
		Amount = config.Amount,
		Text = config.Text,
		Special = special,
		Cost = TalentMath.cost(number),
	}
end

-- Everything the first `bought` nodes add up to.
function TalentMath.totals(bought: number): Totals
	local totals: Totals = {
		Attack = 0,
		MaxHp = 0,
		Armor = 0,
		PieHealing = 0,
		Reroll = 0,
		StartingPie = 0,
		FreePick = 0,
		PickupRange = 0,
		MoveSpeed = 0,
	}
	for number = 1, math.min(bought, Talents.MaxLevel) do
		local node = TalentMath.node(number)
		if node then
			local sums = totals :: any
			sums[node.Kind] += node.Amount
		end
	end
	return totals
end

-- Can the next node be bought: unlocked by the account level, and enough gold?
function TalentMath.canBuyNext(level: number, bought: number, gold: number): boolean
	local nextNumber = bought + 1
	return nextNumber <= Talents.MaxLevel and nextNumber <= level and gold >= TalentMath.cost(nextNumber)
end

-- "+12%" from 0.12 (rounded to a tenth, so float sums don't show as 11.999...).
local function percent(fraction: number): string
	local value = math.round(fraction * 1000) / 10
	return `+{value}%`
end

-- The totals as one line for players: "+4% attack · +3% max HP · +1 reroll". Empty when nothing
-- is bought.
function TalentMath.describe(totals: Totals): string
	local parts = {}
	local function add(amount: number, text: string)
		if amount > 0 then
			table.insert(parts, text)
		end
	end
	add(totals.Attack, `{percent(totals.Attack)} attack`)
	add(totals.MaxHp, `{percent(totals.MaxHp)} max HP`)
	add(totals.Armor, `+{math.round(totals.Armor * 10) / 10} armor`)
	add(totals.PieHealing, `{percent(totals.PieHealing)} pie healing`)
	add(totals.Reroll, `+{totals.Reroll} reroll{if totals.Reroll == 1 then "" else "s"}`)
	add(totals.StartingPie, "starting Pie")
	add(totals.FreePick, `+{totals.FreePick} free pick`)
	add(totals.PickupRange, `{percent(totals.PickupRange)} pickup range`)
	add(totals.MoveSpeed, `{percent(totals.MoveSpeed)} speed`)
	return table.concat(parts, " · ")
end

return TalentMath
