pragma solidity ^0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/os/contracts/common/IsContract.sol";
import "@aragon/os/contracts/lib/math/SafeMath.sol";
import "@aragon/os/contracts/common/SafeERC20.sol";
import "@aragon/os/contracts/lib/token/ERC20.sol";
import "./bancor-formula/BancorFormula.sol";


contract TokenSwap is AragonApp {
    using SafeERC20 for ERC20;    
    using SafeMath  for uint256;
    
    bytes32 public constant PROVIDER   = keccak256("PROVIDER");
    bytes32 public constant BUYER      = keccak256("BUYER");
    bytes32 public constant SELLER     = keccak256("SELLER");

    uint256 public constant PCT_BASE = 10 ** 18; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18
    uint32  public constant PPM = 1000000;  // parts per million

    string private constant ERROR_POOL_NOT_BALANCED                  = "MM_POOL_NOT_BALANCED";
    string private constant ERROR_POOL_NOT_ACTIVE                    = "MM_POOL_NOT_ACTIVE";
    string private constant ERROR_CONTRACT_IS_EOA                    = "MM_CONTRACT_IS_EOA";
    string private constant ERROR_NOT_PROVIDER                       = "MM_NOT_PROVIDER";
    string private constant ERROR_SLIPPAGE_LIMIT_EXCEEDED            = "MM_SLIPPAGE_LIMIT_EXCEEDED";
    string private constant ERROR_POOL_EXISTS                        = "MM_POOL_EXISTS";
    string private constant ERROR_INSUFFICIENT_BALANCE               = "MM_INSUFFICIENT_BALANCE";

    struct Pool{
        address provider;
        uint256 tokenAsupply;
        uint256 tokenBsupply;
        uint32  reserveRatio;
        uint256 exchageRate;
        uint256 slippage;
        bool    isActive;
        address tokenA;  
        address tokenB; 
    }
    
    IBancorFormula public formula;
    ERC20[]        public tokens;
    Pool[]         public pools;

    mapping (address => uint256) initializedTokens; 
    mapping (address => bool) tokensExist; 
    mapping (address => mapping (bytes32 => bool)) poolProviders; 

    event PoolCreated       (
        address indexed provider, 
        uint256 id, 
        uint256 tokenAsupply, 
        uint256 tokenBsupply, 
        uint256 exchangeRate
    );
    event PoolDataUpdated   (
        address indexed reciever, 
        uint256 id, 
        uint256 tokenAsupply, 
        uint256 tokenBsupply, 
        uint256 exchangeRate
    );
    event PoolClosed        (
        address indexed provider, 
        uint256 id 
    );

    event TokenInitialized   (
        address indexed token, 
        uint256 id 
    );

    event TokenBought   (
        address indexed buyer, 
        uint256 poolid,
        uint256 amount 
    );

    event TokenSold   (
        address indexed buyer, 
        uint256 poolid,
        uint256 amount 
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

    /* pool related functions */

    /**
    * @notice Creates the pool of swappable tokens 
    * @param _tokenAaddress           Address of token A contract
    * @param _tokenBaddress           Address of token B contract
    * @param _tokenAsupply            Supply of tokens A in the pool
    * @param _tokenBsupply            Supply of tokens B in the pool
    * @param _slippage                Maximum slippage
    * @param _exchangeRate            The price of token B in token A
    */

    function createPool(
        address    _tokenAaddress, 
        address    _tokenBaddress,
        uint256    _tokenAsupply,
        uint256    _tokenBsupply,
        uint256    _slippage,
        uint256    _exchangeRate     
    ) 
        external 
        auth(PROVIDER)
    {
        require(_isBalanced(_tokenAsupply, _tokenBsupply, _exchangeRate),  
                ERROR_POOL_NOT_BALANCED );
        require(isContract(_tokenAaddress) && isContract(_tokenAaddress), 
                ERROR_CONTRACT_IS_EOA);
        require(!poolProviders[msg.sender][keccak256(abi.encodePacked(_tokenAaddress, _tokenBaddress))], 
                ERROR_POOL_EXISTS);

        _createPool(_tokenAaddress, _tokenBaddress, _tokenAsupply, _tokenBsupply, _slippage, _exchangeRate);
    } 

    /**
    * @notice Closes the pool, returns all balances to the liquidity provider 
    * @param _poolId Id of the pool needed to be closed
    */

    function closePool(uint256 _poolId) external auth(PROVIDER) {
        require(msg.sender == pools[_poolId].provider, ERROR_NOT_PROVIDER);
        require(pools[_poolId].isActive, ERROR_POOL_NOT_ACTIVE);
        
        _closePool(_poolId);        
    }

    /**
    * @notice Adds liquidity to the pool
    * @param _tokenAliquidity number of token A to be added to the pool 
    * @param _tokenBliquidity number of token B to be added to the pool
    */

    function addLiquidity(
        uint256 _poolId, 
        uint256 _tokenAliquidity, 
        uint256 _tokenBliquidity
    ) 
        external 
        auth(PROVIDER)    
    {
        require(msg.sender == pools[_poolId].provider, ERROR_NOT_PROVIDER);
        require(pools[_poolId].isActive, ERROR_POOL_NOT_ACTIVE);

        //get tokens id        
        uint tokenAid = initializedTokens[pools[_poolId].tokenA];
        uint tokenBid = initializedTokens[pools[_poolId].tokenB];

        require(_sufficientBalance(tokenAid, _tokenAliquidity, msg.sender) && _sufficientBalance(tokenBid, _tokenBliquidity, msg.sender), 
                ERROR_INSUFFICIENT_BALANCE);

        _addLiquidity(_poolId, tokenAid, tokenBid, _tokenAliquidity, _tokenBliquidity);
    }

    /**
    * @notice Removes liquidity from the pool, returns tokens to the liquidity provider
    * @param _tokenAliquidity number of token A to be returned to the liquidity provider 
    * @param _tokenBliquidity number of token B to be returned to the liquidity provider
    */
    function removeLiquidity(
        uint256 _poolId, 
        uint256 _tokenAliquidity, 
        uint256 _tokenBliquidity        
    ) 
        external 
        auth(PROVIDER)    
    {
        require(msg.sender == pools[_poolId].provider, ERROR_NOT_PROVIDER);
        require(pools[_poolId].isActive, ERROR_POOL_NOT_ACTIVE);
        require(_tokenAliquidity < pools[_poolId].tokenAsupply && _tokenBliquidity < pools[_poolId].tokenBsupply,
                ERROR_INSUFFICIENT_BALANCE);
        
        _removeLiquidity(_poolId, _tokenAliquidity, _tokenBliquidity);
    }

    /**
    * @notice Buy tokens B from the liquidity pool
    * @param _poolId id of the pool 
    * @param _tokenAamount the price in tokens B which is going to be payed for tokens B
    */
    function buy(uint256 _poolId, uint256 _tokenAamount) external auth(BUYER) {
        require(pools[_poolId].isActive, ERROR_POOL_NOT_ACTIVE);
  
        uint256 tokenAid          = initializedTokens[pools[_poolId].tokenA];
        uint256 tokenBid          = initializedTokens[pools[_poolId].tokenB];
        uint256 totalTokenBsupply = tokens[tokenBid].totalSupply();

        require(_sufficientBalance(tokenAid, _tokenAamount, msg.sender), 
                ERROR_INSUFFICIENT_BALANCE);

        _buy(_poolId,
             tokenAid,
             tokenBid, 
             _tokenAamount, 
             totalTokenBsupply 
             );
    }

    /**
    * @notice Sell tokens B to the liquidity pool
    * @param _poolId id of the pool 
    * @param _tokenBamount the amount of tokens B which is going to be echanged for tokens A
    */
    function sell(uint256 _poolId, uint256 _tokenBamount) public auth(SELLER) {
        
        uint256 tokenAid          = initializedTokens[pools[_poolId].tokenA];
        uint256 tokenBid          = initializedTokens[pools[_poolId].tokenB];
        uint256 totalTokenBsupply = tokens[tokenBid].totalSupply();

        require(_sufficientBalance(tokenBid, _tokenBamount, msg.sender), 
                ERROR_INSUFFICIENT_BALANCE);

        _sell(_poolId,
             tokenAid,
             tokenBid, 
             _tokenBamount, 
             totalTokenBsupply);
    }

    /***** internal functions *****/
    
    /***** calculation functions *****/

    /**
    * @notice Calculate reserve ratio
    * @param _exchangeRate     The price of token A in token B
    * @param _tokenSupply      Supply of token B in the pool
    * @param _totalTokenSupply Total token B supply(should be removed)
    */
    function _getReserveRatio(
        uint256 _exchangeRate, 
        uint256 _tokenSupply, 
        uint256 _totalTokenSupply
    )   
        internal
        pure 
        returns(uint32)
    {
        return uint32(uint256(PPM).mul(_tokenSupply).div(_exchangeRate.mul(_totalTokenSupply).div(uint256(PPM))));
    }

    /**
    * @notice Checks if the pool setup is balanced
    * @param _supplyA      The number of tokens A
    * @param _supplyB      The number of tokens B
    * @param _exchangeRate The price of token A in token B
    */
    function _isBalanced(
        uint256 _supplyA, 
        uint256 _supplyB, 
        uint256 _exchangeRate
    ) 
        internal
        pure
        returns(bool)
    {
        return (uint256(PPM).mul(_supplyA).div(_supplyB) == _exchangeRate);
    }

    /**
    * @notice Calculates is the trade passing slippage limit
    * @param _expectedPrice  Expected price in tokens A
    * @param _actualPrice    Price calculates by Bancor formula
    * @param _slippage       Maximum slippage in percentage
    */
    function _slippageLimitPassed(
        uint _expectedPrice, 
        uint _actualPrice, 
        uint _slippage
    )
        internal
        pure
        returns(bool)
    {

        return _expectedPrice.sub(_actualPrice) <= _slippage.mul(_expectedPrice).div(PPM);
    }

    /* tokens related functions */

    /**
    * @notice Initializes new token in the system
    * @param _tokenAddress address of a token
    */

    function _initializeToken(address _tokenAddress) internal returns(uint) {
        if(tokensExist[_tokenAddress] == true){
            return initializedTokens[_tokenAddress];
        } else {
            ERC20 token   = ERC20(_tokenAddress);
            uint  tokenId = tokens.length;

            tokens.push(token);
            initializedTokens[_tokenAddress] = tokenId;               
            tokensExist[_tokenAddress] = true;               

            emit TokenInitialized(_tokenAddress, tokenId);
            return tokenId;            
        }
    }

    /**
    * @notice Checks token balance of an account
    * @param _tokenId token id in the system
    * @param _sendAmount amount of tokens willing to be sent
    * @param _sender account of a sender
    */
    function _sufficientBalance(
        uint256 _tokenId, 
        uint256 _sendAmount,
        address _sender
    ) 
        internal
        view
        returns(bool) 
    {
        uint256 balance = tokens[_tokenId].balanceOf(_sender);
        return balance >= _sendAmount;
    }

    /* state modifiying functions */
    
    function _createPool(
        address    _tokenAaddress, 
        address    _tokenBaddress,
        uint256    _tokenAsupply,
        uint256    _tokenBsupply,
        uint256    _slippage,
        uint256    _exchangeRate     
    )
        internal
    {
        //initialize tokens
        uint  tokenAid = _initializeToken(_tokenAaddress); 
        uint  tokenBid = _initializeToken(_tokenBaddress);

        require(_sufficientBalance(tokenAid, _tokenAsupply, msg.sender) && _sufficientBalance(tokenBid, _tokenBsupply, msg.sender), 
                ERROR_INSUFFICIENT_BALANCE);

        poolProviders[msg.sender][keccak256(abi.encodePacked(_tokenAaddress, _tokenBaddress))] = true;

        //transfer tokens
        tokens[tokenAid].transferFrom(msg.sender, address(this), _tokenAsupply);       
        tokens[tokenBid].transferFrom(msg.sender, address(this), _tokenBsupply);       

        uint256 totalTokenBsupply = tokens[tokenBid].totalSupply();

        uint _id = pools.length++;
        Pool storage p = pools[_id];

        uint32 reserveRatio = _getReserveRatio(_exchangeRate, 
                                               _tokenBsupply, 
                                               totalTokenBsupply);
        p.provider     = msg.sender;
        p.tokenA       = _tokenAaddress;
        p.tokenB       = _tokenBaddress;
        p.tokenAsupply = _tokenAsupply;
        p.tokenBsupply = _tokenBsupply;
        p.slippage     = _slippage;
        p.exchageRate  = _exchangeRate;
        p.isActive     = true;
        p.reserveRatio = reserveRatio;

        emit PoolCreated(msg.sender, _id, _tokenAsupply, _tokenBsupply, _exchangeRate);
    }

    function _closePool(uint256 _poolId) internal {
        //get tokens id        
        uint tokenAid = initializedTokens[pools[_poolId].tokenA];
        uint tokenBid = initializedTokens[pools[_poolId].tokenB];

        //transfer tokens
        tokens[tokenAid].transfer(msg.sender, pools[_poolId].tokenAsupply);
        tokens[tokenBid].transfer(msg.sender, pools[_poolId].tokenBsupply);

        pools[_poolId].isActive     = false;
        pools[_poolId].tokenAsupply = 0;
        pools[_poolId].tokenBsupply = 0;
        pools[_poolId].reserveRatio = 0;
        pools[_poolId].slippage     = 0;
        pools[_poolId].exchageRate  = 0;

        poolProviders[msg.sender][keccak256(abi.encodePacked(pools[_poolId].tokenA, pools[_poolId].tokenB))] = false;

        emit PoolClosed(msg.sender, _poolId);

    } 

    /**
    * @notice Updates the pool based on trade execution 
    * @param _tokenAsupply           Supply of tokens A in the pool
    * @param _tokenBsupply           Supply of tokens B in the pool
    * @param _exchangeRate           The price of token B in token A
    */
    function _updatePoolData(
        uint256    _poolId,
        uint256    _tokenAsupply,
        uint256    _tokenBsupply,
        uint256    _exchangeRate // the price of token B in token A
    ) 
        internal 
    {
        require(_isBalanced(_tokenAsupply, _tokenBsupply, _exchangeRate), ERROR_POOL_NOT_BALANCED );
 
        uint256 tokenBid          = initializedTokens[pools[_poolId].tokenB];
        uint256 totalTokenBsupply = tokens[tokenBid].totalSupply();

        uint32  reserveRatio = _getReserveRatio(_exchangeRate, 
                                              _tokenBsupply, 
                                              totalTokenBsupply);

        pools[_poolId].tokenAsupply = _tokenAsupply;
        pools[_poolId].tokenBsupply = _tokenBsupply;
        pools[_poolId].exchageRate  = _exchangeRate;
        pools[_poolId].reserveRatio = reserveRatio;

        emit PoolDataUpdated(msg.sender, _poolId, _tokenAsupply, _tokenBsupply, _exchangeRate);
    }


    function _addLiquidity(
        uint256 _poolId, 
        uint256 _tokenAid, 
        uint256 _tokenBid,
        uint256 _tokenAliquidity, 
        uint256 _tokenBliquidity
    ) 
        internal 
    {
        //transfer tokens
        tokens[_tokenAid].transferFrom(msg.sender, address(this), _tokenAliquidity);       
        tokens[_tokenBid].transferFrom(msg.sender, address(this), _tokenBliquidity);       
        
        uint256 tokenAsupply = pools[_poolId].tokenAsupply.add(_tokenAliquidity);
        uint256 tokenBsupply = pools[_poolId].tokenBsupply.add(_tokenBliquidity);
        uint256 exchangeRate = uint256(PPM).mul(tokenAsupply).div(tokenBsupply);
        
        _updatePoolData(_poolId, tokenAsupply, tokenBsupply, exchangeRate);

    }

    function _removeLiquidity(
        uint256 _poolId, 
        uint256 _tokenAliquidity, 
        uint256 _tokenBliquidity        
    )
        internal
    {
        //get tokens id        
        uint tokenAid = initializedTokens[pools[_poolId].tokenA];
        uint tokenBid = initializedTokens[pools[_poolId].tokenB];

        //transfer tokens
        tokens[tokenAid].transfer(msg.sender, _tokenAliquidity);
        tokens[tokenBid].transfer(msg.sender, _tokenBliquidity);
        
        uint256 tokenAsupply = pools[_poolId].tokenAsupply.sub(_tokenAliquidity);
        uint256 tokenBsupply = pools[_poolId].tokenBsupply.sub(_tokenBliquidity);
        uint256 exchangeRate = uint256(PPM).mul(tokenAsupply).div(tokenBsupply);
        
        _updatePoolData(_poolId, tokenAsupply, tokenBsupply, exchangeRate);

    }

    function _buy(
        uint   _poolId,
        uint   _tokenAid,
        uint   _tokenBid, 
        uint   _tokenAamount,
        uint   _totalTokenBsupply                  
    ) 
        internal 
    {

        uint256 _poolBalance        = pools[_poolId].tokenBsupply;
        uint256 _reserveBalance     = pools[_poolId].tokenAsupply;
        uint32  _connectorWeight    = pools[_poolId].reserveRatio; 
        uint256 _staticPrice        = pools[_poolId].exchageRate;                
        uint256 _slippage           = pools[_poolId].slippage;

        uint256 sendAmount = formula.calculatePurchaseReturn(_totalTokenBsupply, 
                                                             _poolBalance, 
                                                             _connectorWeight, 
                                                             _tokenAamount);

     require(_slippageLimitPassed(_tokenAamount, sendAmount.mul(_staticPrice).div(PPM), _slippage),
            ERROR_SLIPPAGE_LIMIT_EXCEEDED);
   

        uint256 poolBalance          = _poolBalance.sub(sendAmount); 
        uint256 reserveBalance       = _reserveBalance.add(_tokenAamount);
        uint256 newPrice             = uint256(PPM).mul(reserveBalance).div(poolBalance);
   
        //transfer tokens
        tokens[_tokenAid].transferFrom(msg.sender, address(this), _tokenAamount);       
        tokens[_tokenBid].transfer(msg.sender, sendAmount);       

        emit TokenBought(msg.sender, _poolId, sendAmount);
        _updatePoolData(_poolId, reserveBalance, poolBalance, newPrice);
    }


    function _sell(
        uint   _poolId,
        uint   _tokenAid,
        uint   _tokenBid, 
        uint   _tokenBamount,
        uint   _totalTokenBsupply                  
    ) 
        internal
    {
        require(pools[_poolId].isActive, ERROR_POOL_NOT_ACTIVE);

        uint256 _poolBalance        = pools[_poolId].tokenBsupply;
        uint256 _reserveBalance     = pools[_poolId].tokenAsupply;
        uint32  _connectorWeight    = pools[_poolId].reserveRatio; 
        uint256 _staticPrice        = pools[_poolId].exchageRate;                
        uint256 _slippage           = pools[_poolId].slippage;  

        uint256 sendAmount  = formula.calculateSaleReturn(_totalTokenBsupply, 
                                                  _poolBalance, 
                                                  _connectorWeight, 
                                                  _tokenBamount);

        require(_slippageLimitPassed(_tokenBamount.mul(_staticPrice).div(PPM), sendAmount, _slippage),
            ERROR_SLIPPAGE_LIMIT_EXCEEDED);
        
        uint reserveBalance       = _reserveBalance.sub(sendAmount);
        uint poolBalance          = _poolBalance.add(_tokenBamount); 
        uint newPrice             = uint256(PPM).mul(reserveBalance).div(poolBalance);

        //transfer tokens
        tokens[_tokenAid].transfer(msg.sender, sendAmount);       
        tokens[_tokenBid].transferFrom(msg.sender, address(this), _tokenBamount);       

        emit TokenSold(msg.sender, _poolId, sendAmount);
        _updatePoolData(_poolId, reserveBalance, poolBalance, newPrice);
    }
}