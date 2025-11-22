// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721EnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

/// @title FixedTermToken
/// @author Mr.Silent
/// @notice ERC721 token representing fixed-term deposits.
/// @notice This contract is designed to be inherited by FixedTermStaking.
abstract contract FixedTermToken is ERC721EnumerableUpgradeable {
    using Strings for uint256;

    /// @notice Event emitted when a new token is minted
    event Mint(address indexed receiver, uint256 indexed tokenId);
    /// @notice Event emitted when a token is burned
    event Burn(address indexed owner, uint256 indexed tokenId);

    /// @dev tokenId increasing one by one, starting from 1
    uint256 internal _tokenId;

    constructor() {
        _disableInitializers();
    }

    /// @dev initializer instead of constructor for upgradeable contracts
    function __FixedTermToken_init(string memory tokenName, string memory tokenSymbol) internal onlyInitializing {
        __ERC721_init(tokenName, tokenSymbol);
        _tokenId = 1; // Initialize token ID counter
    }

    /// @notice Mint a new NFT
    /// @param receiver_ The address to receive the newly minted NFT
    /// @return The ID of the newly minted NFT
    function mint(address receiver_) internal returns (uint256) {
        require(receiver_ != address(0), "INVALID_TO_ADDRESS");

        emit Mint(receiver_, _tokenId);

        _safeMint(receiver_, _tokenId);

        return _tokenId++;
    }

    /// @notice Burn an existed NFT
    /// @param tokenId_ The ID of the NFT to be burned
    function burn(uint256 tokenId_) internal {
        /// @dev revert if tokenId does not exist
        address owner = ERC721Upgradeable.ownerOf(tokenId_);

        /// @dev revert if caller is not owner or approved
        require(
            ERC721Upgradeable.isApprovedForAll(owner, address(this))
                || ERC721Upgradeable.getApproved(tokenId_) == address(this),
            "NOT_APPROVED"
        );

        super._burn(tokenId_);

        emit Burn(owner, tokenId_);
    }

    /// @notice Get the metadata URI for a given token ID
    /// @param tokenId_ The ID of the token
    /// @return The metadata URI as a string
    function tokenURI(uint256 tokenId_) public view override(ERC721Upgradeable) returns (string memory) {
        if (tokenId_ == 0 || tokenId_ >= _tokenId || _ownerOf(tokenId_) == address(0)) {
            revert ERC721NonexistentToken(tokenId_);
        }

        (uint128 principal, uint64 startDate, uint64 maturityDate) = readFixedTermTokenDetails(tokenId_);

        /// @dev mosUSD12M+ logo svg
        string memory image = string(
            abi.encodePacked(
                "data:image/svg+xml;base64,",
                Base64.encode( 
                    abi.encodePacked('<svg width="800" height="600" xmlns="http://www.w3.org/2000/svg">',
                        '<g>',
                        '<title>Layer 1</title>',
                        '<text fill="#FFAFCC" stroke-width="0" x="290.16313" y="235.37489" id="svg_1" font-size="24" font-family="Noto Sans JP" text-anchor="start" xml:space="preserve" stroke="#000" transform="matrix(5.74209 0 0 5.90761 -1413.14 -1069.99)">MoS</text>',
                        '</g>',
                        '</svg>')
                )
            )
        );

        // attributes 数组（包含 display_type 便于市场展示）
        string memory attributes = string(
            abi.encodePacked(
                "[",
                '{"trait_type":"Product Name","display_type":"string","value": "mosUSD12M+"},',
                '{"trait_type":"Principal (raw)","display_type":"number","value":',
                uint256(principal).toString(),
                "},",
                '{"trait_type":"Start Date (raw)","display_type":"date","value":',
                uint256(startDate).toString(),
                "},",
                '{"trait_type":"Maturity","display_type":"date","value":',
                uint256(maturityDate).toString(),
                "}",
                "]"
            )
        );

        // 组装 metadata JSON
        string memory json = string(
            abi.encodePacked(
                "{",
                '"name":"Fixed Term Deposit #',
                tokenId_.toString(),
                '",',
                '"description":"A Cayman Islands-based private equity fund targeting investments in the global renewable energy sector.",',
                '"image":"',
                image,
                '",',
                '"attributes":',
                attributes,
                "}"
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    /// @notice Abstract method to read fixed-term token details
    /// @param tokenId_ The ID of the token
    /// @return principal_ The principal amount of the fixed-term deposit
    /// @return startDate_ The start date of the fixed-term deposit (as a Unix timestamp)
    /// @return maturityDate_ The maturity date of the fixed-term deposit (as a Unix timestamp)
    function readFixedTermTokenDetails(uint256 tokenId_)
        internal
        view
        virtual
        returns (uint128 principal_, uint64 startDate_, uint64 maturityDate_);

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
