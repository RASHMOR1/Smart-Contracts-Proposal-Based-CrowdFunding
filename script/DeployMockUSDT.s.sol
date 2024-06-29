// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";

import {MockUsdtContract} from "../test/mock/MockUsdtContract.sol";

contract DeployMockUSDTContract is Script {
    function run() external returns (MockUsdtContract) {
        vm.startBroadcast();
        MockUsdtContract usdtTokenAddress =
            new MockUsdtContract(1000000000000000000000000000000000000000000, msg.sender);
        vm.stopBroadcast();
        return usdtTokenAddress;
    }
}

// forge script script/DeployMockUSDT.s.sol:DeployMockUSDTContract --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify
