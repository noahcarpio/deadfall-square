--[[
	Deadfall Square client bootstrap: starts the controllers and drives which
	screen is visible from the server's game phase
	(lobby / countdown / wave / intermission / gameover).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Context = require(script.Parent.Context)
local Audio = require(script.Parent.Audio)
local CameraController = require(script.Parent.CameraController)
local CharacterController = require(script.Parent.CharacterController)
local Fx = require(script.Parent.Fx)
local InputController = require(script.Parent.InputController)
local WeaponClient = require(script.Parent.WeaponClient)
local ZombieView = require(script.Parent.ZombieView)
local Builder = require(script.Parent.UI.Builder)
local Hud = require(script.Parent.UI.Hud)
local Placement = require(script.Parent.UI.Placement)
local Screens = require(script.Parent.UI.Screens)
local ShopUI = require(script.Parent.UI.ShopUI)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- The reset button would bypass the downed/revive rules.
task.spawn(function()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", false)
		end)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

CameraController.start()
InputController.start()
CharacterController.start()
ZombieView.start()
Fx.start()
WeaponClient.start()

local hudGui = Builder.screen("DeadfallHUD", 1)
hudGui.Parent = playerGui
Hud.start(hudGui)

local screensGui = Builder.screen("DeadfallScreens", 10)
screensGui.Parent = playerGui
local lobby = Screens.lobby(screensGui)
local perks = Screens.perks(screensGui)
local gameOver = Screens.gameOver(screensGui)
local shop
local placement = Placement.new(screensGui, function()
	if Context.phase() == "intermission" then
		shop.show(Context.gameState:GetAttribute("Wave") or 0)
	end
end)
shop = ShopUI.new(screensGui, function(stype: string)
	shop.hide()
	placement.start(stype)
end)

local pendingPerks: { string }? = nil
local gameOverData = nil

Context.remotes.PerkOffer.OnClientEvent:Connect(function(choices: { string })
	pendingPerks = choices
end)
Context.remotes.GameOver.OnClientEvent:Connect(function(data)
	gameOverData = data
end)
perks.onChosen = function()
	pendingPerks = nil
end

-- Default movement controls are disabled while a menu covers the screen.
local controls = nil
task.spawn(function()
	local ok, module = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
	end)
	if ok and module then
		controls = module:GetControls()
	end
end)

local lastPhase = ""
RunService.RenderStepped:Connect(function()
	local phase = Context.phase()
	if phase ~= lastPhase then
		lastPhase = phase
		Context.signals.phaseChanged:fire(phase)
		if phase ~= "intermission" then
			shop.hide()
			perks.hide()
			if placement.active then
				placement.stop()
			end
		end
		if phase ~= "gameover" then
			gameOver.hide()
			gameOverData = nil
		end
		if phase == "lobby" then
			lobby.show()
			pendingPerks = nil
		else
			lobby.hide()
		end
		if phase == "intermission" and not pendingPerks then
			shop.show(Context.gameState:GetAttribute("Wave") or 0)
		end
	end

	-- Perk choice arrives with the intermission; it is shown before the shop.
	if phase == "intermission" and pendingPerks and not perks.open and not placement.active then
		shop.hide()
		perks.show(pendingPerks)
	elseif phase == "intermission" and not pendingPerks and not perks.open and not shop.open and not placement.active then
		shop.show(Context.gameState:GetAttribute("Wave") or 0)
	end
	if phase == "gameover" and gameOverData and not gameOver.open then
		gameOver.show(gameOverData)
	end
	if gameOver.open then
		local left = math.max(0, math.ceil((Context.gameState:GetAttribute("PhaseEnd") or 0) - Workspace:GetServerTimeNow()))
		gameOver.update(left)
	end

	lobby.update()
	shop.update()
	Context.menuOpen = shop.open or perks.open or gameOver.open or phase == "lobby"
	if controls then
		if Context.menuOpen or placement.active then
			controls:Disable()
		else
			controls:Enable()
		end
	end

	-- Music follows the phase (silent unless sound ids are configured).
	if phase == "wave" then
		Audio.music(if (Context.gameState:GetAttribute("BossId") or 0) ~= 0 then "musicBoss" else "musicCombat")
	else
		Audio.music("musicCalm")
	end
end)
