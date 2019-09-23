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
let tokenA, tokenB, tokenAsupply, tokenBsupply, exchangeRate, slippage

contract('TokenSwap', accounts => {
  let dao, formula, tokenSwap
  let PROVIDER, BUY_ROLE, SELL_ROLE

  const rootUser = accounts[0]
  const provider = accounts[1]
  // const authorized2 = accounts[2]
  // const unauthorized = accounts[3]

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
    tokenA = await MiniMeToken.new(ZERO_ADDRESS, ZERO_ADDRESS, 0, 'Base', 18, 'BASE', true)
    tokenB = await MiniMeToken.new(ZERO_ADDRESS, ZERO_ADDRESS, 0, 'Sub', 18, 'SUB', true)

    await tokenA.generateTokens(provider, INITIAL_TOKEN_BALANCE)
    await tokenB.generateTokens(provider, INITIAL_TOKEN_BALANCE)

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

    await tokenA.approve(tokenSwap.address, tokenAsupply, { from: provider })
    await tokenB.approve(tokenSwap.address, tokenBsupply, { from: provider })

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


})