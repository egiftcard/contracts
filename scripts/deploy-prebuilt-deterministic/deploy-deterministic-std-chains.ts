import "dotenv/config";
import {
  ThirdwebSDK,
  computeCloneFactoryAddress,
  deployContractDeterministic,
  deployCreate2Factory,
  deployWithThrowawayDeployer,
  getCreate2FactoryAddress,
  getDeploymentInfo,
  getThirdwebContractAddress,
  isContractDeployed,
  resolveAddress,
} from "@thirdweb-dev/sdk";
import { Signer } from "ethers";
import { apiMap, chainIdApiKey, chainIdToName } from "./constants";

////// To run this script: `npx ts-node scripts/deploy-prebuilt-deterministic/deploy-deterministic-std-chains.ts` //////
///// MAKE SURE TO PUT IN THE RIGHT CONTRACT NAME HERE AFTER PUBLISHING IT /////
//// THE CONTRACT SHOULD BE PUBLISHED WITH THE NEW PUBLISH FLOW ////
const publishedContractName = "Split";
const publisherKey: string = process.env.THIRDWEB_PUBLISHER_PRIVATE_KEY as string;
const deployerKey: string = process.env.PRIVATE_KEY as string;

const polygonSDK = ThirdwebSDK.fromPrivateKey(publisherKey, "polygon");

async function main() {
  const publisher = await polygonSDK.wallet.getAddress();
  const latest = await polygonSDK.getPublisher().getLatest(publisher, publishedContractName);

  if (latest && latest.metadataUri) {
    for (const [chainId, networkName] of Object.entries(chainIdToName)) {
      console.log(`Deploying ${publishedContractName} on ${networkName}`);
      const sdk = ThirdwebSDK.fromPrivateKey(deployerKey, chainId); // can also hardcode the chain here
      const signer = sdk.getSigner() as Signer;
      // const chainId = (await sdk.getProvider().getNetwork()).chainId;

      try {
        const implAddr = await getThirdwebContractAddress(publishedContractName, parseInt(chainId), sdk.storage);
        if (implAddr) {
          console.log(`implementation ${implAddr} already deployed on chainId: ${chainId}`);
          console.log();
          continue;
        }
      } catch (error) {}

      try {
        console.log("Deploying as", await signer?.getAddress());
        // any evm deployment flow

        // Deploy CREATE2 factory (if not already exists)
        const create2FactoryAddress = await getCreate2FactoryAddress(sdk.getProvider());
        if (await isContractDeployed(create2FactoryAddress, sdk.getProvider())) {
          console.log(`-- Create2 factory already present at ${create2FactoryAddress}`);
        } else {
          console.log(`-- Deploying Create2 factory at ${create2FactoryAddress}`);
          await deployCreate2Factory(signer, {});
        }

        // TWStatelessFactory (Clone factory)
        const cloneFactoryAddress = await computeCloneFactoryAddress(
          sdk.getProvider(),
          sdk.storage,
          create2FactoryAddress,
        );
        if (await isContractDeployed(cloneFactoryAddress, sdk.getProvider())) {
          console.log(`-- TWCloneFactory already present at ${cloneFactoryAddress}`);
        }

        // get deployment info for any evm
        const deploymentInfo = await getDeploymentInfo(
          latest.metadataUri,
          sdk.storage,
          sdk.getProvider(),
          create2FactoryAddress,
        );

        const implementationAddress = deploymentInfo.find(i => i.type === "implementation")?.transaction
          .predictedAddress as string;

        // filter out already deployed contracts (data is empty)
        const transactionsToSend = deploymentInfo.filter(i => i.transaction.data && i.transaction.data.length > 0);
        const transactionsforDirectDeploy = transactionsToSend
          .filter(i => {
            return i.type !== "infra";
          })
          .map(i => i.transaction);
        const transactionsForThrowawayDeployer = transactionsToSend
          .filter(i => {
            return i.type === "infra";
          })
          .map(i => i.transaction);

        // deploy via throwaway deployer, multiple infra contracts in one transaction
        if (transactionsForThrowawayDeployer.length > 0) {
          console.log("-- Deploying Infra");
          await deployWithThrowawayDeployer(signer, transactionsForThrowawayDeployer, {});
        }

        const resolvedImplementationAddress = await resolveAddress(implementationAddress);

        console.log(`-- Deploying ${publishedContractName} at ${resolvedImplementationAddress}`);
        // send each transaction directly to Create2 factory
        await Promise.all(
          transactionsforDirectDeploy.map(tx => {
            return deployContractDeterministic(signer, tx, {});
          }),
        );
      } catch (e) {
        console.log("Error while deploying: ", e);
        console.log();
        continue;
      }
    }

    console.log("Deployments done.");
    console.log();
    console.log("---------- Verification ---------");
    console.log();
    for (const [chainId, networkName] of Object.entries(chainIdToName)) {
      const sdk = new ThirdwebSDK(chainId);
      console.log("Network: ", networkName);
      try {
        await sdk.verifier.verifyThirdwebContract(
          publishedContractName,
          apiMap[parseInt(chainId)],
          chainIdApiKey[parseInt(chainId)] as string,
        );
        console.log();
      } catch (error) {
        console.log(error);
        console.log();
      }
    }
  } else {
    console.log("No previous release found");
    return;
  }

  console.log("All done.");
}

main()
  .then(() => process.exit(0))
  .catch(e => {
    console.error(e);
    process.exit(1);
  });
