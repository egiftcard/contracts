// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/// @author thirdweb

/**
 *  @author  thirdweb.com
 */
library ContractMetadataStorage {
    bytes32 private constant CONTRACT_METADATA_STORAGE_POSITION = keccak256("contract.metadata.storage");

    struct Data {
        string contractURI;
    }

    function contractMetadataStorage() internal pure returns (Data storage contractMetadataData) {
        bytes32 position = CONTRACT_METADATA_STORAGE_POSITION;
        assembly {
            contractMetadataData.slot := position
        }
    }
}
