// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";

/**
 * @title Jellybeans
 * @dev A contract for managing guessing game rounds with ERC1155 tokens
 */
contract Jellybeans is AccessControl, ReentrancyGuard, ERC1155, ERC1155Supply {
    // ============ Constants ============

    /// @notice A role that can initiate and close rounds
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // ============ Structs ============

    struct Round {
        string question;
        uint256 submissionDeadline;
        address token;
        uint256 potAmount;
        uint256 numWinners;
        uint256 feeAmount;
        uint256 correctAnswer;
        bool isFinalized;
    }

    struct Submission {
        address submitter;
        uint256 entry;
    }

    // ============ State Variables ============

    /// @notice The current round number
    uint256 public currentRound;

    /// @notice A mapping of round numbers to round details
    mapping(uint256 => Round) public rounds;

    /// @notice A mapping of round numbers to an array of all submissions
    mapping(uint256 => Submission[]) public submissions;

    /// @notice A mapping of round numbers to an array of winning submissions
    mapping(uint256 => Submission[]) public winners;

    // ============ Errors ============

    error RoundDoesNotExist();
    error SubmissionDeadlinePassed();
    error IncorrectFeeAmount();
    error SubmissionDeadlineNotInFuture();
    error SubmissionDeadlineNotPassed();
    error RoundAlreadyFinalized();
    error NoFeesToWithdraw();
    error FailedToSendFees();

    // ============ Events ============

    event RoundInitialized(
        uint256 indexed roundId,
        string question,
        uint256 submissionDeadline,
        address potTokenAddress,
        uint256 potAmount,
        uint256 numWinners,
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

    /**
     * @notice Allows a user to submit a guess for the current round
     *
     * @dev Mints an ERC1155 token to the submitter as a receipt
     * @param _roundId The ID of the round to submit a guess for
     * @param _guess The user's guess for the round
     */
    function submitGuess(uint256 _roundId, uint256 _guess) external payable nonReentrant {
        Round storage round = rounds[_roundId];

        if (round.submissionDeadline == 0) {
            revert RoundDoesNotExist();
        }
        if (block.timestamp >= round.submissionDeadline) {
            revert SubmissionDeadlinePassed();
        }
        if (msg.value != round.feeAmount) {
            revert IncorrectFeeAmount();
        }

        submissions[_roundId].push(Submission({submitter: msg.sender, entry: _guess}));

        _mint(msg.sender, _roundId, 1, "");

        emit GuessSubmitted(_roundId, msg.sender, _guess);
    }

    // ============ Operator Functions ============

    /**
     * @notice Initializes a new round of the guessing game
     *
     * @dev Only callable by addresses with the OPERATOR_ROLE
     * @param _question The question or prompt for the round
     * @param _submissionDeadline The timestamp after which no more guesses can be submitted
     * @param _potTokenAddress The address of the ERC20 token used for the pot
     * @param _potAmount The total amount of tokens in the pot for this round
     * @param _feeAmount The fee amount in wei required to submit a guess
     */
    function initRound(
        string memory _question,
        uint256 _submissionDeadline,
        address _potTokenAddress,
        uint256 _potAmount,
        uint256 _numWinners,
        uint256 _feeAmount
    ) external onlyRole(OPERATOR_ROLE) {
        if (_submissionDeadline <= block.timestamp) {
            revert SubmissionDeadlineNotInFuture();
        }

        currentRound++;
        rounds[currentRound] = Round({
            question: _question,
            submissionDeadline: _submissionDeadline,
            token: _potTokenAddress,
            potAmount: _potAmount,
            numWinners: _numWinners,
            feeAmount: _feeAmount,
            correctAnswer: 0,
            isFinalized: false
        });

        emit RoundInitialized(
            currentRound, _question, _submissionDeadline, _potTokenAddress, _potAmount, _numWinners, _feeAmount
        );
    }

    /**
     * @notice Sets the correct answer for a round and determines the winners
     *
     * @dev Only callable by addresses with the OPERATOR_ROLE after the submission deadline
     * @param _roundId The ID of the round to set the correct answer for
     * @param _correctAnswer The correct answer for the round
     */
    function setCorrectAnswer(uint256 _roundId, uint256 _correctAnswer) external onlyRole(OPERATOR_ROLE) nonReentrant {
        Round storage round = rounds[_roundId];

        if (round.submissionDeadline == 0) {
            revert RoundDoesNotExist();
        }
        if (block.timestamp < round.submissionDeadline) {
            revert SubmissionDeadlineNotPassed();
        }
        if (round.isFinalized) {
            revert RoundAlreadyFinalized();
        }

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

    // ============ Admin Functions ============

    function withdrawFees() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = address(this).balance;
        if (balance == 0) {
            revert NoFeesToWithdraw();
        }

        (bool success,) = _msgSender().call{value: balance}("");
        if (!success) {
            revert FailedToSendFees();
        }
        emit FeesWithdrawn(_msgSender(), balance);
    }

    function setURI(string memory _newURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(_newURI);
    }

    // ============ Required Overrides ============

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155, ERC1155Supply)
    {
        super._update(from, to, ids, values);
    }

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
