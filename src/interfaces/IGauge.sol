pragma solidity ^0.8.13;

interface IGauge {
    function deposit(uint256 amount) external;
    function getReward(address account) external;
    function notifyRewardAmount(uint256 amount) external;
    function withdraw(uint256 shares) external;
    function balanceOf(address account) external returns (uint256);
    function voter() external view returns (address);
    function rewardToken() external view returns (address);
    function stakingToken() external view returns (address);
}
