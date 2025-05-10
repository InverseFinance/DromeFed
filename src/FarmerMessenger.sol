// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import {DromeFarmer} from "src/DromeFarmer.sol";

/**
 * @title ICrossDomainMessenger
 */
interface ICrossDomainMessenger {
    /**********
     * Events *
     **********/

    event SentMessage(
        address indexed target,
        address sender,
        bytes message,
        uint256 messageNonce,
        uint256 gasLimit
    );
    event RelayedMessage(bytes32 indexed msgHash);
    event FailedRelayedMessage(bytes32 indexed msgHash);

    /*************
     * Variables *
     *************/

    function xDomainMessageSender() external view returns (address);

    /********************
     * Public Functions *
     ********************/

    /**
     * Sends a cross domain message to the target messenger.
     * @param _target Target contract address.
     * @param _message Message to send to the target.
     * @param _gasLimit Gas limit for the provided message.
     */
    function sendMessage(
        address _target,
        bytes calldata _message,
        uint32 _gasLimit
    ) external;
}

contract FarmerMessenger {
    ICrossDomainMessenger immutable crossDomainMessenger;
    address public dromeFarmer;
    address public gov;
    address public pendingGov;

    uint32 public gasLimit = 750_000;

    constructor(address _gov, address _dromeFarmer, address _bridge) {
        gov = _gov;
        dromeFarmer = _dromeFarmer;
        crossDomainMessenger = ICrossDomainMessenger(_bridge);
    } 

    modifier onlyGov {
        if (msg.sender != gov) revert OnlyGov();
        _;
    }

    modifier onlyPendingGov {
        if (msg.sender != pendingGov) revert OnlyPendingGov();
        _;
    }

    error OnlyGov();
    error OnlyGovOrGuardian();
    error OnlyPendingGov();
    error OnlyChair();

    //Helper functions

    function sendMessage(bytes memory message) internal {
        crossDomainMessenger.sendMessage(address(dromeFarmer), message, gasLimit);
    }

    //Gov Messaging functions

    function setMaxGuardianSetableSlippage(uint _maxGuardianSetableSlippageBps) public onlyGov {
        require(_maxGuardianSetableSlippageBps <= 10000, "Max slippage above 100%");
        sendMessage(abi.encodeWithSelector(DromeFarmer.setMaxGuardianSetableSlippageBps.selector, _maxGuardianSetableSlippageBps));
    }

    function setDepegEmergencyThreshold(uint _depegEmergencyThresholdBps) public onlyGov {
        require(_depegEmergencyThresholdBps <= 10000, "Threshold above 100%");
        sendMessage(abi.encodeWithSelector(DromeFarmer.setDepegEmergencyThresholdBps.selector, _depegEmergencyThresholdBps));
    }

    function setPendingGov(address _pendingGov) public onlyGov {
        sendMessage(abi.encodeWithSelector(DromeFarmer.setPendingGov.selector, _pendingGov));
    }
    
    function claimGov() public onlyGov {
        sendMessage(abi.encodeWithSelector(DromeFarmer.claimGov.selector));
    }
    
    function changeTreasury(address _treasury) public onlyGov {
        sendMessage(abi.encodeWithSelector(DromeFarmer.changeTreasury.selector, _treasury));
    }
    
    function changeChair(address _chair) public onlyGov {
        sendMessage(abi.encodeWithSelector(DromeFarmer.changeChair.selector, _chair));
    }
    
    function changeGuardian(address _guardian) public onlyGov {
        sendMessage(abi.encodeWithSelector(DromeFarmer.changeGuardian.selector, _guardian));
    }
    
    function changeL1Fed(address _fed) public onlyGov {
        sendMessage(abi.encodeWithSelector(DromeFarmer.changeL1Fed.selector, _fed));
    }

    //Gov functions

    function setGasLimit(uint32 _gasLimit) public onlyGov {
        gasLimit = _gasLimit;
    }

    function setPendingMessengerGov(address _pendingGov) public onlyGov {
        pendingGov = _pendingGov;
    }

    function claimMessengerGov() public onlyPendingGov {
        gov = pendingGov;
        pendingGov = address(0);
    }

    function setDromeFarmer(address _dromeFarmer) public onlyGov {
        dromeFarmer = _dromeFarmer;
    }
}
