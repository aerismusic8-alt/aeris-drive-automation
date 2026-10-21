-- Central client runtime for completed edit-time FourD rigs.
--
-- A rig is already mechanically assembled before Play. This runtime only
-- starts the client components its manifest declares -- input, camera, UI, and
-- effects. Each component is a ModuleScript (reached directly or through an
-- ObjectValue in `FourDRuntimeManifest.ClientComponents`) that returns a
-- `start(root, manifest)` function, or a table carrying one, and may return a
-- cleanup function.

local CollectionService = game:GetService("CollectionService")

local RIG_TAG = "FourDClientRig"
local MANIFEST_NAME = "FourDRuntimeManifest"
local COMPONENTS_NAME = "ClientComponents"
local WAIT_SECONDS = 10
local RUNTIME_VERSION = 1

type Cleanup = () -> ()
type Session = {
	cleanups: { Cleanup },
	started: { [Instance]: boolean },
	connections: { RBXScriptConnection },
}

local sessions: { [Instance]: Session } = {}

local function waitForChild(parent: Instance, name: string, className: string?): Instance?
	local deadline = os.clock() + WAIT_SECONDS
	repeat
		local child = parent:FindFirstChild(name)
		if child and (className == nil or child:IsA(className)) then return child end
		task.wait()
	until os.clock() >= deadline or parent.Parent == nil
	return nil
end

local function resolveModule(reference: Instance): ModuleScript?
	if reference:IsA("ModuleScript") then return reference end
	if not reference:IsA("ObjectValue") then return nil end
	local deadline = os.clock() + WAIT_SECONDS
	repeat
		local value = reference.Value
		if value and value:IsA("ModuleScript") then return value end
		task.wait()
	until os.clock() >= deadline or reference.Parent == nil
	return nil
end

local function stop(root: Instance, clearStatus: boolean?)
	local session = sessions[root]
	if not session then return end
	sessions[root] = nil
	for _, connection in session.connections do
		connection:Disconnect()
	end
	for index = #session.cleanups, 1, -1 do
		pcall(session.cleanups[index])
	end
	if clearStatus then
		root:SetAttribute("FourDClientStatus", nil)
		root:SetAttribute("FourDClientError", nil)
	end
end

-- Start one declared component. Each runs on its own thread: a component may
-- yield on WaitForChild for parts of the rig still streaming in, and must not
-- block its siblings or the rig from going ready. A component that errors is
-- warned about and recorded in FourDClientError, but does not fail the rig --
-- one bad renderer must not take out the rest of the client side.
local function startComponent(root: Instance, manifest: Instance, session: Session, declaration: Instance)
	if session.started[declaration] then return end
	session.started[declaration] = true
	task.spawn(function()
		local module = resolveModule(declaration)
		if not module then
			root:SetAttribute("FourDClientError", `unresolved client component {declaration.Name}`)
			warn(`[FourDClientRuntime] unresolved client component {declaration:GetFullName()}`)
			return
		end
		local ok, component = pcall(require, module)
		if not ok then
			root:SetAttribute("FourDClientError", `loading {module:GetFullName()}: {tostring(component)}`)
			warn(`[FourDClientRuntime] require {module:GetFullName()}: {tostring(component)}`)
			return
		end
		local starter = if type(component) == "function"
			then component
			elseif type(component) == "table" then component.start
			else nil
		if type(starter) ~= "function" then
			root:SetAttribute("FourDClientError", `{module:GetFullName()} exports no start function`)
			warn(`[FourDClientRuntime] {module:GetFullName()} exports no start function`)
			return
		end
		local started, cleanup = pcall(starter, root, manifest)
		if not started then
			root:SetAttribute("FourDClientError", `starting {module:GetFullName()}: {tostring(cleanup)}`)
			warn(`[FourDClientRuntime] start {module:GetFullName()}: {tostring(cleanup)}`)
			return
		end
		-- The rig may have been removed while this component was starting.
		if type(cleanup) == "function" and sessions[root] == session then
			table.insert(session.cleanups, cleanup)
		end
	end)
end

local function start(root: Instance)
	if sessions[root] then return end
	local session: Session = { cleanups = {}, started = {}, connections = {} }
	sessions[root] = session
	root:SetAttribute("FourDClientStatus", "starting")
	root:SetAttribute("FourDClientVersion", RUNTIME_VERSION)
	root:SetAttribute("FourDClientError", nil)

	local manifest = waitForChild(root, MANIFEST_NAME, "Folder")
	if not manifest then
		root:SetAttribute("FourDClientStatus", "failed")
		root:SetAttribute("FourDClientError", `missing {MANIFEST_NAME}`)
		stop(root, false)
		return
	end

	-- The ClientComponents folder is always compiled into the manifest, but it
	-- and the ObjectValues it holds stream to the client a frame or more after
	-- the tagged root arrives. Discovery is therefore event-driven, mirroring
	-- the old dispatcher: start what is already here, then keep watching for
	-- stragglers, starting each declaration exactly once.
	local components = waitForChild(manifest, COMPONENTS_NAME, "Folder")
	if components and sessions[root] == session then
		table.insert(
			session.connections,
			components.ChildAdded:Connect(function(declaration)
				if sessions[root] == session then
					startComponent(root, manifest, session, declaration)
				end
			end)
		)
		for _, declaration in components:GetChildren() do
			startComponent(root, manifest, session, declaration)
		end
	end

	if sessions[root] == session then
		root:SetAttribute("FourDClientStatus", "ready")
	end
end

for _, root in CollectionService:GetTagged(RIG_TAG) do
	task.spawn(start, root)
end
CollectionService:GetInstanceAddedSignal(RIG_TAG):Connect(function(root)
	task.spawn(start, root)
end)
CollectionService:GetInstanceRemovedSignal(RIG_TAG):Connect(function(root)
	stop(root, true)
end)
