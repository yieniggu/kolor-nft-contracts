// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

enum State {
    Active,
    Paused,
    Inactive,
    MAvailable,
    MLocked,
    MUnavailable
}

interface ILandNFT {
    /**
        @dev Updates the availibility of tokenized land to be
        purchased in a marketplace
    
     */
    function updateLandState(uint256 tokenId, State state) external;

    function updateLandOwner(uint256 tokenId, address newLandOwner) external;

    function updateBuyer(uint256 tokenId, address newBuyer) external;

    function updateName(uint256 tokenId, string memory name) external;

    function updatePrice(uint256 tokenId, uint256 price) external;

    function landOwnerOf(uint256 tokenId)
        external
        view
        returns (address landOwner);

    function buyerOf(uint256 tokenId) external view returns (address buyer);

    function initialPriceOf(uint256 tokenId)
        external
        view
        returns (uint256 price);

    function currentPriceOf(uint256 tokenId)
        external
        view
        returns (uint256 price);

    function stateOf(uint256 tokenId) external view returns (State state);

    function safeTransferToMarketplace(address from, uint256 tokenId) external;
}
