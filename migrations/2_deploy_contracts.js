/* global artifacts */
var TokenSwap = artifacts.require('TokenSwap.sol')

module.exports = function(deployer) {
  deployer.deploy(TokenSwap)
}
