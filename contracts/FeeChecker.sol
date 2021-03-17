pragma solidity ^0.6.0;

import '@openzeppelin/contracts/math/SafeMath.sol';
import './interfaces/IFeeChecker.sol';
import './interfaces/IOracle.sol';
import './owner/Operator.sol';

contract FeeChecker is IFeeChecker, Operator {
    using SafeMath for uint256;

    IOracle public oracle;
    address public tokenAddress;
    address constant stakeLockContract = 0xE144303f7FC3E99A9dE5474fD6c7B40add83a1dA;
    uint256 tax_below_price = 1e18; //The value of $1 worth of Basis returned by the oracle ( 18 decimals, which is why we do oracle.consult(tokenAddress, 10 ** 18) )

    //If price < tax_below_price, sending Basis to addresses in feeList will have a fee
    mapping(address => bool) public feeList;

    //Addresses in whiteList are allowed to send transactions to addresses in feeList
    mapping(address => bool) public whiteList; 

    constructor(address _tokenAddress) public {
        tokenAddress = _tokenAddress;
    }

    /* ========== VIEW FUNCTIONS ========== */

    //Checks in the Cashv2 contract if the transfer is allowed, blocks transfers to addresses in feeList if sender isn't in whiteList
    function isTransferTaxed(address sender, address recipient) 
        external 
        override
        view
        returns (bool) 
    {
        if(oracle.consult(tokenAddress, 10 ** 18) < tax_below_price) {
            require(feeList[recipient] == false || whiteList[sender] == true, "Please use the main website when selling MIC");
        }
        return false;
    }

    //This is ugly, but creating a duplicate function to keep "is the transfer taxed?" logic in one file is better than splitting it between multiple files
    //Used by the ProxyCurve contract
    function isTransferTaxed2() 
        external 
        override
        view
        returns (bool) 
    {
        return oracle.consult(tokenAddress, 10 ** 18) < tax_below_price;
    }


    //Right now sender/recipient args aren't used, but they may be in the future
    function calculateFeeAmount(address sender, address recipient, uint256 amount) 
        external 
        override
        view 
        returns (uint256 feeAmount)
    {
        if (sender == stakeLockContract) {
            return amount.mul(7500).div(10000);
        }
        if (recipient == stakeLockContract) {
            // stop users from transferring to the lock contract.
            return amount;
        }
        feeAmount = amount.mul(calculateTaxPercent()).div(tax_below_price.mul(tax_below_price));
    }

    //Tax = 1 - currPrice ** 2
    function calculateTaxPercent() 
        public 
        view 
        returns (uint256 taxPercent)
    {
        uint256 currPrice = oracle.consult(tokenAddress, 10 ** 18);
        taxPercent = tax_below_price.mul(tax_below_price) - currPrice.mul(currPrice);
    }

    /* ========== GOVERNANCE ========== */
    function addToFeeList(address _address) public onlyOperator {
        feeList[_address] = true;
    }

    function removeFromFeeList(address _address) public onlyOperator {
        feeList[_address] = false;
    }

    function addToWhiteList(address _address) public onlyOperator {
        whiteList[_address] = true;
    }

    function removeFromWhiteList(address _address) public onlyOperator {
        whiteList[_address] = false;
    }
    
    function setOracle(address _address) public onlyOperator {
        oracle = IOracle(_address);
    }
}
