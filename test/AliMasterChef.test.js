const { expectRevert, time } = require('@openzeppelin/test-helpers');
const { assert } = require('chai');
const Staking = artifacts.require('Staking');
const MasterChef = artifacts.require('MasterChef');
const MockBEP20 = artifacts.require('libs/MockBEP20');
const MockTestAliToken = artifacts.require('libs/MockTestAliToken');

contract('MasterChef', ([alice, bob, carol, dev, minter]) => {
    const startBlock = 0;
    const blockPerPeriod = 20;
    const maximumPeriodIndex = 2;
    const initialRewardPerBlock = 1000;
    const maxBlock = startBlock + blockPerPeriod * (maximumPeriodIndex + 1);

    beforeEach(async () => {
        this.ali = await MockTestAliToken.new(startBlock, minter, '1000000', 50, 50, { from: minter }); // (uint _startBlock, address _keeper, uint _amount, uint _incentiveWeight, uint _masterChefWeight)
        this.staking = await Staking.new(this.ali.address, { from: minter });
        this.lp1 = await MockBEP20.new('LPToken', 'LP1', '1000000', { from: minter });

        this.masterChef = await MasterChef.new(this.ali.address, this.staking.address, startBlock, { from: minter }); //  AliToken _ali, Staking _staking, uint256 _startBlock

        await this.ali.setMasterChef(this.masterChef.address, { from: minter });
        await this.ali.setBlockPerPeriod(blockPerPeriod, { from: minter });
        await this.ali.setInitialRewardPerBlock(initialRewardPerBlock, { from: minter });
        await this.staking.transferOwnership(this.masterChef.address, { from: minter });

        await this.lp1.transfer(alice, '2000', { from: minter });
        await this.lp1.transfer(bob, '2000', { from: minter });

    });

    it('getRewardPerBlock: the rewardPerBlock of first period must equal initialRewardPerBlock', async () => {
        const initialRewardPerBlock = await this.ali.getInitialRewardPerBlock();
        const rewardPerBlock0 = await this.masterChef.getRewardPerBlock(0);
        assert.equal(rewardPerBlock0.toString(), initialRewardPerBlock.toString());
    })

    it('getRewardPerBlock: the rewardPerBlock of second period must equal (keepPercent)% of first period', async () => {
        const initialRewardPerBlock = await this.ali.getInitialRewardPerBlock();
        const keepPercent = await this.ali.getKeepPercent();
        const rewardPerBlock1 = await this.masterChef.getRewardPerBlock(1);
        assert.equal(rewardPerBlock1.toString(), (initialRewardPerBlock * keepPercent / 100).toString());
    })

    it('getClaimableReward: can receive rewards if not yet received even though the maximum period has passed ', async () => {
        const rewardPerBlock0 = await this.masterChef.getRewardPerBlock(0);
        const rewardPerBlock1 = await this.masterChef.getRewardPerBlock(1);
        const rewardPerBlock2 = await this.masterChef.getRewardPerBlock(2);
        let currentBlock = await time.latestBlock();

        if (currentBlock < maxBlock + 10) {
            await time.advanceBlockTo(maxBlock + 10);
        }
        currentBlock = await time.latestBlock();

        assert.isAbove(currentBlock.toNumber(), maxBlock, 'Make sure that current block is out of the last period');
        console.log('[INFO] currentBlock', currentBlock.toNumber());
        console.log('[INFO] maxBlock', maxBlock);
        const lastRewardBlock = startBlock;
        const masterChefWeight = await this.ali.getMasterChefWeight();
        const reward = await this.masterChef.getClaimableReward(lastRewardBlock);

        const expectedReward = ((rewardPerBlock0 * blockPerPeriod + rewardPerBlock1 * blockPerPeriod + rewardPerBlock2 * blockPerPeriod) * masterChefWeight / 100);
        assert.equal(reward.toString(), expectedReward.toString());
    })

    it('Real case: Make sure ALI pool is added', async () => {
        const pool = await this.masterChef.poolInfo(0);
        assert.equal(pool.lpToken, this.ali.address);
    })

    it('pendingALI: return the correct pending ALI', async () => {
        
        await this.lp1.approve(this.masterChef.address, '1000', { from: alice });
        const poolAllocPoint = 2000;
        await this.masterChef.add(poolAllocPoint, this.lp1.address, true, { from: minter });

        const totalAllocPoint = (await this.masterChef.totalAllocPoint()).toNumber();

        const pid = 1;
        const amount = 20;

        await this.masterChef.deposit(pid, amount, { from: alice });

        await time.advanceBlock();

        let pool = await this.masterChef.poolInfo(pid);
        const pendingALI = await this.masterChef.pendingALI(pid, alice);
        const allPoolReward = (await this.masterChef.getClaimableReward(pool.lastRewardBlock)).toNumber();
        const poolReward = allPoolReward * poolAllocPoint / totalAllocPoint;
        const lpSupply = (await this.lp1.balanceOf(this.masterChef.address)).toNumber();
        const accALIPerShare = poolReward  * (10 ** 12)  / lpSupply;

        const expectedPendingReward = amount * accALIPerShare / (10 ** 12);
        assert.equal(pendingALI.toString(), expectedPendingReward.toString());
    })

    it('Real case: add pools and check the poolLength', async () => {
        this.lp2 = await MockBEP20.new('LPToken', 'LP2', '1000000', { from: minter });
        this.lp3 = await MockBEP20.new('LPToken', 'LP3', '1000000', { from: minter });
        this.lp4 = await MockBEP20.new('LPToken', 'LP4', '1000000', { from: minter });
        this.lp5 = await MockBEP20.new('LPToken', 'LP5', '1000000', { from: minter });

        await this.masterChef.add('2000', this.lp1.address, true, { from: minter });
        await this.masterChef.add('1000', this.lp2.address, true, { from: minter });
        await this.masterChef.add('500', this.lp3.address, true, { from: minter });
        await this.masterChef.add('500', this.lp4.address, true, { from: minter });
        await this.masterChef.add('500', this.lp5.address, true, { from: minter });

        assert.equal((await this.masterChef.poolLength()).toString(), '6');
    })
    it('Real case: deposit and withdraw at pool[1]', async () => {
        await this.lp1.approve(this.masterChef.address, '1000', { from: alice });
        assert.equal((await this.ali.balanceOf(alice)).toNumber(), 0, 'Make sure that ALI balance is 0 before depositing');

        await this.masterChef.add('2000', this.lp1.address, true, { from: minter });
        const pid = 1;
        const amount = 20;

        await this.masterChef.deposit(pid, amount, { from: alice });

        let user = await this.masterChef.userInfo(pid, alice);
        let pool = await this.masterChef.poolInfo(pid);

        assert.equal(await user.amount.toNumber(), amount, 'Make sure that deposited amount is correct');

        await time.advanceBlock();

        await this.masterChef.withdraw(pid, amount, { from: alice });

        user = await this.masterChef.userInfo(pid, alice);
        pool = await this.masterChef.poolInfo(pid);
        const accALIPerShare = pool.accALIPerShare.toNumber();
        assert.equal((await this.ali.balanceOf(alice)).toNumber(), amount * accALIPerShare / (10 ** 12) - user.rewardDebt.toNumber(), 'Make sure the ALI reward is correct');
    })

    it('Real case: deposit and withdraw to ALI pool', async () => {
        const initialAmount = 1000;
        await this.ali.transfer(alice, initialAmount, { from: minter });
        await this.ali.approve(this.masterChef.address, initialAmount, { from: alice });

        const stakingAmount = 10;
        await this.masterChef.enterStaking(stakingAmount, { from: alice });
        let user = await this.masterChef.userInfo(0, alice);
        let pool = await this.masterChef.poolInfo(0);
        assert.equal(await user.amount.toNumber(), stakingAmount, 'Make sure that deposit amount is correct');

        await time.advanceBlock();

        const unStakingAmount = 10;
        await this.masterChef.leaveStaking(unStakingAmount, { from: alice });
        user = await this.masterChef.userInfo(0, alice);
        pool = await this.masterChef.poolInfo(0);
        assert.equal(await user.amount.toNumber(), stakingAmount - unStakingAmount, 'Make sure that withdraw amount is correct');

        const accALIPerShare = pool.accALIPerShare.toNumber();
        const reward = stakingAmount * accALIPerShare / (10 ** 12) - user.rewardDebt.toNumber();
        const expectedBalance = initialAmount - stakingAmount + unStakingAmount + reward;
        const currentBalance = (await this.ali.balanceOf(alice)).toNumber();

        assert.equal(currentBalance, expectedBalance, 'Make sure the ALI reward is correct');
    })

});
