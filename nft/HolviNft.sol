pragma solidity 0.6.12;

import "../token/ERC1155.sol";

contract HolviNft is ERC1155Tradable {
    string private _contractURI;

    constructor(address _proxyRegistryAddress) public ERC1155Tradable("Holvi NFT", "HolviNFT", _proxyRegistryAddress) {
        _setBaseMetadataURI("https://api.holvi.finance/nft/");
        // _contractURI = "https://api.smol.finance/studio/tings-erc1155";
    }

    // function setContractURI(string memory newURI) public onlyWhitelistAdmin {
    //     _contractURI = newURI;
    // }

    // function contractURI() public view returns (string memory) {
    //     return _contractURI;
    // }

    /**
         * @dev Ends minting of token
         * @param _id          Token ID for which minting will end
         */
    function endMinting(uint256 _id) external onlyWhitelistAdmin {
        tokenMaxSupply[_id] = tokenSupply[_id];
    }

    function burn(address _account, uint256 _id, uint256 _amount) public onlyMinter {
        require(balanceOf(_account, _id) >= _amount, "cannot burn more than address has");
        _burn(_account, _id, _amount);
    }

    /**
    * Mint NFT and send those to the list of given addresses
    */
    function airdrop(uint256 _id, address[] memory _addresses) public onlyMinter {
        require(tokenMaxSupply[_id] - tokenSupply[_id] >= _addresses.length, "cannot mint above max supply");
        for (uint256 i = 0; i < _addresses.length; i++) {
            mint(_addresses[i], _id, 1, "");
        }
    }
}
