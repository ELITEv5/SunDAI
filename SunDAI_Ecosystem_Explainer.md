# SunDAI Ecosystem: Autonomous Stable Assets on PulseChain

**ELITE TEAM6** | [sundaitoken.com](https://www.sundaitoken.com)

*Pure self-sovereignty through immutable infrastructure*

---

## Table of Contents

1. [What is SunDAI?](#what-is-sundai)
2. [The Complete Ecosystem](#the-complete-ecosystem)
3. [Core: pSunDAI Vault (v5.6)](#core-psundai-vault-v56)
4. [Oracle: Self-Healing Price Feeds (v5.1)](#oracle-self-healing-price-feeds-v51)
5. [Yield: sSunDAI Auto-Compounder (v1.0)](#yield-ssundai-auto-compounder-v10)
6. [Bootstrap: Destiny Vault Black Hole](#bootstrap-destiny-vault-black-hole)
7. [Technical Specifications](#technical-specifications)
8. [Why This Architecture Matters](#why-this-architecture-matters)

---

## What is SunDAI?

SunDAI is an **Autonomous Stable Asset (ASA)** - a completely self-governing, overcollateralized stable asset system with **zero admin keys, no governance, and no upgradability**. Once deployed, it runs forever based purely on economic incentives.

**pSunDAI** is the PulseChain implementation - a $1-pegged stable asset backed by PLS collateral, minted through an immutable CDP (Collateralized Debt Position) system.

### Key Principles

- **Immutable**: Cannot be paused, upgraded, or controlled after deployment
- **Autonomous**: Self-regulates through economic incentives
- **Overcollateralized**: Always backed by 150%+ PLS collateral  
- **Self-healing**: Oracle and vault auto-recover from attacks
- **Permissionless**: Anyone can interact, no gatekeepers

---

## The Complete Ecosystem

```
SunDAI (Base meme token)
    ↓
pSunDAI (PulseChain overcollateralized stable)
    ↓
sSunDAI (Auto-compounding LP staking)
    ↓
Destiny Vault (Bootstrap mechanism)
```

**Current Status**: Live on PulseChain mainnet

---

## Core: pSunDAI Vault (v5.6)

### Overview

The vault is a CDP system where users lock PLS collateral to mint pSunDAI. It's the heart of the ecosystem.

**Contract**: `pSunDAIVault_ASA_v5_6`

### Key Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| **Minimum Collateral Ratio** | 150% | Required to mint pSunDAI |
| **Auto-Mint Ratio** | 155% | One-click safe deposit+mint |
| **Liquidation Threshold** | 110% | Below this = liquidatable |
| **Liquidation Bonus** | 2-5% | Graduated over 3 hours (Dutch auction) |
| **Minimum Liquidation** | 20% of debt | Allows partial liquidations |
| **Stability Fee** | 0.5% APY | Accrues continuously on debt |
| **Withdraw Cooldown** | 5 minutes | After deposit (anti-manipulation) |
| **Liquidation Cooldown** | 10 minutes | Between liquidations |
| **Emergency Unlock** | 30 days | If zero debt, can force withdraw |

### How It Works

#### Opening a Position

```solidity
// Deposit PLS
vault.depositPLS{value: amount}()

// Mint pSunDAI (must maintain 150% ratio)
vault.mint(amount)

// OR one-click at safe 155% ratio
vault.depositAndAutoMintPLS{value: amount}()
```

**Example:**
- Deposit 100,000 PLS worth $1.50 at $0.000015/PLS
- Can mint up to $1.00 pSunDAI (150% collateralization)
- Auto-mint gives you $0.968 pSunDAI (155% buffer)

#### Managing Your Position

```solidity
// Add more collateral
vault.depositPLS{value: moreAmount}()

// Mint more (if ratio allows)
vault.mint(additionalAmount)

// Repay debt
vault.repay(amount)

// Withdraw collateral (if safe)
vault.withdrawPLS(amount)

// Repay and auto-withdraw excess
vault.repayAndAutoWithdraw(repayAmount)

// Auto-repay to exactly 150%
vault.autoRepayToHealth()
```

#### Stability Fee (Interest)

- **0.5% APY** accrues on all debt
- Compounds continuously whenever you interact with vault
- Example: $1000 debt → $1005 after 1 year
- Dust forgiven: debt under 0.000001 pSunDAI automatically cleared

### Liquidation System

When a vault drops below 110% collateralization, **anyone** can liquidate it.

```solidity
vault.liquidate(userAddress, repayAmount)
```

**Dutch Auction Mechanism:**

| Time Since Unsafe | Bonus |
|-------------------|-------|
| 0 hours | 2% |
| 1 hour | 3% |
| 2 hours | 4% |
| 3+ hours | 5% (max) |

**Example Liquidation:**
1. Alice has 100,000 PLS ($1.50) backing $1.40 debt → 107% ratio (unsafe!)
2. Bob repays $0.50 of Alice's debt (35.7% of total)
3. Bob receives $0.50 worth of PLS × 1.03 bonus (after 1 hour) = $0.515 in PLS
4. Alice keeps remaining collateral, debt reduced
5. If Alice is still unsafe, can be liquidated again after 10 min cooldown

**Why Partial Liquidations?**
- User-friendly: doesn't wipe out entire position
- Efficient: just enough to restore health
- Gradual: bonus grows over time, incentivizing quick response

### Safety Features

**10% Volatility Guard:**
- If oracle price moves >10% from last accepted price
- **Downward moves**: 4-hour cooldown before acceptance
- **Upward moves**: 1-hour cooldown before acceptance
- **Early recovery**: If price returns to ±10% band, immediately accepted
- Protects against flash crashes while allowing real market moves

**Emergency Unlock:**
- If you have zero debt for 30+ days, can force withdraw all collateral
- Prevents accidental lockups
- No penalties

---

## Oracle: Self-Healing Price Feeds (v5.1)

### Overview

Custom 5-pair median oracle with confirmation periods and stepping mechanism.

**Contract**: `pSunDAIoraclePLSXHybrid_5_1`

### Architecture

```
Price Sources (PulseX DEX):
├── PLS/DAI v1
├── PLS/DAI v2
├── PLS/USDC v1
├── PLS/USDC v2
└── PLS/USDT

Aggregation: Median of 5 prices
Update: Manual poke (30-min rate limit)
```

### Advanced Protection: Confirmation + Stepping

**The Problem Oracle v5.1 Solves:**

Traditional oracles accept price updates immediately. This allows:
- Flash crash attacks (manipulate DEX, liquidate users, profit)
- Oracle manipulation via flash loans
- Unfair liquidations during temporary volatility

**The Solution: Two-Phase Update**

#### Phase 1: Confirmation Period

When price moves >3% from current:

| Price Direction | Confirmation Time |
|----------------|-------------------|
| **Down >3%** | 4 hours |
| **Up >3%** | 1 hour |

**Why Asymmetric?**
- Flash crashes are more common than flash pumps
- Protects users from downside manipulation
- Allows natural upside without excessive delay
- Real crashes take hours to develop

#### Phase 2: Stepping Mechanism

After confirmation period passes, price doesn't jump immediately. Instead:

| Direction | Step Size | Frequency |
|-----------|-----------|-----------|
| **Downward** | 5% per step | Every 30 min |
| **Upward** | 10% per step | Every 30 min |

**Example: Real Crash Scenario**

```
T=0:    PLS = $0.000020, Oracle = $0.000020
        Market dumps to $0.000014 (-30%)

T=0:    Oracle sees -30% divergence
        Starts 4-hour confirmation period
        Still reports $0.000020 (protects users)

T=4h:   Confirmation complete
        Price still $0.000014?
        Begin stepping down 5% per 30min

T=4.5h: Oracle steps to $0.000019 (-5%)
T=5h:   Oracle steps to $0.0000181 (-5% more)
T=5.5h: Oracle steps to $0.0000172 (-5% more)
...continues until reaching $0.000014

Total time: ~6 hours for -30% crash
```

**What if price recovers during confirmation?**
- If price moves back within ±3% during the 4-hour window
- Confirmation **cancels immediately**
- Price **updates instantly** to current level
- This prevents delayed responses to false alarms

### Manual Poke System

```solidity
oracle.poke()
```

- Anyone can call to update oracle
- 30-minute cooldown between pokes (anti-spam)
- No reward for poking (keeps it simple)
- Vault auto-calls when needed (user never needs to poke manually)

### Monitoring Functions

```solidity
// Check if you can poke
oracle.canPoke() // returns bool

// Time until next poke allowed
oracle.timeUntilNextPoke() // returns seconds

// Get complete oracle status
oracle.getPriceStatus() // returns (
//   currentPrice,
//   marketPrice,
//   divergenceBps,
//   inConfirmation,
//   confirmTimeRemaining,
//   targetPrice
// )
```

### Safety Features

**Median Aggregation:**
- Takes median of 5 DEX pairs
- Resistant to single-pair manipulation
- Requires majority of liquidity to manipulate
- Handles pair outages gracefully

**TWAP + Spot Hybrid:**
- Uses time-weighted average when available
- Falls back to spot price for fresh data
- Minimum 1-minute TWAP window
- Maximum 5-minute staleness tolerance

**24-Hour Fallback:**
- If oracle hasn't updated in 24 hours
- Automatically uses current spot median
- Self-healing mechanism
- Prevents permanent oracle failure

---

## Yield: sSunDAI Auto-Compounder (v1.0)

### Overview

Auto-compounding vault for pSunDAI/PLS LP tokens. Deposit LP, receive sSunDAI receipt tokens that appreciate over time as trading fees compound.

**Contract**: `sSunDAI`

### How It Works

```
User deposits 100 LP tokens
    ↓
Receives 100 sSunDAI (1:1 initially)
    ↓
Trading fees accrue in LP pool (0.3% per swap)
    ↓
Anyone calls harvest() (permissionless)
    ↓
Vault burns 1% of LP, receives tokens + fees
    ↓
Re-adds liquidity with fees included
    ↓
Gets back more LP than burned
    ↓
Net gain compounds for all holders
    ↓
sSunDAI now worth 1.02 LP (2% appreciation)
```

### Key Functions

```solidity
// Deposit LP, get sSunDAI
sSunDAI.deposit(lpAmount) // returns shares

// Withdraw LP, burn sSunDAI  
sSunDAI.withdraw(shares) // returns lpAmount

// Withdraw all
sSunDAI.withdrawAll()

// Withdraw only profits
sSunDAI.withdrawYieldOnly()

// Permissionless harvest (anyone can call)
sSunDAI.harvest() // returns netGain
```

### Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| **Min Deposit** | 0.0001 LP | Prevent dust spam |
| **Harvest Batch** | 1% of pool | Amount to compound per harvest |
| **Min Harvest Interval** | 1 hour | Cooldown between harvests |
| **Slippage Tolerance** | 0.5% | Max slippage on re-add |

### Economics

**No external rewards** - Pure auto-compounding of trading fees

**Example APY Calculation:**
```
Pool: $100,000 liquidity
Daily volume: $50,000
Fee: 0.3% = $150/day in fees
Annual fees: $150 × 365 = $54,750
APY: $54,750 / $100,000 = 54.75%

After compounding at 1% batch size every hour:
Effective APY: ~57% (from compound effect)
```

**Key Insight**: APY scales with volume, not liquidity. High volume relative to liquidity = high APY.

### View Functions

```solidity
// Current LP per sSunDAI
sSunDAI.exchangeRate() // e.g., 1.05e18 = 1 sSunDAI worth 1.05 LP

// Preview withdraw
sSunDAI.previewWithdraw(shares) // returns LP amount

// Preview deposit
sSunDAI.previewDeposit(lpAmount) // returns shares

// Check if harvest ready
sSunDAI.canHarvest() // returns (ready, timeUntilReady)

// User position info
sSunDAI.positionInfo(user) // returns (
//   sharesOwned,
//   lpValue,
//   appreciationBps,
//   appreciationPercent,
//   depositedLP,
//   earnedLP
// )

// Vault stats
sSunDAI.vaultStats() // returns (
//   totalLPHeld,
//   totalSharesIssued,
//   currentExchangeRate,
//   harvestCount,
//   feesCompounded,
//   timeSinceLastHarvest
// )
```

---

## Bootstrap: Destiny Vault Black Hole

### Overview

Mechanism to bootstrap pSunDAI collateral by converting SunDAI holders into pSunDAI vault collateral providers.

**Contract**: `DestinyVaultBlackHole`

### The Journey

#### Phase 1: Staking (Before $1)

Users can stake:
- SunDAI tokens (1x weight)
- SunDAI/PLS LP tokens (1.5x weight for providing liquidity)

```solidity
destinyVault.stake(sundaiAmount, plpAmount)
```

**Weighted System:**
- 100 SunDAI = 100 weight
- 100 SunDAI/PLS LP = 150 weight
- Rewards LP providers for bootstrapping liquidity

#### Phase 2: Ignite (SunDAI Reaches $1)

When SunDAI hits $1 (via SunDial Oracle), anyone can call:

```solidity
destinyVault.ignite()
```

**What Happens:**
1. Breaks all LP → SunDAI + WPLS
2. Swaps ALL SunDAI → WPLS
3. Unwraps all WPLS → PLS
4. **Result**: Pure PLS ready for vault deposit

#### Phase 3: Supernova (Deposit to Vault)

```solidity
destinyVault.supernova()
```

Deposits all PLS into pSunDAI vault as collateral.

#### Phase 4: Rebirth (Mint pSunDAI)

```solidity
destinyVault.rebirth()
```

Mints pSunDAI against deposited collateral at **90% of max** (safe buffer).

#### Phase 5: Claim (Distribute)

Each staker claims proportional pSunDAI:

```solidity
destinyVault.claim()
```

**Payout Formula:**
```
Your pSunDAI = (Total pSunDAI minted) × (Your weight / Total weight)
```

**Example:**
- Alice staked 1000 SunDAI = 1000 weight
- Bob staked 500 SunDAI/PLS LP = 750 weight  
- Total weight = 1750
- Vault minted 10,000 pSunDAI
- Alice receives: 10,000 × (1000/1750) = 5,714 pSunDAI
- Bob receives: 10,000 × (750/1750) = 4,286 pSunDAI

### Emergency Exit

If SunDAI never reaches $1 or something goes wrong:

```solidity
// Owner enables emergency mode
destinyVault.enableEmergencyExit()

// Users claim original assets back
destinyVault.claimEmergency()
```

**Returns:**
- If **before ignite**: Original SunDAI + LP tokens
- If **after ignite**: Proportional PLS (from swaps)

### Threshold Control

```solidity
// Set price threshold (default $1)
destinyVault.setThreshold(newThreshold)

// Lock threshold (makes it permanent)
destinyVault.lockThreshold()

// Check if locked
destinyVault.isLocked() // true if price >= threshold OR ignited
```

---

## Technical Specifications

### Contract Versions

| Contract | Version | Status |
|----------|---------|--------|
| pSunDAI Token | v1.0 | Immutable |
| pSunDAI Vault | v5.6 | Production |
| Oracle | v5.1 | Production |
| sSunDAI | v1.0 | Production |
| Destiny Vault | v1.0 | Active |
| SunDial Oracle | v1.0 | Active |

### Key Constants

**Vault:**
```solidity
COLLATERAL_RATIO = 150        // 150% minimum
LIQUIDATION_RATIO = 110        // 110% liquidation threshold  
MIN_BONUS_BPS = 200            // 2% min liquidation bonus
MAX_BONUS_BPS = 500            // 5% max liquidation bonus
AUCTION_TIME = 3 hours         // Dutch auction duration
STABILITY_FEE_BPS = 50         // 0.5% annual fee
WITHDRAW_COOLDOWN = 300        // 5 minutes
LIQUIDATION_COOLDOWN = 600     // 10 minutes
MAX_VOLATILITY_BPS = 1000      // 10% max instant price move
```

**Oracle:**
```solidity
CONFIRM_TIME_DOWN = 4 hours    // Confirmation for drops
CONFIRM_TIME_UP = 1 hours      // Confirmation for pumps
STEP_SIZE_DOWN_BPS = 500       // 5% step down
STEP_SIZE_UP_BPS = 1000        // 10% step up
MIN_POKE_INTERVAL = 30 minutes // Poke rate limit
INSTANT_UPDATE_BPS = 300       // 3% instant threshold
MIN_RESERVE_USD = 10000e18     // $10k min liquidity
MIN_TWAP_INTERVAL = 60         // 1 minute TWAP
MAX_PRICE_AGE = 300            // 5 minutes max staleness
```

**sSunDAI:**
```solidity
MIN_DEPOSIT = 1e14             // 0.0001 LP minimum
HARVEST_BATCH_BPS = 100        // 1% harvest size
MIN_HARVEST_INTERVAL = 1 hours // 1 hour cooldown
SLIPPAGE_BPS = 50              // 0.5% slippage tolerance
```

**Destiny Vault:**
```solidity
LP_MULTIPLIER_BPS = 15000      // 1.5x weight for LP
SAFETY_BPS = 9000              // 90% of max mint (safety)
```

### Gas Optimization

- Minimal storage reads/writes
- Efficient median calculation (insertion sort)
- Batch operations where possible
- No unnecessary token transfers
- Optimized for PulseChain's low gas costs

---

## Why This Architecture Matters

### The Problem with Existing Stablecoins

**Centralized (USDC, USDT):**
- ❌ Trust in issuing company required
- ❌ Can freeze your funds
- ❌ Subject to regulatory pressure
- ❌ Bank run risk

**Governance-Heavy (MakerDAO):**
- ❌ Complex governance = attack surface
- ❌ Voter apathy = plutocracy
- ❌ Parameters can change against you
- ❌ Upgradeable contracts = rug risk

**Algorithmic (Luna/UST, Iron Finance):**
- ❌ Undercollateralized = death spiral risk
- ❌ Ponzi-like mechanics
- ❌ No real backing

### The SunDAI Solution

**True Decentralization:**
- ✅ No company, no foundation, no governance
- ✅ Immutable contracts (cannot be changed)
- ✅ Autonomous operation through incentives
- ✅ Censorship-resistant

**Economic Soundness:**
- ✅ Always overcollateralized (150% minimum)
- ✅ Clear liquidation incentives (2-5% bonus)
- ✅ No algorithmic tricks or ponzinomics
- ✅ Backed by real assets (PLS)

**Advanced Safety:**
- ✅ 4-hour confirmation prevents flash crashes
- ✅ Stepping mechanism prevents oracle jumps
- ✅ Partial liquidations = user-friendly
- ✅ Self-healing oracle with 24h fallback
- ✅ Multiple safety layers (vault + oracle + median)

**User Sovereignty:**
- ✅ Complete control over collateral
- ✅ No admin can seize funds
- ✅ Permissionless access
- ✅ Transparent on-chain

### Comparison to MakerDAO

| Feature | MakerDAO | SunDAI |
|---------|----------|--------|
| **Governance** | Complex, ongoing | None, immutable |
| **Upgradability** | Yes (risk) | No (secure) |
| **Collateral Ratio** | Varies by governance | Fixed 150% |
| **Liquidation** | Auction keepers | Permissionless |
| **Oracle** | Governance-controlled | Self-healing |
| **Stability Fee** | Variable | Fixed 0.5% |
| **Regulatory Risk** | High (foundation) | Low (no entity) |
| **Flash Crash Protection** | Limited | 4-hour confirmation |

### Innovation Highlights

**1. Confirmation + Stepping Oracle**

Industry first: Two-phase price updates with asymmetric timing.

```
Traditional oracle: Price jumps immediately (risky)
SunDAI oracle: Confirms 4h → Steps 5% every 30min (safe)
```

**2. Dutch Auction Liquidations**

```
Traditional: Fixed penalty (brutal for users)
SunDAI: 2% → 5% over 3 hours (fair + effective)
```

**3. Partial Liquidations**

```
Traditional: All-or-nothing (wipes position)
SunDAI: Minimum 20%, liquidate just enough (user-friendly)
```

**4. Auto-Compounding LP (sSunDAI)**

```
Traditional LP: Manually claim + re-add (expensive, slow)
sSunDAI: Permissionless auto-compound (gas-efficient, optimal)
```

**5. Destiny Vault Bootstrap**

```
Traditional: Team provides liquidity (centralized)
SunDAI: Community converts meme → collateral (aligned)
```

---

## Economic Model

### Stability Mechanisms

**Peg Arbitrage (pSunDAI → $1):**

If pSunDAI > $1:
1. Mint pSunDAI at 150% collateral
2. Sell pSunDAI at premium
3. Profit = premium
4. *Effect*: Increases supply → Pushes price down

If pSunDAI < $1:
1. Buy pSunDAI at discount
2. Repay vault debt
3. Profit = discount
4. *Effect*: Decreases supply → Pushes price up

**Collateral Buffer:**

150% → 110% = 40 percentage point buffer

```
Example:
- Collateral worth $1.50
- Debt: $1.00
- Ratio: 150%

PLS drops 26%:
- Collateral now $1.11
- Debt: $1.00  
- Ratio: 111% (still safe!)

PLS drops 27%:
- Collateral now $1.095
- Debt: $1.00
- Ratio: 109.5% (liquidatable)
```

### Revenue Streams

**For the Protocol (not extractive):**
1. Stability fees: 0.5% APY on debt (minimal)
2. Liquidation penalties: Stay in vault (could fund burns)

**For sSunDAI Stakers:**
1. Trading fees: 0.3% per swap on pSunDAI/PLS pool
2. Compounding effect: Reinvested automatically

**For Liquidators:**
1. Liquidation bonus: 2-5% depending on timing
2. MEV opportunities: Front-running liquidations

### Sustainability

**No ongoing costs:**
- ✅ No oracle subscriptions (custom oracle)
- ✅ No keeper infrastructure (permissionless)
- ✅ No governance overhead
- ✅ No admin salaries
- ✅ No marketing budget required

**Self-sustaining through:**
- 📈 Real economic activity (trading volume)
- 📈 Market forces (arbitrage, liquidations)
- 📈 Compounding fees (sSunDAI)

---

## Deployment Addresses

### PulseChain Mainnet

| Contract | Address | Status |
|----------|---------|--------|
| pSunDAI Token | `[TBD]` | ✅ Live |
| pSunDAI Vault v5.6 | `[TBD]` | ✅ Live |
| Oracle v5.1 | `[TBD]` | ✅ Live |
| sSunDAI v1.0 | `[TBD]` | ✅ Live |
| Destiny Vault | `[TBD]` | ✅ Active |
| SunDial Oracle | `[TBD]` | ✅ Active |
| SunDAI Base Token | `[TBD]` | ✅ Live |

### Verified Source Code

All contracts verified on PulseScan:
- [Vault](https://scan.pulsechain.com)
- [Oracle](https://scan.pulsechain.com)
- [sSunDAI](https://scan.pulsechain.com)

---

## For Developers

### Integration Example

```javascript
// Get vault info
const vault = new ethers.Contract(VAULT_ADDRESS, VAULT_ABI, provider);
const info = await vault.vaultInfo(userAddress);

console.log({
  collateral: ethers.formatEther(info.collateral) + ' PLS',
  debt: ethers.formatEther(info.debt) + ' pSunDAI',
  ratio: (Number(info.ratio) / 100).toFixed(2) + '%',
  price: ethers.formatUnits(info.price, 18) + ' USD/PLS',
  mintable: ethers.formatEther(info.mintable) + ' pSunDAI'
});

// Check if vault can be liquidated
const canLiquidate = await vault.canLiquidate(userAddress);

// Get liquidation info
const liquidationInfo = await vault.liquidationInfo(userAddress);
```

### Monitoring Best Practices

**For Vault Owners:**
- Monitor collateral ratio every hour
- Set alerts for ratio < 130%
- Keep ratio above 150% for safety
- Watch oracle status (confirmation periods)

**For Liquidators:**
- Monitor all vaults for ratio < 110%
- Calculate profitability considering gas
- Watch for confirmation period endings
- Use flash loans for capital efficiency

**For LP Providers:**
- Monitor sSunDAI exchange rate
- Harvest when TVL > $10k (economic)
- Track trading volume for APY estimates
- Check impermanent loss vs. fees earned

---

## Community & Development

### Open Source

All contracts are MIT licensed and fully open source.

### Security

- ✅ Battle-tested patterns (MakerDAO-inspired)
- ✅ Multiple safety layers
- ✅ Extensive testing
- ✅ Community reviewed
- ✅ Time-tested on mainnet

**Bug Bounties:** Responsible disclosure encouraged

**Immutability Notice:** Bugs cannot be patched. Deploy improved versions if needed.

### Support

- Website: [sundaitoken.com](https://www.sundaitoken.com)
- Twitter: [@ELITE_Team6](https://twitter.com/ELITE_Team6)
- GitHub: [github.com/ELITE-TEAM6](https://github.com/ELITE-TEAM6)

---

## FAQ

**Q: Can the contracts be upgraded?**  
A: No. They are completely immutable. This is a feature, not a bug.

**Q: What if there's a bug?**  
A: Cannot be patched. Would require deploying new version. This is the price of true decentralization.

**Q: Who controls the protocol?**  
A: No one. It's purely autonomous, controlled only by economic incentives.

**Q: What happens if PLS goes to zero?**  
A: Vault would become underwater. Liquidators would capture remaining value. pSunDAI would depeg. This is the risk of any collateralized system.

**Q: Why 150% instead of 110% minimum?**  
A: Conservative buffer allows users peace of mind and reduces liquidation frequency. 110% minimum would be capital efficient but stressful.

**Q: Can I get liquidated during a flash crash?**  
A: No! Oracle has 4-hour confirmation for large drops. Flash crashes are completely ignored.

**Q: What's the max I can mint?**  
A: (Collateral Value USD × 100) / 150 = Max pSunDAI mintable

**Q: Do I need to poke the oracle?**  
A: No. Vault auto-pokes when needed. Manual pokes optional (30min cooldown).

**Q: Is this audited?**  
A: Community reviewed, not formally audited. Use at your own risk.

**Q: How does this compare to Liquid Loans?**  
A: More conservative (150% vs 110%), but safer. Different tradeoffs. See comparison docs.

---

## Conclusion

SunDAI represents a new paradigm: **financial infrastructure as immutable code**.

Like Bitcoin's supply schedule, these contracts run based on math and economic incentives, not human decisions.

**The sun has risen on truly autonomous stable assets.**

---

**© 2024-2026 ELITE TEAM6. MIT License. No Rights Reserved (Open Source).**

*Built by the people, for the people, owned by no one.*

---

## Appendix: Mathematical Proofs

### Liquidation Profitability

```
Given:
- Vault collateral: C (in PLS)
- Vault debt: D (in pSunDAI)  
- PLS price: P (in USD)
- Ratio: R = (C × P) / D × 100

Liquidation condition: R < 110

Liquidator repays: D_repay (20% to 100% of D)
Liquidator receives: Collateral worth D_repay × (1 + bonus)

Where bonus ranges from 2% to 5% based on time:
bonus(t) = 0.02 + 0.03 × min(t / 10800, 1)

At t=0: bonus = 2%
At t=3h: bonus = 5%

Profit = D_repay × bonus
```

### Peg Stability Equilibrium

```
Arbitrage forces:

If pSunDAI > $1:
  Profit = (Price_pSunDAI - 1) × Amount
  Action: Mint + Sell
  Result: Supply ↑, Price ↓

If pSunDAI < $1:
  Profit = (1 - Price_pSunDAI) × Amount
  Action: Buy + Repay
  Result: Supply ↓, Price ↑

Equilibrium: Price_pSunDAI = $1 ± gas costs
```

### Oracle Step Convergence

```
Given:
- Current price: P_current
- Target price: P_target  
- Step size: s = 5% (down) or 10% (up)
- Step interval: 30 minutes

Convergence time = Step_interval × ceil(log(P_target/P_current) / log(1-s))

Example:
P_current = $0.000020
P_target = $0.000014  
Divergence = -30%
Steps = ceil(log(0.7) / log(0.95)) = 8 steps
Time = 8 × 30min = 4 hours stepping time
Total = 4h confirmation + 4h stepping = 8 hours
```

---

**Documentation Version**: 1.0 (Accurate to deployed contracts)  
**Last Updated**: February 2026  
**Contracts Version**: v5.6 Vault, v5.1 Oracle, v1.0 sSunDAI
