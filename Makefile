-include .env

abiFixedTermStaking:; forge inspect FixedTermStaking abi > abi/FixedTermStaking.abi
abiExchanger:; forge inspect UnderlyingTokenExchanger abi > abi/UnderlyingTokenExchanger.abi

coverage:; forge coverage --ir-minimum --no-match-test invariant* --ffi
coverageReport:; forge coverage --ir-minimum --no-match-coverage .[t,s].sol --no-match-test invariant* --ffi --report debug > report/coverage.txt
testNull:; forge test --match-test testNull -vvv
testStake:; forge test --match-test testStake -vvv