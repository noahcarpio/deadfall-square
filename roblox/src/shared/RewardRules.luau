--!strict
-- String requires below are the Lune (unit test) branch; Roblox uses the Instance branch.
--# selene: allow(incorrect_standard_library_use)
--[[
	The three reward cards each player chooses from after clearing a floor:
	a piece of gear, a perk, coins, supplies or a full patch-up. Boss floors
	guarantee at least one rare-or-better gear card.
]]
local Gear = if script then require(script.Parent.Gear) else require("./Gear")
type GearItem = { uid: number, id: string, kind: string, rarity: string, power: number, traits: { string } }
local Perks = if script then require(script.Parent.Config.Perks) else require("./Config/Perks")
local Items = if script then require(script.Parent.Config.Items) else require("./Config/Items")

export type Card = {
	kind: string, -- gear | perk | coins | supplies | heal
	item: GearItem?,
	perk: string?,
	amount: number?,
	supplies: { [string]: number }?,
}

type RngLike = {
	next: (any) -> number,
	int: (any, number, number) -> number,
	weighted: (any, { [string]: number }) -> string,
	chance: (any, number) -> boolean,
}

local SUPPLY_PACKS: { { [string]: number } } = {
	{ bandage = 2, cloth = 2 },
	{ pipebomb = 1, gunpowder = 2 },
	{ scrap = 4, parts = 2 },
	{ wood = 4, scrap = 2 },
}

--[[
	Rolls the cards. `perkChoices` are perk ids the player can still take
	(PerkState:rollChoices); `nextUid` hands out gear ids.
]]
local function roll(
	rng: RngLike,
	floor: number,
	boss: boolean,
	perkChoices: { string },
	nextUid: () -> number
): { Card }
	local cards: { Card } = {}
	local usedKinds: { [string]: boolean } = {}
	local perkIndex = 1
	if boss then
		table.insert(cards, { kind = "gear", item = Gear.roll(rng, floor, nextUid(), nil, "rare") })
		usedKinds.gear = true
	end
	local guard = 0
	while #cards < 3 and guard < 50 do
		guard += 1
		local weights: { [string]: number } = { gear = 3, coins = 1.5, supplies = 1.5, heal = 1 }
		if perkChoices[perkIndex] then
			weights.perk = 2.2
		end
		-- At most one card of each kind except gear (two gear cards are fine).
		for kind in usedKinds do
			if kind ~= "gear" then
				weights[kind] = nil
			end
		end
		local kind = rng:weighted(weights)
		usedKinds[kind] = true
		if kind == "gear" then
			table.insert(cards, { kind = "gear", item = Gear.roll(rng, floor, nextUid()) })
		elseif kind == "perk" then
			table.insert(cards, { kind = "perk", perk = perkChoices[perkIndex] })
			perkIndex += 1
		elseif kind == "coins" then
			table.insert(cards, { kind = "coins", amount = 60 + floor * 14 + rng:int(0, 30) })
		elseif kind == "supplies" then
			table.insert(cards, { kind = "supplies", supplies = table.clone(SUPPLY_PACKS[rng:int(1, #SUPPLY_PACKS)]) })
		else
			table.insert(cards, { kind = "heal" })
		end
	end
	return cards
end

export type CardText = { glyph: string, title: string, lines: { string }, color: string, footer: string }

-- How a card is shown (client) — shared so tests can check every card has text.
local function describe(card: Card): CardText
	if card.kind == "gear" and card.item then
		local item = card.item
		local r = Gear.rarities[item.rarity]
		local kindName = if item.kind == "gun"
			then "GUN"
			elseif item.kind == "melee" then "MELEE"
			elseif item.kind == "armor" then "ARMOR"
			else "GADGET"
		return {
			glyph = string.sub(kindName, 1, 1),
			title = Gear.title(item),
			lines = Gear.describe(item),
			color = r.color,
			footer = kindName,
		}
	elseif card.kind == "perk" and card.perk then
		local d = Perks.defs[card.perk]
		return { glyph = d.glyph, title = d.name, lines = { d.description }, color = d.color, footer = "PERK" }
	elseif card.kind == "coins" then
		return {
			glyph = "●",
			title = `{card.amount or 0} coins`,
			lines = { "Spend them at the merchant." },
			color = "#ffd23a",
			footer = "COINS",
		}
	elseif card.kind == "supplies" then
		local parts = {}
		for _, id in Items.order do
			local n = card.supplies and card.supplies[id]
			if n then
				table.insert(parts, `{n} {Items.defs[id].name}`)
			end
		end
		return {
			glyph = "+",
			title = "Supply crate",
			lines = { table.concat(parts, ", ") },
			color = "#9ad36b",
			footer = "SUPPLIES",
		}
	end
	return {
		glyph = "♥",
		title = "Patch up",
		lines = { "Full health and armor." },
		color = "#ff6b6b",
		footer = "HEAL",
	}
end

return { roll = roll, describe = describe }
