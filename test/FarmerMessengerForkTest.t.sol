// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDola} from "src/interfaces/IDola.sol";
import "src/interfaces/ICrossDomainMessenger.sol";
import "src/interfaces/IRouter.sol";
import "src/interfaces/IGauge.sol";
import {DromeFarmer, IChainlinkPriceFeed} from "src/DromeFarmer.sol";
import {FarmerMessenger} from "src/FarmerMessenger.sol";
import {console} from "forge-std/console.sol";

contract MockBridge is ICrossDomainMessenger {
    address public xDomainMessageSender;

    function sendMessage(address _target, bytes calldata _message, uint32) external {
        xDomainMessageSender = msg.sender;
        (bool success,) = _target.call(_message);
        require(success, "Failed call");
        xDomainMessageSender = address(0);
    }

    function relayMessage(address, address, bytes calldata, uint256) external pure {
        revert("Not implemented");
    }
}

contract FarmerMessengerForkTest is Test {
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
    IChainlinkPriceFeed usdcPriceFeed = IChainlinkPriceFeed(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B);
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
    FarmerMessenger farmerMessenger;

    error OnlyRole(address l1, string name);
    error OnlyL1Role(address l1, string name);
    error PercentOutOfRange();
    error LiquiditySlippageTooHigh();

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("base"), 24873489);
        vm.label(address(rewardToken), "rewardToken");
        vm.label(address(nUSDC), "nUSDC");
        vm.label(address(USDC), "USDC");
        vm.label(address(DOLA), "DOLA");
        vm.etch(address(l2CrossDomainMessenger), address(new MockBridge()).code);

        farmerMessenger = new FarmerMessenger(gov, address(0), address(l2CrossDomainMessenger));
        DromeFarmer.Admin memory admin = DromeFarmer.Admin(chair, guardian, TWG, address(farmerMessenger));
        dromeFarmer = new DromeFarmer(
            admin, cctpBridge, l1Fed, address(DOLA), address(USDC), address(nUSDC), usdcPriceFeed, router, dolaGauge
        );
        //Inject l2CrossDomainMessenger as bridge to simulate actions
        vm.prank(gov);
        farmerMessenger.setDromeFarmer(address(dromeFarmer));
        rewardToken = dromeFarmer.rewardToken();

        address voter = dolaGauge.voter();
        deal(address(DOLA), address(dromeFarmer), dolaAmount);
        deal(address(nUSDC), address(dromeFarmer), USDCAmount);
        deal(address(rewardToken), address(voter), 1000 ether);
        deal(address(nUSDC), address(0xe8bDbCBC269528daE5bB9E8Fa5917a98FB9191e7), 1000 ether);
        vm.startPrank(voter);
        rewardToken.approve(address(dolaGauge), 1000 ether);
        dolaGauge.notifyRewardAmount(1000 ether);
        vm.stopPrank();
    }

    function testSetPendingGov() public {
        vm.expectRevert();
        farmerMessenger.setPendingGov(user);
        vm.prank(gov);
        farmerMessenger.setPendingGov(user);
        assertEq(dromeFarmer.pendingGov(), user);
    }

    function testSetMaxGuardianSetableSlippage() public {
        vm.expectRevert();
        farmerMessenger.setMaxGuardianSetableSlippage(1);
        vm.prank(gov);
        farmerMessenger.setMaxGuardianSetableSlippage(1);
        assertEq(dromeFarmer.maxGuardianSetableSlippageBps(), 1);
    }

    function testClaimGov() public {
        FarmerMessenger newMessenger = new FarmerMessenger(gov, address(dromeFarmer), address(l2CrossDomainMessenger));
        vm.prank(gov);
        farmerMessenger.setPendingGov(address(newMessenger));

        vm.expectRevert();
        vm.prank(chair);
        farmerMessenger.claimGov();
        vm.prank(gov);
        newMessenger.claimGov();
        assertEq(dromeFarmer.gov(), address(newMessenger));
    }

    function testChangeTreasury() public {
        vm.expectRevert();
        farmerMessenger.changeTreasury(user);
        vm.prank(gov);
        farmerMessenger.changeTreasury(user);
        assertEq(dromeFarmer.TWG(), user);
    }

    function testChangeChair() public {
        vm.expectRevert();
        farmerMessenger.changeChair(user);
        vm.prank(gov);
        farmerMessenger.changeChair(user);
        assertEq(dromeFarmer.chair(), user);
    }

    function testChangeGuardian() public {
        vm.expectRevert();
        farmerMessenger.changeGuardian(user);
        vm.prank(gov);
        farmerMessenger.changeGuardian(user);
        assertEq(dromeFarmer.guardian(), user);
    }

    function testChangeL1Fed() public {
        vm.expectRevert();
        farmerMessenger.changeL1Fed(user);
        vm.prank(gov);
        farmerMessenger.changeL1Fed(user);
        assertEq(dromeFarmer.l1Fed(), user);
    }

    function testEmergencyWithdrawToL1() public {
        vm.expectRevert();
        farmerMessenger.emergencyWithdraw(address(DOLA), dolaAmount);
        uint256 dolaBefore = DOLA.balanceOf(address(dromeFarmer));
        uint256 dolaTWGBefore = DOLA.balanceOf(address(TWG));
        vm.prank(gov);
        farmerMessenger.emergencyWithdraw(address(DOLA), dolaAmount);
        assertEq(DOLA.balanceOf(address(dromeFarmer)), dolaBefore - dolaAmount, "Did not withdraw dolaAmount");
        assertEq(DOLA.balanceOf(address(TWG)), dolaTWGBefore + dolaAmount, "Did not receive dolaAmount");
    }

    function testSetDepegEmergencyThreshold() public {
        vm.expectRevert();
        farmerMessenger.setMaxGuardianSetableSlippage(9500);
        vm.prank(gov);
        farmerMessenger.setMaxGuardianSetableSlippage(9500);
        assertEq(dromeFarmer.maxGuardianSetableSlippageBps(), 9500);
    }

    //Gov functions

    function testSetGasLimit() public {
        vm.expectRevert();
        farmerMessenger.setGasLimit(200);
        vm.prank(gov);
        farmerMessenger.setGasLimit(200);
        assertEq(farmerMessenger.gasLimit(), 200);
    }

    function testSetPendingMessengerGov() public {
        vm.expectRevert();
        farmerMessenger.setPendingMessengerGov(user);
        vm.prank(gov);
        farmerMessenger.setPendingMessengerGov(user);
        assertEq(farmerMessenger.pendingGov(), user);
    }

    function testClaimMessengerGov() public {
        vm.prank(gov);
        farmerMessenger.setPendingMessengerGov(user);

        vm.expectRevert();
        farmerMessenger.claimGov();
        vm.prank(user);
        farmerMessenger.claimMessengerGov();
        assertEq(farmerMessenger.gov(), user);
        assertEq(farmerMessenger.pendingGov(), address(0));
    }

    function testSetDromeFarmer() public {
        vm.expectRevert();
        farmerMessenger.setDromeFarmer(user);
        vm.prank(gov);
        farmerMessenger.setDromeFarmer(user);
        assertEq(farmerMessenger.dromeFarmer(), user);
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
