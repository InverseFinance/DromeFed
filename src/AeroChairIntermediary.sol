//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.21;

interface IAeroFarmer {
    function withdrawLiquidity(uint dolaAmount) external;
    function withdrawLiquidityAndSwapToDOLA(uint dolaAmount) external;
    function withdrawToL1BaseFed(uint dolaAmount) external;
    function withdrawToL1BaseFedNative(uint dolaAmount, uint usdcAmount) external;
    function withdrawToL1BaseFedNative(uint usdcAmount) external;
    function withdrawToL1BaseFedBridged(uint usdcAmount) external;
    function withdrawTokensToL1(address l2Token, uint amount) external;
    function swapUSDCtoDOLA(uint usdcAmount) external;
    function swapUSDCNativetoDOLA(uint usdcAmount) external;
    function swapDOLAtoUSDC(uint dolaAmount) external;
    function swapDOLAtoUSDCNative(uint dolaAmount) external;
    function swapUSDCtoUSDCNative(uint usdcAmount) external;
    function swapUSDCNativeToUSDC(uint usdcAmount) external;
    function resign() external;
}

contract AeroChairIntermediary {
    IAeroFarmer public aeroFarmer;
    address public chair;
    
    constructor(address _chair, address _aeroFarmer){
        chair = _chair;
        aeroFarmer = IAeroFarmer(_aeroFarmer);
    }

    modifier onlyChair() {
        require(msg.sender == chair, "ONLY MSG.SENDER");
        _;
    }

    function withdrawLiquidity(uint dolaAmount) external onlyChair {
        aeroFarmer.withdrawLiquidity(dolaAmount);
    }
 
    function withdrawLiquidityAndSwapToDOLA(uint dolaAmount) external onlyChair {
        aeroFarmer.withdrawLiquidityAndSwapToDOLA(dolaAmount);
    }

    function withdrawToL1BaseFed(uint dolaAmount) external onlyChair {
        aeroFarmer.withdrawToL1BaseFed(dolaAmount);
    }

    function withdrawToL1BaseFedNative(uint dolaAmount, uint usdcAmount) external onlyChair {
        aeroFarmer.withdrawToL1BaseFedNative(dolaAmount, usdcAmount);
    }

    function withdrawToL1BaseFedNative(uint usdcAmount) external onlyChair {
        aeroFarmer.withdrawToL1BaseFedNative(usdcAmount);
    }

    function withdrawToL1BaseFedBridged(uint usdcAmount) external onlyChair {
        aeroFarmer.withdrawToL1BaseFedBridged(usdcAmount);
    }

    function withdrawTokensToL1(address l2Token, uint amount) external onlyChair{
        aeroFarmer.withdrawTokensToL1(l2Token, amount);
    }

    function swapUSDCtoDOLA(uint usdcAmount) external onlyChair {
        aeroFarmer.swapUSDCtoDOLA(usdcAmount);
    }

    function swapUSDCNativetoDOLA(uint usdcAmount) external onlyChair {
        aeroFarmer.swapUSDCNativetoDOLA(usdcAmount);
    }

    function swapDOLAtoUSDC(uint dolaAmount) external onlyChair {
        aeroFarmer.swapDOLAtoUSDC(dolaAmount);
    }

    function swapDOLAtoUSDCNative(uint dolaAmount) external onlyChair {
        aeroFarmer.swapDOLAtoUSDCNative(dolaAmount);
    }

    function swapUSDCtoUSDCNative(uint usdcAmount) external onlyChair {
        aeroFarmer.swapUSDCtoUSDCNative(usdcAmount);
    }

    function swapUSDCNativeToUSDC(uint usdcAmount) external onlyChair {
        aeroFarmer.swapUSDCNativeToUSDC(usdcAmount);
    }

    function resign() external onlyChair {
        aeroFarmer.resign();
    }
}
