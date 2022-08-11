let LandNFT = artifacts.require("LandNFT.sol");
let LockedNFT = artifacts.require("LockedNFT.sol");

module.exports = async function (deployer) {
  // Initial deploy
  await deployer.deploy(LandNFT);
  //await deployer.deploy(LockedNFT);

  // initial setup
  //let landNFTInstance = await LandNFT.deployed();
  //await landNFTInstance.setMarketplace(LockedNFT.address);

  //let marketplaceInstance = await LockedNFT.deployed();
  //await marketplaceInstance.setNFTAddress(LandNFT.address);
};
