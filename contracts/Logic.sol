//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

abstract contract LendingBorrowLogic is IERC20, ERC1155 {
    using Address for address payable;

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

    mapping(uint256 => uint256) public idToTokenPrice;
    mapping(uint256 => uint256) public idToLastUpdate;
    mapping(uint256 => uint256) public idToBorrowedAmount;
    mapping(uint256 => IERC20) public idToFractionalized;
    mapping(uint256 => bool) public idHasBeenRepaid;

    function applyInterest(uint256 id, uint256 interestPerEthPerDay)
        internal
        returns (uint256 newBorrowedAmount)
    {
        uint256 elapsedTime;
        unchecked {
            elapsedTime = block.timestamp - idToLastUpdate[id];
        }
        idToLastUpdate[id] = block.timestamp;
        uint256 oldBorrowedAmount = idToBorrowedAmount[id];
        if (oldBorrowedAmount == 0) {
            return 0;
        }
        newBorrowedAmount =
            oldBorrowedAmount +
            ((oldBorrowedAmount * interestPerEthPerDay * elapsedTime) /
                (1 days * 1e18));
        idToTokenPrice[id] =
            (idToTokenPrice[id] * newBorrowedAmount) /
            oldBorrowedAmount;
    }

    function moveNFT(
        address nftContract,
        uint256 nftId,
        address from,
        address to,
        bool isERC721
    ) internal {
        if (isERC721) {
            IERC721(nftContract).safeTransferFrom(from, to, nftId);
        } else {
            IERC1155(nftContract).safeTransferFrom(from, to, nftId, 1, "");
        }
    }

    function getId(
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

    function repay(
        address nftContract,
        uint256 nftId,
        uint256 endTime,
        uint256 borrowCeiling,
        uint256 interestPerEthPerDay,
        bool isERC721
    ) external payable {
        // only allow repayment before expiration?
        uint256 id = getId(
            nftContract,
            nftId,
            endTime,
            borrowCeiling,
            interestPerEthPerDay
        );
        uint256 amountToRepay = applyInterest(id, interestPerEthPerDay);
        _burn(msg.sender, id, 1);
        payable(msg.sender).sendValue(msg.value - amountToRepay);
        idHasBeenRepaid[id] = true;

        moveNFT(nftContract, nftId, address(this), msg.sender, isERC721);
    }

    function lenderTokenId(uint256 id) internal pure returns (uint256) {
        unchecked {
            return id + 1;
        }
    }

    function lend(
        address nftContract,
        uint256 nftId,
        uint256 endTime,
        uint256 borrowCeiling,
        uint256 interestPerEthPerDay,
        address payable currentOwner
    ) external payable {
        uint256 id = getId(
            nftContract,
            nftId,
            endTime,
            borrowCeiling,
            interestPerEthPerDay
        );
        uint256 newBorrowedAmount = applyInterest(id, interestPerEthPerDay) +
            msg.value;
        require(newBorrowedAmount < borrowCeiling, "max borrow");
        idToBorrowedAmount[id] = newBorrowedAmount;
        currentOwner.sendValue(msg.value);
        require(balanceOf(currentOwner, id) == 1, "wrong owner");
        _mint(
            msg.sender,
            lenderTokenId(id),
            (msg.value * 1e18) / idToTokenPrice[id],
            ""
        );
    }

    function getUnderlyingBalance(uint256 id, address account)
        public
        view
        returns (uint256 depositTokensOwned, uint256 ethWithInterest)
    {
        depositTokensOwned = balanceOf(account, lenderTokenId(id));
        ethWithInterest = (depositTokensOwned * idToTokenPrice[id]) / 1e18;
    }

    function recoverEth(uint256 id) external {
        require(idHasBeenRepaid[id] == true, "not repaid");
        (
            uint256 depositTokensOwned,
            uint256 ethWithInterest
        ) = getUnderlyingBalance(id, msg.sender);
        _burn(msg.sender, lenderTokenId(id), depositTokensOwned);
        payable(msg.sender).sendValue(ethWithInterest);
    }
}
