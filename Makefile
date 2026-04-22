-include .env

abiMultisigWallet:; forge inspect MultisigWallet abi > abi/MultiSigWallet.abi
abiThresholdWallet:; forge inspect ThresholdWallet abi > abi/ThresholdWallet.abi
abiFixedTermStaking:; forge inspect FixedTermStaking abi > abi/FixedTermStaking.abi
abiFixedTermToken:; forge inspect FixedTermToken abi > abi/FixedTermToken.abi
abiOpenTermStaking:; forge inspect OpenTermStaking abi > abi/OpenTermStaking.abi
abiOpenTermToken:; forge inspect OpenTermToken abi > abi/OpenTermToken.abi
abiUnderlyingTokenExchanger:; forge inspect UnderlyingTokenExchanger abi > abi/UnderlyingTokenExchanger.abi
abiUnderlyingToken:; forge inspect UnderlyingToken abi > abi/UnderlyingToken.abi
abiWhitelist:; forge inspect Whitelist abi > abi/Whitelist.abi
abiBlacklist:; forge inspect Blacklist abi > abi/Blacklist.abi
abiTimePowerLoan:; forge inspect TimePowerLoan abi > abi/TimePowerLoan.abi
abiTimeLinearLoan:; forge inspect TimeLinearLoan abi > abi/TimeLinearLoan.abi
abiValueInflationVault:; forge inspect ValueInflationVault abi > abi/ValueInflationVault.abi

coverage:; forge coverage --ir-minimum --no-match-test invariant* --no-match-contract Temp*  --ffi
coverageReport:; forge coverage --ir-minimum --no-match-test invariant* --no-match-contract Temp* --ffi --report debug > report/coverage.txt
testMultisigWallet:; forge test --match-contract MultisigWalletTest --ffi --via-ir --optimize -vvv
testThresholdWallet:; forge test --match-contract ThresholdWalletTest --ffi --via-ir --optimize -vvv
testFixedTermStaking:; forge test --match-contract FixedTermStakingTest --ffi --via-ir --optimize -vvv
testOpenTermStaking:; forge test --match-contract OpenTermStakingTest --ffi --via-ir --optimize -vvv
testUnderlyingTokenExchanger:; forge test --match-contract UnderlyingTokenExchangerTest --ffi --via-ir --optimize -vvv
testWhitelist:; forge test --match-contract WhitelistTest --ffi --via-ir --optimize -vvv
testBlacklist:; forge test --match-contract BlacklistTest --ffi --via-ir --optimize -vvv
testTimePowerLoan:; forge test --match-contract TimePowerLoanTest --ffi --via-ir --optimize -vvv
testTimeLinearLoan:; forge test --match-contract TimeLinearLoanTest --ffi --via-ir --optimize -vvv
testValueInflationVault:; forge test --match-contract ValueInflationVaultTest --ffi --via-ir --optimize -vvv
testInvariant:; forge test --match-test invariant --ffi --via-ir --optimize -vvv
testAll:; forge test --ffi --via-ir --optimize -vvv