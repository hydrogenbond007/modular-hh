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
}

interface IZuniswapV2Pair {
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external;
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

contract BTCToUSDTSwapper {
    IBitcoinRelay public bitcoinRelay;
    IZuniswapV2Pair public btcUsdtPair;
    IERC20 public btcToken;
    IERC20 public usdtToken;
    bytes20 public monitoredBtcAddress;
    uint256 public lastKnownBalance;
    address public owner;

    event MonitoredAddressUpdated(bytes20 newAddress);
    event DepositDetected(uint256 amount);
    event Swapped(uint256 btcAmount, uint256 usdtAmount);

    constructor(address _bitcoinRelay, address _btcUsdtPair, address _btcToken, address _usdtToken) {
        bitcoinRelay = IBitcoinRelay(_bitcoinRelay);
        btcUsdtPair = IZuniswapV2Pair(_btcUsdtPair);
        btcToken = IERC20(_btcToken);
        usdtToken = IERC20(_usdtToken);
        owner = msg.sender;
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

    function checkAndSwap() external {
        require(monitoredBtcAddress != bytes20(0), "Monitored address not set");
        uint256 currentBalance = bitcoinRelay.getBitcoinBalance(monitoredBtcAddress);
        uint256 depositAmount = currentBalance - lastKnownBalance;

        if (depositAmount > 0) {
            // Update the last known balance
            lastKnownBalance = currentBalance;
            emit DepositDetected(depositAmount);

            // Perform the swap
            swapBTCToUSDT(depositAmount);
        }
    }

    function swapBTCToUSDT(uint256 btcAmount) private {
        require(btcToken.transferFrom(msg.sender, address(this), btcAmount), "BTC transfer failed");
        require(btcToken.approve(address(btcUsdtPair), btcAmount), "BTC approval failed");

        (uint112 reserve0, uint112 reserve1,) = btcUsdtPair.getReserves();
        uint256 usdtAmount = (btcAmount * reserve1) / reserve0;

        btcUsdtPair.swap(0, usdtAmount, address(this));

        // Transfer USDT to the caller
        require(usdtToken.transfer(msg.sender, usdtAmount), "USDT transfer failed");

        emit Swapped(btcAmount, usdtAmount);
    }

    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner, amount);
    }
}