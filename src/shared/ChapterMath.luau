--!strict
-- Which chapters can be played (P2-6f #152, design: docs/superpowers/specs/2026-11-18-unlocks-starters-design.md).
-- Shared so the lobby's Chapters tab and the server's Play check agree.
--
-- A chapter's state, from the chapters a player has cleared (won at least once):
--   "ComingSoon"  it has no Timeline yet (or isn't in the MVP): never playable
--   "Locked"      the chapter before it (by Order) isn't cleared yet
--   "Cleared"     won at least once; still playable
--   "Playable"    can be played, not won yet
-- Chapter 1 is never Locked.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Chapters = require(ReplicatedStorage.Config.Chapters)

export type State = "ComingSoon" | "Locked" | "Cleared" | "Playable"

local ChapterMath = {}

-- Every chapter id, by Order.
function ChapterMath.sortedIds(): { string }
	local ids = {}
	for id in Chapters do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return Chapters[a].Order < Chapters[b].Order
	end)
	return ids
end

-- The chapter right before this one (by Order), or nil for Chapter 1.
function ChapterMath.previous(id: string): string?
	local chapter = Chapters[id]
	for otherId, other in Chapters do
		if chapter and other.Order == chapter.Order - 1 then
			return otherId
		end
	end
	return nil
end

function ChapterMath.state(id: string, cleared: { [string]: boolean }): State
	local chapter = Chapters[id]
	if not chapter or not chapter.Mvp or not chapter.Timeline then
		return "ComingSoon"
	end
	local before = ChapterMath.previous(id)
	if before and not cleared[before] then
		return "Locked"
	end
	return if cleared[id] then "Cleared" else "Playable"
end

function ChapterMath.isPlayable(id: string, cleared: { [string]: boolean }): boolean
	local state = ChapterMath.state(id, cleared)
	return state == "Playable" or state == "Cleared"
end

return ChapterMath
