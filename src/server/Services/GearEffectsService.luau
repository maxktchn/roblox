--!strict
-- Gear bonus effects (P2-4 #139, PRD §4.2, design: docs/superpowers/specs/2026-11-17-gear-design.md).
--
-- Epic gear adds a bonus effect and Legendary makes it stronger. The numbers live in each item's
-- Effect entry in Gear.luau. Every time GearService fixes a run's gear (onRunGear), everything is
-- switched off and the effects of this run's Epic and Legendary items are switched on:
--   Chef's Hat   free "Order Up!" picks at the start of the run (UpgradeService.grantLevelUps)
--   Apron        blocks one hit, then is ready again after BlockEverySeconds (paused time doesn't
--                count). Player attribute "ApronReady" (true/false; nil without the effect) lets
--                the HUD show when it's ready.
--   Shoes        after a hit: SpeedBoost faster for BoostSeconds, and no damage for SafeSeconds
--   Chef's Knife and Oven Mitts work inside WeaponService (see the weapon hooks there).
-- Frying Pan and Rolling Pin effects come with those starters (#107).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Gear = require(ReplicatedStorage.Config.Gear)
local GearService = require(script.Parent.GearService)
local RunManager = require(script.Parent.RunManager)
local StatsService = require(script.Parent.StatsService)
local UpgradeService = require(script.Parent.UpgradeService)

local GearEffectsService = {}

-- This run's effects (nil = not on).
local apron: Gear.Effect? = nil
local shoes: Gear.Effect? = nil
local apronReady = false
local apronTimer = 0 -- seconds until the Apron is ready again
local boostTimer = 0 -- seconds left of the Shoes' speed boost
local safeTimer = 0 -- seconds left of the Shoes' no-damage time

local function getRunPlayer(): Player?
	return Players:GetPlayers()[1]
end

-- The bonus effect of an item in this run's gear, if it's Epic or Legendary.
function GearEffectsService.getEffect(itemId: string): Gear.Effect?
	for _, item in GearService.getRunGear() do
		if item.Item == itemId and (item.Rarity == "Epic" or item.Rarity == "Legendary") then
			return (Gear.Items[itemId].Effect :: any)[item.Rarity]
		end
	end
	return nil
end

local function setApronReady(ready: boolean?)
	apronReady = ready == true
	local player = getRunPlayer()
	if player then
		player:SetAttribute("ApronReady", ready)
	end
end

-- RunManager asks this before every hit on the chef. True = the hit is blocked.
local function blockHit(_amount: number, _source: string?): boolean
	if safeTimer > 0 then
		return true -- Legendary Shoes: just hit, can't be hurt yet
	end
	if apron and apronReady then
		setApronReady(false)
		apronTimer = apron.BlockEverySeconds
		return true
	end
	return false
end

-- Turn every effect off, then on again for this run's Epic and Legendary gear.
local function applyRunGear()
	apron = GearEffectsService.getEffect("Apron")
	shoes = GearEffectsService.getEffect("Shoes")
	boostTimer, safeTimer, apronTimer = 0, 0, 0
	StatsService.setSpeedBoost(0)
	setApronReady(if apron then true else nil)
	RunManager.setHitBlocker(if apron or shoes then blockHit else nil)

	local hat = GearEffectsService.getEffect("ChefsHat")
	if hat then
		UpgradeService.grantLevelUps(hat.FreePicks)
	end
end

-- Count the timers down (not while paused, e.g. on the "Order Up!" cards).
local function update(deltaTime: number)
	if RunManager.isPaused() then
		return
	end
	if apron and not apronReady then
		apronTimer -= deltaTime
		if apronTimer <= 0 then
			setApronReady(true)
		end
	end
	if boostTimer > 0 then
		boostTimer -= deltaTime
		if boostTimer <= 0 then
			StatsService.setSpeedBoost(0)
		end
	end
	if safeTimer > 0 then
		safeTimer -= deltaTime
	end
end

-- The chef was hurt: Shoes start their boost (and, at Legendary, a moment of no damage).
local function onDamaged(_hpLost: number, _source: string?)
	if not shoes then
		return
	end
	StatsService.setSpeedBoost(shoes.SpeedBoost)
	boostTimer = shoes.BoostSeconds
	safeTimer = shoes.SafeSeconds
end

function GearEffectsService:start()
	GearService.onRunGear(applyRunGear)
	RunManager.onPlayerDamaged(onDamaged)
	RunService.Heartbeat:Connect(update)
end

return GearEffectsService
