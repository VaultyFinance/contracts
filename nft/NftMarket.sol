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

    event CollectionAdded(uint256 indexed collectionId, uint256[] nftIds, uint256 price);
    event CollectionRemoved(uint256 indexed collectionId);
    event NftRedeemed(address indexed user, uint256 indexed collectionId, uint256 id, uint256 price);
    // event NftRedeemedMultiple(address indexed user, uint256 indexed collectionId, uint256[] ids, uint256[] amounts, uint256 totalCost);

    struct CollectionItem {
        uint256 nftId;
        uint256 amountLeft;
    }

    struct Collection {
        CollectionItem[] items;
        uint256 price;
    }

    uint256 public lastCollectionId;
    HolviNft public nft;
    Lantti public lantti;
    
    mapping(uint256 => Collection) public collections;
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

    function getCollection(uint256 collectionId) public view returns(Collection memory) {
        return collections[collectionId];
    }

    function removeCollection(uint256 collectionId) public onlyGovernance {
        delete collections[collectionId];
        emit CollectionRemoved(collectionId);
    }

    function addCollection(uint256[] memory nftIds, uint256[] memory amounts, uint256 price) public onlyGovernance {
        require(amounts.length == nftIds.length, "arrays do not match");

        uint256 collectionId = lastCollectionId.add(1);
        lastCollectionId = collectionId;

        Collection storage collection = collections[collectionId];
        collection.price = price;

        uint256 length = nftIds.length;
        for (uint256 i = 0; i < length; ++i) {
            collection.items.push(CollectionItem({
                nftId: nftIds[i],
                amountLeft: amounts[i]
            }));
        }

        emit CollectionAdded(collectionId, nftIds, price);
    }

    // Mint 1 random nft from collection directly to the user wallet
    function redeemFor(address user, uint256 collectionId) public {
        Collection storage collection = collections[collectionId];

        uint256 totalItems = collection.items.length;
        require(totalItems > 0, "no items");

        uint256 nextIndex = nextRandom(user) % totalItems;

        CollectionItem memory item = collection.items[nextIndex];
        
        require(item.amountLeft > 0, "not enough items"); // should never revert here!

        item.amountLeft = item.amountLeft.sub(1);

        if (item.amountLeft == 0) {
            // delete item
            collection.items[nextIndex] = collection.items[totalItems - 1];
            collection.items.pop();
        } else {
            collection.items[nextIndex].amountLeft = item.amountLeft;
        }

        uint256 nftId = item.nftId;
        uint256 price = collection.price;
        require(
            lantti.balanceOf(msg.sender) >= price,
            "not enough LANTTI to redeem nft"
        );
        require(
            nft.totalSupply(nftId).add(1) <= nft.maxSupply(nftId),
            "max nfts minted"
        );

        lantti.burn(msg.sender, price);
        nft.mint(user, nftId, 1, "");
        emit NftRedeemed(user, collectionId, nftId, price);
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

    // Transfer multiple nfts from Mart to the user wallet (need the nfts to be minted to market first)
    // function transferMultiple(uint256 collectionId, uint256[] memory _nftIds, uint256[] memory _amounts) public {
    //     require(_nftIds.length == _amounts.length, "arrays do not match");

    //     Collection storage collection = collections[collectionId];
    //     uint256 price = collection.price;

    //     uint256 totalCost = 0;
    //     for (uint256 i = 0; i < _nftIds.length; ++i) {
    //         uint256 nftId = _nftIds[i];
    //         uint256 redeemAmount = _amounts[i];
    //         uint256 nftAmount = collection.nfts[nftId];

    //         require(nftAmount >= redeemAmount, "nft not found");

    //         totalCost = totalCost.add(price.mul(redeemAmount));
    //         collection.nfts[nftId] = nftAmount.sub(redeemAmount);
    //     }

    //     require(lantti.balanceOf(msg.sender) >= totalCost, "not enough LANTTI to redeem nfts");

    //     lantti.burn(msg.sender, totalCost);
    //     nft.safeBatchTransferFrom(address(this), msg.sender, _nftIds, _amounts, "");
    //     emit NftRedeemedMultiple(msg.sender, collectionId, _nftIds, _amounts, totalCost);
    // }

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
