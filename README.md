# SunDAI ASA — Autonomous Stable Asset
> **The World's First Fully Autonomous Stable Asset Vault.**  
> Built on PulseChain. Designed for every chain.  
> Developed by **ELITE TEAM6**.

---

## Overview
**SunDAI ASA** is a completely autonomous, immutable vault system that lets anyone mint **pSunDAI** — a decentralized, USD-pegged stable asset — by locking PLS as collateral.

No admins. No keepers. No governance. No upgrades.  
Just pure math, on-chain collateral, and self-healing code.

**SunDAI runs forever.**

---

## Key Features (v5.6 Immortal Edition)

| Feature                        | Description                                                                                       |
|--------------------------------|---------------------------------------------------------------------------------------------------|
| Immutable Vaults               | Every user owns a personal, keyless vault. No one can pause, freeze, or rug it.                  |
| Hybrid Oracle (v5.1)           | Median-filtered TWAP + spot hybrid across 5 PulseX stable pools with dual-layer protection.      |
| Dual Volatility Protection     | Oracle confirmation system (4h/1h) + vault-level ±10% clamp with asymmetric cooldown.           |
| Full Autonomy                  | No admin keys, no pausable functions, no upgrades. 100% immortal.                                |
| 0.5% Annual Stability Fee      | Accrues only when you interact — fair, gas-efficient, and automatic.                             |
| 150% Collateral Ratio          | Safe over-collateralization. Liquidation at 110%.                                                 |
| Dynamic Liquidation Auctions   | 2%–5% bonus, time-weighted. Anyone can liquidate unsafe vaults.                                  |
| User-Controlled Recovery       | Users can recover collateral after 30 days if debt is zero (no admin emergency withdrawal).      |
| One-Click UX                   | Deposit+Mint, Repay+Auto-Withdraw, Repay to Health, Mint Max, Withdraw Max Safe — all in one click. |
| Chain-Agnostic Design          | Ready for PLS, wETH, HEX, and any EVM chain.                                                     |

---

## Live Contracts (v5.6 Immortal Edition — January 2026)

| Contract           | Address                                    | Explorer Link |
|--------------------|--------------------------------------------|---------------|
| **pSunDAI Token**  | `0x5529c1cb179b2c256501031adCDAfC22D9c6d236` | [View](https://scan.pulsechain.com/address/0x5529c1cb179b2c256501031adCDAfC22D9c6d236) |
| **Vault (v5.6)**   | `0x789472Ef7fa74cB8898Ed38cAa5d18f4D49EcC6d` | [View](https://scan.pulsechain.com/address/0x789472Ef7fa74cB8898Ed38cAa5d18f4D49EcC6d) |
| **Hybrid Oracle (v5.1)** | `0xC19C8201701585D9087F261eaCd3Ee3345251Da3` | [View](https://scan.pulsechain.com/address/0xC19C8201701585D9087F261eaCd3Ee3345251Da3) |

All contracts are **verified** and **immutable**.

---

## Security & Autonomy
SunDAI v5.6 Immortal Edition is engineered to survive anything:
- No upgradeability
- No owner functions
- No emergency pauses (users control their own recovery after 30 days with zero debt)
- Even if the oracle stops forever, you can always repay and withdraw your collateral
- Verified source code on PulseScan
- Most advanced dual-layer oracle protection system ever deployed in autonomous DeFi

Audited logic. Battle-tested on mainnet.

---

## Economic Model (Immutable Parameters)
- **Collateral Ratio:** 150% (minting)
- **Liquidation Threshold:** 110%
- **Stability Fee:** 0.5% per year (auto-accrued)
- **Liquidation Bonus:** 2%–5% (time-weighted over 3-hour auction window)
- **Global Health Halt:** Minting pauses if system ratio < 130%

No votes. No changes. Ever.

---

## Example Workflow
1. Connect wallet → see live PLS price
2. Enter $ amount → **One-Click Deposit + Auto-Mint** (155% buffer)
3. Use pSunDAI anywhere on PulseChain
4. Need to exit? **Repay & Auto-Withdraw Excess PLS** in one click
5. Want perfect safety? Click **"Repay to Safe Health (150%+)"**

Zero math. Zero stress.

---

## Advanced Oracle System (v5.1 + v5.6 Dual-Layer Protection)

The Hybrid Oracle v5.1 + Vault v5.6 represent the most sophisticated price protection system in DeFi with dual-layer defense:

### Oracle Layer (v5.1 - Confirmation System)
- **Flash crash immunity**: 4-hour confirmation period before accepting price drops
- **Responsive to pumps**: 1-hour confirmation period for upward price movements
- **Progressive stepping**: After confirmation, steps 5% (down) or 10% (up) every 30 min toward target
- **Smart recovery**: Cancels confirmation if price recovers, updates immediately
- **Anti-grief protection**: Manual `poke()` rate-limited to once per 30 minutes
- **Median aggregation**: Combines 5 major PulseX pairs (DAI v1/v2, USDC v1/v2, USDT)

### Vault Layer (v5.6 - Volatility Guard)
- **Price clamp**: ±10% maximum movement per update
- **Asymmetric cooldown**: 4h for dumps (safety), 1h for pumps (responsiveness)  
- **Instant recovery**: Clamp lifts immediately when price returns to normal range
- **Rate-limit resistant**: Uses `peekPriceView()` to avoid oracle cooldown issues

### Combined Effect
- **Flash crashes (<4h)**: Completely ignored, zero liquidation risk
- **Real market drops (>4h)**: 4h confirm + gradual stepping = safe, measured response
- **Real market pumps (>1h)**: 1h confirm + faster stepping = quicker value recognition
- **Oracle failures**: Vault continues operating with last known good price
- **24h fallback**: Emergency price recovery from live pairs if oracle becomes stale

---

## Official Links
- **Website & Vault UI:** https://www.sundaitoken.com
- **Live Dashboard:** https://www.sundaitoken.com
- **GitHub:** https://github.com/ELITEv5/SunDAI
- **Whitepaper:** https://github.com/ELITEv5/SunDAI/blob/main/SunDAI_Whitepaper_2025.md
- **Developers:** dev@sundaitoken.com

---

## Philosophy
**"Built for Freedom."**  
No banks. No custodians. No permission.  
Only math, code, and collateral.

Where Bitcoin freed money from banks,  
SunDAI frees stability from permission.

The sun has risen. And it will never set.

---

## License
MIT License  
Copyright © 2026 ELITE TEAM6  
SunDAI Autonomous Stable Asset (ASA)  
Website: https://www.sundaitoken.com  
Contact: dev@sundaitoken.com

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

---

**ELITE TEAM6** — We don't build protocols. We build eternity.
