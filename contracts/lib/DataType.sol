// SPDX-License-Identifier: BUSL-1.1


pragma solidity 0.8.11;

library DataType {
      
    struct Store {
        Asset asset;
        Groups groups;
        mapping(uint => NftInfo) nftInfoMap; // Maps NFT Id to NftInfo
        uint nextIds; // NFT Id management 
        mapping(address=>Action[]) history; // History management
        Erc721Handler erc721Handler; // Erc721 asset deposit & claiming management
    }

    struct Asset {
        string symbol;
        string deedName;
        address tokenAddress;
        AssetType tokenType;
        uint tokenId; // Specific for ERC1155 type of asset only
    }

    struct Groups {
        Group[] items;
        uint vestingStartTime; // Global timestamp for vesting to start
    }
    
    struct GroupInfo {
        string name;
        uint totalEntitlement; // Total tokens to be distributed to this group
    }

    struct GroupState {
        bool verified;
        bool finalized;
    }

    struct Group {
        GroupInfo info;
        VestingItem[] vestItems;
        bytes32 merkleRoot; // Deed Claims using Merkle tree
        mapping(uint => uint) deedClaimMap;
        GroupState state;
    }

    struct Erc721Handler {
        uint[] erc721IdArray;
        mapping(uint => bool) idExistMap;
        uint erc721NextClaimIndex;
        uint numErc721TransferedOut;
        uint numUsedByVerifiedGroups;
    }

    struct NftInfo {
        uint groupId;
        uint totalEntitlement; 
        uint totalClaimed;
        bool valid;
    }  

    struct VestingItem {
        VestingReleaseType releaseType;
        uint delay;
        uint duration;
        uint percent;
    }
    
    struct Action {
        uint128     actionType;
        uint128     time;
        uint256     data1;
        uint256     data2;
    }
   
    struct History {
        mapping(address=>Action[]) investor;
        Action[] campaignOwner;
    }
    
    // ENUMS
    enum AssetType {
        ERC20,
        ERC1155,
        ERC721
    }

    enum VestingReleaseType {
        LumpSum,
        Linear,
        Unsupported
    }

    enum ActionType {
        AppendGroups,
        DefineVesting,
        UploadUsersData,
        SetAssetAddress,
        VerifyGroup,
        FinalizeGroupFundIn,
        FinalizeGroupWithoutFundIn,
        StartVesting,
        ClaimDeed,
        ClaimTokens
    }
}


    