//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

abstract contract NFTEscrow is ERC1155, IERC721Receiver {
    mapping(uint256 => uint256) public idToTokenPrice;

    constructor() ERC1155("https://api.nftColl.fi/nft-lend/v1/{id}.json") {}

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155)
        returns (bool)
    {
        return
            ERC1155.supportsInterface(interfaceId) ||
            interfaceId == type(IERC1155Receiver).interfaceId;
    }

    function getTokenId(
        address nftContract,
        uint256 nftId,
        uint256 endTime,
        uint256 borrowCeiling,
        uint256 interest
    ) public pure returns (uint256 id) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        nftContract,
                        nftId,
                        endTime,
                        borrowCeiling,
                        interest
                    )
                )
            );
    }

    function create(
        address owner,
        address nftContract,
        uint256 nftId,
        uint256 endTime,
        uint256 debtCeiling,
        uint256 interestRate
    ) internal {
        uint256 id = getTokenId(
            nftContract,
            nftId,
            endTime,
            debtCeiling,
            interestRate
        );
        require(idToTokenPrice[id] == 0, "used");
        idToTokenPrice[id] = 1e18;
        _mint(owner, id, 1, "");
    }

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    ) public override returns (bytes4) {
        (uint256 endTime, uint256 debtCeiling, uint256 interestRate) = abi
            .decode(_data, (uint256, uint256, uint256));
        create(
            _operator,
            msg.sender,
            _tokenId,
            endTime,
            debtCeiling,
            interestRate
        );
        return this.onERC721Received.selector;
    }
}

contract NFTBank is NFTEscrow {
    string public name = "nft-bank-v1.0";
}
