// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "src/interfaces/IERC20.sol";
import "src/interfaces/IDola.sol";
import "src/interfaces/IL1ERC20Bridge.sol";
import "src/interfaces/ICurvePool.sol";

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


contract BaseFedCCTP {
    address public chair;
    address public gov;
    address public pendingGov;
    uint public dolaSupply;
    uint public maxSlippageBpsDolaToUsdc;
    uint public maxSlippageBpsUsdcToDola;

    uint constant PRECISION = 10_000;
    uint public constant DOLA_USDC_CONVERSION_MULTI= 1e12;

    IDola public constant DOLA = IDola(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IL1ERC20Bridge public constant baseBridge = IL1ERC20Bridge(0x3154Cf16ccdb4C6d922629664174b904d80F2C35);
    address public constant DOLA_BASE = 0x4621b7A9c75199271F773Ebd9A499dbd165c3191;
    address public constant USDC_BASE = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;
    ICurvePool public curvePool = ICurvePool(0xE57180685E3348589E9521aa53Af0BCD497E884d);
    ICCTP public constant CCTP = ICCTP(0xBd3fa81B58Ba92a82136038B25aDec7066af3155);
    uint32 public constant BASE_CCTP_DOMAIN = 6;
    int128 public dolaIndex = 0;
    int128 public usdcIndex = 2;
    address public aeroFarmer;

    event Expansion(uint amount);
    event Contraction(uint amount);

    error OnlyGov();
    error OnlyPendingGov();
    error OnlyChair();
    error CantBurnZeroDOLA();
    error MaxSlippageTooHigh();
    error DeltaAboveMax();
    error SwapMoreDolaThanMinted();

    constructor(
            address gov_,
            address chair_,
            address aeroFarmer_,
            uint maxSlippageBpsDolaToUsdc_,
            uint maxSlippageBpsUsdcToDola_)
    {
        gov = gov_;
        chair = chair_;
        aeroFarmer = aeroFarmer_;
        maxSlippageBpsDolaToUsdc = maxSlippageBpsDolaToUsdc_;
        maxSlippageBpsUsdcToDola = maxSlippageBpsUsdcToDola_;
    }

    /**
    @notice Mints `dolaAmount` of DOLA, swaps `dolaToSwap` of DOLA to USDC, then transfers all to `aeroFarmer` through base bridge
    @param dolaAmount Amount of DOLA to mint
    @param dolaToSwap Amount of DOLA to swap for USDC
    @param useCCTP If true, will use CCTP to bridge USDC. If false, will use Base bridge
    */
    function expansionAndSwap(uint dolaAmount, uint dolaToSwap, bool useCCTP) external {
        if (msg.sender != chair) revert OnlyChair();
        if (dolaToSwap > dolaAmount) revert SwapMoreDolaThanMinted();
        
        dolaSupply += dolaAmount;
        DOLA.mint(address(this), dolaAmount);

        DOLA.approve(address(curvePool), dolaToSwap);
        uint usdcAmount = curvePool.exchange_underlying(dolaIndex, usdcIndex, dolaToSwap, dolaToSwap * (PRECISION - maxSlippageBpsDolaToUsdc) / PRECISION / DOLA_USDC_CONVERSION_MULTI);

        uint dolaToBridge = dolaAmount - dolaToSwap;
        DOLA.approve(address(baseBridge), dolaToBridge);
        
        baseBridge.depositERC20To(address(DOLA), DOLA_BASE, aeroFarmer, dolaToBridge, 200_000, "");

        if(useCCTP){
            USDC.approve(address(CCTP), usdcAmount);
            CCTP.depositForBurn(usdcAmount, BASE_CCTP_DOMAIN, bytes32(uint256(uint160(aeroFarmer))), address(USDC));
        } else {
            USDC.approve(address(baseBridge), usdcAmount);
            baseBridge.depositERC20To(address(USDC), USDC_BASE, aeroFarmer, usdcAmount, 200_000, "");
        }

        emit Expansion(dolaAmount);
    }

    /**
    @notice Mints & deposits `amountUnderlying` of `underlying` tokens into Base bridge to the `aeroFarmer` contract
    @param dolaAmount Amount of underlying token to mint & deposit into Aerodrome farmer on Base
    */
    function expansion(uint dolaAmount) external {
        if (msg.sender != chair) revert OnlyChair();
        
        dolaSupply += dolaAmount;
        DOLA.mint(address(this), dolaAmount);

        DOLA.approve(address(baseBridge), dolaAmount);
        baseBridge.depositERC20To(address(DOLA), DOLA_BASE, aeroFarmer, dolaAmount, 200_000, "");

        emit Expansion(dolaAmount);
    }

    /**
    @notice Burns `dolaAmount` of DOLA held in this contract
    @param dolaAmount Amount of DOLA to burn
    */
    function contraction(uint dolaAmount) public {
        if (msg.sender != chair) revert OnlyChair();

        _contraction(dolaAmount);
    }

    /**
    @notice Attempts to contract (burn) all DOLA held by this contract
    */
    function contractAll() external {
        if (msg.sender != chair) revert OnlyChair();

        _contraction(DOLA.balanceOf(address(this)));
    }

    /**
    @notice Attempts to contract (burn) `amount` of DOLA. Sends remainder to `gov` if `amount` > DOLA minted by this fed.
    @param amount Amount of DOLA to contract.
    */
    function _contraction(uint amount) internal{
        if (amount == 0) revert CantBurnZeroDOLA();
        if(amount > dolaSupply){
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
    @notice Swap `usdcAmount` of USDC for DOLA through curve.
    @dev Will revert if actual slippage > `maxSlippageBpsUsdcToDola`
    @param usdcAmount Amount of USDC to be swapped to DOLA through curve.
    */
    function swapUSDCtoDOLA(uint usdcAmount) external {
        if (msg.sender != chair) revert OnlyChair();
        
        USDC.approve(address(curvePool), usdcAmount);
        curvePool.exchange_underlying(usdcIndex, dolaIndex, usdcAmount, usdcAmount * (PRECISION - maxSlippageBpsUsdcToDola) / PRECISION * DOLA_USDC_CONVERSION_MULTI);
    }

    /**
    @notice Swap `dolaAmount` of DOLA for USDC through curve.
    @dev Will revert if actual slippage > `maxSlippageBpsDolaToUsdc`
    @param dolaAmount Amount of DOLA to be swapped to USDC through curve.
    */
    function swapDOLAtoUSDC(uint dolaAmount) external {
        if (msg.sender != chair) revert OnlyChair();
        
        DOLA.approve(address(curvePool), dolaAmount);
        curvePool.exchange_underlying(dolaIndex, usdcIndex, dolaAmount, dolaAmount * (PRECISION - maxSlippageBpsDolaToUsdc) / PRECISION / DOLA_USDC_CONVERSION_MULTI);
    }

    /**
    @notice Method for current chair of the Base FED to resign
    */
    function resign() external {
        if (msg.sender != chair) revert OnlyChair();
        chair = address(0);
    }

    /**
    @notice Governance only function for setting acceptable slippage when swapping DOLA -> USDC
    @param newMaxSlippageBps The new maximum allowed loss for DOLA -> USDC swaps. 1 = 0.01%
    */
    function setMaxSlippageDolaToUsdc(uint newMaxSlippageBps) external {
        if (msg.sender != gov) revert OnlyGov();
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsDolaToUsdc = newMaxSlippageBps;
    }

    /**
    @notice Governance only function for setting acceptable slippage when swapping USDC -> DOLA
    @param newMaxSlippageBps The new maximum allowed loss for USDC -> DOLA swaps. 1 = 0.01%
    */
    function setMaxSlippageUsdcToDola(uint newMaxSlippageBps) external {
        if (msg.sender != gov) revert OnlyGov();
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsUsdcToDola = newMaxSlippageBps;
    }

    /**
    @notice Method for `gov` to change `pendingGov` address
    @dev `pendingGov` will have to call `claimGov` to complete `gov` transfer
    @param newPendingGov_ Address to be set as `pendingGov`
    */
    function setPendingGov(address newPendingGov_) external {
        if (msg.sender != gov) revert OnlyGov();
        pendingGov = newPendingGov_;
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
    @param newChair_ Address to be set as chair
    */
    function changeChair(address newChair_) external {
        if (msg.sender != gov) revert OnlyGov();
        chair = newChair_;
    }

    /**
    @notice Method for gov to change the L2 aeroFarmer address
    @dev aeroFarmer is the L2 address that receives all bridged DOLA from expansion
    @param newAeroFarmer_ L2 address to be set as aeroFarmer
    */
     function changeAeroFarmer(address newAeroFarmer_) external {
        if (msg.sender != gov) revert OnlyGov();
        aeroFarmer = newAeroFarmer_;
    }

    /**
    @notice Method for gov to change the curve pool address
    @param newCurvePool_ Address to be set as curvePool 
    @param _dolaIndex int of the dola coin index in the new curvepool
    @param _usdcIndex int of the usdc coin index in the new curvepool
    */
     function changeCurvePool(address newCurvePool_, int128 _dolaIndex, int128 _usdcIndex) external {
        if (msg.sender != gov) revert OnlyGov();
        dolaIndex = _dolaIndex;
        usdcIndex = _usdcIndex;
        curvePool = ICurvePool(newCurvePool_);
    }
}
