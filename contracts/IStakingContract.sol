pragma solidity 0.6.12;

interface IStakingContract {

    function balanceOf(address account) external view returns (uint256);

}