# 🏦 Demo Over-Collateralized Lending Protocol  
**Sepolia Testnet · Solidity 0.8.24 · 4 Contracts**

本项目实现了一个最小可运行的「超额抵押借贷协议 Demo」，包含抵押、借款、还款、提现与清算全流程。  
## 📌 1. 合约地址（Sepolia）
> 所有合约已部署在 Sepolia，价格精度 1e18，代币精度 18 decimals。

| 合约 | 功能 | 地址 |
|------|------|------|
| **MockUSD** | 债务币（mUSD） | `0x1346DABB75fEF239CBaeC966a39b6Ce2675d39a3` |
| **MockWETH** | 抵押币（mWETH） | `0x9846512BF167cC4eCDCbc2A3340722f979a31055` |
| **PriceOracleMock** | 手动预言机（1e18 精度） | `0xAe4f07B209B6CDe3eEC49e40f17eC98D8Df34A92` |
| **LendingPool（主合约）** | 存款/借款/还款/提现/清算 | `0x07BBD56FaE56C6083459Ce1c6a5C977d4B5FB250` |

JSON 导出：
```json
{
  "MockUSD": "0x1346DABB75fEF239CBaeC966a39b6Ce2675d39a3",
  "MockWETH": "0x9846512BF167cC4eCDCbc2A3340722f979a31055",
  "PriceOracleMock": "0xAe4f07B209B6CDe3eEC49e40f17eC98D8Df34A92",
  "LendingPool": "0x07BBD56FaE56C6083459Ce1c6a5C977d4B5FB250"
}