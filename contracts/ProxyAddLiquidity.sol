pragma solidity ^0.6.2;

import './IERC20.sol';
import './SafeERC20.sol';
import "./ICurveMeta2.sol";

contract ProxyAddLiquidity {
    using SafeERC20 for IERC20;

    address public pool; //Address of the Curve metapool
    address public cash;

    constructor(address _pool, address _cash) public {
        pool = _pool;
        cash = _cash;
    }

    function add_liquidity(uint256 _amount, uint256 _min_mint_amount) external returns (uint256) {
        //Transfer MIC from caller to contract 
        IERC20(cash).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(cash).safeApprove(pool, 0);
        IERC20(cash).safeApprove(pool, _amount);

        //Add liquidity to pool (add_liquidity sends LP tokens to address provided as final argument)
        ICurveMeta2(pool).add_liquidity([_amount, 0], _min_mint_amount, msg.sender);
    }
}
