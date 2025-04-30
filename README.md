# 🗳️ Delegato

**Delegato** is a decentralized proxy voting platform designed to empower shareholders to securely delegate their voting rights. Built on the **Stacks blockchain**, Delegato ensures transparent, tamper-proof governance and seamless voting delegation using smart contracts and Clarity.

---

## 🔍 Overview

In traditional shareholder governance, voting can be inefficient, opaque, and inaccessible to smaller stakeholders. **Delegato** reimagines proxy voting using decentralized, trustless infrastructure, ensuring:

- **Secure delegation** of voting rights to trusted proxies.
- **Transparent recording** of all votes and delegations on-chain.
- **Tamper-resistant governance** through Clarity smart contracts.
- **Trustless execution** without third-party intermediaries.

---

## 🏗 Architecture

- **Frontend**: React.js with Stacks.js integration for wallet connections.
- **Smart Contracts**: Written in Clarity, deployed on Stacks blockchain.
- **Wallet Support**: Hiro Wallet, Leather Wallet.
- **Network**: Mainnet/Testnet toggle via configuration.

---

## 🔧 Features

- 🧾 **Register as Shareholder**: Onboard verified token holders to the platform.
- 📜 **Create Proposals**: Token-weighted proposal creation by eligible shareholders.
- 🤝 **Delegate Votes**: Assign voting power to another wallet address.
- ✅ **Cast Votes**: Vote "for", "against", or "abstain" on active proposals.
- 🔍 **Auditability**: View full history of proposals, delegations, and votes.
- 📊 **Live Vote Tallying**: Real-time proposal results based on weighted voting.

---

## 🚀 Getting Started

### Prerequisites

- [Node.js](https://nodejs.org/) >= v18
- [Yarn](https://yarnpkg.com/)
- [Clarinet](https://docs.stacks.co/write-smart-contracts/clarinet/overview) (for local contract development)
- Stacks Wallet (Hiro or Leather)

---

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/delegato.git
cd delegato
```

---

### 2. Install Dependencies

```bash
yarn install
```

---

### 3. Configure Environment

Create a `.env` file with the following:

```env
REACT_APP_STACKS_NETWORK=testnet
REACT_APP_CONTRACT_ADDRESS=ST123...
REACT_APP_CONTRACT_NAME=delegato-voting
```

---

### 4. Run the Development Server

```bash
yarn start
```

---

## 📜 Smart Contracts

Contracts are written in Clarity and located in `/contracts`. Key modules:

- `delegato-voting.clar`: Core logic for vote delegation, casting, and proposal tracking.
- `delegato-tokens.clar`: Optional utility for token-gated proposal creation.

Test with:

```bash
clarinet test
```

Deploy with:

```bash
clarinet deploy
```

---

## 🛠 Development Tasks

| Task | Script |
|------|--------|
| Run frontend | `yarn start` |
| Run tests | `yarn test` |
| Lint code | `yarn lint` |
| Build app | `yarn build` |

---

## 🧪 Local Testing with Clarinet

To simulate contract logic:

```bash
clarinet console
(contract-call? .delegato-voting delegate-vote tx-sender 'ST2...)
```

Use `Clarinet.toml` to define mock accounts and simulate realistic scenarios.

---

## 🔐 Security Considerations

- All vote delegations are **explicit and revocable**.
- Vote weights are calculated **per block height**, avoiding double voting.
- Contracts are designed to be **upgradeable only via governance**.

---

## 🧱 Built With

- [Stacks](https://www.stacks.co/)
- [Clarity](https://docs.stacks.co/)
- [React](https://reactjs.org/)
- [Stacks.js](https://github.com/hirosystems/stacks.js/)
- [Clarinet](https://github.com/hirosystems/clarinet)

---

## 📚 Resources

- [Stacks Documentation](https://docs.stacks.co/)
- [Clarity Smart Contracts](https://docs.stacks.co/write-smart-contracts)
- [Stacks.js SDK](https://github.com/hirosystems/stacks.js/)

---

## 🤝 Contributing

We welcome community contributions! To get started:

1. Fork the repository
2. Create a new branch: `git checkout -b feature/your-feature-name`
3. Make your changes
4. Commit: `git commit -m 'Add your message'`
5. Push: `git push origin feature/your-feature-name`
6. Open a pull request

---

## 📄 License

MIT License. See `LICENSE` file for details.
