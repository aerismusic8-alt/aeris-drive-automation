-- GENERATED WRAPPER around upstream FX.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
-- Use WaitForChild for runtime-replicated dependencies. Same race as
-- ClientController/init.server.luau: this script has RunContext = Client and so can
-- begin executing on a client before its sibling ModuleScripts (Constants in
-- particular) have finished replicating for runtime-spawned bikes (SchemaGen,
-- GenerationService). Direct dot indexing throws and the script dies before the
-- nitro / audio listeners are connected -- the symptom is a generated bike where
-- everything else works but nitro FX never play. Mirror of the FourWheel fix.
local scriptsFolder = script.Parent.Parent
local car = scriptsFolder.Parent

local Constants = require(scriptsFolder:WaitForChild("Constants"))
local Audio = require(script:WaitForChild("Audio"))
local Particles = require(script:WaitForChild("Particles"))

local driverSeat = car:WaitForChild("DriverSeat")
local engine = car:WaitForChild("Engine")

local function onOccupantChanged()
	if driverSeat.Occupant then
		Audio.startupEngine()
	else
		Audio.shutdownEngine()
	end
end

local function onNitroEnabledChanged()
	local isNitroEnabled = engine:GetAttribute(Constants.NITRO_ENABLED_ATTRIBUTE)
	if isNitroEnabled then
		Audio.startNitro()
		Particles.startNitro()
	else
		Audio.stopNitro()
		Particles.stopNitro()
	end
end

local function initialize()
	driverSeat:GetPropertyChangedSignal("Occupant"):Connect(onOccupantChanged)
	engine:GetAttributeChangedSignal(Constants.NITRO_ENABLED_ATTRIBUTE):Connect(onNitroEnabledChanged)

	onOccupantChanged()
	onNitroEnabledChanged()
end

initialize()

end
