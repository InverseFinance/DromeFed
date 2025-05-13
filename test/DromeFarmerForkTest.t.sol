// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDola} from "src/interfaces/IDola.sol";
import "src/interfaces/ICrossDomainMessenger.sol";
import "src/interfaces/IRouter.sol";
import "src/interfaces/IGauge.sol";
import {DromeFarmer, IChainlinkPriceFeed} from "src/DromeFarmer.sol";
import {console} from "forge-std/console.sol";

contract DromeFarmerForkTest is Test {
    IRouter public router = IRouter(payable(0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43));
    IGauge public dolaGauge = IGauge(0xCCff5627cd544b4cBb7d048139C1A6b6Bde67885);

    IDola public DOLA = IDola(0x4621b7A9c75199271F773Ebd9A499dbd165c3191);
    IERC20 public USDC = IERC20(0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA);
    IERC20 public nUSDC = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    IERC20 public rewardToken;
    address public l2optiBridgeAddress = 0x4200000000000000000000000000000000000010;
    address public l1Fed = address(0xA);
    ICrossDomainMessenger public l2CrossDomainMessenger =
        ICrossDomainMessenger(0x4200000000000000000000000000000000000007);
    address public l1CrossDomainMessenger = 0x36BDE71C97B33Cc4729cf772aE268934f7AB70B2;
    address public TWG = 0x586CF50c2874f3e3997660c0FD0996B090FB9764;
    address public cctpBridge = 0x1682Ae6375C4E4A97e4B583BC394c861A46D8962;

    //EOAs
    address user = address(69);
    address chair = address(0xB);
    address gov = address(0x607); // RewardsMessengerV3
    address guardian = address(0xD);

    //Numbas
    uint256 dolaAmount = 1_000e18;
    uint256 USDCAmount = 1_000e6;

    //Feds
    DromeFarmer dromeFarmer;

    error OnlyRole(address l1, string name);
    error OnlyL1Role(address l1, string name);
    error PercentOutOfRange();
    error MaxSlippageTooHigh();
    error LiquiditySlippageTooHigh();

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("base"), 24873489);
        vm.label(address(rewardToken), "rewardToken");
        vm.label(address(nUSDC), "nUSDC");
        vm.label(address(USDC), "USDC");
        vm.label(address(DOLA), "DOLA");

        dromeFarmer = new DromeFarmer(
            chair,
            guardian,
            TWG,
            gov,
            cctpBridge,
            l1Fed,
            address(DOLA),
            address(USDC),
            address(nUSDC),
            router,
            dolaGauge
        );

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        dromeFarmer.setMaxGuardianSetableSlippageBps(2000);
        vm.stopPrank();

        rewardToken = dromeFarmer.rewardToken();
        address voter = dolaGauge.voter();
        deal(address(rewardToken), address(voter), 1000 ether);
        deal(address(nUSDC), address(0xe8bDbCBC269528daE5bB9E8Fa5917a98FB9191e7), 1000 ether);
        vm.startPrank(voter);
        rewardToken.approve(address(dolaGauge), 1000 ether);
        dolaGauge.notifyRewardAmount(1000 ether);
        vm.stopPrank();
    }

    function test_swapStablesDolaToUSDCNative() public {
        deal(address(DOLA), address(dromeFarmer), dolaAmount * 3);

        vm.prank(guardian);
        dromeFarmer.setMaxSwapSlippage(address(DOLA), address(nUSDC), 1000);

        vm.prank(chair);
        dromeFarmer.swapStables(address(DOLA), address(nUSDC), dolaAmount * 3);

        assertGt(nUSDC.balanceOf(address(dromeFarmer)), 0, "No USDC swapped");
    }

    function test_swapUsdcNativeToDola() public {
        deal(address(nUSDC), address(dromeFarmer), USDCAmount);

        vm.prank(chair);
        dromeFarmer.swapStables(address(nUSDC), address(DOLA), USDCAmount);

        assertGt(DOLA.balanceOf(address(dromeFarmer)), 0, "No DOLA swapped");
    }

    function test_deposit() public {
        deal(address(DOLA), address(dromeFarmer), dolaAmount * 3);
        deal(address(nUSDC), address(dromeFarmer), USDCAmount * 3);

        uint256 initialRewards = rewardToken.balanceOf(address(TWG));

        vm.prank(guardian);
        dromeFarmer.setMaxSlippageLP(1000);

        vm.startPrank(chair);
        dromeFarmer.deposit(dolaAmount / 2, USDCAmount / 2);

        vm.roll(block.number + 100000);
        vm.warp(block.timestamp + (10_0000 * 60));
        dromeFarmer.claimRewards();

        assertEq(dromeFarmer.lpToken().balanceOf(address(dromeFarmer)), 0);
        assertGt(rewardToken.balanceOf(address(TWG)), initialRewards, "No rewards claimed");
    }

    function test_depositAll() public {
        deal(address(DOLA), address(dromeFarmer), dolaAmount * 3);
        deal(address(nUSDC), address(dromeFarmer), USDCAmount * 3);

        uint256 initialRewards = rewardToken.balanceOf(address(TWG));

        vm.prank(guardian);
        dromeFarmer.setMaxSlippageLP(1000);

        vm.startPrank(chair);
        dromeFarmer.depositAll();

        vm.roll(block.number + 100000);
        vm.warp(block.timestamp + (10_0000 * 60));
        dromeFarmer.claimRewards();

        assertEq(dromeFarmer.lpToken().balanceOf(address(dromeFarmer)), 0);
        assertGt(rewardToken.balanceOf(address(TWG)), initialRewards, "No rewards claimed");
    }

    function test_withdrawNative() public {
        deal(address(DOLA), address(dromeFarmer), dolaAmount * 3);
        deal(address(nUSDC), address(dromeFarmer), USDCAmount * 3);

        vm.prank(guardian);
        dromeFarmer.setMaxSlippageLP(1000);

        vm.startPrank(chair);
        dromeFarmer.depositAll();
        dromeFarmer.withdraw(dolaAmount / 2);
    }

    function test_withdrawAndSwap() public {
        deal(address(DOLA), address(dromeFarmer), dolaAmount * 3);
        deal(address(nUSDC), address(dromeFarmer), USDCAmount * 3);

        vm.startPrank(guardian);
        dromeFarmer.setMaxSlippageLP(1000);

        vm.startPrank(chair);
        dromeFarmer.depositAll();

        uint256 USDCBefore = nUSDC.balanceOf(address(dromeFarmer));
        dromeFarmer.withdrawAndSwapToDOLA(address(nUSDC), dolaAmount / 2);
        assertGt(DOLA.balanceOf(address(dromeFarmer)), 0, "No DOLA swapped");
        assertEq(nUSDC.balanceOf(address(dromeFarmer)), USDCBefore, "Failed USDC Swap");
    }

    function test_withdrawToL1Native() public {
        deal(address(DOLA), address(dromeFarmer), dolaAmount * 3);
        deal(address(nUSDC), address(dromeFarmer), USDCAmount * 3);

        vm.prank(guardian);
        dromeFarmer.setMaxSlippageLP(1000);

        vm.startPrank(chair);
        dromeFarmer.depositAll();
        dromeFarmer.withdraw(dolaAmount / 2);

        dromeFarmer.withdrawToL1FedNative(
            DOLA.balanceOf(address(dromeFarmer)), nUSDC.balanceOf(address(dromeFarmer)) / 2
        );
        dromeFarmer.withdrawToL1FedNative(nUSDC.balanceOf(address(dromeFarmer)));
    }

    function test_emergencyWithdraw() public {
        deal(address(DOLA), address(dromeFarmer), 1000e6);
        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        dromeFarmer.emergencyWithdraw(address(DOLA), 1000e6);
    }

    function test_withdrawToL1Fed() public {
        deal(address(DOLA), address(dromeFarmer), dolaAmount);
        uint256 prevDolaAmount = DOLA.balanceOf(address(dromeFarmer));
        vm.prank(chair);
        dromeFarmer.withdrawToL1Fed(dolaAmount);
        assertEq(prevDolaAmount - dolaAmount, DOLA.balanceOf(address(dromeFarmer)));
    }

    function test_withdrawToL1FedBridged() public {
        deal(address(USDC), address(dromeFarmer), USDCAmount);
        vm.prank(chair);
        dromeFarmer.withdrawToL1FedBridged(USDCAmount);
    }

    function test_DepositAndClaimRewards() public {
        deal(address(DOLA), address(dromeFarmer), dolaAmount * 3);
        deal(address(nUSDC), address(dromeFarmer), USDCAmount * 3);
        uint256 initialRewards = rewardToken.balanceOf(address(TWG));

        vm.prank(guardian);
        dromeFarmer.setMaxSlippageLP(1000);

        vm.startPrank(chair);
        dromeFarmer.deposit(dolaAmount / 2, USDCAmount / 2);

        vm.roll(block.number + 100000);
        vm.warp(block.timestamp + (10_0000 * 60));
        dromeFarmer.claimRewards();

        assertGt(rewardToken.balanceOf(address(TWG)), initialRewards, "No rewards claimed");
    }

    function test_SwapAndClaimRewards() public {
        deal(address(DOLA), address(dromeFarmer), dolaAmount * 3);
        deal(address(nUSDC), address(dromeFarmer), USDCAmount * 3);

        uint256 initialRewards = rewardToken.balanceOf(address(TWG));

        vm.prank(guardian);
        dromeFarmer.setMaxSlippageLP(1000);

        vm.startPrank(chair);
        dromeFarmer.deposit(dolaAmount, USDCAmount);
        vm.roll(block.number + 10000);
        vm.warp(block.timestamp + (10_000 * 60));
        dromeFarmer.claimRewards();

        assertGt(rewardToken.balanceOf(address(TWG)), initialRewards, "No rewards claimed");
    }

    function test_swap_USDCNativeToUSDC() public {
        deal(address(nUSDC), address(dromeFarmer), USDCAmount * 3);

        assertEq(USDC.balanceOf(address(dromeFarmer)), 0, "Wrong balance");

        vm.prank(chair);
        dromeFarmer.swapStables(address(nUSDC), address(USDC), USDCAmount * 3);

        assertGt(USDC.balanceOf(address(dromeFarmer)), 0, "Failed swap");
    }

    function test_swap_USDCToUSDCNative() public {
        deal(address(USDC), address(dromeFarmer), USDCAmount * 3);

        assertEq(nUSDC.balanceOf(address(dromeFarmer)), 0, "Wrong balance");

        vm.prank(chair);
        dromeFarmer.swapStables(address(USDC), address(nUSDC), uint256(USDCAmount * 3));

        assertGt(nUSDC.balanceOf(address(dromeFarmer)), 0, "Failed swap");
    }

    function test_swap_USDCToDOLA() public {
        deal(address(USDC), address(dromeFarmer), USDCAmount * 3);

        assertEq(DOLA.balanceOf(address(dromeFarmer)), 0, "Wrong balance");

        vm.prank(chair);
        dromeFarmer.swapStables(address(USDC), address(DOLA), uint256(USDCAmount * 3));

        assertGt(DOLA.balanceOf(address(dromeFarmer)), 0, "Failed swap");
    }

    function test_swap_DOLAToUSDC() public {
        deal(address(DOLA), address(dromeFarmer), dolaAmount * 3);

        assertEq(USDC.balanceOf(address(dromeFarmer)), 0, "Wrong balance");

        vm.prank(guardian);
        dromeFarmer.setMaxSwapSlippage(address(DOLA), address(USDC), 1000);

        vm.prank(chair);
        dromeFarmer.swapStables(address(DOLA), address(USDC), uint256(dolaAmount * 3));

        assertGt(USDC.balanceOf(address(dromeFarmer)), 0, "Failed swap");
    }

    function test_Deposit_Succeeds_WhenSlippageLtMaxLiquiditySlippage() public {
        deal(address(DOLA), address(dromeFarmer), dolaAmount);
        deal(address(nUSDC), address(dromeFarmer), USDCAmount * 2);

        uint256 initialPoolTokens = dolaGauge.balanceOf(address(dromeFarmer));

        vm.prank(guardian);
        dromeFarmer.setMaxSlippageLP(100);

        vm.prank(chair);
        dromeFarmer.depositAll();

        assertGt(dolaGauge.balanceOf(address(dromeFarmer)), initialPoolTokens, "depositAll failed");
    }

    function test_SwapDolaToUsdc_Fails_WhenSlippageGtMaxDolaToUsdcSlippage() public {
        deal(address(DOLA), address(dromeFarmer), dolaAmount * 3);

        vm.startPrank(guardian);
        dromeFarmer.setMaxSlippageLP(50);
        dromeFarmer.setMaxSwapSlippage(address(DOLA), address(USDC), 1);
        vm.stopPrank();

        vm.startPrank(chair);
        vm.expectRevert(abi.encodeWithSelector(IRouter.InsufficientOutputAmount.selector));
        dromeFarmer.swapStables(address(DOLA), address(USDC), dolaAmount * 3);
    }

    function test_SwapDolaToUsdc_Fails_WhenSlippageGtMaxDolaToUsdcNativeSlippage() public {
        deal(address(DOLA), address(dromeFarmer), dolaAmount * 3);

        vm.startPrank(guardian);
        dromeFarmer.setMaxSlippageLP(50);
        dromeFarmer.setMaxSwapSlippage(address(DOLA), address(nUSDC), 1);
        vm.stopPrank();

        vm.startPrank(chair);
        vm.expectRevert(abi.encodeWithSelector(IRouter.InsufficientOutputAmount.selector));
        dromeFarmer.swapStables(address(DOLA), address(nUSDC), dolaAmount * 3);
    }

    function test_SwapUsdcToDola_Fails_WhenSlippageGtMaxUsdcToDolaSlippage() public {
        deal(address(USDC), address(dromeFarmer), USDCAmount * 5);

        uint256 USDCToSwap = USDCAmount * 1000;
        deal(address(USDC), address(user), USDCToSwap);
        vm.startPrank(user);
        USDC.approve(address(router), type(uint256).max);
        router.swapExactTokensForTokens(
            USDCToSwap, 1, getRoute(address(USDC), address(DOLA)), address(user), block.timestamp
        );
        vm.stopPrank();

        vm.startPrank(guardian);
        dromeFarmer.setMaxSwapSlippage(address(USDC), address(DOLA), 1);
        vm.stopPrank();

        vm.startPrank(chair);
        vm.expectRevert(abi.encodeWithSelector(IRouter.InsufficientOutputAmount.selector));
        dromeFarmer.swapStables(address(USDC), address(DOLA), USDCAmount * 5);
    }

    function test_SwapUsdcToDola_Fails_WhenSlippageGtMaxUsdcNativeToDolaSlippage() public {
        deal(address(nUSDC), address(dromeFarmer), USDCAmount * 5);

        uint256 USDCToSwap = USDCAmount * 3000;
        deal(address(nUSDC), address(user), USDCToSwap);
        vm.startPrank(user);
        nUSDC.approve(address(router), type(uint256).max);
        router.swapExactTokensForTokens(
            USDCToSwap, 0, getRoute(address(nUSDC), address(DOLA)), address(user), block.timestamp
        );
        vm.stopPrank();

        vm.startPrank(guardian);
        dromeFarmer.setMaxSwapSlippage(address(nUSDC), address(DOLA), 1);
        vm.stopPrank();

        vm.startPrank(chair);
        vm.expectRevert(abi.encodeWithSelector(IRouter.InsufficientOutputAmount.selector));
        dromeFarmer.swapStables(address(nUSDC), address(DOLA), USDCAmount * 5);
    }

    function test_onlyChair_fail_whenCalledByBridge_NonChairSender() public {
        address prevChair = dromeFarmer.chair();

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        vm.expectRevert();
        dromeFarmer.resign();
        vm.stopPrank();

        assertEq(prevChair, dromeFarmer.chair(), "onlyChair function did not revert properly");
        assertTrue(dromeFarmer.chair() != address(0), "onlyChair function did not revert properly");
    }

    function test_resign_fromChair() public {
        address prevChair = dromeFarmer.chair();

        vm.prank(chair);
        dromeFarmer.resign();

        assertTrue(prevChair != dromeFarmer.chair(), "onlyChair function did not revert properly");
        assertEq(dromeFarmer.chair(), address(0), "onlyChair function did not revert properly");
    }

    function test_resign_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(OnlyRole.selector, dromeFarmer.chair(), "chair"));
        dromeFarmer.resign();
    }

    function test_priceAboveEmergencyThreshold() public {
        assertEq(dromeFarmer.priceAboveEmergencyThreshold(), true, "Price below emergency threshold");
        mockUsdcPrice(0.5 * 1e8);
        assertEq(dromeFarmer.priceAboveEmergencyThreshold(), false, "Price above emergency threshold");
    }

    function test_setMaxSwapSlippage() public {
        vm.startPrank(guardian);

        dromeFarmer.setMaxSwapSlippage(address(DOLA), address(USDC), 100);
        assertEq(dromeFarmer.maxSwapSlippage(address(DOLA), address(USDC)), 100);
        assertEq(dromeFarmer.maxSwapSlippage(address(USDC), address(DOLA)), 100);
    }

    function test_setMaxSwapSlippage_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(OnlyRole.selector, guardian, "guardian"));
        dromeFarmer.setMaxSwapSlippage(address(DOLA), address(USDC), 500);
    }

    function test_setMaxSwapSlippage_fail_whenSetAboveLimit() public {
        vm.startPrank(guardian);

        uint256 maxSlippage = dromeFarmer.maxGuardianSetableSlippageBps();
        vm.expectRevert(abi.encodeWithSelector(MaxSlippageTooHigh.selector));
        dromeFarmer.setMaxSwapSlippage(address(DOLA), address(USDC), maxSlippage + 1);
    }

    function test_setMaxSwapSlippage_whenSetAboveLimitAndDepegged() public {
        vm.startPrank(guardian);

        mockUsdcPrice(0.5 * 1e8);
        dromeFarmer.setMaxSwapSlippage(address(DOLA), address(USDC), 9999);
    }

    function test_setMaxSlippage() public {
        vm.startPrank(guardian);

        dromeFarmer.setMaxSlippageLP(100);
        assertEq(dromeFarmer.maxSlippageBps(), 100);
    }

    function test_setMaxSlippageLP_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(OnlyRole.selector, guardian, "guardian"));
        dromeFarmer.setMaxSlippageLP(500);
    }

    function test_setMaxSlippageLP_fail_whenSetAboveLimit() public {
        vm.startPrank(guardian);

        uint256 maxSlippage = dromeFarmer.maxGuardianSetableSlippageBps();
        vm.expectRevert(abi.encodeWithSelector(MaxSlippageTooHigh.selector));
        dromeFarmer.setMaxSlippageLP(maxSlippage + 1);
    }

    function test_setMaxSlippageLP_whenSetAboveLimitAndDepegged() public {
        vm.startPrank(guardian);

        mockUsdcPrice(0.5 * 1e8);
        dromeFarmer.setMaxSlippageLP(9999);
    }

    function test_setPendingGov_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(OnlyL1Role.selector, dromeFarmer.gov(), "gov"));
        dromeFarmer.setPendingGov(user);
    }

    function test_govChange() public {
        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        dromeFarmer.setPendingGov(user);
        vm.stopPrank();

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(user);
        dromeFarmer.claimGov();
        vm.stopPrank();

        assertEq(dromeFarmer.gov(), user, "user failed to be set as gov");
        assertEq(dromeFarmer.pendingGov(), address(0), "pendingGov failed to be set as 0 address");
    }

    function test_changeFed() public {
        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(OnlyL1Role.selector, dromeFarmer.gov(), "gov"));
        dromeFarmer.changeL1Fed(user);

        assertNotEq(dromeFarmer.l1Fed(), user);

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        dromeFarmer.changeL1Fed(user);
        vm.stopPrank();

        assertEq(dromeFarmer.l1Fed(), user);
    }

    function test_changeChair() public {
        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(OnlyL1Role.selector, dromeFarmer.gov(), "gov"));
        dromeFarmer.changeChair(user);

        assertNotEq(dromeFarmer.chair(), user);

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        dromeFarmer.changeChair(user);
        vm.stopPrank();

        assertEq(dromeFarmer.chair(), user);
    }

    function test_changeTreasury() public {
        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(OnlyL1Role.selector, dromeFarmer.gov(), "gov"));
        dromeFarmer.changeTreasury(user);

        assertNotEq(dromeFarmer.TWG(), user);

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        dromeFarmer.changeTreasury(user);
        vm.stopPrank();

        assertEq(dromeFarmer.TWG(), user);
    }

    function test_changeGuardian() public {
        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(OnlyL1Role.selector, dromeFarmer.gov(), "gov"));
        dromeFarmer.changeGuardian(user);

        assertNotEq(dromeFarmer.guardian(), user);

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        dromeFarmer.changeGuardian(user);
        vm.stopPrank();

        assertEq(dromeFarmer.guardian(), user);
    }

    function mockUsdcPrice(uint256 price) internal {
        (uint80 roundId,, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            dromeFarmer.usdcPriceFeed().latestRoundData();
        vm.mockCall(
            address(dromeFarmer.usdcPriceFeed()),
            abi.encodeWithSelector(IChainlinkPriceFeed.latestRoundData.selector),
            abi.encode(roundId, int256(price), startedAt, updatedAt, answeredInRound)
        );
    }

    //My loyal helpers
    function mockXDomainMessageSender(address sender) internal {
        vm.mockCall(
            0x4200000000000000000000000000000000000007,
            abi.encodeWithSelector(ICrossDomainMessenger.xDomainMessageSender.selector),
            abi.encode(sender)
        );
    }

    function getRoute(address from, address to) internal pure returns (IRouter.Route[] memory) {
        address factory = address(0); //Default factory
        IRouter.Route memory route = IRouter.Route(from, to, true, factory);
        IRouter.Route[] memory routeArray = new IRouter.Route[](1);
        routeArray[0] = route;
        return routeArray;
    }
}
