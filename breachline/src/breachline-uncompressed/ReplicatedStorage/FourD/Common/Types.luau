local Types = {}

export type table = { [any]: any }

export type ModelSpec = {
	name: string,
	modelSchema: string,
	description: string,
	generationOptions: { [string]: any }?,
}

export type Capability = {
	new: () -> Capability,
	-- Core capability methods
	getModelSpecs: (self: Capability) -> { ModelSpec },
	getBindParametersDefinition: (self: Capability) -> table,
	getCapabilityDocumentation: (self: Capability) -> string,
	getCapabilitySelectionExamples: (self: Capability) -> { table },
	getModelPlanningExamples: (self: Capability) -> { table },
	getConfigureCapabilityExamples: (self: Capability) -> { table },
	bind: (self: Capability, model: Instance, relevantInstances: table, config: table) -> Instance,
	validateConfig: (self: Capability, config: table) -> (boolean, string?),

	-- Properties
	configurationExamples: table,
	selectionExamples: table,
}

export type CapabilityManager = {
	new: () -> CapabilityManager,
	registerCapability: (self: CapabilityManager, name: string, capability: Capability) -> (),
	getAvailableCapabilityNames: (self: CapabilityManager) -> { string },
	getCapabilityInstance: (self: CapabilityManager, name: string) -> Capability?,
}

export type CapabilitySelectionSchema = {
	capability_reasoning: string,
	capability: string,
	size_reasoning: string,
	overall_size: { x: number, y: number, z: number },
}

export type ConfigureCapabilitySchema = {
	capability_parameters_reasoning: string,
	capability_parameters: table,
}

export type ModelPlanningSchema = {
	size_reasoning: string,
	[string]: { description: string, size: { x: number, y: number, z: number } },
}

export type CapabilitySelectionExampleSchema = {
	user: string,
	assistant: CapabilitySelectionSchema,
}

export type ModelPlanningExampleSchema = {
	user: string,
	assistant: ModelPlanningSchema,
}

export type ConfigureCapabilityExampleSchema = {
	user: string,
	assistant: ConfigureCapabilitySchema,
}

return Types
