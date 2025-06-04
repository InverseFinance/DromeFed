pragma solidity ^0.8.20;

abstract contract Chairable {
    address public gov;
    address public pendingGov;
    address public chair;

    error OnlyGov();
    error OnlyPendingGov();
    error OnlyChair();

    constructor(address _gov, address _chair) {
        gov = _gov;
        chair = _chair;
    }

    modifier onlyGov() {
        if (msg.sender != gov) revert OnlyGov();
        _;
    }

    modifier onlyChair() {
        if (msg.sender != chair) revert OnlyChair();
        _;
    }

    /**
    @notice Method for `gov` to change `pendingGov` address
    @dev `pendingGov` will have to call `claimGov` to complete `gov` transfer
    @param newPendingGov Address to be set as `pendingGov`
    */
    function setPendingGov(address newPendingGov) external onlyGov {
        pendingGov = newPendingGov;
    }

    /**
    @notice Method for `pendingGov` to claim `gov` role.
    */
    function claimGov() external {
        if (msg.sender != pendingGov) revert OnlyPendingGov();
        gov = pendingGov;
        pendingGov = address(0);
    }

    /**
    @notice Method for gov to change the chair
    @param newChair Address to be set as chair
    */
    function changeChair(address newChair) external onlyGov {
        chair = newChair;
    }

    /**
    @notice Method for current chair to resign
    */
    function resign() external onlyChair {
        chair = address(0);
    }
}
