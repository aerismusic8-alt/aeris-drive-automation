#property strict
#property version   "1.0"
#property description "AX XM Execution Bridge - execution adapter only"

// This EA is intentionally a transport/execution adapter.
// It does NOT contain a trading strategy and does NOT manage deposits/withdrawals.
// Live execution remains disabled until the external readiness gates are satisfied.

input bool LiveExecutionEnabled = false;
input string BridgeEndpoint = "";
input string AccountScope = "XM_MICRO_K_DESIGNATED_ACCOUNT";

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
   // Account identity must be verified by the bridge handshake.
   // Never infer the target account from credentials embedded in code.
   return AccountScope == "XM_MICRO_K_DESIGNATED_ACCOUNT";
}

int OnInit()
{
   if(!ValidateAccountScope())
      return INIT_FAILED;

   if(BridgeEndpoint == "")
      Print("AX XM Bridge: endpoint not configured; running in non-connected state.");

   if(!LiveExecutionEnabled)
      Print("AX XM Bridge: LIVE EXECUTION DISABLED.");

   return INIT_SUCCEEDED;
}

void OnTick()
{
   // Deliberately empty until the authenticated command transport is implemented.
   // The EA must never create an order merely because a tick arrived.
}
