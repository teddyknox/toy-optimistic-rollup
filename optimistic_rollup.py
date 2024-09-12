from web3 import Web3
from solcx import compile_files, install_solc
import json
import time

# Connect to local Anvil Ethereum node
w3 = Web3(Web3.HTTPProvider("http://127.0.0.1:8545"))

# Ensure connection is established
if not w3.is_connected():
    print("Failed to connect to Anvil Ethereum node.")
    exit(1)

# Compile the Solidity contract
compiled_sol = compile_files(['SimpleOptimisticRollup.sol'], output_values=['abi', 'bin'])
contract_id = 'SimpleOptimisticRollup.sol:SimpleOptimisticRollup'
contract_interface = compiled_sol[contract_id]

# Deploy the contract
SimpleOptimisticRollup = w3.eth.contract(
    abi=contract_interface['abi'],
    bytecode=contract_interface['bin']
)

# Get accounts
deployer = w3.eth.accounts[0]
challenger = w3.eth.accounts[1]

# Deploy the contract
tx_hash = SimpleOptimisticRollup.constructor().transact({'from': deployer})
tx_receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
contract_address = tx_receipt.contractAddress

# Create contract instance
contract_instance = w3.eth.contract(
    address=contract_address,
    abi=contract_interface['abi']
)

print(f"Contract deployed at address: {contract_address}")

# Transaction structure
class Transaction:
    def __init__(self, tx_type, value):
        self.tx_type = tx_type  # 'add' or 'multiply'
        self.value = value

    def serialize(self):
        return w3.codec.encode_abi(['string', 'uint256'], [self.tx_type, int(self.value)])

# Simple VM state
class SimpleVM:
    def __init__(self):
        self.state = 0  # Use integer for compatibility with Solidity

    def apply_transaction(self, transaction):
        if transaction.tx_type == 'add':
            self.state += transaction.value
        elif transaction.tx_type == 'multiply':
            self.state *= transaction.value

    def get_state_root(self):
        return bytes32(self.state)

def bytes32(value):
    return value.to_bytes(32, byteorder='big')

# Prepare transactions
transactions = [
    Transaction('add', 10),
    Transaction('multiply', 2),
    Transaction('add', 5)
]

serialized_transactions = [tx.serialize() for tx in transactions]

# Initialize VM and compute final state root
vm = SimpleVM()
for tx in transactions:
    vm.apply_transaction(tx)

state_root = bytes32(vm.state)

# Submit the rollup block with transactions
tx_hash = contract_instance.functions.submitRollupBlock(serialized_transactions, state_root).transact({'from': deployer})
w3.eth.wait_for_transaction_receipt(tx_hash)

print("Rollup block submitted with transactions and state root.")

# Simulate a challenge
block_number = 0  # Challenging the first block

# Initiate a challenge
tx_hash = contract_instance.functions.initiateChallenge(block_number).transact({'from': challenger})
w3.eth.wait_for_transaction_receipt(tx_hash)

print(f"Challenge initiated by {challenger} against block {block_number}")

# Defender bisects the challenge
challenge_id = 1  # Assuming it's the first challenge
mid_index = len(transactions) // 2  # Midpoint of transactions

# Defender computes mid state root
vm_defender = SimpleVM()
for tx in transactions[:mid_index]:
    vm_defender.apply_transaction(tx)
mid_state_root = bytes32(vm_defender.state)

tx_hash = contract_instance.functions.bisectChallenge(challenge_id, mid_index, mid_state_root).transact({'from': deployer})
w3.eth.wait_for_transaction_receipt(tx_hash)

print("Defender bisected the challenge.")

# Challenger selects segment (start to mid)
start_state_root = bytes32(0)  # Initial state root is zero
tx_hash = contract_instance.functions.selectSegment(
    challenge_id,
    0,
    mid_index,
    [start_state_root, mid_state_root]
).transact({'from': challenger})
w3.eth.wait_for_transaction_receipt(tx_hash)

print("Challenger selected the segment.")

# Since the segment length is more than 1, the process would repeat
# For simplicity, we'll bisect until one transaction is left

# Continue bisecting until one transaction remains
current_start = 0
current_end = mid_index
current_start_state = 0
current_end_state = vm_defender.state

while current_end - current_start > 1:
    mid = (current_start + current_end) // 2

    # Defender computes mid state root
    vm_defender = SimpleVM()
    for tx in transactions[:mid]:
        vm_defender.apply_transaction(tx)
    mid_state_root = bytes32(vm_defender.state)

    # Defender bisects
    tx_hash = contract_instance.functions.bisectChallenge(challenge_id, mid, mid_state_root).transact({'from': deployer})
    w3.eth.wait_for_transaction_receipt(tx_hash)
    print(f"Defender bisected at index {mid}.")

    # Challenger selects segment
    tx_hash = contract_instance.functions.selectSegment(
        challenge_id,
        current_start,
        mid,
        [bytes32(current_start_state), mid_state_root]
    ).transact({'from': challenger})
    w3.eth.wait_for_transaction_receipt(tx_hash)
    print(f"Challenger selected segment {current_start} to {mid}.")

    # Update current end to mid
    current_end = mid
    current_end_state = int.from_bytes(mid_state_root, byteorder='big')

# Now only one transaction remains, dispute will be resolved
print("Dispute resolution should occur now.")

# The contract should execute the transaction on-chain and emit the result
# In this simplified example, we won't process event logs
