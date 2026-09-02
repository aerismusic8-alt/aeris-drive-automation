/*
 * AERIS Delegation Trigger Scope Compatibility Fix
 *
 * Purpose:
 *   The production AERIS_DELEGATION_QUEUE_TRIGGER() references `data` and
 *   `index`, but those variables are local to another function scope.
 *   This shim provides execution-local-compatible globals for the trigger
 *   without rewriting the large AERIS_Code.gs file through updateContent.
 *
 * Safety:
 *   - Reads only the AERIS_DELEGATION_QUEUE sheet.
 *   - Does not mutate queue rows.
 *   - Rebuilds values/index on every Apps Script execution.
 *   - Must be verified by a real trigger execution before being considered fixed.
 */

var data = (function () {
  try {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = ss.getSheetByName("AERIS_DELEGATION_QUEUE");
    if (!sheet || sheet.getLastRow() === 0 || sheet.getLastColumn() === 0) {
      return [];
    }
    return sheet
      .getRange(1, 1, sheet.getLastRow(), sheet.getLastColumn())
      .getValues();
  } catch (err) {
    return [];
  }
})();

var index = (function () {
  if (!data || data.length === 0) {
    return {};
  }

  var result = {};
  var headers = data[0] || [];
  for (var c = 0; c < headers.length; c++) {
    var key = String(headers[c] == null ? "" : headers[c]).trim();
    if (key) {
      result[key] = c;
    }
  }
  return result;
})();

function verifyAERISDelegationTriggerScopeFix() {
  var required = [
    "Delegation Job ID",
    "Status",
    "Primary Agent"
  ];

  var missing = required.filter(function (key) {
    return index[key] === undefined;
  });

  var result = {
    system: "AERIS_DELEGATION_TRIGGER_SCOPE_FIX",
    dataDefined: Array.isArray(data),
    rowCount: data.length,
    indexDefined: !!index,
    requiredHeadersPresent: missing.length === 0,
    missingHeaders: missing,
    verified: Array.isArray(data) && missing.length === 0,
    timestamp: new Date().toISOString()
  };

  Logger.log(JSON.stringify(result, null, 2));
  return result;
}
