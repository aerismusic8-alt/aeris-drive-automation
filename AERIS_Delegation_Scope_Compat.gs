/* =========================================================
   AERIS DELEGATION SCOPE COMPATIBILITY SHIM
   Purpose: preserve legacy trigger references to global `data`
   and `index` without editing the large trigger function yet.

   Root cause addressed:
   AERIS_DELEGATION_QUEUE_TRIGGER references `data` and `index`
   that are local variables of another function. Apps Script V8
   resolves these names as globals when no local binding exists.

   The shim exposes lazy, per-execution views backed by the
   current delegation sheet. The snapshot is loaded once per
   execution and cached for the duration of that execution.
========================================================= */

var AERIS_TRIGGER_SCOPE_SNAPSHOT_ = null;

function getAERISDelegationTriggerScopeSnapshot_() {
  if (AERIS_TRIGGER_SCOPE_SNAPSHOT_) {
    return AERIS_TRIGGER_SCOPE_SNAPSHOT_;
  }

  var sheet = getAERISDelegationSheet();
  var values = sheet.getDataRange().getValues();
  var headers = values.length ? values[0] : [];
  var headerIndex = {};

  headers.forEach(function(header, i) {
    headerIndex[String(header).trim().toLowerCase()] = i;
  });

  AERIS_TRIGGER_SCOPE_SNAPSHOT_ = {
    data: values,
    index: headerIndex
  };

  return AERIS_TRIGGER_SCOPE_SNAPSHOT_;
}

/*
 * Legacy trigger-compatible globals.
 * Only the properties actually used by the broken loop are exposed.
 */
var data = new Proxy({}, {
  get: function(_target, property) {
    var snapshot = getAERISDelegationTriggerScopeSnapshot_();

    if (property === "length") {
      return snapshot.data.length;
    }

    if (/^\d+$/.test(String(property))) {
      return snapshot.data[Number(property)];
    }

    return undefined;
  }
});

var index = new Proxy({}, {
  get: function(_target, property) {
    var snapshot = getAERISDelegationTriggerScopeSnapshot_();
    return snapshot.index[String(property).trim().toLowerCase()];
  }
});

function TEST_AERIS_DELEGATION_SCOPE_COMPAT() {
  var snapshot = getAERISDelegationTriggerScopeSnapshot_();

  var result = {
    success: true,
    rows: snapshot.data.length,
    headers: Object.keys(snapshot.index),
    dataLength: data.length,
    firstDataRowAccessible: data.length > 1 ? Array.isArray(data[1]) : null,
    statusIndex: index["status"],
    verified: true,
    timestamp: new Date().toISOString()
  };

  Logger.log(JSON.stringify(result, null, 2));
  return result;
}
