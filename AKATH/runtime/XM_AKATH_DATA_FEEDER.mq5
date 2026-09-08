#property strict
#property version   "1.0"
#property description "AKATH XM read-only market/account data feeder. No order execution."

input string RuntimeUrl = "https://ax-control-runtime.aerismusic8.workers.dev";
input string NodeSecret = "";
input string AccountScope = "XM_MICRO_K_DESIGNATED_ACCOUNT";
input int TimerSeconds = 15;
input string SymbolsCsv = "EURUSD,GBPUSD,USDJPY,XAUUSD";
input ENUM_TIMEFRAMES Timeframe = PERIOD_M5;
input int HistoricalBars = 1000;

string Trim(string value) { StringTrimLeft(value); StringTrimRight(value); return value; }

bool HttpPostJson(string path, string body, string &response_text) {
   char data[];
   char result[];
   string headers = "Content-Type: application/json\r\nAuthorization: Bearer " + NodeSecret + "\r\n";
   int copied = StringToCharArray(body, data, 0, -1, CP_UTF8);
   if(copied > 0 && data[copied - 1] == 0) ArrayResize(data, copied - 1);
   string result_headers;
   ResetLastError();
   int code = WebRequest("POST", RuntimeUrl + path, headers, 20000, data, result, result_headers);
   if(code < 0) {
      PrintFormat("AX_FEEDER_WEBREQUEST_FAILED code=%d error=%d", code, GetLastError());
      return false;
   }
   response_text = CharArrayToString(result, 0, -1, CP_UTF8);
   PrintFormat("AX_FEEDER_HTTP code=%d path=%s", code, path);
   return code >= 200 && code < 300;
}

string JsonEscape(string value) {
   StringReplace(value, "\\", "\\\\");
   StringReplace(value, "\"", "\\\"");
   return value;
}

string BuildHeartbeat() {
   string currency = AccountInfoString(ACCOUNT_CURRENCY);
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   bool connected = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   bool trade_allowed = (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);
   bool expert_allowed = (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
   return StringFormat(
      "{\"account_scope\":\"%s\",\"login\":%I64d,\"currency\":\"%s\",\"balance\":%.10f,\"equity\":%.10f,\"terminal_connected\":%s,\"trade_allowed\":%s,\"expert_allowed\":%s}",
      JsonEscape(AccountScope), login, JsonEscape(currency), balance, equity,
      connected ? "true" : "false", trade_allowed ? "true" : "false", expert_allowed ? "true" : "false"
   );
}

string TimeframeText(ENUM_TIMEFRAMES tf) {
   switch(tf) {
      case PERIOD_M1: return "M1"; case PERIOD_M5: return "M5"; case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30"; case PERIOD_H1: return "H1"; case PERIOD_H4: return "H4";
      case PERIOD_D1: return "D1"; default: return EnumToString(tf);
   }
}

string BuildBarsJson(string symbol) {
   MqlRates rates[];
   int copied = CopyRates(symbol, Timeframe, 0, HistoricalBars, rates);
   if(copied <= 0) return "[]";
   ArraySetAsSeries(rates, false);
   string out = "[";
   for(int i = 0; i < copied; i++) {
      if(i > 0) out += ",";
      out += StringFormat(
         "{\"timestamp\":%I64d,\"open\":%.10f,\"high\":%.10f,\"low\":%.10f,\"close\":%.10f,\"tick_volume\":%I64d,\"spread\":%d}",
         (long)rates[i].time, rates[i].open, rates[i].high, rates[i].low, rates[i].close,
         (long)rates[i].tick_volume, (int)rates[i].spread
      );
   }
   out += "]";
   return out;
}

void SendHeartbeat() {
   string ignored;
   HttpPostJson("/xm/node/heartbeat", BuildHeartbeat(), ignored);
}

void SendHistoricalSnapshot() {
   string symbols[];
   int count = StringSplit(SymbolsCsv, ',', symbols);
   if(count <= 0) return;
   string snapshots = "[";
   bool first = true;
   for(int i = 0; i < count; i++) {
      string symbol = Trim(symbols[i]);
      if(symbol == "") continue;
      if(!SymbolSelect(symbol, true)) continue;
      string bars = BuildBarsJson(symbol);
      if(!first) snapshots += ",";
      first = false;
      snapshots += StringFormat(
         "{\"symbol\":\"%s\",\"timeframe\":\"%s\",\"bars\":%s,\"source\":\"MT5_COPYRATES\",\"read_only\":true}",
         JsonEscape(symbol), TimeframeText(Timeframe), bars
      );
   }
   snapshots += "]";
   string body = StringFormat(
      "{\"account_scope\":\"%s\",\"snapshots\":%s}",
      JsonEscape(AccountScope), snapshots
   );
   string ignored;
   HttpPostJson("/xm/node/market-data", body, ignored);
}

int OnInit() {
   if(NodeSecret == "") {
      Print("AX_FEEDER_NODE_SECRET_MISSING");
      return INIT_PARAMETERS_INCORRECT;
   }
   EventSetTimer(MathMax(5, TimerSeconds));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); }
void OnTick() {}

void OnTimer() {
   SendHeartbeat();
   SendHistoricalSnapshot();
}
