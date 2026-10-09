// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DerbyAuction, ISwarmDerby} from "src/DerbyAuction.sol";
import {IERC20} from "src/SwarmDerby.sol";
import {AuctionToken} from "./DerbyAuction.t.sol";

/// Offline adapter: reuse the existing token mock's runtime, without deploying a token.
/// Only the two documented arcade board selectors are mocked at the immutable derby address.
contract AuctionSequenceHandler is Test {
    uint256 public constant FIRST = 20_400;
    uint256 public constant DAYS = 32;
    address public constant IMD = 0x5F7Bb59365ce557C26dbcAa4EE9d39A4b95B7127;
    address public constant DERBY = 0x53d9aA0b925c5148BCC5F98f394872687F4c831C;
    DerbyAuction public sale;
    AuctionToken public token = AuctionToken(IMD);
    address[6] public actors;
    uint256 public minted;
    uint256 public donations;
    uint256 public successfulBids;
    uint256 public successfulSettlements;
    uint256 public successfulResolutions;
    uint256 public successfulWithdrawals;
    mapping(uint256 => bool) public wasSettled;
    mapping(uint256 => bool) public wasPaid;
    mapping(uint256 => bool) public wasVetoed;

    constructor() {
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("auction actor ", vm.toString(i)));
        }
        sale = new DerbyAuction(address(this), IERC20(IMD), ISwarmDerby(DERBY), actors[3], 0);
    }

    function state(uint256 day) public view returns (DerbyAuction.Auction memory a) {
        (a.leader, a.amount, a.end, a.settled, a.vetoed, a.paid, a.bonus) = sale.auction(day);
    }

    function advance(uint256 seconds_) external {
        vm.warp(block.timestamp + bound(seconds_, 0, 12 hours));
    }

    function bid(uint256 actorSeed, uint256 extra, bool snipe) external {
        uint256 day = sale.openDay();
        if (day < FIRST || day >= FIRST + DAYS) return;
        if (snipe) vm.warp(state(day).end - 1);
        uint256 amount = sale.minNextBid(day) + bound(extra, 0, 10 ether);
        address who = actors[actorSeed % 3];
        token.mint(who, amount);
        minted += amount;
        vm.prank(who);
        token.approve(address(sale), amount);
        DerbyAuction.Answers memory a = DerbyAuction.Answers("Comet", 3, 5, 5, "Theme", "");
        vm.prank(who);
        if (_call(day, abi.encodeCall(sale.bid, (day, amount, a)))) ++successfulBids;
    }

    function settle(uint256 daySeed, bool recent) external {
        uint256 day = FIRST + daySeed % DAYS;
        if (recent) {
            uint256 open = sale.openDay();
            day = open > FIRST ? open - 1 : FIRST;
            if (day >= FIRST + DAYS) day = FIRST + DAYS - 1;
        }
        if (_call(day, abi.encodeCall(sale.settle, (day)))) ++successfulSettlements;
    }

    function resolve(uint256 daySeed, uint256 mode, uint256 countSeed) external {
        uint256 day = FIRST + daySeed % DAYS;
        bytes memory data;
        mode %= 3;
        if (mode == 0) data = abi.encodeCall(sale.veto, (day));
        if (mode == 1) {
            // SwarmDerby never closes a board before the end of its theme day.
            vm.mockCall(
                DERBY,
                abi.encodeCall(ISwarmDerby.dayClosed, (uint8(0), day)),
                abi.encode(block.timestamp >= (day + 1) * 1 days)
            );
            uint256 count = countSeed % 5;
            address[] memory winners = new address[](count);
            uint256[] memory scores = new uint256[](count);
            for (uint256 i; i < count; ++i) {
                winners[i] = actors[i];
                scores[i] = 100 - i;
            }
            vm.mockCall(DERBY, abi.encodeCall(ISwarmDerby.board, (uint8(0), day)), abi.encode(winners, scores));
            data = abi.encodeCall(sale.payBonus, (day));
            vm.prank(actors[4]);
        }
        if (mode == 2) data = abi.encodeCall(sale.reclaim, (day));
        if (_call(day, data)) ++successfulResolutions;
    }

    function withdraw(uint256 actorSeed) external {
        address who = actors[actorSeed % actors.length];
        vm.prank(who);
        (bool ok, bytes memory result) = address(sale).call(abi.encodeCall(sale.withdrawRefund, ()));
        if (ok) ++successfulWithdrawals;
        else _expectedFailure(result);
    }

    function configure(uint256 feeSeed, uint256 actorSeed, uint8 failureMode, bool noReturn) external {
        sale.setBuildFee(bound(feeSeed, 0, 1 ether));
        sale.setStudio(actors[3 + actorSeed % 3]);
        token.setFailure(actors[actorSeed % actors.length], uint8(bound(failureMode, 0, 4)));
        token.setNoReturn(noReturn);
    }

    function donate(uint256 amount) external {
        amount = bound(amount, 0, 10 ether);
        token.mint(address(sale), amount);
        minted += amount;
        donations += amount;
    }

    function _call(uint256 day, bytes memory data) internal returns (bool ok) {
        bytes memory result;
        (ok, result) = address(sale).call(data);
        if (!ok) _expectedFailure(result);
        DerbyAuction.Auction memory a = state(day);
        assertTrue(!wasSettled[day] || a.settled, "settlement reopened");
        assertTrue(!wasPaid[day] || a.paid, "paid state reopened");
        assertTrue(!wasVetoed[day] || a.vetoed, "veto state reopened");
        wasSettled[day] = a.settled;
        wasPaid[day] = a.paid;
        wasVetoed[day] = a.vetoed;
    }

    function _expectedFailure(bytes memory result) internal pure {
        require(result.length == 4, "unexpected revert data or panic");
        bytes4 selector = bytes4(result);
        require(
            selector == DerbyAuction.BidClosed.selector || selector == DerbyAuction.WrongStatus.selector
                || selector == DerbyAuction.TooEarly.selector || selector == DerbyAuction.DayNotClosed.selector
                || selector == DerbyAuction.NoRefund.selector || selector == DerbyAuction.TransferFailed.selector,
            "unexpected auction failure"
        );
    }
}

/// @dev Counts persist in source because the verifier supplies its own forge command.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract DerbyAuctionInvariantTest is StdInvariant, Test {
    AuctionSequenceHandler internal handler;
    DerbyAuction internal sale;
    AuctionToken internal token;

    function setUp() public {
        vm.warp((20_400 - 2) * 1 days + 18 hours);
        vm.etch(0x5F7Bb59365ce557C26dbcAa4EE9d39A4b95B7127, vm.getDeployedCode("DerbyAuction.t.sol:AuctionToken"));
        handler = new AuctionSequenceHandler();
        sale = handler.sale();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = handler.advance.selector;
        selectors[1] = handler.bid.selector;
        selectors[2] = handler.settle.selector;
        selectors[3] = handler.resolve.selector;
        selectors[4] = handler.withdraw.selector;
        selectors[5] = handler.configure.selector;
        selectors[6] = handler.donate.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    function invariant_custodyEqualsAllOutstandingObligationsAndDonations() public view {
        uint256 owed = sale.carry() + handler.donations();
        for (uint256 i; i < 6; ++i) {
            owed += sale.refunds(handler.actors(i));
        }
        for (uint256 day = handler.FIRST(); day < handler.FIRST() + handler.DAYS(); ++day) {
            DerbyAuction.Auction memory a = handler.state(day);
            owed += a.settled ? a.bonus : a.amount;
        }
        assertEq(token.balanceOf(address(sale)), owed, "auction must fully back all liabilities");
    }

    function invariant_tokenSupplyIsConserved() public view {
        uint256 total = token.balanceOf(address(sale));
        for (uint256 i; i < 6; ++i) {
            total += token.balanceOf(handler.actors(i));
        }
        assertEq(total, handler.minted(), "refunds and payouts cannot create or destroy value");
    }

    function invariant_terminalStatesAndExtensionBound() public view {
        for (uint256 day = handler.FIRST(); day < handler.FIRST() + handler.DAYS(); ++day) {
            DerbyAuction.Auction memory a = handler.state(day);
            assertTrue(!handler.wasSettled(day) || a.settled);
            assertTrue(!handler.wasPaid(day) || a.paid);
            assertTrue(!handler.wasVetoed(day) || a.vetoed);
            if (a.paid || a.vetoed) {
                assertTrue(a.settled);
                assertEq(a.bonus, 0);
            }
            assertFalse(a.paid && a.vetoed);
            assertGe(a.end, (day - 1) * 1 days + 18 hours);
            assertLe(a.end, (day - 1) * 1 days + 19 hours);
        }
    }

    function test_handlerExercisesCarryCreditWithdrawalAndTerminalPaths() public {
        handler.bid(0, 0, false);
        handler.configure(1 ether, 0, 1, false);
        handler.bid(1, 0, false); // Alice's outbid refund is blocked.
        assertEq(sale.refunds(handler.actors(0)), 2 ether);
        handler.advance(12 hours);
        handler.advance(12 hours);
        handler.settle(0, false);
        handler.resolve(0, 0, 0); // Veto before the theme day.
        handler.configure(0, 0, 0, true);
        handler.withdraw(0);
        handler.bid(2, 0, false);
        handler.advance(12 hours);
        handler.advance(12 hours);
        handler.settle(1, false);
        handler.advance(12 hours);
        handler.advance(12 hours);
        handler.advance(6 hours);
        handler.resolve(1, 1, 0); // Empty board becomes carry.
        assertGt(sale.carry(), 0);
        handler.bid(0, 0, false);
        handler.advance(12 hours);
        handler.advance(6 hours);
        handler.settle(3, false);
        assertGt(sale.carryIn(handler.FIRST() + 3), 0);
        for (uint256 i; i < 20; ++i) {
            handler.advance(12 hours);
        }
        handler.resolve(3, 2, 0); // Reclaim returns the bid, preserves inherited carry.
        assertEq(handler.successfulBids(), 4);
        assertEq(handler.successfulSettlements(), 3);
        assertEq(handler.successfulResolutions(), 3);
        assertEq(handler.successfulWithdrawals(), 1);
        invariant_custodyEqualsAllOutstandingObligationsAndDonations();
        invariant_tokenSupplyIsConserved();
        invariant_terminalStatesAndExtensionBound();
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_nextBidIsTheSmallestWholeWeiFivePercentRaise(uint256 lead) public {
        uint256 day = handler.FIRST();
        lead = bound(lead, 2 ether, type(uint128).max);
        address bidder = handler.actors(0);
        token.mint(bidder, lead);
        vm.prank(bidder);
        token.approve(address(sale), lead);
        DerbyAuction.Answers memory a = DerbyAuction.Answers("a", 0, 0, 0, "b", "");
        vm.prank(bidder);
        sale.bid(day, lead, a);
        uint256 next = sale.minNextBid(day);
        // Inequalities test the economic rule without reproducing _bps or its rounding code.
        assertGe(next * 20, lead * 21);
        assertLt((next - 1) * 20, lead * 21);
        vm.expectRevert(DerbyAuction.BidTooLow.selector);
        sale.bid(day, next - 1, a);
        assertEq(handler.state(day).amount, lead);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_payoutConservesBonusForEveryBoardSizeAndFailedRecipient(
        uint256 bidAmount,
        uint256 fee,
        uint8 boardSize,
        uint8 failedIndex,
        uint8 failureMode
    ) public {
        uint256 day = handler.FIRST();
        bidAmount = bound(bidAmount, 2 ether, type(uint128).max);
        fee = bound(fee, 0, 1 ether);
        uint256 count = bound(boardSize, 0, 4);
        uint256 fail = bound(failedIndex, 0, 3);
        failureMode = uint8(bound(failureMode, 0, 4));
        address bidder = handler.actors(0);
        token.mint(bidder, bidAmount);
        vm.prank(bidder);
        token.approve(address(sale), bidAmount);
        vm.prank(bidder);
        sale.bid(day, bidAmount, DerbyAuction.Answers("a", 0, 0, 0, "b", ""));
        handler.configure(fee, 0, 0, false);
        vm.warp((day - 1) * 1 days + 18 hours);
        sale.settle(day);
        vm.warp((day + 1) * 1 days);
        address[] memory board = new address[](count);
        uint256[] memory scores = new uint256[](count);
        uint256[4] memory beforeBalances;
        for (uint256 i; i < 4; ++i) {
            beforeBalances[i] = token.balanceOf(handler.actors(i));
            if (i < count) board[i] = handler.actors(i);
        }
        vm.mockCall(handler.DERBY(), abi.encodeCall(ISwarmDerby.dayClosed, (uint8(0), day)), abi.encode(true));
        vm.mockCall(handler.DERBY(), abi.encodeCall(ISwarmDerby.board, (uint8(0), day)), abi.encode(board, scores));
        token.setFailure(handler.actors(fail), failureMode);
        uint256 bonus = bidAmount - fee;
        uint256 tip = count == 0 ? 0 : bonus / 200;
        uint256 rest = bonus - tip;
        uint256[3] memory prizes = [rest * 3 / 5, rest / 4, rest * 3 / 20];
        uint256 distributed = tip;
        vm.prank(handler.actors(4));
        sale.payBonus(day);
        for (uint256 i; i < 4; ++i) {
            uint256 expected = i < count && i < 3 ? prizes[i] : 0;
            if (i == fail && failureMode != 0) expected = 0;
            assertEq(token.balanceOf(handler.actors(i)) - beforeBalances[i], expected);
            distributed += expected;
        }
        assertEq(token.balanceOf(handler.actors(4)), tip);
        assertEq(sale.carry(), bonus - distributed);
        assertEq(token.balanceOf(address(sale)), sale.carry());
        assertEq(handler.state(day).bonus, 0);
        vm.expectRevert(DerbyAuction.WrongStatus.selector);
        sale.payBonus(day);
        vm.expectRevert(DerbyAuction.WrongStatus.selector);
        sale.reclaim(day);
    }
}
