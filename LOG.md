# 8.23 ShdV1 合约更新内容
## 合约地址：0xda4d015C835538F075a38C148c249c3acBca4901 （Polygon Amoy）
## 合约源码：https://amoy.polygonscan.com/address/0xda4d015c835538f075a38c148c249c3acbca4901#code

### 优化内容
1. 添加`checkUsePermissionForShd` 函数中,用于检查当前 `shd` 持有者是否具有 `shd` 使用权。
    功能逻辑: 
    1. 检查 `msg.sender` 是否为当前 `shdId` 的 `keeper`，如果不是，则返回 `false`
    2. 检查当前时间是否超过了 `keeper` 既定的持有期限（30 天），如超期，则返回 `false`
    3. 检查当前 `keeper` 质押的代币是否足够支付剩余期限（30 天 - 已使用的期限）的使用费，如果不足，则返回 `false`
2. 优化`purchase` 函数的购买逻辑。
3. 优化结算逻辑，将 `_settle` 函数移动至 `purchase` 函数中，并在每一次购买的交易事件发生时自动对 `lastKeeper` 的使用费进行结算。
4. 提升合约测试的覆盖率至 `62%`, 一些用于测试的 `view` 函数将不会进行测试

### 修复问题：
上一个测试版中未修复合约内 `SRC` 代币的使用逻辑，涉及函数有`purchase`, `setPrice`, `deposit`, `reclaim` 等函数 

