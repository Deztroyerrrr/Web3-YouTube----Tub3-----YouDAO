# 🎬 Tub3 - Web3 YouTube Platform 🚀

> The decentralized video platform that puts creators and viewers first! 💰✨

## 🌟 Overview

Tub3 (YouDAO) is a revolutionary Web3 video platform that solves the traditional problems of centralized video platforms through:

- 💎 **Direct Creator Monetization** - No more middleman taking huge cuts
- 🎫 **NFT Video Clips** - Collect memorable moments as unique digital assets  
- 🏆 **Proof-of-Watch Rewards** - Get paid for engaging with content
- 🗳️ **DAO Governance** - Community-driven content moderation

## ⚡ Core Features

### 📹 Video Management
- Upload videos with IPFS storage
- Track views and engagement metrics
- Creator reputation system

### 🪙 Token Economy  
- **TUB3 Token** - Platform's native cryptocurrency
- Microtransaction ad payouts
- Watch-to-earn mechanism
- Creator revenue sharing

### 🖼️ NFT Collectibles
- Mint video clips as NFTs
- Rarity scoring based on popularity
- Tradeable digital collectibles

### 🏛️ DAO Voting
- Community-based content moderation
- Proposal creation and voting
- Reputation-weighted governance

## 🛠️ Smart Contract Functions

### 👤 User Functions
```clarity
(create-profile "username")           ; Create user profile
(upload-video "title" "ipfs-hash" duration) ; Upload new video
(watch-video video-id watch-duration) ; Watch and track engagement
(claim-watch-reward video-id)         ; Claim proof-of-watch rewards
```

### 🎨 NFT Functions  
```clarity
(mint-video-clip video-id "title" start-time end-time) ; Mint video clip NFT
```

### 🗳️ DAO Functions
```clarity
(create-dao-proposal video-id "type" "description") ; Create moderation proposal
(vote-on-proposal proposal-id support)             ; Vote on proposals  
(execute-proposal proposal-id)                     ; Execute passed proposals
```

### 📊 Read Functions
```clarity
(get-video video-id)                    ; Get video details
(get-user-profile user)                 ; Get user profile
(get-video-clip clip-id)                ; Get NFT clip details
(get-dao-proposal proposal-id)          ; Get proposal details
(get-balance user)                      ; Get TUB3 token balance
```

## 🚀 Getting Started

### Prerequisites
- Clarinet CLI installed
- Stacks wallet configured

### Deployment
1. Clone the repository
2. Deploy the contract:
```bash
clarinet deploy --testnet
```

### Usage Examples

#### 📝 Create Your Profile
```bash
clarinet call .Web3-YouTube----Tub3-----YouDAO create-profile '"MyCreatorName"'
```

#### 🎬 Upload a Video
```bash
clarinet call .Web3-YouTube----Tub3-----YouDAO upload-video '"My Amazing Video"' '"QmHash123"' u3600
```

#### 👀 Watch and Earn
```bash
clarinet call .Web3-YouTube----Tub3-----YouDAO watch-video u1 u1800
clarinet call .Web3-YouTube----Tub3-----YouDAO claim-watch-reward u1
```

#### 🎫 Mint NFT Clip
```bash
clarinet call .Web3-YouTube----Tub3-----YouDAO mint-video-clip u1 '"Epic Moment"' u60 u120
```

## 💡 Tokenomics

- **🏆 Watch Rewards**: Earn TUB3 based on completion rate (50%+ required)
- **💰 Creator Revenue**: Direct ad revenue distribution minus 5% platform fee
- **🎯 Reputation System**: Build reputation through engagement and quality content
- **⚖️ Voting Power**: Based on token balance + reputation score

## 🛡️ Security Features

- ✅ Owner-only administrative functions
- ✅ Input validation on all public functions  
- ✅ Authorization checks for sensitive operations
- ✅ Reentrancy protection through proper state management
- ✅ Error handling with descriptive error codes

## 🎯 Roadmap

- 🔄 **Phase 1**: Core platform functionality (✅ Complete)
- 📱 **Phase 2**: Mobile app integration
- 🌐 **Phase 3**: Cross-chain compatibility  
- 🤖 **Phase 4**: AI-powered content recommendations
- 🎮 **Phase 5**: GameFi integrations

## 🤝 Contributing

We welcome contributions! Please see our contributing guidelines and join our Discord community.

## 📄 License

MIT License - Build the future of decentralized media! 🚀

---

*Made with ❤️ by the Tub3 community* 🌟
