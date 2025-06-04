// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "src/interfaces/IERC20.sol";
import "src/interfaces/IDola.sol";
import "src/interfaces/IL1ERC20Bridge.sol";
import {Chairable} from "src/utils/Chairable.sol";

interface ICCTP {
    /**
     * @notice Deposits and burns tokens from sender to be minted on destination domain.
     * Emits a `DepositForBurn` event.
     * @dev reverts if:
     * - given burnToken is not supported
     * - given destinationDomain has no TokenMessenger registered
     * - transferFrom() reverts. For example, if sender's burnToken balance or approved allowance
     * to this contract is less than `amount`.
     * - burn() reverts. For example, if `amount` is 0.
     * - MessageTransmitter returns false or reverts.
     * @param amount amount of tokens to burn
     * @param destinationDomain destination domain
     * @param mintRecipient address of mint recipient on destination domain
     * @param burnToken address of contract to burn deposited tokens, on local domain
     * @return _nonce unique nonce reserved by message
     */
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken
    ) external returns (uint64 _nonce);
}

interface IChainlinkPriceFeed {
    function decimals() external view returns (uint8);
    function latestAnswer() external view returns (int256);
}

/**
 * @title SuperChainCCTPFed
 * @notice A generic contract for SuperChain CCTP Feds
 */
contract SuperChainCCTPFed is Chairable {
    error CantBurnZeroDOLA();
    error MaxSlippageTooHigh();
    error SlippageTooHigh();
    error SwapMoreDolaThanMinted();
    error SwapFailed();
    error ZeroAddressParameter();
    error InvalidProxyAddress();
    error InvalidDepegThreshold();
    error BelowDepegThreshold();

    uint256 public dolaSupply;
    uint256 public maxSlippageBpsDolaToUsdc;
    uint256 public maxSlippageBpsUsdcToDola;
    uint256 public depegThreshold = 0.98e18; // 0.98 USDC/USD
    address public farmer;

    mapping(address => bool) public isExchangeProxy;

    uint256 public constant PRECISION = 10_000;
    uint256 public constant DOLA_USDC_CONVERSION_MULTI = 1e12;

    IDola public constant DOLA =
        IDola(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public constant USDC =
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ICCTP public constant CCTP =
        ICCTP(0xBd3fa81B58Ba92a82136038B25aDec7066af3155);
    IChainlinkPriceFeed public constant USDC_FEED = IChainlinkPriceFeed(0x5B4e043d614809A4b240Ed4Be7D1589f7871a749); // 18 decimals

    IL1ERC20Bridge public immutable BRIDGE;
    address public immutable DOLA_CHAIN;
    address public immutable USDC_CHAIN;
    uint32 public immutable CCTP_DOMAIN;

    event Expansion(uint256 amount);
    event Contraction(uint256 amount);
    event NewFarmer(address indexed oldFarmer, address indexed newFarmer);
    event NewExchangeProxy(
        address indexed oldExchangeProxy,
        bool isAllowed
    );
    event NewMaxSlippageDolaToUsdc(
        uint256 oldMaxSlippageBps,
        uint256 newMaxSlippageBps
    );
    event NewMaxSlippageUsdcToDola(
        uint256 oldMaxSlippageBps,
        uint256 newMaxSlippageBps
    );
    event NewDepegThreshold(uint256 newDepegThreshold);
    event SwapDOLAtoUSDC(uint256 dolaAmount, uint256 usdcAmount);
    event SwapUSDCtoDOLA(uint256 usdcAmount, uint256 dolaAmount);

    constructor(
        address gov_,
        address chair_,
        uint256 maxSlippageBpsDolaToUsdc_,
        uint256 maxSlippageBpsUsdcToDola_,
        address bridge_,
        address dola_chain_,
        address usdc_chain_,
        uint32 domain_
    ) Chairable(gov_, chair_) {
        maxSlippageBpsDolaToUsdc = maxSlippageBpsDolaToUsdc_;
        maxSlippageBpsUsdcToDola = maxSlippageBpsUsdcToDola_;
        BRIDGE = IL1ERC20Bridge(bridge_);
        DOLA_CHAIN = dola_chain_;
        USDC_CHAIN = usdc_chain_;
        CCTP_DOMAIN = domain_;
    }

    /**
     * @notice Mints `dolaAmount` of DOLA, swaps `dolaToSwap` of DOLA to USDC, then transfers all to `farmer` through L1 bridge
     * @param dolaAmount Amount of DOLA to mint
     * @param dolaToSwap Amount of DOLA to swap for USDC
     * @param useCCTP If true, will use CCTP to bridge USDC. If false, will use L1 bridge
     * @param swapCallData Data for calling the exchange proxy to swap DOLA for USDC
     * @param exchangeProxy Address of the exchange proxy to use for the swap
     */
    function expansionAndSwap(
        uint256 dolaAmount,
        uint256 dolaToSwap,
        bool useCCTP,
        bytes calldata swapCallData,
        address exchangeProxy
    ) external onlyChair {
        if (dolaToSwap > dolaAmount) revert SwapMoreDolaThanMinted();
        if(!isExchangeProxy[exchangeProxy]) revert InvalidProxyAddress();
        _revertIfBelowDepegThreshold();

        dolaSupply += dolaAmount;
        DOLA.mint(address(this), dolaAmount);

        DOLA.approve(exchangeProxy, dolaToSwap);
        uint256 usdcAmountBefore = USDC.balanceOf(address(this));

        (bool success, ) = exchangeProxy.call(swapCallData);
        if (!success) revert SwapFailed();

        uint256 usdcAmountAfter = USDC.balanceOf(address(this));
        uint256 usdcAmount = usdcAmountAfter - usdcAmountBefore;

        if (
            usdcAmount <
            (dolaToSwap * (PRECISION - maxSlippageBpsDolaToUsdc)) /
                PRECISION /
                DOLA_USDC_CONVERSION_MULTI
        ) {
            revert SlippageTooHigh();
        }

        uint256 dolaToBridge = dolaAmount - dolaToSwap;
        DOLA.approve(address(BRIDGE), dolaToBridge);

        BRIDGE.depositERC20To(
            address(DOLA),
            DOLA_CHAIN,
            farmer,
            dolaToBridge,
            200_000,
            ""
        );

        if (useCCTP) {
            USDC.approve(address(CCTP), usdcAmount);
            CCTP.depositForBurn(
                usdcAmount,
                CCTP_DOMAIN,
                bytes32(uint256(uint160(farmer))),
                address(USDC)
            );
        } else {
            USDC.approve(address(BRIDGE), usdcAmount);
            BRIDGE.depositERC20To(
                address(USDC),
                USDC_CHAIN,
                farmer,
                usdcAmount,
                200_000,
                ""
            );
        }

        emit Expansion(dolaAmount);
    }

    /**
     * @notice Mints & deposits `amountUnderlying` of `underlying` tokens into L1 bridge to the `farmer` contract
     * @param dolaAmount Amount of underlying token to mint & deposit into the farmer on the SuperChain
     */
    function expansion(uint256 dolaAmount) external onlyChair {
        dolaSupply += dolaAmount;
        DOLA.mint(address(this), dolaAmount);

        DOLA.approve(address(BRIDGE), dolaAmount);
        BRIDGE.depositERC20To(
            address(DOLA),
            DOLA_CHAIN,
            farmer,
            dolaAmount,
            200_000,
            ""
        );

        emit Expansion(dolaAmount);
    }

    /**
     * @notice Burns `dolaAmount` of DOLA held in this contract
     * @param dolaAmount Amount of DOLA to burn
     */
    function contraction(uint256 dolaAmount) public onlyChair {
        _contraction(dolaAmount);
    }

    /**
     * @notice Attempts to contract (burn) all DOLA held by this contract
     */
    function contractAll() external onlyChair {
        _contraction(DOLA.balanceOf(address(this)));
    }

    /**
     * @notice Attempts to contract (burn) `amount` of DOLA. Sends remainder to `gov` if `amount` > DOLA minted by this fed.
     * @param amount Amount of DOLA to contract.
     */
    function _contraction(uint256 amount) internal {
        if (amount == 0) revert CantBurnZeroDOLA();
        if (amount > dolaSupply) {
            DOLA.burn(dolaSupply);
            DOLA.transfer(gov, amount - dolaSupply);
            emit Contraction(dolaSupply);
            dolaSupply = 0;
        } else {
            DOLA.burn(amount);
            dolaSupply -= amount;
            emit Contraction(amount);
        }
    }

    /**
     * @notice Swap `usdcAmount` of USDC for DOLA through the exchange proxy.
     * @dev Will revert if actual slippage > `maxSlippageBpsUsdcToDola`
     * @param usdcAmount Amount of USDC to be swapped to DOLA through the exchange proxy.
     * @param swapCallData Data for calling the exchange proxy to swap USDC for DOLA
     * @param exchangeProxy Address of the exchange proxy to use for the swap
     */
    function swapUSDCtoDOLA(
        uint256 usdcAmount,
        bytes calldata swapCallData,
        address exchangeProxy
    ) external onlyChair {
        if(!isExchangeProxy[exchangeProxy]) revert InvalidProxyAddress();
        _revertIfBelowDepegThreshold();

        USDC.approve(exchangeProxy, usdcAmount);
        uint256 dolaAmountBefore = DOLA.balanceOf(address(this));

        (bool success, ) = exchangeProxy.call(swapCallData);
        if (!success) revert SwapFailed();

        uint256 dolaAmount = DOLA.balanceOf(address(this)) - dolaAmountBefore;
        if (
            dolaAmount <
            (usdcAmount *
                (PRECISION - maxSlippageBpsUsdcToDola) *
                DOLA_USDC_CONVERSION_MULTI) /
                PRECISION
        ) {
            revert SlippageTooHigh();
        }
        emit SwapUSDCtoDOLA(usdcAmount, dolaAmount);
    }

    /**
     * @notice Swap `dolaAmount` of DOLA for USDC through the exchange proxy.
     * @dev Will revert if actual slippage > `maxSlippageBpsDolaToUsdc`
     * @param dolaAmount Amount of DOLA to be swapped to USDC through the exchange proxy.
     * @param swapCallData Data for calling the exchange proxy to swap DOLA for USDC
     * @param exchangeProxy Address of the exchange proxy to use for the swap
     */
    function swapDOLAtoUSDC(
        uint256 dolaAmount,
        bytes calldata swapCallData,
        address exchangeProxy
    ) external onlyChair {
        if(!isExchangeProxy[exchangeProxy]) revert InvalidProxyAddress();
        _revertIfBelowDepegThreshold();

        DOLA.approve(exchangeProxy, dolaAmount);
        uint256 usdcAmountBefore = USDC.balanceOf(address(this));
        (bool success, ) = exchangeProxy.call(swapCallData);
        if (!success) revert SwapFailed();
        uint256 usdcAmount = USDC.balanceOf(address(this)) - usdcAmountBefore;
        if (
            usdcAmount <
            (dolaAmount * (PRECISION - maxSlippageBpsDolaToUsdc)) /
                DOLA_USDC_CONVERSION_MULTI /
                PRECISION
        ) {
            revert SlippageTooHigh();
        }
        emit SwapDOLAtoUSDC(dolaAmount, usdcAmount);
    }

    /**
     * @notice Reverts if the USDC feed price (normalized with 18 decimals) is below the depeg threshold
     */
    function _revertIfBelowDepegThreshold() internal view {
        if (USDC_FEED.latestAnswer() < int256(depegThreshold)) revert BelowDepegThreshold();
    }

    /**
     * @notice Governance only function for allowing or disallowing an exchange proxy to be used for swaps
     * @param _proxy The address of the exchange proxy
     * @param _isAllowed Whether the exchange proxy is allowed to be used for swaps
     */
    function setExchangeProxy(address _proxy, bool _isAllowed) external onlyGov {
        if (_proxy == address(0)) revert ZeroAddressParameter();
        isExchangeProxy[_proxy] = _isAllowed;
        emit NewExchangeProxy(_proxy, _isAllowed);
    }

    /**
     * @notice Governance only function for setting acceptable depeg threshold
     * @param newDepegThreshold The new depeg price threshold. (18 decimals)
     */
    function setDepegThreshold(uint256 newDepegThreshold) external onlyGov {
        uint8 decimals = USDC_FEED.decimals();
        if (newDepegThreshold > 10 ** decimals || newDepegThreshold < 10 ** (decimals -1)) revert InvalidDepegThreshold();
        depegThreshold = newDepegThreshold;
        emit NewDepegThreshold(newDepegThreshold);
    }
    /**
     * @notice Governance only function for setting acceptable slippage when swapping DOLA -> USDC
     * @param newMaxSlippageBps The new maximum allowed loss for DOLA -> USDC swaps. 1 = 0.01%
     */
    function setMaxSlippageDolaToUsdc(
        uint256 newMaxSlippageBps
    ) external onlyGov {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        emit NewMaxSlippageDolaToUsdc(
            maxSlippageBpsDolaToUsdc,
            newMaxSlippageBps
        );
        maxSlippageBpsDolaToUsdc = newMaxSlippageBps;
    }

    /**
     * @notice Governance only function for setting acceptable slippage when swapping USDC -> DOLA
     * @param newMaxSlippageBps The new maximum allowed loss for USDC -> DOLA swaps. 1 = 0.01%
     */
    function setMaxSlippageUsdcToDola(
        uint256 newMaxSlippageBps
    ) external onlyGov {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        emit NewMaxSlippageUsdcToDola(
            maxSlippageBpsUsdcToDola,
            newMaxSlippageBps
        );
        maxSlippageBpsUsdcToDola = newMaxSlippageBps;
    }

    /**
    @notice Method for gov to change the L2 farmer address
    @dev farmer is the L2 address that receives all bridged DOLA from expansion
    @param newFarmer L2 address to be set as farmer
    */
    function changeFarmer(address newFarmer) external onlyGov {
        if (newFarmer == address(0)) revert ZeroAddressParameter();
        emit NewFarmer(farmer, newFarmer);
        farmer = newFarmer;
    }
}
