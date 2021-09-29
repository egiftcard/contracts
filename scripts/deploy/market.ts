import hre, { run, ethers } from "hardhat";
import { Contract, ContractFactory } from "ethers";

import addresses from "../../utils/addresses/accesspacks.json";
import { txOptions } from "../../utils/txOptions";

import * as fs from "fs";
import * as path from "path";

async function main() {
  await run("compile");

  console.log("\n");

  // Get signer
  const [deployer] = await ethers.getSigners();
  const networkName: string = hre.network.name.toLowerCase();

  // Get chain specific values
  const curentNetworkAddreses = addresses[networkName as keyof typeof addresses];
  const { protocolControl: protocolControlAddress, forwarder: forwarderAddr } = curentNetworkAddreses;
  const txOption = txOptions[networkName as keyof typeof txOptions];

  console.log(`Deploying contracts with account: ${await deployer.getAddress()} to ${networkName}`);

  // Deploy `Market`
  const contractURI: string = "";

  const Market_Factory: ContractFactory = await ethers.getContractFactory("Market");
  const market: Contract = await Market_Factory.connect(deployer).deploy(
    protocolControlAddress,
    forwarderAddr,
    contractURI,
    txOption,
  );

  console.log(`Deploying Market: ${market.address} at tx hash: ${market.deployTransaction.hash}`);

  await market.deployed();

  // Update contract addresses in `/utils`
  const updatedAddresses = {
    ...addresses,

    [networkName]: {
      ...curentNetworkAddreses,

      market: market.address,
    },
  };

  fs.writeFileSync(path.join(__dirname, "../../utils/addresses/accesspacks.json"), JSON.stringify(updatedAddresses));
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
