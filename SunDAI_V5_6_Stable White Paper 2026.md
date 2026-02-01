# SunDAI: A Peer-to-Peer Autonomous Stable Asset for Decentralized Finance

**Author:** ELITE TEAM6  
**Version:** v5.6 Immortal Edition  
**Date:** January 2026  

---

### Abstract  
SunDAI is a first in a new class we call a **fully autonomous stable asset (ASA)** — a decentralized, crypto-collateralized stable asset targeting a $1 unit of value minted against native crypto collateral (PLS, wETH, HEX, etc.) inside **immutable, ownerless vaults**.  

No custodians. No governance. No admin keys. No upgrades.  
Stability is enforced by pure mathematics, self-healing oracle consensus, and dual-layer volatility protection — not human discretion.  

SunDAI v5.6 Immortal Edition introduces the most advanced oracle and volatility guard system ever deployed in DeFi, ensuring both **maximum safety** and **maximum fluidity** in all market conditions.

---

### 1. Introduction  
Centralized stablecoins remain the Achilles' heel of DeFi. SunDAI eliminates that weakness by becoming the first stable asset that is **truly peer-to-protocol** — no company, no multisig, no off-chain dependency.  

Like Bitcoin removed banks from money, SunDAI removes custodians from stability.

---

### 2. System Overview (v5.6)  
Each user owns an immutable personal vault.  
Deposit collateral → mint pSunDAI → repay → withdraw.  

All operations are executed atomically by the contract itself.

$$
\text{Collateral Ratio} = \frac{C \times P}{D} \times 100
$$

- Minimum ratio: **150%**  
- Liquidation trigger: **< 110%**  
- Global minting halt: **< 130% system health**

---

### 3. Dual-Layer Oracle Protection — The Self-Healing Brain  

SunDAI v5.6 employs a **revolutionary dual-layer price protection system** combining Oracle v5.1's confirmation mechanism with Vault v5.6's volatility guard.

#### 3.1 Oracle Layer (v5.1) — Confirmation System

**Median-filtered TWAP + spot hybrid** across five major PulseX stable pools (USDC v1/v2, DAI v1/v2, USDT).

**Key features:**
- **Flash crash immunity**: 4-hour confirmation period before accepting price drops
- **Responsive pumps**: 1-hour confirmation period for upward price movements  
- **Progressive stepping**: After confirmation passes, price steps toward target:
  - Downward moves: 5% per step (every 30 minutes)
  - Upward moves: 10% per step (every 30 minutes)
- **Smart recovery**: If price returns to normal range during confirmation, cancels immediately and updates
- **Anti-grief protection**: Manual `poke()` rate-limited to once per 30 minutes
- **Instant moves**: Price changes under 3% accepted immediately (no confirmation needed)

#### 3.2 Vault Layer (v5.6) — Volatility Guard

**Additional protection at the vault level:**
- **±10% price clamp**: Maximum price movement per vault interaction
- **Asymmetric cooldown**:
  - Price dumps (↓): 4-hour cooldown (prevents over-minting in crashes)
  - Price pumps (↑): 1-hour cooldown (faster response to positive moves)
- **Instant recovery**: If price moves back inside ±10% normal range during cooldown → clamp lifted immediately
- **Rate-limit resistant**: Uses `peekPriceView()` to avoid triggering oracle's poke cooldown
- **Stale-price fallback**: Uses last valid price if oracle lags (guarantees continuity)

#### 3.3 Combined Protection Timeline

**Flash crashes (< 4 hours):**  
Complete protection. Price ignored entirely. Zero liquidation risk.

**Real market drops (> 4 hours):**  
- Oracle: 4h confirmation → confirmed → steps 5% every 30min
- Vault: Additional ±10% clamp with 4h cooldown
- **Total**: Safe, measured response preventing panic liquidations

**Real market pumps (> 1 hour):**  
- Oracle: 1h confirmation → confirmed → steps 10% every 30min  
- Vault: Additional ±10% clamp with 1h cooldown
- **Total**: Faster recognition of value increases

**Oracle failure scenario:**  
- Vault continues operating with last known good price
- 24-hour fallback to live pair prices in oracle
- Users can always repay and withdraw

#### 3.4 No Keeper Dependency

Unlike v5.5 and earlier versions, v5.6 **removed automatic `poke()` calls** to prevent rate-limit reverts. The system is designed to function perfectly without any keeper activity:

- Oracle updates when users manually call `poke()` (optional, 30min cooldown)
- Vault uses `peekPriceView()` for all price checks (no update required)
- 24-hour fallback ensures price availability even if nobody pokes
- System remains fully autonomous and censorship-resistant

This is the most sophisticated, multi-layered, attack-resistant oracle system ever shipped in an autonomous stablecoin.

---

### 4. Autonomous Interest & Stability Fee  
0.5% annual fee, accrued proportionally on every user interaction:  
$$
F = D \times \frac{0.005 \times t}{31536000}
$$  
No external triggers. No debt ceiling. Pure time-based accrual.

---

### 5. Liquidation & Recovery  
- Liquidation below **110%**  
- Dynamic bonus: **2% → 5%** over 3-hour auction window  
- Any participant can liquidate — rewards flow to honest arbitrageurs  
- System self-heals without governance intervention

---

### 6. Autonomy & Finality (v5.6 Immortal)  
- **No owner**  
- **No upgradeability**  
- **No pausable functions**  
- **No admin emergency withdrawal**  
- **User-controlled recovery**: Users can recover collateral after 30 days if debt is zero
- All parameters hardcoded forever  

Even if the oracle dies completely, users can always repay and withdraw their collateral.

**SunDAI cannot be shut down, censored, or corrupted.**

---

### 7. Economic Model (Immutable)  

| Parameter                  | Value          |
|----------------------------|----------------|
| Collateral Ratio           | 150%           |
| Liquidation Threshold      | 110%           |
| Stability Fee              | 0.5% per year  |
| Liquidation Bonus          | 2% – 5%        |
| Liquidation Auction        | 3 hours        |
| Global Health Halt         | < 130%         |
| Oracle Confirmation (Down) | 4 hours        |
| Oracle Confirmation (Up)   | 1 hour         |
| Oracle Step Size (Down)    | 5% per 30min   |
| Oracle Step Size (Up)      | 10% per 30min  |
| Vault Price Clamp          | ±10%           |
| Vault Cooldown (Down)      | 4 hours        |
| Vault Cooldown (Up)        | 1 hour         |

No votes. No changes. Ever.

---

### 8. One-Click User Experience (v5.6 UI)  
- Deposit + Auto-Mint (155% buffer)  
- Repay + Auto-Withdraw Excess  
- Repay to Safe Health (150%+)  
- Mint Max / Withdraw Max Safe  
- Real-time oracle health display  

Zero math required.

---

### 9. Security & Resilience  
- ReentrancyGuard + SafeERC20  
- Dual-layer volatility protection (v5.6 + v5.1)  
- Confirmation-based oracle updates (prevents flash exploits)
- Progressive price stepping (prevents shock liquidations)
- Early recovery from clamps  
- Dust forgiveness  
- Verified, immutable source on PulseScan  

SunDAI has no known exploits and is designed to survive black swan events, flash crashes, chain congestion, oracle manipulation attempts, and complete oracle failures.

---

### 10. Cross-Chain Vision  
Each deployment is native to its chain (PLS, ETH, BNB, SOL, etc.).  
Future versions will support multi-collateral (wETH, HEX, etc.) while preserving full autonomy.

---

### 11. Live Contracts — v5.6 Immortal Edition (January 2026)

| Contract           | Address                                    | Explorer |
|--------------------|--------------------------------------------|----------|
| pSunDAI Token      | `0x5529c1cb179b2c256501031adCDAfC22D9c6d236` | [View](https://scan.pulsechain.com/address/0x5529c1cb179b2c256501031adCDAfC22D9c6d236) |
| Vault (v5.6)       | `0x789472Ef7fa74cB8898Ed38cAa5d18f4D49EcC6d` | [View](https://scan.pulsechain.com/address/0x789472Ef7fa74cB8898Ed38cAa5d18f4D49EcC6d) |
| Hybrid Oracle (v5.1) | `0xC19C8201701585D9087F261eaCd3Ee3345251Da3` | [View](https://scan.pulsechain.com/address/0xC19C8201701585D9087F261eaCd3Ee3345251Da3) |

All contracts are **verified** and **immutable**.

---

### 12. Technical Architecture Details

#### 12.1 Oracle Confirmation Flow
```
Market price diverges >3% from current price
    ↓
Oracle starts confirmation timer
    ↓
If price recovers within confirmation period → Cancel, update immediately
    ↓
If confirmation period passes (4h down / 1h up)
    ↓
Begin stepping toward target (5% down / 10% up per 30min)
    ↓
Continue stepping until target reached or new divergence detected
```

#### 12.2 Vault Volatility Guard Flow
```
Vault interaction requires price check
    ↓
Call oracle.peekPriceView() (no rate limit)
    ↓
Compare to last vault price
    ↓
If within ±10% → Accept immediately
    ↓
If outside ±10% → Check cooldown
    ↓
If cooldown active AND price still outside band → Use last price (clamp)
    ↓
If cooldown passed OR price recovered to ±10% band → Accept new price
```

#### 12.3 Protection Against Attack Vectors

**Flash loan attacks**: Impossible. Oracle uses TWAP + confirmation periods.

**Oracle manipulation**: Median of 5 pairs + ±10% clamp + confirmation periods.

**Panic liquidation cascades**: 4-hour confirmation + progressive stepping prevents sudden price drops.

**Grief attacks**: Poke rate limiting (30min) prevents spam.

**Oracle failure**: Vault continues with last known price + 24h fallback.

**Price staleness**: Falls back to live spot median after 24 hours.

---

### 13. Conclusion  
SunDAI v5.6 Immortal Edition is not just another stablecoin.  
It is the **final form** of decentralized stability:  
- Truly autonomous  
- Mathematically enforced  
- Eternally immutable  
- Self-healing under all conditions  
- Dual-layer protection against all known attack vectors

Where Bitcoin freed money from banks,  
SunDAI frees stability from permission.

The sun has risen.  
And it will never set.
 
*(SunDAI Whitepaper — Immortal Edition | January 2026)*

**ELITE TEAM6** — We don't build protocols.  
We build eternity.
