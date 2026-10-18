--!strict
-- Per-player token bucket rate limiter for remote events.
-- Pure Luau so the policy can be unit tested without a live server.

local Config = require("./Config")

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type Bucket = { tokens: number, lastRefill: number }

function RateLimiter.new(burst: number?, refillPerSecond: number?)
	local self = setmetatable({}, RateLimiter)
	self._burst = burst or Config.Network.RemoteBurst
	self._refill = refillPerSecond or Config.Network.RemoteRefillPerSecond
	self._buckets = {}
	return self
end

local function refill(bucket: Bucket, rate: number, burst: number, now: number)
	local elapsed = now - bucket.lastRefill
	if elapsed <= 0 then
		return
	end
	bucket.tokens = math.min(burst, bucket.tokens + elapsed * rate)
	bucket.lastRefill = now
end

-- Attempt to consume one token for `key`.
-- Returns (allowed, retryAfterSeconds).
function RateLimiter:consume(key: any, now: number): (boolean, number)
	local bucket = self._buckets[key]
	if not bucket then
		bucket = { tokens = self._burst, lastRefill = now }
		self._buckets[key] = bucket
	end

	refill(bucket, self._refill, self._burst, now)

	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true, 0
	end

	local deficit = 1 - bucket.tokens
	return false, deficit / self._refill
end

function RateLimiter:forget(key: any)
	self._buckets[key] = nil
end

function RateLimiter:tracked(): number
	local count = 0
	for _ in pairs(self._buckets) do
		count += 1
	end
	return count
end

return RateLimiter
