# NexusFi Protocol
## Overview
![Protocol Overview](doc/ProtocolOverview.png "Protocol Overview")
### Lender Entity
* **Apple Lender Co :** a lender company
  * **Staff:**
    * **Alice:** a signer holding private key
    * **Brain:** a signer holding private key
    * **Clark:** a signer holding private key
  * **Wallet:**
    * **Multisig:** 3 signers in total and 1 aggregated signature from all signers required
* **Grape Invest Co :** an investment company
  * **Staff:**
    * **David:** a signer holding private key and onchain id
    * **Frank:** a signer holding private key and onchain id
    * **Emily:** a signer holding private key and onchain id
  * **Wallet:**
    * **Threshold:** 3 signers in total and 1 aggregated signature from at least 2 signers required
### Personal Borrower
* **Bob :** a borrower who prefer long term fund
* **Mos :** a borrower who prefer short term fund
### Contracts
* **[MultisigWallet](https://github.com/mosheng-eng/NexusFi/blob/master/src/multisig/MultisigWallet.sol)**  
  This is a n - n wallet where n means the total signers. Multisig wallet contract holds an aggregated public key built from all signers' public keys. Multisig wallet contract is built on BLS algorithm and support two modes:   
  * **Public key on G1 and Private key on G2 :**  
  Public key is a point on G1 which has two coordinates. Each coordinate is 48 bytes (uint384) stored in two words (bytes32).  
  Signature is a point on G2 which has two complex coordinates. Each complex coordinate consists of a real part and imaginary part. Both real part and imaginary part are 48 bytes (uint384) stored in two words (bytes32).  
  * **Public key on G2 and Private key on G1 :**  
  Public key is a point on G2 which has two complex coordinates. Each complex coordinate consists of a real part and imaginary part. Both real part and imaginary part are 48 bytes (uint384) stored in two words (bytes32).  
  Signature is a point on G1 which has two coordinates. Each coordinate is 48 bytes (uint384) stored in two words (bytes32).  
  The following two pictures show **the prototype design of multisig wallet**:  
  ![Prototype Design](doc/MultisigWallet-When-PKs-on-G1.png "Public Key On G1")
  ![Prototype Design](doc/MultisigWallet-When-PKs-on-G2.png "Public Key On G2")
  > Note: EVM version should be Prague or later. Because BLS algorithm in Multisig Wallet contract depends on precompiled contracts:  
  > 1. 0x0b BLS12_G1ADD
  > 2. 0x0c BLS12_G1MSM
  > 3. 0x0d BLS12_G2ADD
  > 4. 0x0e BLS12_G2MSM
  > 5. 0x0f BLS12_PAIRING_CHECK
  > 6. 0x10 BLS12_MAP_FP_TO_G1
  > 7. 0x11 BLS12_MAP_FP2_TO_G2
* **[ThresholdWallet](https://github.com/mosheng-eng/NexusFi/blob/master/src/multisig/ThresholdWallet.sol)**  
  This is a m - n wallet where n means the total signers and m means the minimum signers required (the threshold). Threshold wallet contract holds all signers' public keys and onchain memory ids. Each signer's member id is signed by all signers. In other words, each signer’s membership is agreed upon by all participants through consensus. Multisig wallet contract is built on BLS algorithm and support two modes:
  * **Public key on G1 and Private key on G2 :**  
  Public key is a point on G1 which has two coordinates. Each coordinate is 48 bytes (uint384) stored in two words (bytes32).  
  Signature and onchain member id are points on G2 which has two complex coordinates. Each complex coordinate consists of a real part and imaginary part. Both real part and imaginary part are 48 bytes (uint384) stored in two words (bytes32).  
  * **Public key on G2 and Private key on G1 :**  
  Public key is a point on G2 which has two complex coordinates. Each complex coordinate consists of a real part and imaginary part. Both real part and imaginary part are 48 bytes (uint384) stored in two words (bytes32).  
  Signature and onchain member id are points on G1 which has two coordinates. Each coordinate is 48 bytes (uint384) stored in two words (bytes32).  
  The following two pictures show **the prototype design of threshold wallet**:  
  ![Prototype Design](doc/ThresholdWallet-When-PKs-on-G1.png "Public Key On G1")
  ![Prototype Design](doc/ThresholdWallet-When-PKs-on-G2.png "Public Key On G2")
  > Note: EVM version should be Prague or later. Because BLS algorithm in Threshold Wallet contract depends on precompiled contracts:  
  > 1. 0x0b BLS12_G1ADD
  > 2. 0x0c BLS12_G1MSM
  > 3. 0x0d BLS12_G2ADD
  > 4. 0x0e BLS12_G2MSM
  > 5. 0x0f BLS12_PAIRING_CHECK
  > 6. 0x10 BLS12_MAP_FP_TO_G1
  > 7. 0x11 BLS12_MAP_FP2_TO_G2
* **[UnderlyingToken](https://github.com/mosheng-eng/NexusFi/blob/master/src/underlying/UnderlyingToken.sol)**  
  This is a ERC20 token that is used for circulation inside protocol (e.g. referred to as nfiUSD). Each participant should hold nfiUSD for different purposes. For example, lender should earn interest by staking nfiUSD into fixed term or open term staking protocols. All accepted assets by NexusFi protocol, such as USDC or USDT, can be used to exchange for nfiUSD.
* **[UnderlyingTokenExchanger](https://github.com/mosheng-eng/NexusFi/blob/master/src/underlying/UnderlyingTokenExchanger.sol)**  
  This is an exchanger between underlying asset (e.g. USDC or USDT) and underlying token (e.g. nfiUSD). But this is not an AMM protocol that DEX oftern used. Maybe it can be in the future but not now. It usually has a fixed rate between underlying asset and underlying token.  
  We are planning to build an oracle to support unstable coin asset.
* **[FixedTermStaking](https://github.com/mosheng-eng/NexusFi/blob/master/src/protocols/lender/fixed-term/FixedTermStaking.sol)**  
  Fixed term staking protocol is used for a long term investment, such as 30 or 180 or 360 days. It is suitable for professional investors who have much idle fund and are willing to stick to gain high yeilds.  
  Investors will get NFT tokens (e.g. referred to as nfiFTT) as receipts after they stake nfiUSD. Each nfiFTT token is unique because of the different start date, maturity date and principal.  
  Fixed term staking contract stores daily accumulated interest rates for calculation of any nfiFTT token's interest amount at any day before or at or after maturity date. Daily accumulated interest rates make on-chain interest calculations more efficient.  
  The following picture shows **the basic mathematical formula**.
  ![FixedTermStaking](doc/FixedTermStaking.png "Fixed Term Staking")
* **[FixedTermToken](https://github.com/mosheng-eng/NexusFi/blob/master/src/protocols/lender/fixed-term/FixedTermToken.sol)**  
  This is a ERC721 token that is used to represent a fixed term staking (e.g. referred to as nfiFTT). Investor will get a specific token id of nfiFTT after stake nfiUSD into fixed term staking protocol. Each nfiFTT token is unique because of the different start date, maturity date and principal.  
  We know that NFT is not friendly to DeFi or vault protocol. So we are working on the wrapper functions of nfiFTT and will upgrade protocol soon.
* **[OpenTermStaking](https://github.com/mosheng-eng/NexusFi/blob/master/src/protocols/lender/open-term/OpenTermStaking.sol)**  
  Open term staking protocol is used for a short term investment, such as overnight stake and unstake. It is suitable for individual investors who have small and distributed fund and prefer to speculate.
  Investors will get ERC20 tokens (e.g. referred to as nfiOTT) as receipts after they stake nfiUSD. All nfiOTT tokens are rebasing token and investors can see the growth of balance in their self-hosted wallet after the oracle feed interest to protocol.
  Open term staking contract stores total supply of nfiOTT and total reserve of nfiUSD (sum of all principal and interest). It works similarly to a vault (ERC4626) but accompanied with an oracle to distribute interest.
* **[OpenTermToken](https://github.com/mosheng-eng/NexusFi/blob/master/src/protocols/lender/open-term/OpenTermToken.sol)**  
  This is a ERC20 token that is used to represent shares of open term staking protocol. All nfiOTT tokens are rebasing token and investors can see the growth of balance in their self-hosted wallet after the oracle feed interest to protocol.
* **[ValueInflationVault](https://github.com/mosheng-eng/NexusFi/blob/master/src/vault/ValueInflationVault.sol)**  
  This is a vault following to ERC4626 standard. It's a bridge between lender protocols (FixedTermStaking & OpenTermStaking) and borrower protocols (TimeLinearLoan & TimePowerLoan). Value inflation vault collects fund from lender protocols and release funds to borrower protocols on demands. Vice versa, value inflation vault earns profits from borrower protocols and distributes bonus to lender protocols. The fund strategy of value inflation vault can be smartly modified during the lifetime of protocol.
  The following picture shows **the relationship among ValueInflationVault, FixedTermStaking, OpenTermStaking, TimeLinearLoan and TimePowerLoan**.
  ![Key Protocols Relationship](doc/ValueInflationVault.png "Key Protocols Relationship")
* **[TimeLinearLoan](https://github.com/mosheng-eng/NexusFi/blob/master/src/protocols/borrower/time-linear/TimeLinearLoan.sol)**  
  Time linear loan protocol is used for a long term loan because the interest is linearly increasing during time passing. Comparing to time power loan protocol, you will pay less interest amount in the same annual interest rate, repayment strategy and more than one year loan period.  
  Borrowers should request a loan first and borrow from the loan after approved. Borrowers will receive underlying assets, such as USDC or USDT, which are offered from one or multi value inflation vaults. These vaults own some tranches of net asset value from borrowers' debts and earn profits when borrowers repay.
* **[TimePowerLoan](https://github.com/mosheng-eng/NexusFi/blob/master/src/protocols/borrower/time-power/TimePowerLoan.sol)**  
  Time power loan protocol is used for a short term loan because the interest is exponentially increasing during time passing. It's uneconomic for borrowers when they borrow a long term loan, especially over one year if we use annual interest rates.  
  Borrowers should request a loan first and borrow from the loan after approved. Borrowers will receive underlying assets, such as USDC or USDT, which are offered from one or multi value inflation vaults. These vaults own some tranches of net asset value from borrowers' debts and earn profits when borrowers repay.
  ![TimeLinear&PowerLoan](doc/TimeLinear&PowerLoan.png "TimeLinear&PowerLoan")
* **[Whitelist](https://github.com/mosheng-eng/NexusFi/blob/master/src/whitelist/Whitelist.sol)**  
  Shared whitelist controller for the  whole protocol.
* **[Blacklist](https://github.com/mosheng-eng/NexusFi/blob/master/src/blacklist/Blacklist.sol)**  
  Shared blacklist  controller for the whole protocol.

## Usage

### Build

You can run this command to **build all contracts**.
```shell
$ forge build
```

### Test

You can run these commands to test each contract.  
Some contracts may cost thousand seconds because they contains fuzz test cases.  
```shell
$ make testMultisigWallet
$ make testThresholdWallet
$ make testFixedTermStaking
$ make testOpenTermStaking
$ make testUnderlyingTokenExchanger
$ make testWhitelist
$ make testBlacklist
$ make testTimePowerLoan
$ make testTimeLinearLoan
$ make testValueInflationVault
```

You can run this command to do all invariant test cases in all contracts.  
This test may fail because the conditions are different in each time you trigger it.  
But it works well in most times based on the past experiences.  
Invariant test cases cost a very long time to get result (maybe hours).
```
$ make testInvariant
```

You can run this command to run all test cases of all contracts, including normal test cases, fuzz test cases and invariant test cases.
```
$ make testAll
```

You can run these commands to generate coverage rate and report.  
Coverage report is located in **[report](https://github.com/mosheng-eng/NexusFi/blob/master/report/coverage.txt)** directory.
```
$ make coverage
$ make coverageReport
```
This is the latest coverage report (you can use **make coverage** to get latest report).  
Just focus on solidity files under **[src](https://github.com/mosheng-eng/NexusFi/tree/master/src)** directory.  
We have tried our best to increase the coverage rate and will continue to work on it.
![Coverage Report](doc/CoverageReport-20250120.png "Latest Coverage Report")

### Deploy
#### Local Network
1. start local network  
```
$ anvil --fork-url https://api.zan.top/node/v1/eth/mainnet/Your-API-Key --disable-code-size-limit --hardfork prague
```
2. config **[.env](https://github.com/mosheng-eng/NexusFi/blob/master/.env)** file
```
$ export NEXUSFI_OWNER=0xF265639351621C68867d089d95c14a1f0edBfB48 # replace with your own address
$ export NEXUSFI_UNDERLYING_TOKEN_NAME="NexusFi USD" # replace with your own token name
$ export NEXUSFI_UNDERLYING_TOKEN_SYMBOL="nfiUSD" # replace with your own token symbol
$ export NEXUSFI_ENABLE_WHITELIST=true # set to false to disable whitelist
$ export NEXUSFI_ENABLE_BLACKLIST=true # set to false to disable blacklist
$ export NEXUSFI_UNDERLYING_ASSET=0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 # USDC 
$ export NEXUSFI_VAULT_1_NAME="NexusFi RWA Vault" # replace with your own vault name
$ export NEXUSFI_VAULT_1_SYMBOL="nfiRWA" # replace with your own vault symbol
$ export NEXUSFI_VAULT_1_MINIMUM_PERCENTAGE_IN_A_LOAN=300000 # 30% (6 decimals)
$ export NEXUSFI_VAULT_1_MAXIMUM_PERCENTAGE_IN_A_LOAN=600000 # 60% (6 decimals)
$ export NEXUSFI_VAULT_1_WEIGHT_IN_A_STAKE=50000 # 50% (6 decimals)
$ export NEXUSFI_VAULT_2_NAME="NexusFi MMF Vault" # replace with your own vault name
$ export NEXUSFI_VAULT_2_SYMBOL="nfiMMF" # replace with your own vault symbol
$ export NEXUSFI_VAULT_2_MINIMUM_PERCENTAGE_IN_A_LOAN=400000 # 40% (6 decimals)
$ export NEXUSFI_VAULT_2_MAXIMUM_PERCENTAGE_IN_A_LOAN=700000 # 70% (6 decimals)
$ export NEXUSFI_VAULT_2_WEIGHT_IN_A_STAKE=50000 # 50% (6 decimals)
$ export NEXUSFI_TIME_POWER_LOAN_ALLOWANCE=1000000000000000 # 1 billion USDC (6 decimals)
$ export NEXUSFI_TIME_LINEAR_LOAN_ALLOWANCE=2000000000000000 # 2 billion USDC (6 decimals)
$ export NEXUSFI_TIME_POWER_LOAN_INTEREST_RATES=1000000000937300000,1000000002732680000,1000000004431820000,1000000006044530000 # 3%, 9%, 15%, 21% APR FIXED18
$ export NEXUSFI_TIME_LINEAR_LOAN_INTEREST_RATES=951293760,2853881279,4756468798,6659056317 # 3%, 9%, 15%, 21% APR FIXED18
$ export NEXUSFI_FIXED_TERM_LOCK_PERIOD=365 # days
$ export NEXUSFI_FIXED_TERM_STAKE_FEE_RATE=1000 # 0.1%
$ export NEXUSFI_FIXED_TERM_UNSTAKE_FEE_RATE=1000 # 0.1%
$ export NEXUSFI_FIXED_TERM_START_FEED_TIME=1759301999 # 2025-10-01 14:59:59 UTC+8
$ export NEXUSFI_FIXED_TERM_DUST_BALANCE=1000000000 # 1,000 USDC (6 decimals)
$ export NEXUSFI_FIXED_TERM_MAX_SUPPLY=1000000000000000 # 1 billion underlying tokens (6 decimals)
$ export NEXUSFI_FIXED_TERM_TOKEN_NAME="NexusFi Fixed Term Token" # replace with your own token name
$ export NEXUSFI_FIXED_TERM_TOKEN_SYMBOL="nfiFTT" # replace with your own token symbol
$ export NEXUSFI_OPEN_TERM_STAKE_FEE_RATE=1000 # 0.1%
$ export NEXUSFI_OPEN_TERM_UNSTAKE_FEE_RATE=1000 # 0.1%
$ export NEXUSFI_OPEN_TERM_START_FEED_TIME=1759301999 # 2025-10-01 14:59:59 UTC+8
$ export NEXUSFI_OPEN_TERM_DUST_BALANCE=1000000000 # 1,000 USDC (6 decimals)
$ export NEXUSFI_OPEN_TERM_MAX_SUPPLY=1000000000000000 # 1 billion underlying tokens (6 decimals)
$ export NEXUSFI_OPEN_TERM_TOKEN_NAME="NexusFi Open Term Token" # replace with your own token name
$ export NEXUSFI_OPEN_TERM_TOKEN_SYMBOL="nfiOTT" # replace with your own token symbol
$ export NEXUSFI_MULTISIG_WALLET_PK_ON_G=1 # set to 1 for PUBLIC_KEY_ON_G1, 2 for PUBLIC_KEY_ON_G2
$ export NEXUSFI_MULTISIG_WALLET_PUBLIC_KEY=0x0000000000000000000000000000000008a582ebbbb02e16a25937515dbdaa4b3923c1da08efc4bc7166beb8960e650e6cf50797293e3ee314fbb5b768167663000000000000000000000000000000000fcd3f839507df1fd035e1a3158e2001e30f9091e1ae3711717e15fd0af6ce0697b52c03c39fe1bf88dafbfe7a02bb61 # replace with your own aggregated public key
$ export NEXUSFI_THRESHOLD_WALLET_PK_ON_G=2 # set to 1 for PUBLIC_KEY_ON_G1, 2 for PUBLIC_KEY_ON_G2
$ export NEXUSFI_THRESHOLD_WALLET_PUBLIC_KEYS=0x000000000000000000000000000000000e66653e8d970484318957e1a2aa0600369db04de526863582ca3a0359392338ab2f4c698797cf913b839999d0b204c4000000000000000000000000000000000c42dfce7fbf9fb3e7f137854829e25a3e71bebd7e339f71539e6b98b8b8cfef7a7399517e308aec1b10401a150d97dd00000000000000000000000000000000112bd209171ef4715c17240ba4820023885c24585c352c2a8d69c84abb2a6cbf2e0fbbde51a6b10c023bdb1d3fc67e9700000000000000000000000000000000087334853998796b65601176e24cc3f439f136c706d623d781356ceddb584540a2c3f32628f2cfa01caa1cc39682ed70,0x00000000000000000000000000000000020d7314fcb279e9807d6e113d939b50e582152a9cab9d3535298af70adc0f374fd657ae7a1d0270bb761b595b99868d0000000000000000000000000000000017ebb3ef4991c6a95a25ed52502cbd441db40c78f68c732ef25b7c65400aaf88f952a218c84cc27d3ebb8d40e853e6190000000000000000000000000000000019089dea96a95fa1bbe60ca41d8fb123e8538d9522252c08d12907980655cab0ddcec75e8a73d3a07d74d1362310af1100000000000000000000000000000000054d606b04144a8837ac6e403791a34b4820366beb539ba919c7a081d0b1b5fe06adbbe5b4252089fe9ab71ca8cd8222,0x00000000000000000000000000000000053d46730cbbf7c4bb257068ab6951e1fa651092f1783afb9123e357b9e03b38d72fb2a653608a48281f6dc6d3a9001f0000000000000000000000000000000008bd0d5644986653041a89fb1e0a6d00624d6f786b642ab530eb7a6111c7b3f4300c3606ee74c66c8fc13160486f0583000000000000000000000000000000000768c9dc5f031e7034eb601071c5837a1d410f09573fc78727d6dca3732c6a009c8883da1b5b11060bb674e20c878245000000000000000000000000000000001348ab206da3e7e631e7e961167347fb23949d1e05ab42a746d124ffd6f15473611c2fd05e3ea138025a7b49c048916c # replace with your own public keys
$ export NEXUSFI_THRESHOLD_WALLET_MEMBER_IDS=0x000000000000000000000000000000000d7636e4b84c309cfb0f928c6af91af95c12b97de8f722d7382966ff561f62fbd027eda3e5b15ba533238b628fa747a20000000000000000000000000000000001c4e1712b4ed71b14e7efb7ab738201138910289abc3594b6b3dc49b92d013f9e670ba370c9fc2dad368315d90a4eba,0x000000000000000000000000000000000cbf9f328f92db7cb326d2e59dfa27880a2361f1fcd52a39964debf305ed44c2370df0523032904cf7a9d96d1fe42a7100000000000000000000000000000000196433ba2768ffb360db3d9e3352bd97e73c8c7af3f6add9db344dc460d3f98140d21aca316ffb13fe84e69fb3391c54,0x000000000000000000000000000000000f0b3db7418e50a882828457a6ef7a7e83bf38ac5fc6e5165ee13ddd0d17cde37fc40dad83782a428485d5e0a0031ef200000000000000000000000000000000107c2e484318e669452dc5fefaf851584619f3e3f5b94e99bb96fd1381f711ccae7ba4f11d4a0b0b3acf78904c68a36c # replace with your own member ids
$ export NEXUSFI_THRESHOLD_WALLET_N=3 # m-n parameters
$ export NEXUSFI_THRESHOLD_WALLET_M=2 # m-n parameters
```
3. run deployment script
```
$ forge script script/DeployContractSuit.s.sol:DeployContractSuit --via-ir --rpc-url http://localhost:8545 --broadcast --interactives 1 --optimize  
```
4. input owner's private key
```
[⠊] Compiling...
No files changed, compilation skipped
Enter private key:
```
#### Test Network
1. config **[.env](https://github.com/mosheng-eng/NexusFi/blob/master/.env)** file
```
$ export NEXUSFI_OWNER=0xF265639351621C68867d089d95c14a1f0edBfB48 # replace with your own address
$ export NEXUSFI_UNDERLYING_TOKEN_NAME="NexusFi USD" # replace with your own token name
$ export NEXUSFI_UNDERLYING_TOKEN_SYMBOL="nfiUSD" # replace with your own token symbol
$ export NEXUSFI_ENABLE_WHITELIST=true # set to false to disable whitelist
$ export NEXUSFI_ENABLE_BLACKLIST=true # set to false to disable blacklist
$ export NEXUSFI_UNDERLYING_ASSET=0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 # USDC 
$ export NEXUSFI_VAULT_1_NAME="NexusFi RWA Vault" # replace with your own vault name
$ export NEXUSFI_VAULT_1_SYMBOL="nfiRWA" # replace with your own vault symbol
$ export NEXUSFI_VAULT_1_MINIMUM_PERCENTAGE_IN_A_LOAN=300000 # 30% (6 decimals)
$ export NEXUSFI_VAULT_1_MAXIMUM_PERCENTAGE_IN_A_LOAN=600000 # 60% (6 decimals)
$ export NEXUSFI_VAULT_1_WEIGHT_IN_A_STAKE=50000 # 50% (6 decimals)
$ export NEXUSFI_VAULT_2_NAME="NexusFi MMF Vault" # replace with your own vault name
$ export NEXUSFI_VAULT_2_SYMBOL="nfiMMF" # replace with your own vault symbol
$ export NEXUSFI_VAULT_2_MINIMUM_PERCENTAGE_IN_A_LOAN=400000 # 40% (6 decimals)
$ export NEXUSFI_VAULT_2_MAXIMUM_PERCENTAGE_IN_A_LOAN=700000 # 70% (6 decimals)
$ export NEXUSFI_VAULT_2_WEIGHT_IN_A_STAKE=50000 # 50% (6 decimals)
$ export NEXUSFI_TIME_POWER_LOAN_ALLOWANCE=1000000000000000 # 1 billion USDC (6 decimals)
$ export NEXUSFI_TIME_LINEAR_LOAN_ALLOWANCE=2000000000000000 # 2 billion USDC (6 decimals)
$ export NEXUSFI_TIME_POWER_LOAN_INTEREST_RATES=1000000000937300000,1000000002732680000,1000000004431820000,1000000006044530000 # 3%, 9%, 15%, 21% APR FIXED18
$ export NEXUSFI_TIME_LINEAR_LOAN_INTEREST_RATES=951293760,2853881279,4756468798,6659056317 # 3%, 9%, 15%, 21% APR FIXED18
$ export NEXUSFI_FIXED_TERM_LOCK_PERIOD=365 # days
$ export NEXUSFI_FIXED_TERM_STAKE_FEE_RATE=1000 # 0.1%
$ export NEXUSFI_FIXED_TERM_UNSTAKE_FEE_RATE=1000 # 0.1%
$ export NEXUSFI_FIXED_TERM_START_FEED_TIME=1759301999 # 2025-10-01 14:59:59 UTC+8
$ export NEXUSFI_FIXED_TERM_DUST_BALANCE=1000000000 # 1,000 USDC (6 decimals)
$ export NEXUSFI_FIXED_TERM_MAX_SUPPLY=1000000000000000 # 1 billion underlying tokens (6 decimals)
$ export NEXUSFI_FIXED_TERM_TOKEN_NAME="NexusFi Fixed Term Token" # replace with your own token name
$ export NEXUSFI_FIXED_TERM_TOKEN_SYMBOL="nfiFTT" # replace with your own token symbol
$ export NEXUSFI_OPEN_TERM_STAKE_FEE_RATE=1000 # 0.1%
$ export NEXUSFI_OPEN_TERM_UNSTAKE_FEE_RATE=1000 # 0.1%
$ export NEXUSFI_OPEN_TERM_START_FEED_TIME=1759301999 # 2025-10-01 14:59:59 UTC+8
$ export NEXUSFI_OPEN_TERM_DUST_BALANCE=1000000000 # 1,000 USDC (6 decimals)
$ export NEXUSFI_OPEN_TERM_MAX_SUPPLY=1000000000000000 # 1 billion underlying tokens (6 decimals)
$ export NEXUSFI_OPEN_TERM_TOKEN_NAME="NexusFi Open Term Token" # replace with your own token name
$ export NEXUSFI_OPEN_TERM_TOKEN_SYMBOL="nfiOTT" # replace with your own token symbol
$ export NEXUSFI_MULTISIG_WALLET_PK_ON_G=1 # set to 1 for PUBLIC_KEY_ON_G1, 2 for PUBLIC_KEY_ON_G2
$ export NEXUSFI_MULTISIG_WALLET_PUBLIC_KEY=0x0000000000000000000000000000000008a582ebbbb02e16a25937515dbdaa4b3923c1da08efc4bc7166beb8960e650e6cf50797293e3ee314fbb5b768167663000000000000000000000000000000000fcd3f839507df1fd035e1a3158e2001e30f9091e1ae3711717e15fd0af6ce0697b52c03c39fe1bf88dafbfe7a02bb61 # replace with your own aggregated public key
$ export NEXUSFI_THRESHOLD_WALLET_PK_ON_G=2 # set to 1 for PUBLIC_KEY_ON_G1, 2 for PUBLIC_KEY_ON_G2
$ export NEXUSFI_THRESHOLD_WALLET_PUBLIC_KEYS=0x000000000000000000000000000000000e66653e8d970484318957e1a2aa0600369db04de526863582ca3a0359392338ab2f4c698797cf913b839999d0b204c4000000000000000000000000000000000c42dfce7fbf9fb3e7f137854829e25a3e71bebd7e339f71539e6b98b8b8cfef7a7399517e308aec1b10401a150d97dd00000000000000000000000000000000112bd209171ef4715c17240ba4820023885c24585c352c2a8d69c84abb2a6cbf2e0fbbde51a6b10c023bdb1d3fc67e9700000000000000000000000000000000087334853998796b65601176e24cc3f439f136c706d623d781356ceddb584540a2c3f32628f2cfa01caa1cc39682ed70,0x00000000000000000000000000000000020d7314fcb279e9807d6e113d939b50e582152a9cab9d3535298af70adc0f374fd657ae7a1d0270bb761b595b99868d0000000000000000000000000000000017ebb3ef4991c6a95a25ed52502cbd441db40c78f68c732ef25b7c65400aaf88f952a218c84cc27d3ebb8d40e853e6190000000000000000000000000000000019089dea96a95fa1bbe60ca41d8fb123e8538d9522252c08d12907980655cab0ddcec75e8a73d3a07d74d1362310af1100000000000000000000000000000000054d606b04144a8837ac6e403791a34b4820366beb539ba919c7a081d0b1b5fe06adbbe5b4252089fe9ab71ca8cd8222,0x00000000000000000000000000000000053d46730cbbf7c4bb257068ab6951e1fa651092f1783afb9123e357b9e03b38d72fb2a653608a48281f6dc6d3a9001f0000000000000000000000000000000008bd0d5644986653041a89fb1e0a6d00624d6f786b642ab530eb7a6111c7b3f4300c3606ee74c66c8fc13160486f0583000000000000000000000000000000000768c9dc5f031e7034eb601071c5837a1d410f09573fc78727d6dca3732c6a009c8883da1b5b11060bb674e20c878245000000000000000000000000000000001348ab206da3e7e631e7e961167347fb23949d1e05ab42a746d124ffd6f15473611c2fd05e3ea138025a7b49c048916c # replace with your own public keys
$ export NEXUSFI_THRESHOLD_WALLET_MEMBER_IDS=0x000000000000000000000000000000000d7636e4b84c309cfb0f928c6af91af95c12b97de8f722d7382966ff561f62fbd027eda3e5b15ba533238b628fa747a20000000000000000000000000000000001c4e1712b4ed71b14e7efb7ab738201138910289abc3594b6b3dc49b92d013f9e670ba370c9fc2dad368315d90a4eba,0x000000000000000000000000000000000cbf9f328f92db7cb326d2e59dfa27880a2361f1fcd52a39964debf305ed44c2370df0523032904cf7a9d96d1fe42a7100000000000000000000000000000000196433ba2768ffb360db3d9e3352bd97e73c8c7af3f6add9db344dc460d3f98140d21aca316ffb13fe84e69fb3391c54,0x000000000000000000000000000000000f0b3db7418e50a882828457a6ef7a7e83bf38ac5fc6e5165ee13ddd0d17cde37fc40dad83782a428485d5e0a0031ef200000000000000000000000000000000107c2e484318e669452dc5fefaf851584619f3e3f5b94e99bb96fd1381f711ccae7ba4f11d4a0b0b3acf78904c68a36c # replace with your own member ids
$ export NEXUSFI_THRESHOLD_WALLET_N=3 # m-n parameters
$ export NEXUSFI_THRESHOLD_WALLET_M=2 # m-n parameters
```
2. run deployment script
```
$ forge script script/DeployContractSuite.s.sol:DeployContractSuite --via-ir --rpc-url https://api.zan.top/node/v1/eth/sepolia/YourAPIKey --broadcast --interactives 1 --optimize  
```
If you don't have an API key, you can visit **[ZAN](https://zan.top)** and get a free one.  
If you want to verify your contracts while deploying process, you can run the following script.
```
forge script script/DeployContractSuite.s.sol:DeployContractSuite --via-ir --rpc-url https://api.zan.top/node/v1/eth/sepolia/YourAPIKey --broadcast --interactives 1 --optimize --verify --etherscan-api-key YourEtherscanAPIKey  
```
If you don't have an etherscan API key, you can visit **[Etherscan](https://etherscan.io/apidashboard)** and get a free one.  
3. Following are test contracts already deployed on sepolia network.
  * Whitelist Logic	                      
    **[0x315E84B57D8c62e34e6c0839dD90b981027cE112](https://sepolia.etherscan.io/address/0x315e84b57d8c62e34e6c0839dd90b981027ce112)**	
  * Whitelist Proxy	                      
    **[0xB076e0cDD01833D3E17fD3399137F2636601e294](https://sepolia.etherscan.io/address/0xb076e0cdd01833d3e17fd3399137f2636601e294)**		
  * Whitelist Proxy Admin	                
    **[0x9c6619946815A02C2D958A3839Df06Fb57400e23](https://sepolia.etherscan.io/address/0x9c6619946815a02c2d958a3839df06fb57400e23)**		
  * Blacklist Logic	                      
    **[0x94A3388a2FC1af8F6896436D51EF0b9D40D11fff](https://sepolia.etherscan.io/address/0x94a3388a2fc1af8f6896436d51ef0b9d40d11fff)**		
  * Blacklist Proxy	                      
    **[0x9d160E956D15cFA1BfA4AD10FcE02e7dc3ADae7d](https://sepolia.etherscan.io/address/0x9d160e956d15cfa1bfa4ad10fce02e7dc3adae7d)**		
  * Blacklist Proxy Admin	                
    **[0x6ef6398820d3D96150ED1Caf8ecA8e1838Be4d22](https://sepolia.etherscan.io/address/0x6ef6398820d3d96150ed1caf8eca8e1838be4d22)**		
  * UnderlyingToken Logic	                
    **[0x8B6161502f587A2e2E3FB8f6ce152C579d7282cF](https://sepolia.etherscan.io/address/0x8b6161502f587a2e2e3fb8f6ce152c579d7282cf)**		
  * UnderlyingToken Proxy	                
    **[0xC1745Aa2a1Bdf61F81a0935aF7416442f979dd36](https://sepolia.etherscan.io/token/0xc1745aa2a1bdf61f81a0935af7416442f979dd36)**		
  * UnderlyingToken Proxy Admin	          
    **[0xdb442DefcC65FfBB9CbB7C74fc7b7bCE4e7146ea](https://sepolia.etherscan.io/address/0xdb442defcc65ffbb9cbb7c74fc7b7bce4e7146ea)**		
  * UnderlyingTokenExchanger Logic	      
    **[0xB0106207fB50134B10473859f8d40F98959966b8](https://sepolia.etherscan.io/address/0xb0106207fb50134b10473859f8d40f98959966b8)**		
  * UnderlyingTokenExchanger Proxy	      
    **[0x126E6a6c0bE46a4e728c5bA30608a75196D749E8](https://sepolia.etherscan.io/address/0x126e6a6c0be46a4e728c5ba30608a75196d749e8)**		
  * UnderlyingTokenExchanger Proxy Admin	    
    **[0xcBdA76B2eB841c9E68415332d38E1053FB8058c2](https://sepolia.etherscan.io/address/0xcbda76b2eb841c9e68415332d38e1053fb8058c2)**		
  * MultisigWallet Logic	                
    **[0x1455ab2CfCeC9e5412c8a69efEd81af32Db2dad6](https://sepolia.etherscan.io/address/0x1455ab2cfcec9e5412c8a69efed81af32db2dad6)**		
  * MultisigWallet Proxy	                
    **[0x743D5D8E20f6ede8888044d1e48CA68b4Ec94641](https://sepolia.etherscan.io/address/0x743d5d8e20f6ede8888044d1e48ca68b4ec94641)**		
  * MultisigWallet Proxy Admin	          
    **[0x5722B4d98e30D94d9d85A982c45473FD0b0EE87d](https://sepolia.etherscan.io/address/0x5722b4d98e30d94d9d85a982c45473fd0b0ee87d)**		
  * ThresholdWallet Logic	                
    **[0xA95D9B787F1f7af51F43dA8b0f634481F2619846](https://sepolia.etherscan.io/address/0xa95d9b787f1f7af51f43da8b0f634481f2619846)**		
  * ThresholdWallet Proxy	                
    **[0x39a5A9d44C7E78f18A1C1990aC2eb4Dd4461F615](https://sepolia.etherscan.io/address/0x39a5a9d44c7e78f18a1c1990ac2eb4dd4461f615)**		
  * ThresholdWallet Proxy Admin	          
    **[0xc25DdDA8AeCc127933ee131fa498E9a3aE65b251](https://sepolia.etherscan.io/address/0xc25ddda8aecc127933ee131fa498e9a3ae65b251)**		
  * ValueInflationVault1 Logic	          
    **[0xc8CF5608Dbdc29429B1fDC08892d076A2339cddA](https://sepolia.etherscan.io/address/0xc8cf5608dbdc29429b1fdc08892d076a2339cdda)**		
  * ValueInflationVault1 Proxy	          
    **[0x618008fc3601ad6944d358D6b4b71C1de7CB4480](https://sepolia.etherscan.io/token/0x618008fc3601ad6944d358d6b4b71c1de7cb4480)**		
  * ValueInflationVault1 Proxy Admin	    
    **[0x6825142069830fa198237AFEdfCbe8B3fBD403a0](https://sepolia.etherscan.io/address/0x6825142069830fa198237afedfcbe8b3fbd403a0)**		
  * ValueInflationVault2 Logic	          
    **[0x94A46898350926Dc65e2D13A0fA614c5DBb05743](https://sepolia.etherscan.io/address/0x94a46898350926dc65e2d13a0fa614c5dbb05743)**		
  * ValueInflationVault2 Proxy	          
    **[0x19bd578A5ecD1D23B08F57D4648203B780cB1BE9](https://sepolia.etherscan.io/token/0x19bd578a5ecd1d23b08f57d4648203b780cb1be9)**		
  * ValueInflationVault2 Proxy Admin	    
    **[0xe9423912bfC8f924346B596704EcB06d76F24732](https://sepolia.etherscan.io/address/0xe9423912bfc8f924346b596704ecb06d76f24732)**		
  * FixedTermStaking Logic	              
    **[0xab1Fa1004E19BC39b9ccbDD8fE3Fc4c1539B806C](https://sepolia.etherscan.io/address/0xab1fa1004e19bc39b9ccbdd8fe3fc4c1539b806c)**		
  * FixedTermStaking Proxy	              
    **[0x751aadf0E0e313CcE119eaD623F6Dd327e7969B8](https://sepolia.etherscan.io/token/0x751aadf0e0e313cce119ead623f6dd327e7969b8)**		
  * FixedTermStaking Proxy Admin	        
    **[0x435A18Dc03597D241344bd56a28118648abd3122](https://sepolia.etherscan.io/address/0x435a18dc03597d241344bd56a28118648abd3122)**		
  * OpenTermStaking Logic	                
    **[0x91019e9F22cbCa036139DC84362674a2D3f30b44](https://sepolia.etherscan.io/address/0x91019e9f22cbca036139dc84362674a2d3f30b44)**		
  * OpenTermStaking Proxy	                
    **[0x74518ED2668fA79FA0452325F5C26D5414c9856E](https://sepolia.etherscan.io/token/0x74518ed2668fa79fa0452325f5c26d5414c9856e)**		
  * OpenTermStaking Proxy Admin	          
    **[0x3B9EEF57Ab1Ab7650Fbba22Faf3ED9286A1d722f](https://sepolia.etherscan.io/address/0x3b9eef57ab1ab7650fbba22faf3ed9286a1d722f)**		
  * TimePowerLoan Logic	                  
    **[0xd25c804dC8a816e5E6516894988AAEda8DB6948B](https://sepolia.etherscan.io/address/0xd25c804dc8a816e5e6516894988aaeda8db6948b)**	
  * TimePowerLoan Proxy	                  
    **[0x66cA7998fB69A25Eb1Bef5AbC0f8e0a438EdFCE0](https://sepolia.etherscan.io/address/0x66ca7998fb69a25eb1bef5abc0f8e0a438edfce0)**		
  * TimePowerLoan Proxy Admin	            
    **[0xdE00433C7A94b275ecaBd22b0e76d26Ae46e8A82](https://sepolia.etherscan.io/address/0xde00433c7a94b275ecabd22b0e76d26ae46e8a82)**		
  * TimeLinearLoan Logic	                
    **[0x10B941541B6A79E6F9770B5B74A2660Ab42B512B](https://sepolia.etherscan.io/address/0x10b941541b6a79e6f9770b5b74a2660ab42b512b)**	
  * TimeLinearLoan Proxy	                
    **[0x005816411DA7C0ab39Dc737A4600eac292FD3536](https://sepolia.etherscan.io/address/0x005816411da7c0ab39dc737a4600eac292fd3536)**		
  * TimeLinearLoan Proxy Admin	          
    **[0x71F6E6c4DA815A66b80a8121902325655F26dF3e](https://sepolia.etherscan.io/address/0x71f6e6c4da815a66b80a8121902325655f26df3e)**		

#### Main Network
TOD

### Upgrade
1. config **[.env](https://github.com/mosheng-eng/NexusFi/blob/master/.env)** file  
```
$ export LOGIC_INDEX=4 # set the logic index to deploy
```
Following list is logic contract indexes.  
  * 1 - Whitelist
  * 2 - Blacklist
  * 3 - UnderlyingToken
  * 4 - UnderlyingTokenExchanger
  * 5 - FixedTermStaking
  * 6 - OpenTermStaking
  * 7 - ValueInflationVault
  * 8 - TimePowerLoan
  * 9 - TimeLinearLoan
  * 10 - MultisigWallet
  * 11 - ThresholdWallet
2. run logic contract deployment script 
```
$ forge script script/DeployContractLogic.s.sol:DeployContractLogic --rpc-url https://api.zan.top/node/v1/eth/sepolia/YourAPIKey --broadcast --interactives 1 --verify --etherscan-api-key YourEtherscanAPIKey --optimize
```
If you don't have an API key, you can visit **[ZAN](https://zan.top)** and get a free one.  
If you don't have an etherscan API key, you can visit **[Etherscan](https://etherscan.io/apidashboard)** and get a free one.  
3. open XXX proxy admin contract on sepolia etherscan.  
For example, XXX = **[UnderlyingTokenExchanger Proxy Admin](https://sepolia.etherscan.io/address/0xcbda76b2eb841c9e68415332d38e1053fb8058c2)**.   
Then you should connect your proxy admin owner's wallet and call upgradeAndCall function.  
![Upgrade Example](doc/upgrade_example.png "Upgrade Example")

