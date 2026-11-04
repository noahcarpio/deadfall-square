--[[
	The "Field Manual" design language: every menu is a page from a
	survivor's field manual (paper, ink, one rust accent, square corners),
	and the HUD is the same system on a dark "night" surface so it reads over
	the game. The spec page with every colour, type style, component and
	screen mock-up is linked from the README; this file is the source of
	truth in code.

	Both palettes share the same keys, so a module picks one and uses
	T.text, T.muted, T.accent... without caring which surface it's on:
	  paper - menus: merchant, workbench, inventory, lobby, rewards, game over
	  night - HUD, bag strip, gadget bar, placement bar, toasts
]]

export type Palette = {
	name: string,
	-- surfaces
	bg: Color3,
	panel: Color3,
	panelAlpha: number,
	shade: Color3,
	border: Color3,
	rule: Color3,
	-- text
	text: Color3,
	muted: Color3,
	-- meaning
	accent: Color3, -- positive / ready / affordable (olive)
	rust: Color3, -- the single accent: prices, danger, selection
	danger: Color3,
	gold: Color3, -- coins (rust in this system)
	warn: Color3,
	blue: Color3,
	boss: Color3,
	-- buttons
	buttonFill: Color3,
	buttonText: Color3,
	-- rarity stamps
	stampCommon: Color3,
	stampRare: Color3,
	stampUnique: Color3,
	-- fonts
	head: Enum.Font, -- Oswald: condensed headings, upper case
	type: Enum.Font, -- Special Elite: typewriter labels, section numbers
	mono: Enum.Font, -- Roboto Mono: numbers, prices, stats
	body: Enum.Font, -- Roboto Condensed: body text
	bold: Enum.Font, -- short emphasised labels
}

local FONTS = {
	head = Enum.Font.Oswald,
	type = Enum.Font.SpecialElite,
	mono = Enum.Font.RobotoMono,
	body = Enum.Font.RobotoCondensed,
	bold = Enum.Font.Oswald,
}

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

local paper: Palette = {
	name = "paper",
	bg = hex("#E8E2D4"),
	panel = hex("#E8E2D4"),
	panelAlpha = 0,
	shade = hex("#D9D1BF"),
	border = hex("#1F1D1A"),
	rule = hex("#B8AE98"),
	text = hex("#1F1D1A"),
	muted = hex("#5B554C"),
	accent = hex("#4F5A35"),
	rust = hex("#9C3B22"),
	danger = hex("#9C3B22"),
	gold = hex("#9C3B22"),
	warn = hex("#A9822F"),
	blue = hex("#2F4A6B"),
	boss = hex("#7A2E1B"),
	buttonFill = hex("#1F1D1A"),
	buttonText = hex("#E8E2D4"),
	stampCommon = hex("#1F1D1A"),
	stampRare = hex("#2F4A6B"),
	stampUnique = hex("#A9822F"),
	head = FONTS.head,
	type = FONTS.type,
	mono = FONTS.mono,
	body = FONTS.body,
	bold = FONTS.bold,
}

local night: Palette = {
	name = "night",
	bg = hex("#12110F"),
	panel = hex("#1F1D1A"),
	panelAlpha = 0.12,
	shade = hex("#2A2723"),
	border = hex("#4A453D"),
	rule = hex("#3A3631"),
	text = hex("#E8E2D4"),
	muted = hex("#9A9182"),
	accent = hex("#9DAA74"),
	rust = hex("#D2694A"),
	danger = hex("#D2694A"),
	gold = hex("#D9B26A"),
	warn = hex("#D5AE58"),
	blue = hex("#7FA2C9"),
	boss = hex("#C2553A"),
	buttonFill = hex("#E8E2D4"),
	buttonText = hex("#1F1D1A"),
	stampCommon = hex("#E8E2D4"),
	stampRare = hex("#7FA2C9"),
	stampUnique = hex("#D5AE58"),
	head = FONTS.head,
	type = FONTS.type,
	mono = FONTS.mono,
	body = FONTS.body,
	bold = FONTS.bold,
}

return {
	paper = paper,
	night = night,
	-- Type scale and spacing (8-px grid).
	SIZE = { xs = 12, s = 14, m = 16, l = 20, xl = 28, xxl = 40 },
	SPACE = { s1 = 8, s2 = 16, s3 = 24, s4 = 32 },
	CORNER = 2,
}
