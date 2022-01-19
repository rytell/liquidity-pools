import { ChainId, Token } from "@rytell/sdk";
import { ethers } from "hardhat";

const WAVAX = {
  [ChainId.FUJI]: new Token(
    ChainId.FUJI,
    "0xd00ae08403B9bbb9124bB305C09058E32C39A48c",
    18,
    "WAVAX",
    "Wrapped AVAX"
  ),
  [ChainId.AVALANCHE]: new Token(
    ChainId.AVALANCHE,
    "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7",
    18,
    "WAVAX",
    "Wrapped AVAX"
  ),
};

const RADI = {
  [ChainId.FUJI]: new Token(
    ChainId.FUJI,
    "0xCcA36c23E977d6c2382dF43e930BC8dE9daC897E",
    18,
    "RADI",
    "RADI"
  ),
  [ChainId.AVALANCHE]: new Token(
    ChainId.AVALANCHE,
    "0x0000000000000000000000000000000000000000",
    18,
    "RADI",
    "RADI"
  ),
};

const STABLE_TOKEN = {
  [ChainId.FUJI]: new Token(
    ChainId.FUJI,
    "0x2058ec2791dD28b6f67DB836ddf87534F4Bbdf22",
    6,
    "FUJISTABLE",
    "The Fuji stablecoin"
  ),
  [ChainId.AVALANCHE]: new Token(
    ChainId.AVALANCHE,
    "0x0000000000000000000000000000000000000000",
    18,
    "USDT",
    "USDT"
  ),
};

const TREASURY_VESTER = {
  [ChainId.FUJI]: "0xe5e970FE3a90F314977a9Fd41e349486a9e8c4fe",
  [ChainId.AVALANCHE]: "0x0000000000000000000000000000000000000000",
};

async function main() {
  // We get the contract to deploy
  const LiquidityPoolManager = await ethers.getContractFactory(
    "LiquidityPoolManager"
  );
  const liquidityPoolManager = await LiquidityPoolManager.deploy(
    WAVAX[ChainId.FUJI].address,
    RADI[ChainId.FUJI].address,
    STABLE_TOKEN[ChainId.FUJI].address,
    TREASURY_VESTER[ChainId.FUJI]
  );

  await liquidityPoolManager.deployed();

  console.log(
    "LiquidityPoolManager deployed to:",
    liquidityPoolManager.address
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
