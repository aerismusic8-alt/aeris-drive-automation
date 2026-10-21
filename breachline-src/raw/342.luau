 an underwater vessel with dive capability. SubmarineSimple2Capability is the correct choice; the color is handled by model generation.",
				capability_selection = "SubmarineSimple2Capability",
				overall_size_reasoning = "A classic submarine shape, roughly 2.0m wide, 2.0m tall, and 6m long.",
				overall_size_selection = { x = 2.0, y = 2.0, z = 6.0 },
			},
		},
	}
end

function SubmarineSimple2:getConfigureCapabilityExamples()
	return {
		{
			user = "a submarine",
			assistant = {
				capability_parameters_reasoning = "A standard submarine uses default thrust, steering, and dive speed values. No overrides needed.",
				capability_parameters_selection = {},
			},
		},
		{
			user = "a fast submarine",
			assistant = {
				capability_parameters_reasoning = "A fast submarine should have a higher top speed and quicker acceleration.",
				capability_parameters_selection = {
					maxForwardSpeed = 70,
					maxReverseSpeed = 35,
					acceleration = 15,
				},
			},
		},
	}
end

function SubmarineSimple2:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then
		error("SubmarineSimple2Capability configuration error: " .. errorMsg)
	end

	local model = generatedModels["submarine"]
	if not model then
		error("Could not find 'submarine' model in generatedModels")
	end

	return MakeFunctional(model, parameters)
end

return SubmarineSimple2
B