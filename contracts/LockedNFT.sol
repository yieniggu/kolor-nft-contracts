// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./LandNFT.sol";
import "./IKolorInterface.sol";

struct OffsetEmissions {
    uint256 vcuOffset;
    uint256 timestamp;
    uint256 retirementPercentage;
    uint256 tokenId;
    uint256 harvests;
    uint256 rewardsLeft;
}

contract LockedNFT is Ownable, ReentrancyGuard, IERC721Receiver {
    // Address of the nft contract and kolor
    address public NFTAddress;
    address public KolorAddress;

    // Standard timelock (5 years)
    uint256 public totalLockup = 1825 days;

    // Lockup
    uint256 public monthlyLockup = 30 days;

    // retirement pct
    uint256 public retirementPercentage = 1;

    uint256 public vcuPriceInCUSD = 5 ether;
    uint256 public vcuPriceInCELO = 1 ether;

    // Mapping from token Id to the timestamp when it was staked
    // in this contract
    mapping(uint256 => uint256) private lockStartTime;

    // mapping from buyer to its offsets
    mapping(address => mapping(uint256 => OffsetEmissions))
        public offsetsByAddress;
    mapping(address => uint256) public totalOffsetsOf;

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

    constructor() {}

    receive() external payable {}

    fallback() external payable {}

    function setNFTAddress(address _NFTAddress) public onlyOwner {
        NFTAddress = _NFTAddress;
    }

    function setKolorAddress(address _KolorAddress) public onlyOwner {
        KolorAddress = _KolorAddress;
    }

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
        @dev Allows a buyer to compensate vcu tokens, and
        mint kolor tokens as reward. This tokens remains locked
        for a certain amount of time.

     */
    function offsetEmissions(uint256 tokenId, uint256 emissions)
        external
        payable
        nonReentrant
    {
        ILandNFT ilandInterface = ILandNFT(NFTAddress);

        require(
            ilandInterface.stateOf(tokenId) == State.MAvailable,
            "This land NFT is not available!"
        );
        require(
            msg.value >= vcuPriceInCUSD,
            "The amount of CELO sent is not enough!"
        );

        require(
            ilandInterface.getVCUS(tokenId) >= emissions,
            "This land hasn't that much TCO2 to offset"
        );

        // Receive the amount of CELO sent
        (bool sent, ) = address(this).call{value: msg.value}("");
        require(sent, "Failed to send CELO");

        // Update the buyer
        ilandInterface.addBuyer(tokenId, msg.sender);

        // Create new information about this offset
        addOffsetEmissions(tokenId, emissions, msg.sender);

        // TODO: Add minting kolor token
        IKolorInterface iKolorInterface = IKolorInterface(KolorAddress);
        iKolorInterface.mint(address(this), emissions);
    }

    /** @dev Adds a new offset structure to a buyer to represent
        its newly offset
    */
    function addOffsetEmissions(
        uint256 tokenId,
        uint256 emissions,
        address buyer
    ) internal {
        // get the current offset emissions of this address
        totalOffsetsOf[buyer]++;
        uint256 currentOffsetsOf = totalOffsetsOf[buyer];

        // add offset
        offsetsByAddress[buyer][currentOffsetsOf].vcuOffset = emissions;
        offsetsByAddress[buyer][currentOffsetsOf].timestamp = block.timestamp;
        offsetsByAddress[buyer][currentOffsetsOf]
            .retirementPercentage = retirementPercentage;
        offsetsByAddress[buyer][currentOffsetsOf].tokenId = tokenId;
        offsetsByAddress[buyer][currentOffsetsOf].harvests = 0;
        offsetsByAddress[buyer][currentOffsetsOf].rewardsLeft = emissions;
    }

    /** @dev Allows a buyer to withdraw a certain amount of one of its
        offsets
     */
    function buyerWithdraw(uint256 offsetId, uint256 amount)
        public
        nonReentrant
    {
        require(
            totalOffsetsOf[msg.sender] > 0,
            "Withdraw: You have nothing to withdraw"
        );

        uint256 rewardsLeft = offsetsByAddress[msg.sender][offsetId]
            .rewardsLeft;
        require(amount <= rewardsLeft, "Withdraw: max amount exceeded");

        // get the retirements available to make since last retirement
        uint256 amountAvailable = amountToHarvest(offsetId, msg.sender);

        require(amount <= amountAvailable, "Withdraw: max amount exceeded");

        uint256 _harvestsToMake = harvestsToMake(offsetId, msg.sender);

        // update the harvest control variables
        offsetsByAddress[msg.sender][offsetId].harvests += _harvestsToMake;
        offsetsByAddress[msg.sender][offsetId].rewardsLeft -= amountAvailable;
    }

    function amountToHarvest(uint256 offsetId, address buyer)
        public
        view
        returns (uint256)
    {
        // get the monthly harvests to make this period
        uint256 _harvestsToMake = harvestsToMake(offsetId, buyer);

        uint256 totalRewards = vcuOffsetOf(offsetId, buyer);
        uint256 retirementPct = retirementPercentageOf(offsetId, buyer);

        uint256 amount = (totalRewards * _harvestsToMake * retirementPct) / 100;

        return amount;
    }

    function currentHarvestsOf(uint256 offsetId, address buyer)
        public
        view
        returns (uint256)
    {
        return offsetsByAddress[buyer][offsetId].harvests;
    }

    function harvestsToMake(uint256 offsetId, address buyer)
        public
        view
        returns (uint256)
    {
        uint256 timestamp = timestampOf(offsetId, buyer);
        // Get elapsed months from initial start time
        uint256 _elapsedMonths = elapsedMonths(timestamp);

        if (_elapsedMonths < 1) {
            return 0;
        }

        // Get amount of harvests done
        uint256 currentHarvests = currentHarvestsOf(offsetId, buyer);

        // Calculate harvests that can be made this month
        return _elapsedMonths - currentHarvests;
    }

    function vcuOffsetOf(uint256 offsetId, address buyer)
        public
        view
        returns (uint256)
    {
        return offsetsByAddress[buyer][offsetId].vcuOffset;
    }

    function retirementPercentageOf(uint256 offsetId, address buyer)
        public
        view
        returns (uint256)
    {
        return offsetsByAddress[buyer][offsetId].vcuOffset;
    }

    function timestampOf(uint256 offsetId, address buyer)
        public
        view
        returns (uint256)
    {
        return offsetsByAddress[buyer][offsetId].timestamp;
    }

    function getNextHarvestPeriod(uint256 offsetId, address buyer)
        public
        view
        returns (uint256)
    {
        // get the harvests to make
        uint256 _harvestsToMake = harvestsToMake(offsetId, buyer);

        return timestampOf(offsetId, buyer) + (monthlyLockup * _harvestsToMake);
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
    function elapsedTime(uint256 timestamp) public view returns (uint256) {
        return timestamp - block.timestamp;
    }

    function elapsedMonths(uint256 timestamp) public view returns (uint256) {
        return elapsedTime(timestamp) / monthlyLockup;
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
