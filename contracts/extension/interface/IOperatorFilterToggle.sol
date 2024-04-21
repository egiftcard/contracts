// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.0;

/// @author egiftcard

interface IOperatorFilterToggle {
    event OperatorRestriction(bool restriction);

    function operatorRestriction() external view returns (bool);

    function setOperatorRestriction(bool restriction) external;
}
