# Aragon TokenSwap

Aragon TokenSwap is a PoC implementation of an on-chain ERC20 token exchange based on Bancor inmplementation of Bonding Curve formula. It could potentially be used by DAOs in order to simplify the process of DAO's native token swapping to DAI, ANT, etc.

In the current implementation Liquidity Provider can open a public pool of two interchangable ERC20 tokens, through the bonding curve the system adjusts exchange rates and balances so the pool always stays in equilibrium.  

Current implementation does not include fees system and does not support multiple pool providers. This functionality could be added in the future. 

It is smart-contracts only app and doesn't have front-end yet.

## Usage

Prerequisites: `node`. `npm`, `aragon`, `ipfs`, `ganache-cli`

Clone the repository 

`cd tokenswap`

`npm install`:

`npm test`

