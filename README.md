
# Smart Contract PoC
A collection of my ongoing Web3 security research focused on Solidity smart contract vulnerabilities, exploit development, and reproducible Foundry Proof-of-Concepts (PoCs).

The goal of this repository is to study real-world smart contract security issues by:

* analyzing vulnerable Solidity code
* identifying the root cause
* reproducing vulnerabilities with Foundry
* developing exploit PoCs
* documenting impact and mitigation
* enhancing my Web3 security skills/knowledge

## Repository Structure

```text
web3-security-pocs/
│
├── src/                  # Vulnerable Solidity contracts
├── test/                 # Foundry PoCs / exploit tests
├── writeups/             # Detailed vulnerability write-ups
├── foundry.toml          # Foundry project configuration
└── README.md
```

Each research entry generally contains:

```text
Vulnerable Contract
        ↓
Foundry PoC
        ↓
Exploit Reproduction
        ↓
Technical Write-up
        ↓
Recommended Mitigation
```

## Research Areas

Current and planned topics include:

* Signature replay
* Reentrancy
* Access control
* Oracle manipulation
* Price manipulation
* Flash-loan attacks
* Storage collisions
* Proxy and upgradeability vulnerabilities
* ERC-20 issues
* ERC-4626 vault vulnerabilities
* Liquidation and accounting bugs
* DeFi logic errors
* Governance vulnerabilities
* Integer / precision / rounding issues
* Authentication and authorization flaws
* And Others

## Running the PoCs

This repository uses [Foundry](https://book.getfoundry.sh/).

Clone the repository:

```bash
git clone https://github.com/id490/smart-contract-PoC.git
cd smart-contract-PoC
```

Install dependencies:

```bash
forge install
```

Build:

```bash
forge build
```

Run all tests:

```bash
forge test
```

Run a specific PoC:

```bash
forge test --match-test testAnythingYouWouldLike -vvvv
```

The `-vvvv` flag provides detailed EVM execution traces that can help understand how the vulnerability is exploited.

## Research Format

Each vulnerability is documented with:

1. Vulnerability summary
2. Vulnerable code
3. Root cause
4. Attack scenario
5. Proof-of-Concept
6. Impact
7. Recommended mitigation
8. Security considerations

## Disclaimer

This repository is intended for educational purposes, security research, and responsible vulnerability analysis.
DO NOT USE PROVIDED SOLIDITY CODES IN PRODUCTION !

The PoCs are designed to demonstrate vulnerabilities in controlled environments. Do not use them to attack systems or contracts without authorization.


