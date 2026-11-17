--!strict
-- The mini-boss fight (PRD §2.1 step 6, §3.5, issue #84): The Big Cheese at 3:00.
--
-- When RunManager says the clock reached 3:00 (RunManager.onMiniBoss):
--   1. The clock holds at 3:00 and normal spawns stop (RunManager.setClockHeld). Enemies that
--      are already alive stay and keep fighting.
--   2. The chapter's mini-boss spawns near the chef, with a name + HP bar over it.
--   3. When a cheese piece dies, the pieces in its config's SplitInto appear where it died
--      (Big Cheese -> 3 Wedges -> 6 Cubes). They ignore the alive cap so a split always happens.
--   4. When the last piece is gone, the clock runs again and normal spawns come back.
-- A mini-boss with a Trail in Bosses.luau leaves it as it walks (TrailService, #99): The Big
-- Cheese's melted cheese. Only the big one; its pieces don't.
--
-- Player attribute set here (read by the HUD):
--   "MiniBoss"  the mini-boss's name while the fight is on, otherwise nil

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BossHpBar = require(script.Parent.Parent.BossHpBar)
local Bosses = require(ReplicatedStorage.Config.Bosses)
local Chapters = require(ReplicatedStorage.Config.Chapters)
local EnemyService = require(script.Parent.EnemyService)
local RunManager = require(script.Parent.RunManager)
local TrailService = require(script.Parent.TrailService)

local MiniBossService = {}

local SPAWN_DISTANCE = 30 -- studs from the chef where the mini-boss appears
local SPLIT_SPREAD_MIN = 2 -- studs from where a piece died that its children appear
local SPLIT_SPREAD_MAX = 4

-- Ids of every cheese piece still alive in the current fight. Empty = no fight going on.
local pieces: { [number]: boolean } = {}
local pieceCount = 0
local bossId: number? = nil -- the big one, for its HP bar
local hpFill: Frame? = nil
local fightSeconds: number? = nil -- nil until a fight starts this run
local fightOver = false
local random = Random.new()

local function getPlayer(): Player?
	return Players:GetPlayers()[1]
end

local function getChefPosition(): Vector3?
	local player = getPlayer()
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function addPiece(id: number?)
	if id and not pieces[id] then
		pieces[id] = true
		pieceCount += 1
	end
end

-- The last piece died: let the run carry on.
local function endFight()
	fightOver = true
	bossId = nil
	BossHpBar.remove(hpFill)
	hpFill = nil
	RunManager.setClockHeld(false)
	local player = getPlayer()
	if player then
		player:SetAttribute("MiniBoss", nil)
	end
end

local function startFight()
	local bossType = Chapters[RunManager.getChapter()].MiniBoss
	local boss = bossType and Bosses[bossType]
	local chefPosition = getChefPosition()
	if not (bossType and boss and boss.Body and chefPosition) then
		return -- no mini-boss in this chapter (ConfigCheck makes sure it has a Body)
	end

	RunManager.setClockHeld(true)
	fightSeconds = 0
	fightOver = false

	local angle = random:NextNumber(0, 2 * math.pi)
	local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * SPAWN_DISTANCE
	local id = EnemyService.spawnBoss(bossType, chefPosition + offset)
	if not id then
		endFight()
		return
	end
	bossId = id
	addPiece(id)
	if boss.Trail then
		TrailService.follow(id, boss.Trail)
	end
	local part = EnemyService.getEnemyPart(id)
	if part then
		hpFill = BossHpBar.attach(part, boss.Name)
	end
	local player = getPlayer()
	if player then
		player:SetAttribute("MiniBoss", boss.Name)
	end
end

-- A piece of the mini-boss died: split it, and end the fight when nothing is left.
local function onKilled(enemyId: number, enemyType: string, position: Vector3)
	if not pieces[enemyId] then
		return
	end
	pieces[enemyId] = nil
	pieceCount -= 1
	if enemyId == bossId then
		bossId = nil
		BossHpBar.remove(hpFill)
		hpFill = nil
	end

	local config = EnemyService.getConfigForType(enemyType)
	if config and config.SplitInto then
		for _ = 1, config.SplitCount or 1 do
			local angle = random:NextNumber(0, 2 * math.pi)
			local distance = random:NextNumber(SPLIT_SPREAD_MIN, SPLIT_SPREAD_MAX)
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance
			addPiece(EnemyService.spawnUnscaled(config.SplitInto, position + offset))
		end
	end

	if pieceCount <= 0 then
		endFight()
	end
end

-- Every frame: the big one's HP bar, and how long the fight has taken (paused time doesn't count).
local function update(deltaTime: number)
	if fightSeconds == nil or fightOver or RunManager.isPaused() or RunManager.isRunOver() then
		return
	end
	fightSeconds += deltaTime

	-- Pieces removed without a kill (the final boss clears the kitchen after a dev clock jump)
	-- don't split; forget them so the fight can end.
	for id in pieces do
		if not EnemyService.getEnemyPosition(id) then
			pieces[id] = nil
			pieceCount -= 1
		end
	end
	if pieceCount <= 0 then
		endFight()
		return
	end

	local id = bossId
	if id and hpFill then
		local hp, maxHp = EnemyService.getEnemyHp(id)
		if hp and maxHp then
			hpFill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
		end
	end
end

-- How long this run's mini-boss fight took (or has taken so far), in seconds without pauses,
-- and whether it's over. nil if the fight hasn't started this run. Used by the run report.
function MiniBossService.getFightSeconds(): (number?, boolean)
	return fightSeconds, fightOver
end

-- A new run is starting (RestartService): forget the fight. RunManager.reset() frees the
-- clock, and EnemyService.clearAll() already removed the pieces (without kill callbacks).
function MiniBossService.reset()
	TrailService.reset()
	table.clear(pieces)
	pieceCount = 0
	bossId = nil
	BossHpBar.remove(hpFill)
	hpFill = nil
	fightSeconds = nil
	fightOver = false
	local player = getPlayer()
	if player then
		player:SetAttribute("MiniBoss", nil)
	end
end

function MiniBossService:start()
	RunManager.onMiniBoss(startFight)
	EnemyService.onEnemyKilled(onKilled)
	RunService.Heartbeat:Connect(update)
end

return MiniBossService
