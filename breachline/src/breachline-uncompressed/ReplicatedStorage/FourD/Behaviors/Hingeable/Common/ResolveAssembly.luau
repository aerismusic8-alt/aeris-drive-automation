--[[
	File: Common/ResolveAssembly.luau

	Normalizes a (assembly, params) pair into the four physical pieces every
	mode needs:

		1. `rotorPart`           -- a synthesized invisible BasePart welded
		                            into the assembly so the assembly behaves
		                            as one rigid body and we have a known
		                            BasePart for Motor6D/HingeConstraint to
		                            attach to. The caller's assembly can be
		                            any PVInstance with any internal layout
		                            (no PrimaryPart required) -- this synth
		                            removes the assumption.
		2. `anchorPart`          -- the body the hinge pivots against. Either
		                            a synthesized invisible Terrain-anchored
		                            part (world-space hinge) or a synth welded
		                            to a BasePart inside `RelativeTo` so the
		                            hinge follows that body.
		3. `rotorAttachment`     -- on `rotorPart` at the world pivot.
		4. `anchorAttachment`    -- on `anchorPart` at the world pivot.

	World pivot is derived from `assembly:GetPivot() * params.PivotCFrame`, so
	the caller specifies the pivot in the assembly's own pivot-local frame
	(works for both BaseParts and Models regardless of PrimaryPart).

	Caller side effects:
		* Every BasePart inside `assembly` is unanchored and welded to
		  `rotorPart`. The assembly becomes a single rigid body controlled by
		  the joint primitive.
		* If `params.RelativeTo` is supplied, a WeldConstraint is added between
		  the synth anchor and one BasePart inside the RelativeTo body.
]]--

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Dumpster = require(FourD.Libs.Dumpster)
local ConstructionHelpers = require(FourD.Common.ConstructionHelpers)
local HingeableRoot = FourD.Behaviors.Hingeable
local Constants = require(HingeableRoot.Common.Constants)
local Types = require(HingeableRoot.Common.Types)

-- Local Functions

local function findAnyBasePart(pvInstance: PVInstance): BasePart?
	if pvInstance:IsA("BasePart") then
		return pvInstance
	end

	if pvInstance:IsA("Model") then
		if pvInstance.PrimaryPart then
			return pvInstance.PrimaryPart
		end

		for _, descendant in pvInstance:GetDescendants() do
			if descendant:IsA("BasePart") then
				return descendant
			end
		end
	end

	return nil
end

local function buildSynthPart(name: string, worldCFrame: CFrame, anchored: boolean): BasePart
	local synth = Instance.new("Part")
	synth.Name = name
	synth.Anchored = anchored
	synth.CanCollide = false
	synth.CanQuery = false
	synth.CanTouch = false
	synth.Massless = true
	synth.Transparency = 1
	synth.Size = Vector3.new(0.05, 0.05, 0.05)
	synth.CFrame = worldCFrame
	return synth
end

-- Public Functions

export type Resolved = {
	rotorPart: BasePart,
	anchorPart: BasePart,
	rotorAttachment: Attachment,
	anchorAttachment: Attachment,
	pivotLocalCFrame: CFrame,
}

local function resolveAssembly(
	assembly: PVInstance,
	params: Types.HingeableParams,
	dumpster: typeof(Dumpster.new())
): Resolved
	assert(assembly, "assembly must not be nil")
	assert(
		typeof(assembly) == "Instance" and assembly:IsA("PVInstance"),
		"assembly must be a PVInstance (BasePart or Model)"
	)
	assert(params.PivotCFrame, "params.PivotCFrame is required")
	assert(
		findAnyBasePart(assembly),
		`assembly "{assembly:GetFullName()}" must contain at least one BasePart`
	)

	local pivotLocalCFrame = params.PivotCFrame
	local axisWorldCFrame = assembly:GetPivot() * pivotLocalCFrame

	dumpster:AttachTo(assembly)

	-- Rotor synth part lives inside the assembly when possible so it streams
	-- with it; falls back to workspace for stray BasePart assemblies with no
	-- common parent.
	local rotorParent: Instance = workspace
	if assembly:IsA("Model") then
		rotorParent = assembly
	elseif assembly.Parent then
		rotorParent = assembly.Parent
	end

	local rotorPart = buildSynthPart("HingeableRotor", axisWorldCFrame, false)
	rotorPart.Parent = rotorParent
	dumpster:Add(rotorPart)

	-- Fuse every BasePart in the assembly into one rigid body welded to the
	-- rotor synth. Side-effect: unanchors any anchored parts inside the
	-- assembly. The hinge primitive (Motor6D or HingeConstraint) becomes the
	-- only thing holding the rotor in place.
	ConstructionHelpers.weldAllParts(assembly, rotorPart)

	local anchorPart: BasePart
	if params.RelativeTo then
		assert(
			typeof(params.RelativeTo) == "Instance" and params.RelativeTo:IsA("PVInstance"),
			"params.RelativeTo must be a PVInstance"
		)
		local relPart = findAnyBasePart(params.RelativeTo)
		assert(relPart, "params.RelativeTo must contain at least one BasePart")

		local anchorParent: Instance = workspace
		if params.RelativeTo:IsA("Model") then
			anchorParent = params.RelativeTo
		elseif params.RelativeTo.Parent then
			anchorParent = params.RelativeTo.Parent
		end

		anchorPart = buildSynthPart(Constants.ANCHOR_PART_NAME, axisWorldCFrame, false)
		anchorPart.Parent = anchorParent

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = anchorPart
		weld.Part1 = relPart
		weld.Parent = anchorPart

		dumpster:AttachTo(params.RelativeTo)
	else
		anchorPart = buildSynthPart(Constants.ANCHOR_PART_NAME, axisWorldCFrame, true)
		anchorPart.Parent = workspace.Terrain
	end
	dumpster:Add(anchorPart)

	local rotorAttachment = Instance.new("Attachment")
	rotorAttachment.Name = "Hingeable_RotorAttachment"
	rotorAttachment.Parent = rotorPart
	rotorAttachment.WorldCFrame = axisWorldCFrame
	dumpster:Add(rotorAttachment)

	local anchorAttachment = Instance.new("Attachment")
	anchorAttachment.Name = "Hingeable_AnchorAttachment"
	anchorAttachment.Parent = anchorPart
	anchorAttachment.WorldCFrame = axisWorldCFrame
	dumpster:Add(anchorAttachment)

	-- Resolved.pivotLocalCFrame is consumed by JointBuilder relative to
	-- rotorPart, not the original assembly. Because rotorPart was placed at
	-- axisWorldCFrame above, the rotor-local pivot is identity.
	return {
		rotorPart = rotorPart,
		anchorPart = anchorPart,
		rotorAttachment = rotorAttachment,
		anchorAttachment = anchorAttachment,
		pivotLocalCFrame = CFrame.identity,
	}
end

return resolveAssembly
