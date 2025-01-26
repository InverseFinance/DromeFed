pragma solidity ^0.8.21;
import {ICrossDomainMessenger} from "src/interfaces/ICrossDomainMessenger.sol";
import {Test} from "forge-std/Test.sol";
import {AeroChairIntermediary} from "src/AeroChairIntermediary.sol";

interface IAeroFarmer {
    function changeL2Chair(address newChair) external;
    function setMaxSlippageDolaToUsdc(uint newSlippage) external;
    function setMaxSlippageDolaToUsdcNative(uint newSlippage) external;
}

contract AeroChairIntermediaryForkTest is Test {

    AeroChairIntermediary intermediary;
    address baseChair = 0x09aF9E0D4932604913F7Cd77aD5e157F0BC700eA;
    address aeroFarmer = 0xe96e99a5A3512468A4aaFC317D77C6Fa0289F5f3;
    address l2CrossDomainMessenger = 0x4200000000000000000000000000000000000007;
    address govMessenger = 0x09aF9E0D4932604913F7Cd77aD5e157F0BC700eA;
    address DOLA = 0x4621b7A9c75199271F773Ebd9A499dbd165c3191;
    address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address USDCb = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;
    uint dolaAmount = 1 ether;
    uint usdcAmount = 1 ether / 10**12;
    uint256 baseFork;

    
    function setUp() public {
        intermediary = new AeroChairIntermediary(baseChair, aeroFarmer);
        baseFork = vm.createSelectFork(vm.rpcUrl("base"), 25422154);
        deal(USDC, aeroFarmer, 1 ether);
        deal(USDCb, aeroFarmer, 1 ether);
        deal(DOLA, aeroFarmer, 1 ether);
        vm.prank(l2CrossDomainMessenger);
        mockXDomainMessageSender(govMessenger);
        IAeroFarmer(aeroFarmer).changeL2Chair(address(intermediary));
        vm.prank(l2CrossDomainMessenger);
        mockXDomainMessageSender(govMessenger);
        IAeroFarmer(aeroFarmer).setMaxSlippageDolaToUsdc(1000);
        vm.prank(l2CrossDomainMessenger);
        mockXDomainMessageSender(govMessenger);
        IAeroFarmer(aeroFarmer).setMaxSlippageDolaToUsdcNative(1000);

    }

    function testwithdrawLiquidity() external {
        vm.prank(baseChair);
        intermediary.withdrawLiquidity(dolaAmount);
    }
 
    function testwithdrawLiquidityAndSwapToDOLA() external {
        vm.prank(baseChair);
        intermediary.withdrawLiquidityAndSwapToDOLA(dolaAmount);
    }

    function testwithdrawToL1BaseFed() external {
        vm.prank(baseChair);
        intermediary.withdrawToL1BaseFed(dolaAmount);
    }

    function testwithdrawToL1BaseFedNativeBoth() external {
        vm.prank(baseChair);
        intermediary.withdrawToL1BaseFedNative(dolaAmount, usdcAmount);
    }

    function testwithdrawToL1BaseFedNative() external {
        vm.prank(baseChair);
        intermediary.withdrawToL1BaseFedNative(usdcAmount);
    }

    function testwithdrawToL1BaseFedBridged() external {
        vm.prank(baseChair);
        intermediary.withdrawToL1BaseFedBridged(usdcAmount);
    }

    function testswapUSDCtoDOLA() external {
        vm.prank(baseChair);
        intermediary.swapUSDCtoDOLA(usdcAmount);
    }

    function testswapUSDCNativetoDOLA() external {
        vm.prank(baseChair);
        intermediary.swapUSDCNativetoDOLA(usdcAmount);
    }

    function testswapDOLAtoUSDC() external {
        vm.prank(baseChair);
        intermediary.swapDOLAtoUSDC(dolaAmount);
    }

    function testswapDOLAtoUSDCNative() external {
        vm.prank(baseChair);
        intermediary.swapDOLAtoUSDCNative(dolaAmount);
    }

    function testswapUSDCtoUSDCNative() external {
        vm.prank(baseChair);
        intermediary.swapUSDCtoUSDCNative(usdcAmount);
    }

    function testswapUSDCNativeToUSDC() external {
        vm.prank(baseChair);
        intermediary.swapUSDCNativeToUSDC(usdcAmount);
    }

    function testresign() external {
        vm.prank(baseChair);
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
