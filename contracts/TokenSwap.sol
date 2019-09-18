pragma solidity ^0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/os/contracts/lib/math/SafeMath.sol";
import "@aragon/os/contracts/common/SafeERC20.sol";
import "./bancor-formula/BancorFormula.sol";


// BancorFormula Token A ==> BaseToken == Token B

contract TokenSwap is AragonApp {
    using SafeERC20 for ERC20;    
    using SafeMath for uint256;

    IBancorFormula public formula;
    ERC20          public token;
    
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