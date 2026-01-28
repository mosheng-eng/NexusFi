// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";

import {Roles} from "src/common/Roles.sol";
import {UnderlyingToken} from "src/underlying/UnderlyingToken.sol";
import {FixedTermToken} from "src/protocols/lender/fixed-term/FixedTermToken.sol";
import {FixedTermStakingCore} from "src/protocols/lender/fixed-term/utils/FixedTermStakingCore.sol";
import {FixedTermStakingLibs} from "src/protocols/lender/fixed-term/utils/FixedTermStakingLibs.sol";
import {FixedTermStakingDefs} from "src/protocols/lender/fixed-term/utils/FixedTermStakingDefs.sol";

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
    using FixedTermStakingLibs for uint64;
    using FixedTermStakingLibs for address;
    using FixedTermStakingLibs for uint256[];
    using FixedTermStakingLibs for FixedTermStakingDefs.AssetInfo[];
    using FixedTermStakingCore for mapping(uint64 => int64);
    using FixedTermStakingCore for FixedTermStakingDefs.AssetInfo[];
    using FixedTermStakingCore for mapping(uint256 => FixedTermStakingDefs.StakeInfo);

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
    /// @dev tokenId => FixedTermStakingDefs.StakeInfo
    /// @notice mapping storage
    mapping(uint256 => FixedTermStakingDefs.StakeInfo) public _tokenId_stakeInfo;
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
    uint256[] internal _timepoints;
    /// @dev list of all assets in the basket
    /// @notice dynamic array storage, initialized when deploying this contract
    FixedTermStakingDefs.AssetInfo[] internal _assetsInfoBasket;

    /// @dev whitelist check modifier
    /// @param who_ The address to be checked against the whitelist
    modifier onlyWhitelisted(address who_) {
        _whitelist.onlyWhitelisted(who_);
        _;
    }

    /// @dev initialization check modifier
    modifier onlyInitialized() {
        _assetsInfoBasket.onlyInitialized(
            /**
             * address _underlyingToken,
             * address _whitelist,
             * address _exchanger,
             */
            [_underlyingToken, _whitelist, _exchanger],
            /**
             * uint64 _lockPeriod,
             * uint128 _maxSupply,
             * uint64 _lastFeedTime
             */
            [uint128(_lockPeriod), _maxSupply, uint128(_lastFeedTime)]
        );

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
        FixedTermStakingDefs.AssetInfo[] calldata assetsInfoBasket_
    ) public initializer {
        __AccessControl_init_unchained();
        __ReentrancyGuard_init_unchained();
        __Pausable_init_unchained();
        __FixedTermToken_init(name_, symbol_);

        _assetsInfoBasket.initialize(addrs_, properties_, name_, symbol_, assetsInfoBasket_);

        _underlyingToken = addrs_[1];
        _whitelist = addrs_[2];
        _exchanger = addrs_[3];
        _lockPeriod = uint64(properties_);
        _stakeFeeRate = uint64(properties_ >> 64);
        _unstakeFeeRate = uint64(properties_ >> 128);
        _lastFeedTime = (uint64(properties_ >> 192)).normalizeTimestamp();
        _dustBalance = uint128(limits_);
        _maxSupply = uint128(limits_ >> 128);
        _remainingBalance = _maxSupply;

        _grantRole(Roles.OWNER_ROLE, addrs_[0]);
        _setRoleAdmin(Roles.OPERATOR_ROLE, Roles.OWNER_ROLE);
    }

    function stake(uint128 stakeAmount_)
        external
        whenNotPaused
        nonReentrant
        onlyWhitelisted(msg.sender)
        onlyInitialized
        returns (uint256 tokenId_)
    {
        /**
         * uint128 updatedTotalPrincipal_,
         * uint128 updatedRemainingBalance_,
         * uint128 updatedTotalFee_,
         */
        (uint128[3] memory results, uint256[] memory timepoints) = _tokenId_stakeInfo.stake(
            _startDate_principal,
            _maturityDate_principal,
            _assetsInfoBasket,
            _timepoints,
            /**
             * address from_,
             * address to_,
             * address underlyingToken_,
             * address exchanger_,
             */
            [msg.sender, msg.sender, _underlyingToken, _exchanger],
            /**
             * uint128 totalPrincipal_,
             * uint128 remainingBalance_,
             * uint128 totalFee_,
             * uint128 stakeAmount_,
             * uint128 dustBalance_,
             * uint128 tokenId_,
             * uint64 stakeFeeRate_,
             * uint64 lockPeriod_,
             */
            [
                _totalPrincipal,
                _remainingBalance,
                _totalFee,
                stakeAmount_,
                _dustBalance,
                _maxSupply,
                uint128(_tokenId),
                uint128(_stakeFeeRate),
                uint128(_lockPeriod)
            ]
        );
        unchecked {
            _totalPrincipal = results[0];
            _remainingBalance = results[1];
            _totalFee = results[2];
        }

        delete _timepoints;
        _timepoints = timepoints;

        tokenId_ = mint(msg.sender);
    }

    function unstake(uint256 tokenId_)
        external
        whenNotPaused
        nonReentrant
        onlyWhitelisted(msg.sender)
        onlyInitialized
        returns (uint128 repayAmount_)
    {
        /**
         * uint128 repayAmount_,
         * uint128 updatedTotalPrincipal_,
         * uint128 updatedRemainingBalance_,
         * uint128 updatedTotalFee_,
         * int128 updatedTotalInterest_,
         */
        int256[5] memory results = _tokenId_stakeInfo.unstake(
            _accumulatedInterestRate,
            _assetsInfoBasket,
            /**
             * address from_,
             * address to_,
             * address tokenOwner_,
             * address underlyingToken_,
             * address exchanger_,
             */
            [msg.sender, msg.sender, _requireOwned(tokenId_), _underlyingToken, _exchanger],
            /**
             * uint256 tokenId_,
             * uint128 totalPrincipal_,
             * uint128 remainingBalance_,
             * uint128 totalFee_,
             * int128 totalInterest_,
             * uint64 lastFeedTime_,
             * uint64 unstakeFeeRate_,
             * uint256 maxTokenId_
             */
            [
                int256(tokenId_),
                int256(uint256(_totalPrincipal)),
                int256(uint256(_remainingBalance)),
                int256(uint256(_totalFee)),
                int256(_totalInterest),
                int256(uint256(_lastFeedTime)),
                int256(uint256(_unstakeFeeRate)),
                int256(_tokenId)
            ]
        );

        unchecked {
            _totalPrincipal = uint128(uint256(results[1]));
            _remainingBalance = uint128(uint256(results[2]));
            _totalFee = uint128(uint256(results[3]));
            _totalInterest = int128(results[4]);
        }

        burn(tokenId_);

        repayAmount_ = uint128(uint256(results[0]));
    }

    function stakeFrom(uint128 stakeAmount_, address who_)
        external
        onlyRole(Roles.OPERATOR_ROLE)
        whenNotPaused
        nonReentrant
        onlyWhitelisted(who_)
        onlyInitialized
        returns (uint256 tokenId_)
    {
        /**
         * uint128 updatedTotalPrincipal_,
         * uint128 updatedRemainingBalance_,
         * uint128 updatedTotalFee_,
         */
        (uint128[3] memory results, uint256[] memory timepoints) = _tokenId_stakeInfo.stake(
            _startDate_principal,
            _maturityDate_principal,
            _assetsInfoBasket,
            _timepoints,
            /**
             * address from_,
             * address to_,
             * address underlyingToken_,
             * address exchanger_,
             */
            [who_, who_, _underlyingToken, _exchanger],
            /**
             * uint128 totalPrincipal_,
             * uint128 remainingBalance_,
             * uint128 totalFee_,
             * uint128 stakeAmount_,
             * uint128 dustBalance_,
             * uint128 tokenId_,
             * uint64 stakeFeeRate_,
             * uint64 lockPeriod_,
             */
            [
                _totalPrincipal,
                _remainingBalance,
                _totalFee,
                stakeAmount_,
                _dustBalance,
                _maxSupply,
                uint128(_tokenId),
                uint128(_stakeFeeRate),
                uint128(_lockPeriod)
            ]
        );
        unchecked {
            _totalPrincipal = results[0];
            _remainingBalance = results[1];
            _totalFee = results[2];
        }
        delete _timepoints;
        _timepoints = timepoints;
        tokenId_ = mint(who_);
    }

    function unstakeFrom(uint256 tokenId_, address who_)
        external
        onlyRole(Roles.OPERATOR_ROLE)
        whenNotPaused
        nonReentrant
        onlyWhitelisted(who_)
        onlyInitialized
        returns (uint128 repayAmount_)
    {
        /**
         * uint128 repayAmount_,
         * uint128 updatedTotalPrincipal_,
         * uint128 updatedRemainingBalance_,
         * uint128 updatedTotalFee_,
         * int128 updatedTotalInterest_,
         */
        int256[5] memory results = _tokenId_stakeInfo.unstake(
            _accumulatedInterestRate,
            _assetsInfoBasket,
            /**
             * address from_,
             * address to_,
             * address tokenOwner_,
             * address underlyingToken_,
             * address exchanger_,
             */
            [who_, who_, _requireOwned(tokenId_), _underlyingToken, _exchanger],
            /**
             * uint256 tokenId_,
             * uint128 totalPrincipal_,
             * uint128 remainingBalance_,
             * uint128 totalFee_,
             * int128 totalInterest_,
             * uint64 lastFeedTime_,
             * uint64 unstakeFeeRate_,
             * uint256 maxTokenId_
             */
            [
                int256(tokenId_),
                int256(uint256(_totalPrincipal)),
                int256(uint256(_remainingBalance)),
                int256(uint256(_totalFee)),
                int256(_totalInterest),
                int256(uint256(_lastFeedTime)),
                int256(uint256(_unstakeFeeRate)),
                int256(_tokenId)
            ]
        );

        unchecked {
            _totalPrincipal = uint128(uint256(results[1]));
            _remainingBalance = uint128(uint256(results[2]));
            _totalFee = uint128(uint256(results[3]));
            _totalInterest = int128(results[4]);
        }

        burn(tokenId_);

        repayAmount_ = uint128(uint256(results[0]));
    }

    /// @notice any address can call this method to feed interest rate when not paused
    /// @param timestamp_ The timestamp to feed (non-normalized)
    /// @return dividends_ Whether there are dividends to distribute
    function feed(uint64 timestamp_) external whenNotPaused nonReentrant returns (bool dividends_) {
        (dividends_, _lastFeedTime, _totalInterest) = _accumulatedInterestRate.feed(
            _startDate_principal,
            _maturityDate_principal,
            _timepoints,
            timestamp_,
            false,
            _lastFeedTime,
            _totalPrincipal,
            getTotalAssetValueInBasket(),
            _totalInterest,
            _underlyingToken
        );
    }

    /// @notice only controller roles can force feeding at the same timestamp
    /// @param timestamp_ The timestamp to feed (non-normalized)
    /// @return dividends_ Whether there are dividends to distribute
    function feedForce(uint64 timestamp_)
        external
        whenNotPaused
        nonReentrant
        onlyRole(Roles.OPERATOR_ROLE)
        returns (bool dividends_)
    {
        (dividends_, _lastFeedTime, _totalInterest) = _accumulatedInterestRate.feed(
            _startDate_principal,
            _maturityDate_principal,
            _timepoints,
            timestamp_,
            true,
            _lastFeedTime,
            _totalPrincipal,
            getTotalAssetValueInBasket(),
            _totalInterest,
            _underlyingToken
        );
    }

    /// @notice Method to update staking fee rate
    /// @param newStakeFeeRate_ The new staking fee rate
    /// @dev only operator role can call this method
    /// @dev only influence future staking operations
    function updateStakeFeeRate(uint64 newStakeFeeRate_) external onlyRole(Roles.OPERATOR_ROLE) {
        if (newStakeFeeRate_ > FixedTermStakingDefs.MAX_FEE_RATE) {
            revert FixedTermStakingDefs.InvalidFeeRate(newStakeFeeRate_);
        }
        uint64 oldStakeFeeRate = _stakeFeeRate;
        _stakeFeeRate = newStakeFeeRate_;
        emit FixedTermStakingDefs.StakeFeeRateUpdated(oldStakeFeeRate, newStakeFeeRate_);
    }

    /// @notice Method to update unstaking fee rate
    /// @param newUnstakeFeeRate_ The new unstaking fee rate
    /// @dev only operator role can call this method
    /// @dev only influence future unstaking operations
    function updateUnstakeFeeRate(uint64 newUnstakeFeeRate_) external onlyRole(Roles.OPERATOR_ROLE) {
        if (newUnstakeFeeRate_ > FixedTermStakingDefs.MAX_FEE_RATE) {
            revert FixedTermStakingDefs.InvalidFeeRate(newUnstakeFeeRate_);
        }
        uint64 oldUnstakeFeeRate = _unstakeFeeRate;
        _unstakeFeeRate = newUnstakeFeeRate_;
        emit FixedTermStakingDefs.UnstakeFeeRateUpdated(oldUnstakeFeeRate, newUnstakeFeeRate_);
    }

    /// @notice Method to update the dust balance limit
    /// @param newDustBalance_ The new dust balance limit
    /// @dev only operator role can call this method
    /// @dev only influence future staking operations
    function updateDustBalance(uint128 newDustBalance_) external onlyRole(Roles.OPERATOR_ROLE) {
        /// @dev New limit should not be compatible with current remaining balance
        if (_remainingBalance < newDustBalance_) {
            revert FixedTermStakingDefs.InvalidValue("dustBalance");
        }

        uint128 oldDustBalance = _dustBalance;
        _dustBalance = newDustBalance_;

        emit FixedTermStakingDefs.DustBalanceUpdated(oldDustBalance, newDustBalance_);
    }

    /// @notice Method to update the maximum supply limit
    /// @param newMaxSupply_ The new maximum supply limit
    /// @dev only operator role can call this method
    /// @dev only influence future staking operations
    function updateMaxSupply(uint128 newMaxSupply_) external onlyRole(Roles.OPERATOR_ROLE) {
        /// @dev New limit should not be lower than current total principal
        if (newMaxSupply_ < _totalPrincipal) {
            revert FixedTermStakingDefs.InvalidValue("newMaxSupply");
        }

        /// @dev New limit should not be compatible with current dust balance
        if (newMaxSupply_ - _totalPrincipal < _dustBalance) {
            revert FixedTermStakingDefs.InvalidValue("newMaxSupply");
        }

        uint128 oldMaxSupply = _maxSupply;
        _maxSupply = newMaxSupply_;

        emit FixedTermStakingDefs.MaxSupplyUpdated(oldMaxSupply, newMaxSupply_);
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
    function addNewAssetIntoBasket(FixedTermStakingDefs.AssetInfo[] calldata newAssetInfo_)
        external
        onlyRole(Roles.OPERATOR_ROLE)
    {
        _assetsInfoBasket.addNewAssetIntoBasket(newAssetInfo_, _exchanger);
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
        totalValue_ = _assetsInfoBasket.totalAssetValueInBasket(_exchanger);
    }

    function assetsInfoBasket() external view returns (FixedTermStakingDefs.AssetInfo[] memory) {
        return _assetsInfoBasket;
    }

    uint256[50] private __gap;
}
