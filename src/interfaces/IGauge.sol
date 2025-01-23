pragma solidity ^0.8.13;

interface IGauge {
    function deposit(uint amount) external;
    function getReward(address account) external;
    function notifyRewardAmount(uint amount) external;
    function withdraw(uint shares) external;
    function balanceOf(address account) external returns (uint);
    function voter() external view returns(address);
}
