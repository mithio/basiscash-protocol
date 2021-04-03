pragma solidity ^0.6.2;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import './owner/Operator.sol';
import "./interfaces/ICurveMeta2.sol";
import './interfaces/IFeeChecker.sol';
import './interfaces/IFeeDistributor.sol';

contract ProxyCurve is Operator {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public pool; //Address of the Curve metapool
    address public cash; //Address of the Curve metapool
    address public feeChecker; //Checks whether a transaction is taxed and returns the tax amount
    address public feeDistributor; //Handles distributing the tax

    constructor(address _pool, address _cash) public {
        pool = _pool;
        cash = _cash;

        //Giving infinite approval to the pool allows me to skip the two safeApprove() calls, which saves 20k gas
        IERC20(_cash).approve(_pool, 115792089237316195423570985008687907853269984665640564039457584007913129639935);
    }

    
    /// @notice Deposit coins into the pool
    /// @param _amount of MIC to deposit
    /// @param _min_mint_amount Minimum amount of LP tokens to mint from the deposit, should be calculated on the website based on `transferToAmount` (the amount remaining after the tax)
    /// @return Amount of LP tokens received by depositing (after taxes if applicable)
    function add_liquidity(uint256 _amount, uint256 _min_mint_amount) external returns (uint256) {
        //Transfer MIC from caller to contract 
        IERC20(cash).safeTransferFrom(msg.sender, address(this), _amount);

        if(IFeeChecker(feeChecker).isTransferTaxed2()) {
            //Calculate tax
            uint256 feeAmount = IFeeChecker(feeChecker).calculateFeeAmount(address(this), pool, _amount);
            uint256 transferToAmount = _amount.sub(feeAmount);

            //Send to fee distributor
            //Note: addFee can only be called by the Cash token, I need to allow FeeDistributor to have a whitelist instead
            IERC20(cash).safeTransfer(feeDistributor, feeAmount);
            IFeeDistributor(feeDistributor).addFee(feeAmount);

            //Approve Curve metapool and exchange the amount remaining after the tax
            //IERC20(cash).safeApprove(pool, 0);
            //IERC20(cash).safeApprove(pool, transferToAmount);

            //Add liquidity to pool (add_liquidity sends LP tokens to address provided as final argument)
            return ICurveMeta2(pool).add_liquidity([transferToAmount, 0], _min_mint_amount, msg.sender);
        }
        else {
            //To save gas, the website should use the metapool contract itself when transactions aren't taxed
            ICurveMeta2(pool).add_liquidity([_amount, 0], _min_mint_amount, msg.sender);
        }
    }

    /// @notice Perform an exchange from MIC to one of the 3CRV tokens (frontend should only use this contract when selling MIC, otherwise use the metapool contract itself)
    /// @dev Index values can be found via the `underlying_coins` public getter method
    /// @param j Index value of the underlying coin to recieve
    /// @param dx Amount of MIC being exchanged
    /// @param min_dy Minimum amount of `j` to receive, should be calculated on the website based on `transferToAmount` (the amount remaining after the tax)
    /// @return Actual amount of `j` received
    function exchangeMIC(int128 j, uint256 dx, uint256 min_dy) external returns (uint256) {
        //Transfer tokens from the caller
        IERC20(cash).safeTransferFrom(msg.sender, address(this), dx);

        if(IFeeChecker(feeChecker).isTransferTaxed2()) {
            //Calculate tax
            uint256 feeAmount = IFeeChecker(feeChecker).calculateFeeAmount(address(this), pool, dx);
            uint256 transferToAmount = dx.sub(feeAmount);

            //Send to fee distributor
            //Note: addFee can only be called by the Cash token, I need to allow FeeDistributor to have a whitelist instead
            IERC20(cash).safeTransfer(feeDistributor, feeAmount);
            IFeeDistributor(feeDistributor).addFee(feeAmount);

            //Approve Curve metapool and exchange the amount remaining after the tax
            //IERC20(cash).safeApprove(pool, 0);
            //IERC20(cash).safeApprove(pool, transferToAmount);

            //For metapools: 0 = the token (i.e. Frax, MIC, etc), 1 = DAI, 2 = USDC, 3 = USDT
            //_receiver = msg.sender, so tokens are sent to the user 
            ICurveMeta2(pool).exchange_underlying(0, j, transferToAmount, min_dy, msg.sender);
        }
        else {
            //Transaction isn't taxed, so just do a normal swap
            //To save gas, the website should use the metapool contract when transactions aren't taxed
            //IERC20(cash).safeApprove(pool, 0);
            //IERC20(cash).safeApprove(pool, dx);
            //function exchange_underlying(int128 i, int128 j, uint256 dx, uint256 min_dy, address _receiver) external returns (uint256);
            ICurveMeta2(pool).exchange_underlying(0, j, dx, min_dy, msg.sender);
        }
    }

    function setFeeCheckerAddress(address _address) public onlyOperator {
        feeChecker = _address;
    }

    function setFeeDistributorAddress(address _address) public onlyOperator {
        feeDistributor = _address;
    }
}
