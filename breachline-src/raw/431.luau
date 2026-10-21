-- Central server runtime for completed edit-time FourD rigs.
--
-- The server twin of StarterPlayerScripts.Client.FourDClientRuntime. A rig is
-- mechanically assembled before Play, but any server logic its capability wired
-- as an in-memory connection during edit-time bind() is gone by the time Play
-- starts. This runtime rebinds it: for each rig tagged `FourDServerRig` it starts
-- the server components its manifest declares. Each is a ModuleScript (reached
-- directly or through an ObjectValue in `FourDRuntimeManifest.ServerComponents`)
-- that returns a `start(root, manifest)` function, or a table carrying one, and
-- may return a cleanup function.
--
-- Unlike the client runtime, which tolerates a failed renderer, this one is
-- strict about readiness: FourDServerStatus becomes "ready" only if every
-- declared component bound, and "failed" (with FourDServerError naming the
-- offender) if any is unresolved, fails to require, exports no start, or errors
-- while binding. This is deliberate -- the whole point of the attribute is that a
-- rig whose handler never connected (e.g. a tank whose cannon can't fire) must
-- report a failure instead of a meaningless "ready".

local CollectionService = game:GetService("CollectionService")

local RIG_TAG = "FourDServerRig"
local MANIFEST_NAME = "FourDRuntimeManifest"
local COMPONENTS_NAME = "ServerComponents"
local WAIT_SECONDS = 10
local RUNTIME_VERSION = 1

type Cleanup = () -> ()
type Session = {
	cleanups: { Cleanup },
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
	for index = #session.cleanups, 1, -1 do
		pcall(session.cleanups[index])
	end
	if clearStatus then
		root:SetAttribute("FourDServerStatus", nil)
		root:SetAttribute("FourDServerError", nil)
	end
end

-- Bind one declared server component. Returns nil on success or an error string
-- describing the failure. Runs synchronously (the caller aggregates results to
-- decide readiness): server instances are fully present when the tagged root
-- arrives, so there is no client-style streaming wait to overlap across threads.
local function startComponent(root: Instance, manifest: Instance, session: Session, declaration: Instance): string?
	local module = resolveModule(declaration)
	if not module then
		return `unresolved server component {declaration.Name}`
	end
	local ok, component = pcall(require, module)
	if not ok then
		return `loading {module:GetFullName()}: {tostring(component)}`
	end
	local starter = if type(component) == "function"
		then component
		elseif type(component) == "table" then component.start
		else nil
	if type(starter) ~= "function" then
		return `{module:GetFullName()} exports no start function`
	end
	local started, cleanup = pcall(starter, root, manifest)
	if not started then
		return `starting {module:GetFullName()}: {tostring(cleanup)}`
	end
	if type(cleanup) == "function" and sessions[root] == session then
		table.insert(session.cleanups, cleanup)
	end
	return nil
end

local function start(root: Instance)
	if sessions[root] then return end
	local session: Session = { cleanups = {} }
	sessions[root] = session
	root:SetAttribute("FourDServerStatus", "starting")
	root:SetAttribute("FourDServerRuntimeVersion", RUNTIME_VERSION)
	root:SetAttribute("FourDServerError", nil)

	local manifest = waitForChild(root, MANIFEST_NAME, "Folder")
	if not manifest then
		root:SetAttribute("FourDServerStatus", "failed")
		root:SetAttribute("FourDServerError", `missing {MANIFEST_NAME}`)
		return
	end

	-- The ServerComponents folder is always compiled into the manifest. On the
	-- server the rig arrives whole, so a bounded wait covers construction order
	-- rather than streaming. A rig with no server components lands here with an
	-- empty folder and is legitimately ready.
	local components = waitForChild(manifest, COMPONENTS_NAME, "Folder")
	local firstError: string? = nil
	if components then
		for _, declaration in components:GetChildren() do
			if sessions[root] ~= session then return end
			local err = startComponent(root, manifest, session, declaration)
			if err and not firstError then
				firstError = err
				warn(`[FourDServerRuntime] {root:GetFullName()}: {err}`)
			elseif err then
				warn(`[FourDServerRuntime] {root:GetFullName()}: {err}`)
			end
		end
	end

	if sessions[root] ~= session then return end
	if firstError then
		root:SetAttribute("FourDServerStatus", "failed")
		root:SetAttribute("FourDServerError", firstError)
	else
		root:SetAttribute("FourDServerStatus", "ready")
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
f-