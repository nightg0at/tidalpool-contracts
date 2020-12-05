pragma solidity ^0.6.2;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
//import "./TidalToken.sol";
import "./TideToken.sol";

/* START OF SURF TIDALPOOL EXPLANATION

This is a copy of PoliceChief
https://etherscan.io/address/0x669Bffac935Be666219c68D20931CBf677b8Fa1C
with a few differences, all annoted with the comment "TIDAL EDIT"
to make it easy to verify that it is a copy.

Difference 1:

When the supply goes above 69, TIDAL burn rates are increased 
dramatically and emissions cut, and when supply goes below 42, 
emissions are increased dramatically and burn rates cut, 
resulting in a token that has a total supply pegged between 
42 and 69.

Difference 2:

The dev fund is set to 0.42% instead of 10%, so
no rug pulls.

Difference 3:

No change to PoliceChief (Migrator still removed)

Difference 4:

We levy a withdraw fee on LP tokens during the deflation (burn)
phase. Half the tax is used to buy SURF and send it to the whirlpool,
the other half is used to buy and burn TIDAL.

Emissions:

The initial sushi per block is set to 5000000000000000 (0.005)
TIDAL per block, which leads to ~420 TIDAL every 2 weeks.


END OF SURF TIDALPOOL EXPLANATION */


/* START OF POLICE CHIEF EXPLANATION

PoliceChief is a copy of SushiSwap's MasterChef 
https://etherscan.io/address/0xc2edad668740f1aa35e4d8f227fb8e17dca888cd
with a few differences, all annoted with the comment "NICE EDIT"
to make it easy to verify that it is a copy.

Difference 1:

When the supply goes above 420, NICE burn rates are increased 
dramatically and emissions cut, and when supply goes below 69, 
emissions are increased dramatically and burn rates cut, 
resulting in a token that has a total supply pegged between 
69 and 420.

Difference 2:

The dev fund is set to 0.69% (nice) instead of 10%, so
no rug pulls.

Difference 3:

Migrator is removed, so LP staked in PoliceChief are
100% safe and cannot be stolen by the owner. This removes
the need to use a timelock, because the only malicious thing
the PoliceChief owner can do is add sketchy pools, which do
not endanger your LP https://twitter.com/Quantstamp/status/1301280991021993984

Emissions:

The initial sushi per block is set to 5000000000000000 (0.005)
NICE per block, which leads to ~420 NICE very 2 weeks.

END OF POLICE CHIEF EXPLANATION */


// TIDAL EDIT: See Difference 4 above, and convertAndBurn() towards the bottom


// can we add surf directly instead?

interface Whirlpool {
  function addEthReward() external payable;
}

// TIDAL EDIT: WETH interface so we can convert WETH => ETH
interface EtherToken {
  function withdraw(uint amount) external;
}

// Here at Tidal we think there are more important things to do than a find & replace
// Sushi key words.
//
// PoliceChief is the master of Sushi. He can make Sushi and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SUSHI is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract Poseidon is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of SUSHIs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accSushiPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accSushiPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. SUSHIs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that SUSHIs distribution occurs.
        uint256 accSushiPerShare; // Accumulated SUSHIs per share, times 1e12. See below.
    }

    // TIDAL EDIT: Additionally required contracts
    IUniswapV2Router02 public router;
    Whirlpool public whirlpool;
    EtherToken public weth;


    // TIDAL EDIT: Use TidalToken instead of NiceToken instead of SushiToken
    // NICE EDIT: Use NiceToken instead of SushiToken
    // The SUSHI TOKEN!
    //TidalToken public sushi;

    TideToken public tidal;
    TideToken public riptide;

    // TIDAL EDIT: Set the dev fund to 0.42% instead of 0.69%
    // NICE EDIT: Set the dev fund to 0.69% (nice) instead of 10%
    // Dev address.
    address public devaddr;

    // Block number when bonus SUSHI period ends.
    uint256 public bonusEndBlock;
    // SUSHI tokens created per block.
    uint256 public sushiPerBlock;
    // Bonus muliplier for early sushi makers.
    uint256 public constant BONUS_MULTIPLIER = 10;
    // NICE EDIT: Remove migrator to protect LP tokens
    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    // IMigratorChef public migrator;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when SUSHI mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    // NICE EDIT: Don't add same pool twice https://twitter.com/Quantstamp/status/1301280989906231296
    mapping (address => bool) private poolIsAdded;

    // NICE EDIT: If isInflating is true supply has not yet reached 420 and NICE is inflating
    bool public isInflating = true;

    // TIDAL EDIT: If divisor is 0, set minting to 0 instead of dividing
    // NICE EDIT: Divide mint by this number during deflation periods
    uint256 public deflationMintDivisor = 0;

    // TIDAL EDIT: Change deflation burn from 20% to 7%
    // NICE EDIT: Burn this amount per transaction during inflation/deflation periods
    // those are defaults and can be safely changed by governance with setDivisors
    uint256 public deflationBurnDivisor = 15; // 100 / 15 ~= 6.66..%
    //uint256 public deflationBurnDivisor = 5; // 100 / 5 == 20%
    uint256 public inflationBurnDivisor = 100; // 100 / 100 == 1%

    // TIDAL EDIT: LP withdrawal fee during deflation
    // These tokens are sold for surf and tidal
    // surf are sent to whirlpool, tidal are burned
    uint256 public deflationWithdrawFeeDivisor = 10; // 100 / 10 == 10%

    // NICE EDIT: Allow governance to adjust mint and burn rates during 
    // defation periods in case it's too low / too high, not a dangerous function
    function setDivisors(
      uint256 _deflationMintDivisor,
      uint256 _deflationBurnDivisor,
      uint256 _inflationBurnDivisor,
      uint256 _deflationWithdrawFeeDivisor
    ) public onlyOwner {
        // TIDAL EDIT: We allow 0 and treat it as a special case
        //require(_deflationMintDivisor > 0, "setDivisors: deflationMintDivisor must be bigger than 0");
        deflationMintDivisor = _deflationMintDivisor;
        deflationBurnDivisor = _deflationBurnDivisor;
        inflationBurnDivisor = _inflationBurnDivisor;
        deflationWithdrawFeeDivisor = _deflationWithdrawFeeDivisor;

        // always try setting both numbers to make sure 
        // they both don't revert
        if (isInflating) {
            sushi.setBurnDivisor(deflationBurnDivisor);
            sushi.setBurnDivisor(inflationBurnDivisor);
        }
        else {
            sushi.setBurnDivisor(inflationBurnDivisor);
            sushi.setBurnDivisor(deflationBurnDivisor);
        }
    }

    // TIDAL EDIT: 42 and 69 intead of 69 and 420

    // NICE EDIT: Call this function every pool update, if total supply
    // is above 420, start deflation, if under 69, start inflation
    function updateIsInflating() public {
        // was inflating, should start deflating
        if (isInflating == true && sushi.totalSupply() > 69e18) {
            isInflating = false;
            sushi.setBurnDivisor(deflationBurnDivisor);
        }
        // was deflating, should start inflating
        else if (isInflating == false && sushi.totalSupply() < 42e18) {
            isInflating = true;
            sushi.setBurnDivisor(inflationBurnDivisor);
        }
    }

    // NICE EDIT: Read only util function for easier access from website, never called internally
    function niceBalancePendingHarvest(address _user) public view returns (uint256) {
        uint256 totalPendingNice = 0;
        uint256 poolCount = poolInfo.length;
        for (uint256 pid = 0; pid < poolCount; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            UserInfo storage user = userInfo[pid][_user];
            uint256 accSushiPerShare = pool.accSushiPerShare;
            uint256 lpSupply = pool.lpToken.balanceOf(address(this));
            if (block.number > pool.lastRewardBlock && lpSupply != 0) {
                uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
                uint256 sushiReward = multiplier.mul(sushiPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
                if (!isInflating) {
                  // TIDAL EDIT: We allow rewards to be 0 but can't divide by it
                  if (deflationMintDivisor == 0) {
                    sushiReward = 0;
                  } else {
                    sushiReward = sushiReward.div(deflationMintDivisor);
                  }
                }
                accSushiPerShare = accSushiPerShare.add(sushiReward.mul(1e12).div(lpSupply));
            }
            totalPendingNice = totalPendingNice.add(user.amount.mul(accSushiPerShare).div(1e12).sub(user.rewardDebt));
        }
        return totalPendingNice;
    }

    // NICE EDIT: Read only util function for easier access from website, never called internally
    function niceBalanceStaked(address _user) public view returns (uint256) {
        uint256 totalNiceStaked = 0;
        uint256 poolCount = poolInfo.length;
        for (uint256 pid = 0; pid < poolCount; ++pid) {
            UserInfo storage user = userInfo[pid][_user];
            if (user.amount == 0) {
                continue;
            }
            PoolInfo storage pool = poolInfo[pid];
            uint256 uniswapPairNiceBalance = sushi.balanceOf(address(pool.lpToken));
            if (uniswapPairNiceBalance == 0) {
                continue;
            }
            uint256 userPercentOfLpOwned = user.amount.mul(1e12).div(pool.lpToken.totalSupply());
            totalNiceStaked = totalNiceStaked.add(uniswapPairNiceBalance.mul(userPercentOfLpOwned).div(1e12));
        }
        return totalNiceStaked;
    }

    // NICE EDIT: Read only util function for easier access from website, never called internally
    function niceBalanceAll(address _user) external view returns (uint256) {
        return sushi.balanceOf(_user).add(niceBalanceStaked(_user)).add(niceBalancePendingHarvest(_user));
    }

    constructor(
        // TIDAL EDIT: Use two TideTokens instead of one NiceToken
        // Add the uniswap router
        // NICE EDIT: Use NiceToken instead of SushiToken
        //TidalToken _sushi,
        TideToken _tidal,
        TideToken _riptide,
        IUniswapV2Router02 _router,
        Whirlpool _whirlpool,
        address _devaddr,
        uint256 _sushiPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) public {
        //sushi = _sushi;
        tidal = _tidal;
        riptide = _riptide;
        router = _router;
        whirlpool = _whirlpool;
        weth = EtherToken(router.WETH());
        devaddr = _devaddr;
        sushiPerBlock = _sushiPerBlock;
        bonusEndBlock = _bonusEndBlock;
        startBlock = _startBlock;
    }

    // TIDAL EDIT: required because of convertAndBurn();
    receive() external payable {
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        // NICE EDIT: Don't add same pool twice https://twitter.com/Quantstamp/status/1301280989906231296
        require(poolIsAdded[address(_lpToken)] == false, 'add: pool already added');
        poolIsAdded[address(_lpToken)] = true;

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accSushiPerShare: 0
        }));
    }

    // Update the given pool's SUSHI allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // NICE EDIT: Remove migrator to protect LP tokens
    // Set the migrator contract. Can only be called by the owner.
    // function setMigrator(IMigratorChef _migrator) public onlyOwner {
    //     migrator = _migrator;
    // }

    // NICE EDIT: Remove migrator to protect LP tokens
    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    // function migrate(uint256 _pid) public {
    //     require(address(migrator) != address(0), "migrate: no migrator");
    //     PoolInfo storage pool = poolInfo[_pid];
    //     IERC20 lpToken = pool.lpToken;
    //     uint256 bal = lpToken.balanceOf(address(this));
    //     lpToken.safeApprove(address(migrator), bal);
    //     IERC20 newLpToken = migrator.migrate(lpToken);
    //     require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
    //     pool.lpToken = newLpToken;
    // }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            return _to.sub(_from);
        } else {
            return bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
                _to.sub(bonusEndBlock)
            );
        }
    }

    // View function to see pending SUSHIs on frontend.
    function pendingSushi(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSushiPerShare = pool.accSushiPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 sushiReward = multiplier.mul(sushiPerBlock).mul(pool.allocPoint).div(totalAllocPoint);

            // NICE EDIT: During deflation periods, cut the reward by the deflationMintDivisor amount
            if (!isInflating) {
                // TIDAL EDIT: We allow rewards to be 0 but can't divide by it
                if (deflationMintDivisor == 0) {
                  sushiReward = 0;
                } else {
                  sushiReward = sushiReward.div(deflationMintDivisor);
                }
            }

            accSushiPerShare = accSushiPerShare.add(sushiReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accSushiPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        // TIDAL EDIT: If total supply is above 69, start deflation, if under 42, start inflation
        // NICE EDIT: If total supply is above 420, start deflation, if under 69, start inflation
        updateIsInflating();

        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 sushiReward = multiplier.mul(sushiPerBlock).mul(pool.allocPoint).div(totalAllocPoint);

        // NICE EDIT: During deflation periods, cut the reward by the deflationMintDivisor amount
        if (!isInflating) {
          // TIDAL EDIT: We allow rewards to be 0 but can't divide by it
          if (deflationMintDivisor == 0) {
            sushiReward = 0;
          } else {
            sushiReward = sushiReward.div(deflationMintDivisor);
          }
        }

        // TIDAL EDIT: Set the dev fund to 0.42%
        // NICE EDIT: Set the dev fund to 0.69% (nice)
        sushi.mint(devaddr, sushiReward.div(238)); // 100 / 238 == 0.4201680672268908
        //sushi.mint(devaddr, sushiReward.div(144)); // 100 / 144 == 0.694444444
        // sushi.mint(devaddr, sushiReward.div(10));

        sushi.mint(address(this), sushiReward);
        pool.accSushiPerShare = pool.accSushiPerShare.add(sushiReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to PoliceChief for SUSHI allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accSushiPerShare).div(1e12).sub(user.rewardDebt);
            safeSushiTransfer(msg.sender, pending);
        }
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accSushiPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from PoliceChief.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accSushiPerShare).div(1e12).sub(user.rewardDebt);
        safeSushiTransfer(msg.sender, pending);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accSushiPerShare).div(1e12);
        // TIDAL EDIT: LP withdrawal fee during deflation
        if (!isInflating) {
          uint256 taxAmount = _amount.div(deflationWithdrawFeeDivisor);
          uint256 withdrawAmount = _amount.sub(taxAmount);
          convertAndBurn(taxAmount, pool.lpToken);
          pool.lpToken.safeTransfer(address(msg.sender), withdrawAmount);
        }
        //pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // TIDAL EDIT: A new function to convert the taxed amount into surf and tidal
    // sending tidal to burn and surf to whirlpool
    function convertAndBurn(uint256 _lpAmount, IERC20 _lpToken) internal {
      IUniswapV2Pair pair = IUniswapV2Pair(address(_lpToken));
      uint256 deadline = block.timestamp + 5 minutes;

      // grab the tokens
      address[] memory t = new address[](2);
      t[0] = pair.token0();
      t[1] = pair.token1();

      // remove liquidity
      uint256[] memory tAmount = new uint256[](2);
      (tAmount[0], tAmount[1]) = router.removeLiquidity(
        t[0],
        t[1],
        _lpAmount,
        0,
        0,
        address(this),
        deadline
      );

      // convert underlying tokens to ETH
      for (uint i=0; i<2; i++) {
        if (t[i] == address(weth)) {
          // WETH => ETH
          weth.withdraw(tAmount[i]);
        } else {
          // sell for ETH
          address[] memory sellPath = new address[](2);
          sellPath[0] = t[i];
          sellPath[1] = address(weth);
          router.swapExactTokensForETH(
            tAmount[i],
            0,
            sellPath,
            address(this),
            deadline
          );
        }
      }
      
      // amounts
      uint256 surfETH = address(this).balance.div(2);
      uint256 tidalETH = address(this).balance.sub(surfETH);
      uint256 tidalBalanceBefore = sushi.balanceOf(address(this));

      // send ETH to whirlpool (which buys surf to distribute to users)
      whirlpool.addEthReward{value: surfETH}();

      // markey buy tidal
      address[] memory buyPath = new address[](2);
      buyPath[0] = address(weth);
      buyPath[1] = address(sushi);
      router.swapExactETHForTokens{value: tidalETH}(
        0,
        buyPath,
        address(this),
        deadline
      );

      // burn tidal
      uint256 burnAmount = sushi.balanceOf(address(this)).sub(tidalBalanceBefore);
      sushi.burn(address(this), burnAmount);
    }

    // Safe sushi transfer function, just in case if rounding error causes pool to not have enough SUSHIs.
    function safeSushiTransfer(address _to, uint256 _amount) internal {
      uint256 sushiBal = sushi.balanceOf(address(this));
      if (_amount > sushiBal) {
          sushi.transfer(_to, sushiBal);
      } else {
          sushi.transfer(_to, _amount);
      }
    }

    function dev(address _devaddr) public {
      // NICE EDIT: Minting to 0 address reverts and breaks harvesting
      require(_devaddr != address(0), "dev: don't set to 0 address");
      require(msg.sender == devaddr, "dev: wut?");
      devaddr = _devaddr;
    }

}
