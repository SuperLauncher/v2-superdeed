// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.11;

import "../lib/DataType.sol";
import "../lib/Constant.sol";
import "../logic/Groups.sol";
import "../logic/MerkleClaims.sol";
import "../interfaces/IRoleAccess.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract DataStore {
        
    using SafeERC20 for IERC20;
    using Groups for *;
    using MerkleClaims for *;

    DataType.Store private _dataStore;

    IRoleAccess private _roles;
    address public projectOwner;

    // Emergency Withdrawal Support
    uint internal _emergencyMaxAmount;
    uint internal _emergencyExpiryTime;

    
    modifier onlyProjectOwner() {
        _require(msg.sender == projectOwner, "Not project owner");
        _;
    }
    
    modifier onlyDaoMultiSig() {
        _require(_roles.isAdmin(msg.sender), "Not dao multiSig");
        _;
    }

    modifier onlyProjectOwnerOrConfigurator() {
        _require(msg.sender == projectOwner || _roles.isConfigurator(msg.sender), "Not project owner or configurator");
        _;
    }

    modifier onlyProjectOwnerOrApprover() {
        _require(msg.sender == projectOwner || _roles.isApprover(msg.sender), "Not project owner or approver");
        _;
    }

    modifier notLive() {
        _require(!isLive(), "Already live");
        _;
    }

    event SetAssetDetails(address indexed user, address tokenAddress, DataType.AssetType tokenType, uint tokenIdFor1155);
    event FinalizeGroupFundIn(address indexed user, uint groupId, string groupName, uint amount);
    event FinalizeGroupWithoutFundIn(address indexed user, uint groupId, string groupName);
    event StartVesting(address indexed user, uint timeStamp);
    event ClaimDeed(address indexed user, uint timeStamp, uint groupId, uint claimIndex, uint amount, uint nftId);
    event ClaimTokens(address indexed user, uint timeStamp, uint id, uint amount);
    event Split(uint timeStamp, uint id1, uint id2, uint amount);
    event Combine(uint timeStamp, uint id1, uint id2);
    event ApprovedEmergencyWithdraw(address indexed approver, uint amount, uint expiry);
    event DaoMultiSigEmergencyWithdraw(address to, address tokenAddress, uint amount);
    
    constructor (IRoleAccess roles, address campaignOwner) {
        _require(campaignOwner != Constant.ZERO_ADDRESS, "Invalid address");
        _roles = roles;
        projectOwner = campaignOwner;
    }

    //--------------------//
    //   QUERY FUNCTIONS  //
    //--------------------//

    function sharesOf(uint id) external view returns (uint) {
        DataType.NftInfo memory nft = _store().nftInfoMap[id];
        return nft.valid ? nft.shares : 0;
    }

    function getGroupCount() external view returns (uint) {
        return _groups().items.length;
    }

    function getGroupName(uint groupId) external view returns (string memory) {
        return _groups().getGroupName(groupId);
    }

    function isGroupReady(uint groupId) public view returns (bool) {
        (bool ready, ) = _groups().readyCheck(groupId);
        return ready;
    }

    function getGroupInfo(uint groupId) public view returns (DataType.GroupInfo memory) {
        return _groups().items[groupId].info;
    }

    function getVestingInfo(uint groupId) external view returns (DataType.VestingItem[] memory) {
        return _groups().items[groupId].vestItems;
    }

    function getVestingStartTime() external view returns (uint) {
        return _groups().vestingStartTime;
    }

    function getNftInfo(uint nftId) public view returns (DataType.NftInfo memory) {
        return _store().nftInfoMap[nftId];
    }

    function isLive() public view returns (bool) {
        uint time = _groups().vestingStartTime;
        return (time != 0 && block.timestamp > time);
    }



    function verifyDeedClaim(uint groupId, uint index, address account, uint amount, bytes32[] calldata merkleProof) external view returns (bool) {
        DataType.Group storage group = _groups().items[groupId];
        return group.verifyClaim(index, account, amount, merkleProof);
    }

    //--------------------//
    // INTERNAL FUNCTIONS //
    //--------------------//
    function _store() internal view returns (DataType.Store storage) {
        return _dataStore;
    }

    function _groups() internal view returns (DataType.Groups storage) {
        return _dataStore.groups;
    }

    function _asset() internal view returns (DataType.Asset storage) {
        return _dataStore.asset;
    }

    function _nextNftIdIncrement() internal returns (uint) {
        return _dataStore.nextIds++;
    }

    function _transferOut20(address token, address to, uint amount) internal {
        IERC20(token).safeTransfer(to, amount);
    }

    function _transferOut1155(address to, uint amount) internal {
        IERC1155(_asset().tokenAddress).safeTransferFrom(address(this), to, _asset().tokenId, amount, "");
    }

    function _transferOut721(address to, uint amount) internal {
        uint len = _asset().erc721IdArray.length;
        require(_asset().numErc721TransferedOut + amount <= len, "Exceeded Amount");
        
        for (uint n=0; n<amount; n++) {

            uint id = _asset().erc721IdArray[_asset().erc721NextClaimIndex++];
            IERC721(_asset().tokenAddress).safeTransferFrom(address(this), to, id);
        }
        _asset().numErc721TransferedOut += amount;
    }

    function _setAsset(string memory tokenSymbol, string memory deedName) internal {
        _dataStore.asset.symbol = tokenSymbol;
        _dataStore.asset.deedName = deedName;
    }

    function _setAssetDetails(address tokenAddress, DataType.AssetType tokenType, uint tokenIdFor1155) internal {
        _require(tokenAddress != Constant.ZERO_ADDRESS, "Invalid address");
        _dataStore.asset.tokenAddress = tokenAddress;
        _dataStore.asset.tokenType = tokenType;
        _dataStore.asset.tokenId = tokenIdFor1155;
        emit SetAssetDetails(msg.sender, tokenAddress, tokenType, tokenIdFor1155);
    }

    function _recordHistory(DataType.ActionType actType, uint data1) internal {
        _recordHistory(actType, data1, 0);
    }

    function _recordHistory(DataType.ActionType actType, uint data1, uint data2) internal {
       
       DataType.Action memory act = DataType.Action(uint128(actType), uint128(block.timestamp), data1, data2);
       _dataStore.history[msg.sender].push(act);
    }

    function _require(bool condition, string memory error) pure internal {
        require(condition, error);
    }
}