# XM Bridge Live Enable Checklist

Do not enable live execution until every item is verified.

- [ ] MT5 installed on the dedicated Windows execution node.
- [ ] XM Micro account logged into MT5 on that node.
- [ ] Account number/server identity verified against the designated account record.
- [ ] EA attached to the correct XM symbol/account.
- [ ] Local command transport authenticated.
- [ ] Read-only account-state request succeeds.
- [ ] Position reconciliation succeeds.
- [ ] Symbol contract (digits, point, minimum volume, volume step, stops level) is discovered from MT5 rather than hard-coded.
- [ ] Order validation rejects malformed or out-of-scope requests.
- [ ] Idempotency test proves the same request cannot create duplicate orders.
- [ ] Broker rejection handling is tested.
- [ ] Timeout/unknown-result reconciliation is tested before retry.
- [ ] Stop-loss is mandatory for every new position unless an explicitly approved strategy contract says otherwise.
- [ ] Kill switch is tested and confirmed to prevent new orders.
- [ ] Deposit and withdrawal operations are unreachable from the bridge.
- [ ] Trading strategy and risk engine are connected and independently verified.
- [ ] K live-enable record exists.

Until all boxes are checked, `LiveExecutionEnabled` MUST remain `false`.
