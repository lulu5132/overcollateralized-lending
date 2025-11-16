# Frontend & Safety Usage Notes (v1.0)

## 1) 单位与精度
- 代币数量：**1e18**（1 → `1e18`）
- 价格：**1e18**（$2000 → `2000e18`）
- 健康因子 `healthFactor`：返回 **1e18**（显示时 /1e18）

## 2) 关键只读函数
- `maxBorrowRoom(address)` → 返回你还能借多少 **债务币数量**（1e18）
- `healthFactor(address)` → ≥1 安全，＜1 可清算（返回 1e18）

## 3) 典型调用顺序（Remix / 前端）
1. 价格设置（Owner）：`setPrice(mUSD, 1e18)`，`setPrice(mWETH, 2000e18)`
2. 池子注资（Owner）：`MockUSD.mint(LendingPool, 1_000_000e18)`
3. 存抵押（用户）：`MockWETH.approve(LendingPool, 1e18)` → `deposit(1e18)`
4. 查额度：`maxBorrowRoom(you)`（≈`1300e18`）
5. 借款：`borrow(1000e18)`
6. 还款：`MockUSD.approve(LendingPool, 200e18)` → `repay(200e18)`
7. 提现：`withdraw(0.1e18)`
8. （可选清算）下调价：`setPrice(mWETH, 900e18)` → 换号 `approve + liquidate(user, 100e18)`

## 4) 事件（前端监听）
- `Deposited(user, amount)`
- `Borrowed(user, amount)`
- `Repaid(user, amount)`
- `Withdrawn(user, amount)`
- `Liquidated(user, keeper, repay, seized)`
- `Paused(status)`

## 5) 常见报错（前端需处理）
- `"exceeds LTV"`：超出 65% 可借上限
- `"hf<1"`：提现会导致健康因子 < 1
- `"healthy"`：HF ≥ 1，不能清算
- `"insufficient seize"`：可没收抵押不足
- `"transferFrom fail" / "transfer fail"`：未授权或余额不足
- `"paused"`：Owner 暂停中

## 6) 管理
- `setPaused(bool)`（Owner）：演示前确保为 false
