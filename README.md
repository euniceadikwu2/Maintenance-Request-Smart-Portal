# 🏠 Maintenance Request Smart Portal

A Clarity smart contract that revolutionizes property maintenance management through blockchain technology, ensuring accountability and trust between tenants, landlords, and contractors.

## 🚀 Overview

The Maintenance Request Smart Portal eliminates maintenance delays by creating a transparent, automated system where:
- 🏠 **Tenants** submit repair requests with evidence
- 💰 **Landlords** lock funds in escrow for guaranteed payment
- 🔧 **Contractors** complete work and get paid automatically
- ✅ **Trust** is built through on-chain accountability

## ✨ Features

- **📝 Request Submission**: Tenants can submit detailed maintenance requests with photo/video evidence hashes
- **💳 Escrow Management**: Landlords fund secure escrow accounts for contractor payments
- **👥 Multi-Party System**: Support for tenants, landlords, and contractors with role-based permissions
- **⭐ Rating System**: Tenants can rate contractors and service quality upon completion
- **🚨 Emergency Release**: Landlords can release payments after extended delays (1008 blocks)
- **🏢 Property Management**: Landlords can register multiple properties with assigned tenants

## 🛠 Installation & Setup

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd Maintenance-Request-Smart-Portal
   ```

2. **Install Clarinet** (if not already installed)
   ```bash
   npm install -g @hirosystems/clarinet-cli
   ```

3. **Verify the contract**
   ```bash
   clarinet check
   ```

## 📋 Usage Guide

### 🏢 For Landlords

1. **Register a Property**
   ```clarity
   (contract-call? .Maintenance-Request-Smart-Portal register-property 'SP1234...TENANT "123 Main St, Apt 4B")
   ```

2. **Approve a Maintenance Request**
   ```clarity
   (contract-call? .Maintenance-Request-Smart-Portal approve-request u1 u1000000) ;; 1 STX escrow
   ```

3. **Fund the Escrow**
   ```clarity
   (contract-call? .Maintenance-Request-Smart-Portal fund-escrow u1)
   ```

4. **Assign a Contractor**
   ```clarity
   (contract-call? .Maintenance-Request-Smart-Portal assign-contractor u1 'SP5678...CONTRACTOR)
   ```

### 🏠 For Tenants

1. **Submit a Maintenance Request**
   ```clarity
   (contract-call? .Maintenance-Request-Smart-Portal submit-request 
     'SP9999...LANDLORD 
     "Leaky Faucet" 
     "Kitchen faucet dripping constantly, water damage possible" 
     "QmHash123...PhotoHash")
   ```

2. **Verify Completion (releases payment)**
   ```clarity
   (contract-call? .Maintenance-Request-Smart-Portal verify-completion u1 u5 u4) ;; 5-star contractor, 4-star service
   ```

3. **Reject Completion (if unsatisfactory)**
   ```clarity
   (contract-call? .Maintenance-Request-Smart-Portal reject-completion u1)
   ```

### 🔧 For Contractors

1. **Mark Work as Completed**
   ```clarity
   (contract-call? .Maintenance-Request-Smart-Portal mark-completed u1)
   ```

## 🔍 Read-Only Functions

- **Get Request Details**: `(get-request u1)`
- **Check Escrow Status**: `(get-escrow-status u1)`
- **View Ratings**: `(get-rating 'SP123...TENANT u1)`
- **Get Property Info**: `(get-property 'SP456...LANDLORD u1)`
- **Next Request ID**: `(get-next-request-id)`

## 📊 Request Status Flow

```
SUBMITTED → APPROVED → IN-PROGRESS → COMPLETED → VERIFIED
     ↓          ↓            ↓           ↓
  REJECTED   REJECTED    REJECTED   REJECTED
```

## 🏗 Contract Architecture

### Status Codes
- `1` - SUBMITTED: Request created by tenant
- `2` - APPROVED: Landlord approved with escrow amount
- `3` - IN-PROGRESS: Contractor assigned and working
- `4` - COMPLETED: Contractor marked work as done
- `5` - VERIFIED: Tenant approved and payment released
- `6` - REJECTED: Request rejected at any stage

### Key Data Structures
- **maintenance-requests**: Core request data with all parties and status
- **request-escrow**: Escrow funding and release tracking
- **tenant-ratings**: Service quality ratings (1-5 stars)
- **landlord-properties**: Property registration system

## 🚨 Error Codes

- `u1` - ERR-NOT-AUTHORIZED
- `u2` - ERR-REQUEST-NOT-FOUND
- `u3` - ERR-INVALID-STATUS
- `u4` - ERR-INSUFFICIENT-FUNDS
- `u5` - ERR-ALREADY-COMPLETED
- `u6` - ERR-NOT-TENANT
- `u7` - ERR-NOT-LANDLORD
- `u8` - ERR-NOT-CONTRACTOR
- `u9` - ERR-ESCROW-NOT-FUNDED
- `u10` - ERR-INVALID-AMOUNT

## 🧪 Testing

```bash
npm install
npm test
```

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🔗 Additional Resources

- [Clarity Language Reference](https://docs.stacks.co/clarity)
- [Clarinet Documentation](https://docs.hiro.so/stacks/clarinet)
- [Stacks Blockchain](https://stacks.co)
