import { ChainId, Token } from "@rytell/sdk";
import { ethers } from "hardhat";

async function main() {
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

  // We get the contract to deploy
  const TreasuryVester = await ethers.getContractFactory("TreasuryVester");
  const treasuryVester = await TreasuryVester.deploy(
    RADI[ChainId.FUJI].address
  );

  await treasuryVester.deployed();

  console.log("TreasuryVester deployed to:", treasuryVester.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});