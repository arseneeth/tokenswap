/* global artifacts contract beforeEach it assert */

const { assertRevert } = require('@aragon/test-helpers/assertThrow')
const { getEventArgument } = require('@aragon/test-helpers/events')
const { hash } = require('eth-ens-namehash')
const deployDAO = require('./helpers/deployDAO')

const TokenSwap = artifacts.require('TokenSwap.sol')

const ANY_ADDRESS = '0xffffffffffffffffffffffffffffffffffffffff'

contract('TokenSwap', ([appManager, user]) => {
  let app

  beforeEach('deploy dao and app', async () => {
    const { dao, acl } = await deployDAO(appManager)

    // Deploy the app's base contract.
    const appBase = await TokenSwap.new()

    // Instantiate a proxy for the app, using the base contract as its logic implementation.
    const instanceReceipt = await dao.newAppInstance(
      hash('counter.aragonpm.test'), // appId - Unique identifier for each app installed in the DAO; can be any bytes32 string in the tests.
      appBase.address, // appBase - Location of the app's base implementation.
      '0x', // initializePayload - Used to instantiate and initialize the proxy in the same call (if given a non-empty bytes string).
      false, // setDefault - Whether the app proxy is the default proxy.
      { from: appManager }
    )
    app = TokenSwap.at(
      getEventArgument(instanceReceipt, 'NewAppProxy', 'proxy')
    )

    // Set up the app's permissions.
    await acl.createPermission(
      ANY_ADDRESS, // entity (who?) - The entity or address that will have the permission.
      app.address, // app (where?) - The app that holds the role involved in this permission.
      await app.ADMIN_ROLE(), // role (what?) - The particular role that the entity is being assigned to in this permission.
      appManager, // manager - Can grant/revoke further permissions for this role.
      { from: appManager }
    )

    await app.initialize()
  })

  it('should create a pool', async () => {
    PPM = 1000000;

    tokenAsupply = new web3.BigNumber(30 * 10 ** 18);
    tokenBsupply = new web3.BigNumber(15 * 10 ** 18);
    totalTokenBsupply = new web3.BigNumber(290 * 10 ** 18);
    exchangeRate = new web3.BigNumber(2*PPM); 
    
    await app.createPool(tokenAsupply, tokenBsupply, totalTokenBsupply, exchangeRate, { from: user })
    // await console.log(await app.pools(0));
    // assert.equal(await app.value(), 10)
  })

  it('should create a pool and emit buy function', async () => {
    tokenAsupply = new web3.BigNumber(200 * 10 ** 18);
    tokenBsupply = new web3.BigNumber(100 * 10 ** 18);
    totalTokenBsupply = new web3.BigNumber(4900 * 10 ** 18);
    exchangeRate = new web3.BigNumber(2*PPM); 
    
    await app.createPool(tokenAsupply, tokenBsupply, totalTokenBsupply, exchangeRate, { from: user })
    // await console.log(await app.pools(0));

    poolId = 0;
    tokenAamount = new web3.BigNumber(1 * 10 ** 18);
    totalTokenBsupply = new web3.BigNumber(4900 * 10 ** 18);

    await app.buy(poolId, tokenAamount, totalTokenBsupply, { from: user });
    // await console.log(await app.pools(0));

  })

  // it('should create a pool and emit sell function', async () => {
  //   tokenAsupply = new web3.BigNumber(100 * 10 ** 18);
  //   tokenBsupply = new web3.BigNumber(900 * 10 ** 18);
  //   totalTokenBsupply = new web3.BigNumber(4900 * 10 ** 18);
  //   exchangeRate = new web3.BigNumber(10); 
    
  //   await app.createPool(tokenAsupply, tokenBsupply, totalTokenBsupply, exchangeRate, { from: user })
  //   await console.log(await app.pools(0));

  //   poolId = 0;
  //   tokenAamount = new web3.BigNumber(1 * 10 ** 18);
  //   totalTokenBsupply = new web3.BigNumber(4900 * 10 ** 18);

  //   await app.sell(poolId, tokenAamount, totalTokenBsupply, { from: user });
  //   await console.log(await app.pools(0));

  // })


})
