// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IShdV1  {
    function createShd() external;
    function setFees(uint256 ) external;
    function settle(uint256 ) external;
    function purchase(uint256 ) external ;
    function deposit(uint256 , uint256) external ;
    function setTokenURI(string memory ) external ;
    function withdraw(uint256 , uint256 ) external;
    function reclaim(uint256 , uint256 )  external;
    function withdrawAllForBeneficiary() external;
    function setPrice(uint256 , uint256 , uint256) external ;
    function _calculateDepositFees(uint256 ) external view  returns(uint256); 
    function _calculateCurrentUsageFees(uint256 )  external view  returns(uint256); 
    function _calculateTradeFees(uint256 ) external view  returns(uint256);
    function checkFundsOf(address ) external view  returns(uint256);
    function checkShdKeeper(uint256 ) external view  returns(address);
    function checkShdKeeperUsageTime(uint256 ) external view  returns(uint256);
    function getCurrentPrice(uint256 ) external view  returns (uint256); 
    function getCurrentShdKeeper(uint256 ) external view  returns (address);
    function getOwner() external view returns(address);
    function getUri() external view returns(string memory);
    function getTradeTime() external view returns(uint256);
}
