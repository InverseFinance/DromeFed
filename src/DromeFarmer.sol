// SPDX-License-Identifier: MIT
import {IRouter} from "src/interfaces/IRouter.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IGauge} from "src/interfaces/IGauge.sol";
import {IL2ERC20Bridge} from "src/interfaces/IL2ERC20Bridge.sol";
import {ICrossDomainMessenger} from "src/interfaces/ICrossDomainMessenger.sol";
import {ICCTP} from "src/interfaces/ICCTP.sol";

pragma solidity ^0.8.13;
contract DromeFarmer {
    address public chair;
    address public pendingGov;
    address public gov;
    address public treasury;
    address public guardian;

    uint public maxSlippageBpsDolaToUsdc;
    uint public maxSlippageBpsUsdcToDola;
    uint public maxSlippageBpsUsdcNativeToDola;
    uint public maxSlippageBpsDolaToUsdcNative;
    uint public maxSlippageBpsUsdcToUsdcNative;
    uint public maxSlippageBpsUsdcNativeToUsdc;

    uint public maxSlippageBpsLiquidity;

    uint public constant DOLA_USDC_CONVERSION_MULTI= 1e12;
    uint public constant PRECISION = 10_000;
    ICrossDomainMessenger public constant ovmL2CrossDomainMessenger = ICrossDomainMessenger(0x4200000000000000000000000000000000000007);
    uint32 public constant MAINNET_CCTP_DOMAIN = 0;

    IGauge public immutable dolaGauge;// = IGauge(0xCCff5627cd544b4cBb7d048139C1A6b6Bde67885); 
    IERC20 public immutable LP_TOKEN;// = IERC20(0xf213F2D02837012dC0236cC105061e121bB03e37);
    IERC20 public immutable aeroToken;// = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
    address public immutable factory;// = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;
    IRouter public immutable router;// = IRouter(0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43);
    IERC20 public immutable DOLA;//= IERC20(0x4621b7A9c75199271F773Ebd9A499dbd165c3191);
    IERC20 public immutable USDC;//= IERC20(0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA);
    IERC20 public immutable nUSDC;//= IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);  // native USDC
    IL2ERC20Bridge public bridge;
    address public baseFed;
    ICCTP public immutable cctp;

    error OnlyRole(address, string);
    error OnlyGovOrGuardian();
    error MaxSlippageTooHigh();
    error NotEnoughTokens();
    error LiquiditySlippageTooHigh();
    error RestrictedToken();

    constructor(
        address[] memory addresses,
        uint[] memory maxSlippageBps,
        uint maxSlippageBpsLiquidity_
        )
    {
        gov = addresses[0];
        chair = addresses[1];
        chair = addresses[2];
        treasury = addresses[3];
        treasury = addresses[4];
        guardian = addresses[5];
        bridge = IL2ERC20Bridge(addresses[6]);
        baseFed = addresses[7];
        cctp = ICCTP(addresses[8]);

        maxSlippageBpsDolaToUsdc = maxSlippageBps[0];
        maxSlippageBpsUsdcToDola = maxSlippageBps[1];
        maxSlippageBpsUsdcNativeToDola = maxSlippageBps[2];
        maxSlippageBpsDolaToUsdcNative = maxSlippageBps[3];
        maxSlippageBpsUsdcToUsdcNative = maxSlippageBps[4];
        maxSlippageBpsUsdcNativeToUsdc = maxSlippageBps[5];
        maxSlippageBpsLiquidity = maxSlippageBpsLiquidity_;
    }

    modifier onlyRole(address role, string memory description) {
        if (msg.sender != role && msg.sender != gov) {
            revert OnlyRole(role, description);
        }
        _;
    }

    /**
     * @notice Claims all VELO token rewards accrued by this contract & transfer all VELO owned by this contract to `treasury`
     */
    function claimAeroRewards() external {
        dolaGauge.getReward(address(this));

        aeroToken.transfer(treasury, aeroToken.balanceOf(address(this)));
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

        uint expectedLpTokens = applySlippage(totalDolaValue * 1e18 / lpTokenPrice, maxSlippageBpsLiquidity);
        if (lpTokensReceived < expectedLpTokens) revert LiquiditySlippageTooHigh();
        
        uint lpBalance = LP_TOKEN.balanceOf(address(this));
        LP_TOKEN.approve(address(dolaGauge), lpBalance);
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
     * @param dolaAmount Desired dola value to remove from DOLA/USDC pool. Will attempt to remove 50/50 while allowing for `maxSlippageBpsLiquidity` bps of variance.
     * @return Amount of USDC received from liquidity removal. Used by withdrawLiquidityAndSwap wrapper.
     */
    function _withdrawLiquidity(uint dolaAmount) internal returns (uint) {
        uint lpTokenPrice = getLpTokenPrice();
        uint liquidityToWithdraw = dolaAmount * 1e18 / lpTokenPrice;
        uint ownedLiquidity = dolaGauge.balanceOf(address(this));

        if (liquidityToWithdraw > ownedLiquidity) liquidityToWithdraw = ownedLiquidity;
        dolaGauge.withdraw(liquidityToWithdraw);
   
        LP_TOKEN.approve(address(router), liquidityToWithdraw);
        (uint amountUSDC, uint amountDola) = router.removeLiquidity(address(nUSDC), address(DOLA), true, liquidityToWithdraw, 0, 0, address(this), block.timestamp);

        uint totalDolaReceived = amountDola + (amountUSDC *DOLA_USDC_CONVERSION_MULTI);

        if (applySlippage(dolaAmount, maxSlippageBpsLiquidity) > totalDolaReceived) {
            revert LiquiditySlippageTooHigh();
        }

        return amountUSDC;
    }

    /**
     * @notice Withdraws `dolaAmount` worth of LP tokens from gauge. Then, redeems LP tokens for DOLA/USDC.
     * @dev If attempting to remove more DOLA than total LP tokens are worth, will remove all LP tokens.
     * @param dolaAmount Desired dola value to remove from DOLA/USDC pool. Will attempt to remove 50/50 while allowing for `maxSlippageBpsLiquidity` bps of variance.
     * @return Amount of USDC received from liquidity removal. Used by withdrawLiquidityAndSwap wrapper.
     */
    function withdrawLiquidity(uint dolaAmount) external onlyRole(chair, "chair") returns (uint) {
        return _withdrawLiquidity(dolaAmount);
    }
 
    /**
     * @notice Withdraws `dolaAmount` worth of LP tokens from gauge. Then, redeems LP tokens for DOLA/USDC and swaps redeemed USDC to DOLA.
     * @param dolaAmount Desired dola value to remove from DOLA/USDC pool. Will attempt to remove 50/50 while allowing for `maxSlippageBpsLiquidity` bps of variance.
     */
    function withdrawLiquidityAndSwapToDOLA(uint dolaAmount) external onlyRole(chair, "chair") {
        uint usdcAmount = _withdrawLiquidity(dolaAmount);

        swapUSDCNativetoDOLA(usdcAmount);
    }
    /**
     * @notice Withdraws `dolaAmount` of DOLA to baseFed on L1. Will take 7 days before withdraw is claimable on L1.
     * @param dolaAmount Amount of DOLA to withdraw and send to L1 BaseFed
     */
    function withdrawToL1BaseFed(uint dolaAmount) external onlyRole(chair, "chair") {
        if (dolaAmount > DOLA.balanceOf(address(this))) revert NotEnoughTokens();

        bridge.withdrawTo(address(DOLA), baseFed, dolaAmount, 0, "");
    }

    /**
     * @notice Withdraws `dolaAmount` of DOLA & `usdcAmount` of USDC to baseFed on L1. Will take 7 days before withdraw is claimable on L1.
     * @param dolaAmount Amount of DOLA to withdraw and send to L1 BaseFed
     * @param usdcAmount Amount of USDC to withdraw and send to L1 BaseFed
     */
    function withdrawToL1BaseFedNative(uint dolaAmount, uint usdcAmount) external onlyRole(chair, "chair") {
        if (dolaAmount > DOLA.balanceOf(address(this))) revert NotEnoughTokens();
        if (usdcAmount > nUSDC.balanceOf(address(this))) revert NotEnoughTokens();

        bridge.withdrawTo(address(DOLA), baseFed, dolaAmount, 0, "");
        nUSDC.approve(address(cctp), usdcAmount);
        cctp.depositForBurn(usdcAmount, MAINNET_CCTP_DOMAIN, bytes32(uint256(uint160(baseFed))), address(nUSDC));
    }

    function withdrawToL1BaseFedNative(uint usdcAmount) external onlyRole(chair, "chair") {
        if (usdcAmount > nUSDC.balanceOf(address(this))) revert NotEnoughTokens();
        
        nUSDC.approve(address(cctp), usdcAmount);
        cctp.depositForBurn(usdcAmount, MAINNET_CCTP_DOMAIN, bytes32(uint256(uint160(baseFed))), address(nUSDC));
    }

    /**
     * @notice Withdraws `usdcAmount` of USDC to baseFed on L1. Will take 7 days before withdraw is claimable.
     * @param usdcAmount Amount of USDC to withdraw and send to L1 BaseFed
     */
    function withdrawToL1BaseFedBridged(uint usdcAmount) external onlyRole(chair, "chair") {
        if (usdcAmount > USDC.balanceOf(address(this))) revert NotEnoughTokens();

        bridge.withdrawTo(address(USDC), baseFed, usdcAmount, 0, "");
    }
    /**
     * @notice Withdraws `amount` of `l2Token` to address `to` on L1. Will take 7 days before withdraw is claimable.
     * @param l2Token Address of the L2 token to be withdrawn
     * @param amount Amount of the L2 token to be withdrawn
     */
    function withdrawTokensToL1(address l2Token, uint amount) external onlyRole(chair, "chair") {
        if (amount > IERC20(l2Token).balanceOf(address(this))) revert NotEnoughTokens();
        if(l2Token == address(DOLA) || l2Token == address(nUSDC) || l2Token == address(USDC) ) revert RestrictedToken();

        IERC20(l2Token).approve(address(bridge), amount);
        bridge.withdrawTo(l2Token, treasury, amount, 0, "");
    }

    /**
     * @notice Swap `usdcAmount` of USDC to DOLA through aerodrome.
     * @param usdcAmount Amount of USDC to swap to DOLA
     */
    function swapUSDCtoDOLA(uint usdcAmount) external onlyRole(chair, "chair") {
        uint minOut = applySlippage(usdcAmount, maxSlippageBpsUsdcToDola) * DOLA_USDC_CONVERSION_MULTI;

        USDC.approve(address(router), usdcAmount);
        router.swapExactTokensForTokens(usdcAmount, minOut, getRoute(address(USDC), address(DOLA)), address(this), block.timestamp);
    }

    /**
     * @notice Swap `usdcAmount` of USDC to DOLA through aerodrome.
     * @param usdcAmount Amount of USDC to swap to DOLA
     */
    function swapUSDCNativetoDOLA(uint usdcAmount) public onlyRole(chair, "chair") {
        uint minOut = applySlippage(usdcAmount, maxSlippageBpsUsdcNativeToDola) * DOLA_USDC_CONVERSION_MULTI;

        nUSDC.approve(address(router), usdcAmount);
        router.swapExactTokensForTokens(usdcAmount, minOut, getRoute(address(nUSDC), address(DOLA)), address(this), block.timestamp);
    }

    /**
     * @notice Swap `dolaAmount` of DOLA to USDC through aerodrome.
     * @param dolaAmount Amount of DOLA to swap to USDC
     */
    function swapDOLAtoUSDC(uint dolaAmount) external onlyRole(chair, "chair") { 
        uint minOut = applySlippage(dolaAmount, maxSlippageBpsDolaToUsdc) / DOLA_USDC_CONVERSION_MULTI;
        
        DOLA.approve(address(router), dolaAmount);
        router.swapExactTokensForTokens(dolaAmount, minOut, getRoute(address(DOLA), address(USDC)), address(this), block.timestamp);
    }

    /**
     * @notice Swap `dolaAmount` of DOLA to USDC Native through aerodrome.
     */
    function swapDOLAtoUSDCNative(uint dolaAmount) external onlyRole(chair, "chair") { 
        uint minOut = applySlippage(dolaAmount, maxSlippageBpsDolaToUsdcNative) / DOLA_USDC_CONVERSION_MULTI;
        
        DOLA.approve(address(router), dolaAmount);
        router.swapExactTokensForTokens(dolaAmount, minOut, getRoute(address(DOLA), address(nUSDC)), address(this), block.timestamp);
    }

    /**
     * @notice Swap `usdcAmount` of USDC to USDC Native through aerodrome.
     */
    function swapUSDCtoUSDCNative(uint usdcAmount) external onlyRole(chair, "chair") {
        uint minOut = applySlippage(usdcAmount, maxSlippageBpsUsdcToUsdcNative);
        USDC.approve(address(router), usdcAmount);
        router.swapExactTokensForTokens(usdcAmount, minOut, getRoute(address(USDC), address(nUSDC)), address(this), block.timestamp);
    }

    /**
     * @notice Swap `usdcAmount` of USDC Native to USDC through aerodrome.
     */
    function swapUSDCNativeToUSDC(uint usdcAmount) public onlyRole(chair, "chair") {
        uint minOut = applySlippage(usdcAmount, maxSlippageBpsUsdcNativeToUsdc);

        nUSDC.approve(address(router), usdcAmount);
        router.swapExactTokensForTokens(usdcAmount, minOut, getRoute(address(nUSDC), address(USDC)), address(this), block.timestamp);
    }


    /**
     * @notice Calculates approximate price of 1 Aerodrome DOLA/USDC stable pool LP token
     */
    function getLpTokenPrice() internal view returns (uint) {
        (uint dolaAmountOneLP, uint usdcAmountOneLP) = router.quoteRemoveLiquidity(address(DOLA), address(nUSDC), true, factory, 0.001 ether);
        usdcAmountOneLP *= DOLA_USDC_CONVERSION_MULTI;
        return (dolaAmountOneLP + usdcAmountOneLP)*1000;
    }

    function applySlippage(uint amount, uint maxSlippage) internal pure returns(uint) {
        return amount * (PRECISION - maxSlippage) / PRECISION;
    }

    /**
     * @notice Generate route array for swap between two stablecoins
     * @param from Token to go from
     * @param to Token to go to
     * @return Returns a Route[] with a single element, representing the route
     */
    function getRoute(address from, address to) internal view returns(IRouter.Route[] memory){
        IRouter.Route memory route = IRouter.Route(from, to, true, factory);
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
    function setMaxSlippageDolaToUsdc(uint newMaxSlippageBps) onlyRole(guardian, "Only Gov Or Guardian") external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsDolaToUsdc = newMaxSlippageBps;
    }

    /**
     * @notice Governance only function for setting acceptable slippage when swapping USDC -> DOLA
     * @param newMaxSlippageBps The new maximum allowed loss for USDC -> DOLA swaps. 1 = 0.01%
     */
    function setMaxSlippageUsdcToDola(uint newMaxSlippageBps) onlyRole(guardian, "Only Gov Or Guardian") external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsUsdcToDola = newMaxSlippageBps;
    }

    function setMaxSlippageUsdcNativeToDola(uint newMaxSlippageBps) onlyRole(guardian, "Only Gov Or Guardian") external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsUsdcNativeToDola = newMaxSlippageBps;
    }

    function setMaxSlippageDolaToUsdcNative(uint newMaxSlippageBps) onlyRole(guardian, "Only Gov Or Guardian") external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsDolaToUsdcNative = newMaxSlippageBps;
    }

    function setMaxSlippageUsdcToUsdcNative(uint newMaxSlippageBps) onlyRole(guardian, "Only Gov Or Guardian") external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsUsdcToUsdcNative = newMaxSlippageBps;
    }

    function setMaxSlippageUsdcNativeToUsdc(uint newMaxSlippageBps) onlyRole(guardian, "Only Gov Or Guardian") external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsUsdcNativeToUsdc = newMaxSlippageBps;
    }

    /**
     * @notice Governance only function for setting acceptable slippage when adding or removing liquidty from DOLA/USDC pool
     * @param newMaxSlippageBps The new maximum allowed loss for adding/removing liquidity from DOLA/USDC pool. 1 = 0.01%
     */
    function setMaxSlippageLiquidity(uint newMaxSlippageBps) onlyRole(guardian, "Only Gov Or Guardian") external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsLiquidity = newMaxSlippageBps;
    }

    /**
     * @notice Method for `gov` to change `pendingGov` address
     * @dev `pendingGov` will have to call `claimGov` to complete `gov` transfer
     * @dev `pendingGov` should be an L1 address
     * @param newPendingGov_ L1 address to be set as `pendingGov`
     */
    function setPendingGov(address newPendingGov_) onlyRole(gov, "Only Gov") external {
        pendingGov = newPendingGov_;
    }

    /**
     * @notice Method for `pendingGov` to claim `gov` role.
     */
    function claimGov() external onlyRole(pendingGov, "Only Pending Gov") {
        gov = pendingGov;
        pendingGov = address(0);
    }

    /**
     * @notice Method for gov to change treasury address, the address that receives all rewards
     * @param newTreasury_ L2 address to be set as treasury
     */
    function changeTreasury(address newTreasury_) external onlyRole(gov, "Only Gov") {
        treasury = newTreasury_;
    }

    /**
     * @notice Method for gov to change the chair
     * @param newChair_ address to be set as chair
     */
    function changeChair(address newChair_) external onlyRole(gov, "Only Gov") {
        chair = newChair_;
    }

    /**
     * @notice Method for gov to change the guardian
     * @param guardian_ L1 address to be set as guardian
     */
    function changeGuardian(address guardian_) external onlyRole(gov, "Only Gov") {
        guardian = guardian_;
    }

    /**
     * @notice Method for gov to change the L1 baseFed address
     * @dev baseFed is the L1 address that receives all bridged DOLA/USDC from both withdrawToL1BaseFed functions
     * @param newBaseFed_ L1 address to be set as baseFed
     */
    function changeBaseFed(address newBaseFed_) external onlyRole(gov, "Only Gov") {
        baseFed = newBaseFed_;
    }
}
