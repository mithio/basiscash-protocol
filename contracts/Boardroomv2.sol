pragma solidity ^0.6.0;
//pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import './utils/ContractGuard.sol';
import './utils/Epoch.sol';
import './ProRataRewardCheckpoint.sol';
import './interfaces/IFeeDistributorRecipient.sol';

contract ShareWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public share;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public virtual {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        share.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        uint256 directorShare = _balances[msg.sender];
        require(
            directorShare >= amount,
            'Boardroom: withdraw request greater than staked amount'
        );
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = directorShare.sub(amount);
        share.safeTransfer(msg.sender, amount);
    }
}

contract Boardroomv2 is ShareWrapper, ContractGuard, Epoch, ProRataRewardCheckpoint, IFeeDistributorRecipient{
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========== DATA STRUCTURES ========== */

    struct Boardseat {
        uint256 lastSnapshotIndex;
        uint256 startEpoch;
        uint256 lastEpoch;
        mapping(uint256 => uint256) rewardEarned;
    }

    struct BoardSnapshot {
        uint256 time;
        uint256 rewardReceived;
        uint256 rewardPerShare;
    }

    /* ========== STATE VARIABLES ========== */

    IERC20 private cash;

    mapping(address => Boardseat) private directors;
    BoardSnapshot[] private boardHistory;

    /* ========== CONSTRUCTOR ========== */

    constructor(IERC20 _cash, IERC20 _share, uint256 _startTime) 
        public Epoch(6 hours, _startTime, 0)
        ProRataRewardCheckpoint(6 hours, _startTime, address(_share))
    {
        cash = _cash;
        share = _share;

        BoardSnapshot memory genesisSnapshot = BoardSnapshot({
            time: block.number,
            rewardReceived: 0,
            rewardPerShare: 0
        });
        boardHistory.push(genesisSnapshot);
    }

    /* ========== Modifiers =============== */
    modifier directorExists {
        require(
            balanceOf(msg.sender) > 0,
            'Boardroom: The director does not exist'
        );
        _;
    }

    modifier updateReward(address director) {
        if (director != address(0)) {
            Boardseat storage seat = directors[director];
            uint256 currentEpoch = getCurrentEpoch();

            seat.rewardEarned[currentEpoch] = seat.rewardEarned[currentEpoch].add(earnedNew(director));
            seat.lastEpoch = currentEpoch;
            seat.lastSnapshotIndex = latestSnapshotIndex();
        }
        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function calculateClaimableRewardsForEpoch(address wallet, uint256 epoch) view public returns (uint256) {
        return calculateClaimable(directors[wallet].rewardEarned[epoch], epoch);
    }
    
    function calculateClaimable(uint256 earned, uint256 epoch) view public returns (uint256) {
        uint256 epoch_delta = getCurrentEpoch() - epoch;

        uint256 ten = 10;
        uint256 five = 5;
        uint256 tax_percentage = (epoch_delta > 4) ? 0 : ten.mul(five.sub(epoch_delta));

        uint256 hundred = 100;
        return earned.mul(hundred.sub(tax_percentage)).div(hundred);
    }

    // staking before start time regards as staking at epoch 0.  
    function getCheckpointEpoch() view public returns(uint128) {
        uint256 currentEpoch = getCurrentEpoch();
        return uint128(currentEpoch) + 1;

    }

    // =========== Snapshot getters

    function latestSnapshotIndex() public view returns (uint256) {
        return boardHistory.length.sub(1);
    }

    function getLatestSnapshot() internal view returns (BoardSnapshot memory) {
        return boardHistory[latestSnapshotIndex()];
    }

    function getLastSnapshotIndexOf(address director)
        public
        view
        returns (uint256)
    {
        return directors[director].lastSnapshotIndex;
    }

    function getLastSnapshotOf(address director)
        internal
        view
        returns (BoardSnapshot memory)
    {
        return boardHistory[getLastSnapshotIndexOf(director)];
    }

    // =========== Director getters

    function rewardPerShare() public view returns (uint256) {
        return getLatestSnapshot().rewardPerShare;
    }

    function earned(address director) public view returns (uint256) {
        uint256 totalRewards = 0;
        
        for (uint i = directors[director].startEpoch; i <= directors[director].lastEpoch; i++) {
            totalRewards = totalRewards.add(calculateClaimableRewardsForEpoch(director, i));
        }

        return totalRewards;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount)
        public
        override
        onlyOneBlock
        updateReward(msg.sender)
    {
        require(amount > 0, 'Boardroom: Cannot stake 0');
        uint256 previousBalance = balanceOf(msg.sender);
        super.stake(amount);
        if (directors[msg.sender].startEpoch != 0) {
            directors[msg.sender].startEpoch = getCurrentEpoch();
        }
        depositCheckpoint(msg.sender, amount, previousBalance, getCheckpointEpoch());

        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount)
        public
        override
        onlyOneBlock
        directorExists
        updateReward(msg.sender)
    {
        require(amount > 0, 'Boardroom: Cannot withdraw 0');
        uint256 previousBalance = balanceOf(msg.sender);
        super.withdraw(amount);
        withdrawCheckpoint(msg.sender, amount, previousBalance, getCheckpointEpoch());
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        
        claimReward(earned(msg.sender));
    }

    function claimReward(uint256 amount) 
        public
        updateReward(msg.sender) 
    {
        require(amount > 0, 'Amount cannot be zero');

        uint256 totalEarned = earned(msg.sender);
        require(amount <= totalEarned, 'Amount cannot be larger than total claimable rewards');

        cash.safeTransfer(msg.sender, amount);

        for (uint i = directors[msg.sender].startEpoch; amount > 0; i++) {
            uint256 claimable = calculateClaimableRewardsForEpoch(msg.sender, i);

            if (amount > claimable) {
                directors[msg.sender].rewardEarned[i] = 0;
                directors[msg.sender].startEpoch = i.add(1);
                amount = amount.sub(claimable);
            } else {
                removeRewardsForEpoch(msg.sender, amount, i);
                amount = 0;
            }
        }

        // In this case, startEpoch will be calculated again for the next stake
        if (amount == totalEarned) {
            directors[msg.sender].startEpoch = 0;
        }

        emit RewardPaid(msg.sender, amount);
    }

    // Claim rewards for specific epoch
    function claimRewardsForEpoch(uint256 amount, uint256 epoch) 
        public
        updateReward(msg.sender)
    {
        require(amount > 0, 'Amount cannot be zero');

        uint256 claimable = calculateClaimableRewardsForEpoch(msg.sender, epoch);

        if (claimable > 0) {
            require(
                amount <= claimable,
                'Amount cannot be larger than the claimable rewards for the epoch'
            );

            cash.safeTransfer(msg.sender, amount);

            removeRewardsForEpoch(msg.sender, amount, epoch);
        }
    }

    function allocateSeigniorage(uint256 amount)
        external
        onlyOneBlock
        onlyOperator
    {
        require(amount > 0, 'Boardroom: Cannot allocate 0');
        require(
            totalSupply() > 0,
            'Boardroom: Cannot allocate when totalSupply is 0'
        );

        // Create & add new snapshot
        BoardSnapshot memory latestSnapshot = getLatestSnapshot();
        uint256 prevRPS = latestSnapshot.rewardPerShare;
        uint256 poolSize = getEpochPoolSize(getCheckpointEpoch());
        uint256 nextRPS = prevRPS.add(amount.mul(1e18).div(poolSize));

        BoardSnapshot memory newSnapshot = BoardSnapshot({
            time: block.number,
            rewardReceived: amount,
            rewardPerShare: nextRPS
        });
        boardHistory.push(newSnapshot);

        cash.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardAdded(msg.sender, amount);
    }

    /*
     * manualEpochInit can be used by anyone to initialize an epoch based on the previous one
     * This is only applicable if there was no action (deposit/withdraw) in the current epoch.
     * Any deposit and withdraw will automatically initialize the current and next epoch.
     */
    function manualCheckpointEpochInit(uint128 checkpointEpochId) public {
        manualEpochInit(checkpointEpochId, getCheckpointEpoch());
    }

    function allocateTaxes(uint256 amount)
        external
        onlyOneBlock
        onlyFeeDistributor
    {
        require(amount > 0, 'Boardroom: Cannot allocate 0');
        require(
            totalSupply() > 0,
            'Boardroom: Cannot allocate when totalSupply is 0'
        );
        // Create & add new snapshot
        BoardSnapshot memory latestSnapshot = getLatestSnapshot();
        uint256 prevRPS = latestSnapshot.rewardPerShare;
        uint256 poolSize = getEpochPoolSize(getCheckpointEpoch());
        uint256 nextRPS = prevRPS.add(amount.mul(1e18).div(poolSize));

        BoardSnapshot memory newSnapshot = BoardSnapshot({
            time: block.number,
            rewardReceived: amount,
            rewardPerShare: nextRPS
        });
        boardHistory.push(newSnapshot);

        cash.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardAdded(msg.sender, amount);

    }

    function earnedNew(address director) private view returns (uint256) {
        uint256 latestRPS = getLatestSnapshot().rewardPerShare;
        uint256 storedRPS = getLastSnapshotOf(director).rewardPerShare;
        uint256 directorEffectiveBalance = getEpochUserBalance(director, getCheckpointEpoch());

        return
            directorEffectiveBalance.mul(latestRPS.sub(storedRPS)).div(1e18);
    }

    function removeRewardsForEpoch(address wallet, uint256 amount, uint256 epoch) private
        onlyOneBlock
    {
        uint256 claimable = calculateClaimableRewardsForEpoch(wallet, epoch);

        if (claimable > 0) {
            require(
                amount <= claimable,
                'Amount cannot be larger than the claimable rewards for the epoch'
            );

            directors[wallet].rewardEarned[epoch] = 
                claimable.sub(amount).mul(directors[wallet].rewardEarned[epoch]).div(claimable);
        }
    }

    /* ========== EVENTS ========== */

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);
}
