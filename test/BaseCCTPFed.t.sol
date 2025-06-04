pragma solidity ^0.8.20;

import {FedCCTPProxyMainnetTest, SuperChainCCTPFed} from "test/FedCCTPProxyMainnetTest.sol";

contract BaseCCTPFedTest is FedCCTPProxyMainnetTest {
    address public constant baseBridge =
        address(0x3154Cf16ccdb4C6d922629664174b904d80F2C35);
    address public constant DOLA_BASE =
        0x4621b7A9c75199271F773Ebd9A499dbd165c3191;
    address public constant USDC_BASE =
        0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;
    uint32 public constant BASE_CCTP_DOMAIN = 6;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 21230271);

        initialize(baseBridge, DOLA_BASE, USDC_BASE, BASE_CCTP_DOMAIN);
    }
}
