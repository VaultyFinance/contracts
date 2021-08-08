pragma solidity 0.6.12;

import "../token/ERC1155.sol";

contract HolviNft is ERC1155Mintable {
    string private _contractURI;

    constructor(address _proxyRegistryAddress) public ERC1155Mintable("Vaulty NFT", "VaultyNFT", _proxyRegistryAddress) {
        _setBaseMetadataURI("https://api.vaulty.finance/nft/");
    }
    
    /**
         * @dev Ends minting of token
         * @param _id          Token ID for which minting will end
         */
    function endMinting(uint256 _id) external onlyWhitelistAdmin {
        tokenMaxSupply[_id] = tokenSupply[_id];
    }

    function burnFt(address _account, uint256 _id, uint256 _amount) public onlyMinter {
        _burnFungible(_account, _id, _amount);
    }

    function burnNft(address _account, uint256 _id) public onlyMinter {
        _burnNonFungible(_account, _id);
    }

    function airdropFt(uint256 _id, address[] memory _addresses) public onlyMinter {
        require(tokenMaxSupply[_id] - tokenSupply[_id] >= _addresses.length, "cannot mint above max supply");
        for (uint256 i = 0; i < _addresses.length; i++) {
            mintFt(_addresses[i], _id, 1, "");
        }
    }

    function airdropNft(uint256 _type, address[] memory _addresses) public onlyMinter {
        for (uint256 i = 0; i < _addresses.length; i++) {
            mintNft(_addresses[i], _type, "");
        }
    }
}
