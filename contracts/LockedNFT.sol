// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./LandNFT.sol";

contract LockedNFT is Ownable, ReentrancyGuard, IERC721Receiver {
    // Address of the nft contract
    address NFTAddress;

    // Standard timelock (5 years)
    uint256 public totalLockup = 1825 days;

    // Lockup
    uint256 public monthlyLockup = 30 days;

    // retirement pct
    uint256 public retirementPercentage = 1;

    // Mapping from token Id to the timestamp when it was staked
    // in this contract
    mapping(uint256 => uint256) private lockStartTime;

    // Mapping from address to the total staked/bought
    mapping(address => uint256) private totalStakedByAddress;
    mapping(address => uint256) private totalBoughtByAddress;

    // Mapping from buyer/landowner to list of buyed/staked token ids
    mapping(address => mapping(uint256 => uint256)) private boughtLands;
    mapping(address => mapping(uint256 => uint256)) private stakedLands;

    // Mapping from tokenId to buyer/landowner index
    mapping(uint256 => uint256) private boughtLandsIndex;
    mapping(uint256 => uint256) private stakedLandsIndex;

    // Arrays with all staked/buyed ids, used for enumeration
    uint256[] public _allStakedTokens;
    uint256[] public _allBoughtTokens;

    // Mappings from token id to all tokens posiiton
    mapping(uint256 => uint256) private allStakedIndex;
    mapping(uint256 => uint256) private allBoughtIndex;

    // mapping from token id to current celo balance locked
    mapping(uint256 => uint256) private stakedBalance;

    // mapping from token id to harvests made
    mapping(uint256 => uint256) private harvests;

    constructor(address _NFTAddress) {
        NFTAddress = _NFTAddress;
    }

    receive() external payable {}

    fallback() external payable {}

    /** 
        @dev Deposit a new land nft to the marketplace
    
     */
    function depositNFT(uint256 tokenId) public nonReentrant {
        ILandNFT ilandInterface = ILandNFT(NFTAddress);
        IERC721 erc721 = IERC721(NFTAddress);

        // Get the the land balance
        uint256 landBalance = erc721.balanceOf(msg.sender);
        require(landBalance > 0, "You're currently owning zero lands");
        require(
            erc721.ownerOf(tokenId) == msg.sender,
            "You're not the owner of this land!"
        );

        // Deposit the nft to the marketplace and mark it as available
        ilandInterface.safeTransferToMarketplace(msg.sender, tokenId);

        increaseStakedCount(msg.sender, tokenId);
    }

    /**
        @dev Withdraw a staked land nft from the marketplace

     */
    function withdrawNFT(uint256 tokenId) public nonReentrant {
        ILandNFT ilandInterface = ILandNFT(NFTAddress);
        IERC721 erc721 = IERC721(NFTAddress);

        require(
            totalStakedByAddress[msg.sender] > 0,
            "You have not any land in marketplace!"
        );
        require(
            ilandInterface.landOwnerOf(tokenId) == msg.sender,
            "You're not the land owner of this NFT Land!"
        );
        require(elapsedTime(tokenId) >= totalLockup, "NFT is still locked!");

        // Transfer back the nft to the land owner
        erc721.safeTransferFrom(address(this), msg.sender, tokenId);

        // update the land state to mavailable
        ilandInterface.updateLandState(tokenId, State.Active);

        // reset the lock start time of token
        delete lockStartTime[tokenId];

        // update the staked count
        decreaseStakedCount(msg.sender, tokenId);
    }

    /**
        @dev Allows a buyer to buy a new nft and lock the contract

     */
    function buyNFT(uint256 tokenId) external payable nonReentrant {
        ILandNFT ilandInterface = ILandNFT(NFTAddress);

        require(
            ilandInterface.stateOf(tokenId) == State.MAvailable,
            "This land NFT is not available!"
        );
        require(
            msg.value >= ilandInterface.initialPriceOf(tokenId),
            "The amount of CELO sent is not enough!"
        );

        require(
            msg.sender != ilandInterface.landOwnerOf(tokenId),
            "You can't buy your own land!"
        );

        // Receive the amount of CELO sent
        (bool sent, ) = address(this).call{value: msg.value}("");
        require(sent, "Failed to send CELO");

        // Update land status
        ilandInterface.updateLandState(tokenId, State.MLocked);

        // Set the initial lock to current timestamp
        lockStartTime[tokenId] = block.timestamp;

        /* Update the total land bought by the buyer 
            and add the new nft to its collection */
        increaseBoughtCount(msg.sender, tokenId);

        // Update the buyer
        ilandInterface.updateBuyer(tokenId, msg.sender);

        // set the staked balance
        stakedBalance[tokenId] = msg.value;

        // set the initial lockup info of this land
        harvests[tokenId] = 0;
    }

    function withdrawAllCeloStaked(uint256 tokenId) external {
        ILandNFT ilandInterface = ILandNFT(NFTAddress);
        IERC721 erc721 = IERC721(NFTAddress);

        require(
            erc721.ownerOf(tokenId) == address(this),
            "This land is not staked here!"
        );
        require(
            ilandInterface.buyerOf(tokenId) == msg.sender,
            "You havent bought this land!"
        );
        require(elapsedTime(tokenId) >= totalLockup, "NFT is still locked!");

        // set the state to market unavailable
        ilandInterface.updateLandState(tokenId, State.MUnavailable);

        // get the celo locked
        uint256 _stakedBalance = stakedBalance[tokenId];

        // decrease the current bought lands
        decreaseBoughtCount(msg.sender, tokenId);

        // Transfer the amount of celo Locked
        payable(msg.sender).transfer(_stakedBalance);

        // reset buyer to 0 address
        ilandInterface.updateBuyer(tokenId, address(0));

        // reset the staked balance of this land
        delete stakedBalance[tokenId];

        // reset the harvests info of this land
        delete harvests[tokenId];
    }

    function withdrawMonthlyCelo(uint256 tokenId) external {
        ILandNFT ilandInterface = ILandNFT(NFTAddress);

        require(
            ilandInterface.buyerOf(tokenId) == msg.sender,
            "You havent bought this land!"
        );

        // get the harvests to make
        uint256 _harvestsToMake = harvestsToMake(tokenId);

        require(
            _harvestsToMake >= 1,
            "You should wait until next harvest period!"
        );

        // Calculate the  amount to retire
        uint256 harvestAmount = getHarvestAmount(tokenId);

        // Update the number of harvests made
        harvests[tokenId]++;

        // Send the tokens to buyer
        payable(msg.sender).transfer(harvestAmount);

        // Update the staked balance of the land
        stakedBalance[tokenId] -= harvestAmount;
    }

    function getHarvestAmount(uint256 tokenId) public view returns (uint256) {
        ILandNFT ilandInterface = ILandNFT(NFTAddress);

        uint256 currentPriceOf = ilandInterface.currentPriceOf(tokenId);

        uint256 _harvestsToMake = harvestsToMake(tokenId);

        // Amount to retrieve will be the 1% times the harvests available
        // of the land's staked balance
        uint256 harvestAmount = (currentPriceOf *
            _harvestsToMake *
            retirementPercentage) / 100;

        return harvestAmount;
    }

    function currentHarvestsOf(uint256 tokenId) public view returns (uint256) {
        return harvests[tokenId];
    }

    function harvestsToMake(uint256 tokenId) public view returns (uint256) {
        // Get elapsed months from initial start time
        uint256 _elapsedMonths = elapsedMonths(tokenId);

        if (_elapsedMonths == 0){
            return 0;
        }

        // Get amount of harvests done
        uint256 currentHarvests = currentHarvestsOf(tokenId);

        // Calculate harvests that can be made this month
        return 60 / (_elapsedMonths - currentHarvests);
    }

    function getNextHarvestPeriod(uint256 tokenId)
        public
        view
        returns (uint256)
    {
        // get the harvests to make
        uint256 _harvestsToMake = harvestsToMake(tokenId);

        return lockStartTime[tokenId] + (monthlyLockup * _harvestsToMake);
    }

    /**
        @dev Returns the amount of CELO in this contract
     */
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function totalStaked() public view returns (uint256) {
        return _allStakedTokens.length;
    }

    function totalStakedBy(address landOwner) public view returns (uint256) {
        return totalStakedByAddress[landOwner];
    }

    function totalBought() public view returns (uint256) {
        return _allBoughtTokens.length;
    }

    function totalBoughtBy(address buyer) public view returns (uint256) {
        return totalBoughtByAddress[buyer];
    }

    function timelocked() public view returns (uint256) {
        return totalLockup;
    }

    /**
        @dev Disable the timelock for debugging purposes
     */
    function disableTimelock() public onlyOwner {
        totalLockup = 0;
    }

    /**
        @dev Enables the default timelock of 5 years
     */
    function enableTimelock() public onlyOwner {
        totalLockup = 1825 days;
    }

    /**
        @dev Gets the elapsed time since the nft got staked and
            the current block timestamp
     */
    function elapsedTime(uint256 tokenId) public view returns (uint256) {
        uint256 _elapsedTime = block.timestamp - lockStartTime[tokenId];

        return _elapsedTime;
    }

    function elapsedMonths(uint256 tokenId) public view returns (uint256) {
        return elapsedTime(tokenId) / monthlyLockup;
    }

    function lockStart(uint256 tokenId) public view returns (uint256) {
        return lockStartTime[tokenId];
    }

    function increaseStakedCount(address landOwner, uint256 tokenId) private {
        // Sum a new nft to the total staked by this address
        totalStakedByAddress[landOwner] = totalStakedByAddress[landOwner] + 1;

        // Get the total staked by address
        uint256 _totalStakedByThisAddress = totalStakedByAddress[landOwner];

        // Update the reference of the nfts staked by this address
        stakedLands[landOwner][_totalStakedByThisAddress] = tokenId;

        // Assign the index of a token Id to the owners index
        stakedLandsIndex[tokenId] = _totalStakedByThisAddress;

        // Update the all bought info
        allStakedIndex[tokenId] = _allStakedTokens.length;
        _allStakedTokens.push(tokenId);
    }

    function decreaseStakedCount(address landOwner, uint256 tokenId) private {
        // Get the total staked by address and the token index
        uint256 lastLandIndex = totalStakedByAddress[landOwner] - 1;
        uint256 landIndex = stakedLandsIndex[tokenId];

        // When the Land to delete is the last Land
        // the swap operation is unnecesary
        if (landIndex != lastLandIndex) {
            uint256 lastLandId = stakedLands[landOwner][lastLandIndex];

            stakedLands[landOwner][landIndex] = lastLandId; // Move the last Land to the slot of the to-delete Land
            stakedLandsIndex[lastLandId] = landIndex; // Update the moved Land's index
        }

        // This also deletes the contents at the last position of the array
        delete stakedLandsIndex[tokenId];
        delete stakedLands[landOwner][lastLandIndex];

        // Decrease a nft of the total Staked by this address
        totalStakedByAddress[landOwner]--;

        // remove from global info
        removeLandFromAllStakedEnumeration(tokenId);
    }

    function increaseBoughtCount(address buyer, uint256 tokenId) private {
        // Sum a new nft to the total Bought by this address
        totalBoughtByAddress[buyer] = totalBoughtByAddress[buyer] + 1;

        // Get the total Bought by address
        uint256 _totalBoughtByThisAddress = totalBoughtByAddress[buyer];

        // Update the reference of the nfts Bought by this address
        boughtLands[buyer][_totalBoughtByThisAddress] = tokenId;

        // Assign the index of a token Id to the owners index
        boughtLandsIndex[tokenId] = _totalBoughtByThisAddress;

        // Update the all bought info
        allBoughtIndex[tokenId] = _allBoughtTokens.length;
        _allBoughtTokens.push(tokenId);
    }

    function decreaseBoughtCount(address buyer, uint256 tokenId) private {
        // Get the total Bought by address and the token index
        uint256 lastLandIndex = totalBoughtByAddress[buyer] - 1;
        uint256 landIndex = boughtLandsIndex[tokenId];

        // When the Land to delete is the last Land
        // the swap operation is unnecesary
        if (landIndex != lastLandIndex) {
            uint256 lastLandId = boughtLands[buyer][lastLandIndex];

            boughtLands[buyer][landIndex] = lastLandId; // Move the last Land to the slot of the to-delete Land
            boughtLandsIndex[lastLandId] = landIndex; // Update the moved Land's index
        }

        // This also deletes the contents at the last position of the array
        delete boughtLandsIndex[tokenId];
        delete boughtLands[buyer][lastLandIndex];

        // Decrease a nft of the total Bought by this address
        totalBoughtByAddress[buyer]--;

        // Remove from the all tokens info
        removeLandFromAllBoughtEnumeration(tokenId);
    }

    function removeLandFromAllStakedEnumeration(uint256 tokenId) private {
        // To prevent a gap in the tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).
        uint256 lastTokenIndex = _allStakedTokens.length - 1;
        uint256 tokenIndex = allStakedIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary. However, since this occurs so
        // rarely (when the last minted token is burnt) that we still do the swap here to avoid the gas cost of adding
        // an 'if' statement (like in _removeTokenFromOwnerEnumeration)
        uint256 lastTokenId = allStakedIndex[lastTokenIndex];

        _allStakedTokens[tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
        allStakedIndex[lastTokenId] = tokenIndex; // Update the moved token's index

        // This also deletes the contents at the last position of the array
        delete allStakedIndex[tokenId];
        _allStakedTokens.pop();
    }

    function removeLandFromAllBoughtEnumeration(uint256 tokenId) private {
        // To prevent a gap in the tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).
        uint256 lastTokenIndex = _allBoughtTokens.length - 1;
        uint256 tokenIndex = allBoughtIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary. However, since this occurs so
        // rarely (when the last minted token is burnt) that we still do the swap here to avoid the gas cost of adding
        // an 'if' statement (like in _removeTokenFromOwnerEnumeration)
        uint256 lastTokenId = allBoughtIndex[lastTokenIndex];

        _allBoughtTokens[tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
        allBoughtIndex[lastTokenId] = tokenIndex; // Update the moved token's index

        // This also deletes the contents at the last position of the array
        delete allBoughtIndex[tokenId];
        _allBoughtTokens.pop();
    }

    /**
        @dev Returns a buyed land of an address given an index
     */
    function landOfBuyerByIndex(address buyer, uint256 index)
        public
        view
        returns (uint256)
    {
        require(
            index < totalBoughtByAddress[buyer],
            "Buyer index out of bounds"
        );

        return boughtLands[buyer][index];
    }

    /**
        @dev returns the index position of a NFT in a buyers collection
     */

    function indexOfBoughtLand(uint256 tokenId) public view returns (uint256) {
        require(_allStakedTokens.length > 0, "There is nothing staked");
        require(_allBoughtTokens.length > 0, "There is no land bought yet");

        return boughtLandsIndex[tokenId];
    }

    function allStakedTokens() public view returns (uint256[] memory) {
        return _allStakedTokens;
    }

    function allBoughtTokens() public view returns (uint256[] memory) {
        return _allBoughtTokens;
    }

    function getMontlyLockup() public view returns (uint256) {
        return monthlyLockup;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
