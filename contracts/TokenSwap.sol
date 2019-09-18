pragma solidity ^0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/os/contracts/lib/math/SafeMath.sol";
import "@aragon/os/contracts/common/SafeERC20.sol";
import "./bancor-formula/BancorFormula.sol";


contract TokenSwap is AragonApp {
    using SafeERC20 for ERC20;    
    using SafeMath for uint256;

    IBancorFormula public formula;
    ERC20          public token;
    uint256        public poolBalance;
    uint32         public reserveRatio;


	/// ACL
    bytes32 constant public ADMIN_ROLE = keccak256("ADMIN_ROLE");

    function initialize() public onlyInit {
        initialized();
    }

    function buy(uint totalSupply_) public payable returns(bool) {
        require(msg.value > 0);
        uint256 tokensToMint = formula.calculatePurchaseReturn(totalSupply_, poolBalance, reserveRatio, msg.value);
        totalSupply_ = totalSupply_.add(tokensToMint);
        //balances[msg.sender] = balances[msg.sender].add(tokensToMint);
        poolBalance = poolBalance.add(msg.value);
        // LogMint(tokensToMint, msg.value);
        return true;
    }

    function sell(uint256 sellAmount, uint totalSupply_) public returns(bool) {
        //require(sellAmount > 0 && balances[msg.sender] >= sellAmount);
        uint256 ethAmount = formula.calculateSaleReturn(totalSupply_, poolBalance, reserveRatio, sellAmount);
        msg.sender.transfer(ethAmount);
        poolBalance = poolBalance.sub(ethAmount);
        //balances[msg.sender] = balances[msg.sender].sub(sellAmount);
        totalSupply_ = totalSupply_.sub(sellAmount);
        // LogWithdraw(sellAmount, ethAmount);
        return true;
    }


}