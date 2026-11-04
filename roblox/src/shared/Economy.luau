--!strict
-- Coins, score and the kill-combo multiplier for one player.
local Economy = {}
Economy.__index = Economy

export type Economy = typeof(setmetatable(
	{} :: {
		coins: number,
		score: number,
		totalCoinsEarned: number,
		comboCount: number,
		comboTimer: number,
		bestCombo: number,
		coinMultiplier: number,
		comboWindow: number,
	},
	Economy
))

function Economy.new(): Economy
	return setmetatable({
		coins = 0,
		score = 0,
		totalCoinsEarned = 0,
		comboCount = 0,
		comboTimer = 0,
		bestCombo = 0,
		coinMultiplier = 1,
		comboWindow = 3,
	}, Economy)
end

-- Score multiplier: +0.5x for every 5 chained kills, capped at 5x.
function Economy.multiplier(self: Economy): number
	return math.min(5, 1 + (self.comboCount // 5) * 0.5)
end

function Economy.comboRemaining(self: Economy): number
	return if self.comboCount > 0 then self.comboTimer / self.comboWindow else 0
end

function Economy.addCoins(self: Economy, amount: number)
	local a = math.max(0, math.floor(amount + 0.5))
	self.coins += a
	self.totalCoinsEarned += a
end

function Economy.registerKill(self: Economy, baseScore: number, baseCoins: number): (number, number)
	self.comboCount += 1
	self.comboTimer = self.comboWindow
	self.bestCombo = math.max(self.bestCombo, self.comboCount)
	local score = math.floor(baseScore * self:multiplier() + 0.5)
	local coins = math.max(1, math.floor(baseCoins * self.coinMultiplier + 0.5))
	self.score += score
	self:addCoins(coins)
	return score, coins
end

function Economy.spend(self: Economy, cost: number): boolean
	if cost < 0 or self.coins < cost then
		return false
	end
	self.coins -= cost
	return true
end

function Economy.update(self: Economy, dt: number)
	if self.comboCount == 0 then
		return
	end
	self.comboTimer -= dt
	if self.comboTimer <= 0 then
		self.comboTimer = 0
		self.comboCount = 0
	end
end

return Economy
