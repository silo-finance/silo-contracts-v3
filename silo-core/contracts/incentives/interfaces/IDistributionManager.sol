// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.28;

interface IDistributionManager {
    struct IncentivesProgram {
        uint256 index;
        address rewardToken; // can't be updated after creation
        uint256 emissionPerSecond; // configured by owner
        uint40 lastUpdateTimestamp;
        uint40 distributionEnd; // configured by owner
        mapping(address user => uint256 userIndex) users;
    }

    struct IncentiveProgramDetails {
        uint256 index;
        address rewardToken;
        uint256 emissionPerSecond;
        uint40 lastUpdateTimestamp;
        uint40 distributionEnd;
    }

    struct AccruedRewards {
        uint256 amount;
        bytes32 programId;
        address rewardToken;
    }

    event AssetConfigUpdated(address indexed asset, uint256 emission);
    event AssetIndexUpdated(address indexed asset, uint256 index);
    event DistributionEndUpdated(string incentivesProgram, uint256 newDistributionEnd);
    event IncentivesProgramIndexUpdated(string incentivesProgram, uint256 newIndex);
    event UserIndexUpdated(address indexed user, string incentivesProgram, uint256 newIndex);

    error OnlyNotifier();
    error TooLongProgramName();
    error InvalidIncentivesProgramName();
    error OnlyNotifierOrOwner();
    error ZeroAddress();

    error EmissionForTimeDeltaOverflow();
    error IndexOverflow();
    error NewIndexOverflow();

    /**
     * @dev Sets the end date for the distribution
     * @param _incentivesProgram The incentives program name
     * @param _distributionEnd The end date timestamp
     */
    function setDistributionEnd(string calldata _incentivesProgram, uint40 _distributionEnd) external;

    /**
     * @dev Gets the end date for the distribution  
     * @param _incentivesProgram The incentives program name
     * @return The end of the distribution
     */
    function getDistributionEnd(string calldata _incentivesProgram) external view returns (uint256);

    /**
     * @dev Returns the data of an user on a distribution
     * @param _user Address of the user
     * @param _incentivesProgram The incentives program name
     * @return The new index
     */
    function getUserData(address _user, string calldata _incentivesProgram) external view returns (uint256);

    /**
     * @dev Returns the configuration of the distribution for a certain incentives program
     * @param _incentivesProgram The incentives program name
     * @return details The configuration of the incentives program
     */
    function incentivesProgram(string calldata _incentivesProgram)
        external
        view
        returns (IncentiveProgramDetails memory details);
    
    /**
     * @dev returns the names of all the incentives programs
     * @return programsNames the names of all the incentives programs
     */
    function getAllProgramsNames() external view returns (string[] memory programsNames);

    /**
     * @dev Returns the name of an incentives program (converts bytes32 to string)
     * @notice This function has a bug and can't do it in proper way when _programId is for 
     * immediate distribution (token address) that was not created yet. 
     * It works for programs that already exists.
     *
     * @param _programId the id (bytes32) of the incentives program
     * @return programName the name (string) of the incentives program
     */
    function getProgramName(bytes32 _programId) external view returns (string memory programName);


    /// @dev NOTIFIER is contract that is allowed to notify controller about token transfers.
    /// In original Aave implementation it was share token, but in Silo implementation it is usually hook contract.
    function NOTIFIER() external view returns (address); // solhint-disable-line func-name-mixedcase
    
    /**
     * @dev Returns the program id for the given program name.
     * This method TRUNCATES the program name to 32 bytes.
     * If provided strings only differ after the 32nd byte they would result in the same ProgramId.
     * Ensure to use inputs that will result in 32 bytes or less.
     * @param _programName The incentives program name
     * @return programId
     */
    function getProgramId(string calldata _programName) external pure returns (bytes32 programId);
}
