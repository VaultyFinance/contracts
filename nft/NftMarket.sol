pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../Governable.sol";
import "../token/Lantti.sol";
import "./HolviNft.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "../interfaces/IUpgradeSource.sol";
import "../ControllableInit.sol";
import "../upgradability/BaseProxyStorage.sol";

contract NftMarket is ControllableInit, BaseProxyStorage, IUpgradeSource {
    using SafeMath for uint256;

    enum SetKind {
        Unknown,
        Random,
        Redeemable
    }

    event SetAdded(uint256 indexed setId, SetKind kind, uint256 price);
    event SetRemoved(uint256 indexed setId);
    event NftAdded(uint256 indexed setId, uint256[] nftIds, uint256[] amounts);
    event NftRedeemed(address indexed user, uint256 indexed setId, uint256 id, uint256 price);

    struct SetItem {
        uint256 nftId;
        uint256 amountLeft;
    }

    struct Set {
        SetKind kind;
        SetItem[] items;
        uint256 price;
    }

    uint256 public lastSetId;
    HolviNft public nft;
    Lantti public lantti;
    
    mapping(uint256 => Set) public sets;
    mapping(address => uint256) private seeds; // keep individual seed per address

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

    function getSet(uint256 setId) public view returns(Set memory) {
        return sets[setId];
    }

    function removeSet(uint256 setId) public onlyGovernance {
        delete sets[setId];
        emit SetRemoved(setId);
    }

    function addToSet(uint256 setId, uint256[] memory nftIds, uint256[] memory amounts) public onlyGovernance {
        require(amounts.length == nftIds.length, "arrays do not match");

        Set storage set = sets[setId];
        require(set.kind != SetKind.Unknown, "unknown set");

        uint256 length = nftIds.length;
        for (uint256 i = 0; i < length; ++i) {
            set.items.push(SetItem({
                nftId: nftIds[i],
                amountLeft: amounts[i]
            }));
        }

        emit NftAdded(setId, nftIds, amounts);
    }

    function createSet(uint256 price, SetKind kind) public onlyGovernance {
        require(kind == SetKind.Random || kind == SetKind.Redeemable, "incorrect kind");

        uint256 setId = lastSetId.add(1);
        lastSetId = setId;

        Set storage set = sets[setId];
        set.price = price;
        set.kind = kind;

        emit SetAdded(setId, kind, price);
    }

    // Mint 1 random nft from set
    function openSetFor(address user, uint256 setId) public {
        Set storage set = sets[setId];
        require(set.kind == SetKind.Random, "kind incorrect");

        uint256 totalItems = set.items.length;
        require(totalItems > 0, "no items");

        uint256 price = set.price;
        require(
            lantti.balanceOf(msg.sender) >= price,
            "not enough LANTTI to redeem nft"
        );

        uint256 nextIndex = nextRandom(user) % totalItems;

        SetItem memory item = set.items[nextIndex];
        
        require(item.amountLeft > 0, "not enough items"); // should never revert here!

        uint256 nftId = item.nftId;
        require(
            nft.totalSupply(nftId).add(1) <= nft.maxSupply(nftId),
            "max nfts minted"
        );

        item.amountLeft = item.amountLeft.sub(1);

        if (item.amountLeft == 0) {
            // delete item
            set.items[nextIndex] = set.items[totalItems - 1];
            set.items.pop();
        } else {
            set.items[nextIndex].amountLeft = item.amountLeft;
        }

        lantti.burn(msg.sender, price);

        if (nft.isNonFungible(nftId)) {
            nft.mintNft(user, nftId, "");
        } else {
            nft.mintFt(user, nftId, 1, "");
        }
        
        emit NftRedeemed(user, setId, nftId, price);
    }

    function nextRandom(address user) private returns(uint256) {
        uint256 seed = seeds[user];
        if (seed == 0) {
            // initialize seed
            seed = uint256(keccak256(abi.encodePacked(user, block.timestamp)));
        }

        uint256 nextSeed = uint256(keccak256(abi.encodePacked(seed, block.timestamp)));

        seeds[user] = nextSeed;

        return nextSeed;
    }

    function onERC1155Received(
        address _operator,
        address _from,
        uint256 _id,
        uint256 _amount,
        bytes calldata _data
    ) external returns (bytes4) {
        return 0xf23a6e61;
    }

    function onERC1155BatchReceived(
        address _operator,
        address _from,
        uint256[] calldata _ids,
        uint256[] calldata _amounts,
        bytes calldata _data
    ) external returns (bytes4) {
        return 0xbc197c81;
    }

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
