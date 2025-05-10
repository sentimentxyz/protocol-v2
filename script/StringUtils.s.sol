// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { BaseScript } from "./BaseScript.s.sol";

/**
 * @title StringUtils
 * @notice Utility contract for string parsing to reduce stack usage
 */
contract StringUtils is BaseScript {
    // Max uint256 value for unlimited caps
    uint256 internal constant _MAX_UINT256 =
        115_792_089_237_316_195_423_570_985_008_687_907_853_269_984_665_640_564_039_457_584_007_913_129_639_935;

    /**
     * @dev Parses scientific notation strings like "0.2e18" into uint256
     * @param notation The scientific notation string
     * @return The parsed uint256 value
     */
    function parseScientificNotation(string memory notation) public pure returns (uint256) {
        // Handle "max" special value
        bytes memory notationBytes = bytes(notation);
        if (notationBytes.length == 3 && notationBytes[0] == "m" && notationBytes[1] == "a" && notationBytes[2] == "x")
        {
            return _MAX_UINT256;
        }

        // Find 'e' position
        int256 ePos = -1;
        for (uint256 i = 0; i < notationBytes.length; i++) {
            if (notationBytes[i] == "e" || notationBytes[i] == "E") {
                ePos = int256(i);
                break;
            }
        }

        // If no 'e' found, try to parse as regular uint
        if (ePos == -1) return vm.parseUint(notation);

        // Extract the coefficient and exponent parts
        string memory coeffStr = substring(notation, 0, uint256(ePos));
        string memory expStr = substring(notation, uint256(ePos) + 1, notationBytes.length - uint256(ePos) - 1);

        // Parse coefficient as decimal
        uint256 decimalPos = findDecimalPoint(coeffStr);
        uint256 decimals = 0;
        uint256 coefficient;

        if (decimalPos != type(uint256).max) {
            // Has decimal point, count decimals and remove the point
            decimals = bytes(coeffStr).length - decimalPos - 1;
            string memory intPart = substring(coeffStr, 0, decimalPos);
            string memory decPart = substring(coeffStr, decimalPos + 1, bytes(coeffStr).length - decimalPos - 1);

            if (bytes(intPart).length == 0) intPart = "0";
            coefficient = vm.parseUint(string(abi.encodePacked(intPart, decPart)));
        } else {
            // No decimal point
            coefficient = vm.parseUint(coeffStr);
        }

        // Parse exponent
        uint256 exponent = vm.parseUint(expStr);

        // Apply decimals adjustment
        if (decimals > 0) exponent = exponent - decimals;

        // Calculate the final value: coefficient * 10^exponent
        return coefficient * (10 ** exponent);
    }

    /**
     * @dev Finds the position of the decimal point in a string
     * @param str The string to search
     * @return The position of the decimal point, or type(uint256).max if not found
     */
    function findDecimalPoint(string memory str) public pure returns (uint256) {
        bytes memory strBytes = bytes(str);

        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == ".") return i;
        }

        return type(uint256).max;
    }

    /**
     * @dev Extracts a substring from a string
     * @param str The input string
     * @param startIndex The starting index
     * @param length The length of the substring
     * @return The extracted substring
     */
    function substring(string memory str, uint256 startIndex, uint256 length) public pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        require(startIndex + length <= strBytes.length, "Substring out of bounds");

        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = strBytes[startIndex + i];
        }

        return string(result);
    }
}
