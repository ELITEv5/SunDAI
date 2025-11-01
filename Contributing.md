# 🤝 Contributing to SunDAI ASA

Welcome to the **SunDAI Autonomous Stable Asset (ASA)** project.  
SunDAI is an immutable, autonomous vault protocol built by **ELITE TEAM6**.  
We believe in transparency, open collaboration, and permissionless innovation.

> “Code is law. Freedom is math.” — SunDAI Philosophy

---

## ⚙️ Overview

SunDAI ASA operates as a **fully autonomous DeFi protocol** with immutable vaults, self-healing oracles, and native asset collateralization.  
All contributions should respect the **core design principles** of autonomy, decentralization, and safety.

---

## 🧩 Contribution Guidelines

### 1️⃣ Code Standards
- All contracts must compile under **Solidity ≥0.8.20**.
- Include `// SPDX-License-Identifier: MIT` and copyright notice:
  ```solidity
  // SPDX-License-Identifier: MIT
  // Copyright (c) 2025 ELITE TEAM6
  // SunDAI Autonomous Stable Asset (ASA)
  // Website: https://www.sundaitoken.com
  // Contact: dev@sundaitoken.com
Follow Solidity best practices:

Use ReentrancyGuard on all external state-changing functions.

Prefer immutable for deployment constants.

Minimize gas with inline math (unchecked only when provably safe).

Use explicit revert messages for every require().

2️⃣ Project Structure
Maintain this structure unless improving modularity or readability:

Copy code
contracts/
├── pSunDAI.sol
├── pSunDAIVault_ASA.sol
├── pSunDAIoraclePLSX3.sol
└── interfaces/
    └── IWPLS.sol

docs/
├── whitepaper.pdf
└── overview.md

tests/
└── vault_tests.js
3️⃣ Testing Requirements
All pull requests must include test coverage for new features or changes.

Use Hardhat or Foundry for testing.

Target 100% functional coverage for core logic (minting, collateral ratio, liquidation, oracle behavior).

Simulate edge cases:

Oracle staleness (>24h)

Flash price deviation (>10%)

Liquidation thresholds (110%)

Full repayment and dust clearance

4️⃣ Security Practices
SunDAI prioritizes safety above all else.

🚫 No admin keys

🚫 No upgradeable proxies

🚫 No external dependencies beyond OpenZeppelin stable releases

🚫 No unverified interfaces or oracles

Always consider liveness and user recoverability.
If a feature introduces any form of privileged control, it will not be merged.

5️⃣ Submitting Pull Requests
Fork the repo and create a feature branch:


git checkout -b feature/my-improvement
Commit with clear messages:


git commit -m "feat: add oracle clamp safety"
Push and open a pull request:


git push origin feature/my-improvement
Include:

Description of changes

Security reasoning (why it’s safe and necessary)

Test results or screenshots

6️⃣ Discussions and Ideas
Before starting a major proposal:

Open an Issue tagged [proposal] or [enhancement].

Explain the concept and its impact on autonomy, safety, or efficiency.

Engage with maintainers and contributors for peer review.

🧠 Philosophical Foundation
SunDAI ASA is not governed, owned, or controlled.
It is a living system that balances collateral and debt autonomously.

When contributing, respect the following tenets:

No governance keys.

No mutable parameters.

No human intervention.

Full transparency in all logic paths.

“Autonomy is the highest form of trust.”

🧰 Developer Setup
Install Dependencies

npm install
or


forge install
Compile

npx hardhat compile
Test

npx hardhat test
or with Foundry:


forge test -vv
📜 License
All contributions are released under the MIT License:


MIT License  
Copyright (c) 2025 ELITE TEAM6  
SunDAI Autonomous Stable Asset (ASA)
🌍 Connect
🌞 Website: https://www.sundaitoken.com

🧑‍💻 Developers: dev@sundaitoken.com

🧾 Docs: GitHub Docs Folder

🧠 Philosophy: “No banks. No custodians. Only code.”

Freedom through mathematics — SunDAI, by ELITE TEAM6
