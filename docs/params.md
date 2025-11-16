# 风险参数一页纸（Risk Parameters, v1.0）

> 协议：超额抵押借贷 Demo（Sepolia）  
> 精度约定：**代币数量 1e18**，**价格 1e18**（\$1 → `1e18`；\$2000 → `2000e18`）

---

## 1) 关键参数（万分制）
| 参数名 | 常量名 | 数值 | 含义 |
|---|---|---:|---|
| **最大可借比 LTV** | `LTV_E4` | **6500** | 可借额度 = 抵押价值 × 65% |
| **清算阈值** | `LIQ_THRESHOLD_E4` | **7500** | HF 使用 75% 折扣判断是否可清算 |
| **清算奖励** | `LIQ_BONUS_E4` | **10500** | 清算可没收等值抵押 × **1.05** |

> 注：使用“万分制”便于链上整数运算：`65%→6500`、`75%→7500`、`1.05→10500`。

---

## 2) 资产与地址（Sepolia）
- **MockUSD (mUSD)**：`0x1346DABB75fEF239CBaeC966a39b6Ce2675d39a3`
- **MockWETH (mWETH)**：`0x9846512BF167cC4eCDCbc2A3340722f979a31055`
- **PriceOracleMock**：`0xAe4f07B209B6CDe3eEC49e40f17eC98D8Df34A92`
- **LendingPool**：`0x07BBD56FaE56C6083459Ce1c6a5C977d4B5FB250`

---

## 3) 价格配置（1e18 精度）
```text
setPrice(mUSD, 1e18)        // mUSD = $1
setPrice(mWETH, 2000e18)    // mWETH = $2000
