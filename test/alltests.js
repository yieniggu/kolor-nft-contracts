const LandContract = artifacts.require("LandNFT");
const IlandContract = artifacts.require("ILandNFT");
//const LockedNFT = artifacts.require("LockedNFT");

const { assert } = require("chai");
const chai = require("chai");
const BN = web3.utils.BN;

const chaiBN = require("chai-bn")(BN);
chai.use(chaiBN);

const chaiAsPromised = require("chai-as-promised");
const { contracts_build_directory } = require("../truffle-config");
chai.use(chaiAsPromised);

const expect = chai.expect;

contract("NFT test", async (accounts) => {
  // Lets use 3 accounts to test functionalitites
  const [contractOwner, landOwner, buyer] = accounts;
  const newNFT = {
    name: "Wonderland",
    identifier: "land1",
    landOwner: landOwner,
    landOwnerAlias: "Netflix",
    decimals: new BN(4),
    size: new BN(10000),
    country: "Chile",
    stateOrRegion: "X Los lagos",
    city: "Tucapel",
    initialTCO2: new BN(1000),
  };

  it("should mint a new NFT and send it to the landOwner", async () => {
    // await for NFT contract deployment
    let landContract = await LandContract.deployed();

    // Lets mint a new NFT to 2nd account
    await landContract.safeMint(
      landOwner,
      newNFT.name,
      newNFT.identifier,
      newNFT.landOwner,
      newNFT.landOwnerAlias,
      newNFT.decimals,
      newNFT.size,
      newNFT.country,
      newNFT.stateOrRegion,
      newNFT.city,
      newNFT.initialTCO2
    );

    // Lets test first the total supply of NFTs
    expect(landContract.totalSupply()).to.eventually.be.a.bignumber.equal(
      new BN(1)
    );

    // Now lets test that the landOwner has a new minted NFT
    expect(
      landContract.balanceOf(landOwner)
    ).to.eventually.be.a.bignumber.equal(new BN(1));

    // Now lets test that the tokenId of the owner is 0
    expect(
      landContract.tokenOfOwnerByIndex(landOwner, new BN(0))
    ).to.eventually.be.a.bignumber.equal(new BN(0));
  });

  it("should set the proper attributes to a minted NFT", async () => {
    // await for NFT contract deployment
    let landContract = await LandContract.deployed();

    // lets test that the previous minted NFT has the right attributes
    let mintedNFTInfo = await landContract.getNFTInfo(new BN(0));

    // Lets extract the results
    let result = {
      name: mintedNFTInfo.name,
      identifier: mintedNFTInfo.identifier,
      landOwner: mintedNFTInfo.landOwner,
      landOwnerAlias: mintedNFTInfo.landOwnerAlias,
      decimals: new BN(mintedNFTInfo.decimals),
      size: new BN(mintedNFTInfo.size),
      country: mintedNFTInfo.city,
      stateOrRegion: mintedNFTInfo.stateOrRegion,
      city: mintedNFTInfo.city,
      state: mintedNFTInfo.state,
      initialTCO2: new BN(mintedNFTInfo.initialTCO2),
      currentTCO2: new BN(mintedNFTInfo.currentTCO2),
      soldTCO2: new BN(mintedNFTInfo.soldTCO2),
      creationDate: mintedNFTInfo.creationDate,
    };

    // Define expected result
    let expectedResult = {
      name: newNFT.name,
      identifier: newNFT.identifier,
      landOwner: newNFT.landOwner,
      landOwnerAlias: newNFT.landOwnerAlias,
      decimals: newNFT.decimals,
      size: newNFT.size,
      country: newNFT.city,
      stateOrRegion: newNFT.stateOrRegion,
      city: newNFT.city,
      state: newNFT.state,
      initialTCO2: newNFT.initialTCO2,
      currentTCO2: mintedNFTInfo.currentTCO2,
      soldTCO2: mintedNFTInfo.soldTCO2,
      creationDate: mintedNFTInfo.creationDate,
      state: 1
    };

    expect(result).to.deep.equal(expectedResult);
  });
});
//   it("should define marketplace address correctly", async () => {
//     // await for NFT contract deployment
//     let landContract = await LandContract.deployed();

//     // await for marketplace contract deployment
//     let lockContract = await LockedNFT.deployed();

//     // set marketplace address to the lock contract
//     await landContract.setMarketplace(lockContract.address);

//     // check if address is correct
//     expect(landContract.marketplace()).to.eventually.be.equal(
//       lockContract.address
//     );
//   });

//   it("should send a minted NFT to marketplace", async () => {
//     // await for NFT contract deployment
//     let landContract = await LandContract.deployed();

//     // await for marketplace contract deployment
//     let lockContract = await LockedNFT.deployed();

//     // set marketplace address to the lock contract
//     await landContract.setMarketplace(lockContract.address);

//     // let token owner approve marketplace
//     await landContract.setApprovalForAll(lockContract.address, true, {
//       from: landOwner,
//     });

//     // account 2 deposit a new NFT to the marketplace
//     await lockContract.depositNFT(new BN(0), { from: landOwner });

//     // check that state of the NFT changed to MAvailable
//     let NFTInfo = await landContract.getNFTInfo(new BN(0));
//     expect(NFTInfo.state).to.be.equal("3"); // state MAvailable = 3

//     // check that owner of NFT is the marketplace
//     expect(landContract.ownerOf(0)).to.eventually.be.equal(
//       lockContract.address
//     );

//     // staked nft amount of landowner shouldve increased
//     expect(
//       lockContract.totalStakedBy(landOwner)
//     ).to.eventually.be.a.bignumber.equal(new BN(1));

//     // total staked amount should increase too
//     expect(lockContract.totalStaked()).to.eventually.be.a.bignumber.equal(
//       new BN(1)
//     );
//   });

//   it("should buy a listed nft", async () => {
//     // await for NFT contract deployment
//     let landContract = await LandContract.deployed();

//     // await for marketplace contract deployment
//     let lockContract = await LockedNFT.deployed();

//     // lets send some funds to 3rd account (buyer)
//     await web3.eth.sendTransaction({
//       to: accounts[2],
//       from: accounts[4],
//       value: web3.utils.toWei("10"),
//     });
//     await web3.eth.sendTransaction({
//       to: accounts[2],
//       from: accounts[5],
//       value: web3.utils.toWei("10"),
//     });

//     // buyer account buys the listed NFT
//     await lockContract.buyNFT(0, { from: buyer, value: newNFT.price });

//     // state info of nft should change to MLocked
//     let NFTInfo = await landContract.getNFTInfo(new BN(0));
//     expect(NFTInfo.state).to.be.equal("5");

//     // Also buyer address should change
//     expect(NFTInfo.currentBuyer).to.be.equal(buyer);

//     // total lands bought by buyer should increase
//     expect(
//       lockContract.landOfBuyerByIndex(buyer, 0)
//     ).to.eventually.be.a.bignumber.equal(new BN(0));

//     // index of newly nft buyed should be in index 0 of buyers collection
//     expect(
//       lockContract.indexOfBoughtLand(0)
//     ).to.eventually.be.a.bignumber.equal(new BN(1));

//     // balance of contract should be 5 celo
//     expect(lockContract.getBalance()).to.eventually.be.a.bignumber.equal(
//       newNFT.price
//     );
//   });

//   it("should not allow a withdraw if its timelocked", async () => {
//     // await for marketplace contract deployment
//     let lockContract = await LockedNFT.deployed();

//     // test the withdraw function
//     expect(lockContract.withdrawNFT(new BN(0), { from: landOwner })).to
//       .eventually.be.rejected;
//   });

//   it("should allow a withdraw if timelock is disabled", async () => {
//     // await for NFT contract deployment
//     let landContract = await LandContract.deployed();

//     // await for marketplace contract deployment
//     let lockContract = await LockedNFT.deployed();

//     // lets disable timelock
//     await lockContract.disableTimelock();

//     // lets try nft withdraw
//     expect(lockContract.withdrawNFT(new BN(0), { from: landOwner })).to
//       .eventually.be.fulfilled;

//     // owner of token should be landowner
//     expect(landContract.ownerOf(new BN(0))).to.eventually.be.equal(landOwner);
//   });
// });

// contract("Token test", async (accounts) => {
//     const [deployerAccount, recipient, anotherAccount] = accounts;

//     // Returns an async function /*
//     it("the totally minted supply should be in the first account", async ()=>{
//         //define test cases

//         // await for token deployment and get the instance
//         let instance = await Token.deployed();

//         // get total supply
//         let totalSupply = await instance.totalSupply();

//         // expects from chai: something equals to other
//         expect(instance.balanceOf(accounts[0])).to.eventually.be.a.bignumber.equal(totalSupply);
//     });

//     it ("is possible to send tokens between accounts", async() => {
//         const sendTokens = 1;

//         let instance = await Token.deployed();
//         let totalSupply = await instance.totalSupply();

//         expect(instance.balanceOf(deployerAccount)).to.eventually.be.a.bignumber.equal(totalSupply);
//         expect(instance.transfer(recipient, sendTokens)).to.eventually.be.fulfilled;
//         expect(instance.balanceOf(deployerAccount)).to.eventually.be.a.bignumber.equal(totalSupply-sendTokens);
//         expect(instance.balanceOf(recipient)).to.eventually.be.a.bignumber.equal(new BN(sendTokens));

//     });

//     it("is not possible to send more tokens that available in total", async() =>{

//         let instance = await Token.deployed();
//         let deployerBalance = await instance.balanceOf(deployerAccount);

//         expect(instance.transfer(recipient, new BN(deployerBalance + 1))).to.eventually.be.rejected;

//         expect(instance.balanceOf(deployerAccount)).to.eventually.be.a.bignumber.equal(deployerBalance);

//     });
// })
