pragma solidity ^0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/os/contracts/lib/math/SafeMath.sol";
import "@aragon/os/contracts/common/SafeERC20.sol";
import "./bancor-formula/BancorFormula.sol";


contract TokenSwap is AragonApp, BancorFormula {
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
    // IBancorFormula public formula;
    ERC20          public token;

    uint32  public constant PPM      = 1000000;  // parts per million

    function getReserveRatio(
        uint256 _exchangeRate, 
        uint256 _tokenSupply, 
        uint256 _totalTokenSupply
        ) internal 
          returns(uint32)
    {
        return uint32(uint256(PPM).mul(_tokenSupply).div(_exchangeRate.mul(_totalTokenSupply).div(uint256(PPM))));
    }

    function isBalanced(uint256 supplyA, 
                        uint256 supplyB, 
                        uint256 exchangeRate
                        ) internal
                          returns(bool)
    {
        return (uint256(PPM).mul(supplyA).div(supplyB) == exchangeRate);
    }

    function createPool(
        // address _tokenA, 7
        // address _tokenB,
        uint256    _tokenAsupply,
        uint256    _tokenBsupply,
        uint256    _totalTokenBsupply, // TODO: change to ERC20 getSUpply!
        uint256    _exchangeRate // the price of token A in token B
        ) external 
          returns(bool)
    {
        require(isBalanced(_tokenAsupply, _tokenBsupply, _exchangeRate),
                "Pool is not balanced, please adjust tokens supply" );
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

    function buy(uint256 _poolId, 
                 uint256 _tokenAamount, 
                 uint256 _totalTokenBsupply
                 ) 
        public 
        returns(bool) 
        {
        // TODO: add require pool exists
        uint256 newPrice;
        uint256 poolBalance     = pools[_poolId].tokenBsupply;
        uint256 reserveBalance  = pools[_poolId].tokenAsupply;
        uint32  _reserveRatio   = pools[_poolId].reserveRatio; //TODO: take a look at the convention

        uint256 sendAmount = calculatePurchaseReturn(_totalTokenBsupply, 
                                                     poolBalance, 
                                                     _reserveRatio, 
                                                     _tokenAamount);

        poolBalance          = poolBalance.sub(sendAmount);  // send tokens to the buyer
        reserveBalance       = reserveBalance.add(_tokenAamount);
        newPrice             = uint256(PPM).mul(reserveBalance).div(poolBalance);

        _reserveRatio = getReserveRatio(newPrice, 
                                        poolBalance, 
                                        _totalTokenBsupply);

        pools[_poolId].tokenAsupply = reserveBalance;
        pools[_poolId].tokenBsupply = poolBalance;
        pools[_poolId].reserveRatio = _reserveRatio;
        pools[_poolId].exchageRate = newPrice;

        return true;
    }

    function sell(uint256 _poolId, 
                  uint256 _tokenBamount, 
                  uint256 _totalTokenBsupply
                  ) 
    public 
    returns(bool) 
    {

        uint256 newPrice;
        uint256 poolBalance     = pools[_poolId].tokenBsupply;
        uint256 reserveBalance  = pools[_poolId].tokenAsupply;
        uint32  _reserveRatio   = pools[_poolId].reserveRatio; //TODO: take a look at the convention

        uint256 sendAmount = calculateSaleReturn(_totalTokenBsupply, 
                                                        poolBalance, 
                                                        _reserveRatio, 
                                                        _tokenBamount);
        
        reserveBalance       = reserveBalance.sub(sendAmount);
        poolBalance          = poolBalance.add(_tokenBamount); 
        newPrice             = uint256(PPM).mul(reserveBalance).div(poolBalance);


        _reserveRatio = getReserveRatio(newPrice, 
                                        poolBalance, 
                                        _totalTokenBsupply);

        pools[_poolId].tokenAsupply = reserveBalance;
        pools[_poolId].tokenBsupply = poolBalance;
        pools[_poolId].reserveRatio = _reserveRatio;
        pools[_poolId].exchageRate = newPrice;

        return true;
    }

}