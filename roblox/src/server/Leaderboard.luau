--[[
	Global top-10 by best score, stored in an OrderedDataStore. Every call is
	wrapped in pcall: in Studio with "Enable Studio Access to API Services"
	off, or during DataStore outages, the board is simply unavailable.
]]
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local STORE_NAME = "DeadfallSquareBestScore_v1"
local CACHE_SECONDS = 60

local Leaderboard = {}
Leaderboard.__index = Leaderboard

function Leaderboard.new()
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(STORE_NAME)
	end)
	return setmetatable({
		store = if ok then store else nil,
		cache = nil :: { any }?,
		cacheTime = 0,
		names = {} :: { [number]: string },
	}, Leaderboard)
end

-- Saves a score if it beats the player's best. Runs asynchronously.
function Leaderboard.submit(self, userId: number, score: number)
	local store = self.store
	if not store or score <= 0 or userId <= 0 then
		return
	end
	task.spawn(function()
		pcall(function()
			store:UpdateAsync(tostring(userId), function(old)
				if type(old) == "number" and old >= score then
					return nil
				end
				return math.floor(score)
			end)
		end)
		self.cache = nil
	end)
end

function Leaderboard.nameFor(self, userId: number): string
	local cached = self.names[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and type(name) == "string" then name else `Player {userId}`
	self.names[userId] = result
	return result
end

-- Returns { available = bool, entries = { { name, score } } }.
function Leaderboard.top(self): { [string]: any }
	local store = self.store
	if not store then
		return { available = false, entries = {} }
	end
	if self.cache and os.clock() - self.cacheTime < CACHE_SECONDS then
		return { available = true, entries = self.cache }
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, 10)
	end)
	if not ok or not pages then
		return { available = false, entries = {} }
	end
	local entries = {}
	for _, item in pages:GetCurrentPage() do
		local userId = tonumber(item.key) or 0
		table.insert(entries, { name = self:nameFor(userId), score = item.value })
	end
	self.cache = entries
	self.cacheTime = os.clock()
	return { available = true, entries = entries }
end

return Leaderboard
