pragma solidity ^0.8.20;

import {FedCCTPProxyMainnetTest, SuperChainCCTPFed} from "test/FedCCTPProxyMainnetTest.sol";

contract OptiCCTPFedTest is FedCCTPProxyMainnetTest {
    address public constant optiBridge =
        address(0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1);
    address public constant DOLA_OPTI =
        0x8aE125E8653821E851F12A49F7765db9a9ce7384;
    address public constant USDC_OPTI =
        0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    uint32 public constant OPTIMISM_CCTP_DOMAIN = 2;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));

        initialize(optiBridge, DOLA_OPTI, USDC_OPTI, OPTIMISM_CCTP_DOMAIN);
    }
}
