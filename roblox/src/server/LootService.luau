--[[
	Searchable containers (cars, the bus, crate stacks, dumpsters, trash
	piles). Each holds rolled loot shared by everyone: hold the prompt to
	search it and take whatever fits in your bag; the rest stays for someone
	else. Containers restock at the start of a run and, by chance, at every
	grace period.
]]
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local Items = require(Shared.Config.Items)
local Loot = require(Shared.Loot)
local Weapons = require(Shared.Config.Weapons)

local S = Constants.STUDS

-- Prompt reach (m) by container kind: long vehicles need more.
local REACH = { car = 3.6, bus = 6.2, crate = 2.8, dumpster = 2.8, trash = 2.2 }

local LootService = {}
LootService.__index = LootService

-- Players kneel (character attribute "Kneeling", animated on clients) while holding a prompt.
local function kneelWhileHolding(prompt: ProximityPrompt)
	local function set(player: Player, on: boolean)
		if player.Character then
			player.Character:SetAttribute("Kneeling", on)
		end
	end
	prompt.PromptButtonHoldBegan:Connect(function(player)
		set(player, true)
	end)
	prompt.PromptButtonHoldEnded:Connect(function(player)
		set(player, false)
	end)
	prompt.Triggered:Connect(function(player)
		set(player, false)
	end)
end
LootService.kneelWhileHolding = kneelWhileHolding

function LootService.new(W, layout)
	local self = setmetatable({ W = W, containers = {}, active = false }, LootService)
	local folder = Instance.new("Folder")
	folder.Name = "Loot"
	folder.Parent = Workspace
	for _, spot in layout.loot do
		local anchor = Instance.new("Part")
		anchor.Name = spot.kind
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(1, 1, 1)
		anchor.CFrame = CFrame.new(spot.x * S, 1.2 * S, spot.z * S)
		anchor.Parent = folder
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Search"
		prompt.ObjectText = Loot.tables[spot.kind].label
		prompt.HoldDuration = Loot.SEARCH_SECONDS
		prompt.MaxActivationDistance = (REACH[spot.kind] or 3) * S
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.F
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
		prompt.Enabled = false
		prompt.Parent = anchor
		local c = { kind = spot.kind, x = spot.x, z = spot.z, contents = {}, prompt = prompt }
		prompt.Triggered:Connect(function(player: Player)
			self:search(c, player)
		end)
		kneelWhileHolding(prompt)
		table.insert(self.containers, c)
	end
	return self
end

local function isEmpty(contents): boolean
	return next(contents) == nil
end

function LootService.updatePrompt(self, c)
	c.prompt.Enabled = self.active and not isEmpty(c.contents)
end

function LootService.setActive(self, active: boolean)
	self.active = active
	for _, c in self.containers do
		self:updatePrompt(c)
	end
end

-- Refills containers: all of them (`full`, new run) or a random share (grace period).
function LootService.restock(self, wave: number, full: boolean)
	local rng = self.W.rng
	for _, c in self.containers do
		if full or rng:chance(Loot.RESTOCK_CHANCE) then
			c.contents = Loot.roll(rng, c.kind, wave)
		end
		self:updatePrompt(c)
	end
end

function LootService.clear(self)
	for _, c in self.containers do
		c.contents = {}
	end
	self:setActive(false)
end

-- Gives `units` of found ammo to the player's limited-ammo weapons. Returns true if any was used.
local function takeAmmo(ps, units: number): boolean
	local any = false
	for _, w in ps.arsenal:list() do
		if Weapons.defs[w.id].reserveMax ~= math.huge then
			if ps.arsenal:addAmmoFraction(w.id, Loot.AMMO_FRACTION * units) > 0 then
				any = true
			end
		end
	end
	return any
end

function LootService.search(self, c, player: Player)
	local W = self.W
	local ps = W.players:get(player)
	if not self.active or not ps or ps.downed or not ps.hasBody or isEmpty(c.contents) then
		return
	end
	local reach = (REACH[c.kind] or 3) + 1.5
	if (ps.x - c.x) ^ 2 + (ps.z - c.z) ^ 2 > reach * reach then
		return
	end
	local found = {}
	local leftOver = false
	local ammoLeft = false
	local ids = {}
	for id in c.contents do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local n = c.contents[id]
		if id == "coins" then
			local amount = math.floor(n * ps.economy.coinMultiplier + 0.5)
			ps.economy:addCoins(amount)
			table.insert(found, `+{amount} coins`)
			c.contents[id] = nil
		elseif id == "ammo" then
			if takeAmmo(ps, n) then
				table.insert(found, "ammo")
				c.contents[id] = nil
				W.players:syncArsenal(ps)
			else
				ammoLeft = true
			end
		else
			local added = ps.inventory:add(id, n)
			if added > 0 then
				table.insert(found, `+{added} {Items.defs[id].name}`)
			end
			if added < n then
				c.contents[id] = n - added
				leftOver = true
			else
				c.contents[id] = nil
			end
		end
	end
	self:updatePrompt(c)
	W.players:syncInventory(ps)
	W.players:syncAttributes()
	if #found > 0 then
		local text = table.concat(found, ", ")
		W.notify(player, if leftOver then `{text} (bag full — some left behind)` else text, "good")
	elseif leftOver then
		W.notify(player, "Your bag is full", "bad")
	elseif ammoLeft then
		W.notify(player, "Ammo here, but none of your guns use it", "info")
	end
end

return LootService
