pragma solidity 0.6.12;

import "./libs/IBEP20.sol";

interface IAffiliateManager {

	function hasAffiliate(address userAddress) external view returns(bool);

	function hasAffiliate(address userAddress, uint256 partnerId) external view returns(bool);	

	function payAffiliateInTokensFromCaller(address userAddress, IBEP20 token, uint256 amount) external returns(bool);

	function payAffiliateInTokensFromPartner(address userAddress, IBEP20 token, uint256 amount) external returns(bool);

	function payAffiliateInTokensTransferred(address userAddress, IBEP20 token, uint256 amount, bool burnOnFail) external returns(bool);
	
	function payAffiliateInTokensWithCallback(address userAddress, IBEP20 token, uint256 amount) external returns(bool);

	function payAffiliate(address userAddress) external payable returns(bool);

	function payAffiliateWithCallback(address userAddress, uint256 amount) external returns(bool);

	function setAffiliate(address userAddress, address affiliateAddress) external returns(bool);

	function setAffiliate(address userAddress, string memory affiliateName) external returns(bool);

	function getUserStatus(address userAddress) external view returns(bool, bool);

	function isPartnerContract(address contractAddress) external view returns (bool);
}