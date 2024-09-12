// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SimpleOptimisticRollup {
    struct RollupBlock {
        bytes[] transactions; // Transactions are stored on-chain for data availability
        bytes32 stateRoot;
        uint256 timestamp;
        bool finalized;
    }

    RollupBlock[] public rollupBlocks;
    uint256 public challengePeriod = 1 days;

    event RollupBlockSubmitted(uint256 indexed blockNumber, bytes32 stateRoot);
    event RollupBlockFinalized(uint256 indexed blockNumber);
    event ChallengeInitiated(uint256 challengeId, uint256 blockNumber, address challenger);
    event ChallengeBisected(uint256 challengeId, uint256 start, uint256 end, bytes32[2] stateRoots);
    event ChallengeResolved(uint256 challengeId, bool defenderWins);

    struct Challenge {
        uint256 blockNumber;
        address challenger;
        uint256 start;
        uint256 end;
        bytes32[2] stateRoots; // [startStateRoot, endStateRoot]
        bool resolved;
    }

    mapping(uint256 => Challenge) public challenges;
    uint256 public nextChallengeId = 1;

    function submitRollupBlock(bytes[] calldata _transactions, bytes32 _stateRoot) external {
        RollupBlock memory newBlock = RollupBlock({
            transactions: _transactions,
            stateRoot: _stateRoot,
            timestamp: block.timestamp,
            finalized: false
        });
        rollupBlocks.push(newBlock);
        emit RollupBlockSubmitted(rollupBlocks.length - 1, _stateRoot);
    }

    function finalizeRollupBlock(uint256 blockNumber) external {
        RollupBlock storage rollupBlock = rollupBlocks[blockNumber];
        require(!rollupBlock.finalized, "Block already finalized");
        require(block.timestamp >= rollupBlock.timestamp + challengePeriod, "Challenge period not over");
        rollupBlock.finalized = true;
        emit RollupBlockFinalized(blockNumber);
    }

    function initiateChallenge(uint256 _blockNumber) external {
        RollupBlock storage rollupBlock = rollupBlocks[_blockNumber];
        require(!rollupBlock.finalized, "Block already finalized");
        require(block.timestamp < rollupBlock.timestamp + challengePeriod, "Challenge period over");

        Challenge storage newChallenge = challenges[nextChallengeId];
        newChallenge.blockNumber = _blockNumber;
        newChallenge.challenger = msg.sender;
        newChallenge.start = 0;
        newChallenge.end = rollupBlock.transactions.length;
        newChallenge.stateRoots = [bytes32(0), rollupBlock.stateRoot]; // Initial state root is zero
        newChallenge.resolved = false;

        emit ChallengeInitiated(nextChallengeId, _blockNumber, msg.sender);
        nextChallengeId++;
    }

    function bisectChallenge(
        uint256 _challengeId,
        uint256 _mid,
        bytes32 _midStateRoot
    ) external {
        Challenge storage challenge = challenges[_challengeId];
        require(!challenge.resolved, "Challenge already resolved");
        require(msg.sender == getDefender(challenge.blockNumber), "Only defender can bisect");

        // Update challenge with new mid point
        challenge.end = _mid;
        challenge.stateRoots[1] = _midStateRoot;

        emit ChallengeBisected(_challengeId, challenge.start, challenge.end, challenge.stateRoots);
    }

    function selectSegment(uint256 _challengeId, uint256 _start, uint256 _end, bytes32[2] calldata _stateRoots) external {
        Challenge storage challenge = challenges[_challengeId];
        require(!challenge.resolved, "Challenge already resolved");
        require(msg.sender == challenge.challenger, "Only challenger can select segment");

        // Update challenge with selected segment
        challenge.start = _start;
        challenge.end = _end;
        challenge.stateRoots = _stateRoots;

        emit ChallengeBisected(_challengeId, _start, _end, _stateRoots);

        // If only one instruction left, resolve the dispute
        if (_end - _start == 1) {
            resolveDispute(_challengeId);
        }
    }

    function resolveDispute(uint256 _challengeId) internal {
        Challenge storage challenge = challenges[_challengeId];
        challenge.resolved = true;

        // Execute the disputed instruction on-chain
        RollupBlock storage rollupBlock = rollupBlocks[challenge.blockNumber];
        bytes memory transaction = rollupBlock.transactions[challenge.start];

        // Simulate VM execution
        bytes32 computedStateRoot = executeTransaction(challenge.stateRoots[0], transaction);

        bool defenderWins = (computedStateRoot == challenge.stateRoots[1]);

        emit ChallengeResolved(_challengeId, defenderWins);

        if (defenderWins) {
            // Defender wins, no action needed in this simplified example
        } else {
            // Invalidate the rollup block (not implemented in this toy example)
        }
    }

    function executeTransaction(bytes32 _startStateRoot, bytes memory _transaction) internal pure returns (bytes32) {
        // Simplified execution logic
        // Decode transaction
        (string memory txType, uint256 value) = abi.decode(_transaction, (string, uint256));

        uint256 state = uint256(_startStateRoot);

        if (keccak256(bytes(txType)) == keccak256(bytes("add"))) {
            state += value;
        } else if (keccak256(bytes(txType)) == keccak256(bytes("multiply"))) {
            state *= value;
        }

        return bytes32(state);
    }

    function getDefender(uint256 _blockNumber) public view returns (address) {
        // For simplicity, the defender is the address that submitted the block
        // Not implemented: tracking of block proposers
        return address(0); // Placeholder
    }

    // Rest of the contract code...
}
