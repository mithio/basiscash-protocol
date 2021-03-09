pragma solidity ^0.6.0;

interface IStakingRewardsv2 {
    function balanceOf(address account) external view returns (uint256);

    function exit() external;

    function getReward() external;

    function stakeLockedFor(address user, uint256 amount, uint256 convertedAmount) external;

    function totalSupply() external view returns (uint256);

    function totalRewardAmount() external view returns (uint256);

    function totalRewardBurned() external view returns (uint256);

    function calculateRewardAmount(uint256 convertedAmount) external view returns (uint256);

    function getRedeemableReward(address user) external view returns (uint256);
}
