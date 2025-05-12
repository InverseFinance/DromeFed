// SPDX-License-Identifier: MIT
import {IRouter} from "src/interfaces/IRouter.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IGauge} from "src/interfaces/IGauge.sol";
import {IL2ERC20Bridge} from "src/interfaces/IL2ERC20Bridge.sol";
import {ICrossDomainMessenger} from "src/interfaces/ICrossDomainMessenger.sol";
import {ICCTP} from "src/interfaces/ICCTP.sol";

pragma solidity ^0.8.13;
interface IPool is IERC20 {
    function getReserves() external view returns(uint, uint, uint);
}
interface IChainlinkPriceFeed {
    function latestRoundData()
        external
        view
        returns (
          uint80 roundId,
          int256 answer,
          uint256 startedAt,
          uint256 updatedAt,
          uint80 answeredInRound
        );
    function decimals() external view returns(uint8);
}

contract DromeFarmer {
    address public chair;
    address public pendingGov;
    address public gov;
    address public TWG;
    address public guardian;
    address public l1Fed;

    mapping(address => mapping(address => uint)) public maxSwapSlippage;
    mapping(address => bool) public allowedSwaps;
    uint public maxSlippageBps;
    uint public maxGuardianSetableSlippageBps = 500;
    uint public depegEmergencyThresholdBps = 9800; //If USDC depegs by more than 2%, guardian msig can set emergency slippage parameters

    uint public constant DOLA_USDC_CONVERSION_MULTI= 1e12;
    ICrossDomainMessenger public constant ovmL2CrossDomainMessenger = ICrossDomainMessenger(0x4200000000000000000000000000000000000007);
    IL2ERC20Bridge public constant bridge = IL2ERC20Bridge(0x4200000000000000000000000000000000000010);
    IChainlinkPriceFeed public constant usdcPriceFeed = IChainlinkPriceFeed(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B);

    IGauge public immutable dolaGauge;// = IGauge(0xCCff5627cd544b4cBb7d048139C1A6b6Bde67885); 
    IPool public immutable lpToken;
    IERC20 public immutable rewardToken;
    IRouter public immutable router;// = IRouter(0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43);
    IERC20 public immutable DOLA;
    IERC20 public immutable nUSDC;
    IERC20 public immutable USDC;
    ICCTP public immutable cctp;

    error OnlyRole(address, string);
    error OnlyL1Role(address, string);
    error MaxSlippageTooHigh();
    //error ThresholdTooHigh();
    error NotEnoughTokens();
    error SlippageTooHigh();
    error RestrictedToken();

    constructor(
        address _chair,
        address _guardian,
        address _TWG,
        address _gov,
        address cctpBridge,
        address _l1Fed,
        address _dola,
        address _usdc,
        address _nusdc,
        IRouter _router,
        IGauge _dolaGauge
    ){
        gov = _gov;
        chair = _chair;
        TWG = _TWG;
        guardian = _guardian;
        cctp = ICCTP(cctpBridge);
        l1Fed = _l1Fed;
        DOLA = IERC20(_dola);
        USDC = IERC20(_usdc);
        nUSDC = IERC20(_nusdc);
        router = _router;
        dolaGauge = _dolaGauge;
        rewardToken = IERC20(_dolaGauge.rewardToken());
        lpToken = IPool(_dolaGauge.stakingToken());
        allowedSwaps[_dola] = true;
        allowedSwaps[_usdc] = true;
        allowedSwaps[_nusdc] = true;
        maxSwapSlippage[_dola][_usdc] = 60;
        maxSwapSlippage[_usdc][_dola] = 60;
        maxSwapSlippage[_dola][_nusdc] = 60;
        maxSwapSlippage[_nusdc][_dola] = 60;
        maxSwapSlippage[_nusdc][_usdc] = 20;
        maxSwapSlippage[_usdc][_nusdc] = 20;
    }

    modifier onlyRole(address role, string memory description) {
        if (msg.sender != role && msg.sender != gov) {
            revert OnlyRole(role, description);
        }
        _;
    }

    modifier onlyL1Role(address role, string memory description) {
        if (msg.sender != address(ovmL2CrossDomainMessenger))
            revert OnlyL1Role(role, description);
        address messageSender = ovmL2CrossDomainMessenger.xDomainMessageSender();
        if(messageSender != role)
            revert OnlyL1Role(role, description);
        _;
    }

    /**
     * @notice Claims all VELO token rewards accrued by this contract & transfer all VELO owned by this contract to `TWG`
     */
    function claimRewards() external {
        dolaGauge.getReward(address(this));
        rewardToken.transfer(TWG, rewardToken.balanceOf(address(this)));
    }

    /**
     * @notice Attempts to deposit `dolaAmount` of DOLA & `usdcAmount` of USDC into Aerodrome DOLA/USDC stable pool. Then, deposits LP tokens into gauge.
     * @param dolaAmount Amount of DOLA to be added as liquidity in Aerodrome DOLA/USDC pool
     * @param usdcAmount Amount of USDC to be added as liquidity in Aerodrome DOLA/USDC pool
     */
    function _deposit(uint dolaAmount, uint usdcAmount) internal {
        uint lpTokenPrice = getLpTokenPrice();

        DOLA.approve(address(router), dolaAmount);
        nUSDC.approve(address(router), usdcAmount);
        (uint dolaSpent, uint usdcSpent, uint lpTokensReceived) = router.addLiquidity(address(DOLA), address(nUSDC), true, dolaAmount, usdcAmount, 0, 0, address(this), block.timestamp);
        require(lpTokensReceived > 0, "No LP tokens received");

        uint totalDolaValue = usdcSpent * DOLA_USDC_CONVERSION_MULTI + dolaSpent;

        uint expectedLpTokens = applySlippage(totalDolaValue * 1e18 / lpTokenPrice, maxSlippageBps);
        if (lpTokensReceived < expectedLpTokens) revert SlippageTooHigh();
        
        uint lpBalance = lpToken.balanceOf(address(this));
        lpToken.approve(address(dolaGauge), lpBalance);
        dolaGauge.deposit(lpBalance);
    }

    /**
     * @notice Attempts to deposit `dolaAmount` of DOLA & `usdcAmount` of USDC into Aerodrome DOLA/USDC stable pool. Then, deposits LP tokens into gauge.
     * @param dolaAmount Amount of DOLA to be added as liquidity in Aerodrome DOLA/USDC pool
     * @param usdcAmount Amount of USDC to be added as liquidity in Aerodrome DOLA/USDC pool
     */
    function deposit(uint dolaAmount, uint usdcAmount) external onlyRole(chair, "chair") {
        _deposit(dolaAmount, usdcAmount);
    }

    /**
     * @notice Calls `deposit()` with entire DOLA & USDC token balance of this contract.
     */
    function depositAll() external onlyRole(chair, "chair") {
        _deposit(DOLA.balanceOf(address(this)), nUSDC.balanceOf(address(this)));
    }

    /**
     * @notice Withdraws `dolaAmount` worth of LP tokens from gauge. Then, redeems LP tokens for DOLA/USDC.
     * @dev If attempting to remove more DOLA than total LP tokens are worth, will remove all LP tokens.
     * @param dolaAmount Desired dola value to remove from DOLA/USDC pool. Will attempt to remove 50/50 while allowing for `maxSlippageBps` bps of variance.
     * @return Amount of USDC received from liquidity removal. Used by withdrawAndSwap wrapper.
     */
    function _withdraw(uint dolaAmount) internal returns (uint) {
        uint lpTokenPrice = getLpTokenPrice();
        uint liquidityToWithdraw = dolaAmount * 1e18 / lpTokenPrice;
        uint owned = dolaGauge.balanceOf(address(this));

        if (liquidityToWithdraw > owned) liquidityToWithdraw = owned;
        dolaGauge.withdraw(liquidityToWithdraw);
   
        lpToken.approve(address(router), liquidityToWithdraw);
        (uint amountUSDC, uint amountDola) = router.removeLiquidity(address(nUSDC), address(DOLA), true, liquidityToWithdraw, 0, 0, address(this), block.timestamp);

        uint totalDolaReceived = amountDola + (amountUSDC *DOLA_USDC_CONVERSION_MULTI);

        if (applySlippage(dolaAmount, maxSlippageBps) > totalDolaReceived) {
            revert SlippageTooHigh();
        }

        return amountUSDC;
    }

    /**
     * @notice Withdraws `dolaAmount` worth of LP tokens from gauge. Then, redeems LP tokens for DOLA/USDC.
     * @dev If attempting to remove more DOLA than total LP tokens are worth, will remove all LP tokens.
     * @param dolaAmount Desired dola value to remove from DOLA/USDC pool. Will attempt to remove 50/50 while allowing for `maxSlippageBps` bps of variance.
     * @return Amount of USDC received from liquidity removal. Used by withdrawAndSwap wrapper.
     */
    function withdraw(uint dolaAmount) external onlyRole(chair, "chair") returns (uint) {
        return _withdraw(dolaAmount);
    }
 
    /**
     * @notice Withdraws `dolaAmount` worth of LP tokens from gauge. Then, redeems LP tokens for DOLA/USDC and swaps redeemed USDC to DOLA.
     * @param dolaAmount Desired dola value to remove from DOLA/USDC pool. Will attempt to remove 50/50 while allowing for `maxSlippageBps` bps of variance.
     */
    function withdrawAndSwapToDOLA(address sellStable, uint dolaAmount) external onlyRole(chair, "chair") {
        uint usdcAmount = _withdraw(dolaAmount);
        swapStables(sellStable, address(DOLA), usdcAmount);
    }
    /**
     * @notice Withdraws `dolaAmount` of DOLA to l1Fed on L1. Will take 7 days before withdraw is claimable on L1.
     * @param dolaAmount Amount of DOLA to withdraw and send to L1 Fed
     */
    function withdrawToL1Fed(uint dolaAmount) external onlyRole(chair, "chair") {
        if (dolaAmount > DOLA.balanceOf(address(this))) revert NotEnoughTokens();

        bridge.withdrawTo(address(DOLA), l1Fed, dolaAmount, 0, "");
    }

    /**
     * @notice Withdraws `dolaAmount` of DOLA & `usdcAmount` of USDC to l1Fed on L1. Will take 7 days before withdraw is claimable on L1.
     * @param dolaAmount Amount of DOLA to withdraw and send to L1 Fed
     * @param usdcAmount Amount of USDC to withdraw and send to L1 Fed
     */
    function withdrawToL1FedNative(uint dolaAmount, uint usdcAmount) external onlyRole(chair, "chair") {
        if (dolaAmount > DOLA.balanceOf(address(this))) revert NotEnoughTokens();
        if (usdcAmount > nUSDC.balanceOf(address(this))) revert NotEnoughTokens();

        bridge.withdrawTo(address(DOLA), l1Fed, dolaAmount, 0, "");
        nUSDC.approve(address(cctp), usdcAmount);
        cctp.depositForBurn(usdcAmount, 0, bytes32(uint256(uint160(l1Fed))), address(nUSDC));
    }

    function withdrawToL1FedNative(uint usdcAmount) external onlyRole(chair, "chair") {
        if (usdcAmount > nUSDC.balanceOf(address(this))) revert NotEnoughTokens();
        
        nUSDC.approve(address(cctp), usdcAmount);
        cctp.depositForBurn(usdcAmount, 0, bytes32(uint256(uint160(l1Fed))), address(nUSDC));
    }

    /**
     * @notice Withdraws `usdcAmount` of USDC to l1Fed on L1. Will take 7 days before withdraw is claimable.
     * @param usdcAmount Amount of USDC to withdraw and send to L1 Fed
     */
    function withdrawToL1FedBridged(uint usdcAmount) external onlyRole(chair, "chair") {
        if (usdcAmount > USDC.balanceOf(address(this))) revert NotEnoughTokens();

        bridge.withdrawTo(address(USDC), l1Fed, usdcAmount, 0, "");
    }
    /**
     * @notice Swap `usdcAmount` of USDC to DOLA through aerodrome.
     * @param sellStable Gov approved stable to sell
     * @param buyStable Gov approved stable to buy
     * @param amount Amount of sellStable to swap for buyStable
     */
    function swapStables(address sellStable, address buyStable, uint amount) public onlyRole(chair, "chair") {
        require(sellStable != buyStable, "same stable");
        require(allowedSwaps[sellStable], "sellStable not allowed");
        require(allowedSwaps[buyStable], "buyStable not allowed");
        uint minOut = applySwapSlippage(amount, sellStable, buyStable);

        IERC20(sellStable).approve(address(router), amount);
        router.swapExactTokensForTokens(amount, minOut, getRoute(sellStable, buyStable), address(this), block.timestamp);
    }

    function getLpTokenPrice() internal view returns (uint) {
       (uint256 reservesDOLA, uint256 reservesNUSDC, ) = lpToken.getReserves();
       uint256 k = _k(reservesDOLA, reservesNUSDC, 10**DOLA.decimals(), 10**nUSDC.decimals());
       return 2 * sqrt(sqrt(k/2)) * 1e18 / lpToken.totalSupply();
    }

    // from Velodrome pool
    function _k(uint256 x, uint256 y, uint256 decimals0, uint256 decimals1) internal pure returns (uint256) {
       uint256 _x = (x * 1e18) / decimals0;
       uint256 _y = (y * 1e18) / decimals1;
       uint256 _a = (_x * _y) / 1e18;
       uint256 _b = ((_x * _x) / 1e18 + (_y * _y) / 1e18);
       return (_a * _b) / 1e18;
    }

    //from UniV2 Math.sol, adapted for 18 decimals precision numbers
    function sqrt(uint y) internal pure returns (uint z) {
       y *= 1e18;
       if (y > 3) {
          z = y;
          uint x = y / 2 + 1;
          while (x < z) {
                z = x;
                x = (y / x + x) / 2;
          }
       } else if (y != 0) {
          z = 1;
       }
    }

    function priceAboveEmergencyThreshold() public returns(bool) {
        (,int usdcPrice,,,) = usdcPriceFeed.latestRoundData();
        uint8 decimals = usdcPriceFeed.decimals();
        return usdcPrice > int(10 ** decimals * depegEmergencyThresholdBps / 10000);
    }

    function applySwapSlippage(uint amount, address sellStable, address buyStable) internal view returns(uint) {
        uint sellStableDecimals = IERC20(sellStable).decimals();
        uint buyStableDecimals = IERC20(buyStable).decimals();
        if(sellStableDecimals > buyStableDecimals)
            return applySlippage(amount, maxSwapSlippage[sellStable][buyStable]) / (10 ** (sellStableDecimals - buyStableDecimals));
        return applySlippage(amount, maxSwapSlippage[sellStable][buyStable]) * (10 ** (buyStableDecimals - sellStableDecimals));
    }

    function applySlippage(uint amount, uint maxSlippage) internal pure returns(uint) {
        return amount * (10000 - maxSlippage) / 10000;
    }

    /**
     * @notice Generate route array for swap between two stablecoins
     * @param from Token to go from
     * @param to Token to go to
     * @return Returns a Route[] with a single element, representing the route
     */
    function getRoute(address from, address to) internal view returns(IRouter.Route[] memory){
        IRouter.Route memory route = IRouter.Route(from, to, true, router.defaultFactory());
        IRouter.Route[] memory routeArray = new IRouter.Route[](1);
        routeArray[0] = route;
        return routeArray;
    }

    /**
     * @notice Method for current chair of the fed to resign
     */
    function resign() external onlyRole(chair, "chair") {
        chair = address(0);
    }

    /**
     * @notice Governance only function for setting acceptable slippage when swapping DOLA -> USDC
     * @param newMaxSlippageBps The new maximum allowed loss for DOLA -> USDC swaps. 1 = 0.01%
     */
    function setMaxSwapSlippage(address stable1, address stable2, uint newMaxSlippageBps) onlyRole(guardian, "guardian") external {
        if (priceAboveEmergencyThreshold() && newMaxSlippageBps > maxGuardianSetableSlippageBps) revert MaxSlippageTooHigh();
        maxSwapSlippage[stable1][stable2] = newMaxSlippageBps;
        maxSwapSlippage[stable2][stable2] = newMaxSlippageBps;
    }

    /**
     * @notice Governance only function for setting acceptable slippage when adding or removing liquidty from DOLA/USDC pool
     * @param newMaxSlippageBps The new maximum allowed loss for adding/removing liquidity from DOLA/USDC pool. 1 = 0.01%
     */
    function setMaxSlippageLP(uint newMaxSlippageBps) onlyRole(guardian, "guardian") external {
        if (priceAboveEmergencyThreshold() && newMaxSlippageBps > maxGuardianSetableSlippageBps) revert MaxSlippageTooHigh();
        maxSlippageBps = newMaxSlippageBps;
    }

    /**
     * @notice Sets the depeg emergency threshold. At 9800 if USDC price drops to $0.98, the guardian address can set slippage parameters as they please.
     * @param _depegEmergencyThresholdBps Depeg emergency threshold in bps, at 10000 lets guardian set slippage parameters at $1 USDC price, at 5000 lets guardian set slippage parameters at $0.5 usdc price.
     */
    function setDepegEmergencyThresholdBps(uint _depegEmergencyThresholdBps) external onlyL1Role(gov, "gov") {
        if(_depegEmergencyThresholdBps > 10000) revert MaxSlippageTooHigh();
        depegEmergencyThresholdBps = _depegEmergencyThresholdBps;
    }
    
    /**
     * @notice Sets the maximum slippage setable by the guardian role
     * @param _maxGuardianSetableSlippageBps Max slippage in BPS setable by the guardian role
     */
    function setMaxGuardianSetableSlippageBps(uint _maxGuardianSetableSlippageBps) external onlyL1Role(gov, "gov") {
        if(_maxGuardianSetableSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxGuardianSetableSlippageBps = _maxGuardianSetableSlippageBps;
    }

    /**
     * @notice Withdraws `amount` of `l2Token` to the TWG address.
     * @dev Make sure the TWG address is either a trusted multisig or smart contract before calling this function!
     * @param l2Token Address of the L2 token to be withdrawn
     * @param amount Amount of the L2 token to be withdrawn
     */
    function emergencyWithdraw(address l2Token, uint amount) external onlyL1Role(gov, "gov") {
        if (amount > IERC20(l2Token).balanceOf(address(this))) revert NotEnoughTokens();
        IERC20(l2Token).transfer(TWG, amount);
    }

    /**
     * @notice Method for `gov` to change `pendingGov` address
     * @dev `pendingGov` will have to call `claimGov` to complete `gov` transfer
     * @dev `pendingGov` should be an L1 address
     * @param _pendingGov L1 address to be set as `pendingGov`
     */
    function setPendingGov(address _pendingGov) onlyL1Role(gov, "gov") external {
        pendingGov = _pendingGov;
    }

    /**
     * @notice Method for `pendingGov` to claim `gov` role.
     */
    function claimGov() external onlyL1Role(pendingGov, "pending gov") {
        gov = pendingGov;
        pendingGov = address(0);
    }

    /**
     * @notice Method for gov to change TWG address, the address that receives all rewards
     * @param _TWG L2 address to be set as TWG
     */
    function changeTreasury(address _TWG) external onlyL1Role(gov, "gov") {
        TWG = _TWG;
    }

    /**
     * @notice Method for gov to change the chair
     * @param _chair address to be set as chair
     */
    function changeChair(address _chair) external onlyL1Role(gov, "gov") {
        chair = _chair;
    }

    /**
     * @notice Method for gov to change the guardian
     * @param _guardian L1 address to be set as guardian
     */
    function changeGuardian(address _guardian) external onlyL1Role(gov, "gov") {
        guardian = _guardian;
    }

    /**
     * @notice Method for gov to change the L1 l1Fed address
     * @dev l1Fed is the L1 address that receives all bridged DOLA/USDC from both withdrawToL1Fed functions
     * @param _fed L1 address to be set as l1Fed
     */
    function changeL1Fed(address _fed) external onlyL1Role(gov, "gov") {
        l1Fed = _fed;
    }
}
