// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721EnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

/// @title FixedTermToken
/// @author RiftWriter
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

        /// @dev lbUSD12M+ logo svg
        string memory image = string(
            abi.encodePacked(
                "data:image/svg+xml;base64,",
                Base64.encode(
                    abi.encodePacked(
                        '<svg width="300" height="300" viewBox="0 0 300 300" fill="none" xmlns="http://www.w3.org/2000/svg">',
                        '<path d="M150 31.0352C215.668 31.0352 268.902 84.2697 268.902 149.938C268.902 215.605 215.668 268.841 150 268.841C84.332 268.841 31.0975 215.605 31.0975 149.938C31.0978 84.2698 84.3321 31.0352 150 31.0352Z" fill="#2D48FF"/> ',
                        '<path d="M142.009 115.69L121.24 115.69L139.009 150L121.24 184.31H189.1L204.379 214.864H84.6208L99.8972 184.31H120.666L102.897 150L120.666 115.69H99.8992L84.6208 85.1358L157.285 85.1357L142.009 115.69Z" fill="white"/> ',
                        '<circle cx="218.975" cy="147.93" r="35.1149" fill="#01E16D" stroke="#2E48FE" stroke-width="5.22981"/> ',
                        '<path d="M238.739 159.03H234.256V151.607H226.51V147.303H234.256V139.736H238.739V147.303H246.449V151.607H238.739V159.03Z" fill="#2E48FE"/> ',
                        '<path d="M202.857 162.268H197.995V143.173H192.5V139.861C196.163 139.755 197.96 139.509 199.158 136.726H202.857V162.268Z" fill="#2E48FE"/> ',
                        '<path d="M215.052 136.268C220.16 136.268 223.437 138.663 223.437 143.137C223.437 147.894 218.786 152.931 210.93 158.181H224.036V162.268H205.258V158.322C213.466 151.734 218.54 147.436 218.54 143.384C218.54 141.129 217.166 139.861 214.77 139.861C212.621 139.861 210.437 141.165 210.437 144.969H205.716C205.61 139.72 209.415 136.268 215.052 136.268Z" fill="#2E48FE"/> ',
                        "</svg> "
                    )
                )
            )
        );

        // attributes 数组（包含 display_type 便于市场展示）
        string memory attributes = string(
            abi.encodePacked(
                "[",
                '{"trait_type":"Product Name","display_type":"string","value": "lbUSD12M+"},',
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
                '"description":"A Cayman Islands-based private equity fund targeting investments in the global renewable energy sector. Puhua Capital serves as the investment general partner, and Ant Financial serves as the technical general partner.",',
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
