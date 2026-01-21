# SunDAI Autonomous Stable Asset (ASA) Protocol

**Copyright (c) 2025 ELITE LABS LLC**  
**All rights reserved.**

**Website:** https://www.sundaitoken.com  
**Contact:** dev@sundaitoken.com

---

## License

Licensed under the MIT License.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

---

## ⚠️ IMPORTANT DISCLAIMERS

### Financial Risk Warning
SunDAI is experimental financial software. By using this protocol, you acknowledge and accept the following risks:

- **Smart Contract Risk:** The contracts are immutable and cannot be upgraded. Any bugs or vulnerabilities discovered after deployment cannot be fixed.
- **Oracle Risk:** Price feeds depend on external DEX liquidity and may be subject to manipulation, flash crashes, or technical failures.
- **Liquidation Risk:** Your collateral can be liquidated if your vault health falls below 110%. You are responsible for monitoring your position.
- **Market Risk:** Cryptocurrency prices are highly volatile. PLS price movements can trigger liquidations even with healthy ratios.
- **Total Loss Risk:** You may lose all deposited collateral under extreme market conditions.

### No Warranty or Guarantees
- The protocol is provided "as-is" with no guarantees of uptime, peg stability, or functionality.
- ELITE LABS LLC provides no warranties, express or implied, regarding the security, reliability, or suitability of this software.
- The protocol has not been audited by third-party security firms.

### Not Financial Advice
- This software is for informational and experimental purposes only.
- Nothing in this repository constitutes financial, investment, legal, or tax advice.
- Consult with qualified professionals before making any financial decisions.

### Regulatory Compliance
- Users are responsible for complying with all applicable laws and regulations in their jurisdiction.
- This protocol may not be available or legal in certain jurisdictions.
- ELITE LABS LLC makes no representations regarding the legal status of this protocol in any jurisdiction.

### No Affiliation
- SunDAI is not affiliated with, endorsed by, or connected to any government, financial institution, or regulatory body.
- References to "stable" or "stablecoin" describe intended algorithmic behavior, not regulatory status or guarantees.

### Immutability Notice
- **The deployed smart contracts are immutable and cannot be paused, upgraded, or modified by anyone, including ELITE LABS LLC.**
- Once deployed, the protocol operates autonomously without admin control.
- There is no emergency shutdown mechanism or admin recovery function.

### User Responsibility
By interacting with this protocol, you acknowledge that:
- You understand how decentralized finance (DeFi) protocols work
- You have read and understand the technical documentation
- You are solely responsible for the security of your private keys and wallet
- You accept full responsibility for any losses incurred
- You will not hold ELITE LABS LLC liable for any damages or losses

---

## Security

### Bug Bounty
We encourage responsible disclosure of security vulnerabilities. Contact: dev@sundaitoken.com

### Known Limitations
- Oracle price updates require user interactions or manual poke() calls
- 4-hour confirmation period on large price drops (intended anti-manipulation feature)
- Interest accrues on debt continuously and can affect liquidation thresholds
- First withdrawal after deposit has 5-minute cooldown (anti-attack feature)

---

## Technical Documentation

See [WHITEPAPER.md](./WHITEPAPER.md) for complete technical specifications and economic model details.

---

## Contract Addresses (PulseChain Mainnet)

| Contract | Address | Verified |
|----------|---------|----------|
| pSunDAI Token | `0x5529c1cb179b2c256501031adCDAfC22D9c6d236` | [✓](https://scan.pulsechain.com/address/0x5529c1cb179b2c256501031adCDAfC22D9c6d236) |
| Vault v5.6 | `0x789472Ef7fa74cB8898Ed38cAa5d18f4D49EcC6d` | [✓](https://scan.pulsechain.com/address/0x789472Ef7fa74cB8898Ed38cAa5d18f4D49EcC6d) |
| Oracle v5.1 | `0xC19C8201701585D9087F261eaCd3Ee3345251Da3` | [✓](https://scan.pulsechain.com/address/0xC19C8201701585D9087F261eaCd3Ee3345251Da3) |

⚠️ **Always verify contract addresses before interacting. ELITE LABS LLC will never ask for your private keys or seed phrase.**

---

**USE AT YOUR OWN RISK**
