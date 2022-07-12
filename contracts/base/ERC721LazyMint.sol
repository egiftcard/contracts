// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./ERC721Base.sol";

import "../extension/LazyMint.sol";

import "../lib/TWStrings.sol";

/**
 *      BASE:      ERC721Base
 *      EXTENSION: LazyMint
 *
 *  The `ERC721LazyMint` contract uses the `ERC721Base` contract, along with the `LazyMint` extension.
 *
 *  'Lazy minting' means defining the metadata of NFTs without minting it to an address. Regular 'minting'
 *  of  NFTs means actually assigning an owner to an NFT.
 *
 *  As a contract admin, this lets you prepare the metadata for NFTs that will be minted by an external party,
 *  without paying the gas cost for actually minting the NFTs.
 *
 */

contract ERC721LazyMint is ERC721Base, LazyMint {
    using TWStrings for uint256;

    /*//////////////////////////////////////////////////////////////
                            Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _contractURI,
        address _royaltyRecipient,
        uint128 _royaltyBps
    ) ERC721Base(_name, _symbol, contractURI, _royaltyRecipient, _royaltyBps) {}

    /*//////////////////////////////////////////////////////////////
                            Minting logic
    //////////////////////////////////////////////////////////////*/

    /**
     *  @notice          Lets an authorized address mint a lazy minted NFT to a recipient.
     *  @dev             The logic in the `_canMint` function determines whether the caller is authorized to mint NFTs.
     *
     *  @param _to       The recipient of the NFT to mint.
     */
    function mint(address _to, string memory) public virtual override {
        require(_canMint(), "Not authorized to mint.");
        require(nextTokenIdToMint() + 1 <= nextTokenIdToLazyMint, "Not enough lazy minted tokens.");

        _safeMint(_to, 1, "");
    }

    /**
     *  @notice          Lets an authorized address mint multiple lazy minted NFTs at once to a recipient.
     *  @dev             The logic in the `_canMint` function determines whether the caller is authorized to mint NFTs.
     *
     *  @param _to       The recipient of the NFT to mint.
     *  @param _quantity The number of NFTs to mint.
     *  @param _data     Additional data to pass along during the minting of the NFT.
     */
    function batchMint(
        address _to,
        uint256 _quantity,
        string memory,
        bytes memory _data
    ) public virtual override {
        require(_canMint(), "Not authorized to mint.");
        require(nextTokenIdToMint() + _quantity <= nextTokenIdToLazyMint, "Not enough lazy minted tokens.");

        _safeMint(_to, _quantity, _data);
    }

    /*//////////////////////////////////////////////////////////////
                        Internal functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns whether lazy minting can be done in the given execution context.
    function _canLazyMint() internal view virtual override returns (bool) {
        return msg.sender == owner();
    }
}