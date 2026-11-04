--[[
	Deadfall Square client bootstrap: starts the controllers and drives which
	screen is visible from the server's game phase
	(waiting / countdown / wave / intermission / gameover). During the
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
local AbilityBar = require(script.Parent.UI.AbilityBar)
local InventoryUI = require(script.Parent.UI.InventoryUI)
local InventoryScreen = require(script.Parent.UI.InventoryScreen)
local EmoteMenu = require(script.Parent.UI.EmoteMenu)
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
AbilityBar.start(hudGui)

-- Items: bandage heals at once; a pipe bomb is thrown toward the aim point.
local function useItem(id: string, fromInventory: boolean?)
	if Context.downed() or (Context.menuOpen and not fromInventory) or Context.phase() == "waiting" then
		return
	end
	if Context.inventory:count(id) <= 0 then
		Audio.play("uiDeny")
		return
	end
	Context.remotes.UseItem:FireServer(id, Context.aimX, Context.aimZ, Context.aimDistance)
	Audio.play("uiClick")
end
InventoryUI.new(hudGui)
local inventoryGui = Builder.screen("DeadfallInventory", 12)
inventoryGui.Parent = playerGui
local inventory = InventoryScreen.new(inventoryGui, function(id: string)
	useItem(id, true)
end)
InputController.onUseItem:connect(useItem)
InputController.onToggleBag:connect(function()
	if Context.phase() ~= "waiting" then
		inventory.toggle()
	end
end)
local emoteMenu = EmoteMenu.new(hudGui)
InputController.onEmote:connect(function()
	emoteMenu.toggle(Context.device == "gamepad")
end)

local screensGui = Builder.screen("DeadfallScreens", 10)
screensGui.Parent = playerGui
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
end, function()
	-- The merchant's SELL button: open the inventory with selling enabled.
	station.hide()
	inventory.show("guns", true)
end)
Context.remotes.OpenStation.OnClientEvent:Connect(function(name: string, x: number, z: number)
	local phase = Context.phase()
	-- The merchant trades all run; the workbench only between floors.
	local open = if name == "merchant" then phase ~= "waiting" and phase ~= "gameover" else phase == "intermission"
	if open and not placement.active and not rewards.open then
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

-- Default movement controls are disabled while a full-screen menu or placement is up.
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
		if phase ~= "reward" then
			rewards.hide()
			pendingRewards = nil
		end
		if phase ~= "intermission" and (station.station ~= "merchant" or phase == "waiting" or phase == "gameover") then
			station.hide()
		end
		if phase ~= "intermission" and placement.active then
			placement.stop()
		end
		if phase ~= "gameover" then
			gameOver.hide()
			gameOverData = nil
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

	station.update()
	inventory.update()
	if inventory.open and (phase == "waiting" or phase == "gameover" or rewards.open) then
		inventory.hide()
	end
	Context.menuOpen = station.open or rewards.open or gameOver.open or inventory.open or phase == "waiting"
	-- The merchant, workbench and inventory panels let the player keep walking;
	-- rewards and game over cover the screen and hold them still.
	local modal = rewards.open or gameOver.open
	-- World prompts (search, trade, revive) hide while a panel is open.
	ProximityPromptService.Enabled = not Context.menuOpen and not placement.active
	if controls then
		if modal or placement.active then
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
