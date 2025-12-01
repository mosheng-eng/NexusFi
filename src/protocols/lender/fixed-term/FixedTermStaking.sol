// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {UnderlyingToken} from "src/underlying/UnderlyingToken.sol";
import {UnderlyingTokenExchanger} from "src/underlying/UnderlyingTokenExchanger.sol";
import {IWhitelist} from "src/whitelist/IWhitelist.sol";
import {Roles} from "src/common/Roles.sol";
import {Errors} from "src/common/Errors.sol";
import {FixedTermToken} from "src/protocols/lender/fixed-term/FixedTermToken.sol";

/// @title FixedTermStaking
/// @author Mr.Silent
/// @notice Fixed-term staking contract allowing users to stake ERC20 tokens for a fixed period in exchange for interest-bearing NFTs.
/// @notice Inherits from FixedTermToken to represent stakes as ERC721 tokens.
contract FixedTermStaking is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    FixedTermToken
{
    using Arrays for uint256[];

    /// @dev enumeration of stake status
    /// @notice contained in each StakeRecord
    enum StakeStatus {
        /// @dev default value, not existed
        NOT_EXISTED,
        /// @dev active stake
        ACTIVE,
        /// @dev already unstaked
        CLOSED
    }

    /// @dev record of each fixed-term stake
    /// @notice stored in mapping, each entry takes 3 slots
    struct StakeInfo {
        /// @dev principal amount staked
        uint128 principal;
        /// @dev start date of fixed-term stake
        uint64 startDate;
        /// @dev maturity date of fixed-term stake
        uint64 maturityDate;
        /// @dev indicates the status of fixed-term stake
        StakeStatus status;
    }

    /// @dev information of each asset in a basket
    /// @notice used in multi-asset basket
    struct AssetInfo {
        /// @dev the address of the asset vault, which must implement IERC4626
        address targetVault;
        /// @dev weight of the asset in the basket, in million (1_000_000 = 100%)
        uint64 weight;
    }

    /// @notice Event emitted when stake happens
    /// @param from the address who pay for underlying tokens
    /// @param to the address who receive the fixed-term NFT
    /// @param principal the amount of underlying tokens staked
    /// @param tokenId the ID of the minted fixed-term NFT
    event Stake(address indexed from, address indexed to, uint128 principal, uint256 tokenId);

    /// @notice Event emitted when unstake happens
    /// @param from the address who own the fixed-term NFT
    /// @param to the address who receive the underlying tokens
    /// @param principal the principal amount of underlying tokens returned
    /// @param interest the interest amount of underlying tokens returned
    /// @param tokenId the ID of the burned fixed-term NFT
    event Unstake(address indexed from, address indexed to, uint128 principal, int128 interest, uint256 tokenId);

    /// @notice Event emitted when update stake fee rate
    /// @param oldFeeRate the old stake fee rate
    /// @param newFeeRate the new stake fee rate
    event StakeFeeRateUpdated(uint64 oldFeeRate, uint64 newFeeRate);

    /// @notice Event emitted when update unstake fee rate
    /// @param oldFeeRate the old unstake fee rate
    /// @param newFeeRate the new unstake fee rate
    event UnstakeFeeRateUpdated(uint64 oldFeeRate, uint64 newFeeRate);

    /// @notice Event emitted when update accumulated interest rate
    /// @param timestamp the date of the accumulated interest rate
    /// @param accumulatedInterestRate the accumulated interest rate on that date
    event AccumulatedInterestRateUpdated(uint64 timestamp, int64 accumulatedInterestRate);

    /// @notice Event emitted when update maximum supply
    /// @param oldMaxSupply the old maximum supply
    /// @param newMaxSupply the new maximum supply
    event MaxSupplyUpdated(uint128 oldMaxSupply, uint128 newMaxSupply);

    /// @notice Event emitted when update dust balance
    /// @param oldDustBalance the old dust balance
    /// @param newDustBalance the new dust balance
    event DustBalanceUpdated(uint128 oldDustBalance, uint128 newDustBalance);

    /// @notice Error reverted when staking amount over staker's balance
    /// @param balance the staker's balance
    /// @param stakeAmount the staking amount
    error InsufficientBalance(uint128 balance, uint128 stakeAmount);

    /// @notice Error reverted when staking amount over staker's allowance to this contract
    /// @param allowance the staker's allowance to this contract
    /// @param stakeAmount the staking amount
    error InsufficientAllowance(uint128 allowance, uint128 stakeAmount);

    /// @notice Error reverted when staking amount after fee plus total principal over max supply
    /// @param stakeAmountAfterFee the staking amount after fee deduction
    /// @param totalPrincipal the total principal amount staked
    /// @param maxSupply the maximum supply of tokens that can be staked
    error ExceedMaxSupply(uint128 stakeAmountAfterFee, uint128 totalPrincipal, uint128 maxSupply);

    /// @notice Error reverted when remaining balance substracting staking amount after fee is below dust balance
    /// @param stakeAmountAfterFee the staking amount after fee deduction
    /// @param remainingBalance the remaining balance before staking
    /// @param dustBalance the minimum remaining balance to prevent small stakes
    error BelowDustBalance(uint128 stakeAmountAfterFee, uint128 remainingBalance, uint128 dustBalance);

    /// @notice Error reverted when unstaking before maturity date
    /// @param tokenId the ID of the unstaked fixed-term NFT
    /// @param maturityDate the maturity date of the unstaked fixed-term NFT
    /// @param currentDate the current date when unstaking is attempted
    error StakeNotMatured(uint256 tokenId, uint64 maturityDate, uint64 currentDate);

    /// @notice Error reverted when oracle report is not ready on maturity date
    error WaitingForMaturityDateFeed();

    /// @notice Error reverted when unstaking an already unstaked fixed-term NFT
    /// @param tokenId the ID of the unstaked fixed-term NFT
    error AlreadyUnstaked(uint256 tokenId);

    /// @notice Error reverted when fee rate is over maximum limit
    /// @param feeRate the fee rate that was attempted to be set
    error InvalidFeeRate(uint64 feeRate);

    /// @notice Error reverted when an address is zero
    /// @param addr the name of the address
    error ZeroAddress(string addr);

    /// @notice Error reverted when a required parameter is uninitialized
    /// @param name the name of the uninitialized parameter
    error Uninitialized(string name);

    /// @notice Error reverted when a parameter value is invalid
    /// @param name the name of the invalid parameter
    error InvalidValue(string name);

    /// @notice Error reverted when caller is not the owner of the token
    /// @param who the address of the caller
    /// @param tokenId the ID of the token
    error NotTokenOwner(address who, uint256 tokenId);

    /// @notice Error reverted when feeding at an ancient time which is already fed
    /// @param update the time that inputs into feed function (normalized time)
    /// @param last the last time that feed function was called (normalized time)
    /// @param current the current time (non-normalized time)
    error AncientFeedTimeUpdateIsNotAllowed(uint64 update, uint64 last, uint64 current);

    /// @notice Error reverted when feeding at the current time which is already fed
    /// @param update the time that inputs into feed function (normalized time)
    /// @param last the last time that feed function was called (normalized time)
    /// @param current the current time (non-normalized time)
    error LastFeedTimeUpdateRequireForce(uint64 update, uint64 last, uint64 current);

    /// @notice Error reverted when feeding at a future time which is not allowed
    /// @param update the time that inputs into feed function (normalized time)
    /// @param last the last time that feed function was called (normalized time)
    /// @param current the current time (non-normalized time)
    error FutureFeedTimeUpdateIsNotAllowed(uint64 update, uint64 last, uint64 current);

    /// @notice Error reverted when vault asset is not the same as exchanger token1
    /// @param vaultAsset the asset of the vault
    /// @param exchangerToken1 the token1 of the exchanger
    error VaultAssetNotEqualExchangerToken1(address vaultAsset, address exchangerToken1);

    /// @notice Error reverted when exchanger token0 is not the same as underlying token
    /// @param exchangerToken0 the token0 of the exchanger
    /// @param underlyingToken the underlying token
    error ExchangerToken0NotEqualUnderlyingToken(address exchangerToken0, address underlyingToken);

    /// @notice Error reverted when interest rate is unbelievable (over maximum limit)
    /// @param interestRate the interest rate that was attempted to feed
    /// @param maxInterestRate the maximum interest rate per day
    /// @param minInterestRate the minimum interest rate per day
    error UnbelievableInterestRate(int64 interestRate, int64 maxInterestRate, int64 minInterestRate);

    /// @notice Error reverted when investment into target vault failed
    /// @param depositAmount the amount attempted to deposit
    /// @param sharesAmount the amount of shares received from deposit
    /// @param targetVault the address of the target vault
    error DepositFailed(uint128 depositAmount, uint128 sharesAmount, address targetVault);

    /// @notice Error reverted when withdraw from target vault failed
    /// @param withdrawAmount the amount attempted to withdraw
    /// @param sharesAmount the amount of shares received from withdraw
    /// @param targetVault the address of the target vault
    error WithdrawFailed(uint128 withdrawAmount, uint128 sharesAmount, address targetVault);

    /// @dev precision in million (1_000_000 = 100%)
    /// @notice constant, not stored in storage
    uint64 public constant PRECISION = 1_000_000;
    /// @dev maximum fee rate (5%)
    /// @notice constant, not stored in storage
    uint64 public constant MAX_FEE_RATE = 50_000;
    /// @dev maximum interest rate per day (1%)
    /// @notice constant, not stored in storage
    int64 public constant MAX_INTEREST_RATE_PER_DAY = 10_000;
    /// @dev minimum interest rate per day (-1%)
    /// @notice constant, not stored in storage
    int64 public constant MIN_INTEREST_RATE_PER_DAY = -10_000;
    /// @dev ERC20 token used for staking
    /// @notice stored in slot 0
    address public _underlyingToken;
    /// @dev only allow whitelisted address to stake/unstake
    /// @notice stored in slot 1
    address public _whitelist;
    /// @dev address of the exchanger contract for deposit/withdraw underlying tokens
    /// @notice stored in slot 2
    /// @notice we use exchanger to calculate how much deposit token should be invested into each vault when staking
    /// @notice we use exchanger to calculate how much deposit token should be withdrawn from each vault when unstaking
    address public _exchanger;
    /// @dev record of the total amount staked
    /// @notice stored in slot 3
    uint128 public _totalPrincipal;
    /// @dev record of the total fees collected
    /// @notice stored in slot 3
    uint128 public _totalFee;
    /// @dev record of the total interest accumulated
    /// @notice stored in slot 4
    int128 public _totalInterest;
    /// @dev remaining balance for staking
    /// @notice stored in slot 4
    uint128 public _remainingBalance;
    /// @dev minimum remaining balance to prevent small stakes
    /// @notice stored in slot 5
    uint128 public _dustBalance;
    /// @dev maximum supply of tokens that can be staked
    /// @notice stored in slot 5
    uint128 public _maxSupply;
    /// @dev timestamp of oracle latest report
    /// @notice stored in slot 6
    uint64 public _lastFeedTime;
    /// @dev lock period for fixed-term staking
    /// @notice stored in slot 6
    uint64 public _lockPeriod;
    /// @dev fee rate for staking operations
    /// @notice stored in slot 6
    uint64 public _stakeFeeRate;
    /// @dev fee rate for unstaking operations
    /// @notice stored in slot 6
    uint64 public _unstakeFeeRate;
    /// @dev tokenId => StakeInfo
    /// @notice mapping storage
    mapping(uint256 => StakeInfo) public _tokenId_stakeInfo;
    /// @dev startDate => total principal that starts on that date
    /// @notice mapping storage
    mapping(uint64 => uint128) public _startDate_principal;
    /// @dev maturityDate => total principal that matures on that date
    /// @notice mapping storage
    mapping(uint64 => uint128) public _maturityDate_principal;
    /// @dev date => accumulated interest rate at that date
    /// @notice mapping storage
    mapping(uint64 => int64) public _accumulatedInterestRate;
    /// @dev sorted list of all timepoints (startDate and maturityDate)
    /// @notice dynamic array storage
    uint256[] private _timepoints;
    /// @dev list of all assets in the basket
    /// @notice dynamic array storage, initialized when deploying this contract
    AssetInfo[] private _assetsInfoBasket;

    /// @dev whitelist check modifier
    /// @param who_ The address to be checked against the whitelist
    modifier onlyWhitelisted(address who_) {
        if (_whitelist == address(0)) {
            revert ZeroAddress("whitelist");
        }
        if (who_ == address(0)) {
            revert ZeroAddress("user");
        }
        if (!IWhitelist(_whitelist).isWhitelisted(who_)) {
            revert IWhitelist.NotWhitelisted(who_);
        }
        _;
    }

    /// @dev initialization check modifier
    modifier onlyInitialized() {
        if (_underlyingToken == address(0)) {
            revert Uninitialized("underlyingToken");
        }
        if (_whitelist == address(0)) {
            revert Uninitialized("whitelist");
        }
        if (_exchanger == address(0)) {
            revert Uninitialized("exchanger");
        }
        if (_lockPeriod == 0) {
            revert Uninitialized("lockPeriod");
        }
        if (_maxSupply == 0) {
            revert Uninitialized("maxSupply");
        }
        if (_lastFeedTime == 0) {
            revert Uninitialized("lastFeedTime");
        }
        if (_assetsInfoBasket.length == 0) {
            revert Uninitialized("assetsInfoBasket");
        }

        _;
    }

    /// @dev disable initializers for implementation contract
    /// @notice only used as implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @dev initializer instead of constructor for upgradeable contracts
    /// @param addrs_ Array of addresses: [0] owner_, [1] underlyingToken_, [2] whitelist_, [3] minter_
    /// @param properties_ Packed uint256 containing: [0~63] lockPeriod_, [64~127] stakeFeeRate_, [128~191] unstakeFeeRate_
    /// @param limits_ Packed uint256 containing: [0~127] dustBalance_, [128~255] maxSupply_
    /// @param name_ The name of the staking token
    /// @param symbol_ The symbol of the staking token
    function initialize(
        /**
         * 0: address owner_,
         * 1: address underlyingToken_,
         * 2: address whitelist_,
         * 3: address exchanger_,
         */
        address[4] calldata addrs_,
        /**
         * [0~63]: uint64 lockPeriod_,
         * [64~127]: uint64 stakeFeeRate_,
         * [128~191]: uint64 unstakeFeeRate_,
         * [192~255]: uint64 startFeedTime_
         */
        uint256 properties_,
        /**
         * [0~127]: uint128 dustBalance_,
         * [128~255]: uint128 maxSupply_,
         */
        uint256 limits_,
        string calldata name_,
        string calldata symbol_,
        AssetInfo[] calldata assetsInfoBasket_
    ) public initializer {
        if (addrs_.length != 4) {
            revert Errors.InvalidValue("addresses length mismatch");
        }
        if (addrs_[0] == address(0)) {
            revert ZeroAddress("owner");
        }
        if (addrs_[1] == address(0)) {
            revert ZeroAddress("underlyingToken");
        }
        if (addrs_[2] == address(0)) {
            revert ZeroAddress("whitelist");
        }
        if (addrs_[3] == address(0)) {
            revert ZeroAddress("exchanger");
        }
        if (uint64(properties_) == 0 || uint64(properties_) % 1 days != 0) {
            revert InvalidValue("lockPeriod");
        }
        if (uint64(properties_ >> 64) >= MAX_FEE_RATE) {
            revert InvalidValue("stakeFeeRate");
        }
        if (uint64(properties_ >> 128) >= MAX_FEE_RATE) {
            revert InvalidValue("unstakeFeeRate");
        }
        if (uint64(properties_ >> 192) == 0) {
            revert InvalidValue("startFeedTime");
        }
        if (bytes(name_).length == 0) {
            revert InvalidValue("name");
        }
        if (bytes(symbol_).length == 0) {
            revert InvalidValue("symbol");
        }
        if (assetsInfoBasket_.length == 0) {
            revert InvalidValue("assetsInfoBasket");
        }

        __AccessControl_init_unchained();
        __ReentrancyGuard_init_unchained();
        __Pausable_init_unchained();
        __FixedTermToken_init(name_, symbol_);

        uint64 totalWeight = 0;
        for (uint256 i = 0; i < assetsInfoBasket_.length; i++) {
            if (assetsInfoBasket_[i].targetVault == address(0)) {
                revert ZeroAddress("asset vault");
            }
            if (assetsInfoBasket_[i].weight == 0 || assetsInfoBasket_[i].weight > PRECISION) {
                revert InvalidValue("weight of asset in basket");
            }
            totalWeight += assetsInfoBasket_[i].weight;
            if (totalWeight > PRECISION) {
                revert InvalidValue("total weight of assets in basket");
            }
            if (IERC4626(assetsInfoBasket_[i].targetVault).asset() != UnderlyingTokenExchanger(addrs_[3])._token1()) {
                revert VaultAssetNotEqualExchangerToken1(
                    IERC4626(assetsInfoBasket_[i].targetVault).asset(), UnderlyingTokenExchanger(addrs_[3])._token1()
                );
            }
            if (UnderlyingTokenExchanger(addrs_[3])._token0() != addrs_[1]) {
                revert ExchangerToken0NotEqualUnderlyingToken(UnderlyingTokenExchanger(addrs_[3])._token0(), addrs_[1]);
            }
            _assetsInfoBasket.push(assetsInfoBasket_[i]);
        }

        _underlyingToken = addrs_[1];
        _whitelist = addrs_[2];
        _exchanger = addrs_[3];
        _lockPeriod = uint64(properties_);
        _stakeFeeRate = uint64(properties_ >> 64);
        _unstakeFeeRate = uint64(properties_ >> 128);
        _lastFeedTime = _normalizeTimestamp(uint64(properties_ >> 192));
        _dustBalance = uint128(limits_);
        _maxSupply = uint128(limits_ >> 128);
        _remainingBalance = _maxSupply;

        _grantRole(Roles.OWNER_ROLE, addrs_[0]);
        _setRoleAdmin(Roles.OPERATOR_ROLE, Roles.OWNER_ROLE);
    }

    /// @notice any whitelisted address can stake tokens when not paused
    /// @param stakeAmount_ The amount of tokens to stake (including fees)
    /// @return The tokenId of the minted fixed-term NFT
    function stake(uint128 stakeAmount_)
        external
        whenNotPaused
        nonReentrant
        onlyWhitelisted(msg.sender)
        returns (uint256)
    {
        return _stake(stakeAmount_, msg.sender, msg.sender);
    }

    /// @notice any whitelisted address can unstake tokens when not paused
    /// @param tokenId_ The tokenId of the fixed-term NFT to unstake
    /// @return The net amount of underlying tokens repaid (principal + interest - fees)
    function unstake(uint256 tokenId_)
        external
        whenNotPaused
        nonReentrant
        onlyWhitelisted(msg.sender)
        returns (uint128)
    {
        return _unstake(tokenId_, msg.sender, msg.sender);
    }

    /// @notice only controller roles can stake tokens on behalf of another address
    /// @param stakeAmount_ The amount of tokens to stake (including fees)
    /// @param who_ The address from which the underlying tokens will be transferred and the fixed-term NFT will be minted to
    /// @return The tokenId of the minted fixed-term NFT
    function stakeFrom(uint128 stakeAmount_, address who_)
        external
        onlyRole(Roles.OPERATOR_ROLE)
        whenNotPaused
        nonReentrant
        onlyWhitelisted(who_)
        returns (uint256)
    {
        return _stake(stakeAmount_, who_, who_);
    }

    /// @notice only controller roles can unstake tokens on behalf of another address
    /// @param tokenId_ The tokenId of the fixed-term NFT to unstake
    /// @param who_ The address from which the fixed-term NFT will be burned and the underlying tokens will be transferred to
    /// @return The net amount of underlying tokens repaid (principal + interest - fees)
    function unstakeFrom(uint256 tokenId_, address who_)
        external
        onlyRole(Roles.OPERATOR_ROLE)
        whenNotPaused
        nonReentrant
        onlyWhitelisted(who_)
        returns (uint128)
    {
        return _unstake(tokenId_, who_, who_);
    }

    /// @dev Internal method to perform staking operations
    /// @param stakeAmount_ The amount of tokens to stake (including fees)
    /// @param from_ The address from which the underlying tokens will be transferred
    /// @param to_ The address to which the fixed-term NFT will be minted
    /// @return tokenId_ The tokenId of the minted fixed-term NFT
    function _stake(uint128 stakeAmount_, address from_, address to_)
        internal
        onlyInitialized
        returns (uint256 tokenId_)
    {
        if (stakeAmount_ == 0) {
            revert InvalidValue("stakeAmount");
        }
        if (from_ == address(0)) {
            revert ZeroAddress("from");
        }
        if (to_ == address(0)) {
            revert ZeroAddress("to");
        }
        uint256 allowance = IERC20(_underlyingToken).allowance(from_, address(this));
        if (allowance < uint256(stakeAmount_)) {
            revert InsufficientAllowance(uint128(allowance), stakeAmount_);
        }
        uint256 balance = IERC20(_underlyingToken).balanceOf(from_);
        if (balance < uint256(stakeAmount_)) {
            revert InsufficientBalance(uint128(balance), stakeAmount_);
        }

        uint128 fee = (stakeAmount_ * _stakeFeeRate + PRECISION - 1) / PRECISION;
        uint128 amountAfterFee = stakeAmount_ - fee;

        if (_totalPrincipal + amountAfterFee > _maxSupply) {
            revert ExceedMaxSupply(amountAfterFee, _totalPrincipal, _maxSupply);
        }
        if (_remainingBalance < amountAfterFee || _remainingBalance - amountAfterFee < _dustBalance) {
            revert BelowDustBalance(amountAfterFee, _remainingBalance, _dustBalance);
        }

        /// @dev calculate startDate and maturityDate
        uint64 startDate = _normalizeTimestamp(uint64(block.timestamp));
        uint64 maturityDate = startDate + _lockPeriod;

        if (_startDate_principal[startDate] == 0) {
            _timepoints.push(startDate);
        }
        if (_maturityDate_principal[maturityDate] == 0) {
            _timepoints.push(maturityDate);
        }

        uint256[] memory timepoints = _timepoints;
        delete _timepoints;
        _timepoints = timepoints.sort();

        _startDate_principal[startDate] += amountAfterFee;
        _maturityDate_principal[maturityDate] += amountAfterFee;

        unchecked {
            _totalPrincipal += amountAfterFee;
            _remainingBalance -= amountAfterFee;
            _totalFee += fee;
        }

        SafeERC20.safeTransferFrom(IERC20(_underlyingToken), from_, address(this), stakeAmount_);
        tokenId_ = mint(to_);

        _tokenId_stakeInfo[tokenId_] = StakeInfo({
            principal: amountAfterFee,
            startDate: startDate,
            maturityDate: maturityDate,
            status: StakeStatus.ACTIVE
        });

        for (uint256 i = 0; i < _assetsInfoBasket.length; i++) {
            AssetInfo memory assetInfo = _assetsInfoBasket[i];
            uint128 assetAmount = UnderlyingTokenExchanger(_exchanger).dryrunExchange(
                (amountAfterFee * assetInfo.weight) / PRECISION, false
            );
            if (assetAmount > 0) {
                UnderlyingTokenExchanger(_exchanger).extractDepositTokenForInvestment(assetAmount);
                SafeERC20.safeIncreaseAllowance(
                    IERC20(UnderlyingTokenExchanger(_exchanger)._token1()), assetInfo.targetVault, assetAmount
                );
                if (IERC4626(assetInfo.targetVault).deposit(assetAmount, address(this)) == 0) {
                    revert DepositFailed(assetAmount, 0, assetInfo.targetVault);
                }
            }
        }

        emit Stake(from_, to_, amountAfterFee, tokenId_);
    }

    /// @dev Internal method to perform unstaking operations
    /// @param tokenId_ The tokenId of the fixed-term NFT to unstake
    /// @param from_ The address from which the fixed-term NFT will be burned
    /// @param to_ The address to which the underlying tokens will be transferred
    /// @return repayAmount_ The total amount of underlying tokens repaid (principal + interest - fees)
    function _unstake(uint256 tokenId_, address from_, address to_)
        internal
        onlyInitialized
        returns (uint128 repayAmount_)
    {
        if (tokenId_ == 0 || tokenId_ >= _tokenId) {
            revert InvalidValue("tokenId");
        }
        if (from_ == address(0)) {
            revert ZeroAddress("from");
        }
        if (to_ == address(0)) {
            revert ZeroAddress("to");
        }

        StakeInfo storage stakeInfo = _tokenId_stakeInfo[tokenId_];

        if (stakeInfo.status == StakeStatus.NOT_EXISTED) {
            revert InvalidValue("tokenId");
        }

        if (stakeInfo.status == StakeStatus.CLOSED) {
            revert AlreadyUnstaked(tokenId_);
        }

        if (_requireOwned(tokenId_) != from_) {
            revert NotTokenOwner(from_, tokenId_);
        }

        if (block.timestamp < stakeInfo.maturityDate) {
            revert StakeNotMatured(tokenId_, stakeInfo.maturityDate, uint64(block.timestamp));
        }

        if (stakeInfo.maturityDate > _lastFeedTime) {
            revert WaitingForMaturityDateFeed();
        }

        int64 accumulatedInterestRateOnStartDate = _accumulatedInterestRate[stakeInfo.startDate];
        int64 accumulatedInterestRateOnMaturityDate = _accumulatedInterestRate[stakeInfo.maturityDate];

        int128 interest = int128(stakeInfo.principal)
            * (accumulatedInterestRateOnMaturityDate - accumulatedInterestRateOnStartDate)
            / SafeCast.toInt128(int256(uint256(PRECISION)));

        uint128 fee = int128(stakeInfo.principal) + interest < 0
            ? 0
            : (uint128(int128(stakeInfo.principal) + interest) * _unstakeFeeRate + PRECISION - 1) / PRECISION;

        unchecked {
            _totalFee += fee;
            _totalInterest -= interest;
            _totalPrincipal -= stakeInfo.principal;
            _remainingBalance += stakeInfo.principal;
            repayAmount_ =
                int128(stakeInfo.principal) + interest < 0 ? 0 : uint128(int128(stakeInfo.principal) + interest) - fee;
        }

        stakeInfo.status = StakeStatus.CLOSED;

        burn(tokenId_);

        uint256 assetNumberInBasket = _assetsInfoBasket.length;
        for (uint256 i = 0; i < assetNumberInBasket; i++) {
            AssetInfo memory assetInfo = _assetsInfoBasket[i];
            /// @dev When user unstake a fixed-term staking, protocol should withdraw corresponding amount from each vault
            /// @dev The key issue is how much underlying token should be withdrawn from all vaults
            /// @dev We choose to only withdraw principal amount from each vaults by proportion, just like what we did when staking
            /// @dev No matter vaults value will decrease or increase later, protocol have settled with user immediately when user unstakes
            uint128 assetAmount = UnderlyingTokenExchanger(_exchanger).dryrunExchange(
                (stakeInfo.principal * assetInfo.weight + PRECISION - 1) / PRECISION, false
            );
            /// @dev Check the maximum withdrawable amount from the vault
            uint128 maxAssetAmount = uint128(IERC4626(assetInfo.targetVault).maxWithdraw(address(this)));
            /// @dev Adjust the withdraw amount if it exceeds the maximum withdrawable amount
            /// @dev This may happen when asset portfolio is modified, e.g. one asset's weight is increased significantly after this stake
            /// @dev In this case, protocol should follow the new strategy and be responsible for the loss or profit
            if (assetAmount > maxAssetAmount) {
                assetAmount = maxAssetAmount;
            }
            if (assetAmount > 0) {
                /// @dev Withdraw asset from each vault where owner is this contract and receiver is the exchanger contract
                /// @dev User will retrieve assets from exchanger contract later
                uint128 sharesAmount =
                    uint128(IERC4626(assetInfo.targetVault).withdraw(assetAmount, _exchanger, address(this)));

                if (sharesAmount == 0) {
                    revert WithdrawFailed(assetAmount, 0, assetInfo.targetVault);
                }
            }
        }

        /// @dev After withdrawing from all vaults, we repay underlying tokens to user
        /// @dev User will retrieve assets from exchanger contract later
        if (repayAmount_ > 0) {
            SafeERC20.safeTransfer(IERC20(_underlyingToken), to_, repayAmount_);
        }

        emit Unstake(from_, to_, stakeInfo.principal, interest, tokenId_);
    }

    /// @notice any address can call this method to feed interest rate when not paused
    /// @param timestamp_ The timestamp to feed (non-normalized)
    /// @return dividends Whether there are dividends to distribute
    function feed(uint64 timestamp_) external whenNotPaused nonReentrant returns (bool dividends) {
        dividends = _feed(timestamp_, false);
    }

    /// @notice only controller roles can force feeding at the same timestamp
    /// @param timestamp_ The timestamp to feed (non-normalized)
    /// @return dividends Whether there are dividends to distribute
    function feedForce(uint64 timestamp_)
        external
        whenNotPaused
        nonReentrant
        onlyRole(Roles.OPERATOR_ROLE)
        returns (bool dividends)
    {
        dividends = _feed(timestamp_, true);
    }

    /// @dev Internal method to perform feeding operations
    /// @param timestamp_ The timestamp to feed (non-normalized)
    /// @param force_ Whether to force the feeding even if the timestamp is the same as the last feed time
    /// @return dividends_ Whether there are dividends to distribute
    /// @notice Timestamp should be strictly increased by 1 day from last feed time, unless force_ is true
    /// @notice Block.timestamp should pass the normalized timestamp.
    /// @notice This means continuous next feeding can only happen at a timepoint at least 1 day after last feed time
    function _feed(uint64 timestamp_, bool force_) internal returns (bool dividends_) {
        uint64 normalizedTimestamp = _normalizeTimestamp(timestamp_);

        /// @dev Only allow to force feed at last feed time or normal feed at next day
        if (
            (normalizedTimestamp == _lastFeedTime && force_)
                || (normalizedTimestamp == _lastFeedTime + 1 days && block.timestamp >= normalizedTimestamp)
        ) {
            /// @dev Calculate interest bearing principal at normalizedTimestamp
            /// @dev Sum up all principals that started before or on normalizedTimestamp and not yet matured
            uint128 interestBearingPrincipal = _calculateInterestBearingPrincipal(normalizedTimestamp);
            if (interestBearingPrincipal == 0) {
                /// @dev Unnecessary to calculate interest rate when there is no interest bearing principal
                /// @dev Because you can not divide interest by zero
                /// @dev Thus unnecessary to calculate interest amount either
                _lastFeedTime = normalizedTimestamp;
                dividends_ = false;
            } else {
                /// @dev Calculate interest earned or lost since last feed time
                int128 interest =
                    int128(getTotalAssetValueInBasket()) - int128(_totalPrincipal) - int128(_totalInterest);
                /// @dev Calculate interest rate per day in base points (1_000_000 = 100%)
                int64 interestRate = int64(interest * int128(int64(PRECISION)) / int128(interestBearingPrincipal));
                /// @dev Prevent malicious oracle feed to asset vaults which may cause unbelievable interest rate
                if (interestRate >= MAX_INTEREST_RATE_PER_DAY || interestRate <= MIN_INTEREST_RATE_PER_DAY) {
                    revert UnbelievableInterestRate(interestRate, MAX_INTEREST_RATE_PER_DAY, MIN_INTEREST_RATE_PER_DAY);
                }
                /// @dev Update accumulated interest rate at normalizedTimestamp
                _accumulatedInterestRate[normalizedTimestamp] = _accumulatedInterestRate[_lastFeedTime] + interestRate;
                /// @dev Update total interest
                _totalInterest += interest;
                /// @dev Update last feed time
                _lastFeedTime = normalizedTimestamp;

                if (interest < 0) {
                    /// @dev Vaults value decreased, pool lost money
                    interest = -interest;

                    /// @dev Check pool reserve before burning underlying tokens
                    /// @dev This balance includes fees collected
                    uint128 fixedTermStakingHoldUnderlyingTokenBalance =
                        uint128(IERC20(_underlyingToken).balanceOf(address(this)));

                    if (uint128(interest) > fixedTermStakingHoldUnderlyingTokenBalance) {
                        /// @dev Not enough underlying tokens to burn, just burn what we have
                        /// @dev This should never happen under normal circumstances
                        /// @dev unless there are bad guys attack the pool or vault and steal underlying tokens
                        /// @dev In such case, protocol should contribute all fees collected to compensate the loss
                        interest = int128(fixedTermStakingHoldUnderlyingTokenBalance);
                    }

                    if (interest > 0) {
                        UnderlyingToken(_underlyingToken).burn(uint256(uint128(interest)));
                    }
                } else if (interest > 0) {
                    /// @dev Vaults value increased, pool earned money
                    UnderlyingToken(_underlyingToken).mint(address(this), uint256(uint128(interest)));
                }

                dividends_ = true;
            }
        }
        /// @dev Handle invalid feeding attempts
        else {
            /// @dev Attempt to feed at an ancient time (before last feed time)
            if (normalizedTimestamp < _lastFeedTime) {
                revert AncientFeedTimeUpdateIsNotAllowed(normalizedTimestamp, _lastFeedTime, uint64(block.timestamp));
            }

            /// @dev Attempt to feed at last feed time without force (only controller can force feed)
            if ((normalizedTimestamp == _lastFeedTime || _accumulatedInterestRate[normalizedTimestamp] != 0) && !force_)
            {
                revert LastFeedTimeUpdateRequireForce(normalizedTimestamp, _lastFeedTime, uint64(block.timestamp));
            }

            /// @dev Attempt to feed at a future time beyond next day
            if (!(normalizedTimestamp == _lastFeedTime + 1 days && block.timestamp >= normalizedTimestamp)) {
                revert FutureFeedTimeUpdateIsNotAllowed(normalizedTimestamp, _lastFeedTime, uint64(block.timestamp));
            }

            /// @dev This case should never happen
            revert("Unrecognized condition!");
        }
    }

    /// @notice Method to update staking fee rate
    /// @param newStakeFeeRate_ The new staking fee rate
    /// @dev only operator role can call this method
    /// @dev only influence future staking operations
    function updateStakeFeeRate(uint64 newStakeFeeRate_) external onlyRole(Roles.OPERATOR_ROLE) {
        if (newStakeFeeRate_ > MAX_FEE_RATE) {
            revert InvalidFeeRate(newStakeFeeRate_);
        }
        uint64 oldStakeFeeRate = _stakeFeeRate;
        _stakeFeeRate = newStakeFeeRate_;
        emit StakeFeeRateUpdated(oldStakeFeeRate, newStakeFeeRate_);
    }

    /// @notice Method to update unstaking fee rate
    /// @param newUnstakeFeeRate_ The new unstaking fee rate
    /// @dev only operator role can call this method
    /// @dev only influence future unstaking operations
    function updateUnstakeFeeRate(uint64 newUnstakeFeeRate_) external onlyRole(Roles.OPERATOR_ROLE) {
        if (newUnstakeFeeRate_ > MAX_FEE_RATE) {
            revert InvalidFeeRate(newUnstakeFeeRate_);
        }
        uint64 oldUnstakeFeeRate = _unstakeFeeRate;
        _unstakeFeeRate = newUnstakeFeeRate_;
        emit UnstakeFeeRateUpdated(oldUnstakeFeeRate, newUnstakeFeeRate_);
    }

    /// @notice Method to update the dust balance limit
    /// @param newDustBalance_ The new dust balance limit
    /// @dev only operator role can call this method
    /// @dev only influence future staking operations
    function updateDustBalance(uint128 newDustBalance_) external onlyRole(Roles.OPERATOR_ROLE) {
        /// @dev New limit should not be compatible with current remaining balance
        if (_remainingBalance < newDustBalance_) {
            revert InvalidValue("dustBalance");
        }

        uint128 oldDustBalance = _dustBalance;
        _dustBalance = newDustBalance_;

        emit DustBalanceUpdated(oldDustBalance, newDustBalance_);
    }

    /// @notice Method to update the maximum supply limit
    /// @param newMaxSupply_ The new maximum supply limit
    /// @dev only operator role can call this method
    /// @dev only influence future staking operations
    function updateMaxSupply(uint128 newMaxSupply_) external onlyRole(Roles.OPERATOR_ROLE) {
        /// @dev New limit should not be lower than current total principal
        if (newMaxSupply_ < _totalPrincipal) {
            revert InvalidValue("newMaxSupply");
        }

        /// @dev New limit should not be compatible with current dust balance
        if (newMaxSupply_ - _totalPrincipal < _dustBalance) {
            revert InvalidValue("newMaxSupply");
        }

        uint128 oldMaxSupply = _maxSupply;
        _maxSupply = newMaxSupply_;

        emit MaxSupplyUpdated(oldMaxSupply, newMaxSupply_);
    }

    /// @notice Pause staking and unstaking operations
    function pause() external onlyRole(Roles.OPERATOR_ROLE) whenNotPaused {
        _pause();
    }

    /// @notice Unpause staking and unstaking operations
    function unpause() external onlyRole(Roles.OPERATOR_ROLE) whenPaused {
        _unpause();
    }

    /// @notice Method to add new assets into the basket
    /// @param newAssetInfo_ The array of new asset information to be added into the basket
    /// @dev only operator role can call this method
    /// @dev only influence future staking operations
    function addNewAssetIntoBasket(AssetInfo[] calldata newAssetInfo_) external onlyRole(Roles.OPERATOR_ROLE) {
        if (newAssetInfo_.length == 0) {
            revert InvalidValue("empty newAssetInfo");
        }
        uint64 totalWeight = 0;
        for (uint256 i = 0; i < _assetsInfoBasket.length; i++) {
            totalWeight += _assetsInfoBasket[i].weight;
        }
        for (uint256 i = 0; i < newAssetInfo_.length; i++) {
            if (newAssetInfo_[i].targetVault == address(0)) {
                revert ZeroAddress("new asset's vault");
            }
            if (newAssetInfo_[i].weight == 0 || newAssetInfo_[i].weight > PRECISION) {
                revert InvalidValue("weight of new asset in basket");
            }
            totalWeight += newAssetInfo_[i].weight;
            if (totalWeight > PRECISION) {
                revert InvalidValue("total weight of assets in basket and new assets");
            }
            if (IERC4626(newAssetInfo_[i].targetVault).asset() != UnderlyingTokenExchanger(_exchanger)._token1()) {
                revert VaultAssetNotEqualExchangerToken1(
                    IERC4626(newAssetInfo_[i].targetVault).asset(), UnderlyingTokenExchanger(_exchanger)._token1()
                );
            }
            _assetsInfoBasket.push(newAssetInfo_[i]);
        }
    }

    // Override supportsInterface to resolve conflicts
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(FixedTermToken, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function contractName() external pure returns (string memory) {
        return "FixedTermStaking";
    }

    /// @dev Internal method to read fixed-term token details
    /// @param tokenId_ The ID of the token
    /// @return principal_ The principal amount staked
    /// @return startDate_ The start date of the stake
    /// @return maturityDate_ The maturity date of the stake
    /// @notice override FixedTermToken's method
    function readFixedTermTokenDetails(uint256 tokenId_)
        internal
        view
        override(FixedTermToken)
        returns (uint128 principal_, uint64 startDate_, uint64 maturityDate_)
    {
        return (
            _tokenId_stakeInfo[tokenId_].principal,
            _tokenId_stakeInfo[tokenId_].startDate,
            _tokenId_stakeInfo[tokenId_].maturityDate
        );
    }

    /// @param totalValue_ The total value of all assets in the basket, converted to the underlying token
    function getTotalAssetValueInBasket() public view returns (uint128 totalValue_) {
        uint256 assetNumberInBasket = _assetsInfoBasket.length;
        for (uint256 i = 0; i < assetNumberInBasket; i++) {
            AssetInfo memory assetInfo = _assetsInfoBasket[i];
            totalValue_ += uint128(IERC4626(assetInfo.targetVault).maxWithdraw(address(this)));
        }
        return UnderlyingTokenExchanger(_exchanger).dryrunExchange(totalValue_, true);
    }

    /// @notice Get accumulated interest rate at a specific timestamp
    /// @param timestamp_ The timestamp to query (non-normalized)
    /// @return The accumulated interest rate at the normalized timestamp
    function getAccumulatedInterestRate(uint64 timestamp_) external view returns (int64) {
        return _accumulatedInterestRate[_normalizeTimestamp(timestamp_)];
    }

    function underlyingToken() external view returns (address) {
        return _underlyingToken;
    }

    function whitelist() external view returns (address) {
        return _whitelist;
    }

    function exchanger() external view returns (address) {
        return _exchanger;
    }

    function totalPrincipal() external view returns (uint128) {
        return _totalPrincipal;
    }

    function totalFee() external view returns (uint128) {
        return _totalFee;
    }

    function totalInterest() external view returns (int128) {
        return _totalInterest;
    }

    function remainingBalance() external view returns (uint128) {
        return _remainingBalance;
    }

    function dustBalance() external view returns (uint128) {
        return _dustBalance;
    }

    function maxSupply() external view returns (uint128) {
        return _maxSupply;
    }

    function lastFeedTime() external view returns (uint64) {
        return _lastFeedTime;
    }

    function lockPeriod() external view returns (uint64) {
        return _lockPeriod;
    }

    function stakeFeeRate() external view returns (uint64) {
        return _stakeFeeRate;
    }

    function unstakeFeeRate() external view returns (uint64) {
        return _unstakeFeeRate;
    }

    function tokenIDToStakeInfo(uint256 tokenId_) external view returns (StakeInfo memory stakeInfo_) {
        stakeInfo_ = _tokenId_stakeInfo[tokenId_];
    }

    function principalStartFrom(uint64 startDate_) external view returns (uint128) {
        return _startDate_principal[startDate_];
    }

    function principalMatureAt(uint64 maturityDate_) external view returns (uint128) {
        return _maturityDate_principal[maturityDate_];
    }

    function assetsInfoBasket() external view returns (AssetInfo[] memory) {
        return _assetsInfoBasket;
    }

    function assetInfoAt(uint256 index_) external view returns (AssetInfo memory) {
        return _assetsInfoBasket[index_];
    }

    function _normalizeTimestamp(uint64 timestamp_) internal pure returns (uint64 normalizedTimestamp_) {
        normalizedTimestamp_ = uint64(((timestamp_ + 17 hours) / 1 days) * 1 days + 7 hours);
    }

    /// @dev Internal method to calculate interest bearing principal at a specific timestamp
    /// @param timestamp_ The timestamp to calculate (normalized)
    /// @return interestBearingPrincipal_ The total interest bearing principal at the normalized timestamp
    /// @notice Interest bearing principal is defined as the total principal that has started but not yet matured at the given timestamp
    function _calculateInterestBearingPrincipal(uint64 timestamp_)
        internal
        view
        returns (uint128 interestBearingPrincipal_)
    {
        uint64 normalizedTimestamp = _normalizeTimestamp(timestamp_);
        uint256[] memory timepoints = _timepoints;
        uint256 idx = timepoints.upperBoundMemory(uint256(normalizedTimestamp));
        for (uint256 i = 0; i < idx; ++i) {
            interestBearingPrincipal_ = interestBearingPrincipal_ + _startDate_principal[uint64(timepoints[i])]
                - _maturityDate_principal[uint64(timepoints[i])];
        }
    }

    uint256[50] private __gap;
}
