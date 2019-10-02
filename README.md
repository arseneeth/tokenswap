# Aragon TokenSwap

![alt text](https://paintingvalley.com/drawings/libra-scale-drawing-22.jpg)

Aragon TokenSwap is a PoC implementation of an on-chain ERC20 token exchange based on Bancor inmplementation of Bonding Curve formula. It could potentially be used by DAOs in order to simplify the process of DAO's native token swapping to DAI, ANT, etc.

In the current implementation Liquidity Provider can open a public pool of two interchangable ERC20 tokens, through the bonding curve mechanics the system adjusts exchange rates and balances so the pool always stays in equilibrium.  

Current implementation does not include fees system and does not support multiple providers for the same pool. This functionality could be added in the future. 

It is smart-contracts-only app and doesn't have front-end yet.

## Usage

Prerequisites: `node`. `npm`, `aragon`, `ipfs`, `ganache-cli`

Clone the repo:
`git clone https://github.com/arsenyjin/tokenswap.git && cd tokenswap`

Install dependencies:
`npm install`

Run tests:
`npm test`

## Mechanics

Pool is a ledger of balances per liquidity provider per ERC20 tokens pair. Pool's data structure looks as follows:

```
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

```

Where `tokenA` is a base asset(currency in which prices are formed) and `tokenB` is a reserve asset(asset that users buy and sell). Liquidity provider can update pool data with the help of the following functions:

`createPool`, `closePool`, `addLiquidity`, `removeLiquidity`.

To make sure that Pool always stays in equiliblium we use `_isBalanced` function, which checks that `tokenA supply * tokenA price` equals `TokenB supply`.

Users can call `buy` and `sell` functions in order to buy or sell  `tokenB`. Users input the amount of tokens that they are willing to spend and the system automatically adjusts the amount they can get through the bonding curve mechanics. For `buy` it would be `calculatePurchaseReturn` function from `BancorFormula`, for `sell` it will be `calculateSaleReturn`. 

In order to prevent high price `slippage`, liquidity provider can set up the maximum slippage in percents and the system will automatically revert transactions with slippage higher than the limit through `_slippageLimitPassed` function. It checks if `expectedPrice-actualPrice <= _slippage*_expectedPrice`, if so the transaction will go through.

In order to close the pool liquidity provider should call `closePool` function which will set pool's `isActive` status to `false` and return all the funds being allocated in the pool to the liquidity provider. 
