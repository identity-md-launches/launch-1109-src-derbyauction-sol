// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DerbyAuction} from "../src/DerbyAuction.sol";

/// Test-only factory; deploys just the auction, without dependency fixtures.
contract AuctionLaunchProbe {
    function deploy(bytes memory code, bytes32 salt) external returns (DerbyAuction auction) {
        address deployed;
        assembly ("memory-safe") {
            deployed := create2(0, add(code, 32), mload(code), salt)
        }
        require(deployed != address(0), "deployment failed");
        return DerbyAuction(deployed);
    }
}

contract DerbyAuctionLaunchTest is Test {
    address constant IMD = 0x5F7Bb59365ce557C26dbcAa4EE9d39A4b95B7127;
    address constant DERBY_V2 = 0x53d9aA0b925c5148BCC5F98f394872687F4c831C;

    function _initCode() internal view returns (bytes memory) {
        // The test contract represents $owner; production resolves it through the launch service.
        bytes memory args = abi.encode(address(this), IMD, DERBY_V2, address(this), uint256(0));
        assertEq(args.length, 5 * 32);
        return bytes.concat(type(DerbyAuction).creationCode, args);
    }

    function test_factoryDeploysAuctionWithExactV2ArgumentsOnEmptyChain() public {
        vm.chainId(4663);
        assertEq(IMD.code.length, 0);
        assertEq(DERBY_V2.code.length, 0);
        vm.expectCall(IMD, bytes(""), uint64(0));
        vm.expectCall(DERBY_V2, bytes(""), uint64(0));

        AuctionLaunchProbe factory = new AuctionLaunchProbe();
        bytes memory code = _initCode();
        assertLe(code.length, 49_152);
        bytes32 salt = keccak256("DerbyAuction SwarmDerby v2 launch rehearsal");
        address predicted = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(code)))))
        );
        vm.expectEmit(true, true, false, true, predicted);
        emit DerbyAuction.OwnershipTransferred(address(0), address(this));
        DerbyAuction auction = factory.deploy(code, salt);

        assertEq(address(auction), predicted);
        assertEq(auction.owner(), address(this));
        assertEq(auction.studio(), address(this));
        assertEq(address(auction.imd()), IMD);
        assertEq(address(auction.derby()), DERBY_V2);
        assertEq(auction.buildFee(), 0);
        assertEq(auction.carry(), 0);
        assertEq(auction.pendingOwner(), address(0));
        assertEq(address(auction).balance, 0);
        assertEq(IMD.code.length, 0);
        assertEq(DERBY_V2.code.length, 0);

        vm.prank(address(factory));
        vm.expectRevert(DerbyAuction.NotOwner.selector);
        auction.setBuildFee(1 ether);
        auction.setBuildFee(1 ether);
        assertEq(auction.buildFee(), 1 ether);

        bytes memory runtime = address(auction).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden application opcode");
        }
    }

    function test_factoryRejectsTruncatedConstructorArguments() public {
        AuctionLaunchProbe factory = new AuctionLaunchProbe();
        bytes memory code = _initCode();
        assembly ("memory-safe") { mstore(code, sub(mload(code), 32)) }
        vm.expectRevert("deployment failed");
        factory.deploy(code, keccak256("missing buildFee argument"));
    }

    function test_constructorRejectsETH() public {
        bytes memory code = _initCode();
        vm.deal(address(this), 1);
        address deployed;
        assembly ("memory-safe") { deployed := create(1, add(code, 32), mload(code)) }
        assertEq(deployed, address(0));
        assertEq(address(this).balance, 1);
    }
}
