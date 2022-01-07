// SPDX-License-Identifier: BUSL-1.1


pragma solidity 0.8.11;

library DataType {
      
    struct Store {
        Asset asset;
        Groups groups;
        mapping(uint => NftInfo) nftInfoMap; // Maps NFT Id to NftInfo
        uint nextIds; // NFT Id management 
        mapping(address=>Action[]) history; // History management
    }

    struct Asset {
        string symbol;
        string deedName;
        address tokenAddress;
        AssetType tokenType;

        // ERC1155 specific
        uint tokenId;

        // ERC721 specific
        uint[] erc721IdArray;
        uint erc721NextClaimIndex;
        uint numErc721TransferedOut;
    }

    struct Groups {
        Group[] items;
        uint vestingStartTime; // The global timestamp for vesting to start //
    }
    
    struct GroupInfo {
        string name;
        uint totalShares; // This is the raised amount for this group
        uint totalTokens; // This is the total tokens to be distributed to this group
    }

    struct GroupState {
        bool verified;
        bool finalized;
    }

    struct Group {
    
        // General info
        GroupInfo info;

        // Vesting
        VestingItem[] vestItems;

        // Deed Claims
        bytes32 merkleRoot;
        mapping(uint => uint) deedClaimMap;

        // States
        GroupState state;
    }

    struct NftInfo {
        uint groupId;
        uint shares;
        uint tokenClaimed;
        bool valid;
    }  

    struct VestingItem {
        VestingReleaseType releaseType;
        uint delay;
        uint duration;
        uint percent;
    }
    
    // History
    enum ActionType {
        AppendGroups,
        DefineVesting,
        UploadUsersData,
        SetAssetAddress,
        VerifyGroup,
        FinalizeGroupWithoutFundIn,
        FinalizeGroupFundIn,
        StartVesting,
        ClaimDeed,
        ClaimTokens
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
}


    