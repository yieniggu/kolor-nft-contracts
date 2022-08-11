let KolorLandNFT = artifacts.require("KolorLandNFT.sol");
let KolorMarketplace = artifacts.require("KolorMarketplace.sol");
let KolorLandToken = artifacts.require("KolorLandToken.sol");

module.exports = async function (deployer) {
  // Initial deploy
  await deployer.deploy(KolorLandNFT);
  await deployer.deploy(KolorMarketplace);

  //initial setup
  let KolorlandNFTInstance = await KolorLandNFT.deployed();
  await KolorlandNFTInstance.setMarketplace(KolorMarketplace.address);

  let marketplaceInstance = await KolorMarketplace.deployed();
  await marketplaceInstance.setNFTAddress(KolorLandNFT.address);
  await marketplaceInstance.authorize(KolorLandNFT.address);

  // deploy kolor land token
  await deployer.deploy(
    KolorLandToken,
    KolorlandNFTInstance.address,
    marketplaceInstance.address
  );
};
