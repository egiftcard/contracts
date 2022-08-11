// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./ERC1155SignatureMint.sol";

import "../extension/DropSinglePhase1155.sol";
import "../extension/LazyMint.sol";
import "../extension/DelayedReveal.sol";

contract ERC1155Drop is ERC1155SignatureMint, LazyMint, DelayedReveal, DropSinglePhase1155 {
    using TWStrings for uint256;

    /*///////////////////////////////////////////////////////////////
                            Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(
        string memory _name,
        string memory _symbol,
        address _royaltyRecipient,
        uint128 _royaltyBps,
        address _primarySaleRecipient
    ) ERC1155SignatureMint(_name, _symbol, _royaltyRecipient, _royaltyBps, _primarySaleRecipient) {}

    /*///////////////////////////////////////////////////////////////
                    Overriden metadata logic
    //////////////////////////////////////////////////////////////*/

    /**
     *  @notice         Returns the metadata URI for an NFT.
     *  @dev            See `BatchMintMetadata` for handling of metadata in this contract.
     *
     *  @param _tokenId The tokenId of an NFT.
     */
    function uri(uint256 _tokenId) public view virtual override returns (string memory) {
        (uint256 batchId, ) = getBatchId(_tokenId);
        string memory batchUri = getBaseURI(_tokenId);

        if (isEncryptedBatch(batchId)) {
            return string(abi.encodePacked(batchUri, "0"));
        } else {
            return string(abi.encodePacked(batchUri, _tokenId.toString()));
        }
    }

    /*//////////////////////////////////////////////////////////////
                        Signature minting logic
    //////////////////////////////////////////////////////////////*/

    /**
     *  @notice           Mints tokens according to the provided mint request.
     *
     *  @param _req       The payload / mint request.
     *  @param _signature The signature produced by an account signing the mint request.
     */
    function mintWithSignature(MintRequest calldata _req, bytes calldata _signature)
        external
        payable
        virtual
        override
        returns (address signer)
    {
        require(_req.quantity > 0, "Minting zero tokens.");

        uint256 tokenIdToMint = _req.tokenId;
        require(tokenIdToMint < nextTokenIdToMint(), "Claiming invalid tokenId.");

        // Verify and process payload.
        signer = _processRequest(_req, _signature);

        /**
         *  Get receiver of tokens.
         *
         *  Note: If `_req.to == address(0)`, a `mintWithSignature` transaction sitting in the
         *        mempool can be frontrun by copying the input data, since the minted tokens
         *        will be sent to the `_msgSender()` in this case.
         */
        address receiver = _req.to == address(0) ? msg.sender : _req.to;

        // Collect price
        collectPriceOnClaim(_req.quantity, _req.currency, _req.pricePerToken);

        // Mint tokens.
        _mint(receiver, tokenIdToMint, _req.quantity, "");

        emit TokensMintedWithSignature(signer, receiver, tokenIdToMint, _req);
    }

    /*///////////////////////////////////////////////////////////////
                        Delayed reveal logic
    //////////////////////////////////////////////////////////////*/

    /**
     *  @notice       Lets an authorized address reveal a batch of delayed reveal NFTs.
     *
     *  @param _index The ID for the batch of delayed-reveal NFTs to reveal.
     *  @param _key   The key with which the base URI for the relevant batch of NFTs was encrypted.
     */
    function reveal(uint256 _index, bytes calldata _key) public virtual override returns (string memory revealedURI) {
        require(_canReveal(), "Not authorized");

        uint256 batchId = getBatchIdAtIndex(_index);
        revealedURI = getRevealURI(batchId, _key);

        _setEncryptedBaseURI(batchId, "");
        _setBaseURI(batchId, revealedURI);

        emit TokenURIRevealed(_index, revealedURI);
    }

    /*///////////////////////////////////////////////////////////////
                    Overriden lazy minting logic
    //////////////////////////////////////////////////////////////*/

    /**
     *  @notice                  Lets an authorized address lazy mint a given amount of NFTs.
     *
     *  @param _amount           The number of NFTs to lazy mint.
     *  @param _baseURIForTokens The placeholder base URI for the 'n' number of NFTs being lazy minted, where the
     *                           metadata for each of those NFTs is `${baseURIForTokens}/${tokenId}`.
     *  @param _encryptedBaseURI The encrypted base URI for the batch of NFTs being lazy minted.
     *  @return batchId          A unique integer identifier for the batch of NFTs lazy minted together.
     */
    function lazyMint(
        uint256 _amount,
        string calldata _baseURIForTokens,
        bytes calldata _encryptedBaseURI
    ) public virtual override returns (uint256 batchId) {
        if (_encryptedBaseURI.length != 0) {
            _setEncryptedBaseURI(nextTokenIdToLazyMint + _amount, _encryptedBaseURI);
        }

        return LazyMint.lazyMint(_amount, _baseURIForTokens, _encryptedBaseURI);
    }

    /// @notice The tokenId assigned to the next new NFT to be lazy minted.
    function nextTokenIdToMint() public view virtual override returns (uint256) {
        return nextTokenIdToLazyMint;
    }

    /*///////////////////////////////////////////////////////////////
                        Internal functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Runs before every `claim` function call.
    function _beforeClaim(
        uint256 _tokenId,
        address,
        uint256,
        address,
        uint256,
        AllowlistProof calldata,
        bytes memory
    ) internal view virtual override {
        require(msg.sender == tx.origin, "BOT");
        if (_tokenId >= nextTokenIdToLazyMint) {
            revert("Not enough minted tokens");
        }
    }

    /// @dev Collects and distributes the primary sale value of NFTs being claimed.
    function collectPriceOnClaim(
        uint256 _quantityToClaim,
        address _currency,
        uint256 _pricePerToken
    ) internal virtual override(DropSinglePhase1155, ERC1155SignatureMint) {
        if (_pricePerToken == 0) {
            return;
        }

        uint256 totalPrice = _quantityToClaim * _pricePerToken;

        if (_currency == CurrencyTransferLib.NATIVE_TOKEN) {
            if (msg.value != totalPrice) {
                revert("Must send total price");
            }
        }

        CurrencyTransferLib.transferCurrency(_currency, msg.sender, primarySaleRecipient(), totalPrice);
    }

    /// @dev Transfers the NFTs being claimed.
    function transferTokensOnClaim(
        address _to,
        uint256 _tokenId,
        uint256 _quantityBeingClaimed
    ) internal virtual override {
        _mint(_to, _tokenId, _quantityBeingClaimed, "");
    }

    /// @dev Checks whether primary sale recipient can be set in the given execution context.
    function _canSetPrimarySaleRecipient() internal view virtual override returns (bool) {
        return msg.sender == owner();
    }

    /// @dev Checks whether owner can be set in the given execution context.
    function _canSetOwner() internal view virtual override returns (bool) {
        return msg.sender == owner();
    }

    /// @dev Checks whether royalty info can be set in the given execution context.
    function _canSetRoyaltyInfo() internal view virtual override returns (bool) {
        return msg.sender == owner();
    }

    /// @dev Checks whether contract metadata can be set in the given execution context.
    function _canSetContractURI() internal view virtual override returns (bool) {
        return msg.sender == owner();
    }

    /// @dev Checks whether platform fee info can be set in the given execution context.
    function _canSetClaimConditions() internal view virtual override returns (bool) {
        return msg.sender == owner();
    }

    /// @dev Returns whether lazy minting can be done in the given execution context.
    function _canLazyMint() internal view virtual override returns (bool) {
        return msg.sender == owner();
    }

    /// @dev Checks whether NFTs can be revealed in the given execution context.
    function _canReveal() internal view virtual returns (bool) {
        return msg.sender == owner();
    }
}
