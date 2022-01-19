// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./StakingRewards.sol";

/**
 * Contract to distribute RADI tokens to whitelisted trading pairs. After deploying,
 * whitelist the desired pairs and set the avaxRadiPair. When initial administration
 * is complete. Ownership should be transferred to the Timelock governance contract.
 */
contract LiquidityPoolManager is Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;

    // Whitelisted pairs that offer RADI rewards
    // Note: AVAX/RADI is an AVAX pair
    EnumerableSet.AddressSet private avaxPairs;
    EnumerableSet.AddressSet private radiPairs;
    EnumerableSet.AddressSet private stableTokenPairs;

    // Maps pairs to their associated StakingRewards contract
    mapping(address => address) public stakes;

    // Map of pools to weights
    mapping(address => uint256) public weights;

    // Fields to control potential fee splitting
    bool public splitPools;
    uint256 public avaxSplit;
    uint256 public radiSplit;
    uint256 public stableTokenSplit;

    // Known contract addresses for WAVAX and RADI
    address public wavax;
    address public radi;
    address public stableToken;

    // AVAX/RADI pair used to determine RADI liquidity
    address public avaxRadiPair;
    address public avaxStableTokenPair;

    // TreasuryVester contract that distributes RADI
    address public treasuryVester;

    uint256 public numPools = 0;

    bool private readyToDistribute = false;

    // Tokens to distribute to each pool. Indexed by avaxPairs then radiPairs.
    uint256[] public distribution;

    uint256 public unallocatedRadi = 0;

    constructor(
        address wavax_,
        address radi_,
        address stableToken_,
        address treasuryVester_
    ) {
        require(
            wavax_ != address(0) &&
                radi_ != address(0) &&
                treasuryVester_ != address(0),
            "LPM::constructor: Arguments can't be the zero address"
        );
        wavax = wavax_;
        radi = radi_;
        stableToken = stableToken_;
        treasuryVester = treasuryVester_;
    }

    /**
     * Check if the given pair is a whitelisted pair
     *
     * Args:
     *   pair: pair to check if whitelisted
     *
     * Return: True if whitelisted
     */
    function isWhitelisted(address pair) public view returns (bool) {
        return
            avaxPairs.contains(pair) ||
            radiPairs.contains(pair) ||
            stableTokenPairs.contains(pair);
    }

    /**
     * Check if the given pair is a whitelisted AVAX pair. The AVAX/RADI pair is
     * considered an AVAX pair.
     *
     * Args:
     *   pair: pair to check
     *
     * Return: True if whitelisted and pair contains AVAX
     */
    function isAvaxPair(address pair) external view returns (bool) {
        return avaxPairs.contains(pair);
    }

    /**
     * Check if the given pair is a whitelisted RADI pair. The AVAX/RADI pair is
     * not considered a RADI pair.
     *
     * Args:
     *   pair: pair to check
     *
     * Return: True if whitelisted and pair contains RADI but is not AVAX/RADI pair
     */
    function isRadiPair(address pair) external view returns (bool) {
        return radiPairs.contains(pair);
    }

    /**
     * Check if the given pair is a whitelisted STABLE TOKEN pair. The AVAX/STABLETOKEN pair is
     * not considered a STABLETOKEN pair.
     *
     * Args:
     *   pair: pair to check
     *
     * Return: True if whitelisted and pair contains RADI but is not AVAX/RADI pair
     */
    function isStableTokenPair(address pair) external view returns (bool) {
        return stableTokenPairs.contains(pair);
    }

    /**
     * Sets the AVAX/RADI pair. Pair's tokens must be AVAX and RADI.
     *
     * Args:
     *   pair: AVAX/RADI pair
     */
    function setavaxRadiPair(address avaxRadiPair_) external onlyOwner {
        require(
            avaxRadiPair_ != address(0),
            "LPM::setavaxRadiPair: Pool cannot be the zero address"
        );
        avaxRadiPair = avaxRadiPair_;
    }

    /**
     * Sets the AVAX/STABLETOKEN pair. Pair's tokens must be AVAX and STABLETOKEN.
     *
     * Args:
     *   pair: AVAX/STABLETOKEN pair
     */
    function setavaxStableTokenPair(address avaxStableTokenPair_)
        external
        onlyOwner
    {
        require(
            avaxStableTokenPair_ != address(0),
            "LPM::setavaxStableTokenPair: Pool cannot be the zero address"
        );
        avaxStableTokenPair = avaxStableTokenPair_;
    }

    /**
     * Adds a new whitelisted liquidity pool pair. Generates a staking contract.
     * Liquidity providers may stake this liquidity provider reward token and
     * claim RADI rewards proportional to their stake. Pair must contain either
     * AVAX or RADI. Associates a weight with the pair. Rewards are distributed
     * to the pair proportionally based on its share of the total weight.
     *
     * Args:
     *   pair: pair to whitelist
     *   weight: how heavily to distribute rewards to this pool relative to other
     *     pools
     */
    function addWhitelistedPool(address pair, uint256 weight)
        external
        onlyOwner
    {
        require(
            !readyToDistribute,
            "LPM::addWhitelistedPool: Cannot add pool between calculating and distributing returns"
        );
        require(
            pair != address(0),
            "LPM::addWhitelistedPool: Pool cannot be the zero address"
        );
        require(
            isWhitelisted(pair) == false,
            "LPM::addWhitelistedPool: Pool already whitelisted"
        );
        require(weight > 0, "LPM::addWhitelistedPool: Weight cannot be zero");

        address token0 = IRytellPair(pair).token0();
        address token1 = IRytellPair(pair).token1();

        require(
            token0 != token1,
            "LPM::addWhitelistedPool: Tokens cannot be identical"
        );

        // Create the staking contract and associate it with the pair
        address stakeContract = address(new StakingRewards(radi, pair));
        stakes[pair] = stakeContract;

        weights[pair] = weight;

        // Add as an AVAX or RADI or STABLECOIN pair
        if (token0 == radi || token1 == radi) {
            require(
                radiPairs.add(pair),
                "LPM::addWhitelistedPool: Pair add failed"
            );
        } else if (token0 == wavax || token1 == wavax) {
            require(
                avaxPairs.add(pair),
                "LPM::addWhitelistedPool: Pair add failed"
            );
        } else if (token0 == stableToken || token1 == stableToken) {
            require(
                stableTokenPairs.add(pair),
                "LPM::addWhitelistedPool: Pair add failed"
            );
        } else {
            revert(
                "LPM::addWhitelistedPool: No AVAX, RADI or STABLETOKEN in the pair"
            );
        }

        numPools = numPools.add(1);
    }

    /**
     * Delists a whitelisted pool. Liquidity providers will not receiving future rewards.
     * Already vested funds can still be claimed. Re-whitelisting a delisted pool will
     * deploy a new staking contract.
     *
     * Args:
     *   pair: pair to remove from whitelist
     */
    function removeWhitelistedPool(address pair) external onlyOwner {
        require(
            !readyToDistribute,
            "LPM::removeWhitelistedPool: Cannot remove pool between calculating and distributing returns"
        );
        require(
            isWhitelisted(pair),
            "LPM::removeWhitelistedPool: Pool not whitelisted"
        );

        address token0 = IRytellPair(pair).token0();
        address token1 = IRytellPair(pair).token1();

        stakes[pair] = address(0);
        weights[pair] = 0;

        if (token0 == radi || token1 == radi) {
            require(
                radiPairs.remove(pair),
                "LPM::removeWhitelistedPool: Pair remove failed"
            );
        } else if (token0 == wavax || token1 == wavax) {
            require(
                avaxPairs.remove(pair),
                "LPM::removeWhitelistedPool: Pair remove failed"
            );
        } else if (token0 == stableToken || token1 == stableToken) {
            require(
                stableTokenPairs.remove(pair),
                "LPM::removeWhitelistedPool: Pair remove failed"
            );
        } else {
            revert(
                "LPM::removeWhitelistedPool: No AVAX, RADI or STABLETOKEN in the pair"
            );
        }
        numPools = numPools.sub(1);
    }

    /**
     * Adjust the weight of an existing pool
     *
     * Args:
     *   pair: pool to adjust weight of
     *   weight: new weight
     */
    function changeWeight(address pair, uint256 weight) external onlyOwner {
        require(weights[pair] > 0, "LPM::changeWeight: Pair not whitelisted");
        require(weight > 0, "LPM::changeWeight: Remove pool instead");
        weights[pair] = weight;
    }

    /**
     * Activates the fee split mechanism. Divides rewards between AVAX
     * and RADI pools regardless of liquidity. AVAX and RADI pools will
     * receive a fixed proportion of the pool rewards. The AVAX and RADI
     * splits should correspond to percentage of rewards received for
     * each and must add up to 100. For the purposes of fee splitting,
     * the AVAX/RADI pool is a RADI pool. This method can also be used to
     * change the split ratio after fee splitting has been activated.
     *
     * Args:
     *   avaxSplit: Percent of rewards to distribute to AVAX pools
     *   radiSplit: Percent of rewards to distribute to RADI pools
     *   stableTokenSplit: Percent of rewards to distribute to STABLETOKEN pools
     */
    function activateFeeSplit(
        uint256 avaxSplit_,
        uint256 radiSplit_,
        uint256 stableTokenSplit_
    ) external onlyOwner {
        require(
            avaxSplit_.add(radiSplit_).add(stableTokenSplit_) == 100,
            "LPM::activateFeeSplit: Split doesn't add to 100"
        );
        require(
            !(avaxSplit_ == 100 ||
                radiSplit_ == 100 ||
                stableTokenSplit_ == 100),
            "LPM::activateFeeSplit: Split can't be 100/0-0"
        );
        splitPools = true;
        avaxSplit = avaxSplit_;
        radiSplit = radiSplit_;
        stableTokenSplit = stableTokenSplit_;
    }

    /**
     * Deactivates fee splitting.
     */
    function deactivateFeeSplit() external onlyOwner {
        require(splitPools, "LPM::deactivateFeeSplit: Fee split not activated");
        splitPools = false;
        avaxSplit = 0;
        radiSplit = 0;
        stableTokenSplit = 0;
    }

    /**
     * Determine how the vested RADI allocation will be distributed to the liquidity
     * pool staking contracts. Must be called before distributeTokens(). Tokens are
     * distributed to pools based on relative liquidity proportional to total
     * liquidity. Should be called after vestAllocation()/
     */
    function calculateReturns() public {
        require(
            !readyToDistribute,
            "LPM::calculateReturns: Previous returns not distributed. Call distributeTokens()"
        );
        require(
            unallocatedRadi > 0,
            "LPM::calculateReturns: No RADI to allocate. Call vestAllocation()."
        );
        if (radiPairs.length() > 0) {
            require(
                !(avaxRadiPair == address(0)),
                "LPM::calculateReturns: Avax/RADI Pair not set"
            );
        }
        if (stableTokenPairs.length() > 0) {
            require(
                !(avaxStableTokenPair == address(0)),
                "LPM::calculateReturns: Avax/STABLETOKEN Pair not set"
            );
        }

        // Calculate total liquidity
        distribution = new uint256[](numPools);
        uint256 avaxLiquidity = 0;
        uint256 radiLiquidity = 0;
        uint256 stableTokenLiquidity = 0;

        // Add liquidity from AVAX pairs
        for (uint256 i = 0; i < avaxPairs.length(); i++) {
            address pair = avaxPairs.at(i);
            uint256 pairLiquidity = 1;
            uint256 weightedLiquidity = pairLiquidity.mul(weights[pair]);
            distribution[i] = weightedLiquidity;
            avaxLiquidity = SafeMath.add(avaxLiquidity, weightedLiquidity);
        }

        // Add liquidity from RADI pairs
        if (radiPairs.length() > 0) {
            for (uint256 i = 0; i < radiPairs.length(); i++) {
                address pair = radiPairs.at(i);
                uint256 pairLiquidity = 1;
                uint256 weightedLiquidity = pairLiquidity.mul(weights[pair]);
                distribution[i + avaxPairs.length()] = weightedLiquidity;
                radiLiquidity = SafeMath.add(
                    radiLiquidity,
                    weightedLiquidity
                );
            }
        }

        // Add liquidity from STABLETOKEN pairs
        if (stableTokenPairs.length() > 0) {
            for (uint256 i = 0; i < stableTokenPairs.length(); i++) {
                address pair = stableTokenPairs.at(i);
                uint256 pairLiquidity = 1;
                uint256 weightedLiquidity = pairLiquidity.mul(weights[pair]);
                distribution[
                    i + avaxPairs.length() + radiPairs.length()
                ] = weightedLiquidity;
                stableTokenLiquidity = SafeMath.add(
                    stableTokenLiquidity,
                    weightedLiquidity
                );
            }
        }

        // Calculate tokens for each pool
        uint256 transferred = 0;
        if (splitPools) {
            uint256 avaxAllocatedRadi = unallocatedRadi.mul(avaxSplit).div(
                100
            );
            uint256 radiAllocatedRadi = unallocatedRadi.mul(radiSplit).div(
                100
            );
            uint256 stableTokenAllocatedRadi = unallocatedRadi
                .mul(stableTokenSplit)
                .div(100);

            for (uint256 i = 0; i < avaxPairs.length(); i++) {
                uint256 pairTokens = distribution[i]
                    .mul(avaxAllocatedRadi)
                    .div(avaxLiquidity);
                distribution[i] = pairTokens;
                transferred = transferred.add(pairTokens);
            }

            if (radiPairs.length() > 0) {
                for (uint256 i = 0; i < radiPairs.length(); i++) {
                    uint256 pairTokens = distribution[i + avaxPairs.length()]
                        .mul(radiAllocatedRadi)
                        .div(radiLiquidity);
                    distribution[i + avaxPairs.length()] = pairTokens;
                    transferred = transferred.add(pairTokens);
                }
            }

            if (stableTokenPairs.length() > 0) {
                for (uint256 i = 0; i < stableTokenPairs.length(); i++) {
                    uint256 pairTokens = distribution[
                        i + avaxPairs.length() + radiPairs.length()
                    ].mul(stableTokenAllocatedRadi).div(stableTokenLiquidity);
                    distribution[
                        i + avaxPairs.length() + radiPairs.length()
                    ] = pairTokens;
                    transferred = transferred.add(pairTokens);
                }
            }
        } else {
            uint256 totalLiquidity = avaxLiquidity.add(radiLiquidity).add(
                stableTokenLiquidity
            );

            for (uint256 i = 0; i < distribution.length; i++) {
                uint256 pairTokens = distribution[i].mul(unallocatedRadi).div(
                    totalLiquidity
                );
                distribution[i] = pairTokens;
                transferred = transferred.add(pairTokens);
            }
        }
        readyToDistribute = true;
    }

    /**
     * After token distributions have been calculated, actually distribute the vested RADI
     * allocation to the staking pools. Must be called after calculateReturns().
     */
    function distributeTokens() public nonReentrant {
        require(
            readyToDistribute,
            "LPM::distributeTokens: Previous returns not allocated. Call calculateReturns()"
        );
        readyToDistribute = false;
        address stakeContract;
        uint256 rewardTokens;
        for (uint256 i = 0; i < distribution.length; i++) {
            if (i < avaxPairs.length()) {
                stakeContract = stakes[avaxPairs.at(i)];
            } else if (
                i >= avaxPairs.length() &&
                i < (radiPairs.length() + avaxPairs.length())
            ) {
                stakeContract = stakes[radiPairs.at(i - avaxPairs.length())];
            } else {
                stakeContract = stakes[
                    stableTokenPairs.at(
                        i - avaxPairs.length() - radiPairs.length()
                    )
                ];
            }
            rewardTokens = distribution[i];
            if (rewardTokens > 0) {
                require(
                    IRADI(radi).transfer(stakeContract, rewardTokens),
                    "LPM::distributeTokens: Transfer failed"
                );
                StakingRewards(stakeContract).notifyRewardAmount(rewardTokens);
            }
        }
        unallocatedRadi = 0;
    }

    /**
     * Fallback for distributeTokens in case of gas overflow. Distributes RADI tokens to a single pool.
     * distibuteTokens() must still be called once to reset the contract state before calling vestAllocation.
     *
     * Args:
     *   pairIndex: index of pair to distribute tokens to, AVAX pairs come first in the ordering
     */
    function distributeTokensSinglePool(uint256 pairIndex)
        external
        nonReentrant
    {
        require(
            readyToDistribute,
            "LPM::distributeTokensSinglePool: Previous returns not allocated. Call calculateReturns()"
        );
        require(
            pairIndex < numPools,
            "LPM::distributeTokensSinglePool: Index out of bounds"
        );

        address stakeContract;
        if (pairIndex < avaxPairs.length()) {
            stakeContract = stakes[avaxPairs.at(pairIndex)];
        } else if (
            pairIndex >= avaxPairs.length() &&
            pairIndex < (avaxPairs.length() + radiPairs.length())
        ) {
            stakeContract = stakes[
                radiPairs.at(pairIndex - avaxPairs.length())
            ];
        } else {
            stakeContract = stakes[
                stableTokenPairs.at(
                    pairIndex - avaxPairs.length() - radiPairs.length()
                )
            ];
        }

        uint256 rewardTokens = distribution[pairIndex];
        if (rewardTokens > 0) {
            distribution[pairIndex] = 0;
            require(
                IRADI(radi).transfer(stakeContract, rewardTokens),
                "LPM::distributeTokens: Transfer failed"
            );
            StakingRewards(stakeContract).notifyRewardAmount(rewardTokens);
        }
    }

    /**
     * Calculate pool token distribution and distribute tokens. Methods are separate
     * to use risk of approaching the gas limit. There must be vested tokens to
     * distribute, so this method should be called after vestAllocation.
     */
    function calculateAndDistribute() external {
        calculateReturns();
        distributeTokens();
    }

    /**
     * Claim today's vested tokens for the manager to distribute. Moves tokens from
     * the TreasuryVester to the LPM. Can only be called if all
     * previously allocated tokens have been distributed. Call distributeTokens() if
     * that is not the case. If any additional RADI tokens have been transferred to this
     * this contract, they will be marked as unallocated and prepared for distribution.
     */
    function vestAllocation() external nonReentrant onlyOwner {
        require(
            unallocatedRadi == 0,
            "LPM::vestAllocation: Old RADI is unallocated. Call distributeTokens()."
        );
        unallocatedRadi = ITreasuryVester(treasuryVester).claim();
        require(
            unallocatedRadi > 0,
            "LPM::vestAllocation: No RADI to claim. Try again tomorrow."
        );

        // Check if we've received extra tokens or didn't receive enough
        uint256 actualBalance = IRADI(radi).balanceOf(address(this));
        require(
            actualBalance >= unallocatedRadi,
            "LPM::vestAllocation: Insufficient RADI transferred"
        );
        unallocatedRadi = actualBalance;
    }

    /**
     * Calculate the equivalent of 1e18 of token A denominated in token B for a pair
     * with reserveA and reserveB reserves.
     *
     * Args:
     *   reserveA: reserves of token A
     *   reserveB: reserves of token B
     *
     * Returns: the amount of token B equivalent to 1e18 of token A
     */
    function quote(uint256 reserveA, uint256 reserveB)
        internal
        pure
        returns (uint256 amountB)
    {
        require(
            reserveA > 0 && reserveB > 0,
            "RadiLibrary: INSUFFICIENT_LIQUIDITY"
        );
        uint256 oneToken = 1e18;
        amountB = SafeMath.div(SafeMath.mul(oneToken, reserveB), reserveA);
    }

    /**
     * Sets the treasury vester address.
     *
     * Args:
     *   address: Treasury Vester Address
     */
    function setTreasuryVester(address treasuryVester_) external onlyOwner {
        require(
            treasuryVester_ != address(0),
            "LPM::setTreasuryVester: Treasury Vester cannot be the zero address"
        );
        treasuryVester = treasuryVester_;
    }
}

interface ITreasuryVester {
    function claim() external returns (uint256);
}

interface IRADI {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address dst, uint256 rawAmount) external returns (bool);
}

interface IRytellPair {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function factory() external view returns (address);

    function balanceOf(address owner) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function burn(address to)
        external
        returns (uint256 amount0, uint256 amount1);

    function getReserves()
        external
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        );
}