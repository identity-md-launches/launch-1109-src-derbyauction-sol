# DerbyAuction launch for SwarmDerby v2

This assignment prepares only `src/DerbyAuction.sol:DerbyAuction` for the
`evm_contracts` factory on Robinhood Chain (4663). All four files in `src/`
remain byte-identical to the supplied project. The existing constructor is
already nonpayable, takes supported static arguments, sets the explicit owner
and makes no external calls or dependency code checks. No critical or high
issue was reproduced, so no source, ABI, events, errors, constants or payout
math was changed. No transaction was broadcast.

## Changes and reasons for this assignment

- `test/DerbyAuctionLaunch.t.sol`: adds a CREATE2 deployment rehearsal with
  the exact IMD and v2 derby addresses, `$owner` represented by the test caller
  for both owner and studio, and a zero build fee. It deploys no token or game
  fixture. It checks absent dependencies, zero dependency calls, address
  prediction, the ownership event, constructor settings, usable owner access
  distinct from the factory, zero ETH, runtime size and forbidden opcodes.
  It also checks truncated arguments and nonpayable construction. This covers
  the supplied factory requirements without changing the constructor.
- `test/DerbyAuction.t.sol`: adds two offline regressions for imported info
  finding `736f0635a0681c1fab7f9057091af30ed874924f1d45f1b0d5003a8fb14b3905`,
  using the existing behavioral fixtures. They reproduce a day-20735 bonus
  at the reported settlement time, deployment isolation, empty-board carry
  on the old auction, rejection of reclaim after payment, and the exact
  reclaim boundary when unpaid. No additional token or game fixture is added.
- `DEPLOY.md`: updates the auction's constructor table and request example
  to the approved v2 address, distinguishes the old auction from the new
  deployment, and documents the old bonus and reclaim race. The game
  deployment instructions are marked historical.
- `HANDOFF.md`: directs this assignment to the auction handoff, so the
  previous game/site launch checklist is not mistaken for this launch's scope.
- `ADAPTATION.md`: records this assignment, the constructor handoff, audit
  disposition and validation. The previous game's adaptation is retained below
  as history, including its public modulus; it is not this deployment plan.

No build configuration, dependencies or other application contracts were
changed. No dependencies were installed. The manifest-writing step follows
this adaptation: **the existing `launch.json` describes the prior SwarmDerby
launch and must be replaced by that step**, with exactly one DerbyAuction
entry using the arguments below. This assignment does not write `launch.json`.

## Current constructor handoff

Deploy only `DerbyAuction`, with zero ETH and no initialization calls. The
ABI encoding is five static words (160 bytes), in this order:

| Position | Argument | ABI type | Value |
| --- | --- | --- | --- |
| 1 | `owner_` | `address` | `$owner` |
| 2 | `imd_` | `address` | `0x5F7Bb59365ce557C26dbcAa4EE9d39A4b95B7127` |
| 3 | `derby_` | `address` | `0x53d9aa0b925c5148bcc5f98f394872687f4c831c` |
| 4 | `studio_` | `address` | `$owner` |
| 5 | `buildFee_` | `uint256` | `0` |

Both `$owner` values resolve to the actual launch owner. No wallet address or
key is needed by this adaptation. SwarmDerby v2 (IMD launch #1103) is an
existing dependency, not another contract to deploy. Do not deploy HouseDraw,
DerbyOdds, a token, distributor or pool. The website must obtain the new
auction address from the confirmed deployment handoff.

## Imported audit disposition and review

**Info `736f0635…`: core behavior reproduced; two reported times corrected.**
The immutable derby selects which arcade board gets a bonus. With an empty
board, `payBonus` marks the auction paid and moves the whole bonus into that
auction contract's carry. It does not migrate the funds to v2, and reclaim
then reverts `WrongStatus`. The offline regressions confirm this and confirm
that a fresh v2-configured auction has no claim on the old auction's funds.
This is an operational migration note, not a code defect, so the contract
remains unchanged. The report's two absolute time claims did not reproduce:

- `1791504000 + 600` is still within theme day 20735. The empty v1 board
  remains open then. With no commits, it closes at `(20735 + 1) * 86400 =
  1791590400` (2026-10-10 00:00:00 UTC).
- `(20736 * 86400) + 7 days` is **1792195200**, not the report's
  **1792454400**. The contract rejects reclaim at the correct boundary and
  allows it one second later if still unpaid. The first regression run caught
  this arithmetic error in the imported note; the test and documentation were
  corrected, with no contract change.

Two scratch-only fork tests at the block below confirmed both corrected
boundaries and both terminal outcomes against the actual deployed v1 auction,
derby and IMD, without deploying fixtures or broadcasting. All state changes
in those checks occurred only in Foundry's local fork. Those network-dependent
checks are excluded from the delivered offline suite.

Read-only RPC checks at Robinhood block **83,719,154**, timestamp
**1791503980** (2026-10-08 23:59:40 UTC), confirmed the reported state:

- IMD has code, reports `IMD` and 18 decimals, and reports a 2e18 balance for
  old auction `0x0d81989ea1a4fdafb309ce738271d3bd659dab7b`.
- The old auction's `derby()` is v1
  `0xBa58BC6b5aCf8043DAEa2Bf1BF6C1c09cF84b03C`. Auction 20735's leader is
  `0xD4D1aeEf7b978ab7DbC947205BAFFfde01b41018`, amount and bonus are 2e18,
  settled is true, vetoed and paid are false, `carryIn` and `carry` are zero,
  and `settledAt` is 1791482897. Its arcade board was empty and not closed yet.
- The specified v2 derby has code, its `imd()` matches the supplied IMD
  address, `nextSwingId()` was zero, and `board(0, 20735)` returned empty
  arrays. Its `dayClosed(0, 20735)` returned false at that snapshot.

These are observations at that block, not a promise about later live state.
The operator must decide how to handle the v1 bonus during the transition.
If paid against an empty board, it stays in old carry until a later winning
auction on the old contract settles before its theme day. If left unpaid,
anyone may reclaim for the original bidder only when the timestamp is
**greater than 1792195200**; the first valid timestamp is **1792195201**
(2026-10-17 00:00:01 UTC). This is not a guaranteed refund: permissionless
`payBonus` and `reclaim` can race after grace. No migration or bonus transaction
was performed, and no operator choice is needed to construct the new auction.

Review covered the constructor, owner controls, bid/refund accounting,
settlement, carry, veto, reclaim, payout rounding and external calls. Owner
trust and accepted behavior remain: extensions stop at 19:00 UTC, fee and
studio are read at settlement, and reclaim can race payment. IMD transfer
availability and the immutable derby's board/closure are external
dependencies. Time gates use `block.timestamp`, not L2 block numbers.

## Current validation

- `forge build`: passed using the project's unchanged configuration, Forge
  1.8.3 and Solidity 0.8.26. Existing Forge lint warnings remain; no source
  changes were made to silence them.
- `forge test`: **150 passed, 0 failed, 0 skipped**, without FFI or network
  dependencies in the delivered tests. This includes all five new tests.
  The existing invariant campaign ran 256 sequences / 16,384 calls with zero
  reverts; all four invariants passed. Existing fuzz tests also passed.
- Two separate scratch-only fork tests passed against block 83,719,154,
  confirming the deployed v1 closure, empty-board carry, reclaim rejection
  after payment and the corrected reclaim boundary. The scratch fork test was
  excluded before the final ordinary build/test commands above.
- DerbyAuction runtime is **9,520 bytes**; init code with the five arguments
  is **10,125 bytes**, within the protected limits. The CREATE2 rehearsal's
  PUSH-aware scan found no DELEGATECALL, CALLCODE or SELFDESTRUCT.
- Compared the local DerbyAuction runtime to live v1 and the local SwarmDerby
  runtime to the specified live v2: both match after masking compiler-declared
  immutable references. DerbyAuction has no external library link references.
- Source hashes confirm all four `src/` files and `foundry.toml` are
  unchanged. The compiled DerbyAuction ABI is identical to the baseline.
  `launch.json` remains unchanged for the following manifest step.
- Parsed the current `DEPLOY.md` auction request and checked its single
  application, chain and constructor values against the brief. Diff checks
  pass; only the five documented files changed. No Slither/Mythril, browser
  E2E, live deployment, signing or live fund movement was performed.

---

# Historical: SwarmDerby v2 launch adaptation

The remaining notes describe the earlier game launch, not changes made in
this auction assignment.

This adaptation prepares only `src/SwarmDerby.sol:SwarmDerby` for the
`evm_contracts` factory. No live transaction was sent. DerbyAuction, tokens,
distributors and pools are not part of this launch. The following step writes
`launch.json`; this adaptation does not create it.

## Changes and reasons

- `src/SwarmDerby.sol`: replaced the dynamic constructor key argument with eight
  consecutive `bytes32` arguments. The factory supports static arguments only.
  Concatenating the eight words restores the exact 256-byte big-endian modulus
  before the original key validation, storage and event emission. Ownership
  still comes from `owner_`, not the factory. Construction remains nonpayable
  and makes no external calls or token code check.
- `src/SwarmDerby.sol`: added `NoHouseKey()` to the shared purchase path when
  the key is revoked. This implements the final task instruction to fix
  reproduced imported audit findings (low `da912675…`). Both purchase methods,
  in both leagues and through sessions, now reject before accounting or IMD
  transfers. A pending proposal does not itself block purchases; following
  revocation, purchases resume only after activation. This is the only runtime
  behavior change.
- `test/HouseKey.sol`, `test/SwarmDerby.t.sol` and
  `test/SwarmDerbyDraw.t.sol`: adapted deployment fixtures to the static
  constructor while retaining the existing dummy and RSA test keys. The
  constructor's former short-key test now checks even moduli and moduli without
  the top bit set; a missing constructor word is covered by the launch rehearsal.
  Dynamic proposal-key length tests remain. Added purchase rejection/recovery
  tests and extended the rotation test through the refund.
- `test/SwarmDerbyLaunch.t.sol`: added a zero-value CREATE2 rehearsal using the
  exact launch modulus, token address and prices, with no token fixture.
  It checks the predicted address, explicit ownership, initialization events,
  all launch settings, runtime size and forbidden opcodes. Further tests cover
  a reverting token dependency, truncated static arguments and nonpayable
  construction.
- `e2e/setup.py`: updated the existing local rehearsal's constructor encoding
  to eight static words and rejects a modulus of the wrong length. This script
  is not the production launch plan.
- `DEPLOY.md`: corrected the constructor handoff and documented revoked-key
  purchase rejection and key rotation operations.
- `ADAPTATION.md`: records the changes, audit dispositions and exact factory
  arguments for the next step.

All runtime function signatures, events, errors, constants, EIP-712 data,
`drawMessage`, splits, launch prices and payout math are unchanged.
`src/DerbyOdds.sol` and `src/HouseDraw.sol` remain byte-identical. Build
configuration and dependencies are unchanged; no dependencies were installed.

## Constructor handoff

Use these twelve arguments in this order. Arguments 5–12 are eight separate
`bytes32` values, not an array, dynamic bytes, or text. Concatenate their bytes
without reversing or padding to recover the modulus supplied in the brief.
Each key word is 66 characters including `0x`, within the stated 96-character
manifest argument limit; the complete ABI argument encoding is 384 bytes.

| Position | Argument | Value |
| --- | --- | --- |
| 1 | `owner_` | `$owner` (resolved by the launch service) |
| 2 | `imd_` | `0x5F7Bb59365ce557C26dbcAa4EE9d39A4b95B7127` |
| 3 | `singlePrice_` | `150000000000000000` |
| 4 | `packPrice_` | `500000000000000000` |
| 5 | `houseKey0_` | `0x9b7398ccc4834a29c3064efa2b3530e31022109a8dc6a654bfa878ae0059a2a2` |
| 6 | `houseKey1_` | `0xc3ac9f31916c0a320a2c179109e395905fc821aab91a1136523c1b90bce1536f` |
| 7 | `houseKey2_` | `0xe5c11ab65de79551875327766c99e74f9243761f0b3c8d323194bd7f3da77086` |
| 8 | `houseKey3_` | `0xe27991d5ac2e46ec41b36dc3e959b99dfd40e309277beda06980f5d5d59dd86f` |
| 9 | `houseKey4_` | `0x2d3d01738e7773bfada03634ac9d8611b31f274422bf36137afdf465a406d299` |
| 10 | `houseKey5_` | `0x433bf548042816d7aa6b6f69e007bc70d5acb0db4a5c8f19cecbaf31728faa39` |
| 11 | `houseKey6_` | `0x9b0b143d34eb956a2230fe75fdaed887cbd68f7154d1abfb62204e928b9c4e9b` |
| 12 | `houseKey7_` | `0x54ab9cc7bf171f27a16aa37d8a4a7a02f54b7ab2056befbbffcfbdb24506863d` |

Do not substitute a test owner or test key. The explicit `$owner` placeholder
is resolved by the launch service, as specified by the request.

## Imported audit disposition

- **Medium `98132ac6…`: reproduced and fixed.** The original compiled ABI
  has a fifth argument of type `bytes`. The provided key is 256 bytes
  (514 hex-string characters), conflicting with the supplied static-only
  factory rules and stated string limit. The local input does not include the
  manifest validator, so no claim is made to have executed that validator.
  The static-word CREATE2 test checks the actual replacement encoding.
- **Low `da912675…`: reproduced and fixed.** On the original code, a
  revoked-key purchase credited one turn and sent 0.06 IMD to the burn
  address; the contact swing then reverted `NoHouseKey()`. A scratch test
  reproduced this before the change. Permanent tests cover singles, packs,
  both leagues, sessions, unchanged balances/allowances/accounting on rejection,
  active-key proposals and recovery after activation.
- **Info `e63821e9…`: reproduced; runtime unchanged.** Permissionless
  activation invalidates an old-key signature, and expiration refunds the turn
  and arcade slot. Reproduced on the original code and retained in the
  extended rotation regression. One detail of the report is inaccurate:
  `house/house.mjs` checks the on-chain modulus approximately every 60 ticks
  to alert on a mismatch; it does not load a new signing key automatically.
  The operator must switch/restart the service with the matching key at
  activation. This is documented in `DEPLOY.md`.
- **Info `5d362f1c…`: coverage statement, not a defect.** Reviewed the three
  SwarmDerby source files and the relevant house service rotation behavior.
  No critical/high finding was reproduced. The imported invariant-fuzz results
  are another contributor's evidence, not checks rerun here. DerbyAuction is
  unchanged and outside the launch; its existing tests still run.

The accepted trust assumptions in the brief remain, including house-key
prediction/withholding, client-reported swing inputs, per-wallet arcade caps,
session consent without deadlines and purchases without maxCost. The external
IMD token and Robinhood's live modexp precompile were not verified against a
live RPC in this local adaptation; the deployer's live simulation remains
necessary. All local RSA verification uses Foundry's EVM modexp precompile.

## Validation

- Original baseline: `forge test` passed all 117 tests, without FFI.
- Final `forge build`: passed with the project's unchanged configuration;
  compiler mutability and Forge lint warnings remain.
- Final `forge test`: **125 passed, 0 failed, 0 skipped**, without FFI. This
  includes the original 117 tests (with constructor fixture updates), four
  purchase regressions and four launch tests. The three existing fuzz tests
  each ran 256 cases. An initially incorrect arcade-slot expectation in the
  extended rotation test was corrected: both swings occur on the same UTC day,
  so refunding the second leaves the first slot consumed.
- Compared compiled ABIs before and after: every non-constructor entry is
  identical. Verified the new constructor has two addresses, two uint256s and
  eight bytes32s, and remains nonpayable.
- Runtime size: **17,692 bytes**, below 24,576. Both the CREATE2 test and an
  independent PUSH-aware bytecode scan found no DELEGATECALL, CALLCODE or
  SELFDESTRUCT opcodes.
- Byte comparisons confirmed `DerbyOdds.sol`, `HouseDraw.sol`,
  `DerbyAuction.sol` and `foundry.toml` are unchanged. Source comparison from
  the end of the constructor confirms the sole runtime change is the purchase
  guard.
- Checked `e2e/setup.py` syntax and executed its revised encoding statements
  with `cast abi-encode`: exactly 384 bytes matching the supplied modulus;
  short, long and malformed hex keys reject. No devnet token was deployed.
- Verified the eight documented key words concatenate to the exact launch
  modulus and checked the diff for whitespace errors. No Slither/Mythril,
  browser E2E session, live-chain deployment or live-chain token check ran.
