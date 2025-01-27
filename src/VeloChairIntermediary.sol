//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.21;

interface IVeloFarmer {
    function withdrawLiquidity(uint dolaAmount) external;
    function withdrawLiquidityAndSwapToDOLA(uint dolaAmount) external;
    function withdrawToL1OptiFed(uint dolaAmount) external;
    function withdrawToL1OptiFed(uint dolaAmount, uint usdcAmount) external;
    function withdrawTokensToL1(address l2Token, uint amount) external;
    function swapUSDCtoDOLA(uint usdcAmount) external;
    function swapDOLAtoUSDC(uint dolaAmount) external;
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

    function withdrawToL1OptiFed(uint dolaAmount, uint usdcAmount) external onlyChair {
        veloFarmer.withdrawToL1OptiFed(dolaAmount, usdcAmount);
    }

    function withdrawTokensToL1(address l2Token, uint amount) external onlyChair{
        veloFarmer.withdrawTokensToL1(l2Token, amount);
    }

    function swapUSDCtoDOLA(uint usdcAmount) external onlyChair {
        veloFarmer.swapUSDCtoDOLA(usdcAmount);
    }

    function swapDOLAtoUSDC(uint dolaAmount) external onlyChair {
        veloFarmer.swapDOLAtoUSDC(dolaAmount);
    }

    function resign() external onlyChair {
        veloFarmer.resign();
    }
}
