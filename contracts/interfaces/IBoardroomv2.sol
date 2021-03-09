pragma solidity ^0.6.0;

interface IBoardroomv2 {
    function allocateSeigniorage(uint256 amount) external;
    function allocateTaxes(uint256 amount) external;
}
