// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {ERC1155} from "lib/openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import {IShdV1} from "./interfaces/IShdV1.sol";
import {IERC1155Receiver} from "lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract ShdV1 is IShdV1, ERC165, ERC1155, IERC1155Receiver, ReentrancyGuard {

    using SafeERC20 for IERC20;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  事件
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event AddressAdded(address indexed verifierAddress);
    event AddressRemoved(address indexed verifierAddress);
    event InitializeShd(uint256 indexed ShdId, uint256 indexed InitializedTime);
    event CreateShd(address indexed firstKeeper, uint256 indexed recieveTime, uint256 indexed ShdId);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId, uint256 value, uint256 transferPrice );
    event Withdrawal(uint256 indexed ShdId, address indexed recipient_, uint256 indexed amount_, uint256 withdrawTime);
    event WithdrawAllForBeneficiary(address indexed recipient_, uint256 indexed amount_, uint256 withdrawTime);
    event Deposit(uint256 indexed ShdId, address indexed depositor, uint256 indexed amount);
    event Settlement(address indexed keeper, address indexed beneficiary, uint256 indexed amount);
    event PriceUpdate(uint256 previousPrice, uint256 indexed newPrice, uint256 priceUpdateTime); 
    event CooldownUpdate(uint256 previousPriceCooldown, uint256 indexed newPriceCooldown, uint256 previousTradeCooldown, uint256 indexed newTradeCooldown);
    event FeesUpdate(uint256 previousKeeperTaxNumerator, uint256 indexed newKeeperTaxNumerator);
    event Purchase(uint256 indexed price, uint256 indexed purchaseTime, address indexed currentKeeper, address lastKeeper); // @TODO
    event ReclaimShd(address indexed finalKeeper, uint256 indexed reclaimPrice, uint256 indexed reclaimTime);
    event Received(address Sender, uint Value);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  自定义错误
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// ERC1155 相关的错误
    error NotSupported();

    /// Shd 状态相关的错误
    error ShdIsLocked();
    error ShdIsNotLocked();
    error TradeIsNotCooldown();
    error ExceedingMaximumShdId();

    /// keeper 相关的错误
    error NotOwner();
    error NotUserKeepShd();
    error KeeperInSolvent();
    error ContractHoldsShd();
    error NotKeeper(address wrongKeeper, address correctKeeper);

    /// 操作相关的错误
    error BeyondUsePeriod();
    error NotEnoughFunds();
    error HaveNotReclaimed();
    error TradeIsNotAllowed();
    error WithdrawIsNotAllowed();
    error NotEnoughDepositFees();
    error NotArrivedReclaimTime();
    error PriceSettingIsNotCooldown();
    error NotAllowedTransferToContract();
    error WrongPriceInput(uint256 wrongPrice, uint256 correctPrice);
    error CurrentValueIncorrect(uint256 valueProvided, uint256 currentValue);
    error InsufficientFunds(uint256 fundsAvailable, uint256 fundsRequired);
    error InvalidNewPrice(uint256 previousPrice, uint256  newPrice);
    error NotEnoughMinimiumDepositFees(uint256 correctAmount, uint256 amount);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  存储
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // 构造体
    struct ShdDetails {
        uint256 id;
        uint256 price;
        address keeper;
        uint256 keeperReceiveTime;
        uint256 tradeTime;
        uint256 setPriceTime;
        TradeState  tradeState;
    }

    //  常量
    /// 费用分母：基点（100.00%）。
    uint256 internal constant _FEE_DENOMINATOR = 100_00;
    /// Shd 一个周期的时间：30 天。
    uint256 internal constant _KEEPER_USE_PERIOD = 2592000;

    /// 最大的 Shd 价格，有限制以防止潜在的溢出。
    uint256 internal constant _MAXIMUM_PRICE = 2 ** 128;

    /// 每次铸造的 Shd 数量限定为 1
    uint256 public constant SHD_VALUE = 1;
    /// 能够铸造的最大 Shd 数量为 10；
    uint256 public constant MAXIMUN_SHD_ID = 9;

    /// 交易状态
    TradeState public tradeState;

    /// 存储ERC20代币合约地址
    IERC20 public SRCToken;

    /// 合约的所有者
    address public owner;
    /// Shd 的 id
    uint256 public shdId;
    /// 初始的 Shd 拍卖价格
    uint256 public  initialPrice;

    /// 每个 Shd 持有者的地址。
    mapping( uint256 ShdId  => ShdDetails) Shds;
    ///  资金跟踪器，与此合约交互的每个账户地址都有。
    mapping(address => uint256) public fundsOf;
    /// 用于计算自上次结算以来所欠的金额。
    mapping(uint256 ShdId => uint256) lastSettlementTime;
    /// 审核员地址
    address[] public verifierAddresses;

    /// 验证地址是否在名单中
    mapping(address => bool) public verifierlist;


    //  费用相关的变量
    /// Shd 持有者的使用费（哈勃格税收），初始值设置为 1%
    uint256 public usageNumerator;
    /// 每一次交易 Shd 时会产生的交易费用，初始值设置为 5%
    uint256 public tradingFeeNumerator;
    /// Shd 的代币 uri
    string public _tokenUri;

    /// 交易冷却时间：Shd 可以被交易的时间间隔。
    uint256 public tradeCooldown;
    /// 价格冷却时间：用户能够修改价格的时间间隔。
    uint256 public priceCooldown;

    /// Shd 的交易状态
    enum TradeState {
        UNLOCK,LOCK
    }

    /// 检查函数调用者是否是合约所有者
    modifier onlyOwner() {
        if (msg.sender != owner)
        revert NotOwner();
        _;
    }

    /// 确保函数调用者为 Shd 的当前持有者
    modifier onlyKeeper(uint256 _shdId) {
        if (msg.sender != Shds[_shdId].keeper)
        revert NotKeeper(msg.sender, Shds[_shdId].keeper);
        _;
    }

    /// 确保函数调用者为 Shd 的当前持有者
    modifier onlyKeeperHeld(uint256 _shdId)  {
        if (address(this) == Shds[_shdId].keeper) {
            revert NotUserKeepShd();
        }
        _;
    }

    /// Shd 持有者能够持有 Shd 的最大期限
    modifier inUsePeriod(uint256 _shdId) {
        if ( Shds[_shdId].keeperReceiveTime +  _KEEPER_USE_PERIOD < block.timestamp) {
            revert BeyondUsePeriod();
        }
        _;
    }

    /// 构造函数
    constructor(address SRCTokenAddress, string memory tokenUri_, uint256 initialPrice_, address initialOwner, uint256 tradeCooldown_, uint256 priceCooldown_  ) ERC1155(tokenUri_) {
        owner = initialOwner;
        _tokenUri = tokenUri_;
        tradingFeeNumerator = 5_00;
        usageNumerator = 1_00;
        tradeCooldown = tradeCooldown_;
        priceCooldown = priceCooldown_;
        initialPrice = initialPrice_;
        SRCToken = IERC20(SRCTokenAddress);
    }

    /// 禁用在此合约中不会使用到的 ERC1155 合约函数
    function balanceOf(address , uint256 ) public pure override returns (uint256) {
        revert NotSupported();
    }

    function balanceOfBatch(address[] memory ,uint256[] memory ) public pure override returns (uint256[] memory) {
        revert NotSupported();
    }

    function setApprovalForAll(address , bool ) public pure override {
        revert NotSupported();
    }

    function isApprovedForAll(address , address ) public pure override returns (bool) {
        revert NotSupported();
    }

    function safeTransferFrom(address , address , uint256 , uint256 , bytes memory ) public pure override {
        revert NotSupported();
    }

    function safeBatchTransferFrom(address ,address ,uint256[] memory ,uint256[] memory ,bytes memory ) public pure override {
        revert NotSupported();
    }

        // 实现 supportsInterface 函数以声明合约支持的接口
    function supportsInterface(bytes4 interfaceId) public view override(IERC165,ERC165, ERC1155) returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface(interfaceId);
    }

    /// IERC1155Receiver 函数
    function onERC1155Received(address ,address ,uint256 , uint256 , bytes calldata  ) external pure override returns (bytes4) {
        return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
        } 
        
    function onERC1155BatchReceived(address ,address ,uint256[] calldata ,uint256[] calldata ,bytes calldata ) external pure override returns (bytes4) {
        revert NotSupported();
    } 


    /// 转移 Shd
    function _transferShd(address from_, address to_, uint256 _shdId, uint256 transferPrice) internal virtual  {

        Shds[_shdId].keeper = to_;
        Shds[_shdId].keeperReceiveTime = block.timestamp;

        emit Transfer(from_, to_, _shdId, SHD_VALUE, transferPrice);
        
    }

    /// 初始化 Shd （在 `CreateShd` 以及 `ReclaimShd` 函数时进行调用）
    function _initializeShd(uint256 _shdId, uint256 price_) internal onlyOwner {        
        Shds[_shdId] = ShdDetails({
        id:shdId,
        price:price_,
        keeper:address(this),
        keeperReceiveTime:block.timestamp,
        tradeTime:0,
        setPriceTime:0,
        tradeState:TradeState.UNLOCK
        });

        emit InitializeShd(_shdId,Shds[_shdId].keeperReceiveTime);
    }

    /// 创建一个新的 Shd 实例
    function createShd() external onlyOwner {
        // mint 一个新的 Shd 广告牌并进行初始化
        _mint(address(this), shdId, SHD_VALUE, "");
        _initializeShd(shdId, initialPrice);

        // 设置结算时间
        lastSettlementTime[shdId] = block.timestamp;

        uint256 firstMintTime = Shds[shdId].keeperReceiveTime;
        emit CreateShd(msg.sender, firstMintTime, shdId);

        if (shdId > MAXIMUN_SHD_ID) {
            revert ExceedingMaximumShdId();
        }
        shdId++;
    }

    /// 购买函数 
    function purchase(uint256 _shdId) external  nonReentrant{
        uint256 id_ = _shdId;

        // 检查 shd 的状态，如果 Shd 被锁定（LOCK）则无法进行购买
        if (Shds[id_].tradeState != TradeState.UNLOCK) {
            revert ShdIsLocked();
        }

        // 检查是否已经经过了交易冷却期
        if (block.timestamp < Shds[id_].tradeTime + tradeCooldown) {
            revert TradeIsNotCooldown();
        }

        address lastKeeper = Shds[id_].keeper;
        if (lastKeeper != address(this)) {
            _settle(id_);
        }

        // 计算本次购买交易的交易费（`price` + `tradeFee`）
        uint256 benifitForOwner = _calculateTradeFees(Shds[id_].price);
        uint256 currentPrice = Shds[id_].price;
        uint256 userBalance = SRCToken.balanceOf(msg.sender);
        uint256 amount = currentPrice + benifitForOwner;

        if (userBalance < amount){
            revert WrongPriceInput(userBalance, amount);
        }

        SRCToken.safeTransferFrom(msg.sender, address(this), amount);

        // 将交易费转给上一任 shd 的持有者
        SRCToken.safeTransfer(lastKeeper, currentPrice);

        // 将交易费转给合约的持有者
        SRCToken.safeTransfer(owner, benifitForOwner);

        // 转帐 shd 并修改 shd 的状态
        _transferShd(lastKeeper, msg.sender, id_, currentPrice);
        Shds[id_].tradeTime = block.timestamp;
        Shds[id_].tradeState = TradeState.LOCK;
        
        // 触发交易事件
        emit Purchase(Shds[id_].price, Shds[id_].keeperReceiveTime,lastKeeper,msg.sender);
    }

    /// 质押函数（internal） 在 `purchase` 和 `deposit` 函数中被调用）
    function _deposit(uint256 _shdId, uint256 fees_) internal {
        fundsOf[msg.sender] += fees_;
        emit Deposit(_shdId, msg.sender, msg.value);
    }
    
    /// 质押函数
    function deposit(uint256 _shdId, uint256 fees_) external  virtual  onlyKeeper(_shdId) inUsePeriod(_shdId) nonReentrant{

        uint256 id_ = _shdId;
        
        // 需要提前质押 30 天的使用费 + 下一次交易时的交易费
        uint256 currentDepositFees = _calculateDepositFees(Shds[id_].price);

        // 检查持有者的已质押金额(fundsof[msg.sender]) + 当前存入的金额（msg.value）是否大于当前的应质押余额，如果小于，则触发`NotEnoughMinimiumDepositFees`错误
        if (currentDepositFees > fundsOf[msg.sender] + fees_ ){
            revert NotEnoughMinimiumDepositFees(currentDepositFees,fees_);
        }

        // 修改 shd 的状态，使其可以被购买
        if( Shds[id_].tradeState == TradeState.LOCK) {
            Shds[id_].tradeState == TradeState.UNLOCK;
        }

        // 存入 msg.value 数额的 ETH
        SRCToken.safeTransferFrom(msg.sender,address(this), fees_);
        _deposit(id_,fees_);
    }

    /// 取款函数(internal)
    function withdraw(uint256 _shdId, uint256 amount_) external virtual {
            _withdraw(_shdId, msg.sender, amount_);
        }

    /// 取款函数，当用户售出了自己的 shd 之后，可以调用此函数取走质押在合约内未使用的使用费
    function _withdraw(uint256 _shdId, address recipient_, uint256 amount_) internal  virtual  {
        uint256 id_ = _shdId;

        // 检查用户是否是 shd 的持有者，持有 Shd 期间不允许取款
        if (recipient_ == Shds[id_].keeper) {
            revert WithdrawIsNotAllowed();
        }

        // 如果输入的取款金额大于用户质押在合约内的金额，则会触发错误
        if (fundsOf[recipient_] < amount_) {
            revert InsufficientFunds(fundsOf[recipient_], amount_);
        }

        fundsOf[recipient_] -= amount_;

        // 触发取款事件
        emit Withdrawal(id_, recipient_, amount_, block.timestamp);

        // 将用户质押在合约内的金额转回给用户
        SRCToken.safeTransfer(recipient_, amount_);
    }

    /// 合约所有者提取合约内所有收益（shd 持有者的使用费）的函数，在用户调用`settle`函数进行结算后才能使用
    function withdrawAllForBeneficiary() external virtual onlyOwner {
        uint256 currentBenefit =  fundsOf[msg.sender];

        // 将收益转给合约所有者
        SRCToken.safeTransfer(owner, currentBenefit);

        // 重置合约所有者在合约内的 fundsof
        fundsOf[owner] = 0;

        // 触发取款事件
        emit WithdrawAllForBeneficiary(msg.sender, currentBenefit, block.timestamp);
    }
    
    /// 计算一个周期内广告牌持有者的使用费
    function _settle(uint256 _shdId) internal virtual  {
        uint256 id_ = _shdId;
        address keeper = Shds[id_].keeper;

        // 计算用户到当前调用结算函数为止的使用费
        uint256 owedFunds = _calculateCurrentUsageFees(id_);

        // 如果用户的质押金额小于应付的 shd 使用费，则触发错误
        if (fundsOf[keeper] < owedFunds) {
            revert NotEnoughDepositFees();
        }

        // 将 shd 使用费作为收益转给合约的所有者
        fundsOf[keeper] -= owedFunds;
        fundsOf[owner] += owedFunds;

        // 记录结算时间
        lastSettlementTime[id_] = block.timestamp;

        // 触发事件
        emit Settlement(msg.sender,owner, owedFunds );

    }

    /// 结算当前用户已使用的金额（internal）
    function settle(uint256 _shdId) external virtual onlyKeeperHeld(_shdId) inUsePeriod(_shdId) {
        _settle(_shdId);
    }

    /// 设置新的 tokenUri
        function setTokenURI(string memory newTokenURI) public virtual onlyOwner {
        _tokenUri = newTokenURI;
    }
    
    /// 设置当前 Shd 的价格
    function setPrice(uint256 _shdId, uint256 newPrice_, uint256 fees_) external  virtual onlyKeeper(_shdId) inUsePeriod(_shdId) nonReentrant{

        uint256 id_ = _shdId;

        uint256 previousPrice = Shds[id_].price;

        // 检查是否设置交易的冷却期已经结束
        if (block.timestamp < Shds[id_].setPriceTime + priceCooldown) {
            revert PriceSettingIsNotCooldown();
        }

        if (newPrice_ > _MAXIMUM_PRICE) {
            revert InvalidNewPrice(previousPrice, newPrice_);
        }
        if (newPrice_ <= initialPrice) {
            revert InvalidNewPrice(previousPrice, newPrice_);
        }

        uint256 newDepositFees =  _calculateDepositFees(newPrice_);
        // 检查此次交易传入的 ETH + 持有者已经质押的金额是否大于以新金额计数的应质押费
        if (fees_ + fundsOf[msg.sender] < newDepositFees) {
            revert NotEnoughMinimiumDepositFees(newDepositFees - fundsOf[msg.sender], fees_);
        }

        _deposit(id_,fees_);
        SRCToken.safeTransferFrom(msg.sender,address(this), fees_);

        // 修改 shd 的状态参数
        Shds[_shdId].price = newPrice_;
        Shds[_shdId].setPriceTime = block.timestamp;
        Shds[_shdId].tradeState = TradeState.UNLOCK;

        // 触发设置价格的交易事件
        emit PriceUpdate(previousPrice, newPrice_, block.timestamp);
    }
    
    /// 强制回收 Shd, 并设置初始化价格
    function reclaim(uint256 _shdId, uint256 initialzePrice)  external  virtual onlyOwner {

        //  合约所有者先存入回购价格的 msg.value(应为 initialPrice)
        SRCToken.safeTransferFrom(owner, address(this), initialPrice);
        fundsOf[owner] +=initialPrice;

        uint256 id_ = _shdId;

        // 检查是否 shd 持有者的使用期限是否到期
        if(block.timestamp <= Shds[id_].keeperReceiveTime + _KEEPER_USE_PERIOD ){
            revert NotArrivedReclaimTime();
        }

        address finalKeeper = Shds[id_].keeper;

        if (finalKeeper == owner) {
            revert NotUserKeepShd();
        }

        // 将 shd 转回合约并进行初始化
        _transferShd(finalKeeper, address(this), id_, initialPrice);
        _initializeShd(id_, initialzePrice);

        // 以初始价格回购 shd 并将 ETH 转给最后一任 shd 持有者（finalKeeper）
        uint256 reclaimTime = Shds[id_].keeperReceiveTime;
        SRCToken.safeTransfer(finalKeeper, initialPrice);

        // 触发回购事件
        emit ReclaimShd(finalKeeper, initialPrice, reclaimTime);
    }

    /// 合约所有者设置新的 Shd 使用费
    function setFees(uint256 newUsageNumerator) external virtual onlyOwner {
        uint256 previousUsageNumerator = usageNumerator;
        usageNumerator = newUsageNumerator;
        emit FeesUpdate(
            previousUsageNumerator, newUsageNumerator
        );
    }

    /// 计算以当前价格持有 Shd 30天需要花费的金额
    function _calculateDepositFees(uint256 price)  public view virtual returns(uint256) {
        return  price * usageNumerator * 30 / _FEE_DENOMINATOR ;
    }

    /// 计算 shd 持有者当前的使用费，每日使用费为当前价格的 1%
    function _calculateCurrentUsageFees(uint256 _shdId)  public view virtual returns(uint256) {
        return  Shds[_shdId].price * usageNumerator * (block.timestamp - Shds[_shdId].keeperReceiveTime)  / (_FEE_DENOMINATOR * _KEEPER_USE_PERIOD);
    }

    /// 计算交易费，当前 shd 价格的 5%
    function _calculateTradeFees(uint256 price) public view virtual returns(uint256) {
        return price * tradingFeeNumerator / _FEE_DENOMINATOR;
    }

    /// 检查持有者目前的质押余额
    function checkFundsOf(address user) external view  returns(uint256){
        return fundsOf[user];
    }

    /// 检查 ShdId 对应的持有者    
    function checkShdKeeper(uint256 _shdId) external view  returns(address){
        return Shds[_shdId].keeper;
    }

    /// 检查当前 Shd 持有者的使用期限
    function checkShdKeeperUsageTime(uint256 _shdId) external view  returns(uint256){
        return Shds[_shdId].keeperReceiveTime + _KEEPER_USE_PERIOD;
    }

    /// 查看当前 Shd 的价格
    function getCurrentPrice(uint256 _shdId) external view virtual returns (uint256 currentPrice) {
        return Shds[_shdId].price;
    }

    /// 获取当前的 Shd 持有者
    function getCurrentShdKeeper(uint256 _shdId) external view virtual returns (address) {
        return Shds[_shdId].keeper;
    }

    /// 获取当前 Shd 的相关信息
    function getShdDetails(uint256 _shdId) external view virtual returns( ShdDetails memory ) {
        return Shds[_shdId];
    }
    
    /// 获取当前 Shd 合约的所有者
    function getOwner() external view returns(address) {
        return owner;
    }
    
    /// 获取当前 Shd 的 tokenUri
    function getUri() external view returns(string memory) {
        return _tokenUri;
    }

    /// 用户是否有 shd 使用权的具体判定条件
    function checkUsePermissionForShd(uint256 _shdId) external view  returns(bool) {
        // 检查 msg.sender 是否为当前 shdId 的 keeper
        uint256 id = _shdId ;
        address currentKeeper = Shds[id].keeper;
        if(msg.sender != currentKeeper) {
            return false;
        }

        // 当前时间是否超过了 keeper 既定的持有期限（30天）
        if(block.timestamp > Shds[id].keeperReceiveTime + _KEEPER_USE_PERIOD) {
            return false;
        }

        // 当前 keeper 质押的代币是否足够支付剩余期限（30天 - 已使用的期限）的使用费
        uint256 usageFeeForRemainingDays = _calculateDepositFees(Shds[id].price) - _calculateCurrentUsageFees(id);
        if (fundsOf[msg.sender] < usageFeeForRemainingDays) {
            return false;
        }

        return true;
    }

    /// 获取当前 Shd 合约的交易冷却期
    function getTradeTime() external view returns(uint256) {
        return tradeCooldown;
    }

    function getUsageNumerator() external view returns(uint256) {
        return usageNumerator;
    }

    /// 接收ETH时释放Received事件，以防 ETH 转入黑洞
    receive() external payable {
    emit Received(msg.sender, msg.value);  
    }


    /// 清空现有列表并添加新的审核地址
    function addToVerifierlist(address[] calldata addresses) external onlyOwner {
        // 清空现有的地址
        for (uint256 i = 0; i < verifierAddresses.length; i++) {
            address addr = verifierAddresses[i];
            verifierlist[addr] = false;
            emit AddressRemoved(addr);
        }
        
        // 重置验证者地址的数组
        delete verifierAddresses;

        // 添加新的地址
        for (uint256 i = 0; i < addresses.length; i++) {
            verifierlist[addresses[i]] = true;
            verifierAddresses.push(addresses[i]);
            emit AddressAdded(addresses[i]);
        }
    }
    /// 查询输入地址是否在验证者名单中
    function checkVerifierlistStatus(address account) public view returns (bool) {
        return verifierlist[account];
    }

    /// 返回当前验证者的地址数组
    function getVerifierAddresses() public view returns (address[] memory) {
        return verifierAddresses;
    }
}