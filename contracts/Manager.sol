// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.11;

import "./interfaces/IDeedManager.sol";
import "./interfaces/IRoleAccess.sol";
import "./lib/Constant.sol";

contract Manager is IDeedManager {

    IRoleAccess private _roles;
    
    enum Status {
        Inactive,
        Active,
        Cancelled
    }

     modifier onlyFactory() {
        require(_factoryMap[msg.sender], "Errors.NOT_FACTORY");
        _;
    }
    
    modifier onlyAdmin() {
        require(_roles.isAdmin(msg.sender), "Errors.NOT_ADMIN");
        _;
    }
    
    struct DeedInfo {
        address deed;
        address projectOwner;
        Status status;
    }
    
    // History & list of factories.
    mapping(address => bool) private _factoryMap;
    address[] private _factories;
    
    // History/list of all IDOs
    mapping(uint => DeedInfo) private _indexDeedMap; // Starts from 1. Zero is invalid //
    mapping(address => uint) private _addressIndexMap;  // Maps a Deed address to an index in _indexDeedMap.
    uint private _count;
    
    // Events
    event FactoryRegistered(address indexed deployedAddress);
    event DeedAdded(address indexed contractAddress);
    event DeedCancelled(address indexed contractAddress);
    
    constructor(IRoleAccess rolesRegistry) {
        _roles = rolesRegistry;
    }
    
    //--------------------//
    // EXTERNAL FUNCTIONS //
    //--------------------//
    
    function getDeedInfo(uint id) external view returns (DeedInfo memory) {
        return _indexDeedMap[id];
    }
    
    function registerFactory(address newFactory) external onlyAdmin {
        if ( _factoryMap[newFactory] == false) {
            _factoryMap[newFactory] = true;
            _factories.push(newFactory);
            emit FactoryRegistered(newFactory);
        }
    }
    
    function isFactory(address contractAddress) external view returns (bool) {
        return _factoryMap[contractAddress];
    }
    
    function getFactory(uint id) external view returns (address) {
        return (  (id < _factories.length) ? _factories[id] : Constant.ZERO_ADDRESS);
    }

    function cancelDeed(address contractAddress) external onlyAdmin {
        uint index = _addressIndexMap[contractAddress];
        DeedInfo storage info = _indexDeedMap[index];
        // Update status if deed is exist & active
        if (info.status == Status.Active) {
            info.status = Status.Cancelled;         
            emit DeedCancelled(contractAddress);
        }
    }


    //--------------------------//
    // IMPLEMENTS IDeedManager  //
    //--------------------------//
    
    function addDeed(address deedContract, address projectOwner) external override onlyFactory {
        _count++;
        _indexDeedMap[_count] = DeedInfo(deedContract, projectOwner, Status.Active);
        _addressIndexMap[deedContract] = _count;
        emit DeedAdded(deedContract);
    }
    
    function getRoles() external view override returns (IRoleAccess) {
        return _roles;
    }

    function getDeedsCount() external view override returns(uint) {
        return _count;
    }
}
