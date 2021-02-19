pragma solidity ^0.6.0;

// Inheritance
import "@openzeppelin/contracts/access/Ownable.sol";


// This is the fork from synthetix RewardsDistributionRecipient.
// https://docs.synthetix.io/contracts/source/contracts/rewardsdistributionrecipient
contract LpMigratorRecipient is Ownable {
    address public lpMigrator;


    modifier onlyLpMigrator() {
        require(msg.sender == lpMigrator, "Caller is not LpMigrator contract");
        _;
    }

    function setLpMigrator(address _lpMigrator) external onlyOwner {
        lpMigrator = _lpMigrator;
    }
}
