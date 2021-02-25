pragma solidity ^0.6.0;

import '@openzeppelin/contracts/access/Ownable.sol';

abstract contract IFeeDistributorRecipient is Ownable {
    address public feeDistributor;

    modifier onlyFeeDistributor() {
        require(
            _msgSender() == feeDistributor,
            'Caller is not fee distributor'
        );
        _;
    }

    function setFeeDistributor(address _feeDistributor)
        external
        virtual
        onlyOwner
    {
        feeDistributor = _feeDistributor;
    }
}
