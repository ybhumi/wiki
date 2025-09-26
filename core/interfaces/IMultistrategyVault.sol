// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

/**
 * @title Yearn V3 Vault Interface
 * @author yearn.finance
 * @notice
 *   The Yearn VaultV3 is designed as a non-opinionated system to distribute funds of
 *   depositors for a specific `asset` into different opportunities (aka Strategies)
 *   and manage accounting in a robust way.
 *
 *   Depositors receive shares (aka vaults tokens) proportional to their deposit amount.
 *   Vault tokens are yield-bearing and can be redeemed at any time to get back deposit
 *   plus any yield generated.
 */
interface IMultistrategyVault {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error AlreadyInitialized();
    error AlreadyShutdown();
    error ZeroAddress();
    error ProfitUnlockTimeTooLong();
    error NotAllowed();
    error NotFutureRoleManager();
    error InsufficientFunds();
    error InvalidOwner();
    error PermitExpired();
    error InvalidSignature();
    error StrategyCannotBeZeroAddress();
    error InvalidAsset();
    error InactiveStrategy();
    error StrategyAlreadyActive();
    error StrategyNotActive();
    error NothingToBuy();
    error NothingToBuyWith();
    error NotEnoughDebt();
    error CannotBuyZero();
    error NewDebtEqualsCurrentDebt();
    error StrategyHasUnrealisedLosses();
    error TooMuchLoss();
    error ApprovalFailed();
    error TransferFailed();
    error VaultShutdown();
    error UsingModule();
    error UsingDepositLimit();
    error MaxQueueLengthReached();
    error ExceedDepositLimit();
    error CannotDepositZero();
    error CannotMintZero();
    error NoAssetsToWithdraw();
    error MaxLossExceeded();
    error ExceedWithdrawLimit();
    error InsufficientSharesToRedeem();
    error InsufficientAssetsInVault();
    error StrategyHasDebt();
    error InvalidReceiver();
    error InsufficientAllowance();
    error Reentrancy();
    error NoSharesToRedeem();

    /*//////////////////////////////////////////////////////////////
                                 ENUMS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Each permissioned function has its own Role.
     * Roles can be combined in any combination or all kept separate.
     */
    enum Roles {
        ADD_STRATEGY_MANAGER, // Can add strategies to the vault
        REVOKE_STRATEGY_MANAGER, // Can remove strategies from the vault
        FORCE_REVOKE_MANAGER, // Can force remove a strategy causing a loss
        ACCOUNTANT_MANAGER, // Can set the accountant that assess fees
        QUEUE_MANAGER, // Can set the default withdrawal queue
        REPORTING_MANAGER, // Calls report for strategies
        DEBT_MANAGER, // Adds and removes debt from strategies
        MAX_DEBT_MANAGER, // Can set the max debt for a strategy
        DEPOSIT_LIMIT_MANAGER, // Sets deposit limit and module for the vault
        WITHDRAW_LIMIT_MANAGER, // Sets the withdraw limit module
        MINIMUM_IDLE_MANAGER, // Sets the minimum total idle the vault should keep
        PROFIT_UNLOCK_MANAGER, // Sets the profit_max_unlock_time
        DEBT_PURCHASER, // Can purchase bad debt from the vault
        EMERGENCY_MANAGER // Can shutdown vault in an emergency
    }

    /**
     * @notice Type of change to a strategy.
     */
    enum StrategyChangeType {
        ADDED,
        REVOKED
    }

    /**
     * @notice Rounding direction for calculations.
     */
    enum Rounding {
        ROUND_DOWN,
        ROUND_UP
    }

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Variables for the maxWithdraw function.
     */
    struct MaxWithdrawVars {
        uint256 maxAssets;
        uint256 currentIdle;
        uint256 have;
        uint256 loss;
        address[] withdrawalStrategies;
    }

    /**
     * @notice Variables for the processReport function.
     */
    struct ProcessReportVars {
        address asset;
        uint256 totalAssets;
        uint256 currentDebt;
        uint256 gain;
        uint256 loss;
        uint256 totalFees;
        uint256 totalRefunds;
        uint256 totalFeesShares;
        uint16 protocolFeeBps;
        uint256 protocolFeesShares;
        address protocolFeeRecipient;
        uint256 sharesToBurn;
        uint256 sharesToLock;
        uint256 profitMaxUnlockTime;
        uint256 totalSupply;
        uint256 totalLockedShares;
        uint256 endingSupply;
        uint256 toBurn;
        uint256 previouslyLockedTime;
        uint256 fullProfitUnlockDate;
        uint256 newProfitLockingPeriod;
    }
    /**
     * @notice Parameters for a strategy.
     * @param activation Timestamp when the strategy was added.
     * @param lastReport Timestamp of the strategies last report.
     * @param currentDebt The current assets the strategy holds.
     * @param maxDebt The max assets the strategy can hold.
     */
    struct StrategyParams {
        uint256 activation;
        uint256 lastReport;
        uint256 currentDebt;
        uint256 maxDebt;
    }

    /**
     * @notice Variables for the processReport function.
     */
    struct ProcessReportLocalVars {
        uint256 strategyTotalAssets;
        uint256 currentDebt;
        uint256 gain;
        uint256 loss;
        uint256 totalFees;
        uint256 totalRefunds;
        address accountant;
        uint256 totalFeesShares;
        uint16 protocolFeeBps;
        uint256 protocolFeesShares;
        address protocolFeeRecipient;
        uint256 sharesToBurn;
        uint256 sharesToLock;
        uint256 profitMaxUnlockTimeVar;
        uint256 currentTotalSupply;
        uint256 totalLockedShares;
        uint256 endingSupply;
        uint256 toBurn;
        uint256 previouslyLockedTime;
        uint256 fullProfitUnlockDateVar;
        uint256 newProfitLockingPeriod;
    }

    /**
     * @notice State for a redeem operation.
     * @param requestedAssets The requested assets to redeem.
     * @param currentTotalIdle The current total idle of the vault.
     * @param currentTotalDebt The current total debt of the vault.
     * @param asset The asset of the vault.
     * @param withdrawalStrategies The strategies to withdraw from.
     * @param assetsNeeded The assets needed to fulfill the redeem request.
     * @param previousBalance The previous balance of the vault.
     */
    struct RedeemState {
        uint256 requestedAssets;
        uint256 currentTotalIdle;
        uint256 currentTotalDebt;
        address asset;
        address[] withdrawalStrategies;
        uint256 assetsNeeded;
        uint256 previousBalance;
    }

    /**
     * @notice Variables for the updateDebt function.
     */
    struct UpdateDebtVars {
        uint256 newDebt; // Target debt we want the strategy to have
        uint256 currentDebt; // Current debt the strategy has
        uint256 assetsToWithdraw; // Amount to withdraw when decreasing debt
        uint256 assetsToDeposit; // Amount to deposit when increasing debt
        uint256 minimumTotalIdle; // Minimum amount to keep in vault
        uint256 totalIdle; // Current amount in vault
        uint256 availableIdle; // Amount available for deposits
        uint256 maxDebt; // Maximum debt for the strategy
        uint256 maxDepositAmount; // Maximum amount strategy can accept
        uint256 maxRedeemAmount; // Maximum amount strategy can redeem
        uint256 withdrawable; // Amount that can be withdrawn
        uint256 preBalance; // Balance before operation
        uint256 postBalance; // Balance after operation
        uint256 actualAmount; // Actual amount moved
        bool isDebtDecrease; // Whether debt is being decreased
        address _asset; // Cached asset address
        uint256 unrealisedLossesShare; // Any unrealized losses
    }

    /**
     * @notice State for a withdrawal operation.
     * @param requestedAssets The requested assets to withdraw.
     * @param currentTotalIdle The current total idle of the vault.
     * @param currentTotalDebt The current total debt of the vault.
     * @param assetsNeeded The assets needed to fulfill the withdrawal request.
     * @param previousBalance The previous balance of the vault.
     */
    struct WithdrawalState {
        uint256 requestedAssets;
        uint256 currentTotalIdle;
        uint256 currentTotalDebt;
        uint256 assetsNeeded;
        uint256 previousBalance;
        uint256 currentDebt;
        uint256 assetsToWithdraw;
        uint256 maxWithdraw;
        uint256 unrealisedLossesShare;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    // ERC4626 EVENTS
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    // ERC20 EVENTS
    event Transfer(address indexed sender, address indexed receiver, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // STRATEGY EVENTS
    event StrategyChanged(address indexed strategy, StrategyChangeType indexed change_type);
    event StrategyReported(
        address indexed strategy,
        uint256 gain,
        uint256 loss,
        uint256 currentDebt,
        uint256 protocolFees,
        uint256 totalFees,
        uint256 totalRefunds
    );

    // DEBT MANAGEMENT EVENTS
    event DebtUpdated(address indexed strategy, uint256 currentDebt, uint256 newDebt);

    // ROLE UPDATES
    event RoleSet(address indexed account, uint256 indexed role);

    // STORAGE MANAGEMENT EVENTS
    event UpdateFutureRoleManager(address indexed futureRoleManager);
    event UpdateRoleManager(address indexed roleManager);
    event UpdateAccountant(address indexed accountant);
    event UpdateDepositLimitModule(address indexed depositLimitModule);
    event UpdateWithdrawLimitModule(address indexed withdrawLimitModule);
    event UpdateDefaultQueue(address[] newDefaultQueue);
    event UpdateUseDefaultQueue(bool useDefaultQueue);
    event UpdateAutoAllocate(bool autoAllocate);
    event UpdatedMaxDebtForStrategy(address indexed sender, address indexed strategy, uint256 newDebt);
    event UpdateDepositLimit(uint256 depositLimit);
    event UpdateMinimumTotalIdle(uint256 minimumTotalIdle);
    event UpdateProfitMaxUnlockTime(uint256 profitMaxUnlockTime);
    event DebtPurchased(address indexed strategy, uint256 amount);
    event Shutdown();

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function asset() external view returns (address);
    function decimals() external view returns (uint8);
    // todo fix the following functions that are there as public variables
    function strategies(address strategy) external view returns (StrategyParams memory);
    function defaultQueue() external view returns (address[] memory);
    function useDefaultQueue() external view returns (bool);
    function autoAllocate() external view returns (bool);
    function minimumTotalIdle() external view returns (uint256);
    function depositLimit() external view returns (uint256);
    function accountant() external view returns (address);
    function depositLimitModule() external view returns (address);
    function withdrawLimitModule() external view returns (address);
    function roles(address) external view returns (uint256);
    function roleManager() external view returns (address);
    function futureRoleManager() external view returns (address);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function isShutdown() external view returns (bool);
    function unlockedShares() external view returns (uint256);
    function pricePerShare() external view returns (uint256);
    function nonces(address owner) external view returns (uint256);

    function totalSupply() external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function totalIdle() external view returns (uint256);
    function totalDebt() external view returns (uint256);
    function balanceOf(address addr) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);

    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewMint(uint256 shares) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);

    function maxDeposit(address receiver) external view returns (uint256);
    function maxMint(address receiver) external view returns (uint256);
    function maxWithdraw(address owner, uint256 maxLoss, address[] calldata strategies) external view returns (uint256);
    function maxRedeem(address owner, uint256 maxLoss, address[] calldata strategies) external view returns (uint256);

    function FACTORY() external view returns (address);
    function apiVersion() external pure returns (string memory);
    function assessShareOfUnrealisedLosses(
        address strategy,
        uint256 currentDebt,
        uint256 assetsNeeded
    ) external view returns (uint256);

    function profitMaxUnlockTime() external view returns (uint256);
    function fullProfitUnlockDate() external view returns (uint256);
    function profitUnlockingRate() external view returns (uint256);
    function lastProfitUpdate() external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                           MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function initialize(
        address asset,
        string memory name,
        string memory symbol,
        address roleManager,
        uint256 profitMaxUnlockTime
    ) external;

    // ERC20 & ERC4626 Functions
    function deposit(uint256 assets, address receiver) external returns (uint256);
    // function mint(uint256 shares, address receiver) external returns (uint256);
    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256 maxLoss,
        address[] calldata strategies
    ) external returns (uint256);
    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss,
        address[] calldata strategies
    ) external returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address receiver, uint256 amount) external returns (bool);
    function transferFrom(address sender, address receiver, uint256 amount) external returns (bool);
    function permit(
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bool);

    // Management Functions
    function setName(string memory name) external;
    function setSymbol(string memory symbol) external;
    function setAccountant(address newAccountant) external;
    function setDefaultQueue(address[] calldata newDefaultQueue) external;
    function setUseDefaultQueue(bool useDefaultQueue) external;
    function setAutoAllocate(bool autoAllocate) external;
    function setDepositLimit(uint256 depositLimit, bool shouldOverride) external;
    function setDepositLimitModule(address depositLimitModule, bool shouldOverride) external;
    function setWithdrawLimitModule(address withdrawLimitModule) external;
    function setMinimumTotalIdle(uint256 minimumTotalIdle) external;
    function setProfitMaxUnlockTime(uint256 newProfitMaxUnlockTime) external;

    // Role Management
    function setRole(address account, uint256 roles) external;
    function addRole(address account, Roles role) external;
    function removeRole(address account, Roles role) external;
    function transferRoleManager(address roleManager) external;
    function acceptRoleManager() external;

    // Reporting Management
    function processReport(address strategy) external returns (uint256, uint256);
    function buyDebt(address strategy, uint256 amount) external;

    // Strategy Management
    function addStrategy(address newStrategy, bool addToQueue) external;
    function revokeStrategy(address strategy) external;
    function forceRevokeStrategy(address strategy) external;

    // Debt Management
    function updateMaxDebtForStrategy(address strategy, uint256 newMaxDebt) external;
    function updateDebt(address strategy, uint256 targetDebt, uint256 maxLoss) external returns (uint256);

    // Emergency Management
    function shutdownVault() external;
}
