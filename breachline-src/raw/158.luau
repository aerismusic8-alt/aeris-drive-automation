--[[
	File: SeatSwapInput.luau

	Always-on client module that lets a player swap between the AirVehicle pilot
	position and a caller-owned Gunnable gunner Seat using the SwapSeat keybind.

	It binds the SwapSeat action whenever the local player is either the pilot of
	this vehicle or seated in the registered gunner Seat, and fires the shared
	SwapSeatRequest remote; the server decides the direction. The pilot controller
	deactivates while the player is the gunner, so this listener lives outside that
	lifecycle.
]]--

-- Root

local SeatSwapInput = {}

-- Roblox Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Keybinds = require(FourD.Common.Keybinds)

local InputConstants = require(script.Parent.InputConstants)

-- Constants

local SWAP_BIND_ID = "SwapSeat"
local SWAP_REMOTE_NAME = "SwapSeatRequest"
local GUNNER_SEAT_REF_NAME = "AirVehicle_GunnerSeatRef"

-- Types

export type StartOptions = {
	Root: Instance,
	VehicleModel: Model,
	SetId: string,
}

export type SeatSwapHandle = {
	Destroy: (self: SeatSwapHandle) -> (),
}

-- Public Functions

function SeatSwapInput.start(options: StartOptions): SeatSwapHandle
	local localPlayer = Players.LocalPlayer
	local root = options.Root
	local vehicleModel = options.VehicleModel
	local setId = options.SetId

	local swapRemote = vehicleModel:WaitForChild(SWAP_REMOTE_NAME) :: RemoteEvent

	local connections: { RBXScriptConnection } = {}
	local gunnerSeat: Seat? = nil
	local seatOccupantConnection: RBXScriptConnection? = nil
	local bindHandle: Keybinds.BindActionsHandle? = nil

	local function onSwapAction(state: Enum.UserInputState): Enum.ContextActionResult?
		if state == Enum.UserInputState.Begin then
			swapRemote:FireServer()
		end
		return nil
	end

	local function recompute()
		local amIPilot = root:GetAttribute(InputConstants.PILOT_USER_ID_ATTRIBUTE) == localPlayer.UserId

		local amIGunner = false
		if gunnerSeat then
			local occupant = gunnerSeat.Occupant
			amIGunner = occupant ~= nil and occupant.Parent == localPlayer.Character
		end

		local shouldBind = amIPilot or amIGunner

		if shouldBind and not bindHandle then
			bindHandle = Keybinds.bindActions(setId, {
				[SWAP_BIND_ID] = onSwapAction,
			})
		elseif not shouldBind and bindHandle then
			bindHandle:Destroy()
			bindHandle = nil
		end
	end

	local function setGunnerSeat(seat: Seat?)
		if seatOccupantConnection then
			seatOccupantConnection:Disconnect()
			seatOccupantConnection = nil
		end

		gunnerSeat = seat

		if seat then
			seatOccupantConnection = seat:GetPropertyChangedSignal("Occupant"):Connect(recompute)
		end

		recompute()
	end

	local function watchSeatRef(seatRef: ObjectValue)
		table.insert(connections, seatRef.Changed:Connect(function()
			setGunnerSeat(seatRef.Value :: Seat?)
		end))
		setGunnerSeat(seatRef.Value :: Seat?)
	end

	local existingRef = vehicleModel:FindFirstChild(GUNNER_SEAT_REF_NAME)
	if existingRef and existingRef:IsA("ObjectValue") then
		watchSeatRef(existingRef)
	else
		table.insert(connections, vehicleModel.ChildAdded:Connect(function(child: Instance)
			if child.Name == GUNNER_SEAT_REF_NAME and child:IsA("ObjectValue") then
				watchSeatRef(child)
			end
		end))
	end

	table.insert(connections, root:GetAttributeChangedSignal(InputConstants.PILOT_USER_ID_ATTRIBUTE):Connect(recompute))
	table.insert(connections, localPlayer.CharacterAdded:Connect(recompute))

	recompute()

	local handle: SeatSwapHandle = {
		Destroy = function(_: SeatSwapHandle)
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)

			if seatOccupantConnection then
				seatOccupantConnection:Disconnect()
				seatOccupantConnection = nil
			end

			if bindHandle then
				bindHandle:Destroy()
				bindHandle = nil
			end
		end,
	}

	return handle
end

-- Return

return SeatSwapInput
