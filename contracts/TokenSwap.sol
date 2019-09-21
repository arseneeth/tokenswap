pragma solidity ^0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/os/contracts/common/IsContract.sol";
import "@aragon/os/contracts/lib/math/SafeMath.sol";
import "@aragon/os/contracts/common/SafeERC20.sol";
import "@aragon/os/contracts/lib/token/ERC20.sol";
import "./bancor-formula/BancorFormula.sol";


contract TokenSwap is AragonApp {
    using SafeERC20 for ERC20;    
    using SafeMath for uint256;
    
    bytes32 constant public ADMIN_ROLE = keccak256("ADMIN_ROLE"); //TODO: delete later
    bytes32 public constant PROVIDER  = keccak256("PROVIDER");
    bytes32 public constant BUY_ROLE  = keccak256("BUY_ROLE");
    bytes32 public constant SELL_ROLE = keccak256("SELL_ROLE");

    uint32  public constant PPM = 1000000;  // parts per million

    string private constant ERROR_POOL_NOT_BALANCED = "MM_POOL_NOT_BALANCED";
    string private constant ERROR_CONTRACT_IS_EOA   = "MM_CONTRACT_IS_EOA";

    struct Pool{
        address provider;
        uint256 tokenAsupply;
        uint256 tokenBsupply;
        uint32  reserveRatio;
        uint256 exchageRate; // A => B
        bool    isActive;
        address tokenA; // Base Asset  
        address tokenB; // Reserve Asset
    }
    
    IBancorFormula public formula;
    ERC20[]        public tokens;
    Pool[]         public pools;

    mapping (address => uint256) initializedTokens; // Reserve Asset

    event PoolCreated   (
        address indexed provider, 
        uint256 id, 
        uint256 tokenAsupply, 
        uint256 tokenBsupply, 
        uint256 exchangeRate
    );
    event PoolUpdated   (
        address indexed reciever, 
        uint256 id, 
        uint256 tokenAsupply, 
        uint256 tokenBsupply, 
        uint256 exchangeRate
    );
    event PoolClosed   (
        address indexed provider, 
        uint256 id 
    );

    event TokenInitialized   (
        address indexed token, 
        uint256 id 
    );


    /***** external function *****/
    
    /**
    * @notice Initialize tokenswap contract
    * @param _formula The address of the BancorFormula [computation] contract
    */
    function initialize(IBancorFormula _formula) external onlyInit {
        initialized();
        require(isContract(_formula), ERROR_CONTRACT_IS_EOA);    
        formula = _formula;
    }

    /***** internal functions *****/
    
    /**
    * @notice Calculate reserve ratio
    * @param _exchangeRate     The price of token A in token B
    * @param _tokenSupply      Supply of token B in the pool
    * @param _totalTokenSupply Total token B supply(should be removed)
    */
    function getReserveRatio(
        uint256 _exchangeRate, 
        uint256 _tokenSupply, 
        uint256 _totalTokenSupply
        ) internal 
          returns(uint32)
    {
        return uint32(uint256(PPM).mul(_tokenSupply).div(_exchangeRate.mul(_totalTokenSupply).div(uint256(PPM))));
    }

    /**
    * @notice Checks if the pool setup is balanced
    * @param supplyA      The number of tokens A
    * @param supplyB      The number of tokens B
    * @param exchangeRate The price of token A in token B
    */
    function isBalanced(uint256 supplyA, 
                        uint256 supplyB, 
                        uint256 exchangeRate
                        ) internal
                          returns(bool)
    {
        return (uint256(PPM).mul(supplyA).div(supplyB) == exchangeRate);
    }
    /* tokens related functions */
    function initializeToken(address tokenAddress) public returns(uint) {
        // TODO: add checks

        ERC20 _token   = ERC20(tokenAddress);
        uint  _tokenId = tokens.length;

        tokens.push(_token);
        initializedTokens[tokenAddress] = _tokenId;               

        emit TokenInitialized(tokenAddress, _tokenId);
        return _tokenId;
    }

    
    /* pool related functions */

    /**
    * @notice Creates the pool of swappable tokens 
    * @param _tokenAaddress           Address of token A contract
    * @param _tokenBaddress           Address of token B contract
    * @param _tokenAsupply            Supply of tokens A in the pool
    * @param _tokenBsupply            Supply of tokens B in the pool
    * @param _exchangeRate            The price of token B in token A
    */
    function createPool(
        address    _tokenAaddress, 
        address    _tokenBaddress,
        uint256    _tokenAsupply,
        uint256    _tokenBsupply,
        // uint256    _totalTokenBsupply, // TODO: change to ERC20 getSUpply!
        uint256    _exchangeRate     
        ) external 
    {
        require(isBalanced(_tokenAsupply, _tokenBsupply, _exchangeRate),
                "Pool is not balanced, please adjust tokens supply" );
        require(isContract(_tokenAaddress) && isContract(_tokenAaddress),
                "It's not a contract");

        //initialize tokens
        uint  _tokenAid = initializeToken(_tokenAaddress); 
        uint  _tokenBid = initializeToken(_tokenBaddress);
        // ERC20 _tokenA   = tokens[_tokenAid];
        // ERC20 _tokenB   = tokens[_tokenBid];

        uint256 _totalTokenBsupply = tokens[_tokenBid].totalSupply();

        uint _id = pools.length++;
        Pool storage p = pools[_id];

        uint32 _reserveRatio = getReserveRatio(_exchangeRate, 
                                               _tokenBsupply, 
                                               _totalTokenBsupply);

        p.provider     = msg.sender;
        p.tokenA       = _tokenAaddress;
        p.tokenB       = _tokenBaddress;
        p.tokenAsupply = _tokenAsupply;
        p.tokenBsupply = _tokenBsupply;
        p.reserveRatio = _reserveRatio;
        p.exchageRate  = _exchangeRate;
        p.isActive     = true;

        emit PoolCreated(msg.sender, _id, _tokenAsupply, _tokenBsupply, _exchangeRate);
    } 

    /**
    * @notice Updates the pool based on trade execution 
    * @param _tokenAsupply           Supply of tokens A in the pool
    * @param _tokenBsupply           Supply of tokens B in the pool
    * @param _totalTokenBsupply      Total supply of tokens B
    * @param _exchangeRate           The price of token B in token A
    */
    function updatePool(
        uint256    _poolId,
        uint256    _tokenAsupply,
        uint256    _tokenBsupply,
        uint256    _totalTokenBsupply, // TODO: change to ERC20 getSUpply!
        uint256    _exchangeRate // the price of token B in token A
        ) internal 
    {
        require(isBalanced(_tokenAsupply, _tokenBsupply, _exchangeRate),
                "Pool is not balanced, please adjust tokens supply" );

        uint32 _reserveRatio = getReserveRatio(_exchangeRate, 
                                        _tokenBsupply, 
                                        _totalTokenBsupply);

        pools[_poolId].tokenAsupply = _tokenAsupply;
        pools[_poolId].tokenBsupply = _tokenBsupply;
        pools[_poolId].reserveRatio = _reserveRatio;
        pools[_poolId].exchageRate  = _exchangeRate;
    }

    function closePool(uint256 _poolId) external {
        require(msg.sender == pools[_poolId].provider,
                "you are not the owner of the pool");
        require(pools[_poolId].isActive,
                "pool is not active");

        pools[_poolId].isActive = false;
        pools[_poolId].tokenAsupply = 0;
        pools[_poolId].tokenBsupply = 0;
        pools[_poolId].reserveRatio = 0;
        pools[_poolId].exchageRate  = 0;
    }

    function addLiquidity(
        uint256 _poolId, 
        uint256 _tokenAliquidity, 
        uint256 _tokenBliqudity,
        uint256 _totalTokenBsupply
        ) external 
    {
        require(msg.sender == pools[_poolId].provider,
                "you are not the owner of the pool");
        require(pools[_poolId].isActive,
                "pool is not active");
        
        uint256 _tokenAsupply = pools[_poolId].tokenAsupply.add(_tokenAliquidity);
        uint256 _tokenBsupply = pools[_poolId].tokenBsupply.add(_tokenBliqudity);
        uint256 _exchangeRate = uint256(PPM).mul(_tokenAsupply).div(_tokenBsupply);
        
        updatePool(_poolId, _tokenAsupply, _tokenBsupply, _totalTokenBsupply, _exchangeRate);
    }

    function removeLiquidity(
        uint256 _poolId, 
        uint256 _tokenAliquidity, 
        uint256 _tokenBliqudity,
        uint256 _totalTokenBsupply
        ) external 
    {
        require(msg.sender == pools[_poolId].provider,
                "you are not the owner of the pool");
        require(pools[_poolId].isActive,
                "pool is not active");
        
        uint256 _tokenAsupply = pools[_poolId].tokenAsupply.sub(_tokenAliquidity);
        uint256 _tokenBsupply = pools[_poolId].tokenBsupply.sub(_tokenBliqudity);
        uint256 _exchangeRate = uint256(PPM).mul(_tokenAsupply).div(_tokenBsupply);
        
        updatePool(_poolId, _tokenAsupply, _tokenBsupply, _totalTokenBsupply, _exchangeRate);
    }

    function buy(uint256 _poolId, 
                 uint256 _tokenAamount, 
                 uint256 _totalTokenBsupply
                 ) 
    external 
    {
        // TODO: add require pool exists
        uint256 newPrice;
        uint256 poolBalance       = pools[_poolId].tokenBsupply;
        uint256 reserveBalance    = pools[_poolId].tokenAsupply;
        uint32  connectorWeight   = pools[_poolId].reserveRatio; //TODO: take a look at the convention

        uint256 sendAmount = formula.calculatePurchaseReturn(_totalTokenBsupply, 
                                                     poolBalance, 
                                                     connectorWeight, 
                                                     _tokenAamount);

        poolBalance          = poolBalance.sub(sendAmount);  // send tokens to the buyer
        reserveBalance       = reserveBalance.add(_tokenAamount);
        newPrice             = uint256(PPM).mul(reserveBalance).div(poolBalance);

        updatePool(_poolId, reserveBalance, poolBalance, _totalTokenBsupply, newPrice);
    }

    function sell(uint256 _poolId, 
                  uint256 _tokenBamount, 
                  uint256 _totalTokenBsupply
                  ) 
    public 
    {
        uint256 newPrice;
        uint256 poolBalance       = pools[_poolId].tokenBsupply;
        uint256 reserveBalance    = pools[_poolId].tokenAsupply;
        uint32  connectorWeight   = pools[_poolId].reserveRatio; //TODO: take a look at the convention

        uint256 sendAmount  = formula.calculateSaleReturn(_totalTokenBsupply, 
                                                  poolBalance, 
                                                  connectorWeight, 
                                                  _tokenBamount);
        
        reserveBalance       = reserveBalance.sub(sendAmount);
        poolBalance          = poolBalance.add(_tokenBamount); 
        newPrice             = uint256(PPM).mul(reserveBalance).div(poolBalance);

        updatePool(_poolId, reserveBalance, poolBalance, _totalTokenBsupply, newPrice);
    }

}