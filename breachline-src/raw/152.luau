--[[
	File: Mounting.luau
]]--

-- Root

local Mounting = {}

-- Roblox Services

local Players = game:GetService("Players")

-- Dependencies

local CharacterUtils = require(script.Parent.CharacterUtils)
local NetworkOwnership = require(script.Parent.NetworkOwnership)

-- Constants

local DEFAULT_PILOT_USER_ID_ATTRIBUTE = "PilotUserId"

-- Local Functions

local function defaultPlacementOffset(root: BasePart, hipHeight: number): CFrame
	local rootTop = root.CFrame * CFrame.new(0, root.Size.Y * 0.5, 0)
	local placePos = rootTop.Position + Vector3.new(0, hipHeight, 0)
	return CFrame.lookAt(placePos, placePos + root.CFrame.LookVector)
end

local function tryGetMountTargets(player: Player): (Model?, BasePart?, Humanoid?)
	local character = player.Character
	if not character then return nil, nil, nil end

	local rootPart = character.PrimaryPart
	if not rootPart then return nil, nil, nil end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil, nil, nil end
	if humanoid.Health <= 0 then return nil, nil, nil end

	return character, rootPart, humanoid
end

local function setPlatformStanding(humanoid: Humanoid, enabled: boolean)
	if enabled then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, true)
		humanoid:ChangeState(Enum.HumanoidStateType.PlatformStanding)
		humanoid.PlatformStand = true
	else
		humanoid.PlatformStand = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local function createPilotWeld(part0: BasePart, part1: BasePart, parent: BasePart): WeldConstraint
	local pilotWeld = Instance.new("WeldConstraint")
	pilotWeld.Name = "PilotWeld"
	pilotWeld.Part0 = part0
	pilotWeld.Part1 = part1
	pilotWeld.Parent = parent
	return pilotWeld
end

local function claimVehicle(vehicleModel: Model, root: BasePart, player: Player, pilotAttribute: string)
	NetworkOwnership.setOwner(vehicleModel, player)
	root:SetAttribute(pilotAttribute, player.UserId)
end

local function releaseVehicle(vehicleModel: Model, root: BasePart, pilotAttribute: string)
	NetworkOwnership.setOwner(vehicleModel, nil)
	root:SetAttribute(pilotAttribute, 0)
end

local function wireAutoUnmount(pilotDump: any, player: Player, character: Model, humanoid: Humanoid, performUnmount: (boolean) -> ())
	pilotDump:Connect(humanoid.Died, function()
		performUnmount(true)
	end)

	pilotDump:Connect(character.AncestryChanged, function(_child: Instance, parent: Instance?)
		if parent == nil then
			performUnmount(true)
		end
	end)

	pilotDump:Connect(Players.PlayerRemoving, function(leavingPlayer: Player)
		if leavingPlayer == player then
			performUnmount(true)
		end
	end)
end

-- Public Functions

local function attachPlayer(options: AttachOptions): MountSession?
	local player = options.Player
	local root = options.Root
	local vehicleModel = options.VehicleModel
	local parentDump = options.ParentDump
	local pilotAttribute = options.PilotAttribute

	local character, rootPart, humanoid = tryGetMountTargets(player)
	if not character or not rootPart or not humanoid then return nil end

	if options.PlatformStand then
		setPlatformStanding(humanoid, true)
	end

	options.PlaceBody(root, rootPart, humanoid)

	CharacterUtils.setCharacterMassless(character, true)

	if options.HideCharacter then
		CharacterUtils.hideCharacter(character)
	end

	local pilotWeld = if options.WeldOnRoot
		then createPilotWeld(root, rootPart, root)
		else createPilotWeld(rootPart, root, rootPart)

	claimVehicle(vehicleModel, root, player, pilotAttribute)

	local pilotDump = parentDump:Extend()

	if options.OnMounted then
		options.OnMounted()
	end

	local unmounted = false
	local session: MountSession = {
		Player = player,
		Unmount = function(_skipTeleport: boolean) end,
	}

	local function performUnmount(skipTeleport: boolean)
		if unmounted then return end
		unmounted = true

		if pilotWeld.Parent then
			pilotWeld:Destroy()
		end

		local currentCharacter = player.Character
		if currentCharacter then
			local currentHumanoid = currentCharacter:FindFirstChildOfClass("Humanoid")

			if options.HideCharacter then
				CharacterUtils.showCharacter(currentCharacter)
			end

			CharacterUtils.setCharacterMassless(currentCharacter, false)

			if options.PlatformStand and currentHumanoid then
				setPlatformStanding(currentHumanoid, false)
			end
		end

		releaseVehicle(vehicleModel, root, pilotAttribute)

		if options.OnUnmounted then
			options.OnUnmounted(skipTeleport)
		end

		pilotDump:Destroy()
	end

	session.Unmount = performUnmount
	wireAutoUnmount(pilotDump, player, character, humanoid, performUnmount)

	return session
end

function Mounting.tryMount(config: MountConfig): MountSession?
	local placementOffset = config.PlacementOffset or defaultPlacementOffset
	local hideCharacter = if config.HideCharacter == nil then true else config.HideCharacter
	local platformStand = if config.PlatformStand == nil then true else config.PlatformStand

	return attachPlayer({
		Player = config.Player,
		Root = config.Root,
		VehicleModel = config.VehicleModel,
		ParentDump = config.ParentDump,
		PilotAttribute = config.PilotUserIdAttribute or DEFAULT_PILOT_USER_ID_ATTRIBUTE,
		PlaceBody = function(root: BasePart, rootPart: BasePart, humanoid: Humanoid)
			local hipHeight = CharacterUtils.getHipHeight(humanoid)
			rootPart.CFrame = placementOffset(root, hipHeight)
		end,
		WeldOnRoot = false,
		HideCharacter = hideCharacter,
		PlatformStand = platformStand,
		OnMounted = config.OnMounted,
		OnUnmounted = config.OnUnmounted,
	})
end

function Mounting.tryWear(config: WearConfig): MountSession?
	local backOffset = config.BackOffset or config.Root.Size.Z * 0.5

	return attachPlayer({
		Player = config.Player,
		Root = config.Root,
		VehicleModel = config.VehicleModel,
		ParentDump = config.ParentDump,
		PilotAttribute = config.PilotUserIdAttribute or DEFAULT_PILOT_USER_ID_ATTRIBUTE,
		PlaceBody = function(root: BasePart, rootPart: BasePart, _humanoid: Humanoid)
			root.CFrame = rootPart.CFrame * CFrame.new(0, 0, rootPart.Size.Z * 0.5 + backOffset)
		end,
		WeldOnRoot = true,
		HideCharacter = false,
		PlatformStand = true,
		OnMounted = config.OnMounted,
		OnUnmounted = config.OnUnmounted,
	})
end

-- Types

export type MountConfig = {
	Player: Player,
	Root: BasePart,
	VehicleModel: Model,
	ParentDump: any,
	PilotUserIdAttribute: string?,
	PlacementOffset: ((root: BasePart, hipHeight: number) -> CFrame)?,
	HideCharacter: boolean?,
	PlatformStand: boolean?,
	OnMounted: (() -> ())?,
	OnUnmounted: ((skipTeleport: boolean) -> ())?,
}

export type MountSession = {
	Player: Player,
	Unmount: (skipTeleport: boolean) -> (),
}

export type WearConfig = {
	Player: Player,
	Root: BasePart,
	VehicleModel: Model,
	ParentDump: any,
	PilotUserIdAttribute: string?,
	-- Clearance behind the character's HumanoidRootPart back face. HRP half-depth
	-- is added internally so callers pass only body-thickness + desired air gap.
	BackOffset: number?,
	OnMounted: (() -> ())?,
	OnUnmounted: ((skipTeleport: boolean) -> ())?,
}


type AttachOptions = {
	Player: Player,
	Root: BasePart,
	VehicleModel: Model,
	ParentDump: any,
	PilotAttribute: string,
	PlaceBody: (root: BasePart, rootPart: BasePart, humanoid: Humanoid) -> (),
	WeldOnRoot: boolean,
	HideCharacter: boolean,
	PlatformStand: boolean,
	OnMounted: (() -> ())?,
	OnUnmounted: ((skipTeleport: boolean) -> ())?,
}

-- Return

return Mounting
