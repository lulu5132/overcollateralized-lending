// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Corn.sol";
import "./CornDEX.sol";

error Lending__InvalidAmount();
error Lending__TransferFailed();
error Lending__UnsafePositionRatio();
error Lending__BorrowingFailed();
error Lending__RepayingFailed();
error Lending__PositionSafe();
error Lending__NotLiquidatable();
error Lending__InsufficientLiquidatorCorn();

contract Lending is Ownable {
    uint256 private constant COLLATERAL_RATIO = 120; // 120% collateralization required
    uint256 private constant LIQUIDATOR_REWARD = 10; // 10% reward for liquidators

    Corn private i_corn;
    CornDEX private i_cornDEX;

    mapping(address => uint256) public s_userCollateral; // 用户抵押物 (ETH)
    mapping(address => uint256) public s_userBorrowed; // 用户借出的 CORN

    event CollateralAdded(address indexed user, uint256 indexed amount, uint256 price);
    event CollateralWithdrawn(address indexed user, uint256 indexed amount, uint256 price);
    event AssetBorrowed(address indexed user, uint256 indexed amount, uint256 price);
    event AssetRepaid(address indexed user, uint256 indexed amount, uint256 price);
    event Liquidation(
        address indexed user,
        address indexed liquidator,
        uint256 amountForLiquidator,
        uint256 liquidatedUserDebt,
        uint256 price
    );

    constructor(address _cornDEX, address _corn) Ownable(msg.sender) {
        i_cornDEX = CornDEX(_cornDEX);
        i_corn = Corn(_corn);
        // Approve this contract to move CORN on its behalf (required for repayCorn and liquidate)
        i_corn.approve(address(this), type(uint256).max);
    }

    /**
     * @notice Allows users to add collateral to their account
     */
    // 存入抵押物 (ETH)
    function addCollateral() public payable {
        if (msg.value == 0) {
            revert Lending__InvalidAmount();
        }
        s_userCollateral[msg.sender] += msg.value;
        emit CollateralAdded(msg.sender, msg.value, i_cornDEX.currentPrice());
    }

    /**
     * @notice Allows users to withdraw collateral as long as it doesn't make them liquidatable
     * @param amount The amount of collateral to withdraw
     */
    // 取出抵押物
    function withdrawCollateral(uint256 amount) public {
        if (amount == 0 || s_userCollateral[msg.sender] < amount) {
            revert Lending__InvalidAmount();
        }

        s_userCollateral[msg.sender] -= amount; // 余额减少了
        
        // 🔥 检查这次提款会不会导致违约 (如果还有欠款)
        if(s_userBorrowed[msg.sender] > 0) {
            _validatePosition(msg.sender);  
        }

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) {
            revert Lending__TransferFailed();
        }

        emit CollateralWithdrawn(msg.sender, amount, i_cornDEX.currentPrice());
    }
    /**
     * @notice Calculates the total collateral value for a user based on their collateral balance
     * @param user The address of the user to calculate the collateral value for
     * @return uint256 The collateral value in CORN
     */
    // 计算某个用户的 ETH 抵押物值多少 CORN
    function calculateCollateralValue(address user) public view returns (uint256) {
        uint256 collateralAmount = s_userCollateral[user];
        // i_cornDEX.currentPrice() 返回的是 1 ETH 能换多少 CORN (1e18 精度)
        // (ETH * Price) / 1e18 = CORN Value (1e18 精度)
        return (collateralAmount * i_cornDEX.currentPrice()) / 1e18;
    }

    /**
     * @notice Calculates the position ratio for a user to ensure they are within safe limits
     * @param user The address of the user to calculate the position ratio for
     * @return uint256 The position ratio (1e18 precision, 100% = 1e18)
     */
    // 计算抵押率 (Position Ratio)
    function _calculatePositionRatio(address user) internal view returns (uint256) {
        uint256 borrowedAmount = s_userBorrowed[user];
        uint256 collateralValue = calculateCollateralValue(user);
        
        if (borrowedAmount == 0) return type(uint256).max; // 如果没借钱，极其健康
        
        // Ratio = (Collateral Value in CORN * 1e18) / Debt in CORN
        return (collateralValue * 1e18) / borrowedAmount;
    }
    /**
     * @notice Checks if a user's position can be liquidated
     * @param user The address of the user to check
     * @return bool True if the position is liquidatable (Ratio < 120%), false otherwise
     */
    // 返回 true 如果用户可以被清算 (低于由 COLLATERAL_RATIO 设定的阈值)
    function isLiquidatable(address user) public view returns (bool) {
        uint256 positionRatio = _calculatePositionRatio(user);
        
        // COLLATERAL_RATIO = 120. Threshold is 1.2 * 1e18.
        uint256 liquidationThreshold = (COLLATERAL_RATIO * 1e18) / 100;
        
        // 如果 Position Ratio 小于 120% 的阈值，则可清算
        return positionRatio < liquidationThreshold;
    }

    /**
     * @notice Internal view method that reverts if a user's position is unsafe
     * @param user The address of the user to validate
     */
    // 内部函数：检查位置是否安全，不安全则报错
    function _validatePosition(address user) internal view {
        if (isLiquidatable(user)) {
            revert Lending__UnsafePositionRatio();
        }
    }
    /**
     * @notice Allows users to borrow corn based on their collateral
     * @param borrowAmount The amount of corn to borrow
     */
    function borrowCorn(uint256 borrowAmount) public {
        if (borrowAmount == 0) {
            revert Lending__InvalidAmount();
        }
        
        // 1. 增加债务
        s_userBorrowed[msg.sender] += borrowAmount;
        
        // 2. 检查这笔借款是否会导致违约 (必须保持 > 120% 抵押率)
        _validatePosition(msg.sender);
        
        // 3. 发放贷款
        bool success = i_corn.transfer(msg.sender, borrowAmount);
        if (!success) {
            revert Lending__BorrowingFailed();
        }
        
        emit AssetBorrowed(msg.sender, borrowAmount, i_cornDEX.currentPrice());
    }

    /**
     * @notice Allows users to repay corn and reduce their debt
     * @param repayAmount The amount of corn to repay
     */
    function repayCorn(uint256 repayAmount) public {
        if (repayAmount == 0 || repayAmount > s_userBorrowed[msg.sender]) {
            revert Lending__InvalidAmount();
        }
        
        // 1. 减少债务
        s_userBorrowed[msg.sender] -= repayAmount;
        
        // 2. 收回代币 (需要用户先 Approve)
        bool success = i_corn.transferFrom(msg.sender, address(this), repayAmount);
        if (!success) {
            revert Lending__RepayingFailed();
        }
        
        emit AssetRepaid(msg.sender, repayAmount, i_cornDEX.currentPrice());
    }

    /**
     * @notice Allows liquidators to liquidate unsafe positions
     * @param user The address of the user to liquidate
     * @dev The caller must have enough CORN to pay back user's debt
     * @dev The caller must have approved this contract to transfer the debt
     */
    function liquidate(address user) public {
        // 1. 只有不健康的仓位才能被清算
        if (!isLiquidatable(user)) {
            revert Lending__NotLiquidatable();
        }

        uint256 userDebt = s_userBorrowed[user];
        uint256 userCollateral = s_userCollateral[user];
        
        // 2. 检查清算人是否有足够的 CORN 来偿还全部债务
        if (i_corn.balanceOf(msg.sender) < userDebt) {
            revert Lending__InsufficientLiquidatorCorn();
        }

        // 3. 计算需要扣除多少 ETH 抵押物赔给清算人
        // 目标是计算 userDebt (CORN) 对应多少 ETH
        // Formula: ETH = (CORN_Amount * 1e18) / (CORN_per_ETH_Price)
        uint256 debtEquivalentInEth = (userDebt * 1e18) / i_cornDEX.currentPrice();
        
        // 加上奖励 (LIQUIDATOR_REWARD, 比如 10%)
        uint256 liquidatorReward = (debtEquivalentInEth * LIQUIDATOR_REWARD) / 100;
        uint256 totalCollateralToTake = debtEquivalentInEth + liquidatorReward;

        // 确保不会拿走超过用户拥有的全部抵押物 (以防万一)
        if (totalCollateralToTake > userCollateral) {
            totalCollateralToTake = userCollateral;
        }

        // 4. 执行清算流程
        
        // 从清算人那里拿走 CORN (还债)
        bool successCornTransfer = i_corn.transferFrom(msg.sender, address(this), userDebt);
        if (!successCornTransfer) {
            revert Lending__TransferFailed(); // 使用 TransferFailed 提示转账失败
        }

        // 清除借款人的债务记录
        s_userBorrowed[user] = 0;
        
        // 扣除借款人的抵押物
        s_userCollateral[user] -= totalCollateralToTake;

        // 把抵押物 (ETH) 发给清算人
        (bool successEthTransfer, ) = payable(msg.sender).call{value: totalCollateralToTake}("");
        if (!successEthTransfer) {
            revert Lending__TransferFailed();
        }

        emit Liquidation(user, msg.sender, totalCollateralToTake, userDebt, i_cornDEX.currentPrice());
    }
}