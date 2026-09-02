/* AERIS Delegation Trigger Scope Compatibility Fix */
var data = (function () {
  var ss = SpreadsheetApp.openById("1OBJ_f4WiMDhk_WxcvDE8_5WB91V5xotsP34uUueQSnM");
  var sheet = ss.getSheetByName("AERIS_DELEGATION_QUEUE");
  if (!sheet || sheet.getLastRow() === 0 || sheet.getLastColumn() === 0) return [];
  return sheet.getRange(1, 1, sheet.getLastRow(), sheet.getLastColumn()).getValues();
})();

var index = (function () {
  var result = {};
  if (!data || !data.length) return result;
  var headers = data[0] || [];
  for (var c = 0; c < headers.length; c++) {
    var key = String(headers[c] == null ? "" : headers[c]).trim();
    if (key) result[key] = c;
  }
  return result;
})();

function verifyAERISDelegationTriggerScopeFix() {
  var result = {
    system: "AERIS_DELEGATION_TRIGGER_SCOPE_FIX",
    dataDefined: Array.isArray(data),
    indexDefined: !!index,
    rowCount: data.length,
    verified: Array.isArray(data) && !!index,
    timestamp: new Date().toISOString()
  };
  Logger.log(JSON.stringify(result, null, 2));
  return result;
}
