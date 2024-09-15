// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Jellybeans is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    struct Round {
        string question;
        uint256 submissionDeadline;
        uint256 potAmount;
        uint256 feeAmount;
        uint256 correctAnswer;
        bool isFinalized;
    }

    IERC20 public opToken;
    uint256 public currentRound;
    mapping(uint256 => Round) public rounds;
    mapping(uint256 => mapping(address => uint256[])) public submissions;
    mapping(uint256 => address[]) public winners;

    event RoundInitialized(
        uint256 indexed roundId,
        string question,
        uint256 submissionDeadline,
        uint256 potAmount,
        uint256 feeAmount
    );
    event GuessSubmitted(
        uint256 indexed roundId,
        address indexed participant,
        uint256 guess
    );
    event WinnerSelected(
        uint256 indexed roundId,
        address[] winners,
        uint256 correctAnswer,
        uint256 prizePerWinner
    );
    event FeesWithdrawn(address owner, uint256 amount);

    constructor(address _opTokenAddress) {
        opToken = IERC20(_opTokenAddress);
        _grantRole(OWNER_ROLE, msg.sender);
    }

    function initRound(
        string memory _question,
        uint256 _submissionDeadline,
        uint256 _potAmount,
        uint256 _feeAmount
    ) external onlyRole(ADMIN_ROLE) {
        require(
            _submissionDeadline > block.timestamp,
            "Submission deadline must be in the future"
        );

        currentRound++;
        rounds[currentRound] = Round({
            question: _question,
            submissionDeadline: _submissionDeadline,
            potAmount: _potAmount,
            feeAmount: _feeAmount,
            correctAnswer: 0,
            isFinalized: false
        });

        opToken.safeTransferFrom(msg.sender, address(this), _potAmount);

        emit RoundInitialized(
            currentRound,
            _question,
            _submissionDeadline,
            _potAmount,
            _feeAmount
        );
    }
}