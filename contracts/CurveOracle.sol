pragma solidity ^0.6.0;

import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import './lib/Babylonian.sol';
import './lib/FixedPoint.sol';
import './lib/UniswapV2Library.sol';
import './lib/UniswapV2OracleLibrary.sol';
import './utils/Epoch.sol';
import './interfaces/IUniswapV2Pair.sol';
import './interfaces/IUniswapV2Factory.sol';


interface ICurve {
    function balances(uint256 i) external returns (uint256);
    function coins(uint256 i) external returns (address);
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
}

// fixed window oracle that recomputes the average price for the entire period once every period
// note that the price average is only guaranteed to be over at least 1 period, but may be over a longer period
contract CurveOracle is Epoch {
    using FixedPoint for *;
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    // curve
    address public token0;
    address public token1;
    uint256 public token0Decimals;
    uint256 public token1Decimals;
    ICurve public stableSwap;

    // oracle
    uint32 public blockTimestampLast;
    uint256 public price0Last;
    uint256 public price1Last;
    FixedPoint.uq112x112 public price0Average;
    FixedPoint.uq112x112 public price1Average;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _stableSwap,
        uint256 _period,
        uint256 _startTime
    ) public Epoch(_period, _startTime, 0) {
        stableSwap = ICurve(_stableSwap);
        token0 = stableSwap.coins(0);
        token1 = stableSwap.coins(1);
        token0Decimals = ERC20(token0).decimals();
        token1Decimals = ERC20(token1).decimals();
        // Since MICv2 needs to query an oracle to transfer, we need to set-up one before depositing tokens into
        // Swap Pool.  Set default price = 1.
        price0Last = 10**token0Decimals;
        price1Last = 10**token1Decimals;

        price0Average =  FixedPoint.fraction(uint112(price0Last), uint112(price0Last));
        price1Average = FixedPoint.fraction(uint112(price1Last), uint112(price1Last));
    }

    function getTokensSpotPrice() public returns (uint256, uint256) {
        uint256 price0 = stableSwap.get_dy(0, 1, 10**token0Decimals);
        uint256 price1 = stableSwap.get_dy(1, 0, 10**token1Decimals);
        return (price0, price1);
    }

    /* ========== MUTABLE FUNCTIONS ========== */

    /** @dev Updates 1-day EMA price from Uniswap.  */
    function update() external checkEpoch {
        (uint256 price0, uint256 price1) = getTokensSpotPrice();

        price0Average =  FixedPoint.fraction(uint112(price0Last + price0), uint112(10**token0Decimals)).div(2);
        price1Average = FixedPoint.fraction(uint112(price1Last + price1), uint112(10**token1Decimals)).div(2);
        price0Last = price0;
        price1Last = price1;

        emit Updated(price0, price1);
    }

    // note this will always return 0 before update has been called successfully for the first time.
    function consult(address token, uint256 amountIn)
        external
        view
        returns (uint144 amountOut)
    {
        if (token == token0) {
            amountOut = price0Average.mul(amountIn).decode144();
        } else {
            require(token == token1, 'Oracle: INVALID_TOKEN');
            amountOut = price1Average.mul(amountIn).decode144();
        }
    }


    event Updated(uint256 price0, uint256 price1);
}
