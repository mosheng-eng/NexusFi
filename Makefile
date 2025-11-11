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

coverage:; forge coverage --ir-minimum --no-match-test invariant* --ffi
coverageReport:; forge coverage --ir-minimum --no-match-test invariant* --ffi --report debug > report/coverage.txt
testFixedTermStaking:; forge test --match-contract FixedTermStakingTest --ffi -vvv
testOpenTermStaking:; forge test --match-contract OpenTermStakingTest --ffi -vvv
testMultisigWallet:; forge test --match-contract MultisigWalletTest --ffi -vvv
testThresholdWallet:; forge test --match-contract ThresholdWalletTest --ffi -vvv
testUnderlyingTokenExchanger:; forge test --match-contract UnderlyingTokenExchangerTest --ffi -vvv
testInvariant:; forge test --match-test invariant* --ffi -vvv
testAll:; forge test --ffi -vvv