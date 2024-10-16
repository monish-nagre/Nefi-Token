// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "lib/openzeppelin-contracts/contracts/utils/Context.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";


contract NefiToken is Context, IERC20 {
    // using SafeMath for uint256;
    // Token properties
    string private constant _name = "NefiToken";
    string private constant _symbol = "NEFI";
    uint8 private constant _decimals = 18;
    uint256 private constant MAX_SUPPLY = 20000000 * 1e18; // 20 million with 18 decimals
    uint256 private _totalSupply;
    // Token mappings
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    // Contract-related properties
    IERC20 public immutable deodToken;
    address public defaultReferrer = 0x1234567890123456789012345678901234567890;
    address public nullAddress = 0x000000000000000000000000000000000000dEaD;
    // Staking and circulation properties
    uint256 public totalDeodStaked;
    uint256 public circulatingNefiSupply;
    // Referral properties
    uint256[6] public referralRewards = [7, 1, 1, 1, 1, 1];
    mapping(address => address) public referrals;
    mapping(address => uint256) public referralRewardsAccumulated;
    // User tracking
    mapping(address => uint256) public deodStaked;
    mapping(address => uint256) public unclaimedNefiTokens;
    mapping(address => uint256) public claimedNefiTokens;
    // Transaction records
    uint256 public nextBuyId;
    uint256 public nextSellId;
    mapping(uint256 => BuyRecord) public buyHistory;
    mapping(uint256 => SellRecord) public sellHistory;
    mapping(address => TransactionRecord[]) public buyRecordsByUser;
    mapping(address => TransactionRecord[]) public sellRecordsByUser;
    mapping(address => uint256) private lastActionTime;
    uint256 private actionCooldown = 1 minutes; // Cooldown period
    // Events
    event NefiTokenMinted(
        uint256 nefiMinted,
        uint256 currentNefiPrice,
        address user
    );
    event NefiTokenSold(
        uint256 nefiSold,
        uint256 currentNefiPrice,
        uint256 deodReturned,
        address user
    );
    event TokensClaimed(address user, uint256 amount);
    event ReferralRegistered(address user, address referrer);
    // Modifier to check if the cooldown period has passed for a user
    modifier cooldownPassed(string memory errorMessage) {
        require(
            block.timestamp >= lastActionTime[msg.sender] + actionCooldown,
            errorMessage
        );
        _;
    }

    // Modifier to check User can't Re-set the referer ReciprocalReferral.
    modifier noReciprocalReferral(address _referrer) {
        require(
            referrals[msg.sender] != _referrer,
            "Cannot set reciprocal referrer"
        );
        _;
    }

    // Structs
    struct BuyRecord {
        address buyer;
        uint256 amountInDeod;
        uint256 userAmount;
        address referrer;
        uint256 timestamp;
        uint256 buyId;
    }
    struct SellRecord {
        address seller;
        uint256 amountInNefi;
        uint256 deodReturned;
        uint256 timestamp;
        uint256 sellId;
    }
    struct TransactionRecord {
        uint256 amount;
        uint256 timestamp;
        uint256 transactionId;
    }

    constructor(address _deodToken) {
        deodToken = IERC20(_deodToken);
    }

    // BEP20 Standard Functions
    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        require(
            _allowances[sender][_msgSender()] >= amount,
            "BEP20: transfer amount exceeds allowance"
        );
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()] - amount
        );
        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "BEP20: transfer from the zero address");
        require(recipient != address(0), "BEP20: transfer to the zero address");
        // Instead of using SafeMath, Solidity's built-in checks will handle overflows and underflows
        require(
            _balances[sender] >= amount,
            "BEP20: transfer amount exceeds balance"
        );

        _balances[sender] -= amount;
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "BEP20: mint to the zero address");
        _totalSupply += amount;
        _balances[account] += amount;

        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "BEP20: burn from the zero address");
        // Ensure the account has enough balance before proceeding with the burn
        require(
            _balances[account] >= amount,
            "BEP20: burn amount exceeds balance"
        );
        _balances[account] -= amount;
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function isContract(address addr) internal view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(addr)
        }
        return (size > 0);
    }

    /**
     * @dev Allows users to claim their tokens based on their eligibility.
     * @param amount The amount of tokens the user is eligible to claim.
     */
    function claimTokens(uint256 amount) external  {
        require(_totalSupply + amount <= MAX_SUPPLY, "Max supply exceeded"); // Check against max supply
        require(
            unclaimedNefiTokens[msg.sender] >= amount,
            "Not enough unclaimed tokens"
        );
        unclaimedNefiTokens[msg.sender] -= amount;
        claimedNefiTokens[msg.sender] += amount;
        circulatingNefiSupply -= amount;
        _mint(address(this), amount);
        _transfer(address(this), msg.sender, amount);
        emit TokensClaimed(msg.sender, amount);
    }

    /**
     * @dev Facilitates the purchase of Nefi Tokens.
     * @param amountIn The amount of DEOD Tokens to stake.
     */
    function BuyNefiToken(uint256 amountIn)
        external
    {
        require(
            amountIn > 0 && amountIn <= 10000000000000000000000,
            "Amount must be greater than 0 and less than or equal to 10000"
        );
        uint256 currentPrice = getCurrentNefiPrice();
     
        uint256 nullAddressAmt = (amountIn * 3) / 100;
    
        uint256 AmtIn = amountIn - nullAddressAmt;
   
        totalDeodStaked += AmtIn;
        uint256 nefiToMint = (amountIn * 1e18) / currentPrice;

        uint256 userAmount = (nefiToMint * 70) / 100;
       
        uint256 burnAmount = (nefiToMint * 18) / 100;
        uint256 referralAmount = (nefiToMint * 12) / 100;
     
        uint256 realMint = nefiToMint - burnAmount;
     
        circulatingNefiSupply += (userAmount + referralAmount);
        deodStaked[msg.sender] += amountIn;
        unclaimedNefiTokens[msg.sender] += userAmount;
        address referrer = referrals[msg.sender];
        if (referrer == address(0)) {
            referrer = defaultReferrer;
        }
        distributeReferralRewards(referrer, referralAmount, nefiToMint);
        lastActionTime[msg.sender] = block.timestamp;
        uint256 transactionId = nextBuyId++;
        buyHistory[nextBuyId] = BuyRecord({
            buyer: msg.sender,
            amountInDeod: amountIn,
            userAmount: userAmount,
            referrer: referrer,
            timestamp: block.timestamp,
            buyId: nextBuyId
        });
        buyRecordsByUser[msg.sender].push(
            TransactionRecord({
                amount: AmtIn,
                timestamp: block.timestamp,
                transactionId: transactionId
            })
        );
        require(
            deodToken.transferFrom(msg.sender, address(this), amountIn),
            "Token transfer failed"
        );
        require(
            deodToken.transfer(nullAddress, nullAddressAmt),
            "Token transfer failed"
        );
        emit NefiTokenMinted(realMint, currentPrice, msg.sender);
    }

    /**
     * @dev Facilitates the purchase of Nefi Tokens.
     * @param amountIn The amount of NEFI Tokens to sell and get the DEOD acc. to price - platform fee.
     */
    function sellNefiToken(uint256 amountIn)
        external
    {
        require(amountIn > 0, "Amount must be greater than 0");
        uint256 currentPrice = getCurrentNefiPrice();
   
        require(
            unclaimedNefiTokens[msg.sender] >= amountIn,
            "Not enough unclaimed tokens to sell"
        );
        uint256 getDeod = (amountIn * currentPrice) / 1e18;
       
        uint256 fee = (getDeod * 15) / 100;
      
        uint256 userGetDeod = getDeod - fee;
       
        uint256 maxDeodAllowed = deodStaked[msg.sender] * 2;

        require(
            userGetDeod <= maxDeodAllowed,
            "Cannot withdraw more than 2x of staked DEOD"
        );
        unclaimedNefiTokens[msg.sender] -= amountIn;
        circulatingNefiSupply -= amountIn;
        totalDeodStaked -= userGetDeod;
        lastActionTime[msg.sender] = block.timestamp;
        require(
            deodToken.balanceOf(address(this)) >= userGetDeod,
            "Not enough DEOD in contract"
        );

        uint256 transactionId = nextSellId++;
        sellHistory[nextSellId] = SellRecord({
            seller: msg.sender,
            amountInNefi: amountIn,
            deodReturned: userGetDeod,
            timestamp: block.timestamp,
            sellId: nextSellId
        });
        sellRecordsByUser[msg.sender].push(
            TransactionRecord({
                amount: amountIn,
                timestamp: block.timestamp,
                transactionId: transactionId
            })
        );
        require(
            deodToken.transfer(msg.sender, userGetDeod),
            "Token transfer failed"
        );

        emit NefiTokenSold(amountIn, currentPrice, userGetDeod, msg.sender);
    }

    function getCurrentNefiPrice() public view returns (uint256) {
        if (circulatingNefiSupply == 0) {
            return 1e18; // Initial price 1:1 (1 DEOD = 1 MAGIC)
        }
        return (totalDeodStaked * 1e18) / circulatingNefiSupply;
    }

    function Register(address referrer)
        external
        noReciprocalReferral(referrer)
    {
        require(!isContract(referrer), "Contracts cannot be referrers");
        require(referrals[msg.sender] == address(0), "Referrer already set");
        require(referrer != msg.sender, "Self-referral prohibited");

        referrals[msg.sender] = referrer;
        emit ReferralRegistered(msg.sender, referrer);
    }

    /**
     * @dev Distributes referral rewards to users based on the referral program.
     */
    function distributeReferralRewards(
        address referrer,
        uint256 totalReferralAmount,
        uint256 nefiToMint
    ) internal {
        address currentReferrer = referrer;
        uint256 remainingAmount = totalReferralAmount;
        for (uint256 i = 0; i < 6; i++) {
            if (currentReferrer == address(0)) {
                break;
            }
            uint256 refReward = (nefiToMint * referralRewards[i]) / 100;
            
            remainingAmount -= refReward;
        
            unclaimedNefiTokens[currentReferrer] += refReward;
            referralRewardsAccumulated[currentReferrer] += refReward;
            currentReferrer = referrals[currentReferrer];
        
        }
        if (remainingAmount > 0) {
            unclaimedNefiTokens[defaultReferrer] += remainingAmount;
            referralRewardsAccumulated[defaultReferrer] += remainingAmount;
         
        }
    }
}
