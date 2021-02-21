pragma solidity ^0.6.0;

import '@openzeppelin/contracts/access/Ownable.sol';

abstract contract ILpMigratorRecipient is Ownable {
    address public lpMigrator;

    modifier onlyLpMigrator() {
        require(
            _msgSender() == lpMigrator,
            'Caller is not LpMigrator'
        );
        _;
    }

    function setLpMigrator(address _lpMigrator)
        external
        virtual
        onlyOwner
    {
        lpMigrator = _lpMigrator;
    }
}
