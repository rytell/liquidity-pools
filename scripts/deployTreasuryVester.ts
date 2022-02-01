import { ChainId, Token } from "@rytell/sdk";
import { ethers } from "hardhat";

async function main() {
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

  // We get the contract to deploy
  const TreasuryVester = await ethers.getContractFactory("TreasuryVester");
  const treasuryVester = await TreasuryVester.deploy(
    RADI[ChainId.AVALANCHE].address
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
