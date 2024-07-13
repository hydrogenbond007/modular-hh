// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBitcoinRelay {
    function verifyTx(bytes32 _txId, uint256 _blockHeight, uint256 _index, bytes memory _proof) external view returns (bool);
    function getBitcoinBalance(bytes20 _btcAddress) external view returns (uint256);
}

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IZuniswapV2Pair {
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IZuniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

contract CBTCToUSDTSwapper {
    IBitcoinRelay public bitcoinRelay;
    IZuniswapV2Pair public cbtcUsdtPair;
    IZuniswapV2Factory public factory;
    IWETH public wrappedCBTC;
    IERC20 public usdtToken;
    bytes20 public monitoredBtcAddress;
    uint256 public lastKnownBalance;
    address public owner;

    event MonitoredAddressUpdated(bytes20 newAddress);
    event DepositDetected(uint256 amount);
    event Swapped(uint256 cbtcAmount, uint256 usdtAmount);

    constructor(address _bitcoinRelay, address _factory, address _wrappedCBTC, address _usdtToken) {
        bitcoinRelay = IBitcoinRelay(_bitcoinRelay);
        factory = IZuniswapV2Factory(_factory);
        wrappedCBTC = IWETH(_wrappedCBTC);
        usdtToken = IERC20(_usdtToken);
        owner = msg.sender;

        // Create the CBTC-USDT pair
        address pairAddress = factory.createPair(address(wrappedCBTC), address(usdtToken));
        cbtcUsdtPair = IZuniswapV2Pair(pairAddress);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    function setMonitoredBtcAddress(bytes20 _btcAddress) external onlyOwner {
        monitoredBtcAddress = _btcAddress;
        lastKnownBalance = bitcoinRelay.getBitcoinBalance(_btcAddress);
        emit MonitoredAddressUpdated(_btcAddress);
    }

    function checkAndSwap() external payable {
        require(monitoredBtcAddress != bytes20(0), "Monitored address not set");
        uint256 currentBalance = bitcoinRelay.getBitcoinBalance(monitoredBtcAddress);
        uint256 depositAmount = currentBalance - lastKnownBalance;

        if (depositAmount > 0) {
            // Update the last known balance
            lastKnownBalance = currentBalance;
            emit DepositDetected(depositAmount);

            // Perform the swap
            swapCBTCToUSDT(depositAmount);
        }
    }

    function swapCBTCToUSDT(uint256 cbtcAmount) private {
        require(msg.value == cbtcAmount, "Incorrect CBTC amount sent");

        // Wrap the native CBTC
        wrappedCBTC.deposit{value: cbtcAmount}();

        // Approve the pair contract to spend the wrapped CBTC
        wrappedCBTC.approve(address(cbtcUsdtPair), cbtcAmount);

        // Calculate the amount of USDT to receive
        (uint112 reserve0, uint112 reserve1,) = cbtcUsdtPair.getReserves();
        uint256 usdtAmount = (cbtcAmount * reserve1) / reserve0;

        // Perform the swap
        cbtcUsdtPair.swap(0, usdtAmount, msg.sender, "");

        emit Swapped(cbtcAmount, usdtAmount);
    }

    function addLiquidity(uint256 cbtcAmount, uint256 usdtAmount) external payable onlyOwner {
        require(msg.value == cbtcAmount, "Incorrect CBTC amount sent");

        // Wrap the native CBTC
        wrappedCBTC.deposit{value: cbtcAmount}();

        // Transfer USDT from the owner
        require(usdtToken.transferFrom(msg.sender, address(this), usdtAmount), "USDT transfer failed");

        // Approve the pair contract to spend tokens
        wrappedCBTC.approve(address(cbtcUsdtPair), cbtcAmount);
        usdtToken.approve(address(cbtcUsdtPair), usdtAmount);

        // Add liquidity
        (uint256 cbtcReserve, uint256 usdtReserve,) = cbtcUsdtPair.getReserves();
        uint256 cbtcOptimal = (cbtcAmount * usdtReserve) / usdtAmount;
        uint256 usdtOptimal = (usdtAmount * cbtcReserve) / cbtcAmount;

        if (cbtcOptimal <= cbtcAmount) {
            cbtcUsdtPair.swap(0, usdtOptimal, address(this), "");
        } else {
            cbtcUsdtPair.swap(cbtcOptimal, 0, address(this), "");
        }
    }

    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner, amount);
    }

    receive() external payable {}
}
