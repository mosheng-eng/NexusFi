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
testMultisigWallet:; forge test --match-contract MultisigWalletTest --ffi -vvv
testThresholdWallet:; forge test --match-contract ThresholdWalletTest --ffi -vvv
testFixedTermStaking:; forge test --match-contract FixedTermStakingTest --ffi -vvv
testOpenTermStaking:; forge test --match-contract OpenTermStakingTest --ffi -vvv
testUnderlyingTokenExchanger:; forge test --match-contract UnderlyingTokenExchangerTest --ffi -vvv
testWhitelist:; forge test --match-contract WhitelistTest --ffi -vvv
testBlacklist:; forge test --match-contract BlacklistTest --ffi -vvv
testTimePowerLoan:; forge test --match-contract TimePowerLoanTest --ffi -vvv
testTimeLinearLoan:; forge test --match-contract TimeLinearLoanTest --ffi -vvv
testValueInflationVault:; forge test --match-contract ValueInflationVaultTest --ffi -vvv
testInvariant:; forge test --match-test invariant* --ffi -vvv
testAll:; forge test --ffi -vvv