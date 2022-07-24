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

    /**
     * @dev returns the token id of the NFT corresponding to the details passed as param.
     * @param nftContract address of the NFT contract.
     * @param nftId token id of the borrower's NFT.
     * @param endTime the end date for the loan.
     * @param debtCeiling the debt ceiling of the loan expected by the borrower.
     * @param interestRate expected interest rate of the loan by the borrower.
     */
    function getTokenId(
        address nftContract,
        uint256 nftId,
        uint256 endTime,
        uint256 debtCeiling,
        uint256 interestRate
    ) public pure returns (uint256 id) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        nftContract,
                        nftId,
                        endTime,
                        debtCeiling,
                        interestRate
                    )
                )
            );
    }

    /**
     * @dev creates an NFT with details of the loan and assigns them to borrower until a loan offer is accepted.
     * @param owner NFT owner
     * @param nftContract address of the NFT
     * @param nftId NFT id
     * @param endTime the time of the loan repayment
     * @param debtCeiling debt ceiling set by the borrower 
     * @param interestRate the rate of the loan
     */
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

    /**
     * @dev id for lender's NFT 
     * @param id previous id
     */
    function lenderTokenId(uint256 id) internal pure returns (uint256) {
        unchecked {
            return id + 1;
        }
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

    function onERC1155Received(
        address _operator,
        address _from,
        uint256 _id,
        uint256 _value,
        bytes calldata _data
    ) external returns (bytes4) {
        require(_value == 1);
        onERC721Received(_operator, _from, _id, _data);
        return this.onERC1155Received.selector;
    }
}

contract NFTCollateral is NFTEscrow {
    string public name = "nft-collateral-v1.0";
}
