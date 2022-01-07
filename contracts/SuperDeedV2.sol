// SPDX-License-Identifier: BUSL-1.1


pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./core/DataStore.sol";
import "./logic/Vesting.sol";
import "./interfaces/IEmergency.sol";


contract SuperDeedV2 is ERC721Enumerable, IEmergency, ERC1155Holder, ERC721Holder, DataStore, ReentrancyGuard {

    using SafeERC20 for IERC20;
    using MerkleClaims for DataType.Group;
    using Groups for *;
    using Vesting for *;

    string private constant SUPER_DEED = "SuperDeed";
    string private constant BASE_URI = "https://superlauncher.io/metadata/";

    constructor(
        IRoleAccess roles,
        address projectOwnerAddress, 
        string memory tokenSymbol, 
        string memory deedName
    ) 
        ERC721(deedName, SUPER_DEED)  
        DataStore(roles, projectOwnerAddress)
    {
        _setAsset(tokenSymbol, deedName);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable, ERC1155Receiver) returns (bool) {
        return ERC721Enumerable.supportsInterface(interfaceId) || 
            ERC1155Receiver.supportsInterface(interfaceId);
    }

    function tokenURI(uint256 /*tokenId*/) public view virtual override returns (string memory) {
        return  string(abi.encodePacked(BASE_URI, _store().asset.deedName));
    }

    
    function onERC721Received( address operator, address , uint256 tokenId , bytes memory ) public virtual override returns (bytes4) {
        
        // When ERC721 asset is transfered into this deed, it is saved up in erc721IdArray
        require(_asset().tokenAddress != Constant.ZERO_ADDRESS, "Asset address not yet set");
        if (_asset().tokenType == DataType.AssetType.ERC721 && operator == _asset().tokenAddress) {
            _asset().erc721IdArray.push(tokenId);
        }
        return this.onERC721Received.selector;
    }
    
    //--------------------//
    //   SETUP & CONFIG   //
    //--------------------//

    function appendGroups(string[] memory names) external notLive onlyProjectOwnerOrConfigurator {
        uint added = _groups().appendGroups(names);
        _recordHistory(DataType.ActionType.AppendGroups, added);
    }

    function defineVesting(uint groupId, string memory groupName, DataType.VestingItem[] calldata vestItems) external  notLive onlyProjectOwnerOrConfigurator {    
        _groups().validateGroup(groupId, groupName);
        uint added = _groups().defineVesting(groupId, vestItems);
        _recordHistory(DataType.ActionType.DefineVesting, added);
    }

    function uploadUsersData(uint groupId, string memory groupName, bytes32 merkleRoot, uint totalShares, uint totalTokens) external  notLive onlyProjectOwnerOrConfigurator {   
        _groups().uploadUsersData(groupId, groupName, merkleRoot, totalShares, totalTokens);
        _recordHistory(DataType.ActionType.UploadUsersData, groupId, totalTokens);
    }

    function setAssetDetails(address tokenAddress, DataType.AssetType tokenType, uint tokenIdFor1155) external notLive onlyProjectOwnerOrConfigurator {
        _setAssetDetails(tokenAddress, tokenType, tokenIdFor1155);
        _recordHistory(DataType.ActionType.SetAssetAddress, uint160(tokenAddress), uint(tokenType));
    }

    function setGroupVerified(uint groupId, string memory groupName) external notLive onlyProjectOwnerOrApprover {
        _groups().setVerified(groupId, groupName);
        _recordHistory(DataType.ActionType.VerifyGroup, groupId);
    }

    function finalizeGroupAndFundIn(uint groupId, string memory groupName, uint tokenAmount) external notLive onlyProjectOwner {
        _require(_asset().tokenAddress != Constant.ZERO_ADDRESS, "Invalid address");
        
        // Check required token Amount is correct?
        _groups().validateGroup(groupId, groupName);
        DataType.GroupInfo memory info = getGroupInfo(groupId);
        _require(tokenAmount == info.totalTokens, "Wrong token amount");
        _groups().setFinalized(groupId, groupName);

        // Only ERC20 and ERC1155 can fund in. ERC721 can't fund in easily in 1 function call //
        DataType.AssetType assetType = _asset().tokenType;
        if (assetType == DataType.AssetType.ERC20) {
            IERC20(_asset().tokenAddress).safeTransferFrom(msg.sender, address(this), tokenAmount); 
        } else {
            IERC1155(_asset().tokenAddress).safeTransferFrom(msg.sender, address(this), _asset().tokenId, tokenAmount, ""); 
        }
        
        emit FinalizeGroupFundIn(msg.sender, groupId, groupName, tokenAmount);
        _recordHistory(DataType.ActionType.FinalizeGroupFundIn, groupId, tokenAmount);
    }

    // Use-case 1: ERC721 Support
    // ERC721 does not have batchTransfer. So we have to depend on manual transfer in. Admin have to check for each group's
    // transfer in and then manually finalize each group without fundIn.
    // Use-case 2:
    // If there is an arrangement with project for manual fund-in. Example, a vesting contract that allow the fund in before each 
    // vesting period, then the Group can be finalized without a fund-in.
    // This should be an exception, rather than a norm. Only DaoMultiSig can approve such an arrangement.
    function finalizeGroupWithoutFundIn(uint groupId, string memory groupName) external notLive onlyDaoMultiSig {
        _groups().setFinalized(groupId, groupName);
        emit FinalizeGroupWithoutFundIn(msg.sender, groupId, groupName);
        _recordHistory(DataType.ActionType.FinalizeGroupWithoutFundIn, groupId, 0);
    }

    // If startTime is 0, the vesting wil start immediately.
    function startVesting(uint startTime) external notLive onlyProjectOwnerOrApprover {

        // Make sure that the asset address are set 
        _require(_asset().tokenAddress != Constant.ZERO_ADDRESS, "Token adress must be set before vesting start");

        if (startTime==0) {
            startTime = block.timestamp;
        } 
        _require(startTime >= block.timestamp, "Cannot back-date vesting");
        _groups().vestingStartTime = startTime;
        emit StartVesting(msg.sender, startTime);
        _recordHistory(DataType.ActionType.StartVesting, startTime);
    }

    //--------------------//
    //   USER OPERATION   //
    //--------------------//

    // A user address can participate in multiple groups. In this way, a user address can claim multiple deeds.
    function claimDeeds(uint[] calldata groupIds, uint[] calldata indexes, uint[] calldata amounts, bytes32[][] calldata merkleProofs) external nonReentrant {
        
        uint len = groupIds.length;
        _require(len > 0 && len == indexes.length && len == merkleProofs.length, "Invalid parameters");

        uint grpId;
        uint claimIndex;
        uint amount;
        uint nftId;

        DataType.Groups storage groups = _groups();
        for (uint n=0; n<len; n++) {
            
            grpId = groupIds[n];
            claimIndex = indexes[n];
            amount = amounts[n];

            DataType.Group storage item = groups.items[grpId];
            _require(item.state.finalized, "Group not finalized");
            _require(!item.isClaimed(claimIndex), "Index already claimed"); 

            item.claim(claimIndex, msg.sender, amount, merkleProofs[n]);
            // Mint Deed 
            nftId = _mintInternal(msg.sender, grpId, amount, 0);
            emit ClaimDeed(msg.sender, block.timestamp, grpId, claimIndex, amount, nftId);
            _recordHistory(DataType.ActionType.ClaimDeed, grpId, nftId);
        }
    }

    function getReleasableTokensOfGroup(uint groupId) external view returns (uint percentReleasable, uint totalEntitlement) {
        if (isGroupReady(groupId)) {
            totalEntitlement =  getGroupInfo(groupId).totalTokens;
            percentReleasable = _groups().getClaimable(groupId);
        }
    }

    function getClaimable(uint nftId) public view returns (uint claimable, uint totalClaimed, uint totalEntitlement) {
        
        DataType.NftInfo memory nft = getNftInfo(nftId);
        if (nft.valid && isGroupReady(nft.groupId)) {
        
            DataType.GroupInfo memory info = getGroupInfo(nft.groupId);

            totalEntitlement =  (nft.shares * info.totalTokens) / info.totalShares;
            totalClaimed = nft.tokenClaimed;

            uint percentReleasable = _groups().getClaimable(nft.groupId);
            if (percentReleasable > 0) {
                uint totalReleasable = (percentReleasable * totalEntitlement) / Constant.PCNT_100;
                claimable = totalReleasable - totalClaimed;
            }
        }
    }

    function claimTokens(uint nftId) external nonReentrant {
        
        _require(ownerOf(nftId) == msg.sender, "Not owner");
        (uint claimable, ,) =  getClaimable(nftId);
        _require(claimable > 0, "Nothing to claim");
        
        DataType.NftInfo storage nft = _store().nftInfoMap[nftId];
        nft.tokenClaimed += claimable;

        DataType.AssetType assetType = _asset().tokenType;
        if (assetType == DataType.AssetType.ERC20) {
            _transferOut721(msg.sender, claimable);
        } else if (assetType == DataType.AssetType.ERC1155) {
            _transferOut1155(msg.sender, claimable);
        } else if (assetType == DataType.AssetType.ERC721) {
            _transferOut721(msg.sender, claimable);
        }

        emit ClaimTokens(msg.sender, block.timestamp, nftId, claimable);
        _recordHistory(DataType.ActionType.ClaimTokens, nftId, claimable);
    }
    
    function splitBySharesAmount(uint id, uint shareAmount) external returns (uint) {
        return _splitBySharesAmount(id, shareAmount);
    }

    function splitBySharesPercent(uint id, uint sharePercent) public returns (uint) {
        _require(sharePercent > 0 && sharePercent < Constant.PCNT_100, "Invalid percentage");
        
        uint amount = (_store().nftInfoMap[id].shares * sharePercent)/Constant.PCNT_100;
        return _splitBySharesAmount(id, amount);
    }

    function splitByEntitledTokensAmount(uint id, uint tokenAmount) external returns (uint) {

        // Find remaining tokens in Deed
        DataType.NftInfo storage nftInfo = _store().nftInfoMap[id];
        DataType.GroupInfo memory groupInfo = getGroupInfo(nftInfo.groupId);

        uint totalEntitlement = (nftInfo.shares * groupInfo.totalTokens) / (groupInfo.totalShares);
        uint tokensInDeed = totalEntitlement - nftInfo.tokenClaimed;
        _require(tokenAmount < tokensInDeed, "Amount exceeded");

        uint percent = (tokenAmount * Constant.PCNT_100) / tokensInDeed;
        return splitBySharesPercent(id, percent);
    }

    function _splitBySharesAmount(uint id, uint shareAmount) internal nonReentrant returns (uint newId) {
        
        _require(ownerOf(id) == msg.sender, "Not owner");
        _require(shareAmount > 0, "Invalid amount");

        DataType.NftInfo storage nft = _store().nftInfoMap[id];

        _require(nft.shares > shareAmount, "Exceeded amount");
        uint claimedPortion = (nft.tokenClaimed * shareAmount)/nft.shares;

        nft.shares -= shareAmount;
        nft.tokenClaimed -= claimedPortion;
        
        // mint new nft
        newId = _mintInternal(msg.sender, nft.groupId, shareAmount, claimedPortion);
        emit Split(block.timestamp, id, newId, shareAmount);
    }

    function combine(uint id1, uint id2) external nonReentrant {
        _require(ownerOf(id1) == msg.sender && ownerOf(id2) == msg.sender, "Not owner");

        // Since the vesting items are the same, we can just add up the 2 nft 
        DataType.NftInfo storage nft1 = _store().nftInfoMap[id1];
        DataType.NftInfo memory nft2 = _store().nftInfoMap[id2];
        
        nft1.shares += nft2.shares;
        nft1.tokenClaimed += nft2.tokenClaimed;
         
        // Burn NFT 2 
        _burn(id2);
        delete _store().nftInfoMap[id2];

        emit Combine(block.timestamp, id1, id2);
    }

    function version() external pure returns (uint) {
        return Constant.SUPERDEED_VERSION;
    }

    // Implements IEmergency 
    function approveEmergencyAssetWithdraw(uint maxAmount) external override onlyProjectOwner {
        _emergencyMaxAmount = maxAmount;
        _emergencyExpiryTime = block.timestamp + Constant.EMERGENCY_WINDOW;
        emit ApprovedEmergencyWithdraw(msg.sender, _emergencyMaxAmount, _emergencyExpiryTime);
    }

    function daoMultiSigEmergencyWithdraw(address tokenAddress, address to, uint amount) external override onlyDaoMultiSig {
       
        _require(amount > 0, "Invalid amount");

        // If withdrawn token is the asset, then we will require projectOwner to approve.
        // Every approval allow 1 time withdraw only.
        bool isAsset = (tokenAddress == _asset().tokenAddress);
        if (isAsset) {
            _require(amount <= _emergencyMaxAmount, "Amount exceeded");
            _require(block.timestamp <= _emergencyExpiryTime, "Expired");
            // Reset 
            _emergencyMaxAmount = 0;
            _emergencyExpiryTime = 0;
        } 

         // Withdraw ERC721, 1155
        if (isAsset) {
            if (_asset().tokenType==DataType.AssetType.ERC1155) {
                _transferOut1155(to, amount);
            } else if (_asset().tokenType==DataType.AssetType.ERC721) {
                _transferOut721(to, amount);
            }
        }
        // Withdraw ERC20   
         _transferOut20(tokenAddress, to, amount); 

        emit DaoMultiSigEmergencyWithdraw(to, tokenAddress, amount);
    }


    //--------------------//
    // INTERNAL FUNCTIONS //
    //--------------------//
 
    function _mintInternal(address to, uint groupId, uint shares, uint tokensClaimed) internal returns (uint id) {
        id = _nextNftIdIncrement();
        _mint(to, id);

        // Setup ths certificate's info
        _store().nftInfoMap[id] = DataType.NftInfo(groupId, shares, tokensClaimed, true);
    }
}
