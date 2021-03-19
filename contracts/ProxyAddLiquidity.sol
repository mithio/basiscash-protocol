pragma solidity ^0.6.2;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import "./interfaces/ICurveMeta.sol";

contract ProxyAddLiquidity {
    using SafeERC20 for IERC20;

    uint128 NUM_COINS = 4; //MIC, DAI, USDC, USDT

    address public curveDepositer = 0xA79828DF1850E8a3A3064576f380D90aECDD3359;

    address public pool; //Address of the Curve metapool
    address[4] coins;

    constructor(address _pool, address _cash) public {
        pool = _pool;
        
        coins[0] = _cash;
        coins[1] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; //dai
        coins[2] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; //usdc
        coins[3] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; //usdt
    }

    function add_liquidity(uint256[4] memory _amounts, uint256 _min_mint_amount) external returns (uint256) {
        //Transfer tokens from caller to contract 
        for (uint i = 0; i < NUM_COINS; i++) {
            uint256 amount = _amounts[i];
            if (amount > 0) {
                IERC20(coins[i]).safeTransferFrom(msg.sender, address(this), amount);
                IERC20(coins[i]).safeApprove(curveDepositer, 0);
                IERC20(coins[i]).safeApprove(curveDepositer, amount);
            }
        }
        //Add liquidity to pool
        ICurveMeta(curveDepositer).add_liquidity(pool, _amounts, _min_mint_amount);
        //Send tokens back to user
        uint256 lpBalance = IERC20(pool).balanceOf(address(this));
        IERC20(pool).safeTransfer(msg.sender, lpBalance);
    }
}
