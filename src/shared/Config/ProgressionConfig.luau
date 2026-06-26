--[[
	ProgressionConfig
	-----------------
	All progression tunables in one place (matches the Config/ split). XP, the
	level curve, per-outcome match rewards, and the daily-login reward ladder.
	Edit, re-Play, Rojo live-syncs — no code changes needed to rebalance.

	The level curve is data here (BASE_XP / GROWTH / MAX_LEVEL); the actual
	"xp needed for level N" math lives in DataService so configs stay pure data.
]]

local ProgressionConfig = {}

-- == Level curve =============================================================
-- XP needed to advance FROM level L = BASE_XP * GROWTH ^ (L - 1), floored.
-- e.g. BASE_XP=100, GROWTH=1.18 -> L1:100  L2:118  L3:139 ... L10:~439
ProgressionConfig.BASE_XP = 100
ProgressionConfig.GROWTH = 1.18
ProgressionConfig.MAX_LEVEL = 50

-- == Match XP awards (coins are handled by GameConfig.REWARD_* via Economy) ==
ProgressionConfig.XP_PARTICIPATION = 25 -- everyone who finishes a match
ProgressionConfig.XP_WIN = 50 -- on top, for being on the winning side

-- == Daily login reward ======================================================
-- Coins granted on the Nth consecutive day (index clamps to the last entry).
ProgressionConfig.DAILY_REWARDS = { 50, 75, 100, 150, 200, 300, 500 }
-- Claimable again this many hours after the last claim...
ProgressionConfig.DAILY_COOLDOWN_HOURS = 20
-- ...but if this many hours pass without claiming, the streak resets to day 1.
ProgressionConfig.DAILY_STREAK_GRACE_HOURS = 48

return ProgressionConfig
