# DerbyAuction test coverage

The existing `DerbyAuctionLaunch.t.sol` rehearses only DerbyAuction with the exact
IMD and SwarmDerby v2 addresses, explicit owner/studio, and zero build fee on an
empty chain. The existing `DerbyAuction.t.sol` retains its failure-path, boundary,
callback, migration, and local game integration tests.

`DerbyAuctionInvariant.t.sol` adds a Foundry handler with six actors and 32 auction
days. It randomizes bids (including self raises and anti-snipe timing), monotonic
time advances, early/late settlement, veto, bonus payment, reclaim, withdrawal,
fee/studio changes, blocked/malformed token transfers, no-return token transfers,
and unsolicited donations. Expected application failures are handled explicitly;
unexpected errors and panics fail the campaign. Handler reverts fail the campaign.

Properties checked after each random call:

- Custody equals outstanding bids, unpaid bonuses, carry, all actor
  refund credits, and independently tracked donations.
- Total balances across the auction and actors equal independently tracked minting.
- Settled, paid, and vetoed states never reopen; resolved bonuses are zero, and
  the closing time stays between 18:00 and the accepted 19:00 UTC extension cap.

A deterministic handler test ensures bids, blocked refund credits, withdrawal,
settlement, veto, empty-board carry, inherited carry, and reclaim actually execute.
Two 1,000-run fuzz properties check the minimal whole-wei 5% raise by inequalities
and independently calculated payouts for boards of zero through four players,
including reverted, false-returning, and malformed-returning recipient transfers.
The invariant campaign uses 256 runs of 128 calls, checking all three properties
after each call, configured inline.

The new harness deploys only the auction application and a test handler. It reuses
the existing token adapter runtime via `vm.etch` at the specified IMD address;
it does not deploy a token, distributor, pool, or game. It mocks only league-zero
`dayClosed` and `board` at the specified v2 address, with closure no earlier than
the next UTC midnight. These are offline adapters, not deployed chain contracts.
No RPC, environment mutation, FFI, or new dependency is required.

Live IMD transfer behavior and the actual v2 board at a pinned Robinhood Chain
block remain to be checked on a fork; this offline suite does not establish them.
No production source, launch manifest, or configuration is changed.
