// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

import "../../../lib/CurrencyTransferLib.sol";
import "../../../eip/interface/IERC20.sol";

import { IPRBProxy } from "@prb/proxy/src/interfaces/IPRBProxy.sol";
import "./interface/IPluginCheckout.sol";

//   $$\     $$\       $$\                 $$\                         $$\
//   $$ |    $$ |      \__|                $$ |                        $$ |
// $$$$$$\   $$$$$$$\  $$\  $$$$$$\   $$$$$$$ |$$\  $$\  $$\  $$$$$$\  $$$$$$$\
// \_$$  _|  $$  __$$\ $$ |$$  __$$\ $$  __$$ |$$ | $$ | $$ |$$  __$$\ $$  __$$\
//   $$ |    $$ |  $$ |$$ |$$ |  \__|$$ /  $$ |$$ | $$ | $$ |$$$$$$$$ |$$ |  $$ |
//   $$ |$$\ $$ |  $$ |$$ |$$ |      $$ |  $$ |$$ | $$ | $$ |$$   ____|$$ |  $$ |
//   \$$$$  |$$ |  $$ |$$ |$$ |      \$$$$$$$ |\$$$$$\$$$$  |\$$$$$$$\ $$$$$$$  |
//    \____/ \__|  \__|\__|\__|       \_______| \_____\____/  \_______|\_______/

contract TargetCheckout is IPluginCheckout {
    mapping(address => bool) public isApprovedRouter;

    function withdraw(address _token, uint256 _amount) external {
        require(msg.sender == IPRBProxy(address(this)).owner(), "Not authorized");

        CurrencyTransferLib.transferCurrency(_token, address(this), msg.sender, _amount);
    }

    function approveSwapRouter(address _swapRouter, bool _toApprove) external {
        require(msg.sender == IPRBProxy(address(this)).owner(), "Not authorized");
        require(_swapRouter != address(0), "Zero address");

        isApprovedRouter[_swapRouter] = _toApprove;
    }

    function execute(UserOp memory op) external {
        require(_canExecute(op, msg.sender), "Not authorized");

        _execute(op);
    }

    function swapAndExecute(UserOp memory op, UserOp memory swapOp) external {
        require(isApprovedRouter[swapOp.target], "Invalid router address");
        require(_canExecute(op, msg.sender), "Not authorized");

        _execute(swapOp);
        _execute(op);
    }

    // =================================================
    // =============== Internal functions ==============
    // =================================================

    function _execute(UserOp memory op) internal {
        bool success;
        if (op.currency == CurrencyTransferLib.NATIVE_TOKEN) {
            (success, ) = op.target.call{ value: op.valueToSend }(op.data);
        } else {
            if (op.valueToSend != 0 && op.approvalRequired) {
                IERC20(op.currency).approve(op.target, op.valueToSend);
            }

            (success, ) = op.target.call(op.data);
        }

        require(success, "Execution failed");
    }

    function _canExecute(UserOp memory op, address caller) internal view returns (bool) {
        address owner = IPRBProxy(address(this)).owner();
        if (owner != caller) {
            bool permission = IPRBProxy(address(this)).registry().getPermissionByOwner({
                owner: owner,
                envoy: caller,
                target: op.target
            });

            return permission;
        }

        return true;
    }
}
