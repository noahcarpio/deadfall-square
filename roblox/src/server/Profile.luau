--[[
	Player profiles (Scrip, unlocked tier, cosmetics) in a DataStore, shared
	by the Home place and the game place.

	Every write is an atomic UpdateAsync transform built from the pure rules in
	Cosmetics, so the two places never overwrite each other and no session
	lock is needed. Every call is wrapped in pcall: when DataStores aren't
	available (Studio without "Enable Studio Access to API Services", or an
	outage), profiles live in memory for the session instead, and a fresh
	offline Studio profile starts with Scrip so crates can be tried.
]]
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Cosmetics = require(Shared.Cosmetics)

local STORE_NAME = "DeadfallProfile_v1"
local STUDIO_START_SCRIP = 1000

local Profile = {}

local okStore, storeOrError = pcall(function()
	return DataStoreService:GetDataStore(STORE_NAME)
end)
local store: any = if okStore then storeOrError else nil
local memory: { [number]: Cosmetics.Profile } = {}
local offline = not okStore

local function key(userId: number): string
	return `u{userId}`
end

local function offlineProfile(userId: number): Cosmetics.Profile
	local p = memory[userId]
	if not p then
		p = Cosmetics.newProfile(if RunService:IsStudio() then STUDIO_START_SCRIP else 0)
		memory[userId] = p
	end
	return p
end

-- True when profiles are only kept in memory (nothing is saved).
function Profile.isOffline(): boolean
	return offline
end

-- Loads (a normalized copy of) a player's profile.
function Profile.load(userId: number): Cosmetics.Profile
	if not offline then
		local ok, raw = pcall(function()
			return store:GetAsync(key(userId))
		end)
		if ok then
			return Cosmetics.normalize(raw)
		end
		warn(`[Profile] DataStore unavailable, keeping profiles in memory this session: {raw}`)
		offline = true
	end
	return Cosmetics.normalize(offlineProfile(userId))
end

--[[
	Applies `transform(profile)` atomically. It returns (ok, result): when ok
	is false nothing is saved. Returns ok, result and the profile as saved.
]]
function Profile.update(
	userId: number,
	transform: (Cosmetics.Profile) -> (boolean, any)
): (boolean, any, Cosmetics.Profile)
	if not offline then
		local result: any = nil
		local applied = false
		local saved: Cosmetics.Profile? = nil
		local ok, err = pcall(function()
			store:UpdateAsync(key(userId), function(old)
				local p = Cosmetics.normalize(old)
				local okT, res = transform(p)
				applied, result = okT, res
				if not okT then
					return nil -- cancel the write
				end
				saved = p
				return p
			end)
		end)
		if ok then
			return applied, result, saved or Profile.load(userId)
		end
		warn(`[Profile] DataStore unavailable, keeping profiles in memory this session: {err}`)
		offline = true
	end
	local p = offlineProfile(userId)
	local copy = Cosmetics.normalize(p)
	local okT, res = transform(copy)
	if okT then
		memory[userId] = copy
	end
	return okT, res, Cosmetics.normalize(memory[userId])
end

return Profile
