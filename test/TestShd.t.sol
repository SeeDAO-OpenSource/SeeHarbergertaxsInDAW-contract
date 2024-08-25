// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "../lib/forge-std/src/Test.sol";
import {ShdV1} from "../src/ShdV1.sol";
import {SRCToken} from "./SRCTestToken.sol";

contract TestShdV1 is Test {

    SRCToken public srcToken;

    ShdV1 shd;

    string public URI = "adadsa";
    uint256  public tradeCooldown = 86400;
    uint256 public priceCooldown = 3600;

    receive() external payable {}

    uint256 public startingBalance = 10 ether;
    uint256 public initialPrice = 1 ether;
    uint256 public secondPrice = 2 ether;
    uint256 public thirdPrice = 3 ether;
    uint256 public firstDepositFees = 350000000000000000;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address owner = makeAddr("owner");

    modifier createShd() {
        vm.startPrank(owner);
        shd.createShd();
        vm.stopPrank();
        _;
    }

    modifier purchasedShd() {
        vm.startPrank(owner);
        shd.createShd();
        vm.stopPrank();

        vm.warp(block.timestamp + tradeCooldown + 1);
        vm.startPrank(user1);
        shd.purchase(0);
        vm.stopPrank();

        vm.warp(block.timestamp + tradeCooldown + 1);
        _;
    }

    function setUp() external {
        
        vm.startBroadcast();
        srcToken = new SRCToken("Test Token", "TST");
        shd = new ShdV1(address(srcToken), URI, initialPrice, owner, tradeCooldown, priceCooldown);
        vm.stopBroadcast();
        
        srcToken.mint(address(shd), 1000 * 10**18);
        srcToken.mint(address(owner), 1000 * 10**18);
        srcToken.mint(address(user1), 1000 * 10**18);
        srcToken.mint(address(user2), 1000 * 10**18);

        vm.deal(owner, startingBalance);                                                                                                                                                                                                                                                                                                            
        vm.deal(user1, startingBalance);                                                                                                                                                                                                                                                                                                            
        vm.deal(user2, startingBalance); 

        vm.startPrank(owner);
        srcToken.approve(address(shd), startingBalance);
        vm.stopPrank();

        vm.startPrank(user1);
        srcToken.approve(address(shd), startingBalance);
        vm.stopPrank();

        vm.startPrank(user2);
        srcToken.approve(address(shd), startingBalance);
        vm.stopPrank();

    }
    
    function testIfOwnerCorrect() public view {
        assertEq(shd.getOwner(), owner);
    }

    function testOnlyOwnerCanCreateShd() public {
        vm.prank(user1);
        vm.expectRevert();
        shd.createShd();
    }

    function testIfCreationSuccess() public createShd{
        assertEq(shd.getShdDetails(0).keeper, address(shd));
        assertEq(shd.getCurrentPrice(0), initialPrice);
    }

    function testIfPurchaseOk() public createShd {
        vm.warp(block.timestamp + shd.getTradeTime() + 1);

        vm.startPrank(user1);
        shd.purchase(0);
        vm.stopPrank();

        vm.assertEq(shd.getShdDetails(0).keeper,user1);
        vm.assertEq(shd.getShdDetails(0).id,0);
        vm.assertEq(shd.getShdDetails(0).price, initialPrice);
        vm.assertEq(shd.getShdDetails(0).keeperReceiveTime, block.timestamp);
        vm.assertEq(shd.getShdDetails(0).tradeTime, block.timestamp);
    }
    
    function testIfTradeIsCoolDownAfterPurachase() public purchasedShd {
        vm.prank(user2);
        vm.expectRevert();
        shd.purchase(0);
    }

    function testIfDepositOk() public purchasedShd {
        vm. startPrank(user1);
        uint256 depositFees = shd._calculateDepositFees(initialPrice);
        shd.deposit(0,depositFees);
        vm.stopPrank();
    }

    function testIfCalculateFeesOk() public purchasedShd {
        vm.prank(user1);
        uint256 newPriceFees = 300000000000000000;
        uint256 tradeFees = 50000000000000000;

        assertEq(shd._calculateDepositFees(initialPrice), newPriceFees);
        assertEq(shd._calculateTradeFees(initialPrice), tradeFees);
    }

    function testIfSettleOk() public purchasedShd {
        vm.startPrank(user1);
        shd.deposit(0,firstDepositFees);
        vm.warp(block.timestamp + 3600);
        uint256 amount = shd._calculateCurrentUsageFees(0);

        shd.settle(0);
        vm.stopPrank();
        assertEq(firstDepositFees - amount, shd.checkFundsOf(user1));
        assertEq(shd.checkFundsOf(owner), amount);
    }

    function testIfSetPriceOk() public purchasedShd {
        vm.prank(user1);
        shd.setPrice(0, secondPrice, 700000000000000000);
        assertEq(shd.getShdDetails(0).price, secondPrice);
        assertEq(shd.checkFundsOf(user1), 700000000000000000);
    }

    function testIfPriceCooldownOk() public purchasedShd {
        vm.startPrank(user1);
        shd.setPrice(0, secondPrice,  shd._calculateDepositFees(secondPrice));

        uint256 depositFees = shd._calculateDepositFees(thirdPrice);
        vm.expectRevert();
        shd.setPrice(0, thirdPrice,depositFees);
        vm.stopPrank();

        vm.warp(block.timestamp + priceCooldown + 1);

        uint256 amount = shd.checkFundsOf(user1);
        vm.startPrank(user1);
        shd.setPrice(0, thirdPrice, shd._calculateDepositFees(thirdPrice));
        vm. stopPrank();

        assertEq(shd.checkFundsOf(user1), shd._calculateDepositFees(thirdPrice) + amount);
    }
    

    function testIfOtherUserCanPurchaseWithNewPrice() public purchasedShd {
        vm.startPrank(user1);
        uint256 setPriceFees = shd._calculateDepositFees(secondPrice);
        shd.setPrice(0, secondPrice, setPriceFees);
        vm.stopPrank();

        vm.startPrank(user2);
        shd.purchase(0);
        vm.stopPrank();

        vm.assertEq(shd.getShdDetails(0).keeper,user2);
    }

    function testIfWithdrawOk() public purchasedShd {
        vm.warp(block.timestamp +tradeCooldown + 1);

        vm.startPrank(user1);
        uint256 fees = shd._calculateTradeFees(secondPrice) + shd._calculateDepositFees(secondPrice);
        shd.setPrice(0, secondPrice, fees);
        vm.stopPrank();

        vm.startPrank(user2);
        shd.purchase(0);
        vm.stopPrank();

        vm.prank(user1);
        shd.withdraw(0,firstDepositFees);
    }

    function testIfReclaimOk() public purchasedShd{

        vm.startPrank(owner);
        vm.expectRevert();
        shd.reclaim(0, initialPrice);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days + 1);
        vm.prank(owner);
        shd.reclaim(0, initialPrice);

        assertEq(shd.getShdDetails(0).keeper, address(shd));
        
        assertEq(shd.getShdDetails(0).keeperReceiveTime, block.timestamp);
        assertEq(shd.getShdDetails(0).price, initialPrice);
        assertEq(shd.checkFundsOf(user1), 0);

    }
    function testIfwithdrawAllForBeneficiaryOk() public purchasedShd {
        vm.startPrank(user1);
        uint256 initialDepositFess = shd._calculateDepositFees(initialPrice);
        shd.deposit(0, initialDepositFess);
        vm.warp(block.timestamp + tradeCooldown);
        shd.settle(0);

        vm.stopPrank();

        uint256 user1Amount = shd.checkFundsOf(user1);
        uint256 ownerAmount = shd.checkFundsOf(owner);

        assertEq(initialDepositFess - user1Amount, ownerAmount);

    }

    function testIfSetFeesOk() public {
        vm.startPrank(owner);
        uint256 newUsageNumerator = 2_00;
        shd.setFees(newUsageNumerator);
        vm.stopPrank();

        uint256 usageNumerator = shd.getUsageNumerator();
        assertEq(usageNumerator, newUsageNumerator);
    }

    function testIfSettleOKAfterPurchase() public purchasedShd {
        vm. startPrank(user1);
        uint256 fees_ = shd._calculateDepositFees(secondPrice);
        shd.setPrice(0, secondPrice, fees_);
        vm.stopPrank();

        vm.warp(block.timestamp + tradeCooldown + 1);
        
        vm.startPrank(user2);
        uint256 user1Fees = shd._calculateCurrentUsageFees(0);
        shd.purchase(0);
        vm.stopPrank();

        assert(fees_ == user1Fees + shd.checkFundsOf(user1));

        vm.startPrank(user1);
        uint256 amount = shd.checkFundsOf(user1);
        shd.withdraw(0,amount);
        assertEq(fees_ - user1Fees, amount);
    }

    function testcheckUsePermissionForShd() public purchasedShd {
        vm.startPrank(user1);
        shd.setPrice(0, secondPrice, secondPrice);
        assertTrue(shd.checkUsePermissionForShd(0));
        vm.stopPrank();

        vm.startPrank(user2);
        assertFalse(shd.checkUsePermissionForShd(0));
        vm.stopPrank();

    }
}
