#property strict
#property version   "1.3"
#property description "AX XM Execution Bridge - authenticated execution adapter only"

// Execution adapter only: no trading strategy, no deposits/withdrawals,
// no credential export, and no order creation from market ticks.
// Live execution is fail-closed and disabled by default.

input bool   LiveExecutionEnabled = false;
input string BridgeEndpoint       = ""; // Base URL, e.g. https://ax-control-runtime.aerismusic8.workers.dev
input string BridgeToken          = ""; // Store locally in MT5; never commit to Git.
input string AccountScope         = "XM_MICRO_K_DESIGNATED_ACCOUNT";
input int    PollSeconds          = 5;
input int    RequestTimeoutMs     = 1500;

bool g_kill_switch = true;

bool IsAllowedOperation(const string operation)
{
   if(operation == "GET_ACCOUNT_STATE") return true;
   if(operation == "GET_POSITIONS") return true;
   if(operation == "GET_SYMBOL_STATE") return true;
   if(operation == "SUBMIT_ORDER") return true;
   if(operation == "MODIFY_POSITION") return true;
   if(operation == "CLOSE_POSITION") return true;
   return false;
}

bool IsBlockedOperation(const string operation)
{
   if(operation == "DEPOSIT") return true;
   if(operation == "WITHDRAW") return true;
   if(operation == "CHANGE_ACCOUNT_SETTINGS") return true;
   if(operation == "EXPORT_CREDENTIALS") return true;
   return false;
}

bool ValidateAccountScope()
{
   return AccountScope == "XM_MICRO_K_DESIGNATED_ACCOUNT";
}

bool CanSubmitOrders()
{
   if(!LiveExecutionEnabled) return false;
   if(g_kill_switch) return false;
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)) return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT)) return false;
   if(BridgeEndpoint == "") return false;
   if(BridgeToken == "") return false;
   return true;
}

string AccountStateJson()
{
   string json = "{";
   json += "\"account_scope\":\"" + AccountScope + "\",";
   json += "\"login\":" + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) + ",";
   json += "\"currency\":\"" + AccountInfoString(ACCOUNT_CURRENCY) + "\",";
   json += "\"balance\":" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2) + ",";
   json += "\"equity\":" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2) + ",";
   json += "\"terminal_connected\":" + (TerminalInfoInteger(TERMINAL_CONNECTED) ? "true" : "false") + ",";
   json += "\"trade_allowed\":" + (AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) ? "true" : "false") + ",";
   json += "\"expert_allowed\":" + (AccountInfoInteger(ACCOUNT_TRADE_EXPERT) ? "true" : "false");
   json += "}";
   return json;
}

int PostJson(const string url, const string body, string &response)
{
   if(url == "" || BridgeToken == "") return -1;

   string request_headers = "Content-Type: application/json\r\n";
   request_headers += "Authorization: Bearer " + BridgeToken + "\r\n";
   string response_headers = "";
   char payload[], result[];
   StringToCharArray(body, payload, 0, WHOLE_ARRAY, CP_UTF8);
   // StringToCharArray appends a terminating NUL. Remove it so the HTTP
   // body is exactly the JSON document expected by the Worker parser.
   int payload_size = ArraySize(payload);
   if(payload_size > 0 && payload[payload_size - 1] == 0)
      ArrayResize(payload, payload_size - 1);

   ResetLastError();
   int status = WebRequest("POST", url, request_headers, RequestTimeoutMs,
                           payload, ArraySize(payload), result, response_headers);
   if(status == -1)
   {
      Print("AX XM Bridge WebRequest error=", GetLastError());
      return -1;
   }
   response = CharArrayToString(result, 0, -1, CP_UTF8);
   if(status < 200 || status >= 300)
   {
      Print("AX XM Bridge HTTP status=", status, " response=", response);
   }
   return status;
}

void PublishHeartbeat()
{
   if(BridgeEndpoint == "" || BridgeToken == "") return;

   string response;
   string body = "{\"account_scope\":\"" + AccountScope + "\",";
   body += "\"login\":" + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) + ",";
   body += "\"currency\":\"" + AccountInfoString(ACCOUNT_CURRENCY) + "\",";
   body += "\"balance\":" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2) + ",";
   body += "\"equity\":" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2) + ",";
   body += "\"terminal_connected\":" + (TerminalInfoInteger(TERMINAL_CONNECTED) ? "true" : "false") + ",";
   body += "\"trade_allowed\":" + (AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) ? "true" : "false") + ",";
   body += "\"expert_allowed\":" + (AccountInfoInteger(ACCOUNT_TRADE_EXPERT) ? "true" : "false") + "}";

   int status = PostJson(BridgeEndpoint + "/xm/node/heartbeat", body, response);
   if(status >= 200 && status < 300)
      Print("AX XM Bridge heartbeat HTTP status=", status);
}

void OnTimer()
{
   // Heartbeat only. Market ticks cannot create orders.
   // Command execution remains disabled until a future, separately verified gate.
   PublishHeartbeat();
}

int OnInit()
{
   if(!ValidateAccountScope())
      return INIT_FAILED;

   if(PollSeconds < 1 || RequestTimeoutMs < 100)
      return INIT_PARAMETERS_INCORRECT;

   // Fail closed: this scaffold cannot enable live trading itself.
   g_kill_switch = true;

   if(BridgeEndpoint == "")
      Print("AX XM Bridge: endpoint not configured; disconnected state.");

   if(!LiveExecutionEnabled)
      Print("AX XM Bridge: LIVE EXECUTION DISABLED.");

   EventSetTimer(PollSeconds);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTick()
{
   // Deliberately empty. Market ticks cannot trigger orders.
}
