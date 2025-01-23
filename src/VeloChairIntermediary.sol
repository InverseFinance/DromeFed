//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.21;

interface IVeloFarmer {
    function withdrawLiquidity(uint dolaAmount) external;
    function withdrawLiquidityAndSwapToDOLA(uint dolaAmount) external;
    function withdrawToL1OptiFed(uint dolaAmount) external;
    function withdrawToL1OptiFedBridged(uint usdcAmount) external;
    function withdrawTokensToL1(address l2Token, uint amount) external;
    function swapUSDCtoDOLA(uint usdcAmount) external;
    function swapUSDCNativetoDOLA(uint usdcAmount) external;
    function swapDOLAtoUSDC(uint dolaAmount) external;
    function swapDOLAtoUSDCNative(uint dolaAmount) external;
    function swapUSDCtoUSDCNative(uint usdcAmount) external;
    function swapUSDCNativeToUSDC(uint usdcAmount) external;
    function resign() external;
}

contract VeloChairIntermediary {
    IVeloFarmer public veloFarmer;
    address public chair;
    
    constructor(address _chair, address _veloFarmer){
        chair = _chair;
        veloFarmer = IVeloFarmer(_veloFarmer);
    }

    modifier onlyChair() {
        require(msg.sender == chair, "ONLY MSG.SENDER");
        _;
    }

    function withdrawLiquidity(uint dolaAmount) external onlyChair {
        veloFarmer.withdrawLiquidity(dolaAmount);
    }
 
    function withdrawLiquidityAndSwapToDOLA(uint dolaAmount) external onlyChair {
        veloFarmer.withdrawLiquidityAndSwapToDOLA(dolaAmount);
    }

    function withdrawToL1OptiFed(uint dolaAmount) external onlyChair {
        veloFarmer.withdrawToL1OptiFed(dolaAmount);
    }

    function withdrawToL1OptiFedBridged(uint usdcAmount) external onlyChair {
        veloFarmer.withdrawToL1OptiFedBridged(usdcAmount);
    }

    function withdrawTokensToL1(address l2Token, uint amount) external onlyChair{
        veloFarmer.withdrawTokensToL1(l2Token, amount);
    }

    function swapUSDCtoDOLA(uint usdcAmount) external onlyChair {
        veloFarmer.swapUSDCtoDOLA(usdcAmount);
    }

    function swapUSDCNativetoDOLA(uint usdcAmount) external onlyChair {
        veloFarmer.swapUSDCNativetoDOLA(usdcAmount);
    }

    function swapDOLAtoUSDC(uint dolaAmount) external onlyChair {
        veloFarmer.swapDOLAtoUSDC(dolaAmount);
    }

    function swapDOLAtoUSDCNative(uint dolaAmount) external onlyChair {
        veloFarmer.swapDOLAtoUSDCNative(dolaAmount);
    }

    function swapUSDCtoUSDCNative(uint usdcAmount) external onlyChair {
        veloFarmer.swapUSDCtoUSDCNative(usdcAmount);
    }

    function swapUSDCNativeToUSDC(uint usdcAmount) external onlyChair {
        veloFarmer.swapUSDCNativeToUSDC(usdcAmount);
    }

    function resign() external onlyChair {
        veloFarmer.resign();
    }
}
