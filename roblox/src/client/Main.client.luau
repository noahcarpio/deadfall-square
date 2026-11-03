--[[
	Deadfall Square client bootstrap: starts the controllers and drives which
	screen is visible from the server's game phase
	(lobby / countdown / wave / intermission / gameover). During the
	intermission (the grace period) nothing pops up: players walk to the
	merchant or workbench, and the server opens that panel when they use it.
]]
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Context = require(script.Parent.Context)
local Audio = require(script.Parent.Audio)
local CameraController = require(script.Parent.CameraController)
local CharacterAnimator = require(script.Parent.CharacterAnimator)
local CharacterController = require(script.Parent.CharacterController)
local Fx = require(script.Parent.Fx)
local InputController = require(script.Parent.InputController)
local WeaponClient = require(script.Parent.WeaponClient)
local ZombieView = require(script.Parent.ZombieView)
local Builder = require(script.Parent.UI.Builder)
local Hud = require(script.Parent.UI.Hud)
local InventoryUI = require(script.Parent.UI.InventoryUI)
local Placement = require(script.Parent.UI.Placement)
local Screens = require(script.Parent.UI.Screens)
local StationUI = require(script.Parent.UI.StationUI)

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
CharacterAnimator.start()
ZombieView.start()
Fx.start()
WeaponClient.start()

local hudGui = Builder.screen("DeadfallHUD", 1)
hudGui.Parent = playerGui
Hud.start(hudGui)

-- Items: bandage heals at once; a pipe bomb is thrown toward the aim point.
local function useItem(id: string)
	if Context.downed() or Context.menuOpen or Context.phase() == "lobby" then
		return
	end
	if Context.inventory:count(id) <= 0 then
		Audio.play("uiDeny")
		return
	end
	Context.remotes.UseItem:FireServer(id, Context.aimX, Context.aimZ, Context.aimDistance)
	Audio.play("uiClick")
end
local bag = InventoryUI.new(hudGui, useItem)
InputController.onUseItem:connect(useItem)
InputController.onToggleBag:connect(function()
	if Context.phase() ~= "lobby" then
		bag.toggle()
	end
end)

local screensGui = Builder.screen("DeadfallScreens", 10)
screensGui.Parent = playerGui
local lobby = Screens.lobby(screensGui)
local rewards = Screens.rewards(screensGui)
local gameOver = Screens.gameOver(screensGui)
local station
local lastStation: { name: string, x: number, z: number }? = nil
local placement = Placement.new(screensGui, function()
	-- Back to the workbench panel if the player is still standing at it.
	if Context.phase() == "intermission" and lastStation then
		station.show(lastStation.name, lastStation.x, lastStation.z)
	end
end)
station = StationUI.new(screensGui, function(stype: string)
	station.hide()
	placement.start(stype)
end)
Context.remotes.OpenStation.OnClientEvent:Connect(function(name: string, x: number, z: number)
	if Context.phase() == "intermission" and not placement.active and not rewards.open then
		lastStation = { name = name, x = x, z = z }
		station.show(name, x, z)
		Audio.play("uiClick")
	end
end)

local pendingRewards: { any }? = nil
local gameOverData = nil

Context.remotes.RewardOffer.OnClientEvent:Connect(function(cards: { any })
	pendingRewards = cards
end)
Context.remotes.GameOver.OnClientEvent:Connect(function(data)
	gameOverData = data
end)
rewards.onChosen = function()
	pendingRewards = nil
end

-- Default movement controls are disabled while a menu covers the screen.
local controls = nil
task.spawn(function()
	local ok, module = pcall(function()
		-- PlayerModule is inserted by Roblox at runtime (not part of this project).
		local playerModule: any = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")
		return (require :: any)(playerModule)
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
		if phase ~= "reward" then
			rewards.hide()
			pendingRewards = nil
		end
		if phase ~= "intermission" then
			station.hide()
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
		else
			lobby.hide()
		end
	end

	-- After each floor: choose a reward card.
	if phase == "reward" and pendingRewards and not rewards.open then
		rewards.show(pendingRewards, Context.gameState:GetAttribute("Wave") or 0)
	end
	if phase == "gameover" and gameOverData and not gameOver.open then
		gameOver.show(gameOverData)
	end
	if gameOver.open then
		local left =
			math.max(0, math.ceil((Context.gameState:GetAttribute("PhaseEnd") or 0) - Workspace:GetServerTimeNow()))
		gameOver.update(left)
	end

	lobby.update()
	station.update()
	Context.menuOpen = station.open or rewards.open or gameOver.open or phase == "lobby"
	-- World prompts (search, trade, revive) hide while a panel covers the screen.
	ProximityPromptService.Enabled = not Context.menuOpen and not placement.active
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
