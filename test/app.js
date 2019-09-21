/* global artifacts contract beforeEach it assert */
const MiniMeToken = artifacts.require('MiniMeToken')

const { assertRevert } = require('@aragon/test-helpers/assertThrow')
const { getEventArgument } = require('@aragon/test-helpers/events')
const { hash } = require('eth-ens-namehash')
const deployDAO = require('./helpers/deployDAO')

const Formula = artifacts.require('BancorFormula.sol')
const TokenSwap = artifacts.require('TokenSwap.sol')


const ANY_ADDRESS = '0xffffffffffffffffffffffffffffffffffffffff'
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

const INITIAL_TOKEN_BALANCE = 10000 * Math.pow(10, 18) // 10000 DAIs or ANTs
const PPM                   = 1000000


contract('TokenSwap', ([appManager, user]) => {
  let tokenSwap

  beforeEach('deploy dao and app', async () => {
    const { dao, acl } = await deployDAO(appManager)

    // Deploy the app's base contract.
    const appBase = await TokenSwap.new()
    const formula = await Formula.new()

    // Instantiate a proxy for the app, using the base contract as its logic implementation.
    const instanceReceipt = await dao.newAppInstance(
      hash('counter.aragonpm.test'), // appId - Unique identifier for each app installed in the DAO; can be any bytes32 string in the tests.
      appBase.address, // appBase - Location of the app's base implementation.
      '0x', // initializePayload - Used to instantiate and initialize the proxy in the same call (if given a non-empty bytes string).
      false, // setDefault - Whether the app proxy is the default proxy.
      { from: appManager }
    )
    tokenSwap = TokenSwap.at(
      getEventArgument(instanceReceipt, 'NewAppProxy', 'proxy')
    )

    // Set up the app's permissions.
    await acl.createPermission(
      ANY_ADDRESS, // entity (who?) - The entity or address that will have the permission.
      tokenSwap.address, // app (where?) - The app that holds the role involved in this permission.
      await tokenSwap.ADMIN_ROLE(), // role (what?) - The particular role that the entity is being assigned to in this permission.
      appManager, // manager - Can grant/revoke further permissions for this role.
      { from: appManager }
    )

    await tokenSwap.initialize(formula.address)
  })

  it('should create a pool', async () => {

    const tokenA = await MiniMeToken.new(ZERO_ADDRESS, ZERO_ADDRESS, 0, 'Base', 18, 'BASE', true)
    const tokenB = await MiniMeToken.new(ZERO_ADDRESS, ZERO_ADDRESS, 0, 'Sub', 18, 'SUB', true)

    await tokenA.generateTokens(user, INITIAL_TOKEN_BALANCE)
    await tokenB.generateTokens(user, INITIAL_TOKEN_BALANCE)

    let tokenAsupply = new web3.BigNumber(30 * 10 ** 18)
    let tokenBsupply = new web3.BigNumber(15 * 10 ** 18)

    let exchangeRate = new web3.BigNumber(2*PPM) 

    await tokenA.approve(tokenSwap.address, tokenAsupply, { from: user })
    await tokenB.approve(tokenSwap.address, tokenBsupply, { from: user })

    await tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, exchangeRate, { from: user })
  })

  it('should create a pool and emit buy function', async () => {

    const tokenA = await MiniMeToken.new(ZERO_ADDRESS, ZERO_ADDRESS, 0, 'Base', 18, 'BASE', true)
    const tokenB = await MiniMeToken.new(ZERO_ADDRESS, ZERO_ADDRESS, 0, 'Sub', 18, 'SUB', true)

    await tokenA.generateTokens(user, INITIAL_TOKEN_BALANCE)
    await tokenB.generateTokens(user, INITIAL_TOKEN_BALANCE)


    let tokenAsupply = new web3.BigNumber(200 * 10 ** 18);
    let tokenBsupply = new web3.BigNumber(100 * 10 ** 18);
    let totalTokenBsupply = new web3.BigNumber(4900 * 10 ** 18);
    let exchangeRate = new web3.BigNumber(2*PPM); 
  
    await tokenA.approve(tokenSwap.address, tokenAsupply, { from: user })
    await tokenB.approve(tokenSwap.address, tokenBsupply, { from: user })

    await tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, exchangeRate, { from: user })

    poolId = 0;
    tokenAamount = new web3.BigNumber(1 * 10 ** 18);
    totalTokenBsupply = new web3.BigNumber(4900 * 10 ** 18);

    await tokenSwap.buy(poolId, tokenAamount, { from: user });
  })

  it('should create a pool and emit sell function', async () => {

    const tokenA = await MiniMeToken.new(ZERO_ADDRESS, ZERO_ADDRESS, 0, 'Base', 18, 'BASE', true)
    const tokenB = await MiniMeToken.new(ZERO_ADDRESS, ZERO_ADDRESS, 0, 'Sub', 18, 'SUB', true)

    await tokenA.generateTokens(user, INITIAL_TOKEN_BALANCE)
    await tokenB.generateTokens(user, INITIAL_TOKEN_BALANCE)


    let tokenAsupply = new web3.BigNumber(200 * 10 ** 18);
    let tokenBsupply = new web3.BigNumber(100 * 10 ** 18);
    let totalTokenBsupply = new web3.BigNumber(4900 * 10 ** 18);
    let exchangeRate = new web3.BigNumber(2*PPM); 
  
    await tokenA.approve(tokenSwap.address, tokenAsupply, { from: user })
    await tokenB.approve(tokenSwap.address, tokenBsupply, { from: user })

    await tokenSwap.createPool(tokenA.address, tokenB.address, tokenAsupply, tokenBsupply, exchangeRate, { from: user })

    poolId = 0;
    tokenAamount = new web3.BigNumber(1 * 10 ** 18);
    totalTokenBsupply = new web3.BigNumber(4900 * 10 ** 18);

    await tokenSwap.sell(poolId, tokenAamount, { from: user });
  })


})
