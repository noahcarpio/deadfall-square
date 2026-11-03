--[[
	The grace-period stations in the plaza: the merchant (coins), the
	workbench (materials) and the alarm bell (start the next wave early).
	Each has a proximity prompt that only works between waves; using the
	merchant or workbench opens its panel on that player's screen. Every
	purchase is re-checked against the player's distance to the station.
]]
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)

local S = Constants.STUDS

local INFO = {
	merchant = { title = "MERCHANT", action = "Trade", object = "Merchant", hold = 0 },
	workbench = { title = "WORKBENCH", action = "Craft", object = "Workbench", hold = 0 },
	bell = { title = "ALARM BELL", action = "Ready up", object = "Start the next wave", hold = 0.5 },
}

local Stations = {}
Stations.__index = Stations

local function billboard(parent: BasePart, title: string): (TextLabel, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(200, 50)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2 * S - parent.Position.Y, 0)
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = parent
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 0.6, 0)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(242, 201, 76)
	t.TextStrokeTransparency = 0.4
	t.Text = title
	t.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromScale(0, 0.6)
	sub.Size = UDim2.new(1, 0, 0.4, 0)
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(220, 220, 210)
	sub.TextStrokeTransparency = 0.5
	sub.Parent = gui
	return t, sub
end

-- `onUse(name, player)` runs when a prompt is used while the stations are open.
function Stations.new(W, layout, onUse: (string, Player) -> ())
	local self = setmetatable({ W = W, list = {}, byName = {}, open = false }, Stations)
	local folder = Instance.new("Folder")
	folder.Name = "Stations"
	folder.Parent = Workspace
	for _, st in layout.stations do
		local info = INFO[st.name]
		local anchor = Instance.new("Part")
		anchor.Name = st.name
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(1, 1, 1)
		anchor.CFrame = CFrame.new(st.px * S, 1.3 * S, st.pz * S)
		anchor.Parent = folder
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = info.action
		prompt.ObjectText = info.object
		prompt.HoldDuration = info.hold
		prompt.MaxActivationDistance = Constants.STATION_RANGE * S
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.F
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
		prompt.Enabled = false
		prompt.Parent = anchor
		local _, sub = billboard(anchor, info.title)
		local entry = { name = st.name, x = st.px, z = st.pz, prompt = prompt, sub = sub }
		prompt.Triggered:Connect(function(player: Player)
			if self.open then
				onUse(st.name, player)
			end
		end)
		table.insert(self.list, entry)
		self.byName[st.name] = entry
	end
	self:setOpen(false)
	return self
end

function Stations.setOpen(self, open: boolean)
	self.open = open
	for _, e in self.list do
		e.prompt.Enabled = open
		e.sub.Text = if open then "OPEN — press F" else "opens between waves"
	end
end

-- True if the player stands close enough to use the named station.
function Stations.near(self, ps, name: string): boolean
	local e = self.byName[name]
	if not e or not ps.hasBody or ps.downed then
		return false
	end
	local range = Constants.STATION_RANGE + 1
	return (ps.x - e.x) ^ 2 + (ps.z - e.z) ^ 2 <= range * range
end

function Stations.position(self, name: string): (number, number)
	local e = self.byName[name]
	return e.x, e.z
end

return Stations
