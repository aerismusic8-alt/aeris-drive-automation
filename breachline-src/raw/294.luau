 a handheld tool that emits a directed beam of light. Flashlight3Capability creates an equippable Tool with a toggleable directional light.',
				capability_selection = "Flashlight3Capability",
				overall_size_reasoning = "A flashlight for a Roblox avatar should be roughly hand-sized: about 0.5m long (z), 0.25m diameter (y/x).",
				overall_size_selection = { x = 0.25, y = 0.25, z = 0.5 },
			},
		},
	}
end

function Flashlight3:getConfigureCapabilityExamples()
	return {
		{
			user = "an old flashlight",
			assistant = {
				capability_parameters_reasoning = "An older flashlight emits soft, warm, low-brightness light with a wide spread angle.",
				capability_parameters_selection = {
					lightColor3 = Color3.fromRGB(255, 200, 120),
					lightBrightness = 2,
					lightRange = 12,
					lightSpread = 90,
				},
			},
		},
		{
			user = "a police tactical flashlight",
			assistant = {
				capability_parameters_reasoning = "A tactical flashlight emits a bright white focused beam with high brightness and narrow spread.",
				capability_parameters_selection = {
					lightColor3 = Color3.new(1, 1, 1),
					lightBrightness = 8,
					lightRange = 40,
					lightSpread = 20,
				},
			},
		},
	}
end

function Flashlight3:bind(generatedModels: { [string]: Model }, parameters: { [string]: any }): Tool
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("Flashlight3Capability configuration error: " .. errorMsg)
	end

	local flashlightModel = generatedModels["flashlight"]
	if not flashlightModel then
		error("Flashlight3Capability: Could not find 'flashlight' model")
	end

	return MakeFunctional(flashlightModel, parameters)
end

return Flashlight3
