// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {MainContract} from "../src/MainContract.sol";
import {MockUsdtContract} from "../test/mock/MockUsdtContract.sol";

contract DeployMainContract is Script {
    function run() external returns (MainContract) {
        vm.startBroadcast();
        MockUsdtContract usdtTokenAddress =
            new MockUsdtContract(1000000000000000000000000000000000000000000, msg.sender);
        MainContract mainContract = new MainContract(address(usdtTokenAddress));

        //MainContract mainContract = new MainContract(address(0xc00d792Ae11F44090Cb285be227756e3D6e71692));
        vm.stopBroadcast();
        return mainContract;
    }
}

//forge script --chain sepolia script/DeployMainContract.s.sol:DeployMainContract --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify -vvvv
