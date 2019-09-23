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
    
    // bytes32 constant public ADMIN_ROLE = keccak256("ADMIN_ROLE"); //TODO: delete later
    bytes32 public constant PROVIDER   = keccak256("PROVIDER");
    bytes32 public constant BUYER      = keccak256("BUYER");
    bytes32 public constant SELLER     = keccak256("SELLER");

    uint32  public constant PPM = 1000000;  // parts per million

    string private constant ERROR_POOL_NOT_BALANCED                  = "MM_POOL_NOT_BALANCED";
    string private constant ERROR_POOL_NOT_ACTIVE                    = "MM_POOL_NOT_ACTIVE";
    string private constant ERROR_CONTRACT_IS_EOA                    = "MM_CONTRACT_IS_EOA";
    string private constant ERROR_NOT_PROVIDER                       = "MM_NOT_PROVIDER";
    string private constant ERROR_SLIPPAGE_LIMIT_EXCEEDED            = "MM_SLIPPAGE_LIMIT_EXCEEDED";
    string private constant ERROR_POOL_EXISTS                        = "MM_POOL_EXISTS";
    string private constant ERROR_POOL_DOESNT_EXIST                  = "MM_POOL_DOESNT_EXIST";    
    string private constant ERROR_INSUFFICIENT_BALANCE               = "MM_INSUFFICIENT_BALANCE";

    struct Pool{
        address provider;
        uint256 tokenAsupply;
        uint256 tokenBsupply;
        uint32  reserveRatio;
        uint256 exchageRate;
        uint256 slippage;
        bool    isActive;
        address tokenA; // Base Asset  
        address tokenB; // Reserve Asset
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
          pure 
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
    function isBalanced(
        uint256 supplyA, 
        uint256 supplyB, 
        uint256 exchangeRate
        ) 
        internal
        pure
        returns(bool)
    {
        return (uint256(PPM).mul(supplyA).div(supplyB) == exchangeRate);
    }

    /* tokens related functions */

    function initializeToken(address tokenAddress) internal returns(uint) {
        if(tokensExist[tokenAddress] == true){
            return initializedTokens[tokenAddress];
        } else {
            ERC20 _token   = ERC20(tokenAddress);
            uint  _tokenId = tokens.length;

            tokens.push(_token);
            initializedTokens[tokenAddress] = _tokenId;               
            tokensExist[tokenAddress] = true;               

            emit TokenInitialized(tokenAddress, _tokenId);
            return _tokenId;            
        }
    }

    function sufficientBalance(
        uint256 _tokenId, 
        uint256 _sendAmount,
        address _sender
        ) 
    internal
    view
    returns(bool) 
    {
        uint256 _balance = tokens[_tokenId].balanceOf(_sender);
        return _balance >= _sendAmount;
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
        ) external 
          auth(PROVIDER)
    {
        require(isBalanced(_tokenAsupply, _tokenBsupply, _exchangeRate),  
                ERROR_POOL_NOT_BALANCED );
        require(isContract(_tokenAaddress) && isContract(_tokenAaddress), 
                ERROR_CONTRACT_IS_EOA);
        require(!poolProviders[msg.sender][keccak256(abi.encodePacked(_tokenAaddress, _tokenBaddress))], 
                ERROR_POOL_EXISTS);

        //initialize tokens
        uint  _tokenAid = initializeToken(_tokenAaddress); 
        uint  _tokenBid = initializeToken(_tokenBaddress);

        require(sufficientBalance(_tokenAid, _tokenAsupply, msg.sender) && sufficientBalance(_tokenBid, _tokenBsupply, msg.sender), 
                ERROR_INSUFFICIENT_BALANCE);

        poolProviders[msg.sender][keccak256(abi.encodePacked(_tokenAaddress, _tokenBaddress))] = true;

        //transfer tokens
        tokens[_tokenAid].transferFrom(msg.sender, address(this), _tokenAsupply);       
        tokens[_tokenBid].transferFrom(msg.sender, address(this), _tokenBsupply);       

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
        p.slippage     = _slippage;
        p.exchageRate  = _exchangeRate;
        p.isActive     = true;

        emit PoolCreated(msg.sender, _id, _tokenAsupply, _tokenBsupply, _exchangeRate);
    } 


    function closePool(uint256 _poolId) external auth(PROVIDER) {
        require(msg.sender == pools[_poolId].provider, ERROR_NOT_PROVIDER);
        require(pools[_poolId].isActive, ERROR_POOL_NOT_ACTIVE);
        
        //get tokens id        
        uint _tokenAid = initializedTokens[pools[_poolId].tokenA];
        uint _tokenBid = initializedTokens[pools[_poolId].tokenB];

        //transfer tokens
        tokens[_tokenAid].transfer(msg.sender, pools[_poolId].tokenAsupply);
        tokens[_tokenBid].transfer(msg.sender, pools[_poolId].tokenBsupply);

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
    function updatePoolData(
        uint256    _poolId,
        uint256    _tokenAsupply,
        uint256    _tokenBsupply,
        uint256    _exchangeRate // the price of token B in token A
        ) internal 
    {
        require(isBalanced(_tokenAsupply, _tokenBsupply, _exchangeRate), ERROR_POOL_NOT_BALANCED );

        uint256 _tokenBid          = initializedTokens[pools[_poolId].tokenB];
        uint256 _totalTokenBsupply = tokens[_tokenBid].totalSupply();


        uint32 _reserveRatio = getReserveRatio(_exchangeRate, 
                                        _tokenBsupply, 
                                        _totalTokenBsupply);

        pools[_poolId].tokenAsupply = _tokenAsupply;
        pools[_poolId].tokenBsupply = _tokenBsupply;
        pools[_poolId].reserveRatio = _reserveRatio;
        pools[_poolId].exchageRate  = _exchangeRate;

        emit PoolDataUpdated(msg.sender, _poolId, _tokenAsupply, _tokenBsupply, _exchangeRate);
    }


    function addLiquidity(
        uint256 _poolId, 
        uint256 _tokenAliquidity, 
        uint256 _tokenBliqudity
        ) external 
          auth(PROVIDER)    
    {
        require(msg.sender == pools[_poolId].provider, ERROR_NOT_PROVIDER);
        require(pools[_poolId].isActive, ERROR_POOL_NOT_ACTIVE);

        //get tokens id        
        uint _tokenAid = initializedTokens[pools[_poolId].tokenA];
        uint _tokenBid = initializedTokens[pools[_poolId].tokenB];

        require(sufficientBalance(_tokenAid, _tokenAliquidity, msg.sender) && sufficientBalance(_tokenBid, _tokenBliqudity, msg.sender), 
                ERROR_INSUFFICIENT_BALANCE);

        //transfer tokens
        tokens[_tokenAid].transferFrom(msg.sender, address(this), _tokenAliquidity);       
        tokens[_tokenBid].transferFrom(msg.sender, address(this), _tokenBliqudity);       
        
        uint256 _tokenAsupply = pools[_poolId].tokenAsupply.add(_tokenAliquidity);
        uint256 _tokenBsupply = pools[_poolId].tokenBsupply.add(_tokenBliqudity);
        uint256 _exchangeRate = uint256(PPM).mul(_tokenAsupply).div(_tokenBsupply);
        
        updatePoolData(_poolId, _tokenAsupply, _tokenBsupply, _exchangeRate);
    }

    function removeLiquidity(
        uint256 _poolId, 
        uint256 _tokenAliquidity, 
        uint256 _tokenBliquidity        
    ) external 
      auth(PROVIDER)    
    {
        require(msg.sender == pools[_poolId].provider, ERROR_NOT_PROVIDER);
        require(pools[_poolId].isActive, ERROR_POOL_NOT_ACTIVE);
        require(_tokenAliquidity < pools[_poolId].tokenAsupply && _tokenBliquidity < pools[_poolId].tokenBsupply,
                ERROR_INSUFFICIENT_BALANCE);

        //get tokens id        
        uint _tokenAid = initializedTokens[pools[_poolId].tokenA];
        uint _tokenBid = initializedTokens[pools[_poolId].tokenB];

        //transfer tokens
        tokens[_tokenAid].transfer(msg.sender, _tokenAliquidity);
        tokens[_tokenBid].transfer(msg.sender, _tokenBliquidity);
        
        uint256 _tokenAsupply = pools[_poolId].tokenAsupply.sub(_tokenAliquidity);
        uint256 _tokenBsupply = pools[_poolId].tokenBsupply.sub(_tokenBliquidity);
        uint256 _exchangeRate = uint256(PPM).mul(_tokenAsupply).div(_tokenBsupply);
        
        updatePoolData(_poolId, _tokenAsupply, _tokenBsupply, _exchangeRate);
    }

    function buy(uint256 _poolId, uint256 _tokenAamount) external auth(BUYER) {
        require(pools[_poolId].isActive, ERROR_POOL_NOT_ACTIVE);
  
        uint256 tokenAid          = initializedTokens[pools[_poolId].tokenA];
        uint256 tokenBid          = initializedTokens[pools[_poolId].tokenB];
        uint256 totalTokenBsupply = tokens[tokenBid].totalSupply();

        require(sufficientBalance(tokenAid, _tokenAamount, msg.sender), 
                ERROR_INSUFFICIENT_BALANCE);

        _buy(_poolId,
             tokenAid,
             tokenBid, 
             _tokenAamount, 
             totalTokenBsupply 
             );
    }

    function _buy(uint   _poolId,
                  uint   _tokenAid,
                  uint   _tokenBid, 
                  uint   _tokenAamount,
                  uint   _totalTokenBsupply                  
                  ) internal {

        uint256 _poolBalance        = pools[_poolId].tokenBsupply;
        uint256 _reserveBalance     = pools[_poolId].tokenAsupply;
        uint32  _connectorWeight    = pools[_poolId].reserveRatio; //TODO: take a look at the convention
        uint256 _staticPrice        = pools[_poolId].exchageRate;                
        uint256 _slippage           = pools[_poolId].slippage;

        uint256 sendAmount = formula.calculatePurchaseReturn(_totalTokenBsupply, 
                                                     _poolBalance, 
                                                     _connectorWeight, 
                                                     _tokenAamount);

        require (uint256(PPM).mul(_tokenAamount).add(_slippage) >= sendAmount.mul(_staticPrice),
                 ERROR_SLIPPAGE_LIMIT_EXCEEDED);


        uint256 poolBalance          = _poolBalance.sub(sendAmount);  // send tokens to the buyer
        uint256 reserveBalance       = _reserveBalance.add(_tokenAamount);
        uint256 newPrice             = uint256(PPM).mul(reserveBalance).div(poolBalance);
   
        //transfer tokens
        tokens[_tokenAid].transferFrom(msg.sender, address(this), _tokenAamount);       
        tokens[_tokenBid].transfer(msg.sender, sendAmount);       

        //TODO: add emit tokenBought
        updatePoolData(_poolId, reserveBalance, poolBalance, newPrice);
    }

    function sell(uint256 _poolId, uint256 _tokenBamount) public auth(SELLER) {
        
        uint256 tokenAid          = initializedTokens[pools[_poolId].tokenA];
        uint256 tokenBid          = initializedTokens[pools[_poolId].tokenB];
        uint256 totalTokenBsupply = tokens[tokenBid].totalSupply();

        // require(poolProviders[pools[_poolId].provider][keccak256(abi.encodePacked(pools[_poolId].tokenA, pools[_poolId].tokenB))], 
        //         ERROR_POOL_DOESNT_EXIST);
        require(sufficientBalance(tokenBid, _tokenBamount, msg.sender), 
                ERROR_INSUFFICIENT_BALANCE);

        _sell(_poolId,
             tokenAid,
             tokenBid, 
             _tokenBamount, 
             totalTokenBsupply);
    }

    function _sell(
                  uint   _poolId,
                  uint   _tokenAid,
                  uint   _tokenBid, 
                  uint   _tokenBamount,
                  uint   _totalTokenBsupply                  
                  ) internal{
        require(pools[_poolId].isActive, ERROR_POOL_NOT_ACTIVE);

        uint256 _poolBalance        = pools[_poolId].tokenBsupply;
        uint256 _reserveBalance     = pools[_poolId].tokenAsupply;
        uint32  _connectorWeight    = pools[_poolId].reserveRatio; //TODO: take a look at the convention
        uint256 _staticPrice        = pools[_poolId].exchageRate;                
        uint256 _slippage          = pools[_poolId].slippage;  

        uint256 sendAmount  = formula.calculateSaleReturn(_totalTokenBsupply, 
                                                  _poolBalance, 
                                                  _connectorWeight, 
                                                  _tokenBamount);

        require (uint256(PPM).mul(sendAmount) <= _tokenBamount.mul(_staticPrice).sub(_slippage),
                 ERROR_SLIPPAGE_LIMIT_EXCEEDED);
        
        uint reserveBalance       = _reserveBalance.sub(sendAmount);
        uint poolBalance          = _poolBalance.add(_tokenBamount); 
        uint newPrice             = uint256(PPM).mul(reserveBalance).div(poolBalance);

        //transfer tokens
        tokens[_tokenAid].transfer(msg.sender, sendAmount);       
        tokens[_tokenBid].transferFrom(msg.sender, address(this), _tokenBamount);       

        //TODO: add emit tokenSold
        updatePoolData(_poolId, reserveBalance, poolBalance, newPrice);

    }
}