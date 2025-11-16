// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/* =========================
   Minimal utils（零依赖）
   ========================= */
abstract contract Ownable {
    address public owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() { owner = msg.sender; emit OwnershipTransferred(address(0), owner); }
    modifier onlyOwner() { require(msg.sender == owner, "not owner"); _; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private _locked = 1;
    modifier nonReentrant() {
        require(_locked == 1, "reentered");
        _locked = 2;
        _;
        _locked = 1;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/* =========================================
   ERC20Mintable（18 位，含 internal _mint）
   ========================================= */
contract ERC20Mintable is IERC20, Ownable {
    string public name;
    string public symbol;
    uint8  public constant decimals = 18;
    uint256 public override totalSupply;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function transfer(address to, uint256 amt) public override returns (bool) {
        require(balanceOf[msg.sender] >= amt, "no bal");
        unchecked { balanceOf[msg.sender] -= amt; balanceOf[to] += amt; }
        emit Transfer(msg.sender, to, amt);
        return true;
    }

    function approve(address sp, uint256 amt) public override returns (bool) {
        allowance[msg.sender][sp] = amt;
        emit Approval(msg.sender, sp, amt);
        return true;
    }

    function transferFrom(address from, address to, uint256 amt) public override returns (bool) {
        uint256 a = allowance[from][msg.sender];
        require(a >= amt, "no allowance");
        require(balanceOf[from] >= amt, "no bal");
        unchecked {
            allowance[from][msg.sender] = a - amt;
            balanceOf[from] -= amt;
            balanceOf[to] += amt;
        }
        emit Transfer(from, to, amt);
        return true;
    }

    // 🔹 internal 版本，供构造/铸造复用
    function _mint(address to, uint256 amt) internal {
        totalSupply += amt;
        balanceOf[to] += amt;
        emit Transfer(address(0), to, amt);
    }

    // 🔹 对外铸造（仅 owner）
    function mint(address to, uint256 amt) external onlyOwner {
        _mint(to, amt);
    }
}

/* =========================
   代币：mUSD / mWETH
   ========================= */
contract MockUSD is ERC20Mintable {
    constructor() ERC20Mintable("Mock USD", "mUSD") {
        _mint(msg.sender, 1_000_000e18); // 部署者初始测试币
    }
}

contract MockWETH is ERC20Mintable {
    constructor() ERC20Mintable("Mock WETH", "mWETH") {
        _mint(msg.sender, 1_000_000e18);
    }
}

/* =========================
   预言机（手动设价，精度 1e18）
   ========================= */
contract PriceOracleMock is Ownable {
    mapping(address => uint256) public priceE18; // token => price(1e18)

    function setPrice(address token, uint256 pE18) external onlyOwner {
        require(pE18 > 0, "invalid");
        priceE18[token] = pE18;
    }

    function getPrice(address token) external view returns (uint256) {
        uint256 p = priceE18[token];
        require(p > 0, "no price");
        return p;
    }
}

/* =========================
   主合约：LendingPool
   ========================= */
interface IOracle { function getPrice(address token) external view returns (uint256); }

contract LendingPool is ReentrancyGuard, Ownable {
    IERC20  public collateralToken;   // 抵押代币（如 mWETH）
    IERC20  public debtToken;         // 借出代币（如 mUSD）
    IOracle public oracle;

    uint256 public constant LTV_E4           = 6500;   // 65% 可借上限
    uint256 public constant LIQ_THRESHOLD_E4 = 7500;   // 75% 清算阈值
    uint256 public constant LIQ_BONUS_E4     = 10500;  // +5% 清算奖励

    bool public paused;

    struct Position { uint256 coll; uint256 debt; } // 单位：代币数量（18 位）
    mapping(address => Position) public positions;

    event Deposited(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Liquidated(address indexed user, address indexed keeper, uint256 repay, uint256 seized);
    event Paused(bool status);

    modifier notPaused() { require(!paused, "paused"); _; }

    constructor(IERC20 _coll, IERC20 _debt, IOracle _oracle) {
        collateralToken = _coll;
        debtToken = _debt;
        oracle = _oracle;
    }

    // -------- 用户流程 --------
    function deposit(uint256 amt) external notPaused nonReentrant {
        require(collateralToken.transferFrom(msg.sender, address(this), amt), "transferFrom fail");
        positions[msg.sender].coll += amt;
        emit Deposited(msg.sender, amt);
    }

    function borrow(uint256 amt) external notPaused nonReentrant {
        require(_borrowRoom(msg.sender) >= amt, "exceeds LTV");
        positions[msg.sender].debt += amt;
        require(debtToken.transfer(msg.sender, amt), "transfer fail");
        emit Borrowed(msg.sender, amt);
    }

    function repay(uint256 amt) external nonReentrant {
        require(debtToken.transferFrom(msg.sender, address(this), amt), "transferFrom fail");
        Position storage p = positions[msg.sender];
        p.debt = (amt >= p.debt) ? 0 : (p.debt - amt);
        emit Repaid(msg.sender, amt);
    }

    function withdraw(uint256 amt) external nonReentrant {
        Position storage p = positions[msg.sender];
        require(p.coll >= amt, "exceeds collateral");
        p.coll -= amt;
        require(_healthFactor(msg.sender) >= 1e18, "hf<1");
        require(collateralToken.transfer(msg.sender, amt), "transfer fail");
        emit Withdrawn(msg.sender, amt);
    }

    // -------- 清算流程 --------
    function liquidate(address user, uint256 repayAmt) external nonReentrant {
        require(_healthFactor(user) < 1e18, "healthy");
        Position storage u = positions[user];

        require(debtToken.transferFrom(msg.sender, address(this), repayAmt), "transferFrom fail");

        uint256 seize = _collateralForDebt(repayAmt) * LIQ_BONUS_E4 / 10000;
        require(u.coll >= seize, "insufficient seize");

        u.debt = repayAmt >= u.debt ? 0 : (u.debt - repayAmt);
        u.coll -= seize;

        require(collateralToken.transfer(msg.sender, seize), "transfer fail");
        emit Liquidated(user, msg.sender, repayAmt, seize);
    }

    // -------- 管理 --------
    function setPaused(bool s) external onlyOwner { paused = s; emit Paused(s); }

    // -------- 视图 --------
    function maxBorrowRoom(address user) external view returns (uint256) { return _borrowRoom(user); }
    function healthFactor(address user) external view returns (uint256) { return _healthFactor(user); }

    // -------- 内部计算（价格 1e18 精度）--------
    function _valueE18(IERC20 token, uint256 amt) internal view returns (uint256) {
        uint256 p = IOracle(oracle).getPrice(address(token)); // 1 token 价格(1e18)
        return amt * p / 1e18;
    }

    function _borrowRoom(address user) internal view returns (uint256) {
        Position memory p = positions[user];
        uint256 collV = _valueE18(collateralToken, p.coll);
        uint256 debtV = _valueE18(debtToken,     p.debt);
        if (collV == 0) return 0;
        uint256 limitV = collV * LTV_E4 / 10000;
        if (limitV <= debtV) return 0;
        uint256 roomV = limitV - debtV;
        uint256 debtPrice = IOracle(oracle).getPrice(address(debtToken));
        return roomV * 1e18 / debtPrice; // 转为债务代币数量
    }

    function _collateralForDebt(uint256 repayAmt) internal view returns (uint256) {
        uint256 debtV = _valueE18(debtToken, repayAmt);
        uint256 collPrice = IOracle(oracle).getPrice(address(collateralToken));
        return debtV * 1e18 / collPrice;
    }

    // HF = (collV * 清算阈值) / debtV，缩放成 1e18；>=1e18 安全
    function _healthFactor(address user) internal view returns (uint256) {
        Position memory p = positions[user];
        uint256 collV = _valueE18(collateralToken, p.coll);
        uint256 debtV = _valueE18(debtToken,     p.debt);
        if (debtV == 0) return type(uint256).max;
        uint256 adjCollV = collV * LIQ_THRESHOLD_E4 / 10000;
        return adjCollV * 1e18 / debtV;
    }
}
