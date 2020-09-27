pragma solidity >=0.5.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./token/IronToken.sol";
import "./token/MyERC20Token.sol";
import "./token/KnightToken.sol";

contract DungeonMaster is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // ------------- normal pool variables and structs ----------------------

    struct NormalUserInfo {
        uint256 amountStaked;
        uint256 debt;
    }

    // Info of each pool.
    struct NormalPoolInfo {
        IERC20 stakeToken;
        MyERC20Token receiveToken;
        uint256 stakedSupply;
        uint256 uncollectedAmount;
        uint256 rewardPerBlock;
        uint256 stakeChestAmount;
        uint256 receiveChestAmount;
        uint256 lastUpdateBlock;
        uint256 accumulatedRewardPerStake; // is in 1e12 to allow for cases where stake supply is more than block reward
    }

    // Info of each normal pool.
    NormalPoolInfo[] public normalPoolInfo;
    // Info of each user that stakes tokens in normal pool
    mapping(uint256 => mapping(address => NormalUserInfo)) public normalUserInfo;

    // ------------- burn pool variables and structs ----------------------

    struct BurnUserInfo {
        uint256 amountStaked;
        uint256 startBlock;

        // reward is calculated by (currentBlock - startBlock) / blockrate * rewardRate
        // burn is calculated by (currentBlock - startBlock) / blockrate * burnRate
        // if all stake burned reward is amountStaked / burnRate * rewardRate (which would be the maximum reward possible
        // and is useful for pending function)
    }

    // Info of each pool.
    struct BurnPoolInfo {
        MyERC20Token burningStakeToken;
        MyERC20Token receiveToken;
        uint256 blockRate; // reward is created every x blocks
        uint256 rewardRate; // reward distributed per blockrate
        uint256 burnRate; // token burned per blockrate
        uint256 stakeChestAmount;
        uint256 receiveChestAmount;
    }

    // Info of each burn pool.
    BurnPoolInfo[] public burnPoolInfo;
    // Info of each user that stakes and burns tokens in burn pool
    mapping(uint256 => mapping(address => BurnUserInfo)) public burnUserInfo;

    // ------------- multi burn pool variables and structs ----------------------

    struct MultiBurnUserInfo {
        uint256 amountStakedOfEach;
        uint256 startBlock;

        // reward is calculated by (currentBlock - startBlock) / blockrate * rewardRate
        // burn is calculated by (currentBlock - startBlock) / blockrate * burnRate
        // if all stake burned reward is amountStaked / burnRate * rewardRate (which would be the maximum reward possible
        // and is useful for pending function)
    }

    // Info of each pool.
    struct MultiBurnPoolInfo {
        MyERC20Token[] burningStakeTokens;
        MyERC20Token receiveToken;
        uint256 blockRate; // reward is created every x blocks
        uint256 rewardRate; // reward distributed per blockrate
        uint256 burnRate; // token burned per blockrate
        uint256 stakeChestAmount;
    }

    // Info of each burn pool.
    MultiBurnPoolInfo[] public multiBurnPoolInfo;
    // Info of each user that stakes and burns tokens in burn pool
    mapping(uint256 => mapping(address => MultiBurnUserInfo)) public multiBurnUserInfo;

    // ------------- raid variables and structs ----------------------

    uint256 public raidBlock;
    uint256 public raidFrequency;
    uint256 public returnIfNotInRaidPercentage = 25; // 25% of knights will return if you miss the raid block
    uint256 public raidWinLootPercentage = 25; // 25% of chest will be rewarded based on knights provided
    uint256 public raidWinPercentage = 5; // 5% of total supplied knights must be in raid to win

    address[] public participatedInRaid;

    mapping(address => uint256)[] public knightsProvidedInRaid;
    mapping(address => uint256) public raidShare;

    // -------------------------------------------------------------------------------------

    bool public votingActive = false;
    uint256 public voted = 0;
    address[] public voters;
    mapping(address => uint256) voteAmount;

    address public devaddr;
    uint public depositChestFee = 25;
    uint public chestRewardPercentage = 500;

    uint256 public startBlock;
    KnightToken public knightToken;

    constructor(
        address _devaddr,
        uint256 _startBlock,
        uint256 _depositChestFee
    ) public {
        devaddr = _devaddr;
        startBlock = _startBlock;
        depositChestFee = _depositChestFee;
    }

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    // Set the percentage of the deposit amount going into the chest; max 1%
    function setDepositChestFee(uint256 _depositChestFee) public onlyOwner {
        require(_depositChestFee <= 100, "deposit chest fee can be max 1%");
        depositChestFee = _depositChestFee;
    }

    // Set the percentage of the collected amount going into the chest is in * 0.01%
    function setChestRewardPercentage(uint256 _chestRewardPercentage) public onlyOwner {
        require(_chestRewardPercentage <= 1000, "chest reward percentage can be max 10%");
        chestRewardPercentage = _chestRewardPercentage;
    }

    function setKnightToken(KnightToken _knight) public onlyOwner {
        knightToken = _knight;
    }

    // Set the percentage of the chest which is distributed to the raid participants; min 10%
    function setRaidWinLootPercentage(uint256 _percentage) public onlyOwner {
        require(_percentage >= 10, "minimum of 10% must be distributed");
        raidWinLootPercentage = _percentage;
    }

    // Set the percentage of the total supply of knights which must take part in the raid to win; max 50%
    function setRaidWinPercentage(uint256 _percentage) public onlyOwner {
        require(_percentage <= 50, "maximum of 50% must take part");
        raidWinPercentage = _percentage;
    }

    function getBlocks(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    function isStarted() public view returns (bool) {
        return startBlock <= block.number;
    }

    //    ---------------- Normal Pool Methods -------------------------------

    function addNormalPool(IERC20 _stakeToken, MyERC20Token _receiveToken, uint256 _rewardPerBlock) public onlyOwner {
        uint256 lastUpdateBlock = block.number > startBlock ? block.number : startBlock;
        normalPoolInfo.push(NormalPoolInfo(_stakeToken, _receiveToken, 0, 0, _rewardPerBlock.mul(1e18), 0, 0, lastUpdateBlock, 0));
    }

    function normalPoolLength() external view returns (uint256) {
        return normalPoolInfo.length;
    }

    function normalPending(uint256 _pid, address _user) external view returns (uint256, IERC20) {
        NormalPoolInfo storage pool = normalPoolInfo[_pid];
        NormalUserInfo storage user = normalUserInfo[_pid][_user];
        uint256 rewardPerStake = pool.accumulatedRewardPerStake;
        if (block.number > pool.lastUpdateBlock && pool.stakedSupply != 0) {
            uint256 blocks = getBlocks(pool.lastUpdateBlock, block.number);
            uint256 reward = pool.rewardPerBlock.mul(blocks);
            rewardPerStake = rewardPerStake.add(reward.mul(1e12).div(pool.stakedSupply));
        }
        return (user.amountStaked.mul(rewardPerStake).div(1e12).sub(user.debt), pool.receiveToken);
    }

    function updateNormalPool(uint256 _pid) public {
        NormalPoolInfo storage pool = normalPoolInfo[_pid];
        if (block.number <= pool.lastUpdateBlock) {
            return;
        }
        if (pool.stakedSupply == 0) {
            pool.lastUpdateBlock = block.number;
            return;
        }
        uint256 blocks = getBlocks(pool.lastUpdateBlock, block.number);
        uint256 reward = blocks.mul(pool.rewardPerBlock);
        // reward * (1 - 0,05 - chestRewardPercentage)
        uint256 poolReward = reward.mul(10000 - 500 - chestRewardPercentage).div(10000);
        pool.receiveToken.mint(address(this), poolReward);
        // 5% goes to dev address
        pool.receiveToken.mint(devaddr, reward.mul(5).div(100));
        pool.receiveChestAmount = pool.receiveChestAmount.add(reward.mul(chestRewardPercentage).div(10000));
        pool.receiveToken.mint(address(this), reward.mul(chestRewardPercentage).div(10000));
        pool.uncollectedAmount = pool.uncollectedAmount.add(poolReward);
        pool.accumulatedRewardPerStake = pool.accumulatedRewardPerStake.add(poolReward.mul(1e12).div(pool.stakedSupply));
        pool.lastUpdateBlock = block.number;
    }

    function depositNormalPool(uint256 _pid, uint256 _amount) public {
        require(startBlock <= block.number, "not yet started.");

        NormalPoolInfo storage pool = normalPoolInfo[_pid];
        NormalUserInfo storage user = normalUserInfo[_pid][msg.sender];
        updateNormalPool(_pid);

        // collect farmed token if user has already staked
        if (user.amountStaked > 0) {
            uint256 pending = user.amountStaked.mul(pool.accumulatedRewardPerStake).div(1e12).sub(user.debt);
            require(pool.uncollectedAmount >= pending, "not enough uncollected tokens anymore");
            pool.receiveToken.transfer(address(msg.sender), pending);
            pool.uncollectedAmount = pool.uncollectedAmount - pending;
        }
        pool.stakeToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        uint256 chestAmount = _amount.mul(depositChestFee).div(10000);
        user.amountStaked = user.amountStaked.add(_amount).sub(chestAmount);
        pool.stakedSupply = pool.stakedSupply.add(_amount.sub(chestAmount));
        pool.stakeChestAmount = pool.stakeChestAmount.add(chestAmount);
        user.debt = user.amountStaked.mul(pool.accumulatedRewardPerStake).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdrawNormalPool(uint256 _pid, uint256 _amount) public {
        NormalPoolInfo storage pool = normalPoolInfo[_pid];
        NormalUserInfo storage user = normalUserInfo[_pid][msg.sender];
        require(user.amountStaked >= _amount, "withdraw: not good");
        updateNormalPool(_pid);

        // collect farmed token
        uint256 pending = user.amountStaked.mul(pool.accumulatedRewardPerStake).div(1e12).sub(user.debt);
        require(pool.uncollectedAmount >= pending, "not enough uncollected tokens anymore");
        pool.receiveToken.transfer(address(msg.sender), pending);
        pool.uncollectedAmount = pool.uncollectedAmount - pending;

        user.amountStaked = user.amountStaked.sub(_amount);
        user.debt = user.amountStaked.mul(pool.accumulatedRewardPerStake).div(1e12);
        pool.stakeToken.safeTransfer(address(msg.sender), _amount);
        pool.stakedSupply = pool.stakedSupply.sub(_amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function emergencyWithdrawNormalPool(uint256 _pid) public {
        NormalPoolInfo storage pool = normalPoolInfo[_pid];
        NormalUserInfo storage user = normalUserInfo[_pid][msg.sender];
        emit EmergencyWithdraw(msg.sender, _pid, user.amountStaked);
        pool.stakedSupply = pool.stakedSupply.sub(user.amountStaked);
        pool.stakeToken.safeTransfer(address(msg.sender), user.amountStaked);
        user.amountStaked = 0;
    }

    function collectNormalPool(uint256 _pid) public {
        NormalPoolInfo storage pool = normalPoolInfo[_pid];
        NormalUserInfo storage user = normalUserInfo[_pid][msg.sender];
        updateNormalPool(_pid);
        uint256 pending = user.amountStaked.mul(pool.accumulatedRewardPerStake).div(1e12).sub(user.debt);
        require(pool.uncollectedAmount >= pending, "not enough uncollected tokens anymore");
        pool.receiveToken.transfer(address(msg.sender), pending);
        pool.uncollectedAmount = pool.uncollectedAmount.sub(pending);
        user.debt = user.amountStaked.mul(pool.accumulatedRewardPerStake).div(1e12);
    }

    //    ----------------------------- Burn Pool Methods --------------------------------------------

    function addBurnPool(MyERC20Token _stakeToken, MyERC20Token _receiveToken, uint256 _blockRate, uint256 _rewardRate, uint256 _burnRate) public onlyOwner {
        // reward and burn rate is in * 0.001
        burnPoolInfo.push(BurnPoolInfo(_stakeToken, _receiveToken, _blockRate, _rewardRate.mul(1e15), _burnRate.mul(1e15), 0, 0));
    }

    function burnPoolLength() external view returns (uint256) {
        return burnPoolInfo.length;
    }

    function burnPending(uint256 _pid, address _user) external view returns (uint256, uint256, IERC20) {
        BurnPoolInfo storage pool = burnPoolInfo[_pid];
        BurnUserInfo storage user = burnUserInfo[_pid][_user];
        uint256 blocks = getBlocks(user.startBlock, block.number);
        uint256 ticks = blocks.div(pool.blockRate);
        uint256 burned = ticks.mul(pool.burnRate);
        uint256 reward = 0;
        if (burned > user.amountStaked) {
            reward = user.amountStaked.mul(1e5).div(pool.burnRate).mul(pool.rewardRate).div(1e5);
            burned = user.amountStaked;
        }
        else {
            reward = ticks.mul(pool.rewardRate);
        }
        return (reward, burned, pool.receiveToken);
    }

    function depositBurnPool(uint256 _pid, uint256 _amount) public {
        require(startBlock <= block.number, "not yet started.");

        BurnPoolInfo storage pool = burnPoolInfo[_pid];
        BurnUserInfo storage user = burnUserInfo[_pid][msg.sender];

        // collect farmed token if user has already staked
        if (user.amountStaked > 0) {
            collectBurnPool(_pid);
        }
        pool.burningStakeToken.transferFrom(address(msg.sender), address(this), _amount);
        uint256 chestAmount = _amount.mul(depositChestFee).div(10000);
        pool.stakeChestAmount = pool.stakeChestAmount.add(chestAmount);
        user.amountStaked = user.amountStaked.add(_amount).sub(chestAmount);
        user.startBlock = block.number;
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdrawBurnPool(uint256 _pid, uint256 _amount) public {
        BurnPoolInfo storage pool = burnPoolInfo[_pid];
        BurnUserInfo storage user = burnUserInfo[_pid][msg.sender];

        // collect farmed token
        collectBurnPool(_pid);

        if (user.amountStaked < _amount) {
            _amount = user.amountStaked;
            // withdraw all of stake
        }
        user.amountStaked = user.amountStaked.sub(_amount);
        pool.burningStakeToken.transfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function collectBurnPool(uint256 _pid) public returns (uint256) {
        BurnPoolInfo storage pool = burnPoolInfo[_pid];
        BurnUserInfo storage user = burnUserInfo[_pid][msg.sender];
        uint256 blocks = getBlocks(user.startBlock, block.number);
        uint256 ticks = blocks.div(pool.blockRate);
        uint256 burned = ticks.mul(pool.burnRate);
        uint256 reward = 0;
        if (burned > user.amountStaked) {
            reward = user.amountStaked.mul(1e5).div(pool.burnRate).mul(pool.rewardRate).div(1e5);
            burned = user.amountStaked;
            user.amountStaked = 0;
        }
        else {
            reward = ticks.mul(pool.rewardRate);
            user.amountStaked = user.amountStaked.sub(burned);
        }
        // burn token
        pool.burningStakeToken.burn(burned);

        uint256 userAmount = reward.mul(10000 - 500 - chestRewardPercentage).div(10000);
        uint256 chestAmount = reward.mul(chestRewardPercentage).div(10000);
        uint256 devAmount = reward.mul(500).div(10000);
        pool.receiveToken.mint(msg.sender, userAmount);
        pool.receiveToken.mint(address(this), chestAmount);
        pool.receiveToken.mint(devaddr, devAmount);
        pool.receiveChestAmount = pool.receiveChestAmount.add(chestAmount);
        user.startBlock = block.number;
        return (reward);
    }

    //    ----------------------------- Multi Burn Pool Methods --------------------------------------------

    function addMultiBurnPool(MyERC20Token[] memory _stakeTokens, MyERC20Token _receiveToken, uint256 _blockRate, uint256 _rewardRate, uint256 _burnRate) public onlyOwner {
        // reward and burn rate is in * 0.001
        multiBurnPoolInfo.push(MultiBurnPoolInfo(_stakeTokens, _receiveToken, _blockRate, _rewardRate.mul(1e15), _burnRate.mul(1e15), 0));
    }

    function multiBurnPoolLength() external view returns (uint256) {
        return multiBurnPoolInfo.length;
    }

    function multiBurnPending(uint256 _pid, address _user) external view returns (uint256, uint256, IERC20) {
        MultiBurnPoolInfo storage pool = multiBurnPoolInfo[_pid];
        MultiBurnUserInfo storage user = multiBurnUserInfo[_pid][_user];
        uint256 blocks = getBlocks(user.startBlock, block.number);
        uint256 ticks = blocks.div(pool.blockRate);
        uint256 burned = ticks.mul(pool.burnRate);
        uint256 reward = 0;
        if (burned > user.amountStakedOfEach) {
            reward = user.amountStakedOfEach.mul(1e5).div(pool.burnRate).mul(pool.rewardRate).div(1e5);
            burned = user.amountStakedOfEach;
        }
        else {
            reward = ticks.mul(pool.rewardRate);
        }
        return (reward, burned, pool.receiveToken);
    }

    function depositMultiBurnPool(uint256 _pid, uint256 _amount) public {
        require(startBlock <= block.number, "not yet started.");

        MultiBurnPoolInfo storage pool = multiBurnPoolInfo[_pid];
        MultiBurnUserInfo storage user = multiBurnUserInfo[_pid][msg.sender];

        // collect farmed token if user has already staked
        if (user.amountStakedOfEach > 0) {
            collectMultiBurnPool(_pid);
        }
        for (uint i = 0; i < pool.burningStakeTokens.length; i++) {
            MyERC20Token stakeToken = pool.burningStakeTokens[i];
            stakeToken.transferFrom(address(msg.sender), address(this), _amount);
        }
        uint256 chestAmount = _amount.mul(depositChestFee).div(10000);
        pool.stakeChestAmount = pool.stakeChestAmount.add(chestAmount);
        user.amountStakedOfEach = user.amountStakedOfEach.add(_amount).sub(chestAmount);
        user.startBlock = block.number;
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdrawMultiBurnPool(uint256 _pid, uint256 _amount) public {
        MultiBurnPoolInfo storage pool = multiBurnPoolInfo[_pid];
        MultiBurnUserInfo storage user = multiBurnUserInfo[_pid][msg.sender];
        updateNormalPool(_pid);

        // collect farmed token
        collectMultiBurnPool(_pid);

        if (user.amountStakedOfEach < _amount) {
            _amount = user.amountStakedOfEach;
            // withdraw all
        }

        user.amountStakedOfEach = user.amountStakedOfEach.sub(_amount);
        for (uint i = 0; i < pool.burningStakeTokens.length; i++) {
            MyERC20Token stakeToken = pool.burningStakeTokens[i];
            stakeToken.transfer(address(msg.sender), _amount);
        }
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function collectMultiBurnPool(uint256 _pid) public returns (uint256) {
        MultiBurnPoolInfo storage pool = multiBurnPoolInfo[_pid];
        MultiBurnUserInfo storage user = multiBurnUserInfo[_pid][msg.sender];
        uint256 blocks = getBlocks(user.startBlock, block.number);
        uint256 ticks = blocks.div(pool.blockRate);
        uint256 burned = ticks.mul(pool.burnRate);
        uint256 reward = 0;
        if (burned > user.amountStakedOfEach) {
            reward = user.amountStakedOfEach.mul(1e5).div(pool.burnRate).mul(pool.rewardRate).div(1e5);
            burned = user.amountStakedOfEach;
            user.amountStakedOfEach = 0;
        }
        else {
            reward = ticks.mul(pool.rewardRate);
            user.amountStakedOfEach = user.amountStakedOfEach.sub(burned);
        }
        // burn token
        for (uint i = 0; i < pool.burningStakeTokens.length; i++) {
            MyERC20Token token = pool.burningStakeTokens[i];
            token.burn(burned);
        }

        // nothing goes into chest
        uint256 userAmount = reward.mul(100 - 5).div(100);
        uint256 devAmount = reward.mul(5).div(100);
        pool.receiveToken.mint(msg.sender, userAmount);
        pool.receiveToken.mint(devaddr, devAmount);
        user.startBlock = block.number;
        return (reward);
    }

    //    ----------------------------- Raid Methods --------------------------------------------

    function allowRaids(uint256 _raidFrequency) public onlyOwner {
        raidFrequency = _raidFrequency;
        raidBlock = block.number.add(raidFrequency);
        knightsProvidedInRaid.push();
    }

    function joinRaid(uint256 _amount) public returns (bool) {
        require(startBlock <= block.number, "not yet started.");

        knightToken.transferFrom(address(msg.sender), address(this), _amount);
        if (block.number == raidBlock) {
            uint256 currentRaidId = knightsProvidedInRaid.length.sub(1);

            // can only join a raid once
            if (knightsProvidedInRaid[currentRaidId][msg.sender] != 0) {
                return false;
            }
            knightsProvidedInRaid[currentRaidId][msg.sender] = _amount;
            participatedInRaid.push(msg.sender);
            return true;
        }
        else {
            uint256 returnAmount = _amount.mul(returnIfNotInRaidPercentage).div(100);
            uint256 burnAmount = _amount.sub(returnAmount);
            knightToken.burn(burnAmount);
            knightToken.transfer(address(msg.sender), returnAmount);
            return false;
        }
    }

    function checkAndCalculateRaidShares() public {
        require(block.number > raidBlock, "raid not started!");
        uint256 totalKnights = 0;
        uint256 currentRaidId = knightsProvidedInRaid.length.sub(1);
        for (uint i = 0; i < participatedInRaid.length; i++) {
            address user = participatedInRaid[i];
            totalKnights = totalKnights.add(knightsProvidedInRaid[currentRaidId][user]);
        }
        // check if minimum amount of knights were in raid to win
        if (totalKnights < knightToken.totalSupply().div(raidWinPercentage)) {
            // minimum amount of knights not participated
            knightToken.burn(totalKnights);
            delete participatedInRaid;
            knightsProvidedInRaid.push();
            raidBlock = raidBlock.add(raidFrequency);
            return;
        }

        // calculate each users share times 1e12
        for (uint i = 0; i < participatedInRaid.length; i++) {
            address user = participatedInRaid[i];
            uint256 knights = knightsProvidedInRaid[currentRaidId][user];
            uint256 userShare = knights.mul(1e12).div(totalKnights);
            raidShare[user] = userShare;
        }

        // burn provided knights after shares have been calculated
        knightToken.burn(totalKnights);
        delete participatedInRaid;
        knightsProvidedInRaid.push();
        raidBlock = raidBlock.add(raidFrequency);
    }

    function claimRaidRewards() public {
        uint256 userShare = raidShare[msg.sender];
        address user = msg.sender;
        // distribute normal pool rewards
        for (uint j = 0; j < normalPoolInfo.length; j++) {
            NormalPoolInfo storage poolInfo = normalPoolInfo[j];
            uint256 stakeChestShare = poolInfo.stakeChestAmount.mul(userShare).div(1e12).mul(raidWinLootPercentage).div(100);
            uint256 receiveChestShare = poolInfo.receiveChestAmount.mul(userShare).div(1e12).mul(raidWinLootPercentage).div(100);
            poolInfo.stakeToken.transfer(user, stakeChestShare);
            poolInfo.receiveToken.transfer(user, receiveChestShare);
            poolInfo.stakeChestAmount = poolInfo.stakeChestAmount.sub(stakeChestShare);
            poolInfo.receiveChestAmount = poolInfo.receiveChestAmount.sub(receiveChestShare);
        }

        // distribute burn pool rewards
        for (uint j = 0; j < burnPoolInfo.length; j++) {
            BurnPoolInfo storage poolInfo = burnPoolInfo[j];
            uint256 stakeChestShare = poolInfo.stakeChestAmount.mul(userShare).div(1e12).mul(raidWinLootPercentage).div(100);
            uint256 receiveChestShare = poolInfo.receiveChestAmount.mul(userShare).div(1e12).mul(raidWinLootPercentage).div(100);
            poolInfo.burningStakeToken.transfer(user, stakeChestShare);
            poolInfo.receiveToken.transfer(user, receiveChestShare);
            poolInfo.stakeChestAmount = poolInfo.stakeChestAmount.sub(stakeChestShare);
            poolInfo.receiveChestAmount = poolInfo.receiveChestAmount.sub(receiveChestShare);
        }

        // distribute multi burn pool rewards
        for (uint j = 0; j < multiBurnPoolInfo.length; j++) {
            MultiBurnPoolInfo storage poolInfo = multiBurnPoolInfo[j];
            uint256 stakeChestShare = poolInfo.stakeChestAmount.mul(userShare).div(1e12).mul(raidWinLootPercentage).div(100);
            for (uint x = 0; x < poolInfo.burningStakeTokens.length; x++) {
                poolInfo.burningStakeTokens[x].transfer(user, stakeChestShare);
            }
            poolInfo.stakeChestAmount = poolInfo.stakeChestAmount.sub(stakeChestShare);
        }

        raidShare[msg.sender] = 0;
    }

    //    --------------------------------------------------------------------------------------------

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

    function activateVoting() public onlyOwner {
        votingActive = true;
    }

    function vote(uint256 _amount) public {
        require(votingActive);
        // only allowed to vote once
        require(voteAmount[msg.sender] == 0);
        knightToken.transferFrom(address(msg.sender), address(this), _amount);
        voted = voted.add(_amount);
        voters.push(msg.sender);
        voteAmount[msg.sender] = _amount;
    }

    // expensive operation
    function drainChest() public onlyOwner {
        require(votingActive);
        // more than 10% of total supply must vote
        require(voted >= knightToken.totalSupply().div(10).mul(100));

        for (uint i = 0; i < voters.length; i++) {
            address user = voters[i];
            uint256 knights = voteAmount[user];
            uint256 userShare = knights.mul(1e12).div(voted);
            // distribute normal pool rewards
            for (uint j = 0; j < normalPoolInfo.length; j++) {
                NormalPoolInfo storage poolInfo = normalPoolInfo[j];
                uint256 stakeChestShare = poolInfo.stakeChestAmount.mul(userShare).div(1e12);
                uint256 receiveChestShare = poolInfo.receiveChestAmount.mul(userShare).div(1e12);
                poolInfo.stakeToken.transfer(user, stakeChestShare);
                poolInfo.receiveToken.transfer(user, receiveChestShare);
                poolInfo.stakeChestAmount = poolInfo.stakeChestAmount.sub(stakeChestShare);
                poolInfo.receiveChestAmount = poolInfo.receiveChestAmount.sub(receiveChestShare);
            }

            // distribute burn pool rewards
            for (uint j = 0; j < burnPoolInfo.length; j++) {
                BurnPoolInfo storage poolInfo = burnPoolInfo[j];
                uint256 stakeChestShare = poolInfo.stakeChestAmount.mul(userShare).div(1e12);
                uint256 receiveChestShare = poolInfo.receiveChestAmount.mul(userShare).div(1e12);
                poolInfo.burningStakeToken.transfer(user, stakeChestShare);
                poolInfo.receiveToken.transfer(user, receiveChestShare);
                poolInfo.stakeChestAmount = poolInfo.stakeChestAmount.sub(stakeChestShare);
                poolInfo.receiveChestAmount = poolInfo.receiveChestAmount.sub(receiveChestShare);
            }

            // distribute multi burn pool rewards
            for (uint j = 0; j < multiBurnPoolInfo.length; j++) {
                MultiBurnPoolInfo storage poolInfo = multiBurnPoolInfo[j];
                uint256 stakeChestShare = poolInfo.stakeChestAmount.mul(userShare).div(1e12);
                for (uint x = 0; x < poolInfo.burningStakeTokens.length; x++) {
                    poolInfo.burningStakeTokens[x].transfer(user, stakeChestShare);
                }
                poolInfo.stakeChestAmount = poolInfo.stakeChestAmount.sub(stakeChestShare);
            }

            // clear voteAmount
            knightToken.transfer(user, voteAmount[user]);
            delete voteAmount[user];
        }


        votingActive = false;
        delete voters;
    }
}
