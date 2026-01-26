# ☀️ DESTINY VAULT: Autonomous Collateralization Protocol

> *A deterministic mechanism for converting SunDAI token holders into pSunDAI collateral providers at the $1.00 threshold.*

[![PulseChain](https://img.shields.io/badge/PulseChain-369-ff00ff?style=for-the-badge)](https://pulsechain.com)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.20-363636?style=for-the-badge&logo=solidity)](https://soliditylang.org/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)

---

## Overview

Destiny Vault is a **single-use collateralization mechanism** that activates when SunDAI reaches $1.00. It irreversibly converts all staked assets (SunDAI and LP tokens) into PLS collateral for the pSunDAI minting vault, distributing proportional shares of newly minted pSunDAI to stakers.

**Key Properties:**
- No governance or admin control post-deployment
- Deterministic execution based on oracle price
- Atomic state transitions with safety guarantees
- Pro-rata distribution based on weighted contributions

---

## Technical Architecture

### State Machine

The protocol operates as a linear state machine with five discrete phases:

```
STAKING → IGNITION → SUPERNOVA → REBIRTH → CLAIM
```

**State Transitions:**
- `STAKING`: Open until `oracle.getPrice() >= threshold`
- `IGNITION`: Triggered by `ignite()`, irreversible
- `SUPERNOVA`: Triggered by `supernova()` after ignition
- `REBIRTH`: Triggered by `rebirth()` after supernova
- `CLAIM`: Individual withdrawals after rebirth

### Weight Calculation

User shares are determined by weighted contributions:

```solidity
weight = (sundaiAmount × 1.0) + (plpAmount × 1.5)
share = userWeight / totalWeight
payout = share × totalPayout
```

**Design Rationale:**
- Token-count based weighting (not dollar-value)
- 1.5x multiplier incentivizes LP provision
- Favors large PLP holders (whale-optimized design)
- Creates FOMO dynamics as vault fills

**Economic Implications:**
- Small PLP stakers receive diluted shares relative to dollar value
- Large PLP whales receive fair-to-favorable shares
- SunDAI token stakers receive proportional weight to token count
- Early stakers have advantage before dilution

---

## Protocol Mechanics

### Phase 1: Staking (Pre-Threshold)

**Entry Requirements:**
- Vault unlocked: `oracle.getPrice() < threshold && !ignited`
- User has approved token transfers

**Staking Logic:**
```solidity
function stake(uint256 sundaiAmt, uint256 plpAmt) external {
    // Transfer tokens from user
    sundai.safeTransferFrom(msg.sender, address(this), sundaiAmt);
    plp.safeTransferFrom(msg.sender, address(this), plpAmt);
    
    // Calculate weight
    uint256 newWeight = sundaiAmt + (plpAmt × 15000 / 10000);
    
    // Update state
    stakes[msg.sender].weight += newWeight;
    totalWeight += newWeight;
}
```

**Withdrawal Logic:**
- Only available while unlocked
- Decrements weight proportionally
- Direct token transfer back to user

### Phase 2: Ignition (Asset Liquidation)

**Trigger Condition:**
```solidity
require(oracle.getPrice() >= threshold, "Not at threshold");
```

**Execution Sequence:**

1. **Break LP Tokens**
```solidity
router.removeLiquidity(
    address(sundai),
    address(wpls),
    plpBalance,
    1, 1,  // Min amounts (no slippage protection)
    address(this),
    deadline
);
```
Returns: SunDAI + WPLS

2. **Swap SunDAI → WPLS**
```solidity
router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
    sundaiBalance,
    0,  // Accept any output
    [sundai, wpls],
    address(this),
    deadline
);
```

3. **Unwrap WPLS → PLS**
```solidity
IWPLS(wpls).withdraw(wplsBalance);
```

**Final State:**
- All SunDAI destroyed via swap
- All LP tokens broken and swapped
- 100% PLS native token held

**Critical Design Note:**
Zero slippage protection. Assumes sufficient liquidity or accepts MEV/sandwich risk. Trade-off for simplicity and guaranteed execution.

### Phase 3: Supernova (Collateral Deposit)

**Action:**
```solidity
vault.depositPLS{value: plsBalance}();
```

Transfers all PLS to pSunDAI minting vault as collateral backing.

**Vault Contract Requirements:**
- Must implement `depositPLS() payable`
- Must credit this contract's collateral account
- Must return accurate `maxMintable(address)` values

### Phase 4: Rebirth (pSunDAI Minting)

**Minting Logic:**
```solidity
uint256 maxMint = vault.maxMintable(address(this));
uint256 safeMint = (maxMint × 9000) / 10000;  // 90% safety margin
vault.mint(safeMint);
```

**Safety Margin Rationale:**
- Prevents rounding errors
- Accounts for collateral ratio precision
- Ensures mint succeeds
- 10% buffer against edge cases

**State Update:**
```solidity
totalPayout = actualMinted;  // pSunDAI balance increase
rebirthTriggered = true;
```

### Phase 5: Claim (Distribution)

**Pro-Rata Calculation:**
```solidity
userShare = (totalPayout × userWeight) / totalWeight;
```

**Claim Mechanics:**
- One-time claim per address
- Direct pSunDAI transfer
- No time limit
- Claimed flag prevents double-claim

---

## Oracle Design

**Contract:** SunDial Oracle Simple  
**Address:** `0xa2Bf4FBc3CF16e37550E7571c3816f9AE6c73A4F`

### Architecture

The Simple Oracle calculates SunDAI price by:
1. Reading WPLS price from the pSunDAI 5-pair median oracle
2. Querying SunDAI/WPLS pair reserves
3. Computing SunDAI price: `(WPLS_reserve × WPLS_price) / SunDAI_reserve`

**Data Flow:**
```
pSunDAI 5-Pair Oracle (0xC19C8201...) → WPLS Price → SunDial Simple Oracle → SunDAI Price
```

### pSunDAI 5-Pair Oracle (Upstream)

**Method:** Median aggregation across 5 DEX pairs  
**Update Frequency:** Per-block with cooldown  

**Manipulation Resistance:**
- Median of 5 pairs (not TWAP)
- Requires coordinating manipulation across majority of pairs
- 30-minute cooldown between updates
- Asymmetric delays: 4hr for price drops, 1hr for increases

**Pairs Monitored (for WPLS price):**
1. WPLS/DAI (PulseX)
2. WPLS/USDC (PulseX)
3. WPLS/HEX (PulseX)
4. WPLS/PLSX (PulseX)
5. WPLS/INC (PulseX)

### SunDial Simple Oracle (This Contract)

**Method:** Spot price calculation from single pair  
**Pair:** SunDAI/WPLS (PulseX)  
**Formula:**
```solidity
WPLS_price = pSunDAIOracleV5.getPrice();  // From 5-pair oracle
(reserve_WPLS, reserve_SunDAI) = pair.getReserves();
SunDAI_price = (reserve_WPLS × WPLS_price) / reserve_SunDAI;
```

**Trade-offs:**
- ✅ Simple, gas-efficient
- ✅ Inherits WPLS price manipulation resistance from upstream oracle
- ⚠️ SunDAI/WPLS pair itself vulnerable to flash loans
- ⚠️ No TWAP, no cooldown on SunDAI price calculation
- ⚠️ Single-pair dependency for SunDAI side

**Risk Assessment:**
For Destiny Vault's use case (one-time $1 threshold check), flash loan manipulation is economically unfeasible:
- Attack cost: Manipulate deep liquidity pool to $1
- Attack duration: Must hold through transaction execution
- Attack profit: None (attacker doesn't benefit from vault ignition)
- MEV extraction: More profitable to front-run legitimate ignition

---

## Security Architecture

### Attack Vectors Considered

**1. Oracle Manipulation**
- **Risk:** Flash loan attack on single pair
- **Mitigation:** Median of 5 pairs, cooldown periods
- **Residual Risk:** Coordinated manipulation across 3+ pairs

**2. Front-Running Ignition**
- **Risk:** MEV bot stakes right before $1, dilutes others
- **Mitigation:** None. This is intentional game theory.
- **Design:** Creates urgency to stake early

**3. Sandwich Attacks During Swaps**
- **Risk:** MEV extraction during ignite() swaps
- **Mitigation:** None. Zero slippage protection.
- **Rationale:** Simplicity over optimization

**4. Reentrancy**
- **Risk:** Recursive calls during state changes
- **Mitigation:** OpenZeppelin ReentrancyGuard on all external functions
- **Status:** Protected

**5. Integer Overflow**
- **Risk:** Weight calculation overflow
- **Mitigation:** Solidity 0.8.20 native overflow checks
- **Status:** Protected

### Access Control

**Owner Functions:**
```solidity
setThreshold(uint256)      // Adjust $1 threshold (pre-lock only)
lockThreshold()            // Permanently lock threshold
enableEmergencyExit()      // Enable recovery mode
```

**Public Functions:**
```solidity
ignite()                   // Anyone can trigger when threshold met
supernova()               // Anyone can trigger after ignite
rebirth()                 // Anyone can trigger after supernova
```

**Design Philosophy:**
- Owner can adjust parameters pre-activation
- Ritual execution is permissionless
- No admin control over user funds
- No upgrade path

### Emergency Exit

**Pre-Ignite Recovery:**
Returns original staked tokens (SunDAI + PLP)

**Post-Ignite Recovery:**
Returns pro-rata share of PLS collateral

**Activation Requirements:**
```solidity
require(!supernovaTriggered, "Too late");
require(oracle.getPrice() >= threshold, "Vault not locked");
```

**Use Cases:**
- Critical bug discovered
- Oracle failure
- Community decision to abort
- Regulatory intervention

---

## Gas Optimization

**Design Choices:**

1. **Struct Packing**
```solidity
struct Stake {
    uint256 sundaiAmt;    // 32 bytes
    uint256 plpAmt;       // 32 bytes
    uint256 weight;       // 32 bytes
    bool claimed;         // 1 byte (packed with next struct)
}
```
No optimization. Clarity over gas savings.

2. **No Array Iteration**
- No loops over stakers
- Individual claim pattern
- O(1) complexity for claims

3. **Batch Operations Not Supported**
- No batch stake/withdraw
- Trade-off: Simpler code, slightly higher user gas costs

---

## Deployment Configuration

### Constructor Parameters

```solidity
constructor(
    address _sundai,      // 0x41C6b24019Bd67CC58fe7bb059D532C12356712B
    address _psundai,     // 0x5529c1cb179b2c256501031adCDAfC22D9c6d236
    address _wpls,        // 0xA1077a294dDE1B09bB078844df40758a5D0f9a27
    address _vault,       // 0x789472Ef7fa74cB8898Ed38cAa5d18f4D49EcC6d
    address _router,      // 0x165C3410fC91EF562C50559f7d2289fEbed552d9
    address _pairV1,      // 0xc01e2eDAe9E65950bb5783A6B01DC429Cf3F0eE2
    address _oracle       // 0xa2Bf4FBc3CF16e37550E7571c3816f9AE6c73A4F
)
```

### Immutable Variables

All core addresses set in constructor and immutable:
- Cannot be changed post-deployment
- Gas savings on every read
- Prevents admin rug vectors

### Default Parameters

```solidity
threshold = 1e18;           // $1.00 (18 decimals)
LP_MULTIPLIER_BPS = 15000;  // 1.5x
SAFETY_BPS = 9000;          // 90% of maxMint
```

---

## Testing & Verification

### Test Coverage

**Unit Tests:**
- ✅ Stake/withdraw mechanics
- ✅ Weight calculation edge cases
- ✅ State transition requirements
- ✅ Access control enforcement
- ✅ Emergency exit both phases

**Integration Tests:**
- ✅ Full ritual sequence (stake → ignite → supernova → rebirth → claim)
- ✅ Multi-user scenarios
- ✅ Oracle threshold behavior
- ✅ PLS recovery amounts

**Mainnet Testing:**
- ✅ Deployed to PulseChain
- ✅ Small-scale ignition test successful
- ✅ Supernova collateral deposit verified
- ✅ Rebirth minting executed
- ✅ Claims distributed correctly

### Known Limitations

1. **No Slippage Protection**
   - Ignition swaps accept any output
   - Vulnerable to sandwich attacks
   - Acceptable trade-off for simplicity

2. **Oracle Dependency**
   - Single point of failure
   - Assumes oracle remains functional
   - No fallback price source

3. **Sequential Execution Required**
   - Ignite → Supernova → Rebirth must be manually triggered
   - Funds locked if steps not executed
   - Relies on community participation

4. **Token-Count Weighting**
   - Doesn't account for PLP dollar value
   - Favors large token holders over small high-value LP providers
   - Intentional design (whale-optimized)

---

## Contract Addresses

### PulseChain Mainnet

| Contract | Address | Verified |
|----------|---------|----------|
| **Destiny Vault (Current)** | `0x652137bf4a3CA4c7eb70981b4eB821C4Fd3F11c3` | ✅ |
| SunDAI Token | `0x41C6b24019Bd67CC58fe7bb059D532C12356712B` | ✅ |
| pSunDAI Token | `0x5529c1cb179b2c256501031adCDAfC22D9c6d236` | ✅ |
| pSunDAI Vault v5.6 | `0x789472Ef7fa74cB8898Ed38cAa5d18f4D49EcC6d` | ✅ |
| **SunDial Oracle Simple (Current)** | `0xa2Bf4FBc3CF16e37550E7571c3816f9AE6c73A4F` | ✅ |
| pSunDAI 5-Pair Oracle v5.1 | `0xC19C8201701585D9087F261eaCd3Ee3345251Da3` | ✅ |
| SunDAI/WPLS LP | `0xc01e2eDAe9E65950bb5783A6B01DC429Cf3F0eE2` | ✅ |
| PulseX Router | `0x165C3410fC91EF562C50559f7d2289fEbed552d9` | ✅ |
| WPLS | `0xA1077a294dDE1B09bB078844df40758a5D0f9a27` | ✅ |

### Legacy Contracts (Deprecated)

| Contract | Address | Status |
|----------|---------|--------|
| Destiny Vault (Old) | `0x8738C72c95177C02AB705Ebf8626f30dE6591123` | ⚠️ Deprecated |
| SunDial Oracle Simple (Old) | `0xDA5591A1DE3934B28cB1DE3Ea828606be6473236` | ⚠️ Deprecated |

### Web Interface

**Destiny Vault Interface:** https://elitev5.github.io/SunDAI/Destiny-Vault/

Features:
- PulseChain-themed cosmic nebula background
- Real-time oracle price tracking
- Live vault statistics and user position
- Phase indicators for ritual progression
- One-click execution when conditions met
- Automatic share calculation

---

## Integration Guide

### For Stakers

**Contract Addresses:**
```javascript
const DESTINY_VAULT = '0x652137bf4a3CA4c7eb70981b4eB821C4Fd3F11c3';
const SUNDAI_TOKEN = '0x41C6b24019Bd67CC58fe7bb059D532C12356712B';
const PLP_TOKEN = '0xc01e2eDAe9E65950bb5783A6B01DC429Cf3F0eE2';
const ORACLE = '0xa2Bf4FBc3CF16e37550E7571c3816f9AE6c73A4F';
```

**1. Approve Tokens**
```javascript
const MAX_UINT256 = ethers.constants.MaxUint256;
await sundaiToken.approve(DESTINY_VAULT, MAX_UINT256);
await plpToken.approve(DESTINY_VAULT, MAX_UINT256);
```

**2. Check Vault Status**
```javascript
const isLocked = await destinyVault.isLocked();
const price = await oracle.getPrice();
const threshold = await destinyVault.threshold();
```

**3. Stake Assets**
```javascript
const sundaiAmount = ethers.utils.parseUnits("1000", 18);
const plpAmount = ethers.utils.parseUnits("100", 18);
await destinyVault.stake(sundaiAmount, plpAmount);
```

**4. Query Position**
```javascript
const stake = await destinyVault.stakes(userAddress);
console.log("SunDAI:", ethers.utils.formatUnits(stake.sundaiAmt, 18));
console.log("PLP:", ethers.utils.formatUnits(stake.plpAmt, 18));
console.log("Weight:", ethers.utils.formatUnits(stake.weight, 18));

const totalWeight = await destinyVault.totalWeight();
const sharePercent = (stake.weight / totalWeight) * 100;
```

**5. Execute Ritual (After $1)**
```javascript
// Check if ready
const ignited = await destinyVault.ignited();
if (!ignited) {
    await destinyVault.ignite();
}

const supernovaTriggered = await destinyVault.supernovaTriggered();
if (!supernovaTriggered) {
    await destinyVault.supernova();
}

const rebirthTriggered = await destinyVault.rebirthTriggered();
if (!rebirthTriggered) {
    await destinyVault.rebirth();
}
```

**6. Claim pSunDAI**
```javascript
const totalPayout = await destinyVault.totalPayout();
const userShare = stake.weight.mul(totalPayout).div(totalWeight);
await destinyVault.claim();
```

### For Developers

**Monitoring Events:**
```solidity
event Staked(address indexed user, uint256 sundaiAmt, uint256 plpAmt, uint256 weight);
event Withdrawn(address indexed user, uint256 sundaiAmt, uint256 plpAmt);
event Ignited(uint256 plsRecovered);
event Supernova(uint256 plsDeposited);
event Rebirth(uint256 minted);
event Claimed(address indexed user, uint256 amount);
```

**Reading State:**
```javascript
// Global state
const ignited = await vault.ignited();
const supernovaTriggered = await vault.supernovaTriggered();
const rebirthTriggered = await vault.rebirthTriggered();
const totalWeight = await vault.totalWeight();
const totalPayout = await vault.totalPayout();

// User state
const stake = await vault.stakes(userAddress);
const { sundaiAmt, plpAmt, weight, claimed } = stake;
```

---

## Economic Analysis

### Scenario: 10M PLP vs 1.4M SunDAI

**Assumptions:**
- SunDAI price: $0.0003
- 1.4M SunDAI staked = $420 value
- 10M PLP staked ≈ $3,000 value (estimated)

**Weights:**
```
SunDAI: 1,400,000 × 1.0 = 1,400,000
PLP:   10,000,000 × 1.5 = 15,000,000
Total:                    16,400,000
```

**Shares:**
```
SunDAI stakers: 8.54%
PLP stakers:   91.46%
```

**Result:**
PLP stakers contributed ~87.7% of dollar value, receive 91.46% of payout.  
**Slightly favorable** to PLP, but within reasonable range.

### Scenario: 10K PLP vs 1.4M SunDAI

**Weights:**
```
SunDAI: 1,400,000 × 1.0 = 1,400,000
PLP:       10,000 × 1.5 =     15,000
Total:                    1,415,000
```

**Shares:**
```
SunDAI stakers: 98.94%
PLP stakers:     1.06%
```

**Result:**
PLP stakers contributed ~87.7% of dollar value, receive 1.06% of payout.  
**Heavily unfavorable** to small PLP stakers.

**Conclusion:** Token-count weighting creates whale-optimized dynamics.

---

## Comparison to Alternatives

### vs. MakerDAO CDP Model

| Feature | Destiny Vault | MakerDAO |
|---------|---------------|----------|
| Collateral Type | Batch conversion at threshold | Individual CDPs |
| Governance | None | MKR token voting |
| Liquidation | N/A (one-time event) | Continuous auction system |
| Entry/Exit | Only pre-threshold | Anytime |
| Immutability | Fully immutable | Upgradeable |

### vs. Liquity Stability Pool

| Feature | Destiny Vault | Liquity |
|---------|---------------|---------|
| Mechanism | Destruction → collateral | Liquidation absorber |
| Profit Source | New minting rights | Liquidation gains |
| Entry Timing | Before $1 only | Anytime |
| LP Bonus | 1.5x weight | None |
| Redemptions | N/A | Against SP first |

### vs. Reflexer RAI

| Feature | Destiny Vault | Reflexer |
|---------|---------------|----------|
| Peg Mechanism | One-time threshold | Continuous PID controller |
| Collateral | PLS (post-conversion) | ETH |
| Governance | None | Governance minimized |
| Complexity | Simple state machine | Advanced control theory |

---

## Future Considerations

### Potential V2 Improvements

**1. Value-Based Weighting**
```solidity
// Get PLP value in SunDAI terms
(uint112 reserve0, uint112 reserve1,) = pair.getReserves();
uint256 totalSupply = pair.totalSupply();
uint256 plpValue = (plpAmount × reserve0 × 2) / totalSupply;
uint256 weight = plpValue × LP_MULTIPLIER_BPS / 10000;
```

**2. Slippage Protection**
```solidity
uint256 minOutput = calculateMinOutput(sundaiBalance, slippageBPS);
router.swapExactTokensForTokens(
    sundaiBalance,
    minOutput,
    path,
    address(this),
    deadline
);
```

**3. Automated Execution**
- Chainlink Keepers integration
- Auto-trigger ritual steps when conditions met
- Eliminates sequential execution dependency

**4. Multi-Oracle Redundancy**
- Fallback to secondary oracle if primary fails
- Require consensus across multiple sources
- Higher manipulation resistance

### Why These Weren't Implemented

- **Complexity vs. Auditability trade-off**
- **Gas cost considerations**
- **Desire for simplicity and transparency**
- **"Perfect is the enemy of good"**

---

## License

MIT License

Copyright (c) 2025 ELITE TEAM6

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

---

## References

1. OpenZeppelin Contracts v5.0.0 - Security primitives
2. Uniswap V2 Core - AMM mechanics
3. Liquity Protocol - Stability pool design inspiration
4. MakerDAO - CDP collateralization patterns
5. Reflexer RAI - Autonomous stability mechanisms

---

**Built without governance, without admin keys, without venture capital.**

*Pure code. Pure conviction. Pure self-sovereignty.*


### Phase 1: STAKING (Pre-$1)
The vault is open. Believers stake their conviction:
- **SunDAI tokens** - Raw faith in the protocol
- **SunDAI/WPLS LP tokens** - Liquidity providers get 1.5x weight multiplier

Your share = Your weight / Total vault weight

*This determines your portion of the new Sun.*

### Phase 2: IGNITION ($1.00 Reached)
The vault **locks permanently**. No more staking. No more withdrawals.

The ritual begins:
1. All LP tokens are broken → SunDAI + WPLS extracted
2. ALL SunDAI is swapped to WPLS
3. ALL WPLS is unwrapped to pure PLS
4. **Assets are destroyed. Everything becomes PLS collateral.**

*The black hole consumes all matter.*

### Phase 3: SUPERNOVA (Collateral Deposit)
The accumulated PLS is deposited into the **pSunDAI Minting Vault** as collateral.

*The singularity compresses into infinite density.*

### Phase 4: REBIRTH (pSunDAI Minted)
Fresh **pSunDAI** is minted from the deposited collateral.

*From the cosmic fire, a new star is born.*

### Phase 5: CLAIM (Distribution)
Stakers claim their proportional share of the newly minted pSunDAI.

*Believers receive the new Sun.*

---

## 🔥 The Ritual Sequence

```solidity
// 1. Vault locks when SunDAI >= $1
function isLocked() external view returns (bool) {
    uint256 price = oracle.getPrice();
    return (price >= threshold || ignited);
}

// 2. Ignite: Destroy all assets → PLS
function ignite() external nonReentrant notIgnited {
    // Break LP tokens
    // Swap all SunDAI to WPLS
    // Unwrap WPLS to PLS
    // ⚫ Assets consumed
}

// 3. Supernova: Deposit PLS as collateral
function supernova() external nonReentrant {
    vault.depositPLS{value: plsBal}();
    // 💥 Collateral compressed
}

// 4. Rebirth: Mint pSunDAI
function rebirth() external nonReentrant {
    vault.mint(safeMint);
    // ✨ New star born
}

// 5. Claim: Receive your share
function claim() external nonReentrant {
    uint256 share = (totalPayout * userWeight) / totalWeight;
    // ☀️ New Sun distributed
}
```

---

## 📊 The Economics

### Weight Calculation
- **1 SunDAI** = 1.0 weight
- **1 PLP token** = 1.5 weight (bonus for providing liquidity)

**Your pSunDAI share** = `(Your Weight / Total Vault Weight) × 100%`

### Example Scenario
```
Vault Holdings:
- 1,400,000 SunDAI staked
- 10,000,000 PLP staked

Weight Calculation:
- SunDAI weight: 1,400,000 × 1.0 = 1,400,000
- PLP weight: 10,000,000 × 1.5 = 15,000,000
- Total weight: 16,400,000

If you staked 10M PLP:
Your share = 15,000,000 / 16,400,000 = 91.46% of all pSunDAI minted! 🐳
```

### Game Theory
- ⏰ **Early stakers** get larger shares before dilution
- 🐋 **Whales** compete to maximize their position
- 💎 **LP providers** get rewarded with 1.5x multiplier
- 🔒 **No exit after $1** - only true believers remain
- ⚡ **First-mover advantage** - race to stake before ignition

---

## 🛡️ Security Features

### Immutable & Trustless
- ✅ No admin keys after deployment
- ✅ No upgradability
- ✅ No governance tokens
- ✅ No way to rug
- ✅ **Pure self-sovereignty**

### Emergency Exit
If something goes catastrophically wrong before Supernova:
```solidity
function enableEmergencyExit() external onlyOwner
function claimEmergency() external nonReentrant
```

Users can recover:
- **Pre-Ignite**: Original SunDAI + PLP tokens
- **Post-Ignite**: Proportional PLS share

*Safety valve in case of critical failure.*

---

## 📜 Smart Contract Architecture

### Core Contracts
| Contract | Address | Purpose |
|----------|---------|---------|
| **Destiny Vault** | `0x8738C72c95177C02AB705Ebf8626f30dE6591123` | The black hole |
| **SunDAI Token** | `0x41C6b24019Bd67CC58fe7bb059D532C12356712B` | The ascending asset |
| **pSunDAI Token** | `0x5529c1cb179b2c256501031adCDAfC22D9c6d236` | The reborn star |
| **pSunDAI Vault** | `0x789472Ef7fa74cB8898Ed38cAa5d18f4D49EcC6d` | Collateral engine |
| **SunDial Oracle** | `0xDA5591A1DE3934B28cB1DE3Ea828606be6473236` | Price feed (5-pair median) |
| **SunDAI/WPLS PLP** | `0xc01e2eDAe9E65950bb5783A6B01DC429Cf3F0eE2` | Liquidity pair |

### Dependencies
- OpenZeppelin v5.0.0 (SafeERC20, ReentrancyGuard, Ownable)
- Uniswap V2 interfaces (Router, Pair)
- Custom interfaces (pSunDAI Vault, Oracle)

---

## 🚀 Deployment & Usage

### For Stakers

**1. Connect Wallet**
- Interface: https://ipfs.io/ipfs/[YOUR_CID_HERE]
- Network: PulseChain (Chain ID: 369)

**2. Approve Tokens**
First-time stakers need to approve:
```javascript
SunDAI.approve(DESTINY_VAULT, MaxUint256)
PLP.approve(DESTINY_VAULT, MaxUint256)
```

**3. Stake Your Conviction**
```javascript
DestinyVault.stake(sundaiAmount, plpAmount)
```

**4. Wait for $1.00**
Monitor the oracle. When SunDAI >= $1, the vault locks.

**5. Execute The Ritual**
Anyone can trigger the sequence:
```javascript
DestinyVault.ignite()      // Destroy assets
DestinyVault.supernova()   // Deposit collateral
DestinyVault.rebirth()     // Mint pSunDAI
```

**6. Claim Your Share**
```javascript
DestinyVault.claim()
```

---

## 🎨 Visual Interface

The web interface features:
- 🌌 **PulseChain-themed cosmic nebula** background
- 📊 **Real-time price tracking** from SunDial Oracle
- 💎 **Live vault statistics** (total staked, your share %)
- ⚡ **Phase indicators** (Staking → Ignition → Supernova → Rebirth → Claim)
- 🔥 **One-click ritual execution** when conditions are met
- ☀️ **Automatic share calculation** based on your weight

### Color Palette
```css
Hot Pink:     #FF007F
Blue Violet:  #8A2BE2
Indigo:       #4B0082
Deep Pink:    #FF1493
Purple:       #9333EA
Pink:         #DB2777
```

*PulseChain brand colors throughout the cosmic journey.*

---

## ⚠️ Critical Warnings

### THIS IS IRREVERSIBLE

**Once SunDAI reaches $1.00:**
- ⛔ The vault locks forever
- ⛔ You cannot withdraw your assets
- ⛔ Your tokens will be destroyed
- ⛔ Everything becomes PLS collateral
- ⛔ There is no undo button

### Understand The Risks

**Impermanent Loss:**
If you provide LP before staking, you will suffer IL as SunDAI price rises.

**Smart Contract Risk:**
Code is unaudited. Use at your own risk.

**Oracle Dependency:**
The $1 threshold depends on SunDial Oracle accuracy.

**Execution Risk:**
The ritual requires sequential execution. If anyone fails to trigger steps, funds could be stuck.

---

## 🧪 Testing

Contract was tested on PulseChain testnet with successful execution of:
- ✅ Stake/Withdraw cycles
- ✅ Ignite (asset destruction)
- ✅ Supernova (collateral deposit)
- ✅ Rebirth (pSunDAI minting)
- ✅ Claim (distribution)
- ✅ Emergency exit mechanisms

---

## 🏗️ For Developers

### Build & Deploy

```bash
# Install dependencies
npm install @openzeppelin/contracts @uniswap/v2-core @uniswap/v2-periphery

# Compile
npx hardhat compile

# Deploy to PulseChain
npx hardhat run scripts/deploy.js --network pulsechain
```

### Constructor Parameters
```solidity
constructor(
    address _sundai,      // SunDAI token
    address _psundai,     // pSunDAI token
    address _wpls,        // Wrapped PLS
    address _vault,       // pSunDAI Minting Vault
    address _router,      // PulseX Router
    address _pairV1,      // SunDAI/WPLS LP
    address _oracle       // SunDial Oracle
)
```

### Key Functions

**State Queries:**
```solidity
isLocked() → bool                          // Is vault locked?
stakes(address) → Stake                    // Get user's stake
totalWeight() → uint256                    // Total vault weight
totalPayout() → uint256                    // Total pSunDAI to distribute
```

**User Actions:**
```solidity
stake(uint256 sundai, uint256 plp)        // Stake tokens
withdraw(uint256 sundai, uint256 plp)     // Withdraw (pre-$1 only)
claim()                                    // Claim pSunDAI (post-rebirth)
claimEmergency()                           // Emergency exit
```

**Ritual Actions:**
```solidity
ignite()                                   // Step 1: Destroy assets
supernova()                                // Step 2: Deposit collateral
rebirth()                                  // Step 3: Mint pSunDAI
```

---

## 🌟 Philosophy

### Pure Self-Sovereignty

This protocol embodies the principles of **true DeFi**:

- 🔓 **No governance** - Code is law
- 🔑 **No admin keys** - No one controls it
- 💰 **No treasury** - No ongoing funding needed
- 🏛️ **No legal entity** - Open-source software
- ⚖️ **No regulation** - Permissionless and unstoppable

### The Autonomous Path

Unlike traditional stablecoins that rely on:
- ❌ Centralized collateral custodians
- ❌ Governance votes and proposals
- ❌ Trusted oracles and keepers
- ❌ Legal wrappers and compliance

**SunDAI → pSunDAI transformation is:**
- ✅ Fully autonomous
- ✅ Cryptographically guaranteed
- ✅ Trustlessly executed
- ✅ Mathematically deterministic

*When the oracle says $1, the code executes. No human intervention required.*

---

## 🎯 The Vision

**SunDAI** climbs to $1 through:
- Organic adoption
- Meme energy
- Community belief
- Market dynamics

**Destiny Vault** converts that achievement into:
- Permanent collateral backing
- A new autonomous stablecoin (pSunDAI)
- Proportional rewards for believers
- A proof of commitment

**pSunDAI** inherits:
- Battle-tested vault mechanics
- Deep PLS collateral reserves
- Proven liquidation systems
- Autonomous stability

---

## 📚 Resources

### Official Links
- **Web Interface:** https://ipfs.io/ipfs/[YOUR_CID]
- **Contract Explorer:** https://scan.pulsechain.com/address/0x8738C72c95177C02AB705Ebf8626f30dE6591123
- **Buy SunDAI:** https://libertyswap.finance/
- **Mint pSunDAI:** https://ipfs.io/ipfs/bafybeibirjbinj5j2sdar7jvu4qjxbm6rdskuhraioyfe2gqgazmgpry7q/

### Documentation
- SunDAI Whitepaper: [Link]
- pSunDAI Documentation: [Link]
- Oracle Design: 5-pair median aggregation
- Vault Mechanics: Battle-tested liquidation system

### Community
- Telegram: [Link]
- Twitter: [Link]
- Discord: [Link]

---

## ⚖️ License

MIT License - Use at your own risk

---

## 🙏 Acknowledgments

Built by **ELITE TEAM6** with:
- Pure conviction in autonomous systems
- Zero venture capital funding
- Complete regulatory resistance
- Absolute self-sovereignty

*No ICO. No presale. No governance token. No bullshit.*

---

## 💀 Disclaimer

**THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.**

By using Destiny Vault, you acknowledge:
- You understand the irreversible nature of the protocol
- You accept full responsibility for your actions
- You are not relying on any promises or guarantees
- You could lose all staked assets
- This is experimental DeFi technology
- No one is liable for any losses

**This is not financial advice. This is a cosmic ritual.**

---

<div align="center">

### ⚫ → 🔥 → 💥 → ✨ → ☀️

**The black hole awaits. Only commit what you're willing to see destroyed and reborn.**

*Made with 🖤 on PulseChain*

</div>
