pragma solidity 0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/os/contracts/common/SafeERC20.sol";
import "@aragon/os/contracts/lib/token/ERC20.sol";
import "./IAragonFundraisingController.sol";


contract AragonFundraisingControllerMock is IAragonFundraisingController, AragonApp {
    using SafeERC20 for ERC20;

    function initialize() external onlyInit {
        initialized();
    }

    function openTrading() external {
        // mock
    }

    function resetTokenTap(address _token) external {
        // mock
    }

    function collateralsToBeClaimed(address _collateral) public view returns (uint256) {
        if (_collateral == ETH) {
            return uint256(5);
        } else {
            return uint256(10);
        }
    }

    function balanceOf(address _who, address _token) public view returns (uint256) {
        if (_token == ETH) {
            return _who.balance;
        } else {
            return ERC20(_token).staticBalanceOf(_who);
        }
    }
}
