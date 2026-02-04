// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

library OpenTermStakingDefs {
    /// @notice Event emitted when stake happens
    /// @param from the address who pay for underlying tokens
    /// @param to the address who receive the open-term staking tokens
    /// @param amount the net amount of underlying tokens staked (excluding fees)
    /// @param shares the amount of open-term staking tokens minted
    /// @param fee the fee charged for staking in underlying tokens
    event Stake(address indexed from, address indexed to, uint128 amount, uint128 shares, uint128 fee);

    /// @notice Event emitted when unstake happens
    /// @param from the address who pay for open-term staking tokens
    /// @param to the address who receive the underlying tokens
    /// @param amount the net amount of underlying tokens paid (excluding fees)
    /// @param shares the amount of open-term staking tokens burned
    /// @param fee the fee charged for unstaking in underlying tokens
    event Unstake(address indexed from, address indexed to, uint128 amount, uint128 shares, uint128 fee);

    /// @notice Event emitted when feed happens
    /// @param normalizedTimeStamp the normalized time stamp when feed happens
    /// @param interest the interest rate fed (per day, in 1e18 precision
    event Feed(uint64 indexed normalizedTimeStamp, int128 interest);

    /// @notice Event emitted when update stake fee rate
    /// @param oldFeeRate the old stake fee rate
    /// @param newFeeRate the new stake fee rate
    event StakeFeeRateUpdated(uint64 oldFeeRate, uint64 newFeeRate);

    /// @notice Event emitted when update unstake fee rate
    /// @param oldFeeRate the old unstake fee rate
    /// @param newFeeRate the new unstake fee rate
    event UnstakeFeeRateUpdated(uint64 oldFeeRate, uint64 newFeeRate);

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

    /// @notice Error reverted when the staking pool is bankrupt (total interest plus total principal is non-positive)
    error PoolBankrupt();

    /// @dev information of each asset in a basket
    /// @notice used in multi-asset basket
    struct AssetInfo {
        /// @dev the address of the asset vault, which must implement IERC4626
        address targetVault;
        /// @dev weight of the asset in the basket, in million (1_000_000 = 100%)
        uint64 weight;
    }

    /// @dev precision in million (1_000_000 = 100%)
    /// @notice constant, not stored in storage
    uint64 public constant PRECISION = 1_000_000;
    /// @dev maximum fee rate (5%)
    /// @notice constant, not stored in storage
    uint64 public constant MAX_FEE_RATE = 50_000;
}
