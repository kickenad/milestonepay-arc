// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {MilestonePay, IERC20} from "../src/MilestonePay.sol";

/// Usage (key is read from the environment or a keystore, never hard-coded):
///   forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --account <keystore-name>
/// USDC ERC-20 interface is 0x3600...0000 on both Arc testnet and Arc mainnet.
contract Deploy is Script {
    address constant ARC_USDC = 0x3600000000000000000000000000000000000000;

    function run() external returns (MilestonePay pay) {
        vm.startBroadcast();
        pay = new MilestonePay(IERC20(ARC_USDC));
        vm.stopBroadcast();
        console2.log("MilestonePay deployed at", address(pay));
    }
}
