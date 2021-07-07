// SPDX-License-Identifier: MIT
/** 
* WARNING: This is the mock ALI for unit testing. The production of ALI at ALI-token-contract repository.
* The initial values are different from the official contract
*/
pragma solidity >=0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/BEP20.sol";
import '@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol';

// AliToken with Governance.
contract MockTestAliToken is BEP20('Alita Token', 'ALI') {
    
    using SafeMath for uint;

    uint public startBlock;
    uint public keepPercent = 80; // The amount of tokens distributed in the next period is 80% of the previous period

    uint public initialRewardPerBlock = 1000; //5000000000000000000; // scaled by 1e18. That means about 5 ALI per block in the first period

    uint public maximumPeriodIndex = 2; // 9; // Only distribute ALI tokens in 10 periods

    uint public blockPerPeriod = 20; //5256000; // About 3 seconds for a block on Binance Smart Chain. A period is about 6 months.

    uint public maxSupply = 100000000000000000000000000; // scaled by 1e18. That means 100,000,000 ALI

    address public masterChef;
    address public incentive;
    address public keeper; // first token holder when token is initialized

    uint public incentiveWeight;
    uint public masterChefWeight;

    /**
     * @dev Throws if called by any account other than the masterChef or incentive.
     */
    modifier onlyWhitelist() {
        require((masterChef == msg.sender) || (incentive == msg.sender), 'ALI: caller is neither the masterChef nor incentive');
        _;
    }

    /**
     * @param _startBlock the block number of starting to calculate the reward
     * @param _keeper who holds the first minted tokens when initialized
     * @param _amount the minted token amount is sent to keeper
     */
    constructor(uint _startBlock, address _keeper, uint _amount, uint _incentiveWeight, uint _masterChefWeight) public{
        startBlock = _startBlock < block.number ? block.number : _startBlock;
        keeper = _keeper;
        incentiveWeight = _incentiveWeight;
        masterChefWeight = _masterChefWeight;
        _mintForKeeper(_amount);
    }

    function getKeepPercent() public view returns(uint){
        return keepPercent;
    }

    function getInitialRewardPerBlock() public view returns(uint){
        return initialRewardPerBlock;
    }

    function getMaximumPeriodIndex() public view returns(uint){
        return maximumPeriodIndex;
    }

    function getBlockPerPeriod() public view returns(uint){
        return blockPerPeriod;
    }

    function setMasterChef(address _masterchef) public onlyOwner{
        require(_masterchef != address(0));
        masterChef = _masterchef;
    }

    function setIncentive(address _incentive) public onlyOwner{
        require(_incentive != address(0));
        incentive = _incentive;
    }

    function setMasterChefWeight(uint _masterchefWeight) public onlyOwner{
        require(_masterchefWeight > 0, "ALI: invalid weight");
        require(_masterchefWeight <= 100, "ALI: invalid weight");
        masterChefWeight = _masterchefWeight;
    }

    function setIncentiveWeight(uint _incentiveWeight) public onlyOwner{
        require(_incentiveWeight > 0, "ALI: invalid weight");
        require(_incentiveWeight <= 100, "ALI: invalid weight");
        incentiveWeight = _incentiveWeight;
    }

    function getMasterChefWeight() external view returns(uint) {
        return masterChefWeight;
    }

    function getIncentiveWeight() external view returns(uint) {
        return incentiveWeight;
    }
    
    function mint(address _to, uint256 _amount) public onlyWhitelist {
        uint mintAmount = _amount.add(totalSupply()) > maxSupply ? maxSupply.sub(totalSupply()) : _amount;
        _mint(_to, mintAmount);    
        _moveDelegates(address(0), _delegates[_to], mintAmount);
    }

    function _mintForKeeper(uint256 _amount) private {
        require(keeper != address(0), 'Ali::_mintForKeeper: keeper to the zero address');
        uint mintAmount = _amount.add(totalSupply()) > maxSupply ? maxSupply.sub(totalSupply()) : _amount;
        _mint(keeper, mintAmount);  
    }

    // Copied and modified from YAM code:
    // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernanceStorage.sol
    // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernance.sol
    // Which is copied and modified from COMPOUND:
    // https://github.com/compound-finance/compound-protocol/blob/master/contracts/Governance/Comp.sol

    /// @dev A record of each accounts delegate
    mapping (address => address) internal _delegates;

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint256 votes;
    }

    /// @notice A record of votes checkpoints for each account, by index
    mapping (address => mapping (uint32 => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping (address => uint32) public numCheckpoints;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @notice A record of states for signing / validating signatures
    mapping (address => uint) public nonces;

      /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegator The address to get delegatee for
     */
    function delegates(address delegator)
        external
        view
        returns (address)
    {
        return _delegates[delegator];
    }

    /**
    * @notice Delegate votes from `msg.sender` to `delegatee`
    * @param delegatee The address to delegate votes to
    */
    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(
        address delegatee,
        uint nonce,
        uint expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name())),
                getChainId(),
                address(this)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                DELEGATION_TYPEHASH,
                delegatee,
                nonce,
                expiry
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "Ali::delegateBySig: invalid signature");
        require(nonce == nonces[signatory]++, "Ali::delegateBySig: invalid nonce");
        require(now <= expiry, "Ali::delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account)
        external
        view
        returns (uint256)
    {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber)
        external
        view
        returns (uint256)
    {
        require(blockNumber < block.number, "Ali::getPriorVotes: not yet determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee)
        internal
    {
        address currentDelegate = _delegates[delegator];
        uint256 delegatorBalance = balanceOf(delegator); // balance of underlying Alis (not scaled);
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(address srcRep, address dstRep, uint256 amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                // decrease old representative
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint256 srcRepNew = srcRepOld.sub(amount);
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                // increase new representative
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint256 dstRepNew = dstRepOld.add(amount);
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegatee,
        uint32 nCheckpoints,
        uint256 oldVotes,
        uint256 newVotes
    )
        internal
    {
        uint32 blockNumber = safe32(block.number, "Ali::_writeCheckpoint: block number exceeds 32 bits");

        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function getChainId() internal pure returns (uint) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return chainId;
    }

    function setInitialRewardPerBlock(uint _initialRewardPerBlock) public onlyOwner {
        initialRewardPerBlock = _initialRewardPerBlock;
    }

    function setKeepPercent(uint _keepPercent) public onlyOwner {
        require(_keepPercent > 0 , "Ali::setKeepPercent: _keepPercent must be greater 0");
        require(_keepPercent <= 100 , "Ali::setKeepPercent: _keepPercent must be less or equal 100");
        keepPercent = _keepPercent;
    }

    function setBlockPerPeriod(uint _blockPerPeriod) public onlyOwner {
        require(blockPerPeriod > 0 , "Ali::setBlockPerPeriod: _blockPerPeriod must be greater 0");
        blockPerPeriod = _blockPerPeriod;
    }
    
}