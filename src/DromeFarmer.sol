// SPDX-License-Identifier: MIT
import {IRouter} from "src/interfaces/IRouter.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IGauge} from "src/interfaces/IGauge.sol";
import {IL2ERC20Bridge} from "src/interfaces/IL2ERC20Bridge.sol";
import {ICrossDomainMessenger} from "src/interfaces/ICrossDomainMessenger.sol";
import {ICCTP} from "src/interfaces/ICCTP.sol";

pragma solidity ^0.8.13;

interface IPool is IERC20 {
    function getReserves() external view returns (uint256, uint256, uint256);
}

interface IChainlinkPriceFeed {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function decimals() external view returns (uint8);
}

contract DromeFarmer {
    address public chair;
    address public pendingGov;
    address public gov;
    address public TWG;
    address public guardian;
    address public l1Fed;

    mapping(address => mapping(address => uint256)) public maxSwapSlippage;
    mapping(address => bool) public allowedSwaps;
    uint256 public maxSlippageBps;
    uint256 public maxGuardianSetableSlippageBps = 500;
    uint256 public emergencyPriceThreshold = 0.98e8; //Chainlink price threshold below which guardian role can fully set slippage parameters
    uint256 public USDCPriceThreshold = 0.995e8; //Chainlink price threshold below which no purchases of USDC may be made

    uint256 public constant DOLA_USDC_CONVERSION_MULTI = 1e12;
    ICrossDomainMessenger public constant ovmL2CrossDomainMessenger =
        ICrossDomainMessenger(0x4200000000000000000000000000000000000007);
    IL2ERC20Bridge public constant bridge = IL2ERC20Bridge(0x4200000000000000000000000000000000000010);
    IChainlinkPriceFeed public immutable usdcPriceFeed;

    IGauge public immutable dolaGauge;
    IPool public immutable lpToken;
    IERC20 public immutable rewardToken;
    IRouter public immutable router;
    IERC20 public immutable DOLA;
    IERC20 public immutable nUSDC;
    IERC20 public immutable USDC;
    ICCTP public immutable cctp;

    error OnlyRole(address, string);
    error OnlyL1Role(address, string);
    error MaxSlippageTooHigh();
    error NotEnoughTokens();
    error SlippageTooHigh();

    struct Admin {
        address chair;
        address guardian;
        address l2Treasury;
        address govMessenger;
    }

    constructor(
        Admin memory admin,
        address cctpBridge,
        address _l1Fed,
        address _dola,
        address _usdc,
        address _nusdc,
        IChainlinkPriceFeed _usdcPriceFeed,
        IRouter _router,
        IGauge _dolaGauge
    ) {
        gov = admin.govMessenger;
        chair = admin.chair;
        TWG = admin.l2Treasury;
        guardian = admin.guardian;
        cctp = ICCTP(cctpBridge);
        l1Fed = _l1Fed;
        DOLA = IERC20(_dola);
        USDC = IERC20(_usdc);
        nUSDC = IERC20(_nusdc);
        router = _router;
        dolaGauge = _dolaGauge;
        usdcPriceFeed = _usdcPriceFeed;
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
        if (msg.sender != address(ovmL2CrossDomainMessenger)) {
            revert OnlyL1Role(role, description);
        }
        address messageSender = ovmL2CrossDomainMessenger.xDomainMessageSender();
        if (messageSender != role) {
            revert OnlyL1Role(role, description);
        }
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
    function _deposit(uint256 dolaAmount, uint256 usdcAmount) internal {
        uint256 lpTokenPrice = getLpTokenPrice();

        DOLA.approve(address(router), dolaAmount);
        nUSDC.approve(address(router), usdcAmount);
        (uint256 dolaSpent, uint256 usdcSpent, uint256 lpTokensReceived) = router.addLiquidity(
            address(DOLA), address(nUSDC), true, dolaAmount, usdcAmount, 0, 0, address(this), block.timestamp
        );
        require(lpTokensReceived > 0, "No LP tokens received");
        if (usdcSpent * DOLA_USDC_CONVERSION_MULTI < dolaSpent) {
            require(priceAboveThreshold(USDCPriceThreshold), "price below min threshold");
        }

        uint256 totalDolaValue = usdcSpent * DOLA_USDC_CONVERSION_MULTI + dolaSpent;

        uint256 expectedLpTokens = applySlippage(totalDolaValue * 1e18 / lpTokenPrice, maxSlippageBps);
        if (lpTokensReceived < expectedLpTokens) revert SlippageTooHigh();

        uint256 lpBalance = lpToken.balanceOf(address(this));
        lpToken.approve(address(dolaGauge), lpBalance);
        dolaGauge.deposit(lpBalance);
    }

    /**
     * @notice Attempts to deposit `dolaAmount` of DOLA & `usdcAmount` of USDC into Aerodrome DOLA/USDC stable pool. Then, deposits LP tokens into gauge.
     * @param dolaAmount Amount of DOLA to be added as liquidity in Aerodrome DOLA/USDC pool
     * @param usdcAmount Amount of USDC to be added as liquidity in Aerodrome DOLA/USDC pool
     */
    function deposit(uint256 dolaAmount, uint256 usdcAmount) external onlyRole(chair, "chair") {
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
    function _withdraw(uint256 dolaAmount) internal returns (uint256) {
        uint256 lpTokenPrice = getLpTokenPrice();
        uint256 liquidityToWithdraw = dolaAmount * 1e18 / lpTokenPrice;
        uint256 owned = dolaGauge.balanceOf(address(this));

        if (liquidityToWithdraw > owned) liquidityToWithdraw = owned;
        dolaGauge.withdraw(liquidityToWithdraw);

        lpToken.approve(address(router), liquidityToWithdraw);
        (uint256 amountUSDC, uint256 amountDola) = router.removeLiquidity(
            address(nUSDC), address(DOLA), true, liquidityToWithdraw, 0, 0, address(this), block.timestamp
        );

        uint256 totalDolaValueReceived = amountDola + getDolaPrice(amountUSDC);

        if (applySlippage(dolaAmount, maxSlippageBps) > totalDolaValueReceived) {
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
    function withdraw(uint256 dolaAmount) external onlyRole(chair, "chair") returns (uint256) {
        return _withdraw(dolaAmount);
    }

    /**
     * @notice Withdraws `dolaAmount` worth of LP tokens from gauge. Then, redeems LP tokens for DOLA/USDC and swaps redeemed USDC to DOLA.
     * @param dolaAmount Desired dola value to remove from DOLA/USDC pool. Will attempt to remove 50/50 while allowing for `maxSlippageBps` bps of variance.
     */
    function withdrawAndSwapToDOLA(address sellStable, uint256 dolaAmount) external onlyRole(chair, "chair") {
        uint256 usdcAmount = _withdraw(dolaAmount);
        swapStables(sellStable, address(DOLA), usdcAmount);
    }
    /**
     * @notice Withdraws `dolaAmount` of DOLA to l1Fed on L1. Will take 7 days before withdraw is claimable on L1.
     * @param dolaAmount Amount of DOLA to withdraw and send to L1 Fed
     */

    function withdrawToL1Fed(uint256 dolaAmount) external onlyRole(chair, "chair") {
        if (dolaAmount > DOLA.balanceOf(address(this))) revert NotEnoughTokens();

        bridge.withdrawTo(address(DOLA), l1Fed, dolaAmount, 0, "");
    }

    /**
     * @notice Withdraws `dolaAmount` of DOLA & `usdcAmount` of USDC to l1Fed on L1. Will take 7 days before withdraw is claimable on L1.
     * @param dolaAmount Amount of DOLA to withdraw and send to L1 Fed
     * @param usdcAmount Amount of USDC to withdraw and send to L1 Fed
     */
    function withdrawToL1FedNative(uint256 dolaAmount, uint256 usdcAmount) external onlyRole(chair, "chair") {
        if (dolaAmount > DOLA.balanceOf(address(this))) revert NotEnoughTokens();
        if (usdcAmount > nUSDC.balanceOf(address(this))) revert NotEnoughTokens();

        bridge.withdrawTo(address(DOLA), l1Fed, dolaAmount, 0, "");
        nUSDC.approve(address(cctp), usdcAmount);
        cctp.depositForBurn(usdcAmount, 0, bytes32(uint256(uint160(l1Fed))), address(nUSDC));
    }

    function withdrawToL1FedNative(uint256 usdcAmount) external onlyRole(chair, "chair") {
        if (usdcAmount > nUSDC.balanceOf(address(this))) revert NotEnoughTokens();

        nUSDC.approve(address(cctp), usdcAmount);
        cctp.depositForBurn(usdcAmount, 0, bytes32(uint256(uint160(l1Fed))), address(nUSDC));
    }

    /**
     * @notice Withdraws `usdcAmount` of USDC to l1Fed on L1. Will take 7 days before withdraw is claimable.
     * @param usdcAmount Amount of USDC to withdraw and send to L1 Fed
     */
    function withdrawToL1FedBridged(uint256 usdcAmount) external onlyRole(chair, "chair") {
        if (usdcAmount > USDC.balanceOf(address(this))) revert NotEnoughTokens();

        bridge.withdrawTo(address(USDC), l1Fed, usdcAmount, 0, "");
    }
    /**
     * @notice Swap `usdcAmount` of USDC to DOLA through aerodrome.
     * @param sellStable Gov approved stable to sell
     * @param buyStable Gov approved stable to buy
     * @param amount Amount of sellStable to swap for buyStable
     */

    function swapStables(address sellStable, address buyStable, uint256 amount) public onlyRole(chair, "chair") {
        require(sellStable != buyStable, "same stable");
        require(allowedSwaps[sellStable], "sellStable not allowed");
        require(allowedSwaps[buyStable], "buyStable not allowed");
        if (buyStable == address(USDC) || buyStable == address(nUSDC)) {
            require(priceAboveThreshold(USDCPriceThreshold), "price below min threshold");
        }
        uint256 minOut = applySwapSlippage(amount, sellStable, buyStable);

        IERC20(sellStable).approve(address(router), amount);
        router.swapExactTokensForTokens(amount, minOut, getRoute(sellStable, buyStable), address(this), block.timestamp);
    }

    function getLpTokenPrice() internal view returns (uint256) {
        (uint256 reservesDOLA, uint256 reservesNUSDC,) = lpToken.getReserves();
        uint256 k = _k(reservesDOLA, reservesNUSDC, 10 ** DOLA.decimals(), 10 ** nUSDC.decimals());
        return 2 * sqrt(sqrt(k / 2)) * 1e18 / lpToken.totalSupply();
    }

    // We assume DOLA is always worth 1$
    function getDolaPrice(uint256 usdcAmount) public view returns (uint256) {
        (, int256 usdcPrice,,,) = usdcPriceFeed.latestRoundData();
        if (usdcPrice <= 0) return 1;
        uint8 decimals = usdcPriceFeed.decimals();
        uint256 normalizedAmount = usdcAmount * DOLA_USDC_CONVERSION_MULTI;
        //If usdcPrice > 1$ cap price at 1$
        if (uint256(usdcPrice) > 10 ** decimals) return normalizedAmount;
        return normalizedAmount * uint256(usdcPrice) / 10 ** decimals;
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
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        y *= 1e18;
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    //Helper function for checking if the usdc oracle price is above the threshold price
    function priceAboveThreshold(uint256 threshold) public view returns (bool) {
        (, int256 usdcPrice,,,) = usdcPriceFeed.latestRoundData();
        return usdcPrice > int256(threshold);
    }

    function applySwapSlippage(uint256 amount, address sellStable, address buyStable) internal view returns (uint256) {
        uint256 sellStableDecimals = IERC20(sellStable).decimals();
        uint256 buyStableDecimals = IERC20(buyStable).decimals();
        if (sellStableDecimals > buyStableDecimals) {
            return applySlippage(amount, maxSwapSlippage[sellStable][buyStable])
                / (10 ** (sellStableDecimals - buyStableDecimals));
        }
        return applySlippage(amount, maxSwapSlippage[sellStable][buyStable])
            * (10 ** (buyStableDecimals - sellStableDecimals));
    }

    function applySlippage(uint256 amount, uint256 maxSlippage) internal pure returns (uint256) {
        return amount * (10000 - maxSlippage) / 10000;
    }

    /**
     * @notice Generate route array for swap between two stablecoins
     * @param from Token to go from
     * @param to Token to go to
     * @return Returns a Route[] with a single element, representing the route
     */
    function getRoute(address from, address to) internal view returns (IRouter.Route[] memory) {
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
    function setMaxSwapSlippage(address stable1, address stable2, uint256 newMaxSlippageBps)
        external
        onlyRole(guardian, "guardian")
    {
        if (priceAboveThreshold(emergencyPriceThreshold) && newMaxSlippageBps > maxGuardianSetableSlippageBps) {
            revert MaxSlippageTooHigh();
        }
        maxSwapSlippage[stable1][stable2] = newMaxSlippageBps;
        maxSwapSlippage[stable2][stable1] = newMaxSlippageBps;
    }

    /**
     * @notice Governance only function for setting acceptable slippage when adding or removing liquidty from DOLA/USDC pool
     * @param newMaxSlippageBps The new maximum allowed loss for adding/removing liquidity from DOLA/USDC pool. 1 = 0.01%
     */
    function setMaxSlippageLP(uint256 newMaxSlippageBps) external onlyRole(guardian, "guardian") {
        if (priceAboveThreshold(emergencyPriceThreshold) && newMaxSlippageBps > maxGuardianSetableSlippageBps) {
            revert MaxSlippageTooHigh();
        }
        maxSlippageBps = newMaxSlippageBps;
    }

    /**
     * @notice Sets the depeg emergency price threshold.
     * @dev The emergency price threshold limits the powers of the guardian role to set slippage params when above it.
     * @param _emergencyPriceThreshold Depeg emergency price threshold. Uses the price decimals of the underlying chainlink oracle. For USDC that will be 8 decimals. 
     */
    function setEmergencyPriceThreshold(uint256 _emergencyPriceThreshold) external onlyL1Role(gov, "gov") {
        uint8 decimals = usdcPriceFeed.decimals();
        require(_emergencyPriceThreshold <= 10 ** decimals && _emergencyPriceThreshold >= 10 ** (decimals - 1));
        emergencyPriceThreshold = _emergencyPriceThreshold;
    }
    /**
     * @notice Sets the USDC price threshold, below which the fed is blocked from buying USDC.
     * @dev The USDC Price Threshold limits the ability of the fed to buy USDC if the stable is depegging
     * @param _USDCPriceThreshold The USDC Price Threshold. Uses the decimals of the underlying chainlink oracle. For USDC that will be 8 decimals.
     */
    function setUSDCPriceThreshold(uint256 _USDCPriceThreshold) external onlyL1Role(gov, "gov") {
        uint8 decimals = usdcPriceFeed.decimals();
        require(_USDCPriceThreshold <= 10 ** decimals && _USDCPriceThreshold >= 10 ** (decimals - 1));
        USDCPriceThreshold = _USDCPriceThreshold;
    }

    /**
     * @notice Sets the maximum slippage setable by the guardian role
     * @param _maxGuardianSetableSlippageBps Max slippage in BPS setable by the guardian role
     */
    function setMaxGuardianSetableSlippageBps(uint256 _maxGuardianSetableSlippageBps) external onlyL1Role(gov, "gov") {
        if (_maxGuardianSetableSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxGuardianSetableSlippageBps = _maxGuardianSetableSlippageBps;
    }

    /**
     * @notice Withdraws `amount` of `l2Token` to the TWG address.
     * @dev Make sure the TWG address is either a trusted multisig or smart contract before calling this function!
     * @param l2Token Address of the L2 token to be withdrawn
     * @param amount Amount of the L2 token to be withdrawn
     */
    function emergencyWithdraw(address l2Token, uint256 amount) external onlyL1Role(gov, "gov") {
        if (amount > IERC20(l2Token).balanceOf(address(this))) revert NotEnoughTokens();
        IERC20(l2Token).transfer(TWG, amount);
    }

    /**
     * @notice Method for `gov` to change `pendingGov` address
     * @dev `pendingGov` will have to call `claimGov` to complete `gov` transfer
     * @dev `pendingGov` should be an L1 address
     * @param _pendingGov L1 address to be set as `pendingGov`
     */
    function setPendingGov(address _pendingGov) external onlyL1Role(gov, "gov") {
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
