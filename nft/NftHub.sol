pragma solidity 0.6.12;

import "../Governable.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "../token/Lantti.sol";
import "./HolviNft.sol";
import "./LanttiPools.sol";
import "./INftHub.sol";
import "../interfaces/IUpgradeSource.sol";
import "../ControllableInit.sol";
import "../upgradability/BaseProxyStorage.sol";

/**
 * @dev Contract for handling the NFT staking and set creation.
 */
contract NftHub is ControllableInit, BaseProxyStorage, IUpgradeSource, INftHub {
    using SafeMath for uint256;

    uint256 constant BONUS_PRECISION = 10**5;
    uint256 internal constant TYPE_MASK = uint256(uint128(~0)) << 128;

    event Stake(address indexed user, uint256[] nftIds);
    event Unstake(address indexed user, uint256[] nftIds);
    event Harvest(address indexed user, uint256 amount);

    struct NftSet {
        uint256[] nftIds;
        uint256 lanttiPerDayPerNft;
        uint256 bonusLanttiMultiplier;
        uint256[] poolBoosts; // Applicable if isBooster is true.Eg: [0,20000] = 0% boost for pool 1, 20% boost for pool 2
        uint256 bonusFullSetBoost; // Gives an additional boost if you stake all boosters of that set.
        bool isRemoved;
        bool isBooster; // False if the nft set doesn't give pool boost at lanttiPools
    }

    HolviNft public nft;
    Lantti public lantti;
    LanttiPools public lanttiPools;

    uint256[] public nftSetList;
    //SetId mapped to all nft IDs in the set.
    mapping(uint256 => NftSet) public nftSets;
    //NftId to SetId mapping
    mapping(uint256 => uint256) public nftToSetId;
    mapping(uint256 => uint256) public maxNftStake;
    //Status of user's nfts staked mapped to the nftID
    mapping(address => mapping(uint256 => uint256)) public userNfts;
    //Last update time for a user's LANTTI rewards calculation
    mapping(address => uint256) public userLastUpdate;
    //Mapping data of booster of a user in a pool. 100% booster
    mapping(address => uint256) public boosterInfo;

    constructor() public {}

    function initialize(
        address _storage,
        HolviNft _nft,
        Lantti _lantti
    ) public initializer {
        ControllableInit.initialize(_storage);

        nft = _nft;
        lantti = _lantti;
    }

    function setLanttiPools(LanttiPools _lanttiPools) public onlyGovernance {
        lanttiPools = _lanttiPools;
    }

    function setMultiplierOfAddress(address _address, uint256 _booster) public onlyGovernance {
        boosterInfo[_address] = _booster;
    }

    /**
     * @dev Utility function to check if a value is inside an array
     */
    function _isInArray(uint256 _value, uint256[] storage _array) internal view returns (bool) {
        uint256 length = _array.length;
        for (uint256 i = 0; i < length; ++i) {
            if (_array[i] == _value) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Indexed boolean for whether a nft is staked or not. Index represents the nftId.
     */
    // function getNftsStakedOfAddress(address _user) public view returns (bool[] memory) {
    //     bool[] memory nftsStaked = new bool[](highestNftId + 1);
    //     for (uint256 i = 0; i < highestNftId + 1; ++i) {
    //         nftsStaked[i] = userNfts[_user][i];
    //     }
    //     return nftsStaked;
    // }

    /**
     * @dev Returns the list of nftIds which are part of a set
     */
    function getNftIdListOfSet(uint256 _setId) external view returns (uint256[] memory) {
        return nftSets[_setId].nftIds;
    }

    /**
     * @dev Returns the boosters associated with a nft Id per pool
     */
    function getBoostersOfNft(uint256 _nftId) external view returns (uint256[] memory) {
        return nftSets[nftToSetId[_nftId]].poolBoosts;
    }

    /**
     * @dev Indexed  boolean of each setId for which a user has a full set or not.
     */
    function getFullSetsOfAddress(address _user) public view returns (bool[] memory) {
        uint256 length = nftSetList.length;
        bool[] memory isFullSet = new bool[](length);
        for (uint256 i = 0; i < length; ++i) {
            uint256 setId = nftSetList[i];
            if (nftSets[setId].isRemoved) {
                isFullSet[i] = false;
                continue;
            }
            bool _fullSet = true;
            uint256[] memory _nftIds = nftSets[setId].nftIds;

            for (uint256 j = 0; j < _nftIds.length; ++j) {
                if (userNfts[_user][_nftIds[j]] == 0) {
                    _fullSet = false;
                    break;
                }
            }
            isFullSet[i] = _fullSet;
        }
        return isFullSet;
    }

    /**
     * @dev Returns the amount of NFTs staked by an address for a given set
     */
    function getNumOfNftsStakedForSet(address _user, uint256 _setId) public view returns (uint256) {
        uint256 nbStaked = 0;
        NftSet storage set = nftSets[_setId];
        if (set.isRemoved) {
            return 0;
        }

        uint256 length = set.nftIds.length;
        for (uint256 j = 0; j < length; ++j) {
            uint256 nftId = set.nftIds[j];
            if (userNfts[_user][nftId] != 0) {
                nbStaked = nbStaked.add(1);
            }
        }
        return nbStaked;
    }

    /**
     * @dev Returns the total amount of NFTs staked by an address across all sets
     */
    function getNumOfNftsStakedByAddress(address _user) public view returns (uint256) {
        uint256 nbStaked = 0;
        for (uint256 i = 0; i < nftSetList.length; ++i) {
            nbStaked = nbStaked.add(getNumOfNftsStakedForSet(_user, nftSetList[i]));
        }
        return nbStaked;
    }

    /**
     * @dev Returns the total lantti pending for a given address. Can include the bonus from NFT boosters,
     * if second param is set to true.
     */
    function totalPendingLanttiOfAddress(address _user, bool _includeLanttiBooster)
        public
        view
        returns (uint256)
    {
        uint256 totalLanttiPerDay = 0;
        uint256 length = nftSetList.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 setId = nftSetList[i];

            NftSet storage set = nftSets[setId];
            if (set.isRemoved) {
                continue;
            }

            uint256 nftLength = set.nftIds.length;
            bool isFullSet = true;
            uint256 setLanttiPerDay = 0;

            for (uint256 j = 0; j < nftLength; ++j) {
                uint256 nftsStaked = userNfts[_user][set.nftIds[j]];
                if (nftsStaked == 0) {
                    isFullSet = false;
                    continue;
                }
                setLanttiPerDay = setLanttiPerDay.add(set.lanttiPerDayPerNft.mul(nftsStaked));
            }

            if (isFullSet) {
                setLanttiPerDay = setLanttiPerDay
                    .mul(set.bonusLanttiMultiplier.add(BONUS_PRECISION))
                    .div(BONUS_PRECISION);
            }

            totalLanttiPerDay = totalLanttiPerDay.add(setLanttiPerDay);
        }

        if (_includeLanttiBooster) {
            uint256 boostMult = boosterInfo[_user].add(BONUS_PRECISION);
            totalLanttiPerDay = totalLanttiPerDay.mul(boostMult).div(BONUS_PRECISION);
        }

        uint256 lastUpdate = userLastUpdate[_user];
        uint256 blockTime = block.timestamp;

        return blockTime.sub(lastUpdate).mul(totalLanttiPerDay.div(24 hours));
    }

    /**
     * @dev Returns the applicable booster of a user, for a pool, from a staked NFT set.
     */
    function getBoosterForUser(address _user, uint256 _pid)
        external
        view
        override
        returns (uint256)
    {
        _pid = _pid.sub(1);

        uint256 totalBooster = 0;
        uint256 length = nftSetList.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 setId = nftSetList[i];
            NftSet storage set = nftSets[setId];
            if (!set.isBooster) {
                continue;
            }

            if (set.poolBoosts.length < _pid.add(1)) {
                continue;
            }

            if (set.poolBoosts[_pid] == 0) {
                continue;
            }

            uint256 nftLength = set.nftIds.length;
            bool isFullSet = true;
            uint256 setBooster = 0;

            for (uint256 j = 0; j < nftLength; ++j) {
                uint256 nftsStaked = userNfts[_user][set.nftIds[j]];
                if (nftsStaked == 0) {
                    isFullSet = false;
                    continue;
                }

                setBooster = setBooster.add(set.poolBoosts[_pid].mul(maxNftStake[nftsStaked]));
            }

            if (isFullSet) {
                setBooster = setBooster.add(set.bonusFullSetBoost);
            }

            totalBooster = totalBooster.add(setBooster);
        }
        return totalBooster;
    }

    /**
     * @dev Manually sets the highestNftId, if it goes out of sync.
     * Required calculate the range for iterating the list of staked nfts for an address.
     */
    // function setHighestNftId(uint256 _highestId) public onlyGovernance {
    //     require(_highestId > 0, "Set if minimum 1 nft is staked.");
    //     highestNftId = _highestId;
    // }

    /**
     * @dev Adds a nft set with the input param configs. Removes an existing set if the id exists.
     */
    function addNftSet(
        uint256 _setId,
        uint256[] memory _nftIds,
        uint256[] memory _max,
        uint256 _bonusLanttiMultiplier,
        uint256 _lanttiPerDayPerNft,
        uint256[] memory _poolBoosts,
        uint256 _bonusFullSetBoost,
        bool _isBooster
    ) public onlyGovernance {
        require(_nftIds.length == _max.length);

        removeNftSet(_setId);
        uint256 length = _nftIds.length;

        for (uint256 i = 0; i < length; ++i) {
            uint256 nftId = _nftIds[i];

            // Check all nfts to assign arent already part of another set
            require(nftToSetId[nftId] == 0, "Nft already assigned to a set");
            // Assign to set
            nftToSetId[nftId] = _setId;
            maxNftStake[nftId] = _max[i];
        }

        if (!_isInArray(_setId, nftSetList)) {
            nftSetList.push(_setId);
        }

        nftSets[_setId] = NftSet({
            nftIds: _nftIds,
            bonusLanttiMultiplier: _bonusLanttiMultiplier,
            lanttiPerDayPerNft: _lanttiPerDayPerNft,
            poolBoosts: _poolBoosts,
            bonusFullSetBoost: _bonusFullSetBoost,
            isRemoved: false,
            isBooster: _isBooster
        });
    }

    /**
     * @dev Updates the lanttiPerDayPerNft for a nft set.
     */
    function setLanttiRateOfSets(uint256[] memory _setIds, uint256[] memory _lanttiPerDayPerNft)
        public
        onlyGovernance
    {
        require(
            _setIds.length == _lanttiPerDayPerNft.length,
            "_setId and _lanttiPerDayPerNft have different length"
        );

        for (uint256 i = 0; i < _setIds.length; ++i) {
            require(nftSets[_setIds[i]].nftIds.length > 0, "Set is empty");
            nftSets[_setIds[i]].lanttiPerDayPerNft = _lanttiPerDayPerNft[i];
        }
    }

    /**
     * @dev Set the bonusLanttiMultiplier value for a list of Nft sets
     */
    function setBonusLanttiMultiplierOfSets(
        uint256[] memory _setIds,
        uint256[] memory _bonusLanttiMultiplier
    ) public onlyGovernance {
        require(
            _setIds.length == _bonusLanttiMultiplier.length,
            "_setId and _lanttiPerDayPerNft have different length"
        );
        for (uint256 i = 0; i < _setIds.length; ++i) {
            require(nftSets[_setIds[i]].nftIds.length > 0, "Set is empty");
            nftSets[_setIds[i]].bonusLanttiMultiplier = _bonusLanttiMultiplier[i];
        }
    }

    /**
     * @dev Remove a nftSet that has been added.
     * !!!  Warning : if a booster set is removed, users with the booster staked will continue to benefit from the multiplier  !!!
     */
    function removeNftSet(uint256 _setId) public onlyGovernance {
        uint256 length = nftSets[_setId].nftIds.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 nftId = nftSets[_setId].nftIds[i];
            nftToSetId[nftId] = 0;
        }
        delete nftSets[_setId].nftIds;
        nftSets[_setId].isRemoved = true;
        nftSets[_setId].isBooster = false;
    }

    /**
     * @dev Harvests the accumulated LANTTI in the contract, for the caller.
     */
    function harvest() public {
        uint256 pendingLantti = totalPendingLanttiOfAddress(msg.sender, true);
        userLastUpdate[msg.sender] = block.timestamp;
        if (pendingLantti > 0) {
            lantti.mint(msg.sender, pendingLantti);
        }
        emit Harvest(msg.sender, pendingLantti);
    }

    /**
     * @dev Stakes the nfts on providing the nft IDs.
     */
    function stake(uint256[] memory _nftIds) public {
        stakeAction(_nftIds, true);
    }

    /**
     * @dev Unstakes the nfts on providing the nft IDs.
     */
    function unstake(uint256[] memory _nftIds) public {
        stakeAction(_nftIds, false);
    }

    function stakeAction(uint256[] memory _nftIds, bool stake) private {
        require(_nftIds.length > 0, "you need to stake something");

        // Check no nft will end up above max stake and if it is needed to update the user NFT pool
        uint256 length = _nftIds.length;
        bool hasLanttis = false;
        bool onlyNoBoosters = true;
        uint256 setId;
        uint256 nftType;
        NftSet storage nftSet;

        for (uint256 i = 0; i < length; ++i) {
            nftType = extractType(_nftIds[i]);
            setId = nftToSetId[nftType];

            require(setId != 0, "unknown set");

            if (stake) {
                require(userNfts[msg.sender][nftType] <= maxNftStake[nftType], "max staked");
                userNfts[msg.sender][nftType]++;
            } else {
                require(userNfts[msg.sender][nftType] != 0, "not staked");
                userNfts[msg.sender][nftType]--;
            }

            if (nftSets[setId].lanttiPerDayPerNft > 0) {
                hasLanttis = true;
            }

            if (nftSets[setId].isBooster) {
                onlyNoBoosters = false;
            }
        }

        // Harvest NFT pool if the LANTTI/day will be modified
        if (hasLanttis) {
            harvest();
        }

        // Harvest each pool where booster value will be modified
        if (!onlyNoBoosters) {
            for (uint256 i = 0; i < length; ++i) {
                nftType = extractType(_nftIds[i]);
                setId = nftToSetId[nftType];

                if (nftSets[setId].isBooster) {
                    nftSet = nftSets[setId];
                    uint256 boostLength = nftSet.poolBoosts.length;
                    for (uint256 j = 1; j <= boostLength; ++j) {
                        // pool ID starts from 1
                        if (
                            nftSet.poolBoosts[j - 1] > 0 &&
                            lanttiPools.pendingLantti(j, msg.sender) > 0
                        ) {
                            address staker = msg.sender;
                            lanttiPools.withdraw(j, 0, staker);
                        }
                    }
                }
            }
        }

        //Stake 1 unit of each nftId
        uint256[] memory amounts = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = 1;
        }

        if (stake) {
            nft.safeBatchTransferFrom(msg.sender, address(this), _nftIds, amounts, "");
            emit Stake(msg.sender, _nftIds);
        } else {
            nft.safeBatchTransferFrom(address(this), msg.sender, _nftIds, amounts, "");
            emit Unstake(msg.sender, _nftIds);
        }
    }

    /**
     * @dev Emergency unstake the nfts on providing the nft IDs, forfeiting the LANTTI rewards in both Hub and LanttiPools.
     */
    function emergencyUnstake(uint256[] memory _nftIds) public {
        userLastUpdate[msg.sender] = block.timestamp;

        uint256[] memory amounts = new uint256[](_nftIds.length);
        uint256 length = _nftIds.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 nftType = extractType(_nftIds[i]);

            uint256 nftsStaked = userNfts[msg.sender][nftType];
            require(nftsStaked != 0, "Nft not staked");

            amounts[i] = 1;
            userNfts[msg.sender][nftType]--;
        }

        nft.safeBatchTransferFrom(address(this), msg.sender, _nftIds, amounts, "");
    }

    // update pot address if the pot logic changed.
    function updateLanttiPoolsAddress(LanttiPools _pools) public onlyGovernance {
        lanttiPools = _pools;
    }

    function extractType(uint256 nftId) private pure returns (uint256) {
        return nftId & TYPE_MASK;
    }

    /**
     * @notice Handle the receipt of a single ERC1155 token type
     * @dev An ERC1155-compliant smart contract MUST call this function on the token recipient contract, at the end of a `safeTransferFrom` after the balance has been updated
     * This function MAY throw to revert and reject the transfer
     * Return of other amount than the magic value MUST result in the transaction being reverted
     * Note: The token contract address is always the message sender
     * @param _operator  The address which called the `safeTransferFrom` function
     * @param _from      The address which previously owned the token
     * @param _id        The id of the token being transferred
     * @param _amount    The amount of tokens being transferred
     * @param _data      Additional data with no specified format
     * @return           `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
     */
    function onERC1155Received(
        address _operator,
        address _from,
        uint256 _id,
        uint256 _amount,
        bytes calldata _data
    ) external returns (bytes4) {
        return 0xf23a6e61;
    }

    /**
     * @notice Handle the receipt of multiple ERC1155 token types
     * @dev An ERC1155-compliant smart contract MUST call this function on the token recipient contract, at the end of a `safeBatchTransferFrom` after the balances have been updated
     * This function MAY throw to revert and reject the transfer
     * Return of other amount than the magic value WILL result in the transaction being reverted
     * Note: The token contract address is always the message sender
     * @param _operator  The address which called the `safeBatchTransferFrom` function
     * @param _from      The address which previously owned the token
     * @param _ids       An array containing ids of each token being transferred
     * @param _amounts   An array containing amounts of each token being transferred
     * @param _data      Additional data with no specified format
     * @return           `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
     */
    function onERC1155BatchReceived(
        address _operator,
        address _from,
        uint256[] calldata _ids,
        uint256[] calldata _amounts,
        bytes calldata _data
    ) external returns (bytes4) {
        return 0xbc197c81;
    }

    /**
     * @notice Indicates whether a contract implements the `ERC1155TokenReceiver` functions and so can accept ERC1155 token types.
     * @param  interfaceID The ERC-165 interface ID that is queried for support.s
     * @dev This function MUST return true if it implements the ERC1155TokenReceiver interface and ERC-165 interface.
     *      This function MUST NOT consume more than 5,000 gas.
     * @return Wheter ERC-165 or ERC1155TokenReceiver interfaces are supported.
     */
    function supportsInterface(bytes4 interfaceID) external view returns (bool) {
        return
            interfaceID == 0x01ffc9a7 || // ERC-165 support (i.e. `bytes4(keccak256('supportsInterface(bytes4)'))`).
            interfaceID == 0x4e2312e0; // ERC-1155 `ERC1155TokenReceiver` support (i.e. `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")) ^ bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`).
    }

    function scheduleUpgrade(address impl) public onlyGovernance {
        _setNextImplementation(impl);
        _setNextImplementationTimestamp(block.timestamp.add(nextImplementationDelay()));
    }

    function shouldUpgrade() external view override returns (bool, address) {
        return (
            nextImplementationTimestamp() != 0 &&
                block.timestamp > nextImplementationTimestamp() &&
                nextImplementation() != address(0),
            nextImplementation()
        );
    }

    function finalizeUpgrade() external override onlyGovernance {
        _setNextImplementation(address(0));
        _setNextImplementationTimestamp(0);
    }
}
