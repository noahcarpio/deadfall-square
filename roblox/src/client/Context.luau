--[[
	Client-wide state shared by controllers and UI: remotes, the predicted
	arsenal, stats/perks pushed by the server, local settings and a tiny
	signal implementation for cross-module events.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Arsenal = require(Shared.Arsenal)
local Inventory = require(Shared.Inventory)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local PlayerStats = require(Shared.PlayerStats)

export type Signal = {
	connect: (Signal, (...any) -> ()) -> () -> (),
	fire: (Signal, ...any) -> (),
}

local function signal(): Signal
	local handlers = {}
	local s = {}
	function s.connect(_self, fn)
		handlers[fn] = true
		return function()
			handlers[fn] = nil
		end
	end
	function s.fire(_self, ...)
		for fn in handlers do
			task.spawn(fn, ...)
		end
	end
	return s :: any
end

local remotesFolder = Net.setup(false)
local remotes = {}
for _, name in Net.EVENTS do
	remotes[name] = remotesFolder:WaitForChild(name)
end
for _, name in Net.UNRELIABLE do
	remotes[name] = remotesFolder:WaitForChild(name)
end
for _, name in Net.FUNCTIONS do
	remotes[name] = remotesFolder:WaitForChild(name)
end

local base = PlayerStats.compute(
	{ maxHealth = 0, armor = 0, speed = 0, stamina = 0, backpack = 0 },
	{
		level = function()
			return 0
		end,
		has = function()
			return false
		end,
	} :: any
)

local Context = {
	player = Players.LocalPlayer,
	remotes = remotes,
	gameState = ReplicatedStorage:WaitForChild("GameState"),
	arsenal = Arsenal.new(),
	stats = base,
	perks = {} :: { { id: string, level: number } },
	tiers = { maxHealth = 0, armor = 0, speed = 0, stamina = 0, backpack = 0 },
	-- Mirror of the server's bag (InventorySync).
	inventory = Inventory.new(Items.BASE_CAPACITY),
	-- Mirror of the server's gear (GearSync): stash, melee, armor, gadgets, guns.
	gear = { stash = {}, melee = false, armor = false, gadgets = { false, false, false }, guns = {} } :: any,
	stamina = base.maxStamina,
	-- Aim on the ground plane (metres) and whether the trigger is held.
	aimX = 0,
	aimZ = -1,
	aimDistance = 10,
	firing = false,
	-- Current weapon spread (radians), for the crosshair.
	spread = 0,
	-- Charge-up guns (railgun): 0..1 while the trigger is held.
	charge = 0,
	sprinting = false,
	rolling = false,
	rollStart = 0,
	-- Melee swing in progress (os.clock) and its combo step, for animation.
	swingAt = -10,
	swingStep = 1,
	-- Gadget slots: when each is ready again (server time).
	abilityReady = { 0, 0, 0 },
	-- Adrenal Shot speed boost (os.clock end time).
	adrenalUntil = 0,
	exhausted = false,
	device = "mouse" :: "mouse" | "touch" | "gamepad",
	-- True while a full-screen UI (merchant/workbench, inventory, reward, game over) is open.
	menuOpen = false,
	placing = false,
	-- Camera pan while placing structures (studs).
	panOffset = Vector3.zero,
	settings = { screenShake = true, damageNumbers = true },
	trauma = 0,
	signals = {
		arsenalChanged = signal(),
		statsChanged = signal(),
		shot = signal(),
		hurt = signal(),
		notify = signal(),
		phaseChanged = signal(),
		inventoryChanged = signal(),
		gearChanged = signal(),
		dash = signal(), -- (dirX, dirZ, distance) Charge Strike
		fired = signal(), -- (weaponId) our own shot, for the recoil animation
	},
	signal = signal,
}

remotes.InventorySync.OnClientEvent:Connect(function(data)
	if type(data) == "table" and type(data.items) == "table" and type(data.capacity) == "number" then
		Context.inventory:load(data)
		Context.signals.inventoryChanged:fire()
	end
end)

remotes.GearSync.OnClientEvent:Connect(function(data)
	if type(data) == "table" then
		Context.gear = data
		Context.signals.gearChanged:fire()
	end
end)

function Context.shake(amount: number)
	if Context.settings.screenShake then
		Context.trauma = math.min(1, Context.trauma + amount)
	end
end

function Context.phase(): string
	return Context.gameState:GetAttribute("Phase") or "waiting"
end

function Context.character(): Model?
	return Context.player.Character
end

function Context.downed(): boolean
	return Context.player:GetAttribute("Downed") == true
end

return Context
