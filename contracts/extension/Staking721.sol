// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

import "../openzeppelin-presets/security/ReentrancyGuard.sol";
import "../eip/interface/IERC721.sol";

import "./interface/IStaking721.sol";

/**
 *      note: This is a Beta release.
 */

abstract contract Staking721 is ReentrancyGuard, IStaking721 {
    /*///////////////////////////////////////////////////////////////
                            State variables / Mappings
    //////////////////////////////////////////////////////////////*/

    ///@dev Address of ERC721 NFT contract -- staked tokens belong to this contract.
    address public nftCollection;

    ///@dev List of token-ids ever staked.
    uint256[] public indexedTokens;

    /// @dev List of accounts that have staked their NFTs.
    address[] public stakersArray;

    ///@dev Next staking condition Id. Tracks number of conditon updates so far.
    uint256 private nextConditionId;

    ///@dev Mapping from token-id to whether it is indexed or not.
    mapping(uint256 => bool) public isIndexed;

    ///@dev Mapping from staker address to Staker struct. See {struct IStaking721.Staker}.
    mapping(address => Staker) public stakers;

    /// @dev Mapping from staked token-id to staker address.
    mapping(uint256 => address) public stakerAddress;

    ///@dev Mapping from condition Id to staking condition. See {struct IStaking721.StakingCondition}
    mapping(uint256 => StakingCondition) private stakingConditions;

    constructor(address _nftCollection) ReentrancyGuard() {
        require(address(_nftCollection) != address(0), "collection address 0");
        nftCollection = _nftCollection;
    }

    /*///////////////////////////////////////////////////////////////
                        External/Public Functions
    //////////////////////////////////////////////////////////////*/

    /**
     *  @notice    Stake ERC721 Tokens.
     *
     *  @dev       See {_stake}. Override that to implement custom logic.
     *
     *  @param _tokenIds    List of tokens to stake.
     */
    function stake(uint256[] calldata _tokenIds) external nonReentrant {
        _stake(_tokenIds);
    }

    /**
     *  @notice    Withdraw staked tokens.
     *
     *  @dev       See {_withdraw}. Override that to implement custom logic.
     *
     *  @param _tokenIds    List of tokens to withdraw.
     */
    function withdraw(uint256[] calldata _tokenIds) external nonReentrant {
        _withdraw(_tokenIds);
    }

    /**
     *  @notice    Claim accumulated rewards.
     *
     *  @dev       See {_claimRewards}. Override that to implement custom logic.
     *             See {_calculateRewards} for reward-calculation logic.
     */
    function claimRewards() external nonReentrant {
        _claimRewards();
    }

    /**
     *  @notice  Set time unit. Set as a number of seconds.
     *           Could be specified as -- x * 1 hours, x * 1 days, etc.
     *
     *  @dev     Only admin/authorized-account can call it.
     *
     *
     *  @param _timeUnit    New time unit.
     */
    function setTimeUnit(uint256 _timeUnit) external virtual {
        if (!_canSetStakeConditions()) {
            revert("Not authorized");
        }

        StakingCondition memory condition = stakingConditions[nextConditionId - 1];
        _setStakingCondition(_timeUnit, condition.rewardsPerUnitTime);

        emit UpdatedTimeUnit(condition.timeUnit, _timeUnit);
    }

    /**
     *  @notice  Set rewards per unit of time.
     *           Interpreted as x rewards per second/per day/etc based on time-unit.
     *
     *  @dev     Only admin/authorized-account can call it.
     *
     *
     *  @param _rewardsPerUnitTime    New rewards per unit time.
     */
    function setRewardsPerUnitTime(uint256 _rewardsPerUnitTime) external virtual {
        if (!_canSetStakeConditions()) {
            revert("Not authorized");
        }

        StakingCondition memory condition = stakingConditions[nextConditionId - 1];
        _setStakingCondition(condition.timeUnit, _rewardsPerUnitTime);

        emit UpdatedRewardsPerUnitTime(condition.rewardsPerUnitTime, _rewardsPerUnitTime);
    }

    /**
     *  @notice View amount staked and total rewards for a user.
     *
     *  @param _staker          Address for which to calculated rewards.
     *  @return _tokensStaked   List of token-ids staked by staker.
     *  @return _rewards        Available reward amount.
     */
    function getStakeInfo(address _staker)
        public
        view
        virtual
        returns (uint256[] memory _tokensStaked, uint256 _rewards)
    {
        uint256[] memory _indexedTokens = indexedTokens;
        bool[] memory _isStakerToken = new bool[](_indexedTokens.length);
        uint256 indexedTokenCount = _indexedTokens.length;
        uint256 stakerTokenCount = 0;

        for (uint256 i = 0; i < indexedTokenCount; i++) {
            _isStakerToken[i] = stakerAddress[_indexedTokens[i]] == _staker;
            if (_isStakerToken[i]) stakerTokenCount += 1;
        }

        _tokensStaked = new uint256[](stakerTokenCount);
        uint256 count = 0;
        for (uint256 i = 0; i < indexedTokenCount; i++) {
            if (_isStakerToken[i]) {
                _tokensStaked[count] = _indexedTokens[i];
                count += 1;
            }
        }

        _rewards = _availableRewards(_staker);
    }

    function getTimeUnit() public view returns (uint128 _timeUnit) {
        _timeUnit = stakingConditions[nextConditionId - 1].timeUnit;
    }

    function getRewardsPerUnitTime() public view returns (uint128 _rewardsPerUnitTime) {
        _rewardsPerUnitTime = stakingConditions[nextConditionId - 1].rewardsPerUnitTime;
    }

    /*///////////////////////////////////////////////////////////////
                            Internal Functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Staking logic. Override to add custom logic.
    function _stake(uint256[] calldata _tokenIds) internal virtual {
        uint256 len = _tokenIds.length;
        require(len != 0, "Staking 0 tokens");

        address _nftCollection = nftCollection;

        if (stakers[msg.sender].amountStaked > 0) {
            _updateUnclaimedRewardsForStaker(msg.sender);
        } else {
            stakersArray.push(msg.sender);
            stakers[msg.sender].timeOfLastUpdate = block.timestamp;
            stakers[msg.sender].conditionIdOflastUpdate = nextConditionId - 1;
        }
        for (uint256 i = 0; i < len; ++i) {
            require(
                IERC721(_nftCollection).ownerOf(_tokenIds[i]) == msg.sender &&
                    (IERC721(_nftCollection).getApproved(_tokenIds[i]) == address(this) ||
                        IERC721(_nftCollection).isApprovedForAll(msg.sender, address(this))),
                "Not owned or approved"
            );
            IERC721(_nftCollection).transferFrom(msg.sender, address(this), _tokenIds[i]);
            stakerAddress[_tokenIds[i]] = msg.sender;

            if (!isIndexed[_tokenIds[i]]) {
                isIndexed[_tokenIds[i]] = true;
                indexedTokens.push(_tokenIds[i]);
            }
        }
        stakers[msg.sender].amountStaked += len;

        emit TokensStaked(msg.sender, _tokenIds);
    }

    /// @dev Withdraw logic. Override to add custom logic.
    function _withdraw(uint256[] calldata _tokenIds) internal virtual {
        uint256 _amountStaked = stakers[msg.sender].amountStaked;
        uint256 len = _tokenIds.length;
        require(len != 0, "Withdrawing 0 tokens");
        require(_amountStaked >= len, "Withdrawing more than staked");

        address _nftCollection = nftCollection;

        _updateUnclaimedRewardsForStaker(msg.sender);

        if (_amountStaked == len) {
            for (uint256 i = 0; i < stakersArray.length; ++i) {
                if (stakersArray[i] == msg.sender) {
                    stakersArray[i] = stakersArray[stakersArray.length - 1];
                    stakersArray.pop();
                }
            }
        }
        stakers[msg.sender].amountStaked -= len;

        for (uint256 i = 0; i < len; ++i) {
            require(stakerAddress[_tokenIds[i]] == msg.sender, "Not staker");
            stakerAddress[_tokenIds[i]] = address(0);
            IERC721(_nftCollection).transferFrom(address(this), msg.sender, _tokenIds[i]);
        }

        emit TokensWithdrawn(msg.sender, _tokenIds);
    }

    /// @dev Logic for claiming rewards. Override to add custom logic.
    function _claimRewards() internal virtual {
        uint256 rewards = stakers[msg.sender].unclaimedRewards + _calculateRewards(msg.sender);

        require(rewards != 0, "No rewards");

        stakers[msg.sender].timeOfLastUpdate = block.timestamp;
        stakers[msg.sender].unclaimedRewards = 0;
        stakers[msg.sender].conditionIdOflastUpdate = nextConditionId - 1;

        _mintRewards(msg.sender, rewards);

        emit RewardsClaimed(msg.sender, rewards);
    }

    /// @dev View available rewards for a user.
    function _availableRewards(address _user) internal view virtual returns (uint256 _rewards) {
        if (stakers[_user].amountStaked == 0) {
            _rewards = stakers[_user].unclaimedRewards;
        } else {
            _rewards = stakers[_user].unclaimedRewards + _calculateRewards(_user);
        }
    }

    /// @dev Update unclaimed rewards for a users. Called for every state change for a user.
    function _updateUnclaimedRewardsForStaker(address _staker) internal virtual {
        uint256 rewards = _calculateRewards(_staker);
        stakers[_staker].unclaimedRewards += rewards;
        stakers[_staker].timeOfLastUpdate = block.timestamp;
        stakers[_staker].conditionIdOflastUpdate = nextConditionId - 1;
    }

    /// @dev Set staking conditions.
    function _setStakingCondition(uint256 _timeUnit, uint256 _rewardsPerUnitTime) internal virtual {
        require(_timeUnit != 0, "time-unit can't be 0");
        uint256 conditionId = nextConditionId;
        nextConditionId += 1;

        stakingConditions[conditionId] = StakingCondition({
            timeUnit: uint128(_timeUnit),
            rewardsPerUnitTime: uint128(_rewardsPerUnitTime),
            startTimestamp: uint128(block.timestamp),
            endTimestamp: 0
        });

        if (conditionId > 0) {
            stakingConditions[conditionId - 1].endTimestamp = uint128(block.timestamp);
        }
    }

    /// @dev Calculate rewards for a staker.
    function _calculateRewards(address _staker) internal view virtual returns (uint256 _rewards) {
        Staker memory staker = stakers[_staker];

        uint256 _stakerConditionId = staker.conditionIdOflastUpdate;
        uint256 _nextConditionId = nextConditionId;

        for (uint256 i = _stakerConditionId; i < _nextConditionId; i += 1) {
            StakingCondition memory condition = stakingConditions[i];

            uint256 startTime = i != _stakerConditionId ? condition.startTimestamp : staker.timeOfLastUpdate;
            uint256 endTime = condition.endTimestamp != 0 ? condition.endTimestamp : block.timestamp;

            _rewards +=
                ((endTime - startTime) * staker.amountStaked * condition.rewardsPerUnitTime) /
                condition.timeUnit;
        }
    }

    /**
     *  @dev    Mint/Transfer ERC20 rewards to the staker. Must override.
     *
     *  @param _staker    Address for which to calculated rewards.
     *  @param _rewards   Amount of tokens to be given out as reward.
     *
     *  For example, override as below to mint ERC20 rewards:
     *
     * ```
     *  function _mintRewards(address _staker, uint256 _rewards) internal override {
     *
     *      TokenERC20(rewardTokenAddress).mintTo(_staker, _rewards);
     *
     *  }
     * ```
     */
    function _mintRewards(address _staker, uint256 _rewards) internal virtual;

    /**
     *  @dev    Returns whether staking restrictions can be set in given execution context.
     *          Must override.
     *
     *
     *  For example, override as below to restrict access to admin:
     *
     * ```
     *  function _canSetStakeConditions() internal override {
     *
     *      return msg.sender == adminAddress;
     *
     *  }
     * ```
     */
    function _canSetStakeConditions() internal view virtual returns (bool);
}
