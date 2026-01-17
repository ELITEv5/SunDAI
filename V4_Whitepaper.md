# SunDAI: A Peer-to-Peer Autonomous Stable Asset for Decentralized Finance  
**Author:** ELITE TEAM6  
**Date:** October 31 2025  

---

### Abstract  
A purely peer-to-protocol stable asset system allows value to be issued, collateralized, and redeemed without reliance on banks, custodians, or governance.  
SunDAI introduces an **autonomous stable asset (ASA)** model where equilibrium emerges from algorithmic collateralization and a *creeping oracle* that self-adjusts to market conditions.  
Stability arises from deterministic convergence, not fiat backing or discretionary governance.  
Each SunDAI token (pSunDAI) is minted against native crypto collateral (e.g., PLS, WPLS, wETH, HEX, SOL, BNB) held in immutable vaults.  
The system’s oracle enforces stability through *gradual, bounded adaptation* — ensuring smooth convergence to real value under volatility, without human input.  

---

### 1. Introduction  
Centralized stablecoins bind digital freedom to the liabilities of financial intermediaries.  
Their issuers possess unilateral control to freeze, censor, or redefine balances through policy.  
In contrast, **SunDAI** operates as an *autonomous stable asset*: a self-balancing system that maintains solvency, collateralization, and peg dynamics purely through immutable logic.  

Where Bitcoin detached money from banks, SunDAI detaches *stability* from custodianship.  
No multisigs, no oracles controlled by councils — just code that regulates its own price discovery through a mathematically constrained “creep.”  

---

### 2. System Overview  
Each participant controls a **Vault** that issues **pSunDAI** by locking supported collateral.

\[
\text{Collateral Ratio} = \frac{C \times P}{D} \times 100
\]

Where *C* = collateral, *P* = oracle-derived normalized price, *D* = outstanding pSunDAI debt.  

- Minimum Ratio: **150%**  
- Liquidation Threshold: **110%**  

The Vault interacts directly with the **Creeping Oracle**, ensuring that even under rapid market shifts, pricing transitions remain smooth and predictable.  

---

### 3. Creeping Oracle Mechanism  
The **Creeping Oracle** is SunDAI’s defining feature — a self-adjusting, volatility-resistant feed that regulates the perceived value of collateral.  

Instead of immediately mirroring spot prices, the oracle “creeps” toward market truth at a controlled rate.  
This mitigates shocks, manipulations, and flash loan distortions, providing a stable foundation for minting.

#### Mechanism

| Parameter | Description |
|------------|-------------|
| `liveRate` | Instantaneous market rate (from pair/DEX feed) |
| `baseRate` | Last accepted stable rate |
| `clamp%` | Max deviation allowed per update cycle (default 10%) |
| `creepStep` | Fractional progression toward target (default 0.02 = 2%) |

#### Algorithm
if |liveRate - baseRate| < clamp%:
baseRate = liveRate
else:
baseRate += (liveRate - baseRate) * creepStep

yaml
Copy code

This algorithm ensures:
- **Continuity:** The rate never jumps outside a defined safety envelope.  
- **Integrity:** Manipulated price spikes cannot instantly affect the system.  
- **Adaptivity:** The oracle slowly synchronizes with legitimate long-term shifts.  

In practice, the Oracle behaves like a dampened spring — absorbing shocks and converging smoothly to equilibrium.

---

### 4. Autonomous Interest and Stability Fee  
A time-weighted stability fee of 0.5% per year accrues on outstanding debt:

\[
F = D \times \frac{r \times t}{T}
\]

Where *r* = 50 bps annual rate, *T* = 31,536,000 seconds.  
Accrual is autonomous — calculated on-demand during interactions — eliminating the need for external keepers.

---

### 5. Liquidation and Recovery  
When a Vault’s collateral ratio \( R < 110\% \), liquidation is triggered.  
Liquidators burn SunDAI to repay vault debt and receive collateral plus a dynamic reward (2–5%) determined by time elapsed since liquidation trigger.  

Because the Creeping Oracle dampens short-term price dips, unnecessary liquidations due to temporary volatility are minimized — improving capital efficiency and fairness.

---

### 6. System Health  
System-wide solvency is measured as:

\[
\text{System Health} = \frac{C_t \times P}{D_t} \times 100
\]

- Minting halts when health < 130%.  
- Oracle clamp prevents destabilizing over-minting under rapid price movement.  
- Vaults individually enforce 150% minimum ratios.  

Together, these maintain deterministic solvency and resilience even under partial oracle liveness or isolated volatility events.

---

### 7. Autonomy and Governance  
SunDAI is *governance-free*.  
All contracts — **pSunDAI**, **Vault**, and **CreepingOracle** — are immutable and non-upgradeable.  
No admin keys exist post-deployment.  
Parameters (collateral ratios, clamp%, creepStep) are hardcoded constants, not changeable after genesis.  

The system thus operates as a **public, autonomous utility**, not an organization — it cannot be seized, modified, or censored.  

---

### 8. Economic Incentives  
| Role | Function | Incentive |
|------|-----------|-----------|
| **Borrower** | Mints pSunDAI against collateral | Access to on-chain liquidity |
| **Holder** | Stores or transacts in stable unit | Stability and censorship resistance |
| **Liquidator** | Maintains solvency by repaying undercollateralized vaults | Earns liquidation bonus |
| **Arbitrageur** | Aligns SunDAI price across markets | Captures exchange spreads |

All interactions occur voluntarily and symmetrically, producing an emergent balance of forces — stability from incentives, not authority.

---

### 9. Security Considerations  
Key security primitives:  

- **±10% Clamp:** Prevents oracle shocks and manipulation.  
- **CreepStep Damping:** Limits rate of change per update.  
- **Reentrancy Guard:** Protects mint/burn functions from nested calls.  
- **Immutable Linkage:** Token, Vault, and Oracle are one-time linked.  
- **No Admin Calls:** Eliminates upgrade or freeze vectors.  
- **On-Chain Accounting:** No off-chain feeds or multi-sigs.  

These ensure SunDAI cannot be paused, confiscated, or diluted by any actor.

---

### 10. Cross-Chain Perspective  
Each SunDAI deployment is **native** to its host chain — PulseChain, Ethereum, BNB Chain, or Solana.  
Each system uses its **own collateral base** and independent oracle feed.  
This preserves economic sovereignty while enabling *cross-chain arbitrage alignment* via DEX liquidity or bridge-based swaps.  

No wrapped fiat tokens or centralized price anchors are required; parity emerges algorithmically.

---

### 11. Use Cases  
- Collateralized borrowing without intermediaries  
- Autonomous decentralized savings and payments  
- Base liquidity for DeFi protocols needing censorship-free stability  
- Synthetic accounting unit for decentralized treasuries and DAOs  
- Inflation-hedged store of value within crypto-native ecosystems  

---

### 12. Conclusion  
SunDAI represents the evolution of stability in decentralized finance — from custodial fiat-backing to autonomous equilibrium.  
Through its **Creeping Oracle**, the system internalizes volatility rather than reacting to it, achieving natural peg convergence over time.  
It is not “stable” by force, but *stable by design*.  

> “True stability is not static — it’s controlled motion.”  
> — *ELITE TEAM6*

---
UPDATED November 21,2025 with the addition of the PLSX4 "Creeping" Oracle. A more forgiving mechanism to follow price and mitigate risk of drastic price swings. 
*(SunDAI “Creeping ASA” Whitepaper — October 31 2025)*
