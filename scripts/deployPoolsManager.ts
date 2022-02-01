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
    "0x600615234c0a427834A4344D10fEaCA374B2dfCB",
    18,
    "RADI",
    "RADI"
  ),
  [ChainId.AVALANCHE]: new Token(
    ChainId.AVALANCHE,
    "0x9c5bBb5169B66773167d86818b3e149A4c7e1d1A",
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
    "0xc7198437980c041c805A1EDcbA50c1Ce5db95118",
    18,
    "USDT",
    "USDT"
  ),
};

const TREASURY_VESTER = {
  [ChainId.FUJI]: "0xe3f486d0401fC946aEB95539fACedf0016A342BB",
  [ChainId.AVALANCHE]: "0x5720c005127AbB4Cad729B255C652BeD316cEd7e",
};

async function main() {
  // We get the contract to deploy
  const LiquidityPoolManager = await ethers.getContractFactory(
    "LiquidityPoolManager"
  );
  const liquidityPoolManager = await LiquidityPoolManager.deploy(
    WAVAX[ChainId.AVALANCHE].address,
    RADI[ChainId.AVALANCHE].address,
    STABLE_TOKEN[ChainId.AVALANCHE].address,
    TREASURY_VESTER[ChainId.AVALANCHE]
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
