// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

/**
 * @title Jellybeans
 * @dev A contract for managing guessing game rounds with ERC1155 tokens
 */
contract Jellybeans is AccessControl, ReentrancyGuard, ERC1155 {
    using SafeERC20 for IERC20;

    // ============ Constants ============

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // ============ Structs ============

    struct Round {
        string question;
        uint256 submissionDeadline;
        IERC20 token;
        uint256 potAmount;
        uint256 feeAmount;
        uint256 correctAnswer;
        bool isFinalized;
    }

    struct Submission {
        address submitter;
        uint256 entry;
    }

    // ============ State Variables ============

    uint256 public currentRound;
    mapping(uint256 => Round) public rounds; // round => Round
    mapping(uint256 => Submission[]) public submissions; // round => Submission[]
    mapping(uint256 => Submission[]) public winners; // round => Submission[]

    // ============ Events ============

    event RoundInitialized(
        uint256 indexed roundId,
        string question,
        uint256 submissionDeadline,
        address potTokenAddress,
        uint256 potAmount,
        uint256 feeAmount
    );
    event GuessSubmitted(uint256 indexed roundId, address indexed submitter, uint256 guess);
    event WinnerSelected(uint256 indexed roundId, Submission[] winners, uint256 correctAnswer);
    event FeesWithdrawn(address owner, uint256 amount);

    // ============ Constructor ============

    constructor(address _owner, string memory _uri) ERC1155(_uri) {
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(OPERATOR_ROLE, _owner);
    }

    // ============ External Functions ============

    function initRound(
        string memory _question,
        uint256 _submissionDeadline,
        address _potTokenAddress,
        uint256 _potAmount,
        uint256 _feeAmount
    ) external onlyRole(OPERATOR_ROLE) {
        require(_submissionDeadline > block.timestamp, "Submission deadline must be in the future");

        currentRound++;
        rounds[currentRound] = Round({
            question: _question,
            submissionDeadline: _submissionDeadline,
            token: IERC20(_potTokenAddress),
            potAmount: _potAmount,
            feeAmount: _feeAmount,
            correctAnswer: 0,
            isFinalized: false
        });

        emit RoundInitialized(currentRound, _question, _submissionDeadline, _potTokenAddress, _potAmount, _feeAmount);
    }

    function submitGuess(uint256 _roundId, uint256 _guess) external payable nonReentrant {
        Round storage round = rounds[_roundId];

        require(round.submissionDeadline > 0, "Round does not exist");
        require(block.timestamp < round.submissionDeadline, "Submission deadline has passed");
        require(msg.value == round.feeAmount, "Incorrect fee amount");

        submissions[_roundId].push(Submission({submitter: msg.sender, entry: _guess}));

        _mint(msg.sender, _roundId, 1, "");

        emit GuessSubmitted(_roundId, msg.sender, _guess);
    }

    function setCorrectAnswer(uint256 _roundId, uint256 _correctAnswer) external onlyRole(OPERATOR_ROLE) nonReentrant {
        Round storage round = rounds[_roundId];

        require(round.submissionDeadline > 0, "Round does not exist");
        require(block.timestamp >= round.submissionDeadline, "Submission deadline has not passed");
        require(!round.isFinalized, "Round is already finalized");

        round.correctAnswer = _correctAnswer;
        round.isFinalized = true;

        uint256 closestGuess = 0;

        for (uint256 i = 0; i < submissions[_roundId].length; i++) {
            Submission memory submission = submissions[_roundId][i];
            if (submission.entry > closestGuess && submission.entry <= round.correctAnswer) {
                // Re-set closest guess
                closestGuess = submission.entry;
                // Re-set submission list
                delete winners[_roundId];
                winners[_roundId].push(Submission({submitter: submission.submitter, entry: submission.entry}));
            } else if (submission.entry == closestGuess) {
                winners[_roundId].push(Submission({submitter: submission.submitter, entry: submission.entry}));
            }
        }

        emit WinnerSelected(_roundId, winners[_roundId], _correctAnswer);
    }

    function withdrawFees() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");

        (bool success,) = _msgSender().call{value: balance}("");
        require(success, "Failed to send fees to owner");

        emit FeesWithdrawn(_msgSender(), balance);
    }

    function setURI(string memory _newURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(_newURI);
    }

    // ============ Public Functions ============

    function supportsInterface(bytes4 _interfaceId)
        public
        view
        virtual
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(_interfaceId);
    }

    // ============ Fallback Function ============

    receive() external payable {}
}
