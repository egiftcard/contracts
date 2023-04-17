// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../../interfaces/IPackVRFDirect.sol";

library PackVRFDirectStorage {
    bytes32 public constant PACK_VRF_STORAGE_POSITION = keccak256("pack.vrf.storage");

    struct Data {
        /// @dev The token Id of the next set of packs to be minted.
        uint256 nextTokenIdToMint;
        /// @dev Total amount of link tokens in the contract (not including links as part of created packs).
        uint256 linkBalance;
        /// @dev Mapping from token ID => total circulating supply of token with that ID.
        mapping(uint256 => uint256) totalSupply;
        /// @dev Mapping from pack ID => The state of that set of packs.
        mapping(uint256 => IPackVRFDirect.PackInfo) packInfo;
        /*///////////////////////////////////////////////////////////////
                            VRF state
        //////////////////////////////////////////////////////////////*/
        mapping(uint256 => IPackVRFDirect.RequestInfo) requestInfo;
        mapping(address => uint256) openerToReqId;
    }

    function packVRFStorage() internal pure returns (Data storage packVrfData) {
        bytes32 position = PACK_VRF_STORAGE_POSITION;
        assembly {
            packVrfData.slot := position
        }
    }
}