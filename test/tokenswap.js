const MiniMeToken = artifacts.require('MiniMeToken')
const Formula = artifacts.require('BancorFormula.sol')
const TokenSwap = artifacts.require('TokenSwap.sol')
const deployDAO = require('./helpers/deployDAO')
const assertEvent = require('@aragon/test-helpers/assertEvent')

const { assertRevert } = require('@aragon/test-helpers/assertThrow')
const { getEventArgument } = require('@aragon/test-helpers/events')
const { hash } = require('eth-ens-namehash')

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

const INITIAL_TOKEN_BALANCE = 10000 * Math.pow(10, 18) // 10000 DAIs or ANTs
const PPM = 1000000
const PCT_BASE = 1000000000000000000
let tokenA, tokenB, tokenAsupply, tokenBsupply, exchangeRate, slippage, tokenAliquidity, tokenBliquidity, tokenAamount

contract('TokenSwap', accounts => {
  let dao, formula, tokenSwap
  let PROVIDER, BUY_ROLE, SELL_ROLE

  const rootUser = accounts[0]
  const provider = accounts[1]
  const buyer = accounts[2]
  const seller = accounts[3]

  const initialize = async open => {
  const { dao, acl } = await deployDAO(rootUser)

  const appBase = await TokenSwap.new()
  const formula = await Formula.new()

  const instanceReceipt = await dao.newAppInstance(
      hash('tokenswap.aragonpm.test'), 
      appBase.address, 
      '0x', 
      false, 
      { from: rootUser }
    )
  tokenSwap = TokenSwap.at(
      getEventArgument(instanceReceipt, 'NewAppProxy', 'proxy')
    )

    // Set up the app's permissions.
  await acl.createPermission(
      provider, 
      tokenSwap.address, 
      await tokenSwap.PROVIDER(), 
      rootUser, 
      { from: rootUser }
    )

   await acl.createPermission(
      buyer, 
      tokenSwap.address, 
      await tokenSwap.BUYER(), 
      rootUser, 
      { from: rootUser }
    )

   await acl.createPermission(
      seller, 
      tokenSwap.address, 
      await tokenSwap.SELLER(), 
      rootUser, 
      { from: rootUser }
    )

   tokenA = await MiniMeToken.new(ZERO_ADDRESS, ZERO_ADDRESS, 0, 'Base', 18, 'BASE', true)
   tokenB = await MiniMeToken.new(ZERO_ADDRESS, ZERO_ADDRESS, 0, 'Sub', 18, 'SUB', true)

   await tokenA.generateTokens(provider, INITIAL_TOKEN_BALANCE)
   await tokenA.generateTokens(buyer, INITIAL_TOKEN_BALANCE)
   await tokenB.generateTokens(provider, INITIAL_TOKEN_BALANCE)
   await tokenB.generateTokens(seller, INITIAL_TOKEN_BALANCE)

   await tokenA.approve(tokenSwap.address, INITIAL_TOKEN_BALANCE, { from: provider })
   await tokenB.approve(tokenSwap.address, INITIAL_TOKEN_BALANCE, { from: provider })

   await tokenSwap.initialize(formula.address)
  }	  	

  beforeEach('deploy dao and app', async () => {
  
  	await initialize()
  
  })

  it('should create a pool', async () => {

    tokenAsupply = new web3.BigNumber(30 * 10 ** 18)
    tokenBsupply = new web3.BigNumber(15 * 10 ** 18)

    exchangeRate = new web3.BigNumber(2*PPM) 
    slippage = new web3.BigNumber(0.01*PPM);

    let receipt = await tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, slippage, exchangeRate, { from: provider })

    let balanceA = await tokenA.balanceOf(tokenSwap.address);
    let balanceB = await tokenB.balanceOf(tokenSwap.address);

    assert.equal(await balanceA.toNumber(), tokenAsupply)
    assert.equal(await balanceB.toNumber(), tokenBsupply)
    assertEvent(receipt, 'PoolCreated')
  })

  it('it should not allow to create the same pool twice', async () => {
    tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, slippage, exchangeRate, { from: provider })
    await assertRevert(() => tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, slippage, exchangeRate, { from: provider }))    
    })

  it('it should not allow to create an imbalanced pool', async () => {
    tokenAsupply = new web3.BigNumber(30 * 10 ** 18)
    tokenBsupply = new web3.BigNumber(2 * 10 ** 18)

    await assertRevert(() => tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, slippage, exchangeRate, { from: provider }))    
  })

 it('it should close the pool', async () => {
    tokenAsupply = new web3.BigNumber(30 * 10 ** 18)
    tokenBsupply = new web3.BigNumber(15 * 10 ** 18)
	
    let receipt = await tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, slippage, exchangeRate, { from: provider })

    assertEvent(receipt, 'PoolCreated')
    
    receipt = await tokenSwap.closePool(0, { from: provider })
    
    assertEvent(receipt, 'PoolClosed')

    let balanceA = await tokenA.balanceOf(tokenSwap.address);
    let balanceB = await tokenB.balanceOf(tokenSwap.address);

    assert.equal(await balanceA.toNumber(), 0)
    assert.equal(await balanceB.toNumber(), 0)
  })

 it('it should not allow to close the pool twice', async () => {
    tokenAsupply = new web3.BigNumber(30 * 10 ** 18)
    tokenBsupply = new web3.BigNumber(15 * 10 ** 18)
	
    let receipt = await tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, slippage, exchangeRate, { from: provider })

    assertEvent(receipt, 'PoolCreated')
    
    receipt = await tokenSwap.closePool(0, { from: provider })
    await assertRevert(() => tokenSwap.closePool(0, { from: provider }))    
  })

 it('it should recreate the pool', async () => {
    tokenAsupply = new web3.BigNumber(30 * 10 ** 18)
    tokenBsupply = new web3.BigNumber(15 * 10 ** 18)
	
    let receipt = await tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, slippage, exchangeRate, { from: provider })

    assertEvent(receipt, 'PoolCreated')
   
    await tokenSwap.closePool(0, { from: provider })

    receipt = await tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, slippage, exchangeRate, { from: provider })

    assertEvent(receipt, 'PoolCreated')
  })

 it('it should add liquidity to the pool', async () => {

    tokenAliquidity = new web3.BigNumber(4 * 10 ** 18)
    tokenBliqudity = new web3.BigNumber(2 * 10 ** 18)
  
    await tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, slippage, exchangeRate, { from: provider })

    let receipt = await tokenSwap.addLiquidity(0, tokenAliquidity, tokenBliqudity, { from: provider })

    let balanceA = await tokenA.balanceOf(tokenSwap.address);
    let balanceB = await tokenB.balanceOf(tokenSwap.address);

    let pool =  await tokenSwap.pools(0)

    assert.equal(await balanceA.toNumber(), pool[1])
    assert.equal(await balanceB.toNumber(), pool[2])
    
    assertEvent(receipt, 'PoolDataUpdated')
  })

 it('it should not allow to add liquidity twice due to issuficient balance', async () => {

    tokenAsupply = new web3.BigNumber(15 * 10 ** 18)
    tokenBsupply = new web3.BigNumber(15 * 10 ** 18)

    tokenAliquidity = new web3.BigNumber(6000 * 10 ** 18)
    tokenBliqudity = new web3.BigNumber(6000 * 10 ** 18)
    exchangeRate = new web3.BigNumber(1*PPM) 

    await tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, slippage, exchangeRate, { from: provider })
    await tokenSwap.addLiquidity(0, tokenAliquidity, tokenBliqudity, { from: provider })

    await assertRevert(() => tokenSwap.addLiquidity(0, tokenAliquidity, tokenBliqudity, { from: provider }))    
  })

 it('it should not allow to add liquidity because pool is closed', async () => {

    tokenAsupply = new web3.BigNumber(10000 * 10 ** 18)
    tokenBsupply = new web3.BigNumber(10000 * 10 ** 18)

    await tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, slippage, exchangeRate, { from: provider })
    await tokenSwap.closePool(0, { from: provider })

    await assertRevert(() => tokenSwap.addLiquidity(0, tokenAliquidity, tokenBliqudity, { from: provider }))    
  })

 it('it should remove liquidity from the pool', async () => {

    await tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, slippage, exchangeRate, { from: provider })
    await tokenSwap.removeLiquidity(0, tokenAliquidity, tokenBliqudity, { from: provider })    

  })

 it('it should not remove liquidity from the pool due to issuficient pool balance', async () => {

    let tokenC = await MiniMeToken.new(ZERO_ADDRESS, ZERO_ADDRESS, 0, 'C', 18, 'BASE', true)
    let tokenD = await MiniMeToken.new(ZERO_ADDRESS, ZERO_ADDRESS, 0, 'D', 18, 'D', true)

    await tokenC.generateTokens(provider, INITIAL_TOKEN_BALANCE)
    await tokenD.generateTokens(provider, INITIAL_TOKEN_BALANCE)

    await tokenC.approve(tokenSwap.address, INITIAL_TOKEN_BALANCE, { from: provider })
    await tokenD.approve(tokenSwap.address, INITIAL_TOKEN_BALANCE, { from: provider })

    await tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, slippage, exchangeRate, { from: provider })
    await tokenSwap.createPool(tokenC.address, tokenD.address, tokenAsupply, tokenBsupply, slippage, exchangeRate, { from: provider })

    await tokenSwap.removeLiquidity(0, tokenAliquidity, tokenBliqudity, { from: provider })    

    await assertRevert(() => tokenSwap.removeLiquidity(0, tokenAliquidity, tokenBliqudity, { from: provider }))    
  })
 
it('it should buy tokens from the pool and pass slippage limit', async () => {

    tokenAsupply = new web3.BigNumber(4000 * 10 ** 18)
    tokenBsupply = new web3.BigNumber(1000 * 10 ** 18)

    exchangeRate = new web3.BigNumber(tokenAsupply/tokenBsupply*PPM) 

    tokenAamount = new web3.BigNumber(2 * 10 ** 18);

    await tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, slippage, exchangeRate, { from: provider })

    await tokenSwap.buy(0, tokenAamount, { from: buyer })

    let boughtB = await tokenB.balanceOf(buyer);
    let actualPrice  = await boughtB*exchangeRate/PPM;
    let expectedPrice = tokenAamount //-(slippage*PCT_BASE/PPM)
    let slippageLimitPassed = await (expectedPrice-actualPrice <= (slippage/PPM)*expectedPrice)

  	assert.equal(slippageLimitPassed, true);
  })

it('it should not allow to buy tokens from the pool dur to the low slippage limit', async () => {

    let testSlippage = new web3.BigNumber(0.0001*PPM);


    tokenAsupply = new web3.BigNumber(4000 * 10 ** 18)
    tokenBsupply = new web3.BigNumber(1000 * 10 ** 18)
	
    exchangeRate = new web3.BigNumber(tokenAsupply/tokenBsupply*PPM) 

    tokenAamount = new web3.BigNumber(2 * 10 ** 18);

    await tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, testSlippage, exchangeRate, { from: provider })

    await assertRevert(() => tokenSwap.buy(0, tokenAamount, { from: buyer }))        
  })


it('it should not allow to buy tokens from the non existing pool', async () => {

    await assertRevert(() => tokenSwap.buy(0, tokenAamount, { from: buyer }))        
  })

it('it should not allow to buy tokens from the closed pool', async () => {
    
    await tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, slippage, exchangeRate, { from: provider })
    await tokenSwap.closePool(0, { from: provider })
    await assertRevert(() => tokenSwap.buy(0, tokenAamount, { from: buyer }))    
  })


it('it should sell tokens from the pool and pass slippage limit', async () => {

    let tokenBamount = new web3.BigNumber(3 * 10 ** 18);

    await tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, slippage, exchangeRate, { from: provider })
    await tokenSwap.sell(0, tokenBamount, { from: seller })    

    let tokensApaid = await tokenA.balanceOf(seller)
    let actualPrice = await tokensApaid.toNumber()
    let expectedPrice = await (tokenBamount*exchangeRate/PPM)

    let slippageLimitPassed = await (expectedPrice-actualPrice >= slippage*PCT_BASE/PPM)
  })

it('it should not allow to sell tokens to the closed pool', async () => {

    await tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, slippage, exchangeRate, { from: provider })
    await tokenSwap.closePool(0, { from: provider })
    await assertRevert(() => tokenSwap.sell(0, tokenAamount, { from: buyer }))    
  })

it('it should not allow to sell tokens to the pool due to the low slippage limit', async () => {

    let testSlippage = new web3.BigNumber(0.0001*PPM);

    tokenAsupply = new web3.BigNumber(4000 * 10 ** 18)
    tokenBsupply = new web3.BigNumber(1000 * 10 ** 18)

    exchangeRate = new web3.BigNumber(tokenAsupply/tokenBsupply*PPM) 

    tokenAamount = new web3.BigNumber(2 * 10 ** 18);

    await tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, testSlippage, exchangeRate, { from: provider })

    await assertRevert(() => tokenSwap.buy(0, tokenAamount, { from: buyer }))        
  })
})
