pragma solidity ^0.8.21;
import {ICrossDomainMessenger} from "src/interfaces/ICrossDomainMessenger.sol";
import {Test} from "forge-std/Test.sol";
import {VeloChairIntermediary} from "src/VeloChairIntermediary.sol";

interface IVeloFarmer {
    function changeL2Chair(address newChair) external;
    function setMaxSlippageDolaToUsdc(uint newSlippage) external;
    function setMaxSlippageLiquidity(uint newSlippage) external;
    function depositAll() external;
}

contract VeloChairIntermediaryForkTest is Test {

    VeloChairIntermediary intermediary;
    address optiChair = 0x9f9Fa2C6b432689Dcd4E3ad55f86FdE6c03694EE;
    address veloFarmer = 0x8Bbd036d018657E454F679E7C4726F7a8ECE2773;
    address l2CrossDomainMessenger = 0x4200000000000000000000000000000000000007;
    address govMessenger = 0x257D2836c8f5797581740543F853403b81C44b5A;
    address DOLA = 0x8aE125E8653821E851F12A49F7765db9a9ce7384;
    address USDC = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    uint dolaAmount = 1 ether;
    uint usdcAmount = 1 ether / 10**12;
    uint256 optiFork;

    
    function setUp() public {
        intermediary = new VeloChairIntermediary(optiChair, veloFarmer);
        optiFork = vm.createSelectFork(vm.rpcUrl("opti"), 131188657);
        deal(USDC, veloFarmer, 1 ether);
        deal(DOLA, veloFarmer, 1 ether);
        vm.prank(l2CrossDomainMessenger);
        mockXDomainMessageSender(govMessenger);
        IVeloFarmer(veloFarmer).changeL2Chair(address(intermediary));
        vm.prank(l2CrossDomainMessenger);
        mockXDomainMessageSender(govMessenger);
        IVeloFarmer(veloFarmer).setMaxSlippageDolaToUsdc(1000);
        vm.prank(l2CrossDomainMessenger);
        mockXDomainMessageSender(govMessenger);
        IVeloFarmer(veloFarmer).setMaxSlippageLiquidity(9000);
    }

    function testwithdrawLiquidity() external {
        vm.prank(address(intermediary));
        IVeloFarmer(veloFarmer).depositAll();
        vm.prank(optiChair);
        intermediary.withdrawLiquidity(dolaAmount);
    }
 
    function testwithdrawLiquidityAndSwapToDOLA() external {
        vm.prank(address(intermediary));
        IVeloFarmer(veloFarmer).depositAll();
        vm.prank(optiChair);
        intermediary.withdrawLiquidityAndSwapToDOLA(dolaAmount);
    }

    function testwithdrawToL1OptiFed() external {
        vm.prank(optiChair);
        intermediary.withdrawToL1OptiFed(dolaAmount);
    }

    function testwithdrawToL1OptiFedUsdc() external {
        vm.prank(optiChair);
        intermediary.withdrawToL1OptiFed(dolaAmount, usdcAmount);
    }

    function testswapUSDCtoDOLA() external {
        vm.prank(optiChair);
        intermediary.swapUSDCtoDOLA(usdcAmount);
    }

    function testswapDOLAtoUSDC() external {
        vm.prank(optiChair);
        intermediary.swapDOLAtoUSDC(dolaAmount);
    }

    function testresign() external {
        vm.prank(optiChair);
        intermediary.resign();
    }
    
    function mockXDomainMessageSender(address sender) internal {
        vm.mockCall(
            0x4200000000000000000000000000000000000007,
            abi.encodeWithSelector(ICrossDomainMessenger.xDomainMessageSender.selector),
            abi.encode(sender)
        );
    }
}
