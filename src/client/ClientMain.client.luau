--[[
	ClientMain (client bootstrap)
	-----------------------------
	Starts the client-side controllers. Mirrors the server's registry idea but
	simpler — for now there's just the round HUD.
]]

local controllers = script.Parent:WaitForChild("Controllers")

local RoundHudController = require(controllers:WaitForChild("RoundHudController"))
RoundHudController:Init()

local CombatController = require(controllers:WaitForChild("CombatController"))
CombatController:Init()

local ClassSelectController = require(controllers:WaitForChild("ClassSelectController"))
ClassSelectController:Init()

local ProgressionController = require(controllers:WaitForChild("ProgressionController"))
ProgressionController:Init()

local AbilityBarController = require(controllers:WaitForChild("AbilityBarController"))
AbilityBarController:Init()

local PingController = require(controllers:WaitForChild("PingController"))
PingController:Init()

local ResultsController = require(controllers:WaitForChild("ResultsController"))
ResultsController:Init()

local OnboardingController = require(controllers:WaitForChild("OnboardingController"))
OnboardingController:Init()

local ShopController = require(controllers:WaitForChild("ShopController"))
ShopController:Init()

local RevealController = require(controllers:WaitForChild("RevealController"))
RevealController:Init()
