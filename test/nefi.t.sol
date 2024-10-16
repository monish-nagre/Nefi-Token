// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/nefi.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockDEODToken is ERC20 {
    constructor() ERC20("DEOD Token", "DEOD") {
        _mint(msg.sender, 10000 * 1e18); // Mint some DEOD tokens to deployer
    }

    function mint(address to, uint256 amount) public  {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}

contract NefiTokenTest is Test {
    NefiToken public nefiToken;
    MockDEODToken public deodToken;
    address public user1;
    address public user2;

    function setUp() public {
        deodToken = new MockDEODToken();
        nefiToken = new NefiToken(address(deodToken));
        user1 = address(0x1);
        user2 = address(0x2);
    }

    function testInitialSetup() public view {
        assertEq(nefiToken.name(), "NefiToken");
        assertEq(nefiToken.symbol(), "NEFI");
        assertEq(nefiToken.decimals(), 18);
        assertEq(nefiToken.totalSupply(), 0);
    }

    function testBuyNefiToken() public {
 
    vm.startPrank(user1);

    uint256 userBalance = 1000 * 1e18; 
    deodToken.mint(user1, userBalance); 

    assertEq(deodToken.balanceOf(user1), userBalance);

    deodToken.approve(address(nefiToken), userBalance);

    nefiToken.BuyNefiToken(userBalance);

    assertEq(nefiToken.unclaimedNefiTokens(user1), 700 * 1e18); 
    assertEq(nefiToken.deodStaked(user1), 1000 * 1e18);

  
    vm.stopPrank();
}

    function testSellNefiToken() public {
        vm.startPrank(user1);
        uint256 userBalance = 1000 * 1e18; 
        deodToken.mint(user1, userBalance); 

        deodToken.approve(address(nefiToken), 1000 * 1e18); 
        nefiToken.BuyNefiToken(1000 * 1e18); 

        // Now sell the tokens
        uint256 nefiToSell = 700 * 1e18;
        nefiToken.sellNefiToken(nefiToSell);
        
        assertEq(nefiToken.unclaimedNefiTokens(user1), 0);
       
        uint256 expectedDeodReturned = (nefiToSell * nefiToken.getCurrentNefiPrice()) / 1e18;
        assert(deodToken.balanceOf(user1) > 0);
        vm.stopPrank();
    }

    function testRegisterReferrer() public {
        vm.startPrank(user1);
        nefiToken.Register(user2); 
        assertEq(nefiToken.referrals(user1), user2);
        vm.stopPrank();
    }

    function testClaimTokens() public {
        vm.startPrank(user1);
        uint256 userBalance = 1000 * 1e18;
        deodToken.mint(user1, userBalance); 
        deodToken.approve(address(nefiToken), 1000 * 1e18); 
        nefiToken.BuyNefiToken(1000 * 1e18); 
        nefiToken.claimTokens(700 * 1e18); 

        assertEq(nefiToken.claimedNefiTokens(user1), 700 * 1e18); 
        assertEq(nefiToken.totalSupply(), 700 * 1e18); 
        vm.stopPrank();
    }

    function testForBalance() public {
        vm.startPrank(user1);
        uint256 userBalance = 1000 * 1e18;
        deodToken.mint(user1, userBalance);
        assertEq(deodToken.balanceOf(user1), userBalance);
    }

     //----------------------------------------------------------------------------------//

    // Fuzz Test: BuyNefiToken
  function testFuzz_BuyNefiToken(uint256 amountIn) public {
    // Limit the fuzzing range to a valid range for the test
    vm.assume(amountIn > 0 && amountIn <= 10000 * 1e18); 
    vm.startPrank(user1);

    uint256 userBalance = amountIn; 
    deodToken.mint(user1, userBalance); 

    assertEq(deodToken.balanceOf(user1), userBalance); 

    deodToken.approve(address(nefiToken), userBalance); 

    nefiToken.BuyNefiToken(userBalance); 


    uint256 expectedNefiToMint = (amountIn * 70) / 100; 
    uint256 expectedDeodStaked = amountIn;
   
    assertEq(nefiToken.unclaimedNefiTokens(user1), expectedNefiToMint); 
    assertEq(nefiToken.deodStaked(user1), expectedDeodStaked);

    vm.stopPrank();
  }
}
