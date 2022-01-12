let LandNFT = artifacts.require("LandNFT.sol");
let LockedNFT = artifacts.require("LockedNFT.sol");

module.exports = async function(deployer) {
  await deployer.deploy(LandNFT);
  
  
  await deployer.deploy(LockedNFT, LandNFT.address);

  let landNFTInstance = await LandNFT.deployed();

  await landNFTInstance.setMarketplace(LockedNFT.address);

};
