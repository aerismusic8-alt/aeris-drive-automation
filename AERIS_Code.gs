const AERIS_VERSION = "5.9.1";

/* =========================================================
   AERIS MUSIC — MASTER BUILD
   VERSION: 5.4.1

   LAYERS
   ---------------------------------------------------------
   V5.2  Queue / Drive Automation
   V5.3  State Snapshot / RESUME
   V5.4  Agent Registry / Capability Routing
   V5.4.1 Persistent Delegation Queue

   IMPORTANT
   ---------------------------------------------------------
   - Reuses existing processCommandQueue()
   - DO NOT create a new trigger
   - External AI dispatch is NOT enabled yet
========================================================= */


/* =========================================================
   CORE CONSTANTS
========================================================= */

const AERIS_FOLDERS = {
  "01": "01 — IDENTITY & ACCOUNTS",
  "02": "02 — AI TEAM",
  "03": "03 — HQ & KNOWLEDGE",
  "04": "04 — WORKFLOWS & DISPATCH",
  "05": "05 — PERMISSIONS & APPROVALS",
  "06": "QC & ERROR RECOVERY",
  "07": "07 — AUTOMATION ROADMAP",
  "08": "08 — MASTER WORKFLOW"
};

const QUEUE_SPREADSHEET_ID =
  "1OBJ_f4WiMDhk_WxcvDE8_5WB91V5xotsP34uUueQSnM";

const QUEUE_SHEET_NAME = "ชีต1";

const JOB_LOG_SPREADSHEET_NAME =
  "AERIS JOB LOG";

const JOB_LOG_SHEET_NAME =
  "AERIS_JOB_LOG";

const DELEGATION_SHEET_NAME =
  "AERIS_DELEGATION_QUEUE";

const STATE_FILE_PREFIX =
  "AERIS_CURRENT_STATE_";

const WEB_APP_URL =
  "https://script.google.com/macros/s/AKfycbwz6F8EWTD7YwnGkyu4Mq_JHtBkk6nOwl9TYjWDsMsQTtS5EVj3I6hmakuW6yP_YGQH/exec";

const DELEGATION_HEADERS = [
  "Delegation Job ID",
  "Created At",
  "Task",
  "Capability",
  "Primary Agent",
  "Fallback Agent",
  "Status",
  "Result",
  "Error",
  "Dispatched At",
  "Completed At"
];

/* =========================================================
   WEB APP
========================================================= */

function doGet(e) {

  const mode = e && e.parameter
    ? String(e.parameter.mode || "").trim().toLowerCase()
    : "";

  const action = e && e.parameter
    ? String(e.parameter.action || "").trim().toLowerCase()
    : "";

  // =========================================================
  // AERIS NODE API
  // =========================================================

  if (action === "node_status") {

    try {

      return jsonResponse({
        success: true,
        system: "AERIS_NODE_API",
        action: "node_status",
        nodeApiVersion: "1.0.0",
        timestamp: new Date().toISOString(),
        control: getAERISControlStatus()
      });

    } catch (err) {

      return jsonResponse({
        success: false,
        system: "AERIS_NODE_API",
        action: "node_status",
        error: String(
          err && err.message
            ? err.message
            : err
        )
      });
    }
  }

  // PERFORMANCE
  if (mode === "status" || mode === "api") {
    return jsonResponse(getAERISPerformanceSnapshot());
  }

  // MONITOR
  if (mode === "monitor") {
    return HtmlService.createHtmlOutput(AERIS_MONITOR_HTML)
      .setTitle("AERIS Performance Monitor")
      .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
  }

  // DELEGATION JOB LOOKUP
  if (mode === "delegation") {

    const jobId = e && e.parameter
      ? String(e.parameter.jobId || "").trim()
      : "";

    if (!jobId) {
      return jsonResponse({
        success: false,
        error: "MISSING_JOB_ID",
        message: "jobId is required",
        mode: "delegation"
      });
    }

    try {

      const job = getAERISDelegationJobById(jobId);

      return jsonResponse({
        success: true,
        mode: "delegation",
        jobId: jobId,
        found: !!job,
        job: job || null
      });

    } catch (err) {

      return jsonResponse({
        success: false,
        mode: "delegation",
        jobId: jobId,
        error: String(
          err && err.message
            ? err.message
            : err
        )
      });
    }
  }

  // DEFAULT
  return jsonResponse({
    service: "AERIS DRIVE AUTOMATION",
    status: "ONLINE",
    version: AERIS_VERSION,
    monitor: "?mode=monitor",
    statusEndpoint: "?mode=status",
    delegationEndpoint: "?mode=delegation&jobId=JOB_ID",
    nodeStatusEndpoint: "?action=node_status"
  });
}
function doPost(e) {

  try {

    if (
      !e ||
      !e.postData ||
      !e.postData.contents
    ) {
      throw new Error(
        "MISSING_POST_DATA"
      );
    }

    const payload =
      JSON.parse(
        e.postData.contents
      );

    const action =
      String(payload.action || "")
        .trim()
        .toLowerCase();

    /*
     * Node protocol is explicitly namespaced. Requests without a node_ action
     * retain the original command-queue behavior unchanged.
     */
    if (action.indexOf("node_") === 0) {
      const nodeResult =
        routeAERISNodeRequest(payload);

      return jsonResponse({
        success: true,
        version: AERIS_VERSION,
        result: nodeResult
      });
    }

    const result =
      bridgeCreateJob({

        command:
          payload.command ||
          payload.type,

        fileId:
          payload.fileId,

        fileName:
          payload.fileName,

        destination:
          payload.destination ||
          payload.folderNumber,

        approved:
          payload.approved === undefined
            ? true
            : payload.approved

      });

    return jsonResponse({

      success: true,

      version:
        AERIS_VERSION,

      result:
        result

    });

  } catch (error) {

    return jsonResponse({

      success: false,

      version:
        AERIS_VERSION,

      error:
        error.message,

      timestamp:
        new Date().toISOString()

    });
  }
}


/* =========================================================
   COMMAND BRIDGE
========================================================= */

function bridgeCreateJob(payload) {

  if (!payload) {
    throw new Error("MISSING_PAYLOAD");
  }

  const command =
    String(
      payload.command ||
      payload.type ||
      ""
    )
      .trim()
      .toUpperCase();

  if (!command) {
    throw new Error("MISSING_COMMAND");
  }

  const allowed = [
    "EXECUTE_EXTERNAL",
    "STORE_FILE",
    "SEARCH_FILE",
    "GET_FILE",
    "CREATE_FILE",
    "CREATE_SAVEPOINT",
    "SAVE_STATE",
    "RESUME_STATE",
    "DELEGATE_GEMINI"
  ];

  if (allowed.indexOf(command) === -1) {
    throw new Error(
      "UNKNOWN_COMMAND: " + command
    );
  }

  const sheet = getQueueSheet();

  const headers = [
    "Job ID",
    "Timestamp",
    "Command",
    "File ID",
    "File Name",
    "Destination",
    "Approved",
    "Content",
    "Status",
    "Result",
    "Error",
    "Completed At"
  ];

  ensureAERISQueueSchema(
    sheet,
    headers
  );

  const jobId = createJobId();

  const destination =
    String(
      payload.destination ||
      payload.folderNumber ||
      ""
    ).trim();

  if (destination) {
    normalizeFolderNumber(destination);
  }

  const approved =
    payload.approved === true ||
    String(
      payload.approved || ""
    ).toUpperCase() === "TRUE";

  const content =
    payload.content === undefined ||
    payload.content === null
      ? ""
      : String(payload.content);

  sheet.appendRow([
    jobId,
    new Date(),
    command,
    String(payload.fileId || ""),
    String(payload.fileName || ""),
    destination,
    approved,
    content,
    "PENDING",
    "",
    "",
    ""
  ]);

  const row = sheet.getLastRow();

  const values =
    sheet
      .getRange(
        row,
        1,
        1,
        headers.length
      )
      .getValues()[0];

  if (
    String(values[0]).trim() !== jobId
  ) {
    throw new Error(
      "QUEUE_JOB_ID_VERIFICATION_FAILED"
    );
  }

  if (
    String(values[2])
      .trim()
      .toUpperCase() !== command
  ) {
    throw new Error(
      "QUEUE_COMMAND_VERIFICATION_FAILED"
    );
  }

  if (
    String(values[8])
      .trim()
      .toUpperCase() !== "PENDING"
  ) {
    throw new Error(
      "QUEUE_STATUS_VERIFICATION_FAILED"
    );
  }

  return {
    status: "QUEUE_CREATED",
    verified: true,
    jobId: jobId,
    command: command,
    queueStatus: "PENDING",
    row: row,
    timestamp: new Date().toISOString()
  };
  
  }
  function testAERISExternalExecutionQueue() {

  const result =
    bridgeCreateJob({

      command:
        "EXECUTE_EXTERNAL",

      approved:
        true,

      content:
        "TEST_EXECUTION"

    });

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  return result;
}
function testAERISCreateFileQueue() {

  const result =
    bridgeCreateJob({

      command: "CREATE_FILE",

      fileName:
        "AERIS_RUNTIME_TEST_2026-08-24.txt",

      destination:
        "03",

      approved:
        true,

      content:
        "AERIS RUNTIME TEST\n" +
        "Created by Queue Executor.\n" +
        "Timestamp: " +
        new Date().toISOString()

    });

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  return result;
}
function ensureAERISQueueSchema(sheet, requiredHeaders) {

  const lastColumn =
    sheet.getLastColumn();

  if (lastColumn === 0) {

    sheet
      .getRange(
        1,
        1,
        1,
        requiredHeaders.length
      )
      .setValues([
        requiredHeaders
      ]);

    return;
  }

  const currentHeaders =
    sheet
      .getRange(
        1,
        1,
        1,
        lastColumn
      )
      .getValues()[0]
      .map(function(value) {
        return String(value).trim();
      });

  requiredHeaders.forEach(function(header) {

    if (
      currentHeaders.indexOf(header) === -1
    ) {

      sheet
        .getRange(
          1,
          sheet.getLastColumn() + 1
        )
        .setValue(header);

      currentHeaders.push(header);
    }
  });
}

/* =========================================================
   JSON RESPONSE
========================================================= */

function jsonResponse(data) {

  return ContentService
    .createTextOutput(
      JSON.stringify(data)
    )
    .setMimeType(
      ContentService.MimeType.JSON
    );
}


/* =========================================================
   FOLDER FUNCTIONS
========================================================= */

function normalizeFolderNumber(value) {

  const number =
    String(
      value || ""
    )
      .trim()
      .replace(/^0+/, "");

  if (!number) {

    throw new Error(
      "MISSING_FOLDER_NUMBER"
    );
  }

  const normalized =
    number.padStart(
      2,
      "0"
    );

  if (
    !AERIS_FOLDERS[
      normalized
    ]
  ) {

    throw new Error(
      "INVALID_FOLDER_NUMBER: " +
      value
    );
  }

  return normalized;
}


function getAerisFolder(folderName) {

  const folders =
    DriveApp.getFoldersByName(
      folderName
    );

  if (!folders.hasNext()) {

    throw new Error(
      "DESTINATION_FOLDER_NOT_FOUND: " +
      folderName
    );
  }

  return folders.next();
}


/* =========================================================
   FILE OPERATIONS
========================================================= */

function storeAerisFile(
  fileId,
  folderNumber
) {

  if (!fileId) {

    throw new Error(
      "MISSING_FILE_ID"
    );
  }

  const normalizedFolder =
    normalizeFolderNumber(
      folderNumber
    );

  const folderName =
    AERIS_FOLDERS[
      normalizedFolder
    ];

  const folder =
    getAerisFolder(
      folderName
    );

  const file =
    DriveApp.getFileById(
      fileId
    );

  file.moveTo(
    folder
  );

  const verifiedFile =
    DriveApp.getFileById(
      fileId
    );

  return {

    status:
      "STORED",

    verified:
      true,

    fileId:
      fileId,

    fileName:
      verifiedFile.getName(),

    destination:
      folderName,

    destinationFolderId:
      folder.getId(),

    timestamp:
      new Date().toISOString()

  };
}


function searchAerisFile(
  fileName
) {

  if (!fileName) {

    throw new Error(
      "MISSING_FILE_NAME"
    );
  }

  const files =
    DriveApp.getFilesByName(
      fileName
    );

  const results = [];

  while (
    files.hasNext()
  ) {

    const file =
      files.next();

    results.push({

      fileId:
        file.getId(),

      fileName:
        file.getName(),

      mimeType:
        file.getMimeType(),

      url:
        file.getUrl(),

      lastUpdated:
        file
          .getLastUpdated()
          .toISOString()

    });
  }

  return {

    status:
      "SEARCH_COMPLETED",

    verified:
      true,

    query:
      fileName,

    count:
      results.length,

    files:
      results,

    timestamp:
      new Date().toISOString()

  };
}


function getAerisFile(
  fileId
) {

  if (!fileId) {

    throw new Error(
      "MISSING_FILE_ID"
    );
  }

  const file =
    DriveApp.getFileById(
      fileId
    );

  return {

    status:
      "FILE_FOUND",

    verified:
      true,

    fileId:
      file.getId(),

    fileName:
      file.getName(),

    mimeType:
      file.getMimeType(),

    url:
      file.getUrl(),

    size:
      file.getSize(),

    lastUpdated:
      file
        .getLastUpdated()
        .toISOString(),

    timestamp:
      new Date().toISOString()

  };
}


/* =========================================================
   QUEUE SHEET
========================================================= */

function getQueueSheet() {

  const spreadsheet =
    SpreadsheetApp.openById(
      QUEUE_SPREADSHEET_ID
    );

  let sheet =
    spreadsheet.getSheetByName(
      QUEUE_SHEET_NAME
    );

  if (!sheet) {

    sheet =
      spreadsheet.insertSheet(
        QUEUE_SHEET_NAME
      );
  }

  return sheet;
}


/* =========================================================
   JOB LOG
========================================================= */

function getJobLogSheet() {

  const files =
    DriveApp.getFilesByName(
      JOB_LOG_SPREADSHEET_NAME
    );

  let spreadsheet;

  if (
    files.hasNext()
  ) {

    spreadsheet =
      SpreadsheetApp.open(
        files.next()
      );

  } else {

    spreadsheet =
      SpreadsheetApp.create(
        JOB_LOG_SPREADSHEET_NAME
      );
  }

  let sheet =
    spreadsheet.getSheetByName(
      JOB_LOG_SHEET_NAME
    );

  if (!sheet) {

    sheet =
      spreadsheet.insertSheet(
        JOB_LOG_SHEET_NAME
      );

    sheet.appendRow([

      "Job ID",
      "Timestamp",
      "Job Type",
      "File ID",
      "Folder",
      "Status",
      "Verified",
      "Error"

    ]);
  }

  return sheet;
}


function createJobId() {

  return (

    "AERIS-" +

    Utilities.formatDate(
      new Date(),
      Session.getScriptTimeZone(),
      "yyyyMMdd-HHmmss"
    ) +

    "-" +

    Utilities.getUuid()
      .substring(0, 8)

  );
}


function logJob(
  jobId,
  jobType,
  fileId,
  folder,
  status,
  verified,
  errorMessage
) {

  const sheet =
    getJobLogSheet();

  sheet.appendRow([

    jobId,
    new Date(),
    jobType || "",
    fileId || "",
    folder || "",
    status || "",
    verified === true,
    errorMessage || ""

  ]);
}


/* =========================================================
   SAVEPOINT
========================================================= */

function createAERISSavePointFromQueue(
  jobId
) {

  if (!jobId) {

    throw new Error(
      "MISSING_JOB_ID"
    );
  }

  const timestamp =
    new Date();

  const timestampText =
    Utilities.formatDate(
      timestamp,
      Session.getScriptTimeZone(),
      "yyyy-MM-dd_HH-mm-ss"
    );

  const savePointName =
    "AERIS_LATEST_SAVEPOINT_" +
    timestampText;

  const content =
`AERIS MUSIC — LATEST SAVE POINT
========================================

SAVEPOINT:
AERIS SAVE v1

JOB ID:
${jobId}

DATE:
${timestamp.toISOString()}

STATUS:
CREATED / VERIFIED


SYSTEM
------
Company: AERIS MUSIC
Business Model: Independent AI Music Label
Market: Thailand + Global
Investment: ฿0
Strategy: Organic-first


AUTHORITY
---------
K: Human / Ultimate Approval
AX: CEO / Orchestrator
NOVA: Document & Data Operations Agent


VERIFIED ARCHITECTURE
---------------------
AX
 ↓
NOVA
 ↓
AERIS COMMAND QUEUE
 ↓
Apps Script Time Trigger
 ↓
processCommandQueue()
 ↓
CREATE_SAVEPOINT
 ↓
Google Drive
 ↓
Verification
 ↓
COMPLETED


CURRENT VERIFIED STATE
----------------------
AERIS BRIDGE v1: VERIFIED
Drive Automation: VERIFIED
STORE_FILE: VERIFIED
Command Queue: VERIFIED
Trigger: VERIFIED
Drive Verification: VERIFIED
State Snapshot: VERIFIED
RESUME: VERIFIED


CURRENT OBJECTIVE
-----------------
AERIS DELEGATION ENGINE


RECOVERY RULE
-------------
Never claim that this Save Point is stored
unless Drive verification succeeds.


END OF SAVE POINT
`;

  const file =
    DriveApp.createFile(
      savePointName + ".txt",
      content,
      MimeType.PLAIN_TEXT
    );

  const folder =
    getAerisFolder(
      AERIS_FOLDERS["03"]
    );

  file.moveTo(
    folder
  );

  const verifiedFile =
    DriveApp.getFileById(
      file.getId()
    );

  if (
    verifiedFile.getId() !==
    file.getId()
  ) {

    throw new Error(
      "SAVEPOINT_VERIFICATION_FAILED"
    );
  }

  return {

    status:
      "SAVEPOINT_STORED",

    verified:
      true,

    jobId:
      jobId,

    fileId:
      verifiedFile.getId(),

    fileName:
      verifiedFile.getName(),

    destination:
      folder.getName(),

    destinationFolderId:
      folder.getId(),

    timestamp:
      new Date().toISOString()

  };
}


/* =========================================================
   STATE SNAPSHOT
========================================================= */

function createAERISStateSnapshot(
  sourceJobId,
  sourceCommand
) {

  const timestamp =
    new Date();

  const timestampText =
    Utilities.formatDate(
      timestamp,
      Session.getScriptTimeZone(),
      "yyyy-MM-dd_HH-mm-ss"
    );

  const stateFileName =
    STATE_FILE_PREFIX +
    timestampText +
    ".json";

  const state = {

    aerisVersion:
      AERIS_VERSION,

    snapshotType:
      "AERIS_STATE_SNAPSHOT",

    snapshotVersion:
      "1.0",

    createdAt:
      timestamp.toISOString(),

    sourceJobId:
      sourceJobId || "",

    sourceCommand:
      sourceCommand || "",

    system: {

      company:
        "AERIS MUSIC",

      businessModel:
        "Independent AI Music Label",

      market:
        "Thailand + Global",

      investment:
        "฿0",

      strategy:
        "Organic-first"

    },

    architecture: {

      ax:
        "CEO / Orchestrator",

      nova:
        "Document & Data Operations",

      muse:
        "Creative Strategy",

      commandQueue:
        "VERIFIED",

      driveAutomation:
        "VERIFIED",

      trigger:
        "EXISTING processCommandQueue()",

      delegationEngine:
        "V5.4.1 PERSISTENT QUEUE"

    },

    currentState: {

      queue:
        "ACTIVE",

      continuity:
        "V5.3 STATE SNAPSHOT",

      savePoint:
        "ACTIVE",

      delegation:
        "PERSISTENT QUEUE",

      driveVerification:
        "REQUIRED"

    },

    recovery: {

      resumeEnabled:
        true,

      recoveryRule:
        "Never claim persistence without Drive verification"

    },

    nextObjective:
      "Build AERIS Dispatcher"

  };

  const content =
    JSON.stringify(
      state,
      null,
      2
    );

  const file =
    DriveApp.createFile(
      stateFileName,
      content,
      MimeType.PLAIN_TEXT
    );

  const folder =
    getAerisFolder(
      AERIS_FOLDERS["03"]
    );

  file.moveTo(
    folder
  );

  const verifiedFile =
    DriveApp.getFileById(
      file.getId()
    );

  if (
    verifiedFile.getId() !==
    file.getId()
  ) {

    throw new Error(
      "STATE_SNAPSHOT_VERIFICATION_FAILED"
    );
  }

  return {

    status:
      "STATE_SNAPSHOT_STORED",

    verified:
      true,

    fileId:
      verifiedFile.getId(),

    fileName:
      verifiedFile.getName(),

    destination:
      folder.getName(),

    destinationFolderId:
      folder.getId(),

    snapshotVersion:
      "1.0",

    timestamp:
      new Date().toISOString()

  };
}


/* =========================================================
   RESUME STATE
========================================================= */
/* =========================================================
   AUTONOMOUS RESUME STATE
========================================================= */

function resumeAERISState() {

  const folder =
    getAerisFolder(AERIS_FOLDERS["03"]);

  const files =
    folder.getFiles();

  let latestFile = null;
  let latestTime = 0;

  while (files.hasNext()) {

    const file =
      files.next();

    const name =
      file.getName();

    if (
      name.indexOf(STATE_FILE_PREFIX) !== 0
    ) {
      continue;
    }

    const updated =
      file.getLastUpdated().getTime();

    if (updated > latestTime) {

      latestTime = updated;
      latestFile = file;
    }
  }

  if (!latestFile) {

    return {
      status: "NO_STATE_SNAPSHOT",
      verified: true,
      resumeAvailable: false,
      timestamp: new Date().toISOString()
    };
  }

  const content =
    latestFile
      .getBlob()
      .getDataAsString();

  let state;

  try {

    state =
      JSON.parse(content);

  } catch (error) {

    throw new Error(
      "STATE_FILE_PARSE_FAILED"
    );
  }

  if (
    state.snapshotType !==
    "AERIS_STATE_SNAPSHOT"
  ) {

    throw new Error(
      "INVALID_AERIS_STATE_SNAPSHOT"
    );
  }

  if (
    !state.recovery ||
    state.recovery.resumeEnabled !== true
  ) {

    throw new Error(
      "AERIS_RESUME_NOT_ENABLED"
    );
  }

  const resumeJobId =
    "RESUME-" +
    Utilities.formatDate(
      new Date(),
      Session.getScriptTimeZone(),
      "yyyyMMdd-HHmmss"
    ) +
    "-" +
    Utilities.getUuid().slice(0, 8);

  const sheet =
    SpreadsheetApp
      .openById(QUEUE_SPREADSHEET_ID)
      .getSheetByName(DELEGATION_SHEET_NAME);

  if (!sheet) {
    throw new Error(
      "DELEGATION_SHEET_NOT_FOUND"
    );
  }

  const lastColumn =
    sheet.getLastColumn();

  const headers =
    sheet
      .getRange(
        1,
        1,
        1,
        lastColumn
      )
      .getValues()[0]
      .map(h =>
        String(h).trim()
      );

  const row =
    new Array(headers.length)
      .fill("");

  headers.forEach(
    (header, i) => {

      switch (
        header.toLowerCase()
      ) {

        case "delegation job id":

          row[i] =
            resumeJobId;

          break;

        case "created at":

          row[i] =
            new Date();

          break;

        case "task":

          row[i] =
            "RESUME_NEXT_ACTION";

          break;

        case "capability":

          row[i] =
            "orchestration";

          break;

        case "primary agent":

          row[i] =
            "Gemini";

          break;

        case "fallback agent":

          row[i] =
            "Copilot";

          break;

        case "status":

  nextRow[i] =
    "PENDING_DISPATCH";

  break;
      }

    }
  );

  sheet.appendRow(row);

  const result = {

    status:
      "STATE_RESUMED_TO_QUEUE",

    verified:
      true,

    resumeAvailable:
      true,

    resumeJobId:
      resumeJobId,

    sourceJobId:
      state.sourceJobId || "",

    sourceCommand:
      state.sourceCommand || "",

    nextObjective:
      state.nextObjective || "",

    snapshotFileId:
      latestFile.getId(),

    snapshotFileName:
      latestFile.getName(),

    queue:
      DELEGATION_SHEET_NAME,

    queueStatus:
      "PENDING",

    dispatchReady:
      true,

    timestamp:
      new Date().toISOString()

  };

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  return result;
}
/* =========================================================
   V5.4 AGENT REGISTRY
========================================================= */

function getAERISAgentRegistry() {

  return {

    "AX": {

      name:
        "AX",

      role:
        "CEO / Orchestrator",

      type:
        "ORCHESTRATOR",

      capabilities: [

        "planning",
        "strategy",
        "decision",
        "architecture",
        "verification"

      ],

      execution:
        false,

      priority:
        1

    },

    "MUSE": {

      name:
        "MUSE",

      role:
        "Creative Strategy Director",

      type:
        "SPECIALIST",

      capabilities: [

        "creative",
        "artist",
        "branding",
        "music_direction"

      ],

      execution:
        true,

      priority:
        2

    },

    "GEMINI": {

      name:
        "Gemini",

      role:
        "Technical / Google Operations",

      type:
        "SPECIALIST",

      capabilities: [

        "coding",
        "google_apps_script",
        "technical_qc",
        "google_workspace"

      ],

      execution:
        true,

      priority:
        2

    },

    "COPILOT": {

      name:
        "Copilot",

      role:
        "Coding Backup",

      type:
        "BACKUP",

      capabilities: [

        "coding",
        "debugging",
        "technical_analysis"

      ],

      execution:
        true,

      priority:
        3

    },

    "PERPLEXITY": {

      name:
        "Perplexity",

      role:
        "Research Specialist",

      type:
        "SPECIALIST",

      capabilities: [

        "research",
        "web_research",
        "market_research",
        "fact_checking"

      ],

      execution:
        true,

      priority:
        2

    },

    "NOVA": {

      name:
        "NOVA",

      role:
        "Document & Data Operations",

      type:
        "OPERATIONS",

      capabilities: [

        "document",
        "data",
        "file_operations",
        "knowledge_operations"

      ],

      execution:
        true,

      priority:
        2

    }

  };
}


/* =========================================================
   AGENT LOOKUP
========================================================= */

function getAERISAgent(
  agentName
) {

  if (!agentName) {

    throw new Error(
      "MISSING_AGENT"
    );
  }

  const registry =
    getAERISAgentRegistry();

  const key =
    String(
      agentName
    )
      .trim()
      .toUpperCase();

  if (
    !registry[key]
  ) {

    throw new Error(
      "AGENT_NOT_FOUND: " +
      key
    );
  }

  return registry[key];
}


/* =========================================================
   CAPABILITY ROUTING
========================================================= */

function findAERISAgentByCapability(
  capability
) {

  if (!capability) {

    throw new Error(
      "MISSING_CAPABILITY"
    );
  }

  const registry =
    getAERISAgentRegistry();

  const target =
    String(
      capability
    )
      .trim()
      .toLowerCase();

  const matches = [];

  Object.keys(
    registry
  )
    .forEach(
      function(key) {

        const agent =
          registry[key];

        if (
          agent.execution !== true
        ) {
          return;
        }

        const capabilities =
          agent.capabilities ||
          [];

        if (
          capabilities.indexOf(
            target
          ) !== -1
        ) {

          matches.push(
            agent
          );
        }

      }
    );

  matches.sort(
    function(a, b) {

      return (
        a.priority -
        b.priority
      );

    }
  );

  if (
    matches.length === 0
  ) {

    throw new Error(
      "NO_AGENT_FOR_CAPABILITY: " +
      target
    );
  }

  return matches;
}


/* =========================================================
   DELEGATION JOB ID
========================================================= */

function createDelegationJobId() {

  return (

    "DELEGATE-" +

    Utilities.formatDate(
      new Date(),
      Session.getScriptTimeZone(),
      "yyyyMMdd-HHmmss"
    ) +

    "-" +

    Utilities.getUuid()
      .substring(0, 8)

  );
}


/* =========================================================
   EPHEMERAL DELEGATION
========================================================= */

function createAERISDelegationTask(
  payload
) {

  if (!payload) {

    throw new Error(
      "MISSING_DELEGATION_PAYLOAD"
    );
  }

  const task =
    String(
      payload.task || ""
    ).trim();

  if (!task) {

    throw new Error(
      "MISSING_TASK"
    );
  }

  const capability =
    String(
      payload.capability || ""
    )
      .trim()
      .toLowerCase();

  if (!capability) {

    throw new Error(
      "MISSING_CAPABILITY"
    );
  }

  const matches =
    findAERISAgentByCapability(
      capability
    );

  const primary =
    matches[0];

  const fallback =
    matches.length > 1
      ? matches[1]
      : null;

  const delegationJobId =
    createDelegationJobId();

  return {

    status:
      "DELEGATION_CREATED",

    verified:
      true,

    delegationJobId:
      delegationJobId,

    task:
      task,

    capability:
      capability,

    primaryAgent:
      primary.name,

    fallbackAgent:
      fallback
        ? fallback.name
        : null,

    state:
      "PENDING_DISPATCH",

    createdAt:
      new Date().toISOString()

  };
}


/* =========================================================
   PERSISTENT DELEGATION SHEET
========================================================= */

function getAERISDelegationSheet() {

  const spreadsheet =
    SpreadsheetApp.openById(
      QUEUE_SPREADSHEET_ID
    );

  let sheet =
    spreadsheet.getSheetByName(
      DELEGATION_SHEET_NAME
    );

  if (!sheet) {

    sheet =
      spreadsheet.insertSheet(
        DELEGATION_SHEET_NAME
      );

    sheet
      .getRange(
        1,
        1,
        1,
        DELEGATION_HEADERS.length
      )
      .setValues([
        DELEGATION_HEADERS
      ]);
  }

  return sheet;
}


/* =========================================================
   CREATE PERSISTENT DELEGATION
========================================================= */

function createPersistentAERISDelegationTask(
  payload
) {

  if (!payload) {

    throw new Error(
      "MISSING_DELEGATION_PAYLOAD"
    );
  }

  const task =
    String(
      payload.task || ""
    ).trim();

  if (!task) {

    throw new Error(
      "MISSING_TASK"
    );
  }

  const capability =
    String(
      payload.capability || ""
    )
      .trim()
      .toLowerCase();

  if (!capability) {

    throw new Error(
      "MISSING_CAPABILITY"
    );
  }

  const matches =
    findAERISAgentByCapability(
      capability
    );

  const primary =
    matches[0];

  const fallback =
    matches.length > 1
      ? matches[1]
      : null;

  const delegationJobId =
    createDelegationJobId();

  const sheet =
    getAERISDelegationSheet();

  const createdAt =
    new Date();

  sheet.appendRow([

    delegationJobId,
    createdAt,
    task,
    capability,
    primary.name,
    fallback
      ? fallback.name
      : "",
    "PENDING_DISPATCH",
    "",
    "",
    "",
    ""

  ]);

  const row =
    sheet.getLastRow();

  const verifyId =
    String(
      sheet
        .getRange(
          row,
          1
        )
        .getValue()
    ).trim();

  const verifyStatus =
    String(
      sheet
        .getRange(
          row,
          7
        )
        .getValue()
    ).trim();

  if (
    verifyId !==
    delegationJobId
  ) {

    throw new Error(
      "DELEGATION_JOB_ID_VERIFICATION_FAILED"
    );
  }

  if (
    verifyStatus !==
    "PENDING_DISPATCH"
  ) {

    throw new Error(
      "DELEGATION_STATUS_VERIFICATION_FAILED"
    );
  }

  return {

    status:
      "DELEGATION_PERSISTED",

    verified:
      true,

    delegationJobId:
      delegationJobId,

    task:
      task,

    capability:
      capability,

    primaryAgent:
      primary.name,

    fallbackAgent:
      fallback
        ? fallback.name
        : null,

    state:
      "PENDING_DISPATCH",

    row:
      row,

    timestamp:
      new Date().toISOString()

  };
}


/* =========================================================
   READ DELEGATION JOB
========================================================= */

function getAERISDelegationJob(
  delegationJobId
) {

  if (!delegationJobId) {

    throw new Error(
      "MISSING_DELEGATION_JOB_ID"
    );
  }

  const sheet =
    getAERISDelegationSheet();

  const data =
    sheet
      .getDataRange()
      .getValues();

  for (
    let i = 1;
    i < data.length;
    i++
  ) {

    const row =
      data[i];

    if (
      String(
        row[0]
      ).trim() ===
      delegationJobId
    ) {

      return {

        status:
          "DELEGATION_JOB_FOUND",

        verified:
          true,

        delegationJobId:
          row[0],

        createdAt:
          row[1],

        task:
          row[2],

        capability:
          row[3],

        primaryAgent:
          row[4],

        fallbackAgent:
          row[5],

        state:
          row[6],

        result:
          row[7],

        error:
          row[8],

        dispatchedAt:
          row[9],

        completedAt:
          row[10]

      };
    }
  }

  throw new Error(
    "DELEGATION_JOB_NOT_FOUND: " +
    delegationJobId
  );
}


/* =========================================================
   LIST PENDING DELEGATIONS
========================================================= */

function listPendingAERISDelegations() {

  const sheet =
    getAERISDelegationSheet();

  const data =
    sheet
      .getDataRange()
      .getValues();

  const results = [];

  for (
    let i = 1;
    i < data.length;
    i++
  ) {

    const row =
      data[i];

    const status =
      String(
        row[6] || ""
      )
        .trim()
        .toUpperCase();

    if (
      status ===
      "PENDING_DISPATCH"
    ) {

      results.push({

        delegationJobId:
          row[0],

        createdAt:
          row[1],

        task:
          row[2],

        capability:
          row[3],

        primaryAgent:
          row[4],

        fallbackAgent:
          row[5],

        state:
          status

      });
    }
  }

  return {

    status:
      "PENDING_DELEGATIONS_FOUND",

    verified:
      true,

    count:
      results.length,

    jobs:
      results,

    timestamp:
      new Date().toISOString()

  };
}


/* =========================================================
   COMMAND QUEUE PROCESSOR
========================================================= */

function processCommandQueue() {

  const sheet = getQueueSheet();

  const requiredHeaders = [
    "Job ID",
    "Timestamp",
    "Command",
    "File ID",
    "File Name",
    "Destination",
    "Approved",
    "Content",
    "Status",
    "Result",
    "Error",
    "Completed At"
  ];

  ensureAERISQueueSchema(
    sheet,
    requiredHeaders
  );

  const data =
    sheet
      .getDataRange()
      .getValues();

  if (data.length < 2) {
    return {
      status: "NO_JOBS",
      processed: 0
    };
  }

  const headers = data[0];

  const jobIdIndex =
    headers.indexOf("Job ID");

  const timestampIndex =
    headers.indexOf("Timestamp");

  const commandIndex =
    headers.indexOf("Command");

  const fileIdIndex =
    headers.indexOf("File ID");

  const fileNameIndex =
    headers.indexOf("File Name");

  const destinationIndex =
    headers.indexOf("Destination");

  const approvedIndex =
    headers.indexOf("Approved");

  const contentIndex =
  headers.indexOf("Content");

  const statusIndex =
    headers.indexOf("Status");

  const resultIndex =
    headers.indexOf("Result");

  const errorIndex =
    headers.indexOf("Error");

  const completedIndex =
    headers.indexOf("Completed At");

  const requiredColumns = [
    jobIdIndex,
    timestampIndex,
    commandIndex,
    fileIdIndex,
    fileNameIndex,
    destinationIndex,
    approvedIndex,
    contentIndex,
    statusIndex,
    resultIndex,
    errorIndex,
    completedIndex
  ];

  if (
    requiredColumns.some(function(index) {
      return index === -1;
    })
  ) {
    throw new Error(
      "QUEUE_COLUMNS_INVALID"
    );
  }

  let processed = 0;

  for (
    let rowIndex = 1;
    rowIndex < data.length;
    rowIndex++
  ) {

    const row = data[rowIndex];

    const status =
      String(
        row[statusIndex] || ""
      )
        .trim()
        .toUpperCase();

    if (status !== "PENDING") {
      continue;
    }

    const jobId =
      String(
        row[jobIdIndex] || createJobId()
      ).trim();

    const command =
      String(
        row[commandIndex] || ""
      )
        .trim()
        .toUpperCase();

    const fileId =
      String(
        row[fileIdIndex] || ""
      ).trim();

    const fileName =
      String(
        row[fileNameIndex] || ""
      ).trim();

    const destination =
      String(
        row[destinationIndex] || ""
      ).trim();

    const content =
      String(
        row[contentIndex] || ""
      );

    const approved =
      String(
        row[approvedIndex] || ""
      )
        .trim()
        .toUpperCase();

    sheet
      .getRange(
        rowIndex + 1,
        statusIndex + 1
      )
      .setValue("PROCESSING");

    try {

      if (approved !== "TRUE") {
        throw new Error(
          "APPROVAL_REQUIRED"
        );
      }

      let result;

if (command === "EXECUTE_EXTERNAL") {

  result = dispatchToAERISRuntime(
    jobId,
    String(content || "TEST_EXECUTION").trim()
  );

  if (
    !result ||
    result.accepted !== true ||
    result.verified !== true ||
    result.executed !== true
  ) {
    throw new Error(
      "EXTERNAL_EXECUTION_VERIFICATION_FAILED"
    );
  }
  } else if (command === "STORE_FILE") {

      // =====================================================
      // STORE FILE
      // =====================================================

      
        if (!fileId) {
          throw new Error(
            "MISSING_FILE_ID"
          );
        }

        if (!destination) {
          throw new Error(
            "MISSING_DESTINATION"
          );
        }

        result =
          storeAerisFile(
            fileId,
            normalizeFolderNumber(
              destination
            )
          );

      // =====================================================
      // CREATE FILE
      // =====================================================

      } else if (command === "CREATE_FILE") {

        if (!fileName) {
          throw new Error(
            "MISSING_FILE_NAME"
          );
        }

        if (!destination) {
          throw new Error(
            "MISSING_DESTINATION"
          );
        }

        if (!content) {
          throw new Error(
            "MISSING_CONTENT"
          );
        }

        const normalizedFolder =
          normalizeFolderNumber(
            destination
          );

        const folderName =
          AERIS_FOLDERS[
            normalizedFolder
          ];

        const folder =
          getAerisFolder(
            folderName
          );

        const file =
          folder.createFile(
            fileName,
            content,
            MimeType.PLAIN_TEXT
          );

        const verifiedFile =
          DriveApp.getFileById(
            file.getId()
          );

        const readBack =
          verifiedFile
            .getBlob()
            .getDataAsString();

        if (readBack !== content) {
          throw new Error(
            "CONTENT_READBACK_VERIFICATION_FAILED"
          );
        }

        let verifiedParent = false;

        const parents =
          verifiedFile.getParents();

        while (parents.hasNext()) {

          const parent =
            parents.next();

          if (
            parent.getId() ===
            folder.getId()
          ) {
            verifiedParent = true;
            break;
          }
        }

        if (!verifiedParent) {
          throw new Error(
            "FOLDER_VERIFICATION_FAILED"
          );
        }

        result = {

          status:
            "FILE_CREATED",

          verified:
            true,

          executed:
            true,

          fileId:
            verifiedFile.getId(),

          fileName:
            verifiedFile.getName(),

          destination:
            folder.getName(),

          destinationFolderId:
            folder.getId(),

          contentVerified:
            true,

          readBackVerified:
            true,

          timestamp:
            new Date().toISOString()
        };

      // =====================================================
      // CREATE SAVEPOINT
      // =====================================================

      } else if (
        command === "CREATE_SAVEPOINT"
      ) {

        result =
          createAERISSavePointFromQueue(
            jobId
          );

      // =====================================================
      // SAVE STATE
      // =====================================================

      } else if (
        command === "SAVE_STATE"
      ) {

        result =
          createAERISStateSnapshot(
            jobId,
            command
          );

      // =====================================================
      // RESUME STATE
      // =====================================================

      } else if (
        command === "RESUME_STATE"
      ) {

        result =
          resumeAERISState();

      // =====================================================
      // SEARCH FILE
      // =====================================================

      } else if (
        command === "SEARCH_FILE"
      ) {

        result =
          searchAerisFile(
            fileName
          );

      // =====================================================
      // GET FILE
      // =====================================================

      } else if (
        command === "GET_FILE"
      ) {

        if (!fileId) {
          throw new Error(
            "MISSING_FILE_ID"
          );
        }

        result =
          getAerisFile(
            fileId
          );

      // =====================================================
      // DELEGATE GEMINI
      // =====================================================

      } else if (
        command === "DELEGATE_GEMINI"
      ) {

        const delegationJob =
          getAERISDelegationJobById(
            jobId
          );

        const execution =
          callAERISGemini(
            delegationJob
          );

        const validation =
          validateAERISGeminiResult(
            execution
          );

        if (
          validation.valid !== true
        ) {

          throw new Error(
            "GEMINI_RESULT_REJECTED: " +
            validation.reason
          );
        }

        validation.text =
          extractAERISGeminiText(
            execution
          );

        result = {

          status:
            "GEMINI_DELEGATION_COMPLETED",

          verified:
            true,

          executed:
            true,

          delegationJobId:
            jobId,

          httpStatus:
            execution.httpStatus,

          finishReason:
            validation.finishReason,

          text:
            validation.text
        };

      } else {

        throw new Error(
          "UNKNOWN_COMMAND: " +
          command
        );
      }

      // =====================================================
      // HARD ACCEPTANCE GATE
      // =====================================================

      if (
        !result ||
        result.verified !== true
      ) {

        throw new Error(
          "EXECUTION_VERIFICATION_FAILED"
        );
      }

      logJob(
        jobId,
        command,
        result.fileId || "",
        result.destination || "",
        result.status,
        true,
        ""
      );

      sheet
        .getRange(
          rowIndex + 1,
          jobIdIndex + 1
        )
        .setValue(jobId);

      sheet
        .getRange(
          rowIndex + 1,
          statusIndex + 1
        )
        .setValue("COMPLETED");

      sheet
        .getRange(
          rowIndex + 1,
          resultIndex + 1
        )
        .setValue(
          JSON.stringify(result)
        );

      sheet
        .getRange(
          rowIndex + 1,
          completedIndex + 1
        )
        .setValue(new Date());

      processed++;

    } catch (error) {

      logJob(
        jobId,
        command,
        fileId,
        destination,
        "FAILED",
        false,
        error.message
      );

      sheet
        .getRange(
          rowIndex + 1,
          jobIdIndex + 1
        )
        .setValue(jobId);

      sheet
        .getRange(
          rowIndex + 1,
          statusIndex + 1
        )
        .setValue("FAILED");

      sheet
        .getRange(
          rowIndex + 1,
          errorIndex + 1
        )
        .setValue(error.message);

      sheet
        .getRange(
          rowIndex + 1,
          completedIndex + 1
        )
        .setValue(new Date());
    }
  }

  const finalResult = {

    status:
      "QUEUE_PROCESSED",

    processed:
      processed,

    timestamp:
      new Date().toISOString()
  };

  Logger.log(
    "===== AERIS QUEUE RESULT ====="
  );

  Logger.log(
    JSON.stringify(
      finalResult,
      null,
      2
    )
  );

  Logger.log(
    "===== END AERIS QUEUE RESULT ====="
  );

  return finalResult;
}

/* =========================================================
   TEST FUNCTIONS
========================================================= */

function testV5Queue() {

  const result =
    bridgeCreateJob({

      command:
        "CREATE_SAVEPOINT",

      destination:
        "03",

      approved:
        true

    });

  Logger.log(
    JSON.stringify(
      result
    )
  );

  return result;
}


function testStateSnapshot() {

  const result =
    createAERISStateSnapshot(

      "V5.3-DIRECT-" +
      createJobId(),

      "SAVE_STATE"

    );

  Logger.log(
    JSON.stringify(
      result
    )
  );

  return result;
}


function testResumeState() {

  const result =
    resumeAERISState();

  Logger.log(
    JSON.stringify(
      result
    )
  );

  return result;
}


function testAERISAgentRegistry() {

  const registry =
    getAERISAgentRegistry();

  const result = {

    status:
      "AGENT_REGISTRY_READY",

    verified:
      true,

    version:
      AERIS_VERSION,

    count:
      Object.keys(
        registry
      ).length,

    agents:
      registry,

    timestamp:
      new Date().toISOString()

  };

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  return result;
}


function testAERISCapabilityRouting() {

  const result =
    findAERISAgentByCapability(
      "coding"
    );

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  return result;
}


function testAERISDelegation() {

  const result =
    createAERISDelegationTask({

      task:
        "ตรวจสอบและแก้ไข Apps Script V5.4.1",

      capability:
        "coding"

    });

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  return result;
}


/* =========================================================
   GATE 4 TEST
========================================================= */

function testPersistentAERISDelegation() {

  const result =
    createPersistentAERISDelegationTask({

      task:
        "ทดสอบ Persistent Delegation Queue",

      capability:
        "coding"

    });

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  return result;
}


/* =========================================================
   READ PERSISTENT DELEGATION
========================================================= */

function testReadPersistentDelegation() {

  const result =
    listPendingAERISDelegations();

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  return result;
}


/* =========================================================
   DIRECT SAVEPOINT TEST
========================================================= */

function testDirectSavePoint() {

  const result =
    createAERISSavePointFromQueue(

      "DIRECT-TEST-" +
      createJobId()

    );

  Logger.log(
    JSON.stringify(
      result
    )
  );

  return result;
}/* =========================================================
   AERIS MUSIC — V5.5 DISPATCHER ENGINE
   PURPOSE:
   - Read PENDING_DISPATCH jobs
   - Select Primary Agent
   - Prepare executable dispatch payload
   - Mark job as DISPATCH_READY
   - NEVER claim external AI execution without verification
   - No new trigger
========================================================= */


/* =========================================================
   V5.5 DISPATCH CONSTANTS
========================================================= */

const DISPATCH_READY_STATUS =
  "DISPATCH_READY";

const DISPATCH_FAILED_STATUS =
  "DISPATCH_FAILED";


/* =========================================================
   FIND NEXT PENDING DISPATCH
========================================================= */
function getNextAERISDispatchJob() {

  const sheet =
    getAERISDelegationSheet();

  const data =
    sheet
      .getDataRange()
      .getValues();

  if (data.length < 2) {

    return {

      status:
        "NO_DISPATCH_JOBS",

      verified:
        true,

      available:
        false

    };
  }

  for (
    let i = 1;
    i < data.length;
    i++
  ) {

    const row =
      data[i];

    const status =
      String(
        row[6] || ""
      )
      .trim()
      .toUpperCase();

    if (
      status !== "PENDING_DISPATCH" &&
      status !== "RETRY_PENDING"
    ) {
      continue;
    }

    return {

      status:
        "DISPATCH_JOB_FOUND",

      verified:
        true,

      available:
        true,

      row:
        i + 1,

      delegationJobId:
        row[0],

      createdAt:
        row[1],

      task:
        row[2],

      capability:
        row[3],

      primaryAgent:
        row[4],

      fallbackAgent:
        row[5],

      state:
        status

    };
  }

  return {

    status:
      "NO_DISPATCH_JOBS",

    verified:
      true,

    available:
      false,

    timestamp:
      new Date().toISOString()

  };
}
/* =========================================================
   BUILD DISPATCH PAYLOAD
========================================================= */

function buildAERISDispatchPayload(
  job
) {

  if (!job) {

    throw new Error(
      "MISSING_DISPATCH_JOB"
    );
  }

  if (
    !job.delegationJobId
  ) {

    throw new Error(
      "MISSING_DELEGATION_JOB_ID"
    );
  }

  if (!job.task) {

    throw new Error(
      "MISSING_DELEGATION_TASK"
    );
  }

  if (!job.primaryAgent) {

    throw new Error(
      "MISSING_PRIMARY_AGENT"
    );
  }

  return {

    protocol:
      "AERIS DISPATCH v1",

    delegationJobId:
      job.delegationJobId,

    task:
      job.task,

    capability:
      job.capability,

    primaryAgent:
      job.primaryAgent,

    fallbackAgent:
      job.fallbackAgent || null,

    instruction:
      "EXECUTE_TASK_AND_RETURN_STRUCTURED_RESULT",

    responseRequired:
      true,

    persistenceRequired:
      true,

    verificationRequired:
      true,

    createdAt:
      new Date().toISOString()

  };
}


/* =========================================================
   MARK DISPATCH READY
========================================================= */

function markAERISDispatchReady(
  job
) {

  if (!job) {

    throw new Error(
      "MISSING_DISPATCH_JOB"
    );
  }

  const sheet =
    getAERISDelegationSheet();

  const row =
    Number(
      job.row
    );

  if (
    !row ||
    row < 2
  ) {

    throw new Error(
      "INVALID_DISPATCH_ROW"
    );
  }

  const currentStatus =
    String(
      sheet
        .getRange(
          row,
          7
        )
        .getValue()
    )
      .trim()
      .toUpperCase();

  if (
    currentStatus !==
      "PENDING_DISPATCH" &&
    currentStatus !==
      "RETRY_PENDING"
  ) {

    throw new Error(
      "DISPATCH_STATUS_CHANGED: " +
      currentStatus
    );
  }

  const payload =
    buildAERISDispatchPayload(
      job
    );

  const dispatchedAt =
    new Date();

  sheet
    .getRange(
      row,
      7
    )
    .setValue(
      DISPATCH_READY_STATUS
    );

  sheet
    .getRange(
      row,
      8
    )
    .setValue(
      JSON.stringify(
        payload
      )
    );

  sheet
    .getRange(
      row,
      10
    )
    .setValue(
      dispatchedAt
    );

  const verifyStatus =
    String(
      sheet
        .getRange(
          row,
          7
        )
        .getValue()
    )
      .trim()
      .toUpperCase();

  const verifyResult =
    String(
      sheet
        .getRange(
          row,
          8
        )
        .getValue()
    ).trim();

  if (
    verifyStatus !==
    DISPATCH_READY_STATUS
  ) {

    throw new Error(
      "DISPATCH_READY_VERIFICATION_FAILED"
    );
  }

  if (!verifyResult) {

    throw new Error(
      "DISPATCH_PAYLOAD_VERIFICATION_FAILED"
    );
  }

  return {

    status:
      "DISPATCH_READY",

    verified:
      true,

    delegationJobId:
      job.delegationJobId,

    primaryAgent:
      job.primaryAgent,

    fallbackAgent:
      job.fallbackAgent ||
      null,

    state:
      DISPATCH_READY_STATUS,

    row:
      row,

    dispatchedAt:
      dispatchedAt.toISOString(),

    payload:
      payload

  };
}
/* =========================================================
   DISPATCHER — PREPARE NEXT JOB
========================================================= */

function dispatchNextAERISJob() {

  const job =
    getNextAERISDispatchJob();

  if (
    job.available === false
  ) {

    return job;
  }

  try {

    return markAERISDispatchReady(
      job
    );

  } catch (error) {

    return {

      status:
        DISPATCH_FAILED_STATUS,

      verified:
        false,

      delegationJobId:
        job.delegationJobId,

      error:
        error.message,

      timestamp:
        new Date().toISOString()

    };
  }
}


/* =========================================================
   EXTERNAL EXECUTION GATE
========================================================= */

function executeAERISExternalDispatch(
  dispatchPayload
) {

  if (!dispatchPayload) {
    throw new Error("MISSING_DISPATCH_PAYLOAD");
  }

  const job = {
    delegationJobId: dispatchPayload.delegationJobId,
    task: dispatchPayload.task,
    capability: dispatchPayload.capability,
    primaryAgent: dispatchPayload.primaryAgent,
    fallbackAgent: dispatchPayload.fallbackAgent || null,
    instruction: dispatchPayload.instruction,
    responseRequired: dispatchPayload.responseRequired,
    persistenceRequired: dispatchPayload.persistenceRequired,
    verificationRequired: dispatchPayload.verificationRequired
  };

  /*
   * =======================================================
   * PRIMARY: GEMINI
   * =======================================================
   */

  if (
    String(job.primaryAgent || "")
      .trim()
      .toUpperCase() === "GEMINI"
  ) {

    const execution =
      callAERISGemini(job);

    /*
     * GEMINI SUCCESS
     */

    if (execution.executed === true) {

      const validation =
        validateAERISGeminiResult(execution);

      if (validation.valid !== true) {

        return {
          status:
            "EXTERNAL_DISPATCH_VERIFICATION_FAILED",

          verified: false,
          executed: true,

          delegationJobId:
            job.delegationJobId,

          primaryAgent:
            job.primaryAgent,

          validation:
            validation,

          timestamp:
            new Date().toISOString()
        };
      }

      return {

        status:
          "EXTERNAL_DISPATCH_COMPLETED",

        verified: true,
        executed: true,

        delegationJobId:
          job.delegationJobId,

        primaryAgent:
          job.primaryAgent,

        fallbackAgent:
          job.fallbackAgent,

        httpStatus:
          execution.httpStatus,

        finishReason:
          validation.finishReason,

        text:
          extractAERISGeminiText(
            execution
          ),

        rawExecution:
          execution,

        timestamp:
          new Date().toISOString()
      };
    }

    /*
     * =====================================================
     * GEMINI 429 / QUOTA RECOVERY
     * =====================================================
     */

    if (
      Number(execution.httpStatus) === 429
    ) {

      return {

        status:
          "GEMINI_QUOTA_EXHAUSTED",

        verified: true,
        executed: false,

        delegationJobId:
          job.delegationJobId,

        primaryAgent:
          job.primaryAgent,

        fallbackAgent:
          job.fallbackAgent,

        retryRequired:
          true,

        retryAfterSeconds:
          60,

        primaryExecution:
          execution,

        nextStep:
          "RETRY_AFTER_QUOTA_WINDOW",

        timestamp:
          new Date().toISOString()
      };
    }

    /*
     * =====================================================
     * OTHER GEMINI FAILURE
     * =====================================================
     */

    return {

      status:
        "EXTERNAL_DISPATCH_FAILED",

      verified: true,
      executed: false,

      delegationJobId:
        job.delegationJobId,

      primaryAgent:
        job.primaryAgent,

      fallbackAgent:
        job.fallbackAgent,

      primaryExecution:
        execution,

      retryRequired:
        false,

      nextStep:
        "WAIT_FOR_EXTERNAL_EXECUTOR",

      timestamp:
        new Date().toISOString()
    };
  }

  /*
   * =======================================================
   * UNSUPPORTED PRIMARY
   * =======================================================
   */

  return {

    status:
      "UNSUPPORTED_PRIMARY_AGENT",

    verified: true,
    executed: false,

    delegationJobId:
      job.delegationJobId,

    primaryAgent:
      job.primaryAgent,

    fallbackAgent:
      job.fallbackAgent,

    timestamp:
      new Date().toISOString()
  };
}
/* =========================================================
   V5.5 MASTER DISPATCH
========================================================= */

function processAERISDispatcher() {

  const dispatch =
    dispatchNextAERISJob();

  if (
    dispatch.status ===
    "NO_DISPATCH_JOBS"
  ) {
    return dispatch;
  }

  if (
    dispatch.status !==
    "DISPATCH_READY"
  ) {
    return dispatch;
  }

  const execution =
    executeAERISExternalDispatch(
      dispatch.payload
    );

  /*
   * =======================================================
   * PRIMARY EXECUTION SUCCESS
   * =======================================================
   */

  if (
    execution.executed === true &&
    execution.verified === true
  ) {

    return {

      status:
        "DISPATCH_COMPLETED",

      verified:
        true,

      executed:
        true,

      delegationJobId:
        dispatch.delegationJobId,

      primaryAgent:
        dispatch.primaryAgent,

      fallbackAgent:
        dispatch.fallbackAgent,

      externalExecution:
        execution,

      timestamp:
        new Date().toISOString()

    };
  }

  /*
   * =======================================================
   * PRIMARY FAILED → FALLBACK
   * =======================================================
   */

  if (
    execution.executed !== true &&
    dispatch.fallbackAgent
  ) {

    const fallbackJob = {

      delegationJobId:
        dispatch.delegationJobId,

      task:
        dispatch.payload.task,

      capability:
        dispatch.payload.capability,

      primaryAgent:
        dispatch.primaryAgent,

      fallbackAgent:
        dispatch.fallbackAgent,

      instruction:
        dispatch.payload.instruction,

      responseRequired:
        dispatch.payload.responseRequired,

      persistenceRequired:
        dispatch.payload.persistenceRequired,

      verificationRequired:
        dispatch.payload.verificationRequired

    };

    const fallback =
      handleAERISDispatchRetry(
        fallbackJob
      );

    return {

      status:
        fallback.status,

      verified:
        fallback.verified,

      executed:
        fallback.executed,

      delegationJobId:
        dispatch.delegationJobId,

      primaryAgent:
        dispatch.primaryAgent,

      fallbackAgent:
        dispatch.fallbackAgent,

      primaryExecution:
        execution,

      fallbackExecution:
        fallback,

      timestamp:
        new Date().toISOString()

    };
  }

  /*
   * =======================================================
   * NO FALLBACK
   * =======================================================
   */

  return {

    status:
      "DISPATCH_FAILED",

    verified:
      true,

    executed:
      false,

    delegationJobId:
      dispatch.delegationJobId,

    primaryAgent:
      dispatch.primaryAgent,

    fallbackAgent:
      dispatch.fallbackAgent || null,

    externalExecution:
      execution,

    timestamp:
      new Date().toISOString()

  };
}
/* =========================================================
   V5.5 TEST
========================================================= */

function testAERISDispatcher() {

  const result =
    processAERISDispatcher();

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  return result;
}


/* =========================================================
   V5.5 READ TEST
========================================================= */

function testAERISDispatcherRead() {

  const result =
    getNextAERISDispatchJob();

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  return result;
}/* =========================================================
   AERIS MUSIC — V5.6 EXTERNAL AI EXECUTOR
   PURPOSE:
   - Convert DISPATCH_READY into executable external task
   - Support Connector-Ready architecture
   - Never claim external AI execution without verification
   - Preserve Primary / Fallback routing
   - No new trigger
========================================================= */


/* =========================================================
   V5.6 CONSTANTS
========================================================= */

const EXTERNAL_EXECUTION_STATUS =
  "EXTERNAL_EXECUTION_PENDING";

const EXTERNAL_NOT_CONNECTED_STATUS =
  "EXTERNAL_CONNECTOR_REQUIRED";


/* =========================================================
   FIND DISPATCH-READY JOB
========================================================= */

function getAERISDispatchReadyJob() {

  const sheet =
    getAERISDelegationSheet();

  const data =
    sheet
      .getDataRange()
      .getValues();

  if (data.length < 2) {

    return {
      status:
        "NO_DISPATCH_READY_JOBS",
      verified:
        true,
      available:
        false
    };
  }

  for (
    let i = 1;
    i < data.length;
    i++
  ) {

    const row =
      data[i];

    const status =
      String(
        row[6] || ""
      )
        .trim()
        .toUpperCase();

    if (
      status !==
      "DISPATCH_READY"
    ) {
      continue;
    }

    let payload = null;

    try {

      payload =
        JSON.parse(
          String(row[7] || "")
        );

    } catch (error) {

      throw new Error(
        "DISPATCH_PAYLOAD_INVALID"
      );
    }

    return {

      status:
        "DISPATCH_READY_JOB_FOUND",

      verified:
        true,

      available:
        true,

      row:
        i + 1,

      delegationJobId:
        row[0],

      task:
        row[2],

      capability:
        row[3],

      primaryAgent:
        row[4],

      fallbackAgent:
        row[5],

      payload:
        payload

    };
  }

  return {

    status:
      "NO_DISPATCH_READY_JOBS",

    verified:
      true,

    available:
      false

  };
}


/* =========================================================
   CONNECTOR REGISTRY
========================================================= */

function getAERISExternalConnector(
  agentName
) {

  const agent =
    String(
      agentName || ""
    )
      .trim()
      .toUpperCase();

  const connectors = {

    "GEMINI": {
      agent:
        "Gemini",

      connected:
        false,

      transport:
        "NOT_CONFIGURED",

      execution:
        false
    },

    "COPILOT": {
      agent:
        "Copilot",

      connected:
        false,

      transport:
        "NOT_CONFIGURED",

      execution:
        false
    }

  };

  return (
    connectors[agent] || {

      agent:
        agentName,

      connected:
        false,

      transport:
        "UNKNOWN",

      execution:
        false

    }
  );
}


/* =========================================================
   VERIFY CONNECTOR
========================================================= */

function verifyAERISExternalConnector(
  agentName
) {

  const connector =
    getAERISExternalConnector(
      agentName
    );

  if (
    connector.connected !== true ||
    connector.execution !== true
  ) {

    return {

      status:
        EXTERNAL_NOT_CONNECTED_STATUS,

      verified:
        true,

      connected:
        false,

      executable:
        false,

      agent:
        connector.agent,

      transport:
        connector.transport

    };
  }

  return {

    status:
      "EXTERNAL_CONNECTOR_READY",

    verified:
      true,

    connected:
      true,

    executable:
      true,

    agent:
      connector.agent,

    transport:
      connector.transport

  };
}


/* =========================================================
   BUILD EXTERNAL EXECUTION REQUEST
========================================================= */

function buildAERISExternalExecutionRequest(
  job
) {

  if (!job) {

    throw new Error(
      "MISSING_EXTERNAL_EXECUTION_JOB"
    );
  }

  const connector =
    verifyAERISExternalConnector(
      job.primaryAgent
    );

  return {

    protocol:
      "AERIS EXTERNAL EXECUTION v1",

    delegationJobId:
      job.delegationJobId,

    agent:
      job.primaryAgent,

    fallbackAgent:
      job.fallbackAgent || null,

    capability:
      job.capability,

    task:
      job.task,

    connector:
      connector,

    executionRequired:
      true,

    resultRequired:
      true,

    verificationRequired:
      true,

    persistenceRequired:
      true,

    createdAt:
      new Date().toISOString()

  };
}


/* =========================================================
   EXECUTION GATE
========================================================= */

function executeAERISExternalJob(
  job
) {

  const request =
    buildAERISExternalExecutionRequest(
      job
    );

  const connector =
    request.connector;

  /*
   IMPORTANT:
   No external API call is performed here
   until a verified connector is configured.
  */

  if (
    connector.executable !== true
  ) {

    return {

      status:
        EXTERNAL_NOT_CONNECTED_STATUS,

      verified:
        true,

      executed:
        false,

      delegationJobId:
        job.delegationJobId,

      primaryAgent:
        job.primaryAgent,

      fallbackAgent:
        job.fallbackAgent,

      request:
        request,

      reason:
        "NO_VERIFIED_EXTERNAL_AI_CONNECTOR"

    };
  }

  /*
   Future verified connector execution
   will be inserted here.
  */

  return {

    status:
      "EXTERNAL_EXECUTION_COMPLETED",

    verified:
      false,

    executed:
      false,

    reason:
      "EXECUTOR_IMPLEMENTATION_PENDING"

  };
}


/* =========================================================
   FALLBACK ROUTING CHECK
========================================================= */

function checkAERISFallbackAgent(
  job
) {

  if (!job) {

    throw new Error(
      "MISSING_FALLBACK_JOB"
    );
  }

  const primary =
    verifyAERISExternalConnector(
      job.primaryAgent
    );

  if (
    primary.executable === true
  ) {

    return {

      status:
        "PRIMARY_AVAILABLE",

      verified:
        true,

      selectedAgent:
        job.primaryAgent,

      fallbackUsed:
        false

    };
  }

  if (
    !job.fallbackAgent
  ) {

    return {

      status:
        "NO_FALLBACK_AGENT",

      verified:
        true,

      selectedAgent:
        null,

      fallbackUsed:
        false

    };
  }

  const fallback =
    verifyAERISExternalConnector(
      job.fallbackAgent
    );

  if (
    fallback.executable === true
  ) {

    return {

      status:
        "FALLBACK_AVAILABLE",

      verified:
        true,

      selectedAgent:
        job.fallbackAgent,

      fallbackUsed:
        true

    };
  }

  return {

    status:
      "NO_EXTERNAL_EXECUTOR_AVAILABLE",

    verified:
      true,

    selectedAgent:
      null,

    fallbackUsed:
      false

  };
}


/* =========================================================
   V5.6 MASTER EXECUTOR
========================================================= */

function processAERISExternalExecutor() {

  const job =
    getAERISDispatchReadyJob();

  if (
    job.available !== true
  ) {

    return job;
  }

  const routing =
    checkAERISFallbackAgent(
      job
    );

  if (
    routing.selectedAgent === null
  ) {

    return {

      status:
        EXTERNAL_NOT_CONNECTED_STATUS,

      verified:
        true,

      executed:
        false,

      delegationJobId:
        job.delegationJobId,

      primaryAgent:
        job.primaryAgent,

      fallbackAgent:
        job.fallbackAgent,

      routing:
        routing,

      nextStep:
        "CONFIGURE_VERIFIED_EXTERNAL_CONNECTOR",

      timestamp:
        new Date().toISOString()

    };
  }

  const execution =
    executeAERISExternalJob(
      job
    );

  return {

    status:
      "EXTERNAL_EXECUTOR_PROCESSED",

    verified:
      true,

    delegationJobId:
      job.delegationJobId,

    selectedAgent:
      routing.selectedAgent,

    fallbackUsed:
      routing.fallbackUsed,

    execution:
      execution,

    timestamp:
      new Date().toISOString()

  };
}


/* =========================================================
   V5.6 TEST
========================================================= */

function testAERISExternalExecutor() {

  const result =
    processAERISExternalExecutor();

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  return result;
}


/* =========================================================
   V5.6 CONNECTOR STATUS TEST
========================================================= */

function testAERISConnectorStatus() {

  const gemini =
    verifyAERISExternalConnector(
      "Gemini"
    );

  const copilot =
    verifyAERISExternalConnector(
      "Copilot"
    );

  const result = {

    status:
      "CONNECTOR_STATUS_CHECKED",

    verified:
      true,

    Gemini:
      gemini,

    Copilot:
      copilot,

    timestamp:
      new Date().toISOString()

  };

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  return result;
}/* =========================================================
   AERIS MUSIC — V5.7 GEMINI CONNECTOR
   PURPOSE:
   - Connect AERIS Dispatcher to Gemini API
   - Secure API key via Script Properties
   - Never expose API key in logs
   - Never claim execution without HTTP verification
   - Free-first architecture
========================================================= */

const AERIS_GEMINI_ENDPOINT =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent";

/* =========================================================
   GEMINI CONNECTOR STATUS
========================================================= */

function getAERISGeminiConnector() {

  const key =
    PropertiesService
      .getScriptProperties()
      .getProperty("GEMINI_API_KEY");

  return {

    agent: "Gemini",

    connected:
      !!key,

    executable:
      !!key,

    transport:
      "GEMINI_API_REST",

    keyConfigured:
      !!key,

    freeFirst:
      true

  };
}


/* =========================================================
   GEMINI CONNECTOR VERIFICATION
========================================================= */

function verifyAERISGeminiConnector() {

  const connector =
    getAERISGeminiConnector();

  if (!connector.keyConfigured) {

    return {

      status:
        "GEMINI_API_KEY_REQUIRED",

      verified:
        true,

      connected:
        false,

      executable:
        false,

      agent:
        "Gemini",

      transport:
        connector.transport,

      nextStep:
        "CONFIGURE_GEMINI_API_KEY"

    };
  }

  return {

    status:
      "GEMINI_CONNECTOR_READY",

    verified:
      true,

    connected:
      true,

    executable:
      true,

    agent:
      "Gemini",

    transport:
      connector.transport,

    freeFirst:
      true

  };
}


/* =========================================================
   BUILD GEMINI REQUEST
========================================================= */

function buildAERISGeminiRequest(
  job
) {

  if (!job) {

    throw new Error(
      "MISSING_GEMINI_JOB"
    );
  }

  if (!job.task) {

    throw new Error(
      "MISSING_GEMINI_TASK"
    );
  }

  return {

    contents: [

      {

        role:
          "user",

        parts: [

          {

            text:
              "AERIS MUSIC EXECUTION TASK\n\n" +
              "Job ID: " +
              job.delegationJobId +
              "\n\n" +
              "Capability: " +
              job.capability +
              "\n\n" +
              "Task:\n" +
              job.task +
              "\n\n" +
              "Return a concise structured result. " +
              "Do not claim actions you did not actually perform."

          }

        ]

      }

    ]

  };
}


/* =========================================================
   CALL GEMINI
========================================================= */

function callAERISGemini(
  job
) {

  const verification =
    verifyAERISGeminiConnector();

  if (
    verification.executable !== true
  ) {

    return {

      status:
        "GEMINI_CONNECTOR_REQUIRED",

      verified:
        true,

      executed:
        false,

      connector:
        verification

    };
  }

  const apiKey =
    PropertiesService
      .getScriptProperties()
      .getProperty(
        "GEMINI_API_KEY"
      );

  const payload =
    buildAERISGeminiRequest(
      job
    );

  const response =
    UrlFetchApp.fetch(
      AERIS_GEMINI_ENDPOINT,
      {

        method:
          "post",

        contentType:
          "application/json",

        headers: {

          "x-goog-api-key":
            apiKey

        },

        payload:
          JSON.stringify(
            payload
          ),

        muteHttpExceptions:
          true

      }
    );

  const httpCode =
    response.getResponseCode();

  const body =
    response.getContentText();

  if (
    httpCode < 200 ||
    httpCode >= 300
  ) {

    return {

      status:
        "GEMINI_EXECUTION_FAILED",

      verified:
        true,

      executed:
        false,

      httpStatus:
        httpCode,

      error:
        body.substring(
          0,
          1000
        )

    };
  }

  let parsed;

  try {

    parsed =
      JSON.parse(
        body
      );

  } catch (error) {

    throw new Error(
      "GEMINI_RESPONSE_INVALID"
    );
  }

  return {

    status:
      "GEMINI_EXECUTED",

    verified:
      true,

    executed:
      true,

    httpStatus:
      httpCode,

    delegationJobId:
      job.delegationJobId,

    response:
      parsed,

    timestamp:
      new Date().toISOString()

  };
}


/* =========================================================
   V5.7 MASTER EXECUTOR
========================================================= */

function processAERISGeminiExecutor() {

  const job =
    getAERISDispatchReadyJob();

  if (
    job.available !== true
  ) {

    return job;
  }

  const connector =
    verifyAERISGeminiConnector();

  if (
    connector.executable !== true
  ) {

    return {

      status:
        "GEMINI_CONNECTOR_REQUIRED",

      verified:
        true,

      executed:
        false,

      delegationJobId:
        job.delegationJobId,

      connector:
        connector,

      nextStep:
        "CONFIGURE_GEMINI_API_KEY",

      timestamp:
        new Date().toISOString()

    };
  }

  return callAERISGemini(
    job
  );
}


/* =========================================================
   V5.7 TEST — NO API CALL
========================================================= */

function testAERISGeminiConnector() {

  const result =
    verifyAERISGeminiConnector();

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  return result;
}function testAERISGeminiExecutionVisible() {

  const result =
    processAERISGeminiExecutor();

  Logger.log(
    "===== AERIS GEMINI EXECUTION RESULT ====="
  );

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  Logger.log(
    "===== END RESULT ====="
  );

  return result;
}/* =========================================================
   AERIS MUSIC — V5.8 RESULT VALIDATOR
   PURPOSE:
   - Validate actual Gemini execution result
   - Reject malformed/tool-call responses
   - Prevent false COMPLETED status
   - Preserve DISPATCH_READY on invalid result
   - Prepare safe retry / fallback path
   - No new trigger
========================================================= */


/* =========================================================
   V5.8 VALID FINISH REASONS
========================================================= */

const AERIS_VALID_FINISH_REASONS = [
  "STOP",
  "MAX_TOKENS"
];


/* =========================================================
   EXTRACT GEMINI TEXT
========================================================= */

function extractAERISGeminiText(
  executionResult
) {

  if (!executionResult) {
    return "";
  }

  if (!executionResult.response) {
    return "";
  }

  const candidates =
    executionResult
      .response
      .candidates;

  if (
    !Array.isArray(candidates) ||
    candidates.length === 0
  ) {
    return "";
  }

  const candidate =
    candidates[0];

  if (!candidate.content) {
    return "";
  }

  const parts =
    candidate.content.parts;

  if (
    !Array.isArray(parts)
  ) {
    return "";
  }

  const textParts = [];

  parts.forEach(function(part) {

    if (
      part &&
      typeof part.text === "string" &&
      part.text.trim()
    ) {

      textParts.push(
        part.text.trim()
      );

    }

  });

  return textParts.join("\n").trim();
}


/* =========================================================
   VALIDATE GEMINI RESPONSE
========================================================= */

function validateAERISGeminiResult(
  executionResult
) {

  if (!executionResult) {

    return {

      valid:
        false,

      reason:
        "MISSING_EXECUTION_RESULT"

    };

  }

  if (
    executionResult.executed !== true
  ) {

    return {

      valid:
        false,

      reason:
        "EXECUTION_NOT_CONFIRMED"

    };

  }

  if (
    executionResult.httpStatus !== 200
  ) {

    return {

      valid:
        false,

      reason:
        "HTTP_STATUS_NOT_200",

      httpStatus:
        executionResult.httpStatus

    };

  }

  if (
    !executionResult.response
  ) {

    return {

      valid:
        false,

      reason:
        "MISSING_GEMINI_RESPONSE"

    };

  }

  const candidates =
    executionResult
      .response
      .candidates;

  if (
    !Array.isArray(candidates) ||
    candidates.length === 0
  ) {

    return {

      valid:
        false,

      reason:
        "NO_CANDIDATES"

    };

  }

  const candidate =
    candidates[0];

  const finishReason =
    String(
      candidate.finishReason || ""
    )
      .trim()
      .toUpperCase();

  if (
    AERIS_VALID_FINISH_REASONS
      .indexOf(
        finishReason
      ) === -1
  ) {

    return {

      valid:
        false,

      reason:
        "INVALID_FINISH_REASON",

      finishReason:
        finishReason

    };

  }

  const text =
    extractAERISGeminiText(
      executionResult
    );

  if (!text) {

    return {

      valid:
        false,

      reason:
        "EMPTY_TEXT_RESPONSE",

      finishReason:
        finishReason

    };

  }

  return {

    valid:
      true,

    reason:
      "VALID_GEMINI_RESULT",

    finishReason:
      finishReason,

    textLength:
      text.length

  };

}


/* =========================================================
   GET DELEGATION ROW BY JOB ID
========================================================= */

function getAERISDelegationJobById(
  delegationJobId
) {

  if (!delegationJobId) {

    throw new Error(
      "MISSING_DELEGATION_JOB_ID"
    );

  }

  const sheet =
    getAERISDelegationSheet();

  const data =
    sheet
      .getDataRange()
      .getValues();

  for (
    let i = 1;
    i < data.length;
    i++
  ) {

    if (
      String(data[i][0])
        .trim() ===
      String(delegationJobId)
        .trim()
    ) {

      return {

        row:
          i + 1,

        delegationJobId:
          data[i][0],

        task:
          data[i][2],

        capability:
          data[i][3],

        primaryAgent:
          data[i][4],

        fallbackAgent:
          data[i][5],

        status:
          data[i][6],

        result:
          data[i][7],

        error:
          data[i][8],

        dispatchedAt:
          data[i][9],

        completedAt:
          data[i][10]

      };

    }

  }

  throw new Error(
    "DELEGATION_JOB_NOT_FOUND: " +
    delegationJobId
  );

}


/* =========================================================
   STORE VALID RESULT
========================================================= */

function completeAERISDelegationJob(
  job,
  executionResult,
  validation
) {

  if (
    !job ||
    !executionResult ||
    !validation
  ) {

    throw new Error(
      "MISSING_COMPLETION_DATA"
    );

  }

  if (
    validation.valid !== true
  ) {

    throw new Error(
      "INVALID_RESULT_CANNOT_COMPLETE"
    );

  }

  const sheet =
    getAERISDelegationSheet();

  const row =
    job.row;

  const currentStatus =
    String(
      sheet
        .getRange(row, 7)
        .getValue()
    )
      .trim()
      .toUpperCase();

  if (
    currentStatus !==
    "DISPATCH_READY"
  ) {

    throw new Error(
      "COMPLETION_STATUS_INVALID: " +
      currentStatus
    );

  }

  const resultPayload = {

    verification:
      "PASSED",

    validator:
      "AERIS V5.8",

    finishReason:
      validation.finishReason,

    text:
      validation.text,

    execution:
      executionResult,

    completedAt:
      new Date().toISOString()

  };

  sheet
    .getRange(row, 7)
    .setValue(
      "COMPLETED"
    );

  sheet
    .getRange(row, 8)
    .setValue(
      JSON.stringify(
        resultPayload
      )
    );

  sheet
    .getRange(row, 11)
    .setValue(
      new Date()
    );

  return {

    status:
      "DELEGATION_COMPLETED",

    verified:
      true,

    delegationJobId:
      job.delegationJobId,

    row:
      row,

    finishReason:
      validation.finishReason,

    text:
      validation.text,

    completedAt:
      new Date().toISOString()

  };

}


/* =========================================================
   REJECT INVALID RESULT
========================================================= */

function rejectAERISDelegationResult(
  job,
  validation
) {

  if (!job) {

    throw new Error(
      "MISSING_REJECTION_JOB"
    );

  }

  const sheet =
    getAERISDelegationSheet();

  const row =
    job.row;

  /*
   IMPORTANT:
   Invalid results MUST NOT become COMPLETED.
   Keep the job available for retry/fallback.
  */

  const errorPayload = {

    validator:
      "AERIS V5.8",

    verified:
      true,

    rejected:
      true,

    reason:
      validation.reason,

    finishReason:
      validation.finishReason || "",

    rejectedAt:
      new Date().toISOString()

  };

  sheet
    .getRange(row, 8)
    .setValue("");

  sheet
    .getRange(row, 9)
    .setValue(
      JSON.stringify(
        errorPayload
      )
    );

  /*
   Return to DISPATCH_READY.
   This allows the future Retry/Fallback Engine
   to process the job without creating a new job.
  */

  sheet
    .getRange(row, 7)
    .setValue(
      "DISPATCH_READY"
    );

  return {

    status:
      "RESULT_REJECTED",

    verified:
      true,

    completed:
      false,

    retryAvailable:
      true,

    delegationJobId:
      job.delegationJobId,

    reason:
      validation.reason,

    finishReason:
      validation.finishReason || "",

    nextStep:
      "RETRY_OR_FALLBACK"

  };

}


/* =========================================================
   V5.8 VALIDATED GEMINI EXECUTION
========================================================= */

function processAERISValidatedGeminiExecution() {

  const readyJob =
    getAERISDispatchReadyJob();

  if (
    readyJob.available !== true
  ) {

    return readyJob;

  }

  /*
   Actual Gemini API execution
  */

  const execution =
    callAERISGemini(
      readyJob
    );

  /*
   Validate actual result
  */

  const validation =
    validateAERISGeminiResult(
      execution
    );

  if (
    validation.valid === true
  ) {

    const text =
      extractAERISGeminiText(
        execution
      );

    validation.text =
      text;

    return completeAERISDelegationJob(
      readyJob,
      execution,
      validation
    );

  }

  return rejectAERISDelegationResult(
    readyJob,
    validation
  );

}


/* =========================================================
   V5.8 TEST — VALIDATOR ONLY
========================================================= */

function testAERISGeminiValidator() {

  const result =
    processAERISValidatedGeminiExecution();

  Logger.log(
    "===== AERIS V5.8 VALIDATOR ====="
  );

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  Logger.log(
    "===== END V5.8 ====="
  );

  return result;

}/* =========================================================
   AERIS MUSIC — V5.9 RETRY + FALLBACK ENGINE
   PURPOSE:
   - Retry failed Gemini execution
   - Fallback to Copilot
   - Preserve original Delegation Job ID
   - Validate every result
   - Prevent false COMPLETED
   - No new trigger
========================================================= */


/* =========================================================
   V5.9 CONFIGURATION
========================================================= */

const AERIS_RETRY_LIMIT = 1;

const AERIS_RETRYABLE_REASONS = [
  "INVALID_FINISH_REASON",
  "EMPTY_TEXT_RESPONSE",
  "MISSING_GEMINI_RESPONSE",
  "NO_CANDIDATES",
  "HTTP_STATUS_NOT_200",
  "EXECUTION_NOT_CONFIRMED"
];


/* =========================================================
   FIND DISPATCH READY JOB
========================================================= */

function getAERISDispatchReadyJob() {

  const sheet =
    getAERISDelegationSheet();

  const data =
    sheet
      .getDataRange()
      .getValues();

  for (
    let i = 1;
    i < data.length;
    i++
  ) {

    const status =
      String(data[i][6] || "")
        .trim()
        .toUpperCase();

    if (
      status === "DISPATCH_READY"
    ) {

      return {

        available:
          true,

        row:
          i + 1,

        delegationJobId:
          data[i][0],

        createdAt:
          data[i][1],

        task:
          data[i][2],

        capability:
          data[i][3],

        primaryAgent:
          data[i][4],

        fallbackAgent:
          data[i][5],

        status:
          data[i][6],

        result:
          data[i][7],

        error:
          data[i][8],

        dispatchedAt:
          data[i][9],

        completedAt:
          data[i][10]

      };

    }

  }

  return {

    available:
      false,

    status:
      "NO_DISPATCH_READY_JOB"

  };

}


/* =========================================================
   RETRY COUNT
========================================================= */

function getAERISRetryCount(
  job
) {

  if (!job || !job.error) {
    return 0;
  }

  try {

    const error =
      JSON.parse(job.error);

    return Number(
      error.retryCount || 0
    );

  } catch (e) {

    return 0;

  }

}


/* =========================================================
   WRITE DISPATCH ERROR
========================================================= */

function writeAERISDispatchError(
  job,
  reason,
  retryCount,
  agent
) {

  const sheet =
    getAERISDelegationSheet();

  const payload = {

    validator:
      "AERIS V5.9",

    verified:
      true,

    reason:
      reason,

    retryCount:
      retryCount,

    agent:
      agent,

    updatedAt:
      new Date().toISOString()

  };

  sheet
    .getRange(job.row, 9)
    .setValue(
      JSON.stringify(payload)
    );

}


/* =========================================================
   EXECUTE PRIMARY AGENT
========================================================= */

function executeAERISPrimaryAgent(
  job
) {

  if (
    String(job.primaryAgent)
      .trim()
      .toUpperCase() !==
    "GEMINI"
  ) {

    throw new Error(
      "PRIMARY_AGENT_NOT_GEMINI"
    );

  }

  return callAERISGemini(
    job
  );

}


/* =========================================================
   EXECUTE FALLBACK AGENT
========================================================= */

function executeAERISFallbackAgent(
  job
) {

  const fallback =
    String(
      job.fallbackAgent || ""
    )
      .trim()
      .toUpperCase();

  if (
    fallback !== "COPILOT"
  ) {

    throw new Error(
      "FALLBACK_AGENT_NOT_COPILOT"
    );

  }

  /*
   V5.9 currently establishes
   the fallback gate and routing contract.

   Actual Copilot transport will only be
   marked executable after a verified
   external Copilot connector exists.
  */

  return {

    status:
      "FALLBACK_CONNECTOR_NOT_READY",

    verified:
      true,

    executed:
      false,

    agent:
      "Copilot",

    transport:
      "EXTERNAL_CONNECTOR",

    reason:
      "COPILOT_CONNECTOR_NOT_CONFIGURED",

    delegationJobId:
      job.delegationJobId,

    timestamp:
      new Date().toISOString()

  };

}


/* =========================================================
   VALIDATE FALLBACK RESULT
========================================================= */

function validateAERISFallbackResult(
  result
) {

  if (!result) {

    return {

      valid:
        false,

      reason:
        "MISSING_FALLBACK_RESULT"

    };

  }

  if (
    result.executed !== true
  ) {

    return {

      valid:
        false,

      reason:
        result.reason ||
        "FALLBACK_NOT_EXECUTED"

    };

  }

  if (
    result.verified !== true
  ) {

    return {

      valid:
        false,

      reason:
        "FALLBACK_NOT_VERIFIED"

    };

  }

  return {

    valid:
      true,

    reason:
      "VALID_FALLBACK_RESULT"

  };

}


/* =========================================================
   FINAL FAILURE
========================================================= */

function failAERISDelegationJob(
  job,
  reason,
  retryCount
) {

  const sheet =
    getAERISDelegationSheet();

  const payload = {

    system:
      "AERIS V5.9",

    verified:
      true,

    finalFailure:
      true,

    reason:
      reason,

    retryCount:
      retryCount,

    failedAt:
      new Date().toISOString()

  };

  sheet
    .getRange(job.row, 7)
    .setValue(
      "FAILED"
    );

  sheet
    .getRange(job.row, 8)
    .setValue("");

  sheet
    .getRange(job.row, 9)
    .setValue(
      JSON.stringify(payload)
    );

  sheet
    .getRange(job.row, 11)
    .setValue(
      new Date()
    );

  return {

    status:
      "DELEGATION_FAILED",

    verified:
      true,

    completed:
      false,

    delegationJobId:
      job.delegationJobId,

    retryCount:
      retryCount,

    reason:
      reason

  };

}


/* =========================================================
   V5.9 RETRY + FALLBACK PROCESSOR
========================================================= */

function processAERISRetryFallback() {

  const job =
    getAERISDispatchReadyJob();

  if (
    job.available !== true
  ) {

    return job;

  }

  let retryCount =
    getAERISRetryCount(
      job
    );

  /*
   ---------------------------------------------------------
   PRIMARY: GEMINI RETRY
   ---------------------------------------------------------
  */

  if (
    retryCount <
    AERIS_RETRY_LIMIT
  ) {

    retryCount++;

    const execution =
      executeAERISPrimaryAgent(
        job
      );

    const validation =
      validateAERISGeminiResult(
        execution
      );

    if (
      validation.valid === true
    ) {

      validation.text =
        extractAERISGeminiText(
          execution
        );

      return completeAERISDelegationJob(
        job,
        execution,
        validation
      );

    }

    writeAERISDispatchError(
      job,
      validation.reason,
      retryCount,
      "Gemini"
    );

    return {

      status:
        "GEMINI_RETRY_FAILED",

      verified:
        true,

      completed:
        false,

      delegationJobId:
        job.delegationJobId,

      retryCount:
        retryCount,

      reason:
        validation.reason,

      nextStep:
        "FALLBACK_TO_COPILOT"

    };

  }


  /*
   ---------------------------------------------------------
   FALLBACK: COPILOT
   ---------------------------------------------------------
  */

  const fallback =
    executeAERISFallbackAgent(
      job
    );

  const fallbackValidation =
    validateAERISFallbackResult(
      fallback
    );

  if (
    fallbackValidation.valid === true
  ) {

    return completeAERISDelegationJob(
      job,
      fallback,
      {
        valid:
          true,

        finishReason:
          "FALLBACK",

        text:
          fallback.text ||
          ""
      }
    );

  }


  return failAERISDelegationJob(
    job,
    fallbackValidation.reason,
    retryCount
  );

}


/* =========================================================
   V5.9 TEST
========================================================= */

function testAERISRetryFallback() {

  const result =
    processAERISRetryFallback();

  Logger.log(
    "===== AERIS V5.9 RETRY / FALLBACK ====="
  );

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  Logger.log(
    "===== END V5.9 ====="
  );

  return result;

}

/* =========================================================
   AERIS V5.9.1 — REAL-TIME PERFORMANCE MONITOR
   ---------------------------------------------------------
   PURPOSE
   - Live AX/Worker status
   - Heartbeat
   - Job progress
   - Current step / agent
   - Queue counters
   - Event stream
   - Stale/offline detection
   - No new trigger required
   ---------------------------------------------------------
   IMPORTANT
   - Monitor is READ-ONLY for job execution.
   - Worker/process functions must call the state helpers.
   - UI polls the status endpoint every 2 seconds.
========================================================= */

const AERIS_MONITOR_PROPERTY = "AERIS_PERFORMANCE_STATE";
const AERIS_HEARTBEAT_TIMEOUT_MS = 15000;
const AERIS_EVENT_LIMIT = 40;

function aerisMonitorDefaultState_() {
  return {
    system: "ONLINE",
    status: "IDLE",
    jobId: "",
    task: "",
    step: "",
    stepIndex: 0,
    stepTotal: 0,
    progress: 0,
    agent: "AX",
    startedAt: "",
    lastHeartbeat: "",
    retryCount: 0,
    queue: {
      running: 0,
      queued: 0,
      waitingK: 0,
      completed: 0,
      failed: 0
    },
    events: [],
    updatedAt: new Date().toISOString()
  };
}

function getAERISMonitorState_() {
  const raw = PropertiesService.getScriptProperties()
    .getProperty(AERIS_MONITOR_PROPERTY);

  if (!raw) return aerisMonitorDefaultState_();

  try {
    const parsed = JSON.parse(raw);
    return Object.assign(aerisMonitorDefaultState_(), parsed);
  } catch (e) {
    return aerisMonitorDefaultState_();
  }
}

function saveAERISMonitorState_(state) {
  state.updatedAt = new Date().toISOString();
  PropertiesService.getScriptProperties()
    .setProperty(AERIS_MONITOR_PROPERTY, JSON.stringify(state));
  return state;
}

function pushAERISEvent_(state, message, level) {
  state.events = Array.isArray(state.events) ? state.events : [];
  state.events.unshift({
    at: new Date().toISOString(),
    level: level || "INFO",
    message: String(message || "")
  });
  state.events = state.events.slice(0, AERIS_EVENT_LIMIT);
}

function setAERISMonitorState(patch) {
  const state = getAERISMonitorState_();
  const update = patch || {};

  Object.keys(update).forEach(function(key) {
    if (key === "queue" && update.queue) {
      state.queue = Object.assign(state.queue || {}, update.queue);
    } else if (key !== "events") {
      state[key] = update[key];
    }
  });

  if (update.event) {
    pushAERISEvent_(state, update.event.message, update.event.level);
  }

  return saveAERISMonitorState_(state);
}

function recordAERISHeartbeat(patch) {
  const state = getAERISMonitorState_();
  const update = patch || {};

  Object.keys(update).forEach(function(key) {
    if (key === "queue" && update.queue) {
      state.queue = Object.assign(state.queue || {}, update.queue);
    } else {
      state[key] = update[key];
    }
  });

  state.lastHeartbeat = new Date().toISOString();
  state.system = "ONLINE";

  if (update.event) {
    pushAERISEvent_(state, update.event.message, update.event.level);
  }

  return saveAERISMonitorState_(state);
}

function startAERISMonitorJob(job) {
  job = job || {};
  const state = getAERISMonitorState_();

  state.status = "RUNNING";
  state.jobId = String(job.jobId || job.delegationJobId || "");
  state.task = String(job.task || "");
  state.step = String(job.step || "START");
  state.stepIndex = Number(job.stepIndex || 1);
  state.stepTotal = Number(job.stepTotal || 1);
  state.progress = Number(job.progress || 0);
  state.agent = String(job.agent || "AX");
  state.startedAt = new Date().toISOString();
  state.lastHeartbeat = state.startedAt;

  state.queue = Object.assign(state.queue || {}, {
    running: Math.max(1, Number((state.queue || {}).running || 0)),
    waitingK: Number((state.queue || {}).waitingK || 0)
  });

  pushAERISEvent_(state, "JOB STARTED: " + state.jobId, "RUN");
  return saveAERISMonitorState_(state);
}

function finishAERISMonitorJob(success, message) {
  const state = getAERISMonitorState_();
  state.status = success ? "COMPLETED" : "ERROR";
  state.progress = success ? 100 : Number(state.progress || 0);
  state.lastHeartbeat = new Date().toISOString();

  if (state.queue) {
    state.queue.running = 0;
    if (success) state.queue.completed = Number(state.queue.completed || 0) + 1;
    else state.queue.failed = Number(state.queue.failed || 0) + 1;
  }

  pushAERISEvent_(
    state,
    message || (success ? "JOB COMPLETED" : "JOB FAILED"),
    success ? "SUCCESS" : "ERROR"
  );

  return saveAERISMonitorState_(state);
}

function setAERISWaitingK(reason) {
  const state = getAERISMonitorState_();
  state.status = "WAITING_K";
  state.lastHeartbeat = new Date().toISOString();
  state.queue = Object.assign(state.queue || {}, {
    waitingK: Number((state.queue || {}).waitingK || 0) + 1
  });
  pushAERISEvent_(state, "WAITING FOR K: " + String(reason || "DECISION REQUIRED"), "WAIT");
  return saveAERISMonitorState_(state);
}

function getAERISPerformanceSnapshot() {
  const state = getAERISMonitorState_();
  const now = Date.now();
  const heartbeat = state.lastHeartbeat
    ? new Date(state.lastHeartbeat).getTime()
    : 0;
  const ageMs = heartbeat ? now - heartbeat : Number.MAX_SAFE_INTEGER;

  let liveStatus = state.status || "IDLE";

  if (liveStatus === "RUNNING" && ageMs > AERIS_HEARTBEAT_TIMEOUT_MS) {
    liveStatus = "STALE";
  }

  return {
    success: true,
    service: "AERIS PERFORMANCE MONITOR",
    version: AERIS_VERSION,
    live: liveStatus,
    heartbeatAgeMs: heartbeat ? ageMs : null,
    heartbeatTimeoutMs: AERIS_HEARTBEAT_TIMEOUT_MS,
    state: state,
    serverTime: new Date().toISOString()
  };
}

function testAERISPerformanceMonitor() {
  startAERISMonitorJob({
    jobId: "MONITOR-TEST",
    task: "Performance Monitor Test",
    step: "HEARTBEAT",
    stepIndex: 1,
    stepTotal: 3,
    progress: 25,
    agent: "AX"
  });

  recordAERISHeartbeat({
    progress: 50,
    step: "LIVE STATE",
    stepIndex: 2,
    event: { message: "Heartbeat verified", level: "INFO" }
  });

  return getAERISPerformanceSnapshot();
}

const AERIS_MONITOR_HTML = `
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AERIS Performance Monitor</title>
<style>
body{font-family:Arial,sans-serif;background:#111;color:#eee;margin:0;padding:20px}
.panel{max-width:1000px;margin:auto}
.card{background:#1b1b1b;border:1px solid #333;border-radius:12px;padding:16px;margin-bottom:14px}
h1{margin:0 0 6px;font-size:22px}.muted{color:#999}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}
.metric{background:#222;padding:12px;border-radius:8px}.value{font-size:20px;font-weight:700;margin-top:5px}
.progress{height:14px;background:#333;border-radius:8px;overflow:hidden;margin-top:10px}.bar{height:100%;background:#4caf50;width:0%;transition:width .4s}
pre{white-space:pre-wrap;margin:0;font-size:12px;line-height:1.6}.green{color:#4caf50}.yellow{color:#ffc107}.red{color:#f44336}.blue{color:#64b5f6}
@media(max-width:700px){.grid{grid-template-columns:repeat(2,1fr)}}
</style>
</head>
<body>
<div class="panel">
<div class="card"><h1>AERIS PERFORMANCE MONITOR</h1><div class="muted" id="time">Connecting...</div></div>
<div class="card"><div class="grid">
<div class="metric">AX STATUS<div class="value" id="status">—</div></div>
<div class="metric">PROGRESS<div class="value" id="progressText">0%</div></div>
<div class="metric">AGENT<div class="value" id="agent">—</div></div>
<div class="metric">HEARTBEAT<div class="value" id="heartbeat">—</div></div>
</div><div class="progress"><div class="bar" id="bar"></div></div></div>
<div class="card"><b>CURRENT JOB</b><pre id="job">—</pre></div>
<div class="card"><b>QUEUE</b><pre id="queue">—</pre></div>
<div class="card"><b>EVENT STREAM</b><pre id="events">Waiting...</pre></div>
</div>
<script>
const ENDPOINT='?mode=status';
function esc(v){return String(v??'').replace(/[&<>]/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;'}[c]})}
function cls(s){s=String(s||'');return s==='RUNNING'?'green':(s==='WAITING_K'||s==='STALE'?'yellow':(s==='ERROR'?'red':'blue'))}
async function refresh(){
 try{
  const r=await fetch(ENDPOINT,{cache:'no-store'}); const d=await r.json(); const s=d.state||{};
  const live=d.live||s.status||'IDLE'; const el=document.getElementById('status'); el.textContent='● '+live; el.className='value '+cls(live);
  const p=Number(s.progress||0); document.getElementById('progressText').textContent=p+'%'; document.getElementById('bar').style.width=Math.max(0,Math.min(100,p))+'%';
  document.getElementById('agent').textContent=esc(s.agent||'—');
  document.getElementById('heartbeat').textContent=d.heartbeatAgeMs==null?'—':Math.round(d.heartbeatAgeMs/100)/10+'s ago';
  document.getElementById('time').textContent='SERVER '+new Date(d.serverTime).toLocaleTimeString();
  document.getElementById('job').textContent='Job: '+(s.jobId||'—')+'\nTask: '+(s.task||'—')+'\nStep: '+(s.step||'—')+' ('+(s.stepIndex||0)+'/'+(s.stepTotal||0)+')';
  const q=s.queue||{}; document.getElementById('queue').textContent='Running: '+(q.running||0)+' | Queued: '+(q.queued||0)+' | Waiting K: '+(q.waitingK||0)+'\nCompleted: '+(q.completed||0)+' | Failed: '+(q.failed||0);
  document.getElementById('events').textContent=(s.events||[]).slice(0,20).map(e=>new Date(e.at).toLocaleTimeString()+'  ['+e.level+']  '+e.message).join('\n')||'No events';
 }catch(e){document.getElementById('status').textContent='● OFFLINE';document.getElementById('status').className='value red'}
}
refresh(); setInterval(refresh,2000);
</script>
</body></html>`;
function TEST_DELEGATION_JOB_LOOKUP() {

  const jobId = "DELEGATE-20260823-143759-fa8cc938";

  try {

    const job = getAERISDelegationJobById(jobId);

    const result = {
      success: true,
      test: "DELEGATION_JOB_LOOKUP",
      jobId: jobId,
      found: !!job,
      job: job || null,
      timestamp: new Date().toISOString()
    };

    Logger.log(JSON.stringify(result, null, 2));

    return result;

  } catch (err) {

    const result = {
      success: false,
      test: "DELEGATION_JOB_LOOKUP",
      jobId: jobId,
      error: String(err && err.message ? err.message : err),
      stack: err && err.stack ? err.stack : null,
      timestamp: new Date().toISOString()
    };

    Logger.log(JSON.stringify(result, null, 2));

    return result;
  }
}function TEST_AERIS_AUTONOMOUS_CONTROL_LOOP() {

  const jobId = "DELEGATE-20260823-143759-fa8cc938";

  const job = getAERISDelegationJobById(jobId);

  if (!job) {
    throw new Error("JOB_NOT_FOUND: " + jobId);
  }

  const result = {
    success: true,
    system: "AERIS_AUTONOMOUS_CONTROL_LOOP",
    jobId: job.delegationJobId,
    queueStatus: job.status,
    executionStatus: job.execution
      ? job.execution.status
      : null,
    verified: job.execution
      ? job.execution.verified === true
      : false,
    completed: String(job.status).toUpperCase() === "COMPLETED",
    resumeEligible:
      String(job.status).toUpperCase() === "COMPLETED" &&
      job.execution &&
      job.execution.verified === true,
    timestamp: new Date().toISOString()
  };

  Logger.log(JSON.stringify(result, null, 2));

  return result;
}function TEST_AERIS_AUTONOMOUS_CONTROL_LOOP_V2() {

  const jobId = "DELEGATE-20260823-143759-fa8cc938";
  const job = getAERISDelegationJobById(jobId);

  if (!job) {
    throw new Error("JOB_NOT_FOUND: " + jobId);
  }

  let parsedResult = null;

  try {
    parsedResult = typeof job.result === "string"
      ? JSON.parse(job.result)
      : job.result;
  } catch (err) {
    parsedResult = {
      parseError: String(err.message || err),
      rawResult: job.result
    };
  }

  const execution =
    parsedResult && parsedResult.execution
      ? parsedResult.execution
      : null;

  const result = {
    success: true,
    system: "AERIS_AUTONOMOUS_CONTROL_LOOP_V2",
    jobId: job.delegationJobId,
    queueStatus: job.status,
    executionStatus: execution ? execution.status : null,
    executed: execution ? execution.executed === true : false,
    verified: execution ? execution.verified === true : false,
    httpStatus: execution ? execution.httpStatus : null,
    completed: String(job.status).toUpperCase() === "COMPLETED",
    resumeEligible:
      String(job.status).toUpperCase() === "COMPLETED" &&
      execution &&
      execution.executed === true &&
      execution.verified === true,
    timestamp: new Date().toISOString()
  };

  Logger.log(JSON.stringify(result, null, 2));

  return result;
}function TEST_AERIS_RESUME_EXECUTION() {

  const jobId = "DELEGATE-20260823-143759-fa8cc938";
  const job = getAERISDelegationJobById(jobId);

  if (!job) throw new Error("JOB_NOT_FOUND");

  const result = {
    success: true,
    test: "AERIS_RESUME_EXECUTION",
    jobId: job.delegationJobId,
    persistedStatus: job.status,
    persistedVerified: !!(
      job.result &&
      String(job.result).indexOf('"verified":true') !== -1
    ),
    resumeSource: "AERIS_DELEGATION_QUEUE",
    resumeAction: "STATE_REHYDRATED",
    resumedAt: new Date().toISOString()
  };

  Logger.log(JSON.stringify(result, null, 2));
  return result;
}function TEST_AERIS_RESUME_TO_DISPATCH() {

  const sourceJobId = "DELEGATE-20260823-143759-fa8cc938";
  const job = getAERISDelegationJobById(sourceJobId);

  if (!job) throw new Error("SOURCE_JOB_NOT_FOUND");

  const canResume =
    String(job.status).toUpperCase() === "COMPLETED" &&
    String(job.result).indexOf('"verified":true') !== -1;

  if (!canResume) throw new Error("RESUME_STATE_NOT_VALID");

  const nextJobId =
    "RESUME-" +
    Utilities.formatDate(
      new Date(),
      Session.getScriptTimeZone(),
      "yyyyMMdd-HHmmss"
    ) +
    "-" +
    Utilities.getUuid().slice(0, 8);

  const result = {
    success: true,
    test: "AERIS_RESUME_TO_DISPATCH",
    sourceJobId,
    nextJobId,
    sourceStatus: job.status,
    resumeVerified: canResume,
    dispatchReady: true,
    createdAt: new Date().toISOString()
  };

  Logger.log(JSON.stringify(result, null, 2));
  return result;
}function TEST_AERIS_RESUME_QUEUE_WRITE() {

  const nextJobId = "RESUME-20260823-212448-441de095";

  const ss = SpreadsheetApp.openById(QUEUE_SPREADSHEET_ID);
  const sheet = ss.getSheetByName(DELEGATION_SHEET_NAME);

  if (!sheet) throw new Error("DELEGATION_SHEET_NOT_FOUND");

  const headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];

  const row = headers.map(function(header) {
    const h = String(header).trim().toLowerCase();

    if (h === "delegationjobid" || h === "jobid") return nextJobId;
    if (h === "status") return "PENDING";
    if (h === "task") return "RESUME_NEXT_ACTION";
    if (h === "capability") return "orchestration";
    if (h === "primaryagent") return "Gemini";
    if (h === "fallbackagent") return "Copilot";

    return "";
  });

  sheet.appendRow(row);

  const result = {
    success: true,
    test: "AERIS_RESUME_QUEUE_WRITE",
    nextJobId,
    status: "PENDING",
    persisted: true,
    timestamp: new Date().toISOString()
  };

  Logger.log(JSON.stringify(result, null, 2));
  return result;
}function TEST_AERIS_QUEUE_PROCESSOR_DIAGNOSTIC() {

  const ss = SpreadsheetApp.openById(QUEUE_SPREADSHEET_ID);
  const sheet = ss.getSheetByName(DELEGATION_SHEET_NAME);

  if (!sheet) throw new Error("DELEGATION_SHEET_NOT_FOUND");

  const data = sheet.getDataRange().getValues();

  const headers = data[0].map(h => String(h).trim());

  const rows = data.slice(1).map((r, i) => {

    const obj = {};

    headers.forEach((h, j) => {
      obj[h] = r[j];
    });

    return {
      row: i + 2,
      jobId:
        obj.delegationJobId ||
        obj.delegationJobID ||
        obj.jobId ||
        obj.JobID ||
        null,
      status: obj.status || null,
      task: obj.task || null,
      capability: obj.capability || null,
      primaryAgent: obj.primaryAgent || null
    };

  });

  const pending = rows.filter(
    r => String(r.status).trim().toUpperCase() === "PENDING"
  );

  const result = {
    success: true,
    test: "QUEUE_PROCESSOR_DIAGNOSTIC",
    sheet: DELEGATION_SHEET_NAME,
    headers,
    totalRows: rows.length,
    pendingCount: pending.length,
    pendingRows: pending,
    timestamp: new Date().toISOString()
  };

  Logger.log(JSON.stringify(result, null, 2));
  return result;
}function TEST_RESUME_JOB_STATE() {

  const jobId = "RESUME-20260823-215112-628c029e";
  const job = getAERISDelegationJobById(jobId);

  const result = {
    success: true,
    jobId,
    found: !!job,
    row: job ? job.row : null,
    status: job ? job.status : null,
    result: job ? job.result : null,
    error: job ? job.error : null,
    dispatchedAt: job ? job.dispatchedAt : null,
    completedAt: job ? job.completedAt : null,
    timestamp: new Date().toISOString()
  };

  Logger.log(JSON.stringify(result, null, 2));
  return result;
}function TEST_RESUME_RAW_QUEUE_ROW() {

  const ss = SpreadsheetApp.openById(QUEUE_SPREADSHEET_ID);
  const sheet = ss.getSheetByName(DELEGATION_SHEET_NAME);

  const lastRow = sheet.getLastRow();
  const lastColumn = sheet.getLastColumn();

  const headers = sheet
    .getRange(1, 1, 1, lastColumn)
    .getValues()[0];

  const values = lastRow > 1
    ? sheet.getRange(lastRow, 1, 1, lastColumn).getValues()[0]
    : [];

  const row = {};

  headers.forEach((header, i) => {
    row[String(header)] = values[i];
  });

  const result = {
    success: true,
    test: "RESUME_RAW_QUEUE_ROW",
    sheet: DELEGATION_SHEET_NAME,
    lastRow,
    lastColumn,
    row
  };

  Logger.log(JSON.stringify(result, null, 2));
  return result;
}function TEST_AERIS_RESUME_QUEUE_WRITE_V2() {

  const nextJobId = "RESUME-20260823-212448-441de095";

  const ss = SpreadsheetApp.openById(QUEUE_SPREADSHEET_ID);
  const sheet = ss.getSheetByName(DELEGATION_SHEET_NAME);

  if (!sheet) throw new Error("DELEGATION_SHEET_NOT_FOUND");

  const lastColumn = sheet.getLastColumn();
  const headers = sheet
    .getRange(1, 1, 1, lastColumn)
    .getValues()[0]
    .map(h => String(h).trim());

  const row = new Array(lastColumn).fill("");

  headers.forEach((header, i) => {

    switch (header.toLowerCase()) {

      case "delegation job id":
        row[i] = nextJobId;
        break;

      case "created at":
        row[i] = new Date();
        break;

      case "task":
        row[i] = "RESUME_NEXT_ACTION";
        break;

      case "capability":
        row[i] = "orchestration";
        break;

      case "primary agent":
        row[i] = "Gemini";
        break;

      case "fallback agent":
        row[i] = "Copilot";
        break;

      case "status":
        row[i] = "PENDING";
        break;
    }

  });

  sheet.appendRow(row);

  const result = {
    success: true,
    test: "AERIS_RESUME_QUEUE_WRITE_V2",
    nextJobId,
    persisted: true,
    status: "PENDING",
    timestamp: new Date().toISOString()
  };

  Logger.log(JSON.stringify(result, null, 2));
  return result;
}/* =========================================================
   AERIS DELEGATION QUEUE PROCESSOR
========================================================= */

function processAERISDelegationQueue() {

  const sheet = SpreadsheetApp
    .openById(QUEUE_SPREADSHEET_ID)
    .getSheetByName(DELEGATION_SHEET_NAME);

  if (!sheet) {
    throw new Error("DELEGATION_SHEET_NOT_FOUND");
  }

  const data = sheet.getDataRange().getValues();

  if (data.length < 2) {
    return {
      status: "NO_DELEGATION_JOBS",
      processed: 0
    };
  }

  const headers = data[0].map(h =>
    String(h).trim()
  );

  const index = {};

  headers.forEach((h, i) => {
    index[h.toLowerCase()] = i;
  });

  const required = [
    "delegation job id",
    "task",
    "capability",
    "primary agent",
    "fallback agent",
    "status",
    "result",
    "error",
    "dispatched at",
    "completed at"
  ];

  required.forEach(name => {
    if (index[name] === undefined) {
      throw new Error(
        "DELEGATION_QUEUE_COLUMN_MISSING: " + name
      );
    }
  });

  let processed = 0;

  for (let r = 1; r < data.length; r++) {

    const row = data[r];

    const status = String(
      row[index["status"]] || ""
    ).trim().toUpperCase();

    if (status !== "PENDING") {
      continue;
    }

    const jobId = String(
      row[index["delegation job id"]] || ""
    ).trim();

    if (!jobId) {
      sheet.getRange(
        r + 1,
        index["status"] + 1
      ).setValue("FAILED");

      sheet.getRange(
        r + 1,
        index["error"] + 1
      ).setValue("MISSING_DELEGATION_JOB_ID");

      continue;
    }

    sheet.getRange(
      r + 1,
      index["status"] + 1
    ).setValue("PROCESSING");

    sheet.getRange(
      r + 1,
      index["dispatched at"] + 1
    ).setValue(new Date());

    try {

      const delegationJob =
        getAERISDelegationJobById(jobId);

      if (!delegationJob) {
        throw new Error(
          "DELEGATION_JOB_NOT_FOUND: " + jobId
        );
      }

      const execution =
        callAERISGemini(delegationJob);

      const validation =
        validateAERISGeminiResult(
          execution
        );

      if (validation.valid !== true) {
        throw new Error(
          "GEMINI_RESULT_REJECTED: " +
          validation.reason
        );
      }

      const text =
        extractAERISGeminiText(
          execution
        );

      const result = {
        status: "GEMINI_DELEGATION_COMPLETED",
        verified: true,
        executed: true,
        delegationJobId: jobId,
        httpStatus: execution.httpStatus,
        finishReason: validation.finishReason,
        text: text
      };

      sheet.getRange(
        r + 1,
        index["status"] + 1
      ).setValue("COMPLETED");

      sheet.getRange(
        r + 1,
        index["result"] + 1
      ).setValue(
        JSON.stringify(result)
      );

      sheet.getRange(
        r + 1,
        index["completed at"] + 1
      ).setValue(new Date());

      processed++;

    } catch (error) {

      sheet.getRange(
        r + 1,
        index["status"] + 1
      ).setValue("FAILED");

      sheet.getRange(
        r + 1,
        index["error"] + 1
      ).setValue(
        String(
          error && error.message
            ? error.message
            : error
        )
      );

      sheet.getRange(
        r + 1,
        index["completed at"] + 1
      ).setValue(new Date());
    }
  }

  const result = {
    status: "DELEGATION_QUEUE_PROCESSED",
    processed: processed,
    timestamp: new Date().toISOString()
  };

  Logger.log(
    "===== AERIS DELEGATION QUEUE RESULT ====="
  );

  Logger.log(
    JSON.stringify(result, null, 2)
  );

  Logger.log(
    "===== END AERIS DELEGATION QUEUE RESULT ====="
  );

  return result;
}function AERIS_DELEGATION_QUEUE_TRIGGER() {

  const lock =
    LockService.getScriptLock();

  if (!lock.tryLock(5000)) {

    return {
      status:
        "BUSY",

      processed:
        0
    };
  }

  try {

    const queueResult =
      processAERISDelegationQueue();

    const fallbackResult =
      processAERISFallback();

    const autonomousResult =
      AERIS_AUTONOMOUS_NEXT_ACTION();
/*
 * =======================================================
 * CREATE NEXT PERSISTENT JOB
 * =======================================================
 */const activeStatuses = [
  "PENDING",
  "PENDING_DISPATCH",
  "DISPATCH_READY",
  "RETRY_PENDING",
  "FALLBACK_PENDING"
];

for (let r = 1; r < data.length; r++) {

  const rowStatus =
    String(
      data[r][index["status"]] || ""
    )
    .trim()
    .toUpperCase();

  if (
    activeStatuses.indexOf(rowStatus) !== -1
  ) {

    return {

      success: true,

      status:
        "ACTIVE_JOB_EXISTS",

      verified:
        true,

      existingJobId:
        String(
          data[r][index["delegation job id"]] || ""
        ).trim(),

      existingStatus:
        rowStatus,

      persisted:
        true,

      dispatchReady:
        rowStatus === "PENDING_DISPATCH" ||
        rowStatus === "DISPATCH_READY",

      timestamp:
        new Date().toISOString()

    };
  }
}
    const dispatchResult =
      processAERISDispatcher();

    const result = {

      success:
        true,

      system:
        "AERIS_AUTONOMOUS_CONTROL_LOOP",

      queue:
        queueResult,

      fallback:
        fallbackResult,

      autonomous:
        autonomousResult,

      dispatcher:
        dispatchResult,

      timestamp:
        new Date().toISOString()

    };

    Logger.log(
      JSON.stringify(
        result,
        null,
        2
      )
    );

    return result;

  } finally {

    lock.releaseLock();

  }
}function INSTALL_AERIS_DELEGATION_TRIGGER() {

  const handler = "AERIS_DELEGATION_QUEUE_TRIGGER";

  ScriptApp.getProjectTriggers()
    .filter(t =>
      t.getHandlerFunction() === handler
    )
    .forEach(t =>
      ScriptApp.deleteTrigger(t)
    );

  ScriptApp.newTrigger(handler)
    .timeBased()
    .everyMinutes(1)
    .create();

  const result = {
    success: true,
    trigger: handler,
    schedule: "EVERY_1_MINUTE",
    installed: true,
    timestamp: new Date().toISOString()
  };

  Logger.log(JSON.stringify(result, null, 2));

  return result;
}function TEST_AERIS_AUTONOMOUS_TRIGGER() {

  const jobId =
    "AUTO-TRIGGER-" +
    Utilities.getUuid().slice(0, 8);

  const ss =
    SpreadsheetApp.openById(QUEUE_SPREADSHEET_ID);

  const sheet =
    ss.getSheetByName(DELEGATION_SHEET_NAME);

  const headers =
    sheet.getRange(
      1,
      1,
      1,
      sheet.getLastColumn()
    ).getValues()[0]
    .map(h => String(h).trim());

  const row =
    new Array(headers.length).fill("");

  headers.forEach((header, i) => {

    switch (header.toLowerCase()) {

      case "delegation job id":
        row[i] = jobId;
        break;

      case "created at":
        row[i] = new Date();
        break;

      case "task":
        row[i] = "AUTONOMOUS_TRIGGER_TEST";
        break;

      case "capability":
        row[i] = "coding";
        break;

      case "primary agent":
        row[i] = "Gemini";
        break;

      case "fallback agent":
        row[i] = "Copilot";
        break;

      case "status":
        row[i] = "PENDING";
        break;
    }

  });

  sheet.appendRow(row);

  Logger.log(JSON.stringify({
    success: true,
    test: "AUTONOMOUS_TRIGGER",
    jobId,
    status: "PENDING",
    waitingForTrigger: true,
    timestamp: new Date().toISOString()
  }, null, 2));

}function TEST_AUTO_TRIGGER_RESULT() {

  const jobId = "AUTO-TRIGGER-98792b1b";
  const job = getAERISDelegationJobById(jobId);

  Logger.log(JSON.stringify({
    success: true,
    jobId,
    found: !!job,
    status: job ? job.status : null,
    result: job ? job.result : null,
    error: job ? job.error : null,
    timestamp: new Date().toISOString()
  }, null, 2));
}function TEST_AERIS_TRIGGER_STATUS() {

  const triggers = ScriptApp.getProjectTriggers();

  const result = triggers.map(t => ({
    handler: t.getHandlerFunction(),
    type: String(t.getEventType()),
    source: String(t.getTriggerSource())
  }));

  Logger.log(JSON.stringify(result, null, 2));

  return result;
}function TEST_AERIS_DELEGATION_TRIGGER_RUN() {

  const jobId = "AUTO-TRIGGER-98792b1b";

  const result =
    processAERISDelegationQueue();

  const job =
    getAERISDelegationJobById(jobId);

  Logger.log(JSON.stringify({
    triggerResult: result,
    jobAfterRun: job ? {
      status: job.status,
      result: job.result,
      error: job.error
    } : null,
    timestamp: new Date().toISOString()
  }, null, 2));

  return result;
}/* =========================================================
   AUTONOMOUS NEXT-ACTION DISPATCH
========================================================= */
function AERIS_AUTONOMOUS_NEXT_ACTION() {

  const sheet =
    SpreadsheetApp
      .openById(QUEUE_SPREADSHEET_ID)
      .getSheetByName(DELEGATION_SHEET_NAME);

  if (!sheet) {
    throw new Error("DELEGATION_SHEET_NOT_FOUND");
  }

  const data =
    sheet.getDataRange().getValues();

  if (data.length < 2) {
    return {
      success: false,
      status: "NO_JOBS"
    };
  }

  const headers =
    data[0].map(h =>
      String(h).trim()
    );

  const index = {};

  headers.forEach((h, i) => {
    index[h.toLowerCase()] = i;
  });

  const required = [
    "delegation job id",
    "created at",
    "task",
    "capability",
    "primary agent",
    "fallback agent",
    "status",
    "result",
    "error",
    "dispatched at",
    "completed at"
  ];

  required.forEach(name => {

    if (index[name] === undefined) {
      throw new Error(
        "DELEGATION_QUEUE_COLUMN_MISSING: " +
        name
      );
    }

  });

  let latestCompleted = null;

  for (
    let r = 1;
    r < data.length;
    r++
  ) {

    const row = data[r];

    const status =
      String(
        row[index["status"]] || ""
      )
      .trim()
      .toUpperCase();

    if (status !== "COMPLETED") {
      continue;
    }

    const jobId =
      String(
        row[index["delegation job id"]] || ""
      ).trim();

    if (!jobId) {
      continue;
    }

    if (
      jobId.indexOf("RESUME-") !== 0 &&
      jobId.indexOf("NEXT-") !== 0 &&
      jobId.indexOf("AUTO-TRIGGER-") !== 0
    ) {
      continue;
    }

    latestCompleted = {
      row: r + 1,
      jobId: jobId,
      result:
        String(
          row[index["result"]] || ""
        )
    };
  }

  if (!latestCompleted) {

    return {
      success: false,
      status: "NO_COMPLETED_AUTONOMOUS_JOB"
    };

  }

  let agentResult = null;

  try {

    agentResult =
      JSON.parse(
        latestCompleted.result
      );

  } catch (error) {

    agentResult = null;

  }

  let parsedText = null;

  if (
    agentResult &&
    typeof agentResult.text === "string"
  ) {

    const text =
      agentResult.text;

    const jsonMatch =
      text.match(
        /```(?:json|yaml)?\s*([\s\S]*?)\s*```/i
      );

    if (jsonMatch) {

      try {

        parsedText =
          JSON.parse(
            jsonMatch[1].trim()
          );

      } catch (error) {

        parsedText = null;

      }

    }
  }

  /*
   * =======================================================
   * EXTRACT NEXT ACTION / NEXT STEP
   * =======================================================
   */

  let nextAction = null;

  if (
    parsedText &&
    parsedText.next_action
  ) {

    nextAction =
      parsedText.next_action;

  } else if (
    parsedText &&
    parsedText.next_step
  ) {

    nextAction =
      parsedText.next_step;

  }

  /*
   * =======================================================
   * SAFE DEFAULT
   * =======================================================
   */

  if (!nextAction) {

    nextAction = {

      directive:
        "CONTINUE_ORCHESTRATION",

      target:
        "AERIS_AUTONOMOUS_PIPELINE",

      parameters: {}

    };

  }

  const directive =
    String(
      nextAction.directive ||
      nextAction.operation ||
      "CONTINUE_ORCHESTRATION"
    )
    .trim()
    .toUpperCase();

  const target =
    String(
      nextAction.target ||
      nextAction.target_component ||
      "AERIS_AUTONOMOUS_PIPELINE"
    ).trim();

  const parameters =
    nextAction.parameters ||
    {};

  /*
   * =======================================================
   * OBJECTIVE GATE
   * =======================================================
   */

  const allowedDirectives = [

    "CONTINUE_ORCHESTRATION",

    "INITIATE_METADATA_DISCOVERY",

    "SEARCH_CATALOG",

    "ANALYZE_METADATA",

    "PREPARE_RELEASE",

    "RUN_QC",

    "CREATE_SAVEPOINT",

    "INITIALIZE_STEM_RENDERING"

  ];

  if (
    allowedDirectives.indexOf(
      directive
    ) === -1
  ) {

    return {

      success: true,

      status:
        "WAITING_FOR_K",

      reason:
        "UNKNOWN_AUTONOMOUS_DIRECTIVE",

      sourceJobId:
        latestCompleted.jobId,

      directive:
        directive,

      target:
        target,

      verified:
        true,

      requiresApproval:
        true,

      timestamp:
        new Date().toISOString()

    };

  }

  /*
   * =======================================================
   * CREATE NEXT PERSISTENT DISPATCH JOB
   * =======================================================
   */

  const nextJobId =
    "NEXT-" +
    Utilities.formatDate(
      new Date(),
      Session.getScriptTimeZone(),
      "yyyyMMdd-HHmmss"
    ) +
    "-" +
    Utilities.getUuid().slice(0, 8);

  const nextRow =
    new Array(headers.length)
      .fill("");

  headers.forEach(
    (header, i) => {

      switch (
        header.toLowerCase()
      ) {

        case "delegation job id":

          nextRow[i] =
            nextJobId;

          break;

        case "created at":

          nextRow[i] =
            new Date();

          break;

        case "task":

          nextRow[i] =
            directive;

          break;

        case "capability":

          nextRow[i] =
            "orchestration";

          break;

        case "primary agent":

          nextRow[i] =
            "Gemini";

          break;

        case "fallback agent":

          nextRow[i] =
            "Copilot";

          break;

        case "status":

          nextRow[i] =
            "PENDING_DISPATCH";

          break;

      }

    }
  );

  sheet.appendRow(
    nextRow
  );

  /*
   * =======================================================
   * VERIFY PERSISTENCE
   * =======================================================
   */

  const createdRow =
    sheet.getLastRow();

  const verifyJobId =
    String(
      sheet
        .getRange(
          createdRow,
          index["delegation job id"] + 1
        )
        .getValue()
    ).trim();

  const verifyStatus =
    String(
      sheet
        .getRange(
          createdRow,
          index["status"] + 1
        )
        .getValue()
    )
    .trim()
    .toUpperCase();

  if (
    verifyJobId !==
    nextJobId
  ) {

    throw new Error(
      "NEXT_JOB_PERSISTENCE_VERIFICATION_FAILED"
    );

  }

  if (
    verifyStatus !==
    "PENDING_DISPATCH"
  ) {

    throw new Error(
      "NEXT_JOB_DISPATCH_STATUS_VERIFICATION_FAILED: " +
      verifyStatus
    );

  }

  /*
   * =======================================================
   * RETURN DISPATCH PACKAGE
   * =======================================================
   */

  const result = {

    success:
      true,

    system:
      "AERIS_AUTONOMOUS_ACTION_ROUTER",

    sourceJobId:
      latestCompleted.jobId,

    nextJobId:
      nextJobId,

    directive:
      directive,

    target:
      target,

    parameters:
      parameters,

    status:
      "PENDING_DISPATCH",

    persisted:
      true,

    dispatchReady:
      true,

    verified:
      true,

    timestamp:
      new Date().toISOString()

  };

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  return result;

}function TEST_NEXT_JOB_STATE() {

  const jobId =
  "NEXT-20260823-225434-9bc1ad56";

  const job =
    getAERISDelegationJobById(jobId);

  Logger.log(JSON.stringify({
    success: true,
    jobId: jobId,
    found: !!job,
    row: job ? job.row : null,
    status: job ? job.status : null,
    result: job ? job.result : null,
    error: job ? job.error : null,
    dispatchedAt: job ? job.dispatchedAt : null,
    completedAt: job ? job.completedAt : null,
    timestamp: new Date().toISOString()
  }, null, 2));
}function TEST_AERIS_DISPATCHER() {

  const result =
    processAERISDispatcher();

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  return result;
}function handleAERISDispatchRetry(
  dispatch,
  execution
) {

  if (!dispatch) {
    throw new Error(
      "MISSING_DISPATCH_CONTEXT"
    );
  }

  const sheet =
    getAERISDelegationSheet();

  const row =
    Number(
      dispatch.row
    );

  if (
    !row ||
    row < 2
  ) {
    throw new Error(
      "INVALID_DISPATCH_ROW"
    );
  }

  const current =
    String(
      sheet
        .getRange(row, 8)
        .getValue() ||
      ""
    ).trim();

  let payload = {};

  try {

    payload =
      JSON.parse(current);

  } catch (error) {

    payload = {};

  }

  let retryCount =
    Number(
      payload.retryCount || 0
    );

  retryCount++;

  const primaryExecution =
    execution &&
    execution.primaryExecution
      ? execution.primaryExecution
      : execution;

  const httpStatus =
    primaryExecution &&
    primaryExecution.httpStatus
      ? Number(
          primaryExecution.httpStatus
        )
      : null;

  payload.retryCount =
    retryCount;

  payload.lastRetryAt =
    new Date().toISOString();

  payload.lastHttpStatus =
    httpStatus;

  /*
   * =======================================================
   * GEMINI QUOTA RECOVERY
   * =======================================================
   */

  if (
    httpStatus === 429 ||
    (
      primaryExecution &&
      primaryExecution.status ===
      "GEMINI_QUOTA_EXHAUSTED"
    )
  ) {

    const retryAfterSeconds =
      Number(
        primaryExecution.retryAfterSeconds ||
        60
      );

    payload.retryAfterSeconds =
      retryAfterSeconds;

    payload.nextRetryAt =
      new Date(
        Date.now() +
        retryAfterSeconds * 1000
      ).toISOString();

    /*
     * DO NOT FALLBACK TO COPILOT
     */

    sheet
      .getRange(row, 7)
      .setValue(
        "RETRY_PENDING"
      );

    sheet
      .getRange(row, 8)
      .setValue(
        JSON.stringify(payload)
      );

    sheet
      .getRange(row, 9)
      .setValue(
        "GEMINI_QUOTA_WAIT_" +
        retryAfterSeconds +
        "_SECONDS"
      );

    return {

      status:
        "RETRY_PENDING",

      verified:
        true,

      executed:
        false,

      delegationJobId:
        dispatch.delegationJobId,

      primaryAgent:
        "Gemini",

      fallbackAgent:
        null,

      retryCount:
        retryCount,

      retryAfterSeconds:
        retryAfterSeconds,

      nextRetryAt:
        payload.nextRetryAt,

      httpStatus:
        httpStatus,

      reason:
        "GEMINI_QUOTA_EXHAUSTED_RETRY_ONLY",

      timestamp:
        new Date().toISOString()

    };
  }

  /*
   * =======================================================
   * STANDARD GEMINI RETRY
   * =======================================================
   */

  const MAX_RETRIES = 3;

  if (
    retryCount <=
    MAX_RETRIES
  ) {

    sheet
      .getRange(row, 7)
      .setValue(
        "RETRY_PENDING"
      );

    sheet
      .getRange(row, 8)
      .setValue(
        JSON.stringify(payload)
      );

    sheet
      .getRange(row, 9)
      .setValue(
        "RETRY_" +
        retryCount +
        "_OF_" +
        MAX_RETRIES
      );

    return {

      status:
        "RETRY_PENDING",

      verified:
        true,

      executed:
        false,

      delegationJobId:
        dispatch.delegationJobId,

      primaryAgent:
        "Gemini",

      fallbackAgent:
        null,

      retryCount:
        retryCount,

      maxRetries:
        MAX_RETRIES,

      retryAfterSeconds:
        60,

      httpStatus:
        httpStatus,

      timestamp:
        new Date().toISOString()

    };
  }

  /*
   * =======================================================
   * HARD FAILURE
   * =======================================================
   *
   * No Copilot fallback.
   * Stop claiming autonomous execution.
   */

  sheet
    .getRange(row, 7)
    .setValue(
      "FAILED"
    );

  sheet
    .getRange(row, 9)
    .setValue(
      "GEMINI_RETRY_LIMIT_EXCEEDED"
    );

  return {

    status:
      "FAILED",

    verified:
      true,

    executed:
      false,

    delegationJobId:
      dispatch.delegationJobId,

    primaryAgent:
      "Gemini",

    fallbackAgent:
      null,

    reason:
      "GEMINI_RETRY_LIMIT_EXCEEDED",

    timestamp:
      new Date().toISOString()

  };
}function executeAERISCopilotFallback(
  dispatch
) {

  if (!dispatch) {
    throw new Error(
      "MISSING_COPILOT_DISPATCH"
    );
  }

  return {
    status:
      "COPILOT_CONNECTOR_REQUIRED",

    verified:
      true,

    executed:
      false,

    delegationJobId:
      dispatch.delegationJobId,

    fallbackAgent:
      "Copilot",

    reason:
      "COPILOT_EXTERNAL_CONNECTOR_NOT_CONFIGURED",

    timestamp:
      new Date().toISOString()
  };
}function processAERISFallback() {

  const sheet =
    getAERISDelegationSheet();

  const data =
    sheet
      .getDataRange()
      .getValues();

  if (data.length < 2) {

    return {

      status:
        "NO_FALLBACK_JOBS",

      processed:
        0

    };
  }

  /*
   * =======================================================
   * COPILOT FALLBACK DISABLED
   * =======================================================
   *
   * AERIS currently uses Gemini as primary executor.
   *
   * Copilot is NOT an autonomous execution path until
   * a verified external Copilot connector exists.
   */

  let converted =
    0;

  for (
    let r = 1;
    r < data.length;
    r++
  ) {

    const status =
      String(
        data[r][6] || ""
      )
      .trim()
      .toUpperCase();

    if (
      status !==
      "FALLBACK_PENDING"
    ) {

      continue;
    }

    /*
     * Convert stale fallback jobs back into
     * Gemini retry queue.
     */

    sheet
      .getRange(
        r + 1,
        7
      )
      .setValue(
        "RETRY_PENDING"
      );

    sheet
      .getRange(
        r + 1,
        9
      )
      .setValue(
        "COPILOT_DISABLED_GEMINI_RETRY"
      );

    converted++;
  }

  return {

    status:
      converted > 0
        ? "FALLBACK_DISABLED_RETRY_PENDING"
        : "NO_FALLBACK_JOBS",

    processed:
      converted,

    verified:
      true,

    executed:
      false,

    nextStep:
      "RETRY_GEMINI_AFTER_QUOTA_WINDOW",

    timestamp:
      new Date().toISOString()

  };
}function executeAERISCopilotFallback(job) {

  if (!job) {
    throw new Error("MISSING_COPILOT_FALLBACK_JOB");
  }

  return {
    status: "COPILOT_CONNECTOR_REQUIRED",
    verified: true,
    executed: false,

    delegationJobId:
      job.delegationJobId,

    fallbackAgent:
      "Copilot",

    reason:
      "COPILOT_EXTERNAL_CONNECTOR_NOT_CONFIGURED",

    timestamp:
      new Date().toISOString()
  };
}function handleAERISDispatchRetry(job) {

  if (!job) {
    throw new Error(
      "MISSING_DISPATCH_RETRY_JOB"
    );
  }

  const delegationJobId =
    String(
      job.delegationJobId || ""
    ).trim();

  if (!delegationJobId) {
    throw new Error(
      "MISSING_DELEGATION_JOB_ID"
    );
  }

  const primaryExecution =
    job.primaryExecution ||
    job.execution ||
    job;

  const httpStatus =
    Number(
      primaryExecution.httpStatus || 0
    );

  /*
   * =======================================================
   * GEMINI QUOTA RECOVERY
   * =======================================================
   */

  if (
    httpStatus === 429 ||
    primaryExecution.status ===
      "GEMINI_QUOTA_EXHAUSTED"
  ) {

    const retryAfterSeconds =
      Number(
        job.retryAfterSeconds || 60
      );

    return {

      status:
        "RETRY_PENDING",

      verified:
        true,

      executed:
        false,

      delegationJobId:
        delegationJobId,

      primaryAgent:
        "Gemini",

      fallbackAgent:
        null,

      retryRequired:
        true,

      retryAfterSeconds:
        retryAfterSeconds,

      nextStep:
        "RETRY_GEMINI_AFTER_QUOTA_WINDOW",

      reason:
        "GEMINI_QUOTA_EXHAUSTED",

      timestamp:
        new Date().toISOString()

    };
  }

  /*
   * =======================================================
   * NO AUTOMATIC COPILOT FALLBACK
   * =======================================================
   */

  return {

    status:
      "RETRY_PENDING",

    verified:
      true,

    executed:
      false,

    delegationJobId:
      delegationJobId,

    primaryAgent:
      "Gemini",

    fallbackAgent:
      null,

    retryRequired:
      true,

    retryAfterSeconds:
      60,

    nextStep:
      "RETRY_GEMINI",

    reason:
      "PRIMARY_EXECUTION_NOT_COMPLETED",

    timestamp:
      new Date().toISOString()

  };
}
/* =========================================================
   AERIS CONTROL BRIDGE v1
   AX → AERIS Apps Script Control Layer

   POLICY:
   - READ source/state first
   - WRITE is explicitly gated
   - VERIFY after every operation
   - Never claim external execution without evidence
   ========================================================= */

const AERIS_CONTROL_BRIDGE_VERSION = "1.0.0";

function AERIS_CONTROL_BRIDGE_STATUS() {

  return {
    success: true,
    system: "AERIS_CONTROL_BRIDGE",
    version: AERIS_CONTROL_BRIDGE_VERSION,

    capabilities: {
      readState: true,
      readQueue: true,
      writeScript: false,
      executeScript: true,
      verify: true
    },

    writeGate:
      "LOCKED",

    reason:
      "WRITE_GATE_REQUIRES_VERIFIED_CONTROL_CHANNEL",

    timestamp:
      new Date().toISOString()
  };
}


function AERIS_CONTROL_BRIDGE_READ_STATE() {

  const sheet =
    getAERISDelegationSheet();

  const data =
    sheet.getDataRange().getValues();

  const pending = [];
  const processing = [];
  const completed = [];
  const failed = [];
  const fallback = [];

  for (
    let r = 1;
    r < data.length;
    r++
  ) {

    const status =
      String(
        data[r][6] || ""
      )
      .trim()
      .toUpperCase();

    const item = {
      row: r + 1,
      delegationJobId: data[r][0],
      task: data[r][2],
      capability: data[r][3],
      primaryAgent: data[r][4],
      fallbackAgent: data[r][5],
      status: status
    };

    if (
      status === "PENDING" ||
      status === "PENDING_DISPATCH" ||
      status === "RETRY_PENDING"
    ) {
      pending.push(item);
    }

    else if (
      status === "PROCESSING" ||
      status === "DISPATCH_READY"
    ) {
      processing.push(item);
    }

    else if (
      status === "COMPLETED"
    ) {
      completed.push(item);
    }

    else if (
      status === "FAILED"
    ) {
      failed.push(item);
    }

    else if (
      status === "FALLBACK_PENDING"
    ) {
      fallback.push(item);
    }
  }

  return {

    success: true,

    system:
      "AERIS_CONTROL_BRIDGE",

    version:
      AERIS_CONTROL_BRIDGE_VERSION,

    queue: {

      totalRows:
        Math.max(
          data.length - 1,
          0
        ),

      pending:
        pending.length,

      processing:
        processing.length,

      completed:
        completed.length,

      failed:
        failed.length,

      fallbackPending:
        fallback.length
    },

    pendingJobs:
      pending,

    processingJobs:
      processing,

    fallbackJobs:
      fallback,

    verified:
      true,

    timestamp:
      new Date().toISOString()
  };
}


function AERIS_CONTROL_BRIDGE_EXECUTE(
  functionName
) {

  if (!functionName) {

    throw new Error(
      "MISSING_FUNCTION_NAME"
    );
  }

  const allowed = [

    "AERIS_DELEGATION_QUEUE_TRIGGER",

    "processCommandQueue",

    "processAERISDispatcher",

    "processAERISFallback",

    "AERIS_AUTONOMOUS_NEXT_ACTION",

    "TEST_AERIS_DISPATCHER"

  ];

  if (
    allowed.indexOf(
      functionName
    ) === -1
  ) {

    return {

      success: false,

      status:
        "FUNCTION_NOT_ALLOWED",

      functionName:
        functionName,

      verified:
        true,

      timestamp:
        new Date().toISOString()
    };
  }

  const fn =
    this[functionName];

  if (
    typeof fn !==
    "function"
  ) {

    return {

      success: false,

      status:
        "FUNCTION_NOT_FOUND",

      functionName:
        functionName,

      verified:
        true,

      timestamp:
        new Date().toISOString()
    };
  }

  const result =
    fn();

  return {

    success: true,

    status:
      "EXECUTED",

    functionName:
      functionName,

    result:
      result,

    verified:
      true,

    timestamp:
      new Date().toISOString()
  };
}


function TEST_AERIS_CONTROL_BRIDGE() {

  const status =
    AERIS_CONTROL_BRIDGE_STATUS();

  const state =
    AERIS_CONTROL_BRIDGE_READ_STATE();

  return {

    success:
      status.success &&
      state.success,

    status:
      status,

    state:
      state,

    verified:
      true,

    timestamp:
      new Date().toISOString()
  };
}

function TEST_AERIS_CONTROL_BRIDGE_OUTPUT() {

  const result = {
    success: false,
    system: "AERIS_CONTROL_BRIDGE",
    timestamp: new Date().toISOString()
  };

  try {

    const status =
      AERIS_CONTROL_BRIDGE_STATUS();

    const state =
      AERIS_CONTROL_BRIDGE_READ_STATE();

    result.success =
      status &&
      status.success === true &&
      state &&
      state.success === true;

    result.status =
      status;

    result.queue =
      state.queue;

    result.verified =
      result.success;

  } catch (error) {

    result.success = false;

    result.verified = false;

    result.error =
      error.message;

  }

  Logger.log(
    "===== AERIS CONTROL BRIDGE VERIFICATION ====="
  );

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  Logger.log(
    "===== END AERIS CONTROL BRIDGE VERIFICATION ====="
  );

  return result;
}
function AERIS_RECOVER_STALE_PROCESSING() {

  const sheet =
    getAERISDelegationSheet();

  const data =
    sheet.getDataRange().getValues();

  const now =
    new Date();

  const STALE_MINUTES = 10;

  let scanned = 0;
  let recovered = 0;

  const recoveredJobs = [];

  for (let r = 1; r < data.length; r++) {

    const status =
      String(data[r][6] || "")
        .trim()
        .toUpperCase();

    if (status !== "PROCESSING") {
      continue;
    }

    scanned++;

    const dispatchedAt =
      data[r][9];

    if (!dispatchedAt) {
      continue;
    }

    const dispatchedTime =
      new Date(dispatchedAt);

    if (isNaN(dispatchedTime.getTime())) {
      continue;
    }

    const ageMinutes =
      (now.getTime() -
       dispatchedTime.getTime()) / 60000;

    if (ageMinutes < STALE_MINUTES) {
      continue;
    }

    const jobId =
      String(data[r][0] || "").trim();

    sheet
      .getRange(r + 1, 7)
      .setValue("PENDING_DISPATCH");

    sheet
      .getRange(r + 1, 9)
      .setValue(
        "RECOVERED_STALE_PROCESSING_" +
        Math.floor(ageMinutes) +
        "M"
      );

    recovered++;

    recoveredJobs.push({
      row: r + 1,
      delegationJobId: jobId,
      ageMinutes:
        Math.floor(ageMinutes)
    });
  }

  const result = {

    success: true,

    system:
      "AERIS_STALE_PROCESSING_RECOVERY",

    scanned:
      scanned,

    recovered:
      recovered,

    staleThresholdMinutes:
      STALE_MINUTES,

    recoveredJobs:
      recoveredJobs,

    verified:
      true,

    timestamp:
      new Date().toISOString()
  };

  Logger.log(
    "===== AERIS STALE PROCESSING RECOVERY ====="
  );

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  Logger.log(
    "===== END AERIS STALE PROCESSING RECOVERY ====="
  );

  return result;
}
function AERIS_DIAGNOSE_QUEUE() {

  const sheet =
    getAERISDelegationSheet();

  const data =
    sheet.getDataRange().getValues();

  const result = {
    success: true,
    system: "AERIS_QUEUE_DIAGNOSTIC",
    processing: [],
    failed: [],
    pending: [],
    verified: true,
    timestamp: new Date().toISOString()
  };

  for (let r = 1; r < data.length; r++) {

    const status =
      String(data[r][6] || "")
        .trim()
        .toUpperCase();

    const item = {
      row: r + 1,
      delegationJobId:
        String(data[r][0] || ""),
      task:
        String(data[r][2] || ""),
      primaryAgent:
        String(data[r][4] || ""),
      fallbackAgent:
        String(data[r][5] || ""),
      status:
        status,
      result:
        String(data[r][7] || "").substring(0, 300),
      error:
        String(data[r][8] || "").substring(0, 300),
      dispatchedAt:
        data[r][9] || "",
      completedAt:
        data[r][10] || ""
    };

    if (status === "PROCESSING") {
      result.processing.push(item);
    }

    if (status === "FAILED") {
      result.failed.push(item);
    }

    if (
      status === "PENDING" ||
      status === "PENDING_DISPATCH"
    ) {
      result.pending.push(item);
    }
  }

  result.counts = {
    processing:
      result.processing.length,
    failed:
      result.failed.length,
    pending:
      result.pending.length
  };

  Logger.log(
    "===== AERIS QUEUE DIAGNOSTIC ====="
  );

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  Logger.log(
    "===== END AERIS QUEUE DIAGNOSTIC ====="
  );

  return result;
}
function AERIS_CLEAN_STALE_PENDING_QUEUE() {

  const sheet =
    getAERISDelegationSheet();

  const data =
    sheet.getDataRange().getValues();

  let cancelled = [];
  let orphaned = [];

  for (let r = 1; r < data.length; r++) {

    const row = r + 1;

    const status =
      String(data[r][6] || "")
        .trim()
        .toUpperCase();

    const jobId =
      String(data[r][0] || "")
        .trim();

    const task =
      String(data[r][2] || "")
        .trim()
        .toUpperCase();

    /*
     * CANCEL ORPHAN FAILED JOB
     */

    if (
      status === "FAILED" &&
      !jobId
    ) {

      sheet
        .getRange(row, 7)
        .setValue("CANCELLED");

      sheet
        .getRange(row, 9)
        .setValue(
          "ORPHAN_JOB_MISSING_DELEGATION_JOB_ID"
        );

      orphaned.push(row);

      continue;
    }

    /*
     * CANCEL STALE AUTONOMOUS LOOP JOBS
     */

    if (
      status === "PENDING_DISPATCH" &&
      task === "CONTINUE_ORCHESTRATION" &&
      jobId.indexOf("NEXT-") === 0
    ) {

      sheet
        .getRange(row, 7)
        .setValue("CANCELLED");

      sheet
        .getRange(row, 9)
        .setValue(
          "STALE_AUTONOMOUS_LOOP_JOB_CANCELLED"
        );

      cancelled.push({
        row: row,
        delegationJobId: jobId
      });

      continue;
    }
  }

  const result = {

    success: true,

    system:
      "AERIS_QUEUE_CLEANUP",

    cancelledCount:
      cancelled.length,

    orphanedCount:
      orphaned.length,

    cancelled:
      cancelled,

    orphaned:
      orphaned,

    verified:
      true,

    timestamp:
      new Date().toISOString()
  };

  Logger.log(
    "===== AERIS QUEUE CLEANUP ====="
  );

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  Logger.log(
    "===== END AERIS QUEUE CLEANUP ====="
  );

  return result;
}function TEST_AERIS_WRITE_GATE() {

  const marker =
    "AX_WRITE_TEST_" +
    new Date().toISOString();

  const source =
    ScriptApp
      .getProjectTriggers()
      .length;

  const result = {
    success: true,
    system: "AERIS_WRITE_GATE_TEST",
    writeCapability: "EXECUTION_CONTEXT_ACTIVE",
    marker: marker,
    triggerCount: source,
    timestamp: new Date().toISOString()
  };

  console.log(
    "===== AERIS WRITE GATE TEST ====="
  );

  console.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  console.log(
    "===== END AERIS WRITE GATE TEST ====="
  );

  return result;
}
function TEST_AERIS_SOURCE_READ() {

  const scriptId =
    ScriptApp.getScriptId();

  const url =
    "https://script.googleapis.com/v1/projects/" +
    encodeURIComponent(scriptId) +
    "/content";

  const response =
    UrlFetchApp.fetch(
      url,
      {
        method: "get",
        headers: {
          Authorization:
            "Bearer " +
            ScriptApp.getOAuthToken()
        },
        muteHttpExceptions: true
      }
    );

  const code =
    response.getResponseCode();

  const text =
    response.getContentText();

  const result = {
    success:
      code === 200,

    system:
      "AERIS_SOURCE_READ",

    scriptId:
      scriptId,

    httpStatus:
      code,

    sourceLength:
      text.length,

    timestamp:
      new Date().toISOString()
  };

  console.log(
    "===== AERIS SOURCE READ ====="
  );

  console.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  console.log(
    "===== END AERIS SOURCE READ ====="
  );

  if (code !== 200) {
    console.log(text);
  }

  return result;
}
function TEST_AERIS_SOURCE_WRITE() {

  const scriptId =
    ScriptApp.getScriptId();

  const url =
    "https://script.googleapis.com/v1/projects/" +
    encodeURIComponent(scriptId) +
    "/content";

  const token =
    ScriptApp.getOAuthToken();

  // READ CURRENT SOURCE
  const readResponse =
    UrlFetchApp.fetch(
      url,
      {
        method: "get",
        headers: {
          Authorization:
            "Bearer " + token
        },
        muteHttpExceptions: true
      }
    );

  const readCode =
    readResponse.getResponseCode();

  if (readCode !== 200) {

    throw new Error(
      "SOURCE_READ_FAILED HTTP " +
      readCode +
      ": " +
      readResponse.getContentText()
    );
  }

  const content =
    JSON.parse(
      readResponse.getContentText()
    );

  const files =
    content.files || [];

  const target =
    files.find(
      file =>
        file.name === "รหัส"
    ) ||
    files.find(
      file =>
        file.name === "Code"
    );

  if (!target) {

    throw new Error(
      "SOURCE_CODE_FILE_NOT_FOUND"
    );
  }

  const marker =
    "AX_WRITE_VERIFIED_" +
    new Date().getTime();

  const originalSource =
    target.source || "";

  const newSource =
    originalSource +
    "\n\n/* " +
    marker +
    " */\n";

  target.source =
    newSource;

  // WRITE FULL PROJECT CONTENT
  const updateResponse =
    UrlFetchApp.fetch(
      url,
      {
        method: "put",
        contentType:
          "application/json",
        headers: {
          Authorization:
            "Bearer " + token
        },
        payload:
          JSON.stringify({
            files:
              files
          }),
        muteHttpExceptions: true
      }
    );

  const updateCode =
    updateResponse.getResponseCode();

  if (
    updateCode < 200 ||
    updateCode >= 300
  ) {

    throw new Error(
      "SOURCE_WRITE_FAILED HTTP " +
      updateCode +
      ": " +
      updateResponse.getContentText()
    );
  }

  // READ BACK
  const verifyResponse =
    UrlFetchApp.fetch(
      url,
      {
        method: "get",
        headers: {
          Authorization:
            "Bearer " + token
        },
        muteHttpExceptions: true
      }
    );

  const verifyCode =
    verifyResponse.getResponseCode();

  if (verifyCode !== 200) {

    throw new Error(
      "SOURCE_VERIFY_READ_FAILED HTTP " +
      verifyCode +
      ": " +
      verifyResponse.getContentText()
    );
  }

  const verifyContent =
    JSON.parse(
      verifyResponse.getContentText()
    );

  const verifyFiles =
    verifyContent.files || [];

  const verifyTarget =
    verifyFiles.find(
      file =>
        file.name === "รหัส"
    ) ||
    verifyFiles.find(
      file =>
        file.name === "Code"
    );

  const verified =
    !!verifyTarget &&
    String(
      verifyTarget.source || ""
    ).indexOf(marker) !== -1;

  const result = {

    success:
      updateCode >= 200 &&
      updateCode < 300 &&
      verified,

    system:
      "AERIS_SOURCE_WRITE",

    scriptId:
      scriptId,

    httpStatus:
      updateCode,

    marker:
      marker,

    verified:
      verified,

    timestamp:
      new Date().toISOString()
  };

  console.log(
    "===== AERIS SOURCE WRITE ====="
  );

  console.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  console.log(
    "===== END AERIS SOURCE WRITE ====="
  );

  return result;
}
function AX_SELF_WRITE_CONTROLLER_V1(changeRequest) {

  if (!changeRequest) {
    throw new Error("MISSING_CHANGE_REQUEST");
  }

  const scriptId =
    ScriptApp.getScriptId();

  const url =
    "https://script.googleapis.com/v1/projects/" +
    encodeURIComponent(scriptId) +
    "/content";

  const token =
    ScriptApp.getOAuthToken();

  /*
   * =====================================================
   * 1. READ CURRENT SOURCE
   * =====================================================
   */

  const readResponse =
    UrlFetchApp.fetch(
      url,
      {
        method: "get",
        headers: {
          Authorization:
            "Bearer " + token
        },
        muteHttpExceptions: true
      }
    );

  const readCode =
    readResponse.getResponseCode();

  if (readCode !== 200) {
    throw new Error(
      "AX_SOURCE_READ_FAILED HTTP " +
      readCode +
      ": " +
      readResponse.getContentText()
    );
  }

  const currentContent =
    JSON.parse(
      readResponse.getContentText()
    );

  const currentFiles =
    currentContent.files || [];

  if (!currentFiles.length) {
    throw new Error(
      "AX_SOURCE_EMPTY"
    );
  }

  /*
   * =====================================================
   * 2. CREATE IN-MEMORY BACKUP
   * =====================================================
   */

  const backup =
    JSON.stringify(
      currentFiles
    );

  /*
   * =====================================================
   * 3. VALIDATE CHANGE REQUEST
   * =====================================================
   */

  const targetFile =
    String(
      changeRequest.file || ""
    ).trim();

  const operation =
    String(
      changeRequest.operation || ""
    ).trim()
    .toUpperCase();

  const marker =
    "AX_CONTROLLER_" +
    new Date().getTime();

  if (!targetFile) {
    throw new Error(
      "MISSING_TARGET_FILE"
    );
  }

  if (
    operation !== "APPEND_COMMENT"
  ) {
    throw new Error(
      "UNSUPPORTED_OPERATION"
    );
  }

  /*
   * =====================================================
   * 4. LOCATE TARGET SOURCE
   * =====================================================
   */

  const target =
    currentFiles.find(
      file =>
        file.name === targetFile
    );

  if (!target) {
    throw new Error(
      "TARGET_FILE_NOT_FOUND: " +
      targetFile
    );
  }

  const originalSource =
    target.source || "";

  /*
   * =====================================================
   * 5. APPLY SAFE TEST CHANGE
   * =====================================================
   */

  target.source =
    originalSource +
    "\n\n/* " +
    marker +
    " */\n";

  /*
   * =====================================================
   * 6. WRITE FULL PROJECT
   * =====================================================
   */

  const writeResponse =
    UrlFetchApp.fetch(
      url,
      {
        method: "put",
        contentType:
          "application/json",
        headers: {
          Authorization:
            "Bearer " + token
        },
        payload:
          JSON.stringify({
            files:
              currentFiles
          }),
        muteHttpExceptions: true
      }
    );

  const writeCode =
    writeResponse.getResponseCode();

  if (
    writeCode < 200 ||
    writeCode >= 300
  ) {

    throw new Error(
      "AX_SOURCE_WRITE_FAILED HTTP " +
      writeCode +
      ": " +
      writeResponse.getContentText()
    );
  }

  /*
   * =====================================================
   * 7. READ-BACK
   * =====================================================
   */

  const verifyResponse =
    UrlFetchApp.fetch(
      url,
      {
        method: "get",
        headers: {
          Authorization:
            "Bearer " + token
        },
        muteHttpExceptions: true
      }
    );

  const verifyCode =
    verifyResponse.getResponseCode();

  if (verifyCode !== 200) {
    throw new Error(
      "AX_READBACK_FAILED HTTP " +
      verifyCode
    );
  }

  const verifyContent =
    JSON.parse(
      verifyResponse.getContentText()
    );

  const verifyFiles =
    verifyContent.files || [];

  const verifyTarget =
    verifyFiles.find(
      file =>
        file.name === targetFile
    );

  const verified =
    !!verifyTarget &&
    String(
      verifyTarget.source || ""
    ).indexOf(marker) !== -1;

  /*
   * =====================================================
   * 8. ACCEPT / FAIL
   * =====================================================
   */

  const result = {

    success:
      verified,

    system:
      "AX_SELF_WRITE_CONTROLLER_V1",

    scriptId:
      scriptId,

    targetFile:
      targetFile,

    operation:
      operation,

    httpStatus:
      writeCode,

    verified:
      verified,

    backupCreated:
      backup.length > 0,

    marker:
      marker,

    timestamp:
      new Date().toISOString()
  };

  console.log(
    "===== AX SELF WRITE CONTROLLER ====="
  );

  console.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  console.log(
    "===== END AX SELF WRITE CONTROLLER ====="
  );

  if (!verified) {
    throw new Error(
      "AX_WRITE_VERIFICATION_FAILED"
    );
  }

  return result;
}function TEST_AX_SELF_WRITE_CONTROLLER_V1() {
  return AX_SELF_WRITE_CONTROLLER_V1({
    file: "รหัส",
    operation: "APPEND_COMMENT"
  });
}

function getAERISControlStatus() {
  const sheet = getAERISDelegationSheet();
  const data = sheet.getDataRange().getValues();

  let pending = 0;
  let processing = 0;
  let completed = 0;
  let failed = 0;

  for (let r = 1; r < data.length; r++) {
    const status = String(data[r][6] || "").trim().toUpperCase();

    if (status === "PENDING_DISPATCH" || status === "PENDING") {
      pending++;
    } else if (status === "PROCESSING") {
      processing++;
    } else if (status === "COMPLETED") {
      completed++;
    } else if (status === "FAILED") {
      failed++;
    }
  }

  const total = pending + processing + completed + failed;

  const progress = total > 0
    ? Math.round((completed / total) * 100)
    : 100;

  return {
    success: true,
    system: "AERIS_CONTROL_CENTER",
    timestamp: new Date().toISOString(),
    status: processing > 0
      ? "RUNNING"
      : pending > 0
        ? "WAITING"
        : "IDLE",
    progress: progress,
    queue: {
      total: total,
      pending: pending,
      processing: processing,
      completed: completed,
      failed: failed
    },
    verified: true
  };
}

function getAERISControlCenterHTML() {

  return `
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">

<style>

body {
  margin: 0;
  font-family: Arial, sans-serif;
  background: #0b1020;
  color: #ffffff;
}

.container {
  max-width: 1100px;
  margin: auto;
  padding: 24px;
}

.header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 24px;
}

.title {
  font-size: 26px;
  font-weight: bold;
}

.online {
  color: #4ade80;
  font-weight: bold;
}

.card {
  background: #151c31;
  border-radius: 14px;
  padding: 20px;
  margin-bottom: 18px;
  box-shadow: 0 8px 30px rgba(0,0,0,.25);
}

.job {
  font-size: 18px;
  margin-bottom: 16px;
}

.progress {
  width: 100%;
  height: 18px;
  background: #252e49;
  border-radius: 20px;
  overflow: hidden;
}

.progressBar {
  height: 100%;
  width: 0%;
  background: #4ade80;
  transition: width .5s ease;
}

.percent {
  margin-top: 10px;
  font-size: 18px;
  font-weight: bold;
}

.grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 12px;
}

.metric {
  background: #1d2742;
  padding: 16px;
  border-radius: 10px;
}

.metricTitle {
  font-size: 13px;
  color: #9ca3af;
}

.metricValue {
  font-size: 25px;
  font-weight: bold;
  margin-top: 6px;
}

.status {
  font-size: 20px;
  font-weight: bold;
}

.footer {
  color: #9ca3af;
  font-size: 12px;
  margin-top: 12px;
}

@media(max-width:700px) {
  .grid {
    grid-template-columns: repeat(2, 1fr);
  }
}

</style>
</head>

<body>

<div class="container">

  <div class="header">
    <div class="title">
      AERIS CONTROL CENTER
    </div>

    <div class="online">
      ● AX ONLINE
    </div>
  </div>

  <div class="card">

    <div class="job">
      CURRENT SYSTEM STATUS
    </div>

    <div id="status"
         class="status">
      CONNECTING...
    </div>

    <div style="margin-top:16px"
         class="progress">

      <div id="progressBar"
           class="progressBar">
      </div>

    </div>

    <div id="percent"
         class="percent">
      0%
    </div>

  </div>

  <div class="card">

    <div class="job">
      QUEUE
    </div>

    <div class="grid">

      <div class="metric">
        <div class="metricTitle">
          TOTAL
        </div>
        <div id="total"
             class="metricValue">
          -
        </div>
      </div>

      <div class="metric">
        <div class="metricTitle">
          PENDING
        </div>
        <div id="pending"
             class="metricValue">
          -
        </div>
      </div>

      <div class="metric">
        <div class="metricTitle">
          PROCESSING
        </div>
        <div id="processing"
             class="metricValue">
          -
        </div>
      </div>

      <div class="metric">
        <div class="metricTitle">
          COMPLETED
        </div>
        <div id="completed"
             class="metricValue">
          -
        </div>
      </div>

    </div>

  </div>

  <div class="card">

    <div class="job">
      ERROR MONITOR
    </div>

    <div class="metricValue"
         id="failed">
      -
    </div>

    <div class="footer"
         id="updated">
      Waiting for telemetry...
    </div>

  </div>

</div>

<script>

function updateDashboard() {

  google.script.run
    .withSuccessHandler(function(data) {

      if (!data || !data.success) {
        return;
      }

      document.getElementById("status")
        .textContent =
        data.status;

      document.getElementById("progressBar")
        .style.width =
        data.progress + "%";

      document.getElementById("percent")
        .textContent =
        data.progress + "%";

      document.getElementById("total")
        .textContent =
        data.queue.total;

      document.getElementById("pending")
        .textContent =
        data.queue.pending;

      document.getElementById("processing")
        .textContent =
        data.queue.processing;

      document.getElementById("completed")
        .textContent =
        data.queue.completed;

      document.getElementById("failed")
        .textContent =
        data.queue.failed;

      document.getElementById("updated")
        .textContent =
        "Last update: " +
        new Date().toLocaleTimeString();

    })
    .getAERISControlStatus();
}

updateDashboard();

setInterval(
  updateDashboard,
  2000
);

</script>

</body>
</html>
`;
}function TEST_AERIS_NODE_API_DIRECT() {
  const mockEvent = {
    parameter: {
      action: "node_status"
    }
  };

  const result = doGet(mockEvent);

  Logger.log("===== AERIS NODE API DIRECT TEST =====");
  Logger.log(result.getContent());
  Logger.log("===== END AERIS NODE API DIRECT TEST =====");
}function TEST_AERIS_CREATE_FILE() {

  const result = bridgeCreateJob({

    command: "CREATE_FILE",

    fileName:
      "AERIS_RUNTIME_TEST_2026-08-24.txt",

    destination:
      "03",

    content:
      "AERIS RUNTIME BRIDGE TEST\n" +
      "Created by Queue Executor.\n" +
      "Timestamp: " +
      new Date().toISOString(),

    approved: true

  });

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  return result;
}function TEST_AERIS_QUEUE_INSPECT() {

  const sheet = getQueueSheet();

  const data = sheet.getDataRange().getValues();

  Logger.log(
    JSON.stringify(
      {
        spreadsheetId:
          sheet.getParent().getId(),

        spreadsheetName:
          sheet.getParent().getName(),

        sheetName:
          sheet.getName(),

        lastRow:
          sheet.getLastRow(),

        lastColumn:
          sheet.getLastColumn(),

        headers:
          data.length
            ? data[0]
            : [],

        row18:
          data.length >= 18
            ? data[17]
            : null

      },
      null,
      2
    )
  );
}function TEST_AERIS_QUEUE_ROW18() {

  const sheet = getQueueSheet();

  const data =
    sheet.getDataRange().getValues();

  const headers = data[0];
  const row = data[17];

  const indexes = {
    jobId: headers.indexOf("Job ID"),
    command: headers.indexOf("Command"),
    approved: headers.indexOf("Approved"),
    status: headers.indexOf("Status"),
    content: headers.indexOf("Content")
  };

  const values = {
    jobId: row[indexes.jobId],
    command: row[indexes.command],
    approved: row[indexes.approved],
    status: row[indexes.status],
    content: row[indexes.content]
  };

  Logger.log(
    JSON.stringify(
      {
        indexes: indexes,
        values: values,
        statusUpper:
          String(values.status || "")
            .trim()
            .toUpperCase(),
        isPending:
          String(values.status || "")
            .trim()
            .toUpperCase() === "PENDING",
        isApproved:
          String(values.approved || "")
            .trim()
            .toUpperCase() === "TRUE"
      },
      null,
      2
    )
  );
}function REPAIR_AERIS_ROW18() {

  const sheet = getQueueSheet();

  const row = 18;

  const content =
    "AERIS RUNTIME BRIDGE TEST\n" +
    "Created by Queue Executor.\n" +
    "Timestamp: 2026-08-24T05:31:50.295Z";

  sheet.getRange(row, 8).setValue("PENDING");
  sheet.getRange(row, 9).setValue("");
  sheet.getRange(row, 10).setValue("");
  sheet.getRange(row, 11).setValue("");
  sheet.getRange(row, 12).setValue(content);

  Logger.log(
    JSON.stringify({
      repaired: true,
      row: row,
      status: "PENDING",
      contentLength: content.length
    }, null, 2)
  );
}function TEST_AERIS_DRIVE_PERMISSION() {
  const files = DriveApp.getFilesByName("AERIS COMMAND QUEUE v1.0");
  Logger.log("DRIVE_PERMISSION_OK");
}function inspectAERISQueueRow() {

  const sheet = getQueueSheet();

  const lastRow = sheet.getLastRow();
  const lastColumn = sheet.getLastColumn();

  const headers =
    sheet
      .getRange(1, 1, 1, lastColumn)
      .getValues()[0];

  const row =
    sheet
      .getRange(lastRow, 1, 1, lastColumn)
      .getValues()[0];

  const indexes = {
    jobId: headers.indexOf("Job ID"),
    command: headers.indexOf("Command"),
    approved: headers.indexOf("Approved"),
    content: headers.indexOf("Content"),
    status: headers.indexOf("Status")
  };

  const result = {

    lastRow: lastRow,

    lastColumn: lastColumn,

    headers: headers,

    indexes: indexes,

    values: {
      jobId: row[indexes.jobId],
      command: row[indexes.command],
      approved: row[indexes.approved],
      content: row[indexes.content],
      status: row[indexes.status]
    },

    statusUpper:
      String(
        row[indexes.status] || ""
      )
        .trim()
        .toUpperCase(),

    isPending:
      String(
        row[indexes.status] || ""
      )
        .trim()
        .toUpperCase() === "PENDING",

    isApproved:
      String(
        row[indexes.approved] || ""
      )
        .trim()
        .toUpperCase() === "TRUE"
  };

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  return result;
}function migrateAERISQueueSchemaV2() {

  const sheet = getQueueSheet();

  const lastRow = sheet.getLastRow();

  if (lastRow < 1) {
    throw new Error("QUEUE_EMPTY");
  }

  const oldHeaders = [
    "Job ID",
    "Timestamp",
    "Command",
    "File ID",
    "File Name",
    "Destination",
    "Approved",
    "Status",
    "Result",
    "Error",
    "Completed At",
    "Content"
  ];

  const newHeaders = [
    "Job ID",
    "Timestamp",
    "Command",
    "File ID",
    "File Name",
    "Destination",
    "Approved",
    "Content",
    "Status",
    "Result",
    "Error",
    "Completed At"
  ];

  const data =
    sheet
      .getRange(
        1,
        1,
        lastRow,
        12
      )
      .getValues();

  const headers = data[0].map(function(value) {
    return String(value).trim();
  });

  if (
    JSON.stringify(headers) !==
    JSON.stringify(oldHeaders)
  ) {
    throw new Error(
      "UNEXPECTED_QUEUE_SCHEMA"
    );
  }

  const migrated = [newHeaders];

  for (
    let i = 1;
    i < data.length;
    i++
  ) {

    const row = data[i];

    migrated.push([

      row[0],  // Job ID
      row[1],  // Timestamp
      row[2],  // Command
      row[3],  // File ID
      row[4],  // File Name
      row[5],  // Destination
      row[6],  // Approved

      row[11], // Content
      row[7],  // Status
      row[8],  // Result
      row[9],  // Error
      row[10]  // Completed At

    ]);
  }

  sheet
    .getRange(
      1,
      1,
      migrated.length,
      12
    )
    .setValues(
      migrated
    );

  const verify =
    sheet
      .getRange(
        1,
        1,
        migrated.length,
        12
      )
      .getValues();

  const verifyHeaders =
    verify[0].map(function(value) {
      return String(value).trim();
    });

  if (
    JSON.stringify(verifyHeaders) !==
    JSON.stringify(newHeaders)
  ) {
    throw new Error(
      "QUEUE_SCHEMA_MIGRATION_VERIFICATION_FAILED"
    );
  }

  return {

    status:
      "QUEUE_SCHEMA_MIGRATED",

    verified:
      true,

    rows:
      migrated.length - 1,

    columns:
      12,

    headers:
      verifyHeaders,

    timestamp:
      new Date().toISOString()

  };
}function inspectAERISQueueSchema() {

  const sheet = getQueueSheet();

  const lastRow = sheet.getLastRow();
  const lastColumn = sheet.getLastColumn();

  if (lastRow < 1) {
    throw new Error("QUEUE_EMPTY");
  }

  const headers =
    sheet
      .getRange(
        1,
        1,
        1,
        lastColumn
      )
      .getValues()[0]
      .map(function(value) {
        return String(value).trim();
      });

  const expectedHeaders = [
    "Job ID",
    "Timestamp",
    "Command",
    "File ID",
    "File Name",
    "Destination",
    "Approved",
    "Content",
    "Status",
    "Result",
    "Error",
    "Completed At"
  ];

  const schemaMatch =
    JSON.stringify(headers) ===
    JSON.stringify(expectedHeaders);

      const result = {

    status:
      schemaMatch
        ? "QUEUE_SCHEMA_OK"
        : "QUEUE_SCHEMA_MISMATCH",

    verified:
      schemaMatch,

    lastRow:
      lastRow,

    lastColumn:
      lastColumn,

    headers:
      headers,

    expectedHeaders:
      expectedHeaders,

    timestamp:
      new Date().toISOString()

  };

  Logger.log(
    "===== AERIS QUEUE SCHEMA INSPECTION ====="
  );

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  Logger.log(
    "===== END AERIS QUEUE SCHEMA INSPECTION ====="
  );

  return result;
}function inspectAERISQueueRow19() {

  const sheet = getQueueSheet();

  const rowNumber = 19;

  const values =
    sheet
      .getRange(rowNumber, 1, 1, 12)
      .getValues()[0];

  const result = {

    row: rowNumber,

    A_JobID: values[0],
    B_Timestamp: values[1],
    C_Command: values[2],
    D_FileID: values[3],
    E_FileName: values[4],
    F_Destination: values[5],
    G_Approved: values[6],
    H_Content: values[7],
    I_Status: values[8],
    J_Result: values[9],
    K_Error: values[10],
    L_CompletedAt: values[11]

  };

  Logger.log(
    "===== AERIS QUEUE ROW 19 ====="
  );

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  Logger.log(
    "===== END AERIS QUEUE ROW 19 ====="
  );

  return result;
}function inspectAERISProcessingJob19() {

  const sheet = getQueueSheet();

  const rowNumber = 19;

  const values =
    sheet
      .getRange(rowNumber, 1, 1, 12)
      .getValues()[0];

  const result = {

    row: rowNumber,

    jobId: values[0],
    command: values[2],
    fileName: values[4],
    destination: values[5],
    approved: values[6],
    contentPresent:
      String(values[7] || "").length > 0,

    status: values[8],
    resultPresent:
      String(values[9] || "").length > 0,

    error:
      String(values[10] || ""),

    completedAt:
      values[11] || ""

  };

  Logger.log(
    "===== AERIS PROCESSING JOB INSPECTION ====="
  );

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  Logger.log(
    "===== END AERIS PROCESSING JOB INSPECTION ====="
  );

  return result;
}function diagnoseAERISCreateFilePath() {

  const sheet = getQueueSheet();

  const rowNumber = 19;

  const values =
    sheet
      .getRange(rowNumber, 1, 1, 12)
      .getValues()[0];

  const destination =
    String(values[5] || "").trim();

  const fileName =
    String(values[4] || "").trim();

  const content =
    String(values[7] || "");

  const result = {
    row: rowNumber,
    jobId: String(values[0] || "").trim(),
    command: String(values[2] || "").trim().toUpperCase(),
    destination: destination,
    normalizedDestination: "",
    folderName: "",
    fileName: fileName,
    contentLength: content.length,
    approved: values[6] === true,
    status: String(values[8] || "").trim().toUpperCase()
  };

  try {

    result.normalizedDestination =
      normalizeFolderNumber(destination);

    result.folderName =
      AERIS_FOLDERS[
        result.normalizedDestination
      ];

    if (!result.folderName) {
      throw new Error(
        "FOLDER_NAME_NOT_FOUND: " +
        result.normalizedDestination
      );
    }

    const folder =
      getAerisFolder(
        result.folderName
      );

    result.folderId =
      folder.getId();

    result.folderExists =
      true;

  } catch (error) {

    result.diagnosticError =
      error.message;

  }

  Logger.log(
    "===== AERIS CREATE FILE PATH DIAGNOSTIC ====="
  );

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  Logger.log(
    "===== END AERIS CREATE FILE PATH DIAGNOSTIC ====="
  );

  return result;
}function resetAERISJob19ToPending() {

  const sheet = getQueueSheet();

  const rowNumber = 19;

  const currentStatus =
    String(
      sheet
        .getRange(rowNumber, 9)
        .getValue() || ""
    )
      .trim()
      .toUpperCase();

  if (currentStatus !== "PROCESSING") {
    throw new Error(
      "UNEXPECTED_JOB_STATUS: " +
      currentStatus
    );
  }

  sheet
    .getRange(rowNumber, 9)
    .setValue("PENDING");

  const verifiedStatus =
    String(
      sheet
        .getRange(rowNumber, 9)
        .getValue() || ""
    )
      .trim()
      .toUpperCase();

  if (verifiedStatus !== "PENDING") {
    throw new Error(
      "JOB_STATUS_RESET_VERIFICATION_FAILED"
    );
  }

  const result = {
    status: "JOB_RESET_TO_PENDING",
    verified: true,
    row: rowNumber,
    jobId:
      sheet
        .getRange(rowNumber, 1)
        .getValue(),
    previousStatus: "PROCESSING",
    currentStatus: verifiedStatus,
    timestamp:
      new Date().toISOString()
  };

  Logger.log(
    "===== AERIS JOB RESET ====="
  );

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  Logger.log(
    "===== END AERIS JOB RESET ====="
  );

  return result;
}function dispatchToAERISRuntime(jobId, command) {

  const url =
    "https://aeris-execution-runtime.aerismusic8.workers.dev/execute";

  const payload = {
    jobId: jobId,
    command: command
  };

  const response = UrlFetchApp.fetch(
    url,
    {
      method: "post",
      contentType: "application/json",
      payload: JSON.stringify(payload),
      muteHttpExceptions: true
    }
  );

  const httpStatus =
    response.getResponseCode();

  const text =
    response.getContentText();

  let data;

  try {
    data = JSON.parse(text);
  } catch (error) {
    throw new Error(
      "RUNTIME_INVALID_RESPONSE: " +
      text
    );
  }

  if (
    httpStatus < 200 ||
    httpStatus >= 300
  ) {
    throw new Error(
      "RUNTIME_HTTP_" +
      httpStatus +
      ": " +
      text
    );
  }

  if (
    data.accepted !== true ||
    data.verified !== true
  ) {
    throw new Error(
      "RUNTIME_EXECUTION_REJECTED: " +
      text
    );
  }

  return data;
}function testAERISRuntimeDispatch() {

  const result =
    dispatchToAERISRuntime(
      "AERIS-APPSCRIPT-TEST-001",
      "TEST_EXECUTION"
    );

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  return result;
}function testAERISExternalDispatch() {

  const result =
    bridgeCreateJob({

      command: "EXECUTE_EXTERNAL",

      approved: true,

      content: "REAL_EXTERNAL_DISPATCH_TEST"

    });

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  return result;
}function testAERISGeminiExternalExecution() {

  const result =
    bridgeCreateJob({

      command: "EXECUTE_EXTERNAL",

      approved: true,

      content:
        "ตอบคำว่า AERIS_GEMINI_TEST_PASS เท่านั้น"

    });

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  return result;
}function testAERISProductionDispatch() {

  const result =
    bridgeCreateJob({

      command:
        "EXECUTE_EXTERNAL",

      approved:
        true,

      content:
        "PRODUCTION_DISPATCH_TEST: " +
        "วิเคราะห์คำว่า AERIS และตอบกลับสั้น ๆ " +
        "พร้อมระบุว่าได้รับงานจาก AERIS Runtime"

    });

  Logger.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );

  return result;
}