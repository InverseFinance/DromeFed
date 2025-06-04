// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/DromeFarmer.sol";

contract DeployDromeFarmer is Script {
    function run() external {
        // Load private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Contract addresses - replace with actual addresses for your target network
        address chair = 0x7FD13dD8d653F32Bd5E2B6bAbb4978507960A0dA;
        address guardian = 0x09aF9E0D4932604913F7Cd77aD5e157F0BC700eA;
        address treasury = 0x586CF50c2874f3e3997660c0FD0996B090FB9764;
        address gov = 0x09aF9E0D4932604913F7Cd77aD5e157F0BC700eA;
        DromeFarmer.Admin memory admin = DromeFarmer.Admin(chair, guardian, treasury, gov);
        address cctpBridge = 0x1682Ae6375C4E4A97e4B583BC394c861A46D8962;
        address l1Fed = 0x4F38991402cE398412C2010B2Ae9CC83B194504f;
        address dola = 0x4621b7A9c75199271F773Ebd9A499dbd165c3191;
        address usdc = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;
        address nusdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        IChainlinkPriceFeed usdcPriceFeed = IChainlinkPriceFeed(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B);
        IRouter router = IRouter(0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43);
        IGauge dolaGauge = IGauge(0xCCff5627cd544b4cBb7d048139C1A6b6Bde67885);

        // Deploy DromeFarmer contract
        DromeFarmer dromeFarmer =
            new DromeFarmer(admin, cctpBridge, l1Fed, dola, usdc, nusdc, usdcPriceFeed, router, dolaGauge);

        // Log the deployed contract address
        console.log("DromeFarmer deployed at:", address(dromeFarmer));

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
