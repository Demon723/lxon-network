# Escrow Instructions for LXON OTC Sale

<!-- lxon-724-restart-notice:begin -->
> ⚠️ **Chain 724 addresses quoted in this file no longer exist.** Measured 2026-11-04 against `https://rpc.lxon.in`. Chain 724 restarted from an empty volume on 2026-11-03 under its original genesis (block 0 `0x6c931dff...`), so blocks 1-242,493 -- and every contract created in them -- are gone. Each address below returns **0 bytes of code** on 724 today:
>
> - `0x7999b8c0662fe6ae3d82ac6988718189e66f9b4b` - Validator / attester
> - `0xc0177883c0c662870855660495c697385fe040f5` - LXON, native (per the bridge docs)
>
> The control that makes those empty reads evidence, measured by the same script: the v4.1 bridge on Polygon 137 is 19,105 bytes and wLXON is 2,106 bytes, so a working reader does return bytes when something is there. Read everything below as history or as a redeploy target, not as live state. Per-address ledger and method: `docs/724-claim-ledger-2026-11-03.md`.
<!-- lxon-724-restart-notice:end -->
## 🔒 Escrow Setup Guide

This guide provides step-by-step instructions for setting up escrow for the 2B LXON OTC sale.

---

## 📋 Pre-Escrow Checklist

### Seller Checklist
- [ ] Verify 2B LXON balance in wallet
- [ ] Generate balance proof
- [ ] Prepare legal documents
- [ ] Choose escrow service
- [ ] Verify buyer credentials

### Buyer Checklist
- [ ] Verify funds availability
- [ ] Prepare payment method
- [ ] Complete KYC/AML
- [ ] Review legal documents
- [ ] Agree to escrow terms

---

## 🏢 Option 1: Third-Party Escrow Service

### Recommended Services

#### BitGo
- **Website:** https://www.bitgo.com
- **Support:** Institutional crypto custody
- **Features:** Multi-sig, insurance, compliance
- **Contact:** sales@bitgo.com

#### Coinbase Custody
- **Website:** https://custody.coinbase.com
- **Support:** Institutional custody
- **Features:** Cold storage, insurance, compliance
- **Contact:** custody@coinbase.com

#### Anchorage Digital
- **Website:** https://www.anchorage.com
- **Support:** Digital asset custody
- **Features:** Cold storage, compliance, governance
- **Contact:** info@anchorage.com

#### Fireblocks
- **Website:** https://www.fireblocks.com
- **Support:** Digital asset platform
- **Features:** Multi-party computation, API access
- **Contact:** sales@fireblocks.com

### Setup Process

#### Step 1: Contact Escrow Service
```
Subject: LXON Token Escrow Inquiry - 2B LXON Sale

Dear [Escrow Service],

I am interested in using your escrow services for a large token sale:

- Token: LXON
- Amount: 2,000,000,000 LXON
- Value: ~$4,000,000,000 USD
- Network: LXON (Chain ID: 724)
- Contract: 0xc0177883C0c662870855660495C697385FE040f5

Please provide information on:
1. Escrow fees
2. KYC/AML requirements
3. Setup timeline
4. Supported payment methods
5. Insurance coverage

Thank you,
[Your Name]
```

#### Step 2: Complete KYC/AML
- Submit identity documents
- Provide business registration
- Source of funds documentation
- Beneficial ownership information

#### Step 3: Sign Escrow Agreement
- Review terms and conditions
- Agree to fee structure
- Define release conditions
- Set dispute resolution process

#### Step 4: Deposit Assets
- Seller deposits 2B LXON to escrow
- Buyer deposits payment to escrow
- Escrow verifies both deposits
- Both parties confirm receipt

#### Step 5: Execute Release
- Escrow releases LXON to buyer
- Escrow releases payment to seller
- Transaction recorded on blockchain
- Both parties receive confirmation

---

## 🔐 Option 2: Smart Contract Escrow

### Smart Contract Template

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LXONEscrow is Ownable {
    IERC20 public lxonToken;
    address public seller;
    address public buyer;
    uint256 public amount;
    bool public buyerDeposited;
    bool public sellerDeposited;
    bool public released;

    event Deposited(address indexed who, uint256 amount);
    event Released(address indexed to, uint256 amount);
    event Cancelled(address indexed initiator);

    constructor(
        address _lxonToken,
        address _seller,
        address _buyer,
        uint256 _amount
    ) Ownable(msg.sender) {
        lxonToken = IERC20(_lxonToken);
        seller = _seller;
        buyer = _buyer;
        amount = _amount;
    }

    function depositTokens() external {
        require(msg.sender == seller, "Only seller can deposit");
        require(!sellerDeposited, "Already deposited");

        require(
            lxonToken.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        sellerDeposited = true;
        emit Deposited(msg.sender, amount);
    }

    function depositPayment() external payable {
        require(msg.sender == buyer, "Only buyer can deposit");
        require(!buyerDeposited, "Already deposited");
        require(msg.value >= amount, "Insufficient payment");

        buyerDeposited = true;
        emit Deposited(msg.sender, msg.value);
    }

    function release() external onlyOwner {
        require(sellerDeposited && buyerDeposited, "Both must deposit");
        require(!released, "Already released");

        released = true;

        lxonToken.transfer(buyer, amount);
        payable(seller).transfer(address(this).balance);

        emit Released(buyer, amount);
        emit Released(seller, address(this).balance);
    }

    function cancel() external onlyOwner {
        require(!released, "Already released");

        if (sellerDeposited) {
            lxonToken.transfer(seller, amount);
        }

        if (buyerDeposited) {
            payable(buyer).transfer(address(this).balance);
        }

        emit Cancelled(msg.sender);
    }
}
```

### Deployment Steps

#### Step 1: Deploy Contract
```bash
npx hardhat run scripts/deploy-escrow.js --network lxon
```

#### Step 2: Configure Parameters
- LXON Token Address: `0xc0177883C0c662870855660495C697385FE040f5`
- Seller Address: `0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b`
- Buyer Address: [Buyer's Address]
- Amount: 2,000,000,000 × 10^6 (with decimals)

#### Step 3: Approve Token Transfer
```bash
npx hardhat run scripts/approve-escrow.js --network lxon
```

#### Step 4: Deposit Tokens
```bash
npx hardhat run scripts/deposit-tokens.js --network lxon
```

#### Step 5: Buyer Deposits Payment
- Buyer sends ETH/LXON to contract
- Contract verifies payment amount

#### Step 6: Release Funds
- Owner calls `release()` function
- Tokens transfer to buyer
- Payment transfers to seller

---

## 📊 Escrow Fee Structure

### Third-Party Services
- **BitGo:** 0.10% - 0.50% of transaction value
- **Coinbase Custody:** 0.05% - 0.30% of transaction value
- **Anchorage:** 0.15% - 0.40% of transaction value
- **Fireblocks:** 0.10% - 0.35% of transaction value

### Smart Contract
- **Deployment Gas:** ~$50-200
- **Transaction Gas:** ~$10-50
- **Total Cost:** ~$60-250

---

## ⚠️ Security Best Practices

### For Smart Contract Escrow
- Use audited contracts
- Implement multi-sig control
- Add time-lock release
- Include emergency pause
- Test on testnet first

### For Third-Party Escrow
- Verify service reputation
- Check insurance coverage
- Review compliance standards
- Confirm regulatory approval
- Read customer reviews

---

## 🔄 Release Conditions

### Standard Release
- Both parties deposit assets
- No disputes raised
- 24-48 hour confirmation period
- Automatic release

### Conditional Release
- Milestone-based release
- Vesting schedule
- Performance conditions
- Custom agreement terms

### Emergency Release
- Dispute resolution
- Arbitration decision
- Regulatory intervention
- Mutual agreement

---

## 📞 Dispute Resolution

### Escrow Service Process
1. One party raises dispute
2. Escrow service investigates
3. Both parties submit evidence
4. Escrow makes decision
5. Assets released accordingly

### Smart Contract Process
1. Multi-sig holders vote
2. Majority decision wins
3. Assets released based on vote
4. On-chain record maintained

---

## ✅ Post-Escrow

### Seller Actions
- Receive payment
- File taxes
- Update records
- Announce to community
- Monitor market

### Buyer Actions
- Receive tokens
- Verify ownership
- Store securely
- Track market
- Plan trading/holding

---

## 📞 Support Contacts

### For Smart Contract Issues
- Contact developer
- Review transaction logs
- Check block explorer
- Consult blockchain expert

### For Third-Party Escrow
- Contact escrow service
- Review service agreement
- Check service status
- File support ticket

---

*Last Updated: 2026-10-06*
