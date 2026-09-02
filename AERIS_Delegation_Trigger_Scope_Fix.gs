/*
 * AERIS Delegation Trigger Scope Compatibility Fix
 *
 * Purpose:
 *   AERIS_DELEGATION_QUEUE_TRIGGER() references `data` and `index`, while
 *   those names were previously local to another function scope.
 *
 * Safety:
 *   - Read-only against AERIS_DELEGATION_QUEUE.
 *   - Uses the known queue spreadsheet ID rather than active-spreadsheet state.
 *   - Rebuilds values/index for each Apps Script execution.
 *   - Production fix is not considered verified until a real trigger run
 *     completes without ReferenceError: data is not defined.
 */

var data = (function () {
  try {
    var ss = SpreadsheetApp.openById(
      "1OBJ_f4WiMDhk_WxcvDE8_5WB91V5xotsP34uUueQSnM"
    );
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
