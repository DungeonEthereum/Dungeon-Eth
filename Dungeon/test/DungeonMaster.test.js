const {expectRevert, time} = require('@openzeppelin/test-helpers');
const IronToken = artifacts.require('IronToken');
const DungeonMaster = artifacts.require('DungeonMaster');
const MockERC20 = artifacts.require("MockERC20");

contract("DungeonMasterTest", ([alice, bob, carol, dev]) => {
    beforeEach(async () => {
        this.dm = await DungeonMaster.new(dev, '1', '25', {from: alice});
        this.iron = await IronToken.new(this.dm.address, this.dm.address, {from: alice});
        await this.iron.transferOwnership(this.dm.address, {from: alice});
        // await this.iron.approve(this.dm.address, "100000000000000000000000000000000000000000000", {from: this.dm});
    });

    it('should set correct state variables and addresses of Owner and Minter', async () => {
        const devaddr = await this.dm.devaddr();
        const ironOwner = await this.iron.owner();
        const ironMinter = await this.iron.minter();
        const ironBurner = await this.iron.burner();
        assert.equal(devaddr.valueOf(), dev);
        assert.equal(ironOwner.valueOf(), this.dm.address);
        assert.equal(ironMinter.valueOf(), this.dm.address);
        assert.equal(ironBurner.valueOf(), this.dm.address);
    });

    it('should allow dev and only dev to update dev', async () => {
        assert.equal((await this.dm.devaddr()).valueOf(), dev);
        await expectRevert(this.dm.dev(bob, {from: bob}), 'dev: wut?');
        await this.dm.dev(bob, {from: dev});
        assert.equal((await this.dm.devaddr()).valueOf(), bob);
        await this.dm.dev(alice, {from: bob});
        assert.equal((await this.dm.devaddr()).valueOf(), alice);
    })

    context('With token added to normal pool', () => {
        beforeEach(async () => {
            this.token1 = await MockERC20.new('Token 1', 'T1', '10000000000', this.dm.address, {from: alice});
            assert.equal((await this.token1.minter()).valueOf(), alice);
            await this.token1.transfer(bob, '10000', {from: alice});
            await this.token1.transfer(carol, '10000', {from: alice});
            this.token2 = await MockERC20.new('Token 2', 'T2', '10000000000', this.dm.address, {from: alice});
            await this.token2.transfer(bob, '10000', {from: alice});
            await this.token2.transfer(carol, '10000', {from: alice});
            this.iron = await IronToken.new(this.dm.address, this.dm.address, {from: alice});
            await this.iron.transferOwnership(this.dm.address, {from: alice});
        });

        it('should allow emergency withdraw', async () => {
            await this.dm.addNormalPool(this.token1.address, this.token2.address, 200)
            await this.token1.approve(this.dm.address, '10000', {from: bob});
            await this.dm.depositNormalPool(0, '1000', {from: bob});
            assert.equal((await this.token1.balanceOf(bob)).valueOf(), '9000');
            await this.dm.emergencyWithdrawNormalPool(0, {from: bob});
            assert.equal((await this.token1.balanceOf(bob)).valueOf(), '9998'); // 0.25% chest fee rounds up to being 2 token1
        });

        it('should give out rewards only after farming time', async () => {
            // 200 per block farming rate
            await this.dm.addNormalPool(this.token1.address, this.iron.address, 200)
            await this.token1.approve(this.dm.address, '10000', {from: bob});
            await this.dm.depositNormalPool(0, '1000', {from: bob});
            const block = +(await time.latestBlock());
            console.log(block + 5)
            await time.advanceBlockTo(block + 5);
            await this.dm.collectNormalPool(0, {from: bob});
            // everything is in 1e18; 6 block rewards
            assert.equal((await this.iron.balanceOf(bob)).valueOf(), '1079999999999999999999'); // 1200 iron - 10% (dev and chestfee)
            assert.equal((await this.iron.balanceOf(dev)).valueOf(), '60000000000000000000'); // 60 iron
            assert.equal((await this.iron.totalSupply()).valueOf(), '1200000000000000000000'); // total of 1200 iron
        });

        it('should give out rewards based on stake', async () => {
            // 200 per block farming rate; 60/40
            await this.dm.addNormalPool(this.token1.address, this.iron.address, 200)
            await this.token1.approve(this.dm.address, '10000', {from: bob});
            await this.token1.approve(this.dm.address, '10000', {from: carol});
            await this.dm.depositNormalPool(0, '600', {from: bob});
            await this.dm.depositNormalPool(0, '400', {from: carol});
            // assert.equal((await this.dm.normalPoolInfo(0)).stakedSupply().valueOf(), '')
            const block = +(await time.latestBlock());
            console.log(block + 4)
            await time.advanceBlockTo(block + 4);
            await this.dm.collectNormalPool(0, {from: bob});
            await this.dm.collectNormalPool(0, {from: carol});
            // everything is in 1e18
            assert.equal((await this.iron.balanceOf(bob)).valueOf(), '720180360721442885771'); // 180 (full reward before carol joined) + 1000 - dev&chest fee * 60%
            assert.equal((await this.iron.balanceOf(carol)).valueOf(), '431783567134268537074'); // (1200 iron - 10% (dev and chestfee)) * 40%
            assert.equal((await this.iron.balanceOf(dev)).valueOf(), '70000000000000000000'); // 70 iron
            assert.equal((await this.iron.totalSupply()).valueOf(), '1400000000000000000000'); // total of 1400 iron: 7 blocks since first deposit
        });
    });

    context("With token added to burning pool", () => {
        beforeEach(async () => {
            this.token1 = await MockERC20.new('Token 1', 'T1', '1200000000000000000000', this.dm.address, {from: alice});
            assert.equal((await this.token1.minter()).valueOf(), alice);
            await this.token1.transfer(bob, '400000000000000000000', {from: alice});
            await this.token1.transfer(carol, '400000000000000000000', {from: alice});
            this.token2 = await MockERC20.new('Token 2', 'T2', '1200000000000000000000', this.dm.address, {from: alice});
            await this.token2.transfer(bob, '400000000000000000000', {from: alice});
            await this.token2.transfer(carol, '400000000000000000000', {from: alice});
            this.iron = await IronToken.new(this.dm.address, this.dm.address, {from: alice});
            await this.iron.transferOwnership(this.dm.address, {from: alice});
        });

        it('should give out rewards and burn tokens only after farming time', async () => {
            // every 10 blocks 5 are burned and 1 reward is created
            await this.dm.addBurnPool(this.token1.address, this.iron.address, 10, 1, 5)
            await this.token1.approve(this.dm.address, '400000000000000000000', {from: bob});
            await this.dm.depositBurnPool(0, '60000000000000000000', {from: bob});
            const block = +(await time.latestBlock());
            console.log(block + 15)
            await time.advanceBlockTo(block + 15);
            await this.dm.collectBurnPool(0, {from: bob});
            // everything is in 1e18; 6 block rewards
            assert.equal((await this.iron.balanceOf(bob)).valueOf(), '900000000000000'); // 0.001 iron reward - 10% (dev and chest fee)
            assert.equal((await this.iron.balanceOf(dev)).valueOf(), '50000000000000'); // 0.00005 iron
            assert.equal((await this.iron.totalSupply()).valueOf(), '1000000000000000'); // total of 0.001 iron
        });
    })

    context("With token added to multi burning pool", () => {
        beforeEach(async () => {
            this.token1 = await MockERC20.new('Token 1', 'T1', '1200000000000000000000', this.dm.address, {from: alice});
            assert.equal((await this.token1.minter()).valueOf(), alice);
            await this.token1.transfer(bob, '400000000000000000000', {from: alice});
            await this.token1.transfer(carol, '400000000000000000000', {from: alice});
            this.token2 = await MockERC20.new('Token 2', 'T2', '1200000000000000000000', this.dm.address, {from: alice});
            await this.token2.transfer(bob, '400000000000000000000', {from: alice});
            await this.token2.transfer(carol, '400000000000000000000', {from: alice});
            this.iron = await IronToken.new(this.dm.address, this.dm.address, {from: alice});
            await this.iron.transferOwnership(this.dm.address, {from: alice});
        });

        it('should give out rewards and burn tokens only after farming time', async () => {
            // every 10 blocks 5 are burned and 1 reward is created
            await this.dm.addMultiBurnPool([this.token1.address, this.token2.address], this.iron.address, 10, 1, 5)
            await this.token1.approve(this.dm.address, '400000000000000000000', {from: bob});
            await this.token2.approve(this.dm.address, '400000000000000000000', {from: bob});
            await this.dm.depositMultiBurnPool(0, '60000000000000000000', {from: bob});
            const block = +(await time.latestBlock());
            console.log(block + 15)
            await time.advanceBlockTo(block + 15);
            await this.dm.collectMultiBurnPool(0, {from: bob});
            // everything is in 1e18; 6 block rewards
            assert.equal((await this.iron.balanceOf(bob)).valueOf(), '950000000000000'); // 0.001 iron reward - 5% (dev fee; no chest fee)
            assert.equal((await this.iron.balanceOf(dev)).valueOf(), '50000000000000'); // 0.00005 iron
            assert.equal((await this.iron.totalSupply()).valueOf(), '1000000000000000'); // total of 0.001 iron
        });
    })
})