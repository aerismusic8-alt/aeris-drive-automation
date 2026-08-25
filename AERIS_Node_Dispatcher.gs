/* =========================================================
   AERIS NODE DISPATCHER FOUNDATION
   Isolated module: does not modify the verified AERIS_Code.gs baseline.
   Configure AERIS_NODE_BOOTSTRAP_SECRET in Script Properties before use.
========================================================= */

const AERIS_NODE_REGISTRY_PROPERTY = "AERIS_NODE_REGISTRY_V1";
const AERIS_NODE_BOOTSTRAP_SECRET_PROPERTY = "AERIS_NODE_BOOTSTRAP_SECRET";
const AERIS_NODE_LEASE_STATUS = "PROCESSING";
const AERIS_NODE_MAX_CAPABILITIES = 20;

function aerisNodeNow_() {
  return new Date().toISOString();
}

function aerisNodeRegistry_() {
  const raw = PropertiesService.getScriptProperties()
    .getProperty(AERIS_NODE_REGISTRY_PROPERTY);

  if (!raw) return {};

  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch (error) {
    throw new Error("AERIS_NODE_REGISTRY_INVALID");
  }
}

function saveAerisNodeRegistry_(registry) {
  PropertiesService.getScriptProperties()
    .setProperty(AERIS_NODE_REGISTRY_PROPERTY, JSON.stringify(registry));
}

function aerisNodeHash_(value) {
  const bytes = Utilities.computeDigest(
    Utilities.DigestAlgorithm.SHA_256,
    String(value || "")
  );

  return bytes.map(function(byte) {
    const normalized = byte < 0 ? byte + 256 : byte;
    return ("0" + normalized.toString(16)).slice(-2);
  }).join("");
}

function aerisNodeRequireText_(value, fieldName) {
  const text = String(value || "").trim();
  if (!text) throw new Error("MISSING_" + fieldName);
  return text;
}

function aerisNodeCapabilities_(value) {
  if (!Array.isArray(value) || value.length === 0) {
    throw new Error("MISSING_NODE_CAPABILITIES");
  }

  const normalized = value.map(function(capability) {
    return String(capability || "").trim().toLowerCase();
  }).filter(function(capability) {
    return capability.length > 0;
  });

  if (!normalized.length || normalized.length > AERIS_NODE_MAX_CAPABILITIES) {
    throw new Error("INVALID_NODE_CAPABILITIES");
  }

  return normalized.filter(function(capability, index) {
    return normalized.indexOf(capability) === index;
  });
}

function aerisNodeAuthenticate_(request) {
  const nodeId = aerisNodeRequireText_(request && request.nodeId, "NODE_ID");
  const nodeSecret = aerisNodeRequireText_(
    request && request.nodeSecret,
    "NODE_SECRET"
  );

  const registry = aerisNodeRegistry_();
  const node = registry[nodeId];

  if (!node || node.status !== "ACTIVE") {
    throw new Error("NODE_NOT_TRUSTED");
  }

  if (node.secretHash !== aerisNodeHash_(nodeSecret)) {
    throw new Error("NODE_AUTHENTICATION_FAILED");
  }

  return { nodeId: nodeId, node: node, registry: registry };
}

/*
 * Register a node using a one-time bootstrap secret held only in Script
 * Properties. The returned nodeSecret is deliberately not persisted.
 */
function AERIS_NODE_REGISTER(request) {
  const bootstrap = PropertiesService.getScriptProperties()
    .getProperty(AERIS_NODE_BOOTSTRAP_SECRET_PROPERTY);

  if (!bootstrap) {
    throw new Error("NODE_BOOTSTRAP_SECRET_NOT_CONFIGURED");
  }

  const nodeId = aerisNodeRequireText_(request && request.nodeId, "NODE_ID");
  const bootstrapSecret = aerisNodeRequireText_(
    request && request.bootstrapSecret,
    "BOOTSTRAP_SECRET"
  );

  if (aerisNodeHash_(bootstrapSecret) !== aerisNodeHash_(bootstrap)) {
    throw new Error("NODE_BOOTSTRAP_AUTHENTICATION_FAILED");
  }

  const agent = aerisNodeRequireText_(request && request.agent, "NODE_AGENT");
  const capabilities = aerisNodeCapabilities_(request && request.capabilities);
  const registry = aerisNodeRegistry_();
  const nodeSecret = Utilities.getUuid() + Utilities.getUuid();

  registry[nodeId] = {
    nodeId: nodeId,
    agent: agent,
    capabilities: capabilities,
    status: "ACTIVE",
    secretHash: aerisNodeHash_(nodeSecret),
    registeredAt: aerisNodeNow_(),
    lastHeartbeat: "",
    lastPullAt: "",
    lastCompletedAt: ""
  };

  saveAerisNodeRegistry_(registry);

  return {
    success: true,
    status: "NODE_REGISTERED",
    verified: true,
    nodeId: nodeId,
    agent: agent,
    capabilities: capabilities,
    nodeSecret: nodeSecret,
    registeredAt: registry[nodeId].registeredAt
  };
}

function AERIS_NODE_HEARTBEAT(request) {
  const auth = aerisNodeAuthenticate_(request);
  const node = auth.node;

  node.lastHeartbeat = aerisNodeNow_();
  node.lastHeartbeatMeta = {
    status: String((request && request.status) || "ONLINE").trim(),
    version: String((request && request.version) || "").trim()
  };

  auth.registry[auth.nodeId] = node;
  saveAerisNodeRegistry_(auth.registry);

  return {
    success: true,
    status: "NODE_HEARTBEAT_RECORDED",
    verified: true,
    nodeId: auth.nodeId,
    heartbeatAt: node.lastHeartbeat
  };
}

function aerisNodeReadDispatchReadyJob_(node) {
  const sheet = getAERISDelegationSheet();
  const data = sheet.getDataRange().getValues();

  for (let rowIndex = 1; rowIndex < data.length; rowIndex++) {
    const row = data[rowIndex];
    const status = String(row[6] || "").trim().toUpperCase();

    if (status !== "DISPATCH_READY") continue;

    let payload;
    try {
      payload = JSON.parse(String(row[7] || ""));
    } catch (error) {
      continue;
    }

    const assignedAgent = String(payload.primaryAgent || row[4] || "").trim();
    const matchingCapability = node.capabilities.indexOf(
      String(payload.capability || row[3] || "").trim().toLowerCase()
    ) !== -1;

    if (assignedAgent !== node.agent || !matchingCapability) continue;

    return {
      sheet: sheet,
      row: rowIndex + 1,
      delegationJobId: String(row[0] || "").trim(),
      payload: payload
    };
  }

  return null;
}

/*
 * Pull is a lease: it moves only an explicitly node-routed DISPATCH_READY
 * job to PROCESSING, preventing the existing dispatcher from claiming it.
 */
function AERIS_NODE_PULL(request) {
  const auth = aerisNodeAuthenticate_(request);
  const job = aerisNodeReadDispatchReadyJob_(auth.node);

  auth.node.lastPullAt = aerisNodeNow_();
  auth.registry[auth.nodeId] = auth.node;
  saveAerisNodeRegistry_(auth.registry);

  if (!job) {
    return {
      success: true,
      status: "NO_NODE_JOB_AVAILABLE",
      verified: true,
      available: false,
      nodeId: auth.nodeId
    };
  }

  const currentStatus = String(job.sheet.getRange(job.row, 7).getValue() || "")
    .trim().toUpperCase();

  if (currentStatus !== "DISPATCH_READY") {
    throw new Error("NODE_JOB_STATUS_CHANGED");
  }

  const leasedAt = aerisNodeNow_();
  const leasedPayload = Object.assign({}, job.payload, {
    nodeLease: {
      nodeId: auth.nodeId,
      leasedAt: leasedAt
    }
  });

  job.sheet.getRange(job.row, 7).setValue(AERIS_NODE_LEASE_STATUS);
  job.sheet.getRange(job.row, 8).setValue(JSON.stringify(leasedPayload));

  const verifyStatus = String(job.sheet.getRange(job.row, 7).getValue() || "")
    .trim().toUpperCase();

  if (verifyStatus !== AERIS_NODE_LEASE_STATUS) {
    throw new Error("NODE_LEASE_VERIFICATION_FAILED");
  }

  return {
    success: true,
    status: "NODE_JOB_LEASED",
    verified: true,
    available: true,
    delegationJobId: job.delegationJobId,
    payload: leasedPayload
  };
}

function AERIS_NODE_COMPLETE(request) {
  const auth = aerisNodeAuthenticate_(request);
  const delegationJobId = aerisNodeRequireText_(
    request && request.delegationJobId,
    "DELEGATION_JOB_ID"
  );
  const execution = request && request.execution;

  if (!execution || execution.executed !== true || execution.verified !== true) {
    throw new Error("NODE_EXECUTION_VERIFICATION_REQUIRED");
  }

  const sheet = getAERISDelegationSheet();
  const data = sheet.getDataRange().getValues();
  let rowNumber = 0;
  let leasedPayload = null;

  for (let rowIndex = 1; rowIndex < data.length; rowIndex++) {
    if (String(data[rowIndex][0] || "").trim() !== delegationJobId) continue;
    rowNumber = rowIndex + 1;
    try {
      leasedPayload = JSON.parse(String(data[rowIndex][7] || ""));
    } catch (error) {
      throw new Error("NODE_LEASE_PAYLOAD_INVALID");
    }
    break;
  }

  if (!rowNumber) throw new Error("NODE_JOB_NOT_FOUND");

  const status = String(sheet.getRange(rowNumber, 7).getValue() || "")
    .trim().toUpperCase();

  if (status !== AERIS_NODE_LEASE_STATUS) {
    throw new Error("NODE_COMPLETION_STATUS_INVALID");
  }

  if (!leasedPayload.nodeLease ||
      leasedPayload.nodeLease.nodeId !== auth.nodeId) {
    throw new Error("NODE_LEASE_OWNER_MISMATCH");
  }

  const completedAt = new Date();
  const result = {
    status: "NODE_DISPATCH_COMPLETED",
    verified: true,
    executed: true,
    delegationJobId: delegationJobId,
    nodeId: auth.nodeId,
    execution: execution,
    completedAt: completedAt.toISOString()
  };

  sheet.getRange(rowNumber, 7).setValue("COMPLETED");
  sheet.getRange(rowNumber, 8).setValue(JSON.stringify(result));
  sheet.getRange(rowNumber, 9).setValue("");
  sheet.getRange(rowNumber, 11).setValue(completedAt);

  const verifyStatus = String(sheet.getRange(rowNumber, 7).getValue() || "")
    .trim().toUpperCase();
  const verifyResult = String(sheet.getRange(rowNumber, 8).getValue() || "");

  if (verifyStatus !== "COMPLETED" || verifyResult.indexOf(auth.nodeId) === -1) {
    throw new Error("NODE_COMPLETION_PERSISTENCE_VERIFICATION_FAILED");
  }

  auth.node.lastCompletedAt = completedAt.toISOString();
  auth.registry[auth.nodeId] = auth.node;
  saveAerisNodeRegistry_(auth.registry);

  return {
    success: true,
    status: "NODE_JOB_COMPLETED",
    verified: true,
    delegationJobId: delegationJobId,
    nodeId: auth.nodeId,
    completedAt: completedAt.toISOString()
  };
}

/*
 * Adapter for a future, explicitly reviewed doPost route.
 * It is intentionally not wired into AERIS_Code.gs in this baseline-safe step.
 */
function routeAERISNodeRequest(request) {
  const action = String((request && request.action) || "").trim().toLowerCase();

  if (action === "node_register") return AERIS_NODE_REGISTER(request);
  if (action === "node_heartbeat") return AERIS_NODE_HEARTBEAT(request);
  if (action === "node_pull") return AERIS_NODE_PULL(request);
  if (action === "node_complete") return AERIS_NODE_COMPLETE(request);

  throw new Error("UNKNOWN_NODE_ACTION");
}
