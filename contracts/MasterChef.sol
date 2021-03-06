// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import '@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol';
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol';

import "./ALIToken.sol";
import "./Staking.sol";

// import "@nomiclabs/buidler/console.sol";

// MasterChef is the master of ali. He can make ali and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once ali is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of alitas
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accALIPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accALIPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. alitas to distribute per block.
        uint256 lastRewardBlock;  // Last block number that alitas distribution occurs.
        uint256 accALIPerShare; // Accumulated alitas per share, times 1e12. See below.
    }

    // The ali TOKEN!
    AliToken public ali;
    Staking public staking;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when ali mining starts.
    uint256 public startBlock;

    // The percentage of ALI token rewards distributed to ALI pool
    uint256 public aliPoolPercent = 50;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    modifier validatePoolByPid(uint256 _pid) {
        require (_pid < poolInfo.length, "Pool does not exist") ;
        _;
    }
    constructor(
        AliToken _ali,
        Staking _staking,
        uint256 _startBlock
    ) public {
        ali = _ali;
        staking = _staking;
        startBlock = _startBlock;

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: IBEP20(_ali),
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accALIPerShare: 0
        }));

        totalAllocPoint = 1000;

    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // ali DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IBEP20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accALIPerShare: 0
        }));
        updateStakingPool();
    }

    // Update the given pool's ali allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public validatePoolByPid(_pid) onlyOwner {
        if(_pid == 0){
            return;
        }
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            updateStakingPool();
        }
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            uint denominator = 100 - aliPoolPercent;
            uint aliPoints = aliPoolPercent.mul(points).div(denominator);
            poolInfo[0].allocPoint = aliPoints;
            totalAllocPoint = aliPoints + points;
        }
    }

    // View function to see pending alitas on frontend.
    function pendingALI(uint256 _pid, address _user) external view validatePoolByPid(_pid) returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accALIPerShare = pool.accALIPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 alitaReward = getClaimableReward(pool.lastRewardBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accALIPerShare = accALIPerShare.add(alitaReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accALIPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }


    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public validatePoolByPid(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 alitaReward = getClaimableReward(pool.lastRewardBlock).mul(pool.allocPoint).div(totalAllocPoint);
        ali.mint(address(staking), alitaReward);
        pool.accALIPerShare = pool.accALIPerShare.add(alitaReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for ali allocation.
    function deposit(uint256 _pid, uint256 _amount) public validatePoolByPid(_pid) {

        require (_pid != 0, 'deposit ali by staking');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accALIPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accALIPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public validatePoolByPid(_pid) {

        require (_pid != 0, 'withdraw ali by unstaking');
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accALIPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accALIPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Stake ali tokens to MasterChef
    function enterStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accALIPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accALIPerShare).div(1e12);

        emit Deposit(msg.sender, 0, _amount);
    }

    // Withdraw ali tokens from STAKING.
    function leaveStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accALIPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accALIPerShare).div(1e12);

        emit Withdraw(msg.sender, 0, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public validatePoolByPid(_pid){
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe ali transfer function, just in case if rounding error causes pool to not have enough alitas.
    function safeTransfer(address _to, uint256 _amount) internal {
        staking.safeTransfer(_to, _amount);
    }

    /**
     * @notice Returns the result of (base ** exponent) with SafeMath
     * @param base The base number. Example: 2
     * @param exponent The exponent used to raise the base. Example: 3
     * @return A number representing the given base taken to the power of the given exponent. Example: 2 ** 3 = 8
     */
    function pow(uint base, uint exponent) internal pure returns (uint) {
        if (exponent == 0) {
            return 1;
        } else if (exponent == 1) {
            return base;
        } else if (base == 0 && exponent != 0) {
            return 0;
        } else {
            uint result = base;
            for (uint i = 1; i < exponent; i++) {
                result = result.mul(base);
            }
            return result;
        }
    }

    /**
     * @notice Caculate the reward per block at the period: (keepPercent / 100) ** period * initialRewardPerBlock
     * @param periodIndex The period index. The period index must be between [0, maximumPeriodIndex]
     * @return A number representing the reward token per block at specific period. Result is scaled by 1e18.
     */
    function getRewardPerBlock(uint periodIndex) public view returns (uint) {
        if(periodIndex > ali.getMaximumPeriodIndex()){
            return 0;
        }
        else{
            return pow(ali.getKeepPercent(), periodIndex).mul(ali.getInitialRewardPerBlock()).div(pow(100, periodIndex));
        }
    }

    /**
     * @notice Calculate the block number corresponding to each milestone at the beginning of each period.
     * @param periodIndex The period index. The period index must be between [0, maximumPeriodIndex]
     * @return A number representing the block number of the milestone at the beginning of the period.
     */
    function getBlockNumberOfMilestone(uint periodIndex) public view returns (uint) {
        return ali.getBlockPerPeriod().mul(periodIndex).add(startBlock);
    }

    /**
     * @notice Determine the period corresponding to any block number.
     * @param blockNumber The block number. The block number must be >= startBlock
     * @return A number representing period index of the input block number.
     */
    function getPeriodIndexByBlockNumber(uint blockNumber) public view returns (uint) {
        require(blockNumber >= startBlock, 'MasterChef: blockNumber must be greater or equal startBlock');
        return blockNumber.sub(startBlock).div(ali.getBlockPerPeriod());
    }

    /**
     * @notice Calculate the reward that can be claimed from the last received time to the present time.
     * @param lastRewardBlock The block number of the last received time 
     * @return A number representing the reclamable ALI tokens. Result is scaled by 1e18.
     */
    function getClaimableReward(uint lastRewardBlock) public view returns (uint) {
        uint maxBlock = getBlockNumberOfMilestone(ali.getMaximumPeriodIndex() + 1);
        uint currentBlock = block.number > maxBlock ? maxBlock: block.number;

        require(currentBlock >= startBlock, 'MasterChef: currentBlock must be greater or equal startBlock');

        uint lastClaimPeriod = getPeriodIndexByBlockNumber(lastRewardBlock); 
        uint currentPeriod = getPeriodIndexByBlockNumber(currentBlock);
        
        uint startCalculationBlock = lastRewardBlock; 
        uint sum = 0; 
        
        for(uint i = lastClaimPeriod ; i  <= currentPeriod ; i++) { 
            uint nextBlock = i < currentPeriod ? getBlockNumberOfMilestone(i+1) : currentBlock;
            uint delta = nextBlock.sub(startCalculationBlock);
            sum = sum.add(delta.mul(getRewardPerBlock(i)));
            startCalculationBlock = nextBlock;
        }
        sum = sum.mul(ali.getMasterChefWeight()).div(100);
        return sum;
    }

    function setKeepPercent(uint _aliPoolPercent) public onlyOwner {
        require(_aliPoolPercent > 0 , "MasterChef::_aliPoolPercent: _aliPoolPercent must be greater 0");
        require(_aliPoolPercent <= 100 , "MasterChef::_aliPoolPercent: _aliPoolPercent must be less or equal 100");
        aliPoolPercent = _aliPoolPercent;
    }
}
