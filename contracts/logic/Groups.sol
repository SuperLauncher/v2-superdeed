// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.11;
import "../lib/DataType.sol";

library Groups {

    event AppendGroup(address indexed user, string name);
    event SetGroupVerified(address indexed user, uint groupId, string name);
    event SetGroupFinalized(address indexed user, uint groupId, string name);
    event UploadGroupUserData(address indexed user, uint groupId, string name, uint totalTokens);
    event SetupFee(address indexed user, uint groupId, string name, address feeAddress, uint feePercent);

    function appendGroups(DataType.Groups storage groups, string[] memory names) external returns (uint len) {
        len = names.length;
        for (uint n=0; n<len; n++) {
            
            (bool found, ) = exist(groups, names[n]);
            _require(!found, "Group already exist");

            DataType.Group storage newGroup = groups.items.push();
            newGroup.info.name = names[n];
            emit AppendGroup(msg.sender, names[n]);
        }
    }

    function uploadUsersData(DataType.Groups storage groups, uint groupId, string memory groupName, bytes32 root, uint totalTokens) external {
        validateGroup(groups, groupId, groupName);
        DataType.Group storage item = groups.items[groupId];
        _require(!item.state.finalized, "Already finalized");
        item.merkleRoot = root;
        item.info.totalEntitlement = totalTokens;
        item.state.verified = false;
        emit UploadGroupUserData(msg.sender, groupId, groupName, totalTokens);
    }

    function setVerified(DataType.Groups storage groups, uint groupId, string memory groupName) external {
        validateGroup(groups, groupId, groupName);
        DataType.Group storage item = groups.items[groupId];
        _require(!item.state.verified, "Already verified");
        item.state.verified = true;
        emit SetGroupVerified(msg.sender, groupId, groupName);
    }

    function setFinalized(DataType.Groups storage groups, uint groupId, string memory groupName) external {
        validateGroup(groups, groupId, groupName);
        DataType.Group storage item = groups.items[groupId];
        _require(item.state.verified, "Not yet verified");
        _require(!item.state.finalized, "Already finalized");
        _require(item.merkleRoot.length > 0, "No merkle root");
        item.state.finalized = true;
        emit SetGroupFinalized(msg.sender, groupId, groupName);
    }

    function validateGroup(DataType.Groups storage groups, uint groupId, string memory groupName) public view {
        (bool found, uint id ) = exist(groups, groupName);
        _require (found && id==groupId, "Invalid group");
    }

    function readyCheck(DataType.Groups storage groups, uint groupId) external view returns (bool, string memory) {
        uint len = groups.items.length;
        if (groupId >= len) { return (false, "Invalid group id"); }

        DataType.Group storage item = groups.items[groupId];
        if (!item.state.verified) { return (false,  "Not yet verified"); }
        if (!item.state.finalized) { return (false, "Not yet finalized"); }
        if (item.merkleRoot.length == 0) { return (false, "No merkle root"); }
        if (item.info.totalEntitlement == 0) { return (false, "No entitlement"); }
        if (item.vestItems.length == 0) { return (false, "No vesting item"); }
        return (true, "ok");
    }

    function exist(DataType.Groups storage groups, string memory name) private view returns (bool, uint) {
        uint len = groups.items.length;
        for (uint n=0; n<len; n++) {
            if (strcmp(groups.items[n].info.name, name)) {
                return (true, n);
            }
        }
        return (false, 0);
    }

    function getGroupName(DataType.Groups storage groups, uint groupId) external view returns (string memory ) {
        _require(groupId  < groups.items.length, "Invalid Id");
        return groups.items[groupId].info.name;
    }

    function getGroupNames(DataType.Groups storage groups) external view returns (string[] memory) {
        uint len = groups.items.length;
        string[] memory names = new string[](len);

        for (uint n=0; n<len; n++) {
            names[n] = groups.items[n].info.name;
        }
        return names;
    }

    function strcmp(string memory a, string memory b) private pure returns (bool) {
        return (keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b)));
    }

    function _require(bool condition, string memory error) pure private {
        require(condition, error);
    }
}

