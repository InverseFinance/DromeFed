// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

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
    address public dromeFed;
    address public gov;
    address public pendingGov;

    uint32 public gasLimit = 750_000;

    constructor(address _gov, address dromeFed_, address _bridge) {
        gov = _gov;
        dromeFed = dromeFed_;
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
        crossDomainMessenger.sendMessage(address(dromeFed), message, gasLimit);
    }

    //Gov Messaging functions

    function setMaxGuardianSetableSlippage(uint _maxGuardianSetableSlippageBps) public onlyGov {
        require(_maxGuardianSetableSlippageBps <= 10000, "Max slippage above 100%");
        sendMessage(abi.encodeWithSignature("setMaxGuardianSetableSlippage(uint)", _maxGuardianSetableSlippageBps));
    }

    function setPendingGov(address _pendingGov) public onlyGov {
        sendMessage(abi.encodeWithSignature("setPendingGov(address)", _pendingGov));
    }
    
    function claimGov() public onlyGov {
        sendMessage(abi.encodeWithSignature("claimGov()"));
    }
    
    function changeTreasury(address _treasury) public onlyGov {
        sendMessage(abi.encodeWithSignature("changeTreasury(address)", _treasury));
    }
    
    function changeChair(address _chair) public onlyGov {
        sendMessage(abi.encodeWithSignature("changeChair(address)", _chair));
    }
    
    function changeGuardian(address _guardian) public onlyGov {
        sendMessage(abi.encodeWithSignature("changeGuardian(address)", _guardian));
    }
    
    function changeL1Fed(address _fed) public onlyGov {
        sendMessage(abi.encodeWithSignature("changeL1Fed(address)", _fed));
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

    function setDromeFed(address dromeFed_) public onlyGov {
        dromeFed = dromeFed_;
    }
}
