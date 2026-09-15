/* =========================================================
   AX UNIVERSAL INPUT GATEWAY v1.0
   Purpose: provide a provider-neutral input layer so AX work does not
   depend on a single ChatGPT/file-upload channel.

   Supported ingress modes:
   - TEXT / URL / JSON: direct API payload
   - DRIVE_FILE: reference an existing Google Drive file by fileId
   - INLINE_TEXT: text supplied directly in the payload

   Security / integrity:
   - No credentials are accepted as input data.
   - Every accepted item receives an inputId, timestamp, source and SHA-256.
   - Payloads are persisted before downstream dispatch.
   - This module is additive and does not replace the verified core queue.

   Activation note:
   The existing doPost() remains backward-compatible. The gateway is exposed
   through AX_INPUT_SUBMIT() and can be wired into an approved ingress route
   without creating a duplicate processCommandQueue trigger.
========================================================= */

const AX_INPUT_GATEWAY_VERSION = "1.0.0";
const AX_INPUT_SHEET_NAME = "AX_INPUT_QUEUE";
const AX_INPUT_HEADERS = [
  "Input ID", "Created At", "Source", "Input Type", "File ID", "File Name",
  "Mime Type", "Content Hash", "Payload", "Status", "Error", "Completed At"
];
function axInputNow_() { return new Date().toISOString(); }
function axInputText_(value, field) { const text = String(value == null ? "" : value).trim(); if (!text) throw new Error("MISSING_INPUT_" + field); return text; }
function axInputHash_(value) { const bytes = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, String(value == null ? "" : value)); return bytes.map(function(byte) { const n = byte < 0 ? byte + 256 : byte; return ("0" + n.toString(16)).slice(-2); }).join(""); }
function axInputSheet_() { const ss = SpreadsheetApp.openById(QUEUE_SPREADSHEET_ID); let sheet = ss.getSheetByName(AX_INPUT_SHEET_NAME); if (!sheet) sheet = ss.insertSheet(AX_INPUT_SHEET_NAME); if (sheet.getLastRow() === 0) { sheet.getRange(1, 1, 1, AX_INPUT_HEADERS.length).setValues([AX_INPUT_HEADERS]); sheet.setFrozenRows(1); } return sheet; }
function AX_INPUT_SUBMIT(request) { request = request || {}; const source = axInputText_(request.source || "K", "SOURCE"); const inputType = axInputText_(request.inputType || request.type, "TYPE").toUpperCase(); const allowed = ["TEXT", "URL", "JSON", "DRIVE_FILE", "INLINE_TEXT"]; if (allowed.indexOf(inputType) === -1) throw new Error("UNSUPPORTED_INPUT_TYPE: " + inputType); let payload = request.payload; let fileId = String(request.fileId || "").trim(); let fileName = String(request.fileName || "").trim(); let mimeType = String(request.mimeType || "").trim(); if (inputType === "DRIVE_FILE") { fileId = axInputText_(fileId, "FILE_ID"); const file = DriveApp.getFileById(fileId); fileName = file.getName(); mimeType = file.getMimeType(); payload = JSON.stringify({ fileId: fileId, fileName: fileName, mimeType: mimeType, url: file.getUrl() }); } else if (inputType === "JSON") { if (typeof payload === "string") JSON.parse(payload); else payload = JSON.stringify(payload == null ? {} : payload); } else { payload = axInputText_(payload, "PAYLOAD"); } const inputId = "AXIN-" + Utilities.getUuid(); const createdAt = axInputNow_(); const hash = axInputHash_(payload); const sheet = axInputSheet_(); sheet.appendRow([inputId, createdAt, source, inputType, fileId, fileName, mimeType, hash, String(payload), "RECEIVED", "", ""]); const row = sheet.getLastRow(); const persistedId = String(sheet.getRange(row, 1).getValue() || "").trim(); const persistedHash = String(sheet.getRange(row, 8).getValue() || "").trim(); if (persistedId !== inputId || persistedHash !== hash) throw new Error("AX_INPUT_PERSISTENCE_VERIFICATION_FAILED"); return { success: true, verified: true, gatewayVersion: AX_INPUT_GATEWAY_VERSION, inputId: inputId, status: "RECEIVED", inputType: inputType, contentHash: hash, createdAt: createdAt }; }
function AX_INPUT_STATUS(inputId) { const id = axInputText_(inputId, "ID"); const sheet = axInputSheet_(); const values = sheet.getDataRange().getValues(); for (let i = 1; i < values.length; i++) { if (String(values[i][0] || "").trim() !== id) continue; return { success: true, verified: true, inputId: id, createdAt: values[i][1], source: values[i][2], inputType: values[i][3], fileId: values[i][4], fileName: values[i][5], mimeType: values[i][6], contentHash: values[i][7], status: values[i][9], error: values[i][10], completedAt: values[i][11] }; } return { success: true, verified: true, found: false, inputId: id }; }
function AX_INPUT_HEALTH() { const sheet = axInputSheet_(); return { success: true, verified: true, gatewayVersion: AX_INPUT_GATEWAY_VERSION, sheet: AX_INPUT_SHEET_NAME, records: Math.max(0, sheet.getLastRow() - 1), timestamp: axInputNow_() }; }
