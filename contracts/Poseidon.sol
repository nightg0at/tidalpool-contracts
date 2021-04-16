/*
    The farming contract

    MasterChef
    + restaking rewards
    + dual toggled token rewards

    Thanks sushiswap, surf, niceee, dracula.

    @nightg0at
    SPDX-License-Identifier: MIT
*/

pragma solidity 0.6.12;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./ds-math/math.sol";
import "./restaking/interfaces/IStakingAdapter.sol";
import "./interfaces/ITideToken.sol";

// MasterChef is the master of Sushi. He can make Sushi and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SUSHI is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract Poseidon is Ownable, DSMath {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 tidalRewardDebt; // Reward debt. See explanation below.
        uint256 riptideRewardDebt; // Reward debt. See explanation below.
        uint256 otherRewardDebt;
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
        uint256 withdrawFee; // Amount of LP liquidated on withdraw (often 0)
        uint256 lastRewardBlock;  // Last block number that SUSHIs distribution occurs.
        uint256 accTidalPerShare; // Accumulated SUSHIs per share, times 1e12. See below.
        uint256 accRiptidePerShare; // Accumulated SUSHIs per share, times 1e12. See below.
        uint256 accOtherPerShare; // Accumulated OTHERs per share, times 1e12. See below.
        IStakingAdapter adapter; // Manages external farming
        IERC20 otherToken; // The OTHER reward token for this pool, if any
    }

    IUniswapV2Router02 router;

    ITideToken public tidal;
    ITideToken public riptide;
    IERC20 public boon;

    // Dev address.
    address public devaddr;
    // Fee address
    address public feeaddr;
    // Reward tokens created per block.
    uint256 public baseRewardPerBlock = 2496e11; // base reward token emission (0.0002496)
    uint256 public devDivisor = 238; // dev fund of 4.2%, 1000/238 = 4.20168...

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when SUSHI mining starts.
    uint256 public startBlock;

    // Don't add the same pool twice
    mapping (address => bool) private poolIsAdded;

    // Tide phase. The address of either tidal or riptide. Tidal to start
    address public phase;
    uint256 public constant TIDAL_CAP = 69e18;
    uint256 public constant TIDAL_VERTEX = 42e18;

    // weather
    bool public stormy = false;
    uint256 public stormDivisor = 2;

    // weather god
    address public zeus;

    // surf and whirlpool
    address public surf;
    address public whirlpool;


    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        IUniswapV2Router02 _router,
        ITideToken _tidal,
        ITideToken _riptide,
        IERC20 _boon,
        address _surf, // 0xEa319e87Cf06203DAe107Dd8E5672175e3Ee976c
        address _whirlpool, // 0x999b1e6EDCb412b59ECF0C5e14c20948Ce81F40b
        address _devaddr,
        uint256 _startBlock
    ) public {
        router = _router;
        tidal = _tidal;
        riptide = _riptide;
        boon = _boon;
        surf = _surf;
        whirlpool = _whirlpool;
        devaddr = _devaddr;
        feeaddr = _devaddr;
        startBlock = _startBlock;
        phase = address(_tidal);
    }

    // rudimentary checks for the staking adapter
    modifier validAdapter(IStakingAdapter _adapter) {
        require(address(_adapter) != address(0), "no adapter specified");
        require(_adapter.rewardTokenAddress() != address(0), "no other reward token specified in staking adapter");
        require(_adapter.lpTokenAddress() != address(0), "no staking token specified in staking adapter");
        _;
    }

    modifier onlyZeus() {
        require(msg.sender == zeus, "only zeus can call this method");
        _;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // This is assumed to not be a restaking pool.
    // Restaking can be added later or with addWithRestaking() instead of add()
    function add(uint256 _allocPoint, IERC20 _lpToken, uint256 _withdrawFee, bool _withUpdate) public onlyOwner {
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
            withdrawFee: _withdrawFee,
            lastRewardBlock: lastRewardBlock,
            accTidalPerShare: 0,
            accRiptidePerShare: 0,
            accOtherPerShare: 0,
            adapter: IStakingAdapter(0),
            otherToken: IERC20(0)
        }));
    }

    // Add a new lp to the pool that uses restaking. Can only be called by the owner.
    function addWithRestaking(uint256 _allocPoint, uint256 _withdrawFee, bool _withUpdate, IStakingAdapter _adapter) public onlyOwner validAdapter(_adapter) {
        IERC20 _lpToken = IERC20(_adapter.lpTokenAddress());

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
            withdrawFee: _withdrawFee,
            lastRewardBlock: lastRewardBlock,
            accTidalPerShare: 0,
            accRiptidePerShare: 0,
            accOtherPerShare: 0,
            adapter: _adapter,
            otherToken: IERC20(_adapter.rewardTokenAddress())
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

    // Set a new restaking adapter.
    function setRestaking(uint256 _pid, IStakingAdapter _adapter, bool _claim) public onlyOwner validAdapter(_adapter) {
        if (_claim) {
            updatePool(_pid);
        }
        if (isRestaking(_pid)) {
            withdrawRestakedLP(_pid);
        }
        PoolInfo storage pool = poolInfo[_pid];
        require(address(pool.lpToken) == _adapter.lpTokenAddress(), "LP mismatch");
        pool.accOtherPerShare = 0;
        pool.adapter = _adapter;
        pool.otherToken = IERC20(_adapter.rewardTokenAddress());

        // transfer LPs to new target if we have any
        uint256 poolBal = pool.lpToken.balanceOf(address(this));
        if (poolBal > 0) {
            pool.lpToken.safeTransfer(address(pool.adapter), poolBal);
            pool.adapter.deposit(poolBal);
        }
    }

    // remove restaking
    function removeRestaking(uint256 _pid, bool _claim) public onlyOwner {
        require(isRestaking(_pid), "not a restaking pool");
        if (_claim) {
            updatePool(_pid);
        }
        withdrawRestakedLP(_pid);
        poolInfo[_pid].adapter = IStakingAdapter(address(0));
        require(!isRestaking(_pid), "failed to remove restaking");
    }

    // should always be called with update unless prohibited by gas
    function setWeather(bool _isStormy, bool _withUpdate) public onlyZeus {
        if (_withUpdate) {
            massUpdatePools();
        }
        stormy = _isStormy;
    }

    function setWeatherConfig(address _newZeus, uint256 _newStormDivisor) public onlyOwner {
        require(_newStormDivisor != 0, "Cannot divide by zero");
        stormDivisor = _newStormDivisor;
        zeus = _newZeus; // can be address(0)
    }

    function setRewardPerBlock(uint256 _newReward) public onlyOwner {
        baseRewardPerBlock = _newReward;
    }

    // used if surf.finance upgrade their contracts
    function setSurfConfig(address _newSurf, address _newWhirlpool) public onlyOwner {
        surf = _newSurf;
        whirlpool = _newWhirlpool;
    }

    function _tokensPerBlock(address _tideToken) internal view returns (uint256) {
        if (phase == _tideToken) {
            if (stormy) {
                return baseRewardPerBlock.div(stormDivisor);
            } else {
                return baseRewardPerBlock;
            }
        } else {
            return 0;
        }
    }

    function tokensPerBlock(address _tideToken) external view returns (uint256) {
        return _tokensPerBlock(_tideToken);
    }

    // View function to see pending tide tokens on frontend.
    function pendingTokens(uint256 _pid, address _user) external view returns (uint256, uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTidalPerShare = pool.accTidalPerShare;
        uint256 accRiptidePerShare = pool.accRiptidePerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (isRestaking(_pid)) {
            lpSupply = pool.adapter.balance();
        }
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            // we don't have a bonus multiplier stage, so just work out the unclaimed blockspan
            uint256 span = block.number.sub(pool.lastRewardBlock);
            // get pending tokens if we are in phase
            uint256 pendingTidal = 0;
            uint256 pendingRiptide = 0;
            if (phase == address(tidal)) {
                pendingTidal = span.mul(_tokensPerBlock(address(tidal))).mul(pool.allocPoint).div(totalAllocPoint);
            } else if (phase == address(riptide)) {
                pendingRiptide = span.mul(_tokensPerBlock(address(riptide))).mul(pool.allocPoint).div(totalAllocPoint);
            }
            accTidalPerShare = accTidalPerShare.add(pendingTidal.mul(1e12).div(lpSupply));
            accRiptidePerShare = accRiptidePerShare.add(pendingRiptide.mul(1e12).div(lpSupply));
        }
        uint256 unclaimedTidal = user.amount.mul(accTidalPerShare).div(1e12).sub(user.tidalRewardDebt);
        uint256 unclaimedRiptide = user.amount.mul(accRiptidePerShare).div(1e12).sub(user.riptideRewardDebt);
        return (unclaimedTidal, unclaimedRiptide);
    }

    // View function to see our pending OTHERs on frontend (whatever the restaked reward token is)
    function pendingOther(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accOtherPerShare = pool.accOtherPerShare;
        uint256 lpSupply = pool.adapter.balance();
 
        if (lpSupply != 0) {
            uint256 otherReward = pool.adapter.pending();
            accOtherPerShare = accOtherPerShare.add(otherReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accOtherPerShare).div(1e12).sub(user.otherRewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {

        updatePhase();

        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        uint256 lpSupply = getPoolSupply(_pid);
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        if (isRestaking(_pid)) {
            uint256 pendingOtherTokens = pool.adapter.pending();
            if (pendingOtherTokens >= 0) {
                uint256 otherBalanceBefore = pool.otherToken.balanceOf(address(this));
                pool.adapter.claim();
                uint256 otherBalanceAfter = pool.otherToken.balanceOf(address(this));
                pendingOtherTokens = otherBalanceAfter.sub(otherBalanceBefore);
                pool.accOtherPerShare = pool.accOtherPerShare.add(pendingOtherTokens.mul(1e12).div(lpSupply));
            }
        }

        uint256 span = block.number.sub(pool.lastRewardBlock);
        if (phase == address(tidal)) {
            uint256 tidalReward = span.mul(_tokensPerBlock(address(tidal))).mul(pool.allocPoint).div(totalAllocPoint);
            uint256 devTidalReward = tidalReward.mul(10).div(devDivisor);
            if (tidal.totalSupply().add(tidalReward).add(devTidalReward) > TIDAL_CAP) {
                // we would exceed the cap
                uint256 totalTidalReward = TIDAL_CAP.sub(tidal.totalSupply());
                // split proportionally
                uint256 newDevTidalReward = totalTidalReward.mul(10).div(devDivisor-10); // ~ reverse percentage approximation
                uint256 newTidalReward = totalTidalReward.sub(newDevTidalReward);
                tidal.mint(devaddr, newDevTidalReward); 
                tidal.mint(address(this), newTidalReward);
                pool.accTidalPerShare = pool.accTidalPerShare.add(newTidalReward.mul(1e12).div(lpSupply));

                uint256 totalRiptideReward = tidalReward.sub(totalTidalReward);
                uint256 newDevRiptideReward = totalRiptideReward.mul(10).div(devDivisor-10);
                uint256 newRiptideReward = totalRiptideReward.sub(newDevRiptideReward);
                riptide.mint(devaddr, newDevRiptideReward);
                riptide.mint(devaddr, newRiptideReward);
                pool.accRiptidePerShare = pool.accRiptidePerShare.add(newRiptideReward.mul(1e12).div(lpSupply));
            } else {
                tidal.mint(devaddr, devTidalReward); 
                tidal.mint(address(this), tidalReward);
                pool.accTidalPerShare = pool.accTidalPerShare.add(tidalReward.mul(1e12).div(lpSupply));
            }
        } else {
            uint256 riptideReward = span.mul(_tokensPerBlock(address(riptide))).mul(pool.allocPoint).div(totalAllocPoint);
            riptide.mint(devaddr, riptideReward.mul(10).div(devDivisor));
            riptide.mint(address(this), riptideReward);
            pool.accRiptidePerShare = pool.accRiptidePerShare.add(riptideReward.mul(1e12).div(lpSupply));
        }
        pool.lastRewardBlock = block.number;
    }

    // Internal view function to get the amount of LP tokens staked in the specified pool
    function getPoolSupply(uint256 _pid) internal view returns (uint256 lpSupply) {
        PoolInfo memory pool = poolInfo[_pid];
        if (isRestaking(_pid)) {
            lpSupply = pool.adapter.balance();
        } else {
            lpSupply = pool.lpToken.balanceOf(address(this));
        }
    }

    function isRestaking(uint256 _pid) public view returns (bool outcome) {
        if (address(poolInfo[_pid].adapter) != address(0)) {
            outcome = true;
        } else {
            outcome = false;
        }
    }

    // Deposit LP tokens to MasterChef for SUSHI allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        uint256 pendingOtherTokens = 0;
        if (user.amount > 0) {
            uint256 pendingTidal = user.amount.mul(pool.accTidalPerShare).div(1e12).sub(user.tidalRewardDebt);
            if(pendingTidal > 0) {
                safeTideTransfer(msg.sender, pendingTidal, tidal);
            }
            uint256 pendingRiptide = user.amount.mul(pool.accRiptidePerShare).div(1e12).sub(user.riptideRewardDebt);
            if(pendingRiptide > 0) {
                safeTideTransfer(msg.sender, pendingRiptide, riptide);
            }
            pendingOtherTokens = user.amount.mul(pool.accOtherPerShare).div(1e12).sub(user.otherRewardDebt);
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if (isRestaking(_pid)) {
                pool.lpToken.safeTransfer(address(pool.adapter), _amount);
                pool.adapter.deposit(_amount);
            }
            user.amount = user.amount.add(_amount);
        }
        // we can't guarantee we have the tokens until after adapter.deposit()
        if (pendingOtherTokens > 0) {
            safeOtherTransfer(msg.sender, pendingOtherTokens, _pid);
        }
        user.tidalRewardDebt = user.amount.mul(pool.accTidalPerShare).div(1e12);
        user.riptideRewardDebt = user.amount.mul(pool.accRiptidePerShare).div(1e12);
        user.otherRewardDebt = user.amount.mul(pool.accOtherPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }


    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pendingTidal = user.amount.mul(pool.accTidalPerShare).div(1e12).sub(user.tidalRewardDebt);
        if(pendingTidal > 0) {
            safeTideTransfer(msg.sender, pendingTidal, tidal);
        }
        uint256 pendingRiptide = user.amount.mul(pool.accRiptidePerShare).div(1e12).sub(user.riptideRewardDebt);
        if(pendingRiptide > 0) {
            safeTideTransfer(msg.sender, pendingRiptide, riptide);
        }
        uint256 pendingOtherTokens = user.amount.mul(pool.accOtherPerShare).div(1e12).sub(user.otherRewardDebt);
        if(_amount > 0) {
            uint256 amount = _amount;
            user.amount = user.amount.sub(amount);
            if (isRestaking(_pid)) {
                pool.adapter.withdraw(amount);
            }
            if (pool.withdrawFee > 0) {
                uint256 fee = wmul(amount, pool.withdrawFee);
                amount = amount.sub(fee);
                processWithdrawFee(address(pool.lpToken), fee);
            }
            pool.lpToken.safeTransfer(address(msg.sender), amount);
        }
        //  we can't guarantee we have the tokens until after adapter.withdraw()
        if (pendingOtherTokens > 0) {
            safeOtherTransfer(msg.sender, pendingOtherTokens, _pid);
        }
        user.tidalRewardDebt = user.amount.mul(pool.accTidalPerShare).div(1e12);
        user.riptideRewardDebt = user.amount.mul(pool.accRiptidePerShare).div(1e12);
        user.otherRewardDebt = user.amount.mul(pool.accOtherPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function processWithdrawFee(address _lpToken, uint256 _fee) private {
        // get token addresses & balances
        address token0 = IUniswapV2Pair(_lpToken).token0();
        address token1 = IUniswapV2Pair(_lpToken).token1();

        // remove liquidity
        IERC20(_lpToken).approve(address(router), _fee);
        (uint256 token0Amount, uint256 token1Amount) = router.removeLiquidity(token0, token1, _fee, 0, 0, address(this), block.timestamp);
        IERC20(_lpToken).approve(address(router), 0);

        address[] memory surfPath = new address[](2);
        surfPath[1] = surf;

        // sell and transfer
        if (token0 == surf) {
            surfPath[0] = token1;
            router.swapExactTokensForTokens(
                token1Amount,
                0,
                surfPath,
                whirlpool,
                block.timestamp
            );
            IERC20(token0).transfer(whirlpool, token0Amount);
        } else if (token1 == surf) {
            surfPath[0] = token0;
            router.swapExactTokensForTokens(
                token0Amount,
                0,
                surfPath,
                whirlpool,
                block.timestamp
            );
            IERC20(token1).transfer(whirlpool, token1Amount);
        } else {
            // this is not a reward/surf pair. Transfer to fee wallet
            IERC20(token0).transfer(feeaddr, token0Amount);
            IERC20(token1).transfer(feeaddr, token1Amount);
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.tidalRewardDebt = 0;
        user.riptideRewardDebt = 0;
        if (isRestaking(_pid)) {
            pool.adapter.withdraw(amount);
        }
        if (pool.withdrawFee > 0) {
            uint256 fee = wmul(amount, pool.withdrawFee);
            amount = amount.sub(fee);
            pool.lpToken.transfer(feeaddr, fee);
        }
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Withdraw LP tokens from the restaking target back here
    // Does not claim rewards
    function withdrawRestakedLP(uint256 _pid) internal {
        require(isRestaking(_pid), "not a restaking pool");
        PoolInfo storage pool = poolInfo[_pid];
        uint lpBalanceBefore = pool.lpToken.balanceOf(address(this));
        pool.adapter.emergencyWithdraw();
        uint lpBalanceAfter = pool.lpToken.balanceOf(address(this));
        emit EmergencyWithdraw(address(pool.adapter), _pid, lpBalanceAfter.sub(lpBalanceBefore));
    }


    // Safe tide token transfer function, just in case if rounding error causes pool to not have enough tokens of type _tideToken
    function safeTideTransfer(address _to, uint256 _amount, ITideToken _tideToken) internal {
        uint256 tokenBal = _tideToken.balanceOf(address(this));
        if (_amount > tokenBal) {
            _tideToken.transfer(_to, tokenBal);
        } else {
            _tideToken.transfer(_to, _amount);
        }
    }

    // as above but for any restaking token
    function safeOtherTransfer(address _to, uint256 _amount, uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 otherBal = pool.otherToken.balanceOf(address(this));
        if (_amount > otherBal) {
            pool.otherToken.transfer(_to, otherBal);
        } else {
            pool.otherToken.transfer(_to, _amount);
        }
    }

    // Update dev fee address
    function dev(address _devaddr) public onlyOwner {
        devaddr = _devaddr;
    }

    // Set dev fee divisor
    function setNewDevDivisor(uint256 _newDivisor) public onlyOwner {
        require(_newDivisor >= 145, "Dev fee too high"); // ~6.9% max
        devDivisor = _newDivisor;
    }

    // Update withdraw fee recipient
    function fee(address _feeaddr) public onlyOwner {
        feeaddr = _feeaddr;
    }

    // transfer ownership from this contract to a new owner
    function transferTokenOwnership(address _owned, address _newOwner) public onlyOwner {
        Ownable(_owned).transferOwnership(_newOwner);
    }

    /*
        set a new tidal token
        before calling, ensure:
            tokens per block is set to 0 beforehand and reinstated afterwards
            this is the sibling of riptide
            poseidon is the owner
            poseidon's new and old tidal balances match
    */
    function setNewTidalToken(address _newTidal) public onlyOwner {
        require(ITideToken(_newTidal).owner() == address(this), "Poseidon not the owner");
        if (phase == address(tidal)) phase = _newTidal;
        tidal = ITideToken(_newTidal);
    }

    /*
        set a new riptide token
        before calling, see above
    */
    function setNewRiptideToken(address _newRiptide) public onlyOwner {
        require(ITideToken(_newRiptide).owner() == address(this), "Poseidon not the owner");
        if (phase == address(riptide)) phase = _newRiptide;
        riptide = ITideToken(_newRiptide);
    }

    // return the active reward token (the phase; either tide or riptide)
    function getPhase() public view returns (address) {
        return phase;
    }

    // called every pool update.
    function updatePhase() internal {
        if (phase == address(tidal) && tidal.totalSupply() >= TIDAL_CAP){
            phase = address(riptide);
        }
        else if (phase == address(riptide) && tidal.totalSupply() < TIDAL_VERTEX) {
            phase = address(tidal);
        }
    }

}
