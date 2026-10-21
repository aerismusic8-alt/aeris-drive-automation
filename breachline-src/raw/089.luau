--[[
	File: Common/BuildBulletTemplate.luau

	Builds a cosmetic bullet Part with Beam + Glow Beam + Trail effects, and
	provides a higher-level `setup` helper that wires the template into the
	rig (parents the template to the assembled model and creates the
	Gunnable_BulletProjectile ObjectValue + TracerShot UnreliableRemoteEvent).

	If a `projectileSource` Model is supplied, its visual BaseParts are
	cloned onto the template and the Front/Rear/TrailF/TrailR attachments
	are re-parented to the first cloned visual.
]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildBulletTemplate = {}

-- Cosmetic bullet templates live in a shared ReplicatedStorage folder, never in
-- the rig itself. A template parented to the assembled model sits at the world
-- origin (it is never positioned), which is invisible in play but drags the
-- model's GetBoundingBox center tens of studs toward (0,0,0) -- breaking camera
-- framing, placement, and measurement. Mirrors Launcher's Gunnable_LauncherProjectiles.
local BULLET_TEMPLATE_FOLDER_NAME = "Gunnable_BulletProjectiles"

local function getTemplateFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(BULLET_TEMPLATE_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = BULLET_TEMPLATE_FOLDER_NAME
	folder.Parent = ReplicatedStorage

	return folder
end

local function buildTemplate(tracerColor: Color3, glowColor: Color3, trailColor: Color3, projectileSource: Instance?): BasePart
	local bulletTemplate = Instance.new("Part")
	bulletTemplate.Name = "CosmeticBullet"
	bulletTemplate.Size = Vector3.new(0.3, 0.3, 0.3)
	bulletTemplate.Transparency = 1
	bulletTemplate.Anchored = true
	bulletTemplate.CanCollide = false
	bulletTemplate.CanTouch = false
	bulletTemplate.CanQuery = false
	bulletTemplate.CastShadow = false

	local fa = Instance.new("Attachment")
	fa.Name = "Front"
	fa.Position = Vector3.new(0, 0, -1.5)
	fa.Parent = bulletTemplate

	local ra = Instance.new("Attachment")
	ra.Name = "Rear"
	ra.Position = Vector3.new(0, 0, 1.5)
	ra.Parent = bulletTemplate

	local cb = Instance.new("Beam")
	cb.Attachment0 = fa
	cb.Attachment1 = ra
	cb.Texture = "rbxassetid://14364459325"
	cb.Color = ColorSequence.new(tracerColor)
	cb.Brightness = 5.225
	cb.LightEmission = 1
	cb.LightInfluence = 0
	cb.FaceCamera = true
	cb.Segments = 10
	cb.TextureLength = 10
	cb.TextureMode = Enum.TextureMode.Wrap
	cb.TextureSpeed = 3
	cb.Width0 = 1
	cb.Width1 = 1
	cb.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	cb.Parent = bulletTemplate

	local gb = Instance.new("Beam")
	gb.Attachment0 = fa
	gb.Attachment1 = ra
	gb.Texture = "rbxassetid://14364454897"
	gb.Color = ColorSequence.new(glowColor)
	gb.Brightness = 3
	gb.LightEmission = 1
	gb.LightInfluence = 0
	gb.FaceCamera = true
	gb.Segments = 10
	gb.TextureLength = 20
	gb.TextureMode = Enum.TextureMode.Wrap
	gb.TextureSpeed = 2
	gb.Width0 = 3
	gb.Width1 = 1
	gb.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 0.1),
		NumberSequenceKeypoint.new(1, 0.5),
	})
	gb.Parent = bulletTemplate

	local tf = Instance.new("Attachment")
	tf.Name = "TrailF"
	tf.Position = Vector3.new(0, 0, -0.2)
	tf.Parent = bulletTemplate

	local tr = Instance.new("Attachment")
	tr.Name = "TrailR"
	tr.Position = Vector3.new(0, 0, 0.2)
	tr.Parent = bulletTemplate

	local trail = Instance.new("Trail")
	trail.Attachment0 = tf
	trail.Attachment1 = tr
	trail.Color = ColorSequence.new(trailColor)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.15
	trail.MinLength = 0.1
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Parent = bulletTemplate

	if projectileSource then
		for _, p in ipairs(projectileSource:GetDescendants()) do
			if p:IsA("BasePart") then
				local vp = p:Clone()
				vp.Name = "Visual"
				vp.CFrame = bulletTemplate.CFrame
				vp.Anchored = true
				vp.CanCollide = false
				vp.CanTouch = false
				vp.Massless = true
				vp.Parent = bulletTemplate
				fa.Parent = vp
				ra.Parent = vp
				tf.Parent = vp
				tr.Parent = vp
			end
		end
	end

	return bulletTemplate
end

---Builds a cosmetic bullet template from explicit colors + optional source.
function BuildBulletTemplate.build(tracerColor: Color3, glowColor: Color3, trailColor: Color3, projectileSource: Instance?): BasePart
	return buildTemplate(tracerColor, glowColor, trailColor, projectileSource)
end

---Reads the `GunnableConfig.projectileName` value on `assembledModel`,
---resolves the optional `ReplicatedStorage.FourD.Projectiles[name]` model,
---builds a bullet template from that model's TracerColor/GlowColor/
---TrailColor attributes (falling back to defaults), parents the template
---under the assembled model, exposes it via a
---`Gunnable_BulletProjectile` ObjectValue, and creates a `TracerShot`
---UnreliableRemoteEvent on `assembledModel`.
function BuildBulletTemplate.setup(assembledModel: Model): UnreliableRemoteEvent
	local cfg = assembledModel:FindFirstChild("GunnableHardpointConfig")
	local projNameValue = if cfg then cfg:FindFirstChild("projectileName") else nil
	local projName = if projNameValue then projNameValue.Value else ""

	local projectileSource: Instance? = nil
	if projName ~= "" then
		local fourD = ReplicatedStorage:FindFirstChild("FourD")
		local pf = fourD and fourD:FindFirstChild("Projectiles")
		if pf then projectileSource = pf:FindFirstChild(projName) end
	end

	local function attr(name: string, default: any): any
		if projectileSource and projectileSource:GetAttribute(name) ~= nil then
			return projectileSource:GetAttribute(name)
		end

		return default
	end

	local function configColor(name: string): Color3?
		local value = if cfg then cfg:FindFirstChild(name) else nil
		if value and value:IsA("Color3Value") then return value.Value end

		return nil
	end

	local override = configColor("tracerColor")
	local tracerColor = override or attr("TracerColor", Color3.fromRGB(255, 200, 50))
	local glowColor = if override then override:Lerp(Color3.new(0, 0, 0), 0.25) else attr("GlowColor", Color3.fromRGB(218, 150, 0))
	local trailColor = override or attr("TrailColor", Color3.fromRGB(255, 200, 50))

	local template = buildTemplate(tracerColor, glowColor, trailColor, projectileSource)
	template.Name = assembledModel.Name .. "_BulletProjectile"
	-- Parent to the shared ReplicatedStorage folder, not the rig: keeps the
	-- world-origin template out of the model's bounding box. Consumers resolve it
	-- through the Gunnable_BulletProjectile ObjectValue below, so location is free.
	template.Parent = getTemplateFolder()

	local templateRef = Instance.new("ObjectValue")
	templateRef.Name = "Gunnable_BulletProjectile"
	templateRef.Value = template
	templateRef.Parent = assembledModel

	local tracerEvent = Instance.new("UnreliableRemoteEvent")
	tracerEvent.Name = "TracerShot"
	tracerEvent.Parent = assembledModel

	return tracerEvent
end

return BuildBulletTemplate
