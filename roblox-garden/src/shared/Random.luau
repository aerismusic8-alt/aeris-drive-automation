--!strict
-- Deterministic pseudo random number generator.
--
-- xorshift128 with a splitmix32 seeding stage. Uses bit32 so the module runs
-- identically inside Roblox and in the standalone Luau CLI used by tests.

local Random = {}
Random.__index = Random

local band = bit32.band
local bxor = bit32.bxor
local lshift = bit32.lshift
local rshift = bit32.rshift

local TWO32 = 4294967296

-- (a * b) mod 2^32 without losing precision to float64 mantissa limits.
local function mul32(a: number, b: number): number
	local a0 = a % 65536
	local a1 = math.floor(a / 65536)
	local b0 = b % 65536
	local b1 = math.floor(b / 65536)

	local lo = a0 * b0
	local mid = (a0 * b1 + a1 * b0) % 65536
	return (lo + mid * 65536) % TWO32
end

-- splitmix32: strong avalanche from a single integer seed.
local function splitmix32(seed: number): () -> number
	local state = seed % TWO32
	return function(): number
		state = (state + 0x9E3779B9) % TWO32
		local z = state
		z = mul32(bxor(z, rshift(z, 16)), 0x21F0AAAD)
		z = mul32(bxor(z, rshift(z, 15)), 0x735A2D97)
		return bxor(z, rshift(z, 15))
	end
end

function Random.new(seed: number?)
	local s = seed or os.time()
	local nextSeed = splitmix32(s)
	local x = nextSeed()
	local y = nextSeed()
	local z = nextSeed()
	local w = nextSeed()

	-- Guard against the all-zero state, which is a fixed point.
	if x == 0 and y == 0 and z == 0 and w == 0 then
		w = 1
	end

	return setmetatable({ _x = x, _y = y, _z = z, _w = w }, Random)
end

-- Raw 32-bit unsigned draw.
function Random:nextInt(): number
	local x, y, z, w = self._x, self._y, self._z, self._w
	local t = bxor(x, lshift(x, 11))
	self._x, self._y, self._z = y, z, w
	w = bxor(w, rshift(w, 19))
	w = bxor(w, bxor(t, rshift(t, 8)))
	self._w = w
	return w
end

-- Uniform float in [0, 1).
function Random:nextNumber(): number
	return self:nextInt() / TWO32
end

-- Uniform integer in [min, max] inclusive.
function Random:nextInteger(min: number, max: number): number
	assert(min <= max, "min must be <= max")
	assert(min == math.floor(min) and max == math.floor(max), "bounds must be integers")
	local span = max - min + 1
	if span >= TWO32 then
		return min + self:nextInt()
	end
	return min + (self:nextInt() % span)
end

function Random:nextBool(probability: number?): boolean
	return self:nextNumber() < (probability or 0.5)
end

export type WeightedEntry = { weight: number, [any]: any }

-- Weighted pick. Returns nil when the table is empty or has no positive weight.
function Random:pickWeighted(entries: { WeightedEntry }): WeightedEntry?
	local total = 0
	for _, entry in ipairs(entries) do
		local w = entry.weight or 0
		if w > 0 then
			total += w
		end
	end
	if total <= 0 then
		return nil
	end

	local roll = self:nextNumber() * total
	local acc = 0
	local last: WeightedEntry? = nil
	for _, entry in ipairs(entries) do
		local w = entry.weight or 0
		if w > 0 then
			acc += w
			last = entry
			if roll < acc then
				return entry
			end
		end
	end
	return last
end

return Random
