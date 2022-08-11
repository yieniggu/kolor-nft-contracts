const Web3 = require("web3");
const ContractKit = require("@celo/contractkit");
const web3 = new Web3("https://alfajores-forno.celo-testnet.org");
const kit = ContractKit.newKitFromWeb3(web3);
const getAccount = require("./getAccount").getAccount;

async function awaitWrapper() {
  let account = await getAccount();
  kit.connection.addAccount(account.privateKey);
}
awaitWrapper();

const path = require("path");

module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // to customize your Truffle configuration!
  //contracts_build_directory: path.join(__dirname, "build/contracts_abis"),
  networks: {
    develop: {
      port: 8545,
    },
    alfajores: {
      provider: kit.connection.web3.currentProvider, // CeloProvider
      network_id: 44787, // Alfajores network id
    },
  },
  compilers: {
    solc: {
      version: "0.8.0",
      settings: {
        optimizer: {
          enabled: true,
          runs: 50,
        },
      },
    },
  },
};
