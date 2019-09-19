pragma solidity ^0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/os/contracts/lib/math/SafeMath.sol";
import "@aragon/os/contracts/common/SafeERC20.sol";
import "./bancor-formula/BancorFormula.sol";


contract TokenSwap is AragonApp {
    using SafeERC20 for ERC20;    
    using SafeMath for uint256;

    struct Pool{
        address provider;
        // address tokenA; // Base Asset  
        // address tokenB; // Reserve Asset
        uint256 tokenAsupply;
        uint256 tokenBsupply;
        uint32  reserveRatio;
        uint256 exchageRate; // A => B
    }
    
    Pool[]         public pools;
    IBancorFormula public formula;
    ERC20          public token;

    uint32  public constant PPM      = 1000000;  // parts per million

    function getReserveRatio(
        uint256 _exchangeRate, 
        uint256 _tokenSupply, 
        uint256 _totalTokenSupply
        ) internal 
          returns(uint32)
    {
        return uint32(uint256(PPM).mul(_tokenSupply.div(_exchangeRate.mul(_totalTokenSupply))));
    }


    function createPool(
        // address _tokenA, 
        // address _tokenB,
        uint256    _tokenAsupply,
        uint256    _tokenBsupply,
        uint256    _totalTokenBsupply, // TODO: change to ERC20 getSUpply!
        uint256    _exchangeRate // the price of token A in token B
        ) external 
          returns(bool)
    {
        uint _id = pools.length++;
        Pool storage p = pools[_id];

        uint32 _reserveRatio = getReserveRatio(_exchangeRate, 
                                               _tokenBsupply, 
                                               _totalTokenBsupply);

        p.provider     = msg.sender;
        // p.tokenA       = _tokenA;
        // p.tokenB       = _tokenB;
        p.tokenAsupply = _tokenAsupply;
        p.tokenBsupply = _tokenBsupply;
        p.reserveRatio = _reserveRatio;
        p.exchageRate  = _exchangeRate;

        return true;
    } 

	/// ACL
    bytes32 constant public ADMIN_ROLE = keccak256("ADMIN_ROLE");

    function initialize() public onlyInit {
        initialized();
    }

    // temporary
    // uint256 poolBalance;
    // uint32  reserveRatio;

    function buy(uint256 _poolId, uint256 _buyAmount) public returns(bool) {

        uint256 totalSupply =  pools[_poolId].tokenBsupply;
        uint256 poolBalance =  pools[_poolId].tokenAsupply;
        uint32  reserveRatio = pools[_poolId].reserveRatio;

        uint256 tokensToSend = formula.calculatePurchaseReturn(totalSupply, poolBalance, reserveRatio, _buyAmount);
        pools[_poolId].tokenBsupply = totalSupply.sub(tokensToSend);
        pools[_poolId].tokenAsupply = poolBalance.add(_buyAmount);

        //TODO: change to safe
        // pools[_poolId].exchageRate  = 

        return true;
    }

    // function sell(uint256 _poolId, uint256 sellAmount) public returns(bool) {
    //     //require(sellAmount > 0 && balances[msg.sender] >= sellAmount);

    //     uint256 ethAmount = formula.calculateSaleReturn(totalSupply_, poolBalance, reserveRatio, sellAmount);
    //     msg.sender.transfer(ethAmount);
    //     poolBalance = poolBalance.sub(ethAmount);
    //     //balances[msg.sender] = balances[msg.sender].sub(sellAmount);
    //     totalSupply_ = totalSupply_.sub(sellAmount);
    //     // LogWithdraw(sellAmount, ethAmount);

    //     return true;
    // }

}