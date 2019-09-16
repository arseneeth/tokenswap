pragma solidity ^0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
// import "@aragon/os/contracts/lib/math/SafeMath.sol";


contract TokenSwap is AragonApp{

	/// ACL
    bytes32 constant public ADMIN_ROLE = keccak256("ADMIN_ROLE");

	/// State
	uint256 public value;

    function initialize() public onlyInit {
        initialized();
    }

    /**
     * @notice Sets value of a variable
     * @param _value Value to set
     */
    function setValue(uint256 _value) public auth(ADMIN_ROLE) {
    	value = _value;
    }

}