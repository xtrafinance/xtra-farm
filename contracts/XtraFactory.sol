// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./libs/IBEP20.sol";
import "./libs/SafeBEP20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./XtraToken.sol";
import "./IAffiliateManager.sol";

// XtraFactory is the master of Xtra. It can make Xtra and it is fair.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once XTRA is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract XtraFactory is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of XTRAs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accXtraPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accXtraPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;            // Address of LP token contract.
        uint256 allocPoint;        // How many allocation points assigned to this pool. XTRAs to distribute per block.
        uint256 lastRewardBlock;   // Last block number that XTRAs distribution occurs.
        uint256 accXtraPerShare;   // Accumulated XTRAs per share, times 1e12. See below.
        uint16 depositFeeBP;       // Deposit fee in basis points
        bool depositsDisabled;     // Disables deposits to this pool
    }

    // The XTRA TOKEN!
    XtraToken public xtra;
    // XTRA tokens created per block.
    uint256 public xtraPerBlock;
    // Deposit Fee address
    address public feeAddress;
    // Emission master address
    address public emissionMaster;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The block number when XTRA mining starts.
    uint256 public startBlock;

    IAffiliateManager public affiliateManager;
    uint16 public affiliateShare;
    bool public isAffiliateActive;
    bool public allowAddressAffiliate;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdateEmissionRate(address indexed user, uint256 xtraPerBlock);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetEmissionMaster(address indexed user, address indexed newAddress);
    event UpdateAffiliateSettings(address indexed user, address indexed newAddress, bool isAffiliateActive, bool allowAddressAffiliate, uint16 affiliateShare);

    constructor(
        XtraToken _xtra,
        address _feeAddress,
        uint256 _xtraPerBlock,
        uint256 _startBlock,
        IAffiliateManager _affiliateManager
    ) public {
        xtra = _xtra;
        feeAddress = _feeAddress;
        xtraPerBlock = _xtraPerBlock;
        startBlock = _startBlock;

        if (address(_affiliateManager) != address(0x0)) {
            affiliateManager = _affiliateManager;
            isAffiliateActive = true;
        }
        allowAddressAffiliate = true;
        affiliateShare = 1000;

        // init first pool
        uint256 pool0allocPoints = 1000;
        totalAllocPoint = pool0allocPoints;
        poolExistence[xtra] = true;
        poolInfo.push(
            PoolInfo({
                lpToken : xtra,
                allocPoint : pool0allocPoints,
                lastRewardBlock : startBlock,
                accXtraPerShare : 0,
                depositFeeBP : 0,
                depositsDisabled : false
            })
        );

        emissionMaster = msg.sender;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IBEP20 => bool) public poolExistence;

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IBEP20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(poolExistence[_lpToken] == false, "Pool already exists");
        require(_depositFeeBP <= 10000, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(
            PoolInfo({
                lpToken : _lpToken,
                allocPoint : _allocPoint,
                lastRewardBlock : lastRewardBlock,
                accXtraPerShare : 0,
                depositFeeBP : _depositFeeBP,
                depositsDisabled : false
            })
        );
    }

    // Update the given pool's XTRA allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 10000, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
    }

    // View function to see pending XTRAs on frontend.
    function pendingXtra(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accXtraPerShare = pool.accXtraPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 xtraReward = block.number.sub(pool.lastRewardBlock).mul(xtraPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accXtraPerShare = accXtraPerShare.add(xtraReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accXtraPerShare).div(1e12).sub(user.rewardDebt);
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
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        if (pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 xtraReward = block.number.sub(pool.lastRewardBlock).mul(xtraPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        xtra.mint(feeAddress, xtraReward.div(10));
        xtra.mint(address(this), xtraReward);
        pool.accXtraPerShare = pool.accXtraPerShare.add(xtraReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to XtraFactory for XTRA allocation.
    function deposit(uint256 _pid, uint256 _amount) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accXtraPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeXtraTransfer(msg.sender, pending);
                if (isAffiliateActive == true && affiliateManager.hasAffiliate(msg.sender) == true) {
                    uint256 affiliateReward = pending.mul(affiliateShare).div(10000);
                    payAffiliate(msg.sender, affiliateReward);
                }
            }
        }
        if (_amount > 0) {
            require(!pool.depositsDisabled, "deposit: Deposits to this pools are disabled");
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accXtraPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from XtraFactory.
    function withdraw(uint256 _pid, uint256 _amount) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: invalid amount");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accXtraPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            safeXtraTransfer(msg.sender, pending);
            if (isAffiliateActive == true && affiliateManager.hasAffiliate(msg.sender) == true) {
                uint256 affiliateReward = pending.mul(affiliateShare).div(10000);
                payAffiliate(msg.sender, affiliateReward);
            }
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accXtraPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe xtra transfer function, just in case if rounding error causes pool to not have enough XTRAs.
    function safeXtraTransfer(address _to, uint256 _amount) internal {
        uint256 xtraBal = xtra.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > xtraBal) {
            transferSuccess = xtra.transfer(_to, xtraBal);
        } else {
            transferSuccess = xtra.transfer(_to, _amount);
        }
        require(transferSuccess, "safeXtraTransfer: transfer failed");
    }

    function setFeeAddress(address _feeAddress) external {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    function setEmissionMaster(address newEmissionMaster) external {
        require(msg.sender == emissionMaster, "setEmissionMaster: FORBIDDEN");
        emissionMaster = newEmissionMaster;
        emit SetEmissionMaster(msg.sender, emissionMaster);
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _xtraPerBlock) external {
        require(msg.sender == emissionMaster, "updateEmissionRate: FORBIDDEN");
        massUpdatePools();
        xtraPerBlock = _xtraPerBlock;
        emit UpdateEmissionRate(msg.sender, _xtraPerBlock);
    }

    function depositWithAffiliateAddress(uint256 _pid, uint256 _amount, address affiliateAddress) external {
        if (isAffiliateActive == true) {
            if (allowAddressAffiliate == true){            
                affiliateManager.setAffiliate(msg.sender, affiliateAddress);
            } else {
                affiliateManager.setAffiliate(msg.sender, address(0x0));
            }
        }
        deposit(_pid, _amount);
    }

    function depositWithAffiliateName(uint256 _pid, uint256 _amount, string memory affiliateName) external {
        if (isAffiliateActive == true)
            affiliateManager.setAffiliate(msg.sender, affiliateName);
        deposit(_pid, _amount);
    }

    function setIsAffiliateActive(bool _isAffiliateActive) external onlyOwner {
        isAffiliateActive = _isAffiliateActive;
        emit UpdateAffiliateSettings(msg.sender, address(affiliateManager), isAffiliateActive, allowAddressAffiliate, affiliateShare);
    }

    function setAllowAddressAffiliate(bool _allowAddressAffiliate) external onlyOwner {
        allowAddressAffiliate = _allowAddressAffiliate;
        emit UpdateAffiliateSettings(msg.sender, address(affiliateManager), isAffiliateActive, allowAddressAffiliate, affiliateShare);
    }

    function setAffiliateManager(IAffiliateManager _affiliateManager) external onlyOwner {
        affiliateManager = _affiliateManager;

        emit UpdateAffiliateSettings(msg.sender, address(affiliateManager), isAffiliateActive, allowAddressAffiliate, affiliateShare);
    }

    function setAffiliateShare(uint16 _affiliateShare) external onlyOwner {
        require (_affiliateShare <= 2000);        
        affiliateShare = _affiliateShare;
        emit UpdateAffiliateSettings(msg.sender, address(affiliateManager), isAffiliateActive, allowAddressAffiliate, affiliateShare);
    }

    function payAffiliate(address user, uint256 affiliateReward) internal {
        if (affiliateReward > 0) {
            (, bool invitedWithName) = affiliateManager.getUserStatus(user);
            if (invitedWithName == false && allowAddressAffiliate == false)
                return;

            affiliateManager.payAffiliateInTokensWithCallback(msg.sender, xtra, affiliateReward);
        }
    }

    function payAffiliateInTokens(address tokenAddress, address affiliateAddress, uint256 affiliateAmount, address feeAddress, uint256 feeAmount) external {
        require(msg.sender == address(affiliateManager), "payAffiliateInTokens: FORBIDDEN");
        xtra.mint(affiliateAddress, affiliateAmount);
        xtra.mint(feeAddress, feeAmount);
    }

    function toggleDeposits(uint256 pid) external onlyOwner {
        require(pid < poolInfo.length, "toggleDeposits: INVALID POOL ID");
        poolInfo[pid].depositsDisabled = !poolInfo[pid].depositsDisabled;
    }

    function getStakedAmount(uint256 pid, address userAddress) external view returns(uint256) {
        if (pid >= poolInfo.length) 
            return 0;
        return userInfo[pid][userAddress].amount;
    }
    
    // we want it to be compliant with BEP20 balanceOf, so it's possble to switch between XTRA Token and Factory for checking staked XTRA amount
    function balanceOf(address userAddress) public view returns (uint256) {
        return userInfo[0][userAddress].amount;
    }

}