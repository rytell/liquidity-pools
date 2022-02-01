// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * Contract to control the release of RADI.
 */
contract TreasuryVester is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public radi;
    address public recipient;

    bool public vestingEnabled;

    // Amount of RADI required to start distributing denominated in wei
    // Should be 1 RADI
    uint256 public startingBalance = 1;

    event VestingEnabled();
    event TokensVested(uint256 amount, address recipient);
    event RecipientChanged(address recipient);

    // RADI Distribution plan:
    // According to the Pangolin Litepaper, we initially will distribute
    // 175342.465 RADI per day. Vesting period will be 24 hours: 86400 seconds.
    // Halving will occur every four years. No leap day. 4 years: 1460 distributions

    constructor(address radi_) {
        radi = radi_;
    }

    /**
     * Enable distribution. A sufficient amount of RADI >= startingBalance must be transferred
     * to the contract before enabling. The recipient must also be set. Can only be called by
     * the owner.
     */
    function startVesting() external onlyOwner {
        require(
            !vestingEnabled,
            "TreasuryVester::startVesting: vesting already started"
        );
        require(
            IERC20(radi).balanceOf(address(this)) >= startingBalance,
            "TreasuryVester::startVesting: incorrect RADI supply"
        );
        require(
            recipient != address(0),
            "TreasuryVester::startVesting: recipient not set"
        );
        vestingEnabled = true;

        emit VestingEnabled();
    }

    /**
     * Sets the recipient of the vested distributions. In the initial Pangolin scheme, this
     * should be the address of the LiquidityPoolManager. Can only be called by the contract
     * owner.
     */
    function setRecipient(address recipient_) external onlyOwner {
        require(
            recipient_ != address(0),
            "TreasuryVester::setRecipient: Recipient can't be the zero address"
        );
        recipient = recipient_;
        emit RecipientChanged(recipient);
    }

    /**
     * Vest the next RADI allocation. Requires vestingCliff seconds in between calls. RADI will
     * be distributed to the recipient.
     */
    function claim() external nonReentrant returns (uint256) {
        require(vestingEnabled, "TreasuryVester::claim: vesting not enabled");
        require(
            msg.sender == recipient,
            "TreasuryVester::claim: only recipient can claim"
        );

        uint256 radiAvailable = IERC20(radi).balanceOf(address(this));
        // Distribute the tokens
        IERC20(radi).safeTransfer(recipient, radiAvailable);
        emit TokensVested(radiAvailable, recipient);

        return radiAvailable;
    }
}