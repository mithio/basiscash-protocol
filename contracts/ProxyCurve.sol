pragma solidity ^0.6.2;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import "./interfaces/ICurveMeta2.sol";
import './owner/Operator.sol';
import './Cashv2.sol';
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
    }

    
    /// @notice Perform an exchange from MIC to one of the 3CRV tokens (frontend should only use this contract when selling MIC, otherwise use the metapool contract itself)
    /// @dev Index values can be found via the `underlying_coins` public getter method
    /// @param j Index value of the underlying coin to recieve
    /// @param dx Amount of MIC being exchanged
    /// @param min_dy Minimum amount of `j` to receive, should be calculated on the website based on `transferToAmount` (the amount remaining after the tax)
    /// @param _receiver Address that receives `j`
    /// @return Actual amount of `j` received
    function exchangeMIC(uint128 j, uint256 dx, uint256 min_dy, address _receiver) external returns (uint256) {
        //Transfer tokens from the caller
        IERC20(cash).safeTransferFrom(msg.sender, address(this), dx);

        if(IFeeChecker(feeChecker).isTransferTaxed2()) {
            //Calculate tax
            uint256 feeAmount = IFeeChecker(feeChecker).calculateFeeAmount(address(this), pool, dx);
            uint256 transferToAmount = dx.sub(feeAmount);

            //Send to fee distributor
            IERC20(cash).safeTransfer(feeDistributor, feeAmount);
            IFeeDistributor(feeDistributor).addFee(feeAmount);

            //Approve Curve metapool and exchange the amount remaining after the tax
            IERC20(cash).safeApprove(pool, 0);
            IERC20(cash).safeApprove(pool, transferToAmount);
            //For metapools: 0 = the token (i.e. Frax, MIC, etc), 1 = DAI, 2 = USDC, 3 = USDT
            ICurveMeta2(pool).exchange_underlying(0, j, transferToAmount, min_dy, msg.sender);
        }
        else {
            //Transaction isn't taxed, so just do a normal swap
            //To save gas, the website should use the metapool contract when transactions aren't taxed
            IERC20(cash).safeApprove(pool, 0);
            IERC20(cash).safeApprove(pool, dx);
            ICurveMeta2(pool).exchange_underlying(0, j, dx, min_dy, msg.sender);
        }
    }

    //function exchange_underlying(uint128 i, uint128 j, uint256 dx, uint256 min_dy, address _receiver) external returns (uint256) {

    //Give the Curve depositer infinite spending privileges, unless we want to spend gas checking the amount of tokens each time someone deposits
    //No tokens actually remain within this contract after a transaction
    //function approveForever(address tokenAddress) public onlyOperator {
    //    IERC20(tokenAddress).approve(pool, 115792089237316195423570985008687907853269984665640564039457584007913129639935);
    //}

    function setFeeCheckerAddress(address _address) public onlyOperator {
        feeChecker = _address;
    }

    function setFeeDistributorAddress(address _address) public onlyOperator {
        feeDistributor = _address;
    }
}
