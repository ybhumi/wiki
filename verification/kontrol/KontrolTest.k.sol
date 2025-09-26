pragma solidity ^0.8.25;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

contract KontrolTest is Test, KontrolCheats {
    // Note: there are lemmas dependent on `ethUpperBound`
    uint256 constant ethMaxWidth = 96;
    uint256 constant ETH_UPPER_BOUND = 2 ** ethMaxWidth;
    // Note: 2 ** 35 takes us to year 3058
    uint256 constant timeUpperBound = 2 ** 35;

    function infoAssert(bool condition, string memory message) external pure {
        if (!condition) {
            revert(message);
        }
    }

    enum Mode {
        Assume,
        Try,
        Assert
    }

    function _establish(Mode mode, bool condition) internal pure returns (bool) {
        if (mode == Mode.Assume) {
            vm.assume(condition);
            return true;
        } else if (mode == Mode.Try) {
            return condition;
        } else {
            vm.assertEq(condition, true);
            return true;
        }
    }

    function freshUInt256Bounded() internal view returns (uint256) {
        uint256 fresh = freshUInt256();
        vm.assume(fresh < ETH_UPPER_BOUND);
        return fresh;
    }

    function freshUInt256Bounded(string memory varName) internal view returns (uint256) {
        uint256 fresh = kevm.freshUInt(32, varName);
        vm.assume(fresh < ETH_UPPER_BOUND);
        return fresh;
    }

    function _loadData(
        address contractAddress,
        uint256 slot,
        uint256 offset,
        uint256 width
    ) internal view returns (uint256) {
        // `offset` and `width` must not overflow the slot
        assert(offset + width <= 32);

        // Slot read mask
        uint256 mask;
        unchecked {
            mask = (2 ** (8 * width)) - 1;
        }
        // Value right shift
        uint256 shift = 8 * offset;

        // Current slot value
        uint256 slotValue = uint256(vm.load(contractAddress, bytes32(slot)));

        // Isolate and return data to retrieve
        return mask & (slotValue >> shift);
    }

    function _storeData(address contractAddress, uint256 slot, uint256 offset, uint256 width, uint256 value) internal {
        // `offset` and `width` must not overflow the slot
        assert(offset + width <= 32);
        // and `value` must fit into the designated part
        assert(width == 32 || value < 2 ** (8 * width));

        // Slot update mask
        uint256 maskLeft;
        unchecked {
            maskLeft = ~((2 ** (8 * (offset + width))) - 1);
        }
        uint256 maskRight = (2 ** (8 * offset)) - 1;
        uint256 mask = maskLeft | maskRight;

        uint256 newValue = (2 ** (8 * offset)) * value;

        // Current slot value
        uint256 slotValue = uint256(vm.load(contractAddress, bytes32(slot)));
        // Updated slot value
        slotValue = newValue | (mask & slotValue);

        vm.store(contractAddress, bytes32(slot), bytes32(slotValue));
    }

    function _loadMappingData(
        address contractAddress,
        uint256 mappingSlot,
        uint256 key,
        uint256 subSlot,
        uint256 offset,
        uint256 width
    ) internal view returns (uint256) {
        bytes32 hashedSlot = keccak256(abi.encodePacked(key, mappingSlot));
        return _loadData(contractAddress, uint256(hashedSlot) + subSlot, offset, width);
    }

    function _storeMappingData(
        address contractAddress,
        uint256 mappingSlot,
        uint256 key,
        uint256 subSlot,
        uint256 offset,
        uint256 width,
        uint256 value
    ) internal {
        bytes32 hashedSlot = keccak256(abi.encodePacked(key, mappingSlot));
        _storeData(contractAddress, uint256(hashedSlot) + subSlot, offset, width, value);
    }

    function _loadUInt256(address contractAddress, uint256 slot) internal view returns (uint256) {
        return _loadData(contractAddress, slot, 0, 32);
    }

    function _loadMappingUInt256(
        address contractAddress,
        uint256 mappingSlot,
        uint256 key,
        uint256 subSlot
    ) internal view returns (uint256) {
        bytes32 hashedSlot = keccak256(abi.encodePacked(key, mappingSlot));
        return _loadData(contractAddress, uint256(hashedSlot) + subSlot, 0, 32);
    }

    function _loadAddress(address contractAddress, uint256 slot) internal view returns (address) {
        return address(uint160(_loadData(contractAddress, slot, 0, 20)));
    }

    function _storeMappingUInt256(
        address contractAddress,
        uint256 mappingSlot,
        uint256 key,
        uint256 subSlot,
        uint256 value
    ) internal {
        bytes32 hashedSlot = keccak256(abi.encodePacked(key, mappingSlot));
        _storeData(contractAddress, uint256(hashedSlot) + subSlot, 0, 32, value);
    }

    function _storeUInt256(address contractAddress, uint256 slot, uint256 value) internal {
        _storeData(contractAddress, slot, 0, 32, value);
    }

    function _storeAddress(address contractAddress, uint256 slot, address value) internal {
        _storeData(contractAddress, slot, 0, 20, uint160(value));
    }

    function _storeBytes32(address contractAddress, uint256 slot, bytes32 value) internal {
        _storeUInt256(contractAddress, slot, uint256(value));
    }

    function _assumeNoOverflow(uint256 augend, uint256 addend) internal pure {
        unchecked {
            vm.assume(augend < augend + addend);
        }
    }

    function _clearSlot(address contractAddress, uint256 slot) internal {
        _storeUInt256(contractAddress, slot, 0);
    }

    function _clearMappingSlot(address contractAddress, uint256 mappingSlot, uint256 key, uint256 subSlot) internal {
        bytes32 hashedSlot = keccak256(abi.encodePacked(key, mappingSlot));
        _storeData(contractAddress, uint256(hashedSlot) + subSlot, 0, 32, 0);
    }
}
