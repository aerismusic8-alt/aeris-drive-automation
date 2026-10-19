--!strict
-- The axe: harvesting crops charges it, and a swing spends every charge at
-- once for a big area hit.
--
-- This is the bridge between the two halves of the game. Farming is not a side
-- activity; it is how you charge the weapon you fight with.
--
-- Pure Luau so the charge and damage maths can be tested directly.

local Config = require("./Config")

local Axe = {}

export type State = {
        charges: number,
}

function Axe.new(): State
        return { charges = 0 }
end

function Axe.maxCharges(): number
        return Config.Farm.AxeMaxCharges
end

-- Add charges, clamped to the cap. Returns the new charge count.
function Axe.addCharges(state: State, count: number): number
        if count <= 0 then
                return state.charges
        end
        state.charges = math.min(Axe.maxCharges(), state.charges + count)
        return state.charges
end

function Axe.isReady(state: State): boolean
        return state.charges > 0
end

-- Damage of a swing at the given charge count. Zero charges means no swing.
function Axe.swingDamage(charges: number, baseDamage: number): number
        if charges <= 0 then
                return 0
        end
        local multiplier = 1 + charges * Config.Farm.AxeDamagePerCharge
        return math.floor(baseDamage * multiplier + 0.5)
end

-- Spend every charge. Returns (chargesSpent, damage) or (0, 0) when empty.
-- The whole point of the axe is the burst, so it never spends a partial stack.
function Axe.swing(state: State, baseDamage: number): (number, number)
        local charges = state.charges
        if charges <= 0 then
                return 0, 0
        end
        state.charges = 0
        return charges, Axe.swingDamage(charges, baseDamage)
end

function Axe.snapshot(state: State): any
        return {
                charges = state.charges,
                maxCharges = Axe.maxCharges(),
        }
end

return Axe
