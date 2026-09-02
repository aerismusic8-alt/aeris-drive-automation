const TRIGGER_FILE_NAMES = new Set(["AERIS_Code.gs", "Code.gs"]);

const ACTIVE_STATUS_BLOCK = `const activeStatuses = [
  "PENDING",
  "PENDING_DISPATCH",
  "DISPATCH_READY",
  "RETRY_PENDING",
  "FALLBACK_PENDING"
];`;

const BROKEN_LOOP = `for (let r = 1; r < data.length; r++) {
  const rowStatus =
    String(data[r][index["status"]] || "")`;

export function repairDelegationQueueTrigger(content) {
  if (!content || !Array.isArray(content.files)) {
    throw new Error("COMPLETE_PROJECT_CONTENT_REQUIRED");
  }

  let changed = false;
  const files = content.files.map((file) => {
    if (!TRIGGER_FILE_NAMES.has(file.name) || file.type !== "SERVER_JS" || typeof file.source !== "string") {
      return file;
    }

    if (!file.source.includes("function AERIS_DELEGATION_QUEUE_TRIGGER")) {
      return file;
    }

    const source = file.source;
    const marker = ACTIVE_STATUS_BLOCK;
    const markerAt = source.indexOf(marker, source.indexOf("function AERIS_DELEGATION_QUEUE_TRIGGER"));
    if (markerAt < 0) throw new Error("AERIS_TRIGGER_ACTIVE_STATUS_BLOCK_NOT_FOUND");

    const loopAt = source.indexOf(BROKEN_LOOP, markerAt);
    if (loopAt < 0) throw new Error("AERIS_TRIGGER_BROKEN_SCOPE_NOT_FOUND");

    const replacement = `for (let r = 1; r < delegationData.length; r++) {\n  const rowStatus =\n    String(delegationData[r][delegationIndex["status"]] || "")`;
    const nextSource = source.slice(0, loopAt) + replacement + source.slice(loopAt + BROKEN_LOOP.length);

    const helper = `\n\nfunction getAERISDelegationTriggerData_() {\n  const sheet = getAERISDelegationSheet();\n  const values = sheet.getDataRange().getValues();\n  const headers = values.length ? values[0] : [];\n  const delegationIndex = {};\n  headers.forEach(function(header, i) {\n    delegationIndex[String(header).trim().toLowerCase()] = i;\n  });\n  return { sheet: sheet, delegationData: values, delegationIndex: delegationIndex };\n}\n`;

    const helperAlreadyPresent = source.includes("function getAERISDelegationTriggerData_()");
    const finalSource = helperAlreadyPresent ? nextSource : nextSource + helper;
    changed = true;
    return { ...file, source: finalSource };
  });

  if (!changed) throw new Error("AERIS_TRIGGER_FIX_TARGET_NOT_FOUND");
  return { ...content, files };
}
