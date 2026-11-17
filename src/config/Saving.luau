--!strict
-- Saving player data (PRD §8.2, P2-1 #102). DataService reads these.
--
-- SaveSlot            the DataStore name every player's save lives in. Before launch, changing
--                     it (e.g. to "PlayerData_v2") wipes everyone: the old store is just never
--                     read again. In Studio "_Studio" is added, so tests never touch real saves.
-- LoadTimeoutSeconds  how long to keep trying to load a save before giving up. After that the
--                     player plays without saving (SaveStatus "Off") and their save is never
--                     written that session. The run starts meanwhile, so the wait isn't felt.
--                     Must be more than 40: if a crashed server still holds the save, ProfileStore
--                     takes it over after 40 s, and giving up sooner would block saving for ~10 min.
-- TestBuild           shows "Test build: progress may be reset" until launch.

export type Saving = {
	SaveSlot: string,
	LoadTimeoutSeconds: number,
	TestBuild: boolean,
}

local Saving: Saving = {
	SaveSlot = "PlayerData_v1",
	LoadTimeoutSeconds = 45,
	TestBuild = true,
}

return Saving
