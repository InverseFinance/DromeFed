// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IDola} from "src/interfaces/IDola.sol";
import {MockExchangeProxy} from "test/mocks/MockExchangeProxy.sol";
import {Test} from "forge-std/Test.sol";
import {SuperChainCCTPFed, IChainlinkPriceFeed} from "src/SuperChainCCTPFed.sol";

abstract contract FedCCTPProxyMainnetTest is Test {
    //Tokens
    IDola public DOLA = IDola(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address l1BridgeAddr;
    MockExchangeProxy exchangeProxy;

    //EOAs
    address user = address(0x69);
    address chair = address(0xB);
    address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    //Numbas
    uint dolaAmount = 1_000_00e18;
    uint usdcAmount = 1_000_00e6;

    //Feds
    SuperChainCCTPFed fed;

    error OnlyChair();
    error OnlyGov();
    error SlippageTooHigh();
    error ZeroAddressParameter();
    error InvalidDepegThreshold();
    error BelowDepegThreshold();
    function initialize(
        address bridge,
        address dola_chain,
        address usdc_chain,
        uint32 domain
    ) public {
        l1BridgeAddr = bridge;
        exchangeProxy = new MockExchangeProxy(address(DOLA));

        fed = new SuperChainCCTPFed(
            gov,
            chair,
            25,
            10,
            bridge,
            dola_chain,
            usdc_chain,
            domain
        );

        gibUSDC(address(exchangeProxy), 1_000_000e6);
        vm.startPrank(gov);
        DOLA.addMinter(address(fed));
        DOLA.mint(address(exchangeProxy), 1_000_000e18);
        fed.setExchangeProxy(address(exchangeProxy), true);
        fed.changeFarmer(address(0x69));
        vm.stopPrank();
    }

    function testL1_Expansion() public {
        vm.startPrank(chair);

        uint prevBal = DOLA.balanceOf(l1BridgeAddr);

        fed.expansion(dolaAmount);

        assertEq(prevBal + dolaAmount, DOLA.balanceOf(l1BridgeAddr));
    }

    function testL1_ExpansionAndSwap_Half_CCTP() public {
        vm.startPrank(chair);

        uint prevDolaBal = DOLA.balanceOf(l1BridgeAddr);
        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            address(USDC),
            dolaAmount / 2,
            dolaAmount / 2 / 1e12
        );
        fed.expansionAndSwap(dolaAmount, dolaAmount / 2, true, swapData, address(exchangeProxy));

        assertEq(
            prevDolaBal + dolaAmount / 2,
            DOLA.balanceOf(l1BridgeAddr),
            "Bridge didn't receive correct amount of DOLA"
        );
        assertEq(USDC.balanceOf(address(fed)), 0, "CCTP Burn Failed");
    }

    function testL1_ExpansionAndSwap_Half_NO_CCTP() public {
        vm.startPrank(chair);

        uint prevDolaBal = DOLA.balanceOf(l1BridgeAddr);
        uint prevUsdcBal = USDC.balanceOf(l1BridgeAddr);
        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            address(USDC),
            dolaAmount / 2,
            dolaAmount / 2 / 1e12
        );
        fed.expansionAndSwap(dolaAmount, dolaAmount / 2, false, swapData, address(exchangeProxy));

        uint estimatedUsdcAmount = dolaAmount / 2 / 1e12;

        assertEq(
            prevDolaBal + dolaAmount / 2,
            DOLA.balanceOf(l1BridgeAddr),
            "Bridge didn't receive correct amount of DOLA"
        );

        assertGt(
            prevUsdcBal + (estimatedUsdcAmount * 1001) / 1000,
            USDC.balanceOf(l1BridgeAddr),
            "Bridge didn't receive correct amount of USDC"
        );
        assertLt(
            prevUsdcBal + estimatedUsdcAmount,
            (USDC.balanceOf(l1BridgeAddr) * 1001) / 1000,
            "Bridge didn't receive correct amount of USDC"
        );
    }

    function testL1_ExpansionAndSwap(uint8 multi) public {
        uint256 multiplier = bound(uint(multi), 1, 10);
        uint dolaToSwap = (dolaAmount * multiplier) / 10;
        uint dolaToBridge = dolaAmount - dolaToSwap;

        vm.startPrank(chair);

        uint prevDolaBal = DOLA.balanceOf(l1BridgeAddr);
        uint prevUsdcBal = USDC.balanceOf(l1BridgeAddr);
        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            address(USDC),
            dolaToSwap,
            dolaToSwap / 1e12
        );
        fed.expansionAndSwap(dolaAmount, dolaToSwap, false, swapData, address(exchangeProxy));

        uint estimatedUsdcAmount = dolaToSwap / 1e12;

        assertEq(
            prevDolaBal + dolaToBridge,
            DOLA.balanceOf(l1BridgeAddr),
            "Bridge didn't receive correct amount of DOLA"
        );

        assertGt(
            prevUsdcBal + (estimatedUsdcAmount * 1001) / 1000,
            USDC.balanceOf(l1BridgeAddr),
            "Bridge didn't receive correct amount of USDC"
        );
        assertLt(
            prevUsdcBal + estimatedUsdcAmount,
            (USDC.balanceOf(l1BridgeAddr) * 1001) / 1000,
            "Bridge didn't receive correct amount of USDC"
        );
    }

    function testL1_ExpansionAndSwap_CCTP(uint8 multi) public {
        uint256 multiplier = bound(uint(multi), 1, 10);
        uint dolaToSwap = (dolaAmount * multiplier) / 10;
        uint dolaToBridge = dolaAmount - dolaToSwap;

        vm.startPrank(chair);

        uint prevDolaBal = DOLA.balanceOf(l1BridgeAddr);
        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            address(USDC),
            dolaToSwap,
            dolaToSwap / 1e12
        );
        fed.expansionAndSwap(dolaAmount, dolaToSwap, true, swapData, address(exchangeProxy));

        assertEq(
            prevDolaBal + dolaToBridge,
            DOLA.balanceOf(l1BridgeAddr),
            "Bridge didn't receive correct amount of DOLA"
        );
        assertEq(USDC.balanceOf(address(fed)), 0, "CCTP Burn Failed");
    }

    function testL1_ExpansionAndSwap_Fails_IfSlippageRestraintUnmet() public {
        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            address(USDC),
            dolaAmount / 2,
            ((dolaAmount / 2) * 98) / 100 / 1e12
        );
        vm.startPrank(chair);

        vm.expectRevert(SlippageTooHigh.selector);
        fed.expansionAndSwap(dolaAmount, dolaAmount / 2, true, swapData, address(exchangeProxy));
    }

    function testL1_ExpansionAndSwap_Fail_If_USDC_Depeg() public {
        _mockUSDCFeed_latestAnswer();

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            address(USDC),
            dolaAmount / 2,
            (dolaAmount / 2) / 1e12
        );
        vm.startPrank(chair);

        vm.expectRevert(BelowDepegThreshold.selector);
        fed.expansionAndSwap(dolaAmount, dolaAmount / 2, false, swapData, address(exchangeProxy));
    }

    function testL1_SwapDOLAtoUSDC() public {
        vm.startPrank(chair);

        uint prevDolaBal = DOLA.balanceOf(address(fed));
        uint prevUsdcBal = USDC.balanceOf(address(fed));

        gibDOLA(address(fed), dolaAmount);
        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            address(USDC),
            dolaAmount,
            dolaAmount / 1e12
        );
        fed.swapDOLAtoUSDC(dolaAmount, swapData, address(exchangeProxy));

        uint estimatedUsdcAmount = dolaAmount / 1e12;

        assertEq(
            prevDolaBal,
            DOLA.balanceOf(address(fed)),
            "DOLA didn't leave fed"
        );
        assertGt(
            prevUsdcBal + (estimatedUsdcAmount * 101) / 100,
            USDC.balanceOf(address(fed)),
            "Fed didn't receive correct amount of USDC"
        );
        assertLt(
            prevUsdcBal + estimatedUsdcAmount,
            (USDC.balanceOf(address(fed)) * 101) / 100,
            "Fed didn't receive correct amount of USDC"
        );
    }

    function testL1_SwapUSDCtoDOLA_Fails_IfSlippageRestraintUnmet() public {
        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            address(USDC),
            usdcAmount,
            ((usdcAmount * 1e12) * 98) / 100
        );
        vm.startPrank(chair);
        gibUSDC(address(fed), usdcAmount);

        vm.expectRevert(SlippageTooHigh.selector);
        fed.swapUSDCtoDOLA(usdcAmount, swapData, address(exchangeProxy));
    }

    function testL1_SwapDOLAtoUSDC_Fails_IfSlippageRestraintUnmet() public {
        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            address(USDC),
            dolaAmount,
            (dolaAmount * 98) / 100 / 1e12
        );

        vm.startPrank(chair);
        gibDOLA(address(fed), dolaAmount);
        vm.expectRevert(SlippageTooHigh.selector);
        fed.swapDOLAtoUSDC(dolaAmount, swapData, address(exchangeProxy));
    }

    function testL1_SwapUSDCtoDOLA() public {
        vm.startPrank(chair);

        uint prevDolaBal = DOLA.balanceOf(address(fed));
        uint prevUsdcBal = USDC.balanceOf(address(fed));

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            address(USDC),
            usdcAmount,
            usdcAmount * 1e12
        );

        gibUSDC(address(fed), usdcAmount);

        fed.swapUSDCtoDOLA(usdcAmount, swapData, address(exchangeProxy));

        uint estimatedDolaAmount = usdcAmount * 1e12;

        assertEq(
            prevUsdcBal,
            USDC.balanceOf(address(fed)),
            "USDC didn't leave fed"
        );
        assertGt(
            prevDolaBal + (estimatedDolaAmount * 101) / 100,
            DOLA.balanceOf(address(fed)),
            "Fed didn't receive correct amount of DOLA"
        );
        assertLt(
            prevDolaBal + estimatedDolaAmount,
            (DOLA.balanceOf(address(fed)) * 101) / 100,
            "Fed didn't receive correct amount of DOLA"
        );
    }

    function testL1_SwapUSDCtoDOLA_fail_if_USDC_Depeg() public {
        _mockUSDCFeed_latestAnswer();

        vm.startPrank(chair);

        gibUSDC(address(fed), usdcAmount);
        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            address(USDC),
            usdcAmount,
            usdcAmount * 1e12
        );

        vm.expectRevert(BelowDepegThreshold.selector);
        fed.swapUSDCtoDOLA(usdcAmount, swapData, address(exchangeProxy));
    }

    

    function testL1_SwapDOLAtoUSDC_fail_if_USDC_Depeg() public {
        _mockUSDCFeed_latestAnswer();
        
        vm.startPrank(chair);
        gibDOLA(address(fed), dolaAmount);
        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            address(USDC),
            dolaAmount,
            dolaAmount / 1e12
        );

        vm.expectRevert(BelowDepegThreshold.selector);
        fed.swapDOLAtoUSDC(dolaAmount, swapData, address(exchangeProxy));
    }

    function testL1_SwapDOLAtoUSDC_succeed_if_USDC_Depeg_after_DepegThreshold_update() public {
        _mockUSDCFeed_latestAnswer();

        gibDOLA(address(fed), dolaAmount);
        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            address(USDC),
            dolaAmount,
            dolaAmount / 1e12
        );
        vm.startPrank(chair);
        vm.expectRevert(BelowDepegThreshold.selector);
        fed.swapDOLAtoUSDC(dolaAmount, swapData, address(exchangeProxy));

        vm.stopPrank();
        
        vm.prank(gov);
        fed.setDepegThreshold(0.85 ether);
        
        vm.prank(chair);
        fed.swapDOLAtoUSDC(dolaAmount, swapData, address(exchangeProxy));
    }

    function testL1_setDepegThreshold() public {
        vm.startPrank(gov);
        uint256 newDepegThreshold = 0.7 ether;
        fed.setDepegThreshold(newDepegThreshold);
        assertEq(fed.depegThreshold(), newDepegThreshold);
    }

    function testL1_setDepegThreshold_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.setDepegThreshold(0.9 ether);
    }

    function testL1_setDepegThreshold_fail_whenTooHigh() public {
        vm.startPrank(gov);

        vm.expectRevert(InvalidDepegThreshold.selector);
        fed.setDepegThreshold(1.01 ether);
    }

    function testL1_setDepegThreshold_fail_whenTooLow() public {
        vm.startPrank(gov);

        vm.expectRevert(InvalidDepegThreshold.selector);
        fed.setDepegThreshold(0.01 ether);
    }
    function testL1_changeChair_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.changeChair(user);
    }

    function testL1_setPendingGov_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.setPendingGov(user);
    }

    function testL1_govChange() public {
        vm.startPrank(gov);

        fed.setPendingGov(user);
        vm.stopPrank();

        vm.startPrank(user);

        fed.claimGov();

        assertEq(fed.gov(), user, "user failed to be set as gov");
        assertEq(
            fed.pendingGov(),
            address(0),
            "pendingGov failed to be set as 0 address"
        );
    }

    function testL1_setExchangeProxy_allow() public {
        address newExchangeProxy = address(0x70);
        assertFalse(fed.isExchangeProxy(newExchangeProxy));
        vm.prank(gov);
        fed.setExchangeProxy(address(newExchangeProxy), true);
        assertTrue(fed.isExchangeProxy(newExchangeProxy));
    }

    function testL1_setExchangeProxy_fail_when_address_zero() public {
        vm.prank(gov);
        vm.expectRevert(ZeroAddressParameter.selector);
        fed.setExchangeProxy(address(0), true);
    }

    function testL1_setExchangeProxy_deny() public {
        address newExchangeProxy = address(0x70);
        vm.prank(gov);
        fed.setExchangeProxy(address(newExchangeProxy), true);
        assertTrue(fed.isExchangeProxy(newExchangeProxy));

        vm.prank(gov);
        fed.setExchangeProxy(address(newExchangeProxy), false);
        assertFalse(fed.isExchangeProxy(newExchangeProxy));
    }
    function testL1_setExchangeProxy_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.setExchangeProxy(address(0x70), true);
    }

    function testL1_setMaxSlippageDolaToUsdc_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.setMaxSlippageDolaToUsdc(500);
    }

    function testL1_setMaxSlippageUsdcToDola_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.setMaxSlippageUsdcToDola(500);
    }

    function testL1_resign_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyChair.selector);
        fed.resign();
    }

    function testL1_swapDOLAtoUSDC_fail_whenCalledByNonChair() public {
        vm.startPrank(user);
        bytes memory swapData;
        vm.expectRevert(OnlyChair.selector);
        fed.swapDOLAtoUSDC(1e18, swapData, address(exchangeProxy));
    }

    function testL1_swapUSDCtoDOLA_fail_whenCalledByNonChair() public {
        vm.startPrank(user);
        bytes memory swapData;
        vm.expectRevert(OnlyChair.selector);
        fed.swapUSDCtoDOLA(1e6, swapData, address(exchangeProxy));
    }

    function testL1_contractAll_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyChair.selector);
        fed.contractAll();
    }

    function testL1_contract_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyChair.selector);
        fed.contraction(1e18);
    }

    function testL1_changeFarmer() public {
        vm.prank(gov);
        fed.changeFarmer(user);
        assertEq(fed.farmer(), user);
    }

    function testL1_changeFarmer_fail_whenCalledByNonGov() public {
        vm.prank(chair);
        vm.expectRevert(OnlyGov.selector);
        fed.changeFarmer(user);
    }

    function testL1_changeFarmer_fail_when_address_zero() public {
        vm.prank(gov);
        vm.expectRevert(ZeroAddressParameter.selector);
        fed.changeFarmer(address(0));
    }

    // My loyal helpers

    function _mockUSDCFeed_latestAnswer() internal {
        vm.mockCall(
            address(fed.USDC_FEED()),
            abi.encodeWithSelector(IChainlinkPriceFeed.latestAnswer.selector),
            abi.encode(10 ** fed.USDC_FEED().decimals() * 9 / 10)
        );
    }
    function gibDOLA(address _user, uint _amount) internal {
        bytes32 slot;
        assembly {
            mstore(0, _user)
            mstore(0x20, 0x6)
            slot := keccak256(0, 0x40)
        }

        vm.store(address(DOLA), slot, bytes32(_amount));
    }

    function gibUSDC(address _user, uint _amount) internal {
        bytes32 slot;
        assembly {
            mstore(0, _user)
            mstore(0x20, 0x9)
            slot := keccak256(0, 0x40)
        }

        vm.store(address(USDC), slot, bytes32(_amount));
    }
}
