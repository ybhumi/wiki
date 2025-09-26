// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Initializable } from "solady/utils/Initializable.sol";
import { ISplitChecker } from "src/zodiac-core/interfaces/ISplitChecker.sol";

import { AlreadyInitialized } from "src/errors.sol";
/// @title SplitChecker
/// @notice Validates split configurations for revenue distribution
/// @dev Ensures splits meet requirements for opex and metapool allocations

contract SplitChecker is ISplitChecker, Initializable {
    // =============================================================
    //                            CONSTANTS
    // =============================================================

    uint256 private constant SPLIT_PRECISION = 1e18;

    // =============================================================
    //                            STORAGE
    // =============================================================

    /// @notice Address of the governance controller
    address public governance;

    /// @notice Max operational expenses split
    /// @dev in precision of 1e18
    uint256 public maxOpexSplit;

    /// @notice Min metapool split
    /// @dev in precision of 1e18
    uint256 public minMetapoolSplit;

    // =============================================================
    //                            EVENTS
    // =============================================================

    /// @notice Emitted when the maximum opex split is updated
    /// @param newMaxOpexSplit The new maximum opex split value
    event MaxOpexSplitUpdated(uint256 newMaxOpexSplit);

    /// @notice Emitted when the minimum metapool split is updated
    /// @param newMinMetapoolSplit The new minimum metapool split value
    event MinMetapoolSplitUpdated(uint256 newMinMetapoolSplit);

    // =============================================================
    //                            ERRORS
    // =============================================================

    /// @notice Thrown when the split configuration is invalid
    error InvalidSplit();

    /// @notice Thrown when the caller is not authorized
    error NotAuthorized();

    /// @notice Thrown when a value exceeds the allowed maximum
    error ValueExceedsMaximum();

    /// @notice Thrown when a value is below the required minimum
    error ValueBelowMinimum();

    // =============================================================
    //                            MODIFIERS
    // =============================================================

    /// @notice Restricts function access to governance address
    /// @dev Throws if called by any account other than governance
    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotAuthorized();
        _;
    }

    // =============================================================
    //                         INITIALIZATION
    // =============================================================

    /// @notice Initializes the SplitChecker contract
    /// @param _governance Address of the governance controller
    /// @param _maxOpexSplit Maximum allowed split for operational expenses (scaled by 1e18)
    /// @param _minMetapoolSplit Minimum required split for metapool (scaled by 1e18)
    function initialize(address _governance, uint256 _maxOpexSplit, uint256 _minMetapoolSplit) external initializer {
        if (governance != address(0)) revert AlreadyInitialized();
        governance = _governance;
        _setMaxOpexSplit(_maxOpexSplit);
        _setMinMetapoolSplit(_minMetapoolSplit);
    }

    // =============================================================
    //                         GOVERNANCE
    // =============================================================

    /// @notice Updates the minimum required metapool split
    /// @param _minMetapoolSplit New minimum split value (scaled by 1e18)
    function setMinMetapoolSplit(uint256 _minMetapoolSplit) external onlyGovernance {
        _setMinMetapoolSplit(_minMetapoolSplit);
        emit MinMetapoolSplitUpdated(_minMetapoolSplit);
    }

    /// @notice Updates the maximum allowed opex split
    /// @param _maxOpexSplit New maximum split value (scaled by 1e18)
    function setMaxOpexSplit(uint256 _maxOpexSplit) external onlyGovernance {
        _setMaxOpexSplit(_maxOpexSplit);
    }

    // =============================================================
    //                         VALIDATION
    // =============================================================

    /// @notice Validates split configuration for revenue distribution
    /// @param split Split configuration to validate
    /// @param opexVault Address of the operational expenses vault
    /// @param metapool Address of the metapool
    /// @dev Ensures splits meet requirements for opex and metapool allocations
    function checkSplit(Split memory split, address opexVault, address metapool) external view override {
        if (split.recipients.length != split.allocations.length) revert InvalidSplit();
        bool flag = false;
        uint256 calculatedTotalAllocation = 0;
        for (uint256 i = 0; i < split.recipients.length; i++) {
            if (split.recipients[i] == opexVault) {
                if ((split.allocations[i] * SPLIT_PRECISION) / split.totalAllocations > maxOpexSplit) {
                    revert ValueExceedsMaximum();
                }
            }
            if (split.recipients[i] == metapool) {
                if ((split.allocations[i] * SPLIT_PRECISION) / split.totalAllocations <= minMetapoolSplit) {
                    revert ValueBelowMinimum();
                }
                flag = true;
            }
            calculatedTotalAllocation += split.allocations[i];
        }
        if (!flag) revert InvalidSplit();
        if (calculatedTotalAllocation != split.totalAllocations) revert InvalidSplit();
    }

    // =============================================================
    //                         INTERNAL
    // =============================================================

    /// @notice Internal function to set maximum opex split
    /// @param _maxOpexSplit New maximum split value (scaled by 1e18)
    /// @dev Validates that split doesn't exceed 100% (1e18)
    function _setMaxOpexSplit(uint256 _maxOpexSplit) internal {
        if (_maxOpexSplit > 1e18) revert ValueExceedsMaximum();
        maxOpexSplit = _maxOpexSplit;
        emit MaxOpexSplitUpdated(_maxOpexSplit);
    }

    /// @notice Internal function to set minimum metapool split
    /// @param _minMetapoolSplit New minimum split value (scaled by 1e18)
    /// @dev Validates that split doesn't exceed 100% (1e18)
    function _setMinMetapoolSplit(uint256 _minMetapoolSplit) internal {
        if (_minMetapoolSplit > 1e18) revert ValueExceedsMaximum();
        minMetapoolSplit = _minMetapoolSplit;
        emit MinMetapoolSplitUpdated(_minMetapoolSplit);
    }
}
