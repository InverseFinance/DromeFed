// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IERC20} from "src/interfaces/IERC20.sol";

contract MockExchangeProxy {
    IERC20 dola;

    constructor(address _dola) {
        dola = IERC20(_dola);
    }

    function swapDolaIn(
        address collateral,
        uint256 dolaAmount,
        uint256 collateralAmount
    ) external returns (bool success, bytes memory ret) {
        dola.transferFrom(msg.sender, address(this), dolaAmount);
        IERC20(collateral).transfer(msg.sender, collateralAmount);
        success = true;
    }

    function swapDolaOut(
        address collateral,
        uint256 collateralAmount,
        uint256 dolaAmount
    ) external returns (bool success, bytes memory ret) {
        IERC20(collateral).transferFrom(
            msg.sender,
            address(this),
            collateralAmount
        );
        dola.transfer(msg.sender, dolaAmount);
        success = true;
    }
}
