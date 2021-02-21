pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import '../utils/ContractGuard.sol';
// Inheritance
import "../interfaces/ILpMigratorRecipient.sol";
import "../interfaces/IStakingRewardsv2.sol";
import '../interfaces/IOracle.sol';
import '../utils/Epoch.sol';


contract StakingRewardsv2 is IStakingRewardsv2, ILpMigratorRecipient, ContractGuard, Operator, Epoch {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    uint256 constant private ONE_DOLLAR_PRICE = 1000000;
    uint256 constant TOTAL_EPOCH = 10;
    /* ========== STATE VARIABLES ========== */

    IERC20 public rewardsToken;
    IERC20 public stakingToken;
    uint256 public unlockEpoch;
    bool public isStartRewards;
    mapping(address => uint256) public rewardsPaid;
    mapping(address => uint256) public rewards;

    uint256 private _totalRewardAmount;
    uint256 private _totalRewardBurned;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    //Tokens
    address public cash_old;
    //Contracts
    address public cashOracle;
    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _lpMigrator,
        address _rewardsToken,
        address _stakingToken,
        address _cash_old,
        address _cashOracle,
        uint256 _startTime,
        uint256 _unlockEpoch
    )   Epoch(7 days, _startTime, 0) public
    {
        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);
        lpMigrator = _lpMigrator;
        cash_old = _cash_old;
        cashOracle = _cashOracle;
        unlockEpoch = _unlockEpoch;
    }

    /* ========== VIEWS ========== */

    function getOraclePrice() public view returns (uint256) {
        try IOracle(cashOracle).consult(cash_old, 1e18) returns (uint256 price) {
            return price;
        } catch {
            revert('StakingRewards: failed to consult cash price from the oracle');
        }
    }

    function totalRewardAmount() external view override returns (uint256) {
        return _totalRewardAmount;
    }

    function totalRewardBurned() external view override returns (uint256) {
        return _totalRewardBurned;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function calculateRewardAmount(uint256 convertedAmount) public view override returns (uint256) {
        uint256 price = getOraclePrice();
        // no reward if MICv1 price > 1
        if (price > ONE_DOLLAR_PRICE) {
            return 0;
        }
        // rewards = MIC V1 converted * 1 / x - 1
        return convertedAmount.mul(ONE_DOLLAR_PRICE).div(getOraclePrice()).sub(convertedAmount);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function _burnReward(address user, uint256 amount) private {
        uint256 currentReward = rewards[user];
        require(currentReward.sub(amount) >= rewardsPaid[user], 'StakingRewards: reward burned should not exceed total reward');
        rewards[user] = rewards[user].sub(amount);
        _totalRewardBurned = _totalRewardBurned.add(amount);
        _totalRewardAmount = _totalRewardAmount.sub(amount);
        emit RewardBurn(user, amount);
    }

    function getRedeemableReward(address user) public view override returns (uint256){
        uint256 reward = rewards[user];
        if (getCurrentEpoch() >= TOTAL_EPOCH) {
            return reward;
        }
        uint256 multiplier = ONE_DOLLAR_PRICE.mul(getCurrentEpoch()).div(TOTAL_EPOCH);
        return reward.mul(multiplier).div(ONE_DOLLAR_PRICE);
    }

    function getReward() public override onlyOneBlock checkUnlock {
        uint256 rewardPaid = rewardsPaid[msg.sender];
        uint256 redeemableReward = getRedeemableReward(msg.sender);
        if (rewardPaid < redeemableReward) {
            uint256 currentRewardAmount = redeemableReward.sub(rewardPaid);
            rewardsPaid[msg.sender] = rewardsPaid[msg.sender].add(currentRewardAmount);
            rewardsToken.safeTransfer(msg.sender, currentRewardAmount);
            emit RewardPaid(msg.sender, currentRewardAmount);
        }
    }

    function _withdrawFor(address user, uint256 amount) private {
        require(amount > 0, "StakingRewards: Cannot withdraw 0");
        _totalSupply = _totalSupply.sub(amount);
        _balances[user] = _balances[user].sub(amount);
        stakingToken.safeTransfer(user, amount);
        emit Withdrawn(user, amount);
    }

    function exit() public override checkUnlock {
        // reward will be burned when users exit.  get redeemable reward before exit.  
        getReward();
        uint256 unredeemedReward = rewards[msg.sender].sub(rewardsPaid[msg.sender]);
        _burnReward(msg.sender, unredeemedReward);
        _withdrawFor(msg.sender, _balances[msg.sender]);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    // calculate the amount of MICv2 users can get for converted amount

    function startRewards() public onlyOperator checkStartTime {
        require(!isStartRewards, 'StakingRewards: Rewards already started');
        isStartRewards = true;
        rewardsToken.safeTransferFrom(msg.sender, address(this), _totalRewardAmount);
    }


    // stakeLockedFor locked MICV2 LP Token and distribute reward according to converted MICv1 amount
    function stakeLockedFor(address user, uint256 stakeAmount, uint256 convertedAmount) external override onlyLpMigrator {
        require(getOraclePrice() < ONE_DOLLAR_PRICE, 'StakingRewards: Cannot stake while price > 1');
        require(stakeAmount > 0, 'StakingRewards: Cannot stake 0');
        require(!isStartRewards, 'StakingRewards: Cannot stake after start time');
        _totalSupply = _totalSupply.add(stakeAmount);
        _balances[user] = _balances[user].add(stakeAmount);

        uint256 rewardAmount = calculateRewardAmount(convertedAmount);
        rewards[user] = rewards[user].add(rewardAmount);
        _totalRewardAmount = _totalRewardAmount.add(rewardAmount);
        stakingToken.safeTransferFrom(user, address(this), stakeAmount);
        emit Staked(user, stakeAmount);
        emit RewardAdded(rewardAmount);
    }

    // Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(stakingToken), "StakingRewards: Cannot withdraw the staking token");
        IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /* ========== MODIFIERS ========== */

    modifier checkUnlock {
        require(getCurrentEpoch() >= unlockEpoch, 'StakingRewards: not unlocked yer');

        _;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardBurn(address indexed user, uint256 reward);
    event Recovered(address token, uint256 amount);
}
