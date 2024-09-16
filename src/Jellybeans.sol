// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Jellybeans is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("ADMIN_ROLE");

    struct Round {
        string question;
        uint256 submissionDeadline;
        uint256 potAmount;
        uint256 feeAmount;
        uint256 correctAnswer;
        bool isFinalized;
    }

    struct Submission {
        address submitter;
        uint256 entry;
    }

    IERC20 public immutable opToken;
    address private immutable reserveAccount;

    uint256 public currentRound;
    mapping(uint256 => Round) public rounds; // round => Round
    mapping(uint256 => Submission[]) public submissions; // round => Submission[]
    mapping(uint256 => address[]) public winners; // round => address[]

    event RoundInitialized(
        uint256 indexed roundId, string question, uint256 submissionDeadline, uint256 potAmount, uint256 feeAmount
    );
    event GuessSubmitted(uint256 indexed roundId, address indexed participant, uint256 guess);
    event WinnerSelected(uint256 indexed roundId, address[] winners, uint256 correctAnswer, uint256 prizePerWinner);
    event FeesWithdrawn(address owner, uint256 amount);

    constructor(address _opTokenAddress, address _reserveAccount) {
        opToken = IERC20(_opTokenAddress);
        reserveAccount = _reserveAccount;
        _grantRole(OWNER_ROLE, msg.sender);
        _setRoleAdmin(OPERATOR_ROLE, OWNER_ROLE);
    }

    function initRound(string memory _question, uint256 _submissionDeadline, uint256 _potAmount, uint256 _feeAmount)
        external
        onlyRole(OPERATOR_ROLE)
    {
        require(_submissionDeadline > block.timestamp, "Submission deadline must be in the future");

        currentRound++;
        rounds[currentRound] = Round({
            question: _question,
            submissionDeadline: _submissionDeadline,
            potAmount: _potAmount,
            feeAmount: _feeAmount,
            correctAnswer: 0,
            isFinalized: false
        });

        opToken.safeTransferFrom(reserveAccount, address(this), _potAmount);

        emit RoundInitialized(currentRound, _question, _submissionDeadline, _potAmount, _feeAmount);
    }

    function submitGuess(uint256 _roundId, uint256 _guess) external payable nonReentrant {
        Round storage round = rounds[_roundId];
        require(round.submissionDeadline > 0, "Round does not exist");
        require(block.timestamp < round.submissionDeadline, "Submission deadline has passed");
        require(msg.value == round.feeAmount, "Incorrect fee amount");

        submissions[_roundId].push(Submission({submitter: msg.sender, entry: _guess}));

        emit GuessSubmitted(_roundId, msg.sender, _guess);
    }

    function setCorrectAnswer(uint256 _roundId, uint256 _correctAnswer) external onlyRole(OPERATOR_ROLE) nonReentrant {
        Round storage round = rounds[_roundId];
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
                winners[_roundId].push(submission.submitter);
            } else if (submission.entry == closestGuess) {
                winners[_roundId].push(submission.submitter);
            }
        }

        uint256 prizePerWinner = round.potAmount / winners[_roundId].length;
        for (uint256 i = 0; i < winners[_roundId].length; i++) {
            opToken.safeTransfer(winners[_roundId][i], prizePerWinner);
        }

        emit WinnerSelected(_roundId, winners[_roundId], _correctAnswer, prizePerWinner);
    }

    function withdrawFees() external onlyRole(OWNER_ROLE) {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");

        (bool success,) = _msgSender().call{value: balance}("");
        require(success, "Failed to send fees to owner");

        emit FeesWithdrawn(_msgSender(), balance);
    }

    receive() external payable {}
}
