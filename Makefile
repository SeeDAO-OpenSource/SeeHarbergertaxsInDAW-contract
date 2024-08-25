# Load environment variables from .env file
include .env

# Common variables
RPC_URL := --rpc-url ${AMOY_RPC_URL}
CHAIN_ID := --chain 80002
CONTRACT := src/ShdV1.sol:ShdV1

# PHONY targets
.PHONY: all compile test deploy verify approve create purchase setPrice balance send allowance deposit withdraw withdrawBenefit checkUsePermissionForShd

# Default target
all: compile

# Compilation
compile:
	forge compile

# Testing
test:
	forge test -vvvvv

# Deployment
deploy:
	forge create --constructor-args ${SRC_TEST_TOKEN_ADDRESS} "SHD" 1000000000000000000 0xfF9fdF34a7C3590ec24C879767F8Becb04558ce2 60 30 --private-key ${OWNER_PRIVATE_KEY} $(CHAIN_ID) $(RPC_URL) $(CONTRACT)

# Verification
verify:
	forge verify-contract --constructor-args ${ABI_ENCODED_CONSTRUCTOR} -e ${AMOY_SCAN_KEY} $(RPC_URL) $(CHAIN_ID) ${CONTRACT_ADDRESS} $(CONTRACT)

# Approve function for multiple users (pattern rule)
approve%:
	cast send ${SRC_TEST_TOKEN_ADDRESS} "approve(address,uint256)" ${CONTRACT_ADDRESS} ${AMOUNT} $(RPC_URL) --private-key ${USER$*_PRIVATE_KEY}

# Other contract interactions
create:
	cast send ${CONTRACT_ADDRESS} "createShd()" $(RPC_URL) --private-key ${OWNER_PRIVATE_KEY}

purchase:
	cast send ${CONTRACT_ADDRESS} "purchase(uint256)" 0 $(RPC_URL) --private-key ${USER2_PRIVATE_KEY}

setPrice:
	cast send ${CONTRACT_ADDRESS} "setPrice(uint256,uint256,uint256)" 0 2ether 1ether $(RPC_URL) --private-key ${USER2_PRIVATE_KEY}

# Balance check for multiple users (pattern rule)
balance%:
	cast call ${SRC_TEST_TOKEN_ADDRESS} "balanceOf(address)(uint256)" ${USER$*_ADDRESS} $(RPC_URL)

# Transfer tokens
send:
	cast send ${SRC_TEST_TOKEN_ADDRESS} "transfer(address,uint256)" ${USER2_ADDRESS} ${AMOUNT} $(RPC_URL) --private-key ${OWNER_PRIVATE_KEY}

# Check allowance
allowance:
	cast call ${SRC_TEST_TOKEN_ADDRESS} "allowance(address,address)(uint256)" ${CONTRACT_ADDRESS} ${USER3_ADDRESS} $(RPC_URL)

# Deposit
deposit:
	cast send ${CONTRACT_ADDRESS} "deposit(uint256,uint256)" 0 100000000000000000 $(RPC_URL) --private-key ${USER1_PRIVATE_KEY}

# Withdraw
withdraw:
	cast send ${CONTRACT_ADDRESS} "withdraw(uint256,uint256)" 0 1000000 $(RPC_URL) --private-key ${USER1_PRIVATE_KEY}

# Withdraw benefits
withdrawBenefit:
	cast send ${CONTRACT_ADDRESS} "withdrawAllForBeneficiary()" $(RPC_URL) --private-key ${OWNER_PRIVATE_KEY}

# Check SHD usage permission
checkUsePermissionForShd:
	cast call ${CONTRACT_ADDRESS} "checkUsePermissionForShd(uint256)(bool)" 0 $(RPC_URL)
