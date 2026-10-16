# Pricing & Credits：设计状态与实现对照

> 范围回退（2026-10-16）：按用户最新要求，Widget 客户端已恢复原提交和取消流程。下表中依赖 `BillingCoordinator.prepare / decide / continueIntent / showSubmitted / confirmRunningCancellation` 的任务确认、余额不足恢复、充值自动提交及撤销提示均已撤回，不代表当前已实现状态。Pro 购买、独立充值、订单退款及管理员授权继续保留；本地存储不再交互式读写钥匙串。本表其余内容保留为设计方案参考，不再作为当前全部完成的证明。

依据最新 PRD v0.5 和 Figma `Pricing & Credits / PRD v0.4 Flow`（286:2）。本表逐项核对原型状态的业务入口与实现位置，**不代表已完成运行中的像素级 UI 验收或真实支付验收**。项目规则要求用户构建和测试 Glance；本次没有启动 App、操作 App UI 或构建 App。

同一控件的动态状态复用 AppKit 原生实现。原型中的任务进度、成功与失败按 v0.5 收敛进现有任务中心 / toast；钱包与流水合并，登录完成直接恢复原操作。外部收银台由 Pancake 托管。明确改动依据列在备注，不把外部页面标成已实测。

本轮补齐：验证码错误剩余次数与不可用分流、设备释放上限帮助、被释放 Mac 状态、退款结果 / 不满足条件状态、续购完成、微信不可用时切换币种、充值与实际任务提交关联、指标看板。

| Figma 节点 | 状态 | 实现入口 | 核对范围 / 剩余验证 |
| --- | --- | --- | --- |
| 286:132 | launchTrial · 已开启 14 天完整试用 | BillingManager.start / trialBadge / presentLaunchNotice；BillingCoordinator.showTrialEnded | 按 PRD v0.5：首启轻提示、标题栏角标和一次到期 sheet，不复制首启模态页 |
| 286:162 | trialEnding · 试用还剩 3 天 | BillingManager.start / trialBadge / presentLaunchNotice；BillingCoordinator.showTrialEnded | 按 PRD v0.5：首启轻提示、标题栏角标和一次到期 sheet，不复制首启模态页 |
| 286:192 | trialEnded · 试用已结束 | BillingManager.start / trialBadge / presentLaunchNotice；BillingCoordinator.showTrialEnded | 按 PRD v0.5：首启轻提示、标题栏角标和一次到期 sheet，不复制首启模态页 |
| 286:221 | freeLocked · 格式转换需要 Pro | BillingCoordinator.requireLocalTool；BillingManager.verifiedClaims / needsUpdates | 入口可见并带锁；区分免费版、更新资格、离线过期和被释放设备。待用户运行 UI 验收 |
| 286:252 | login · 登录后使用 AI Widget | BillingWindow.showLogin / showCode / verifyCode / showCodeUnavailable；users.verifyEmailCode | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:277 | codeSent · 输入验证码 | BillingWindow.showLogin / showCode / verifyCode / showCodeUnavailable；users.verifyEmailCode | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:310 | codeError · 输入验证码 | BillingWindow.showLogin / showCode / verifyCode / showCodeUnavailable；users.verifyEmailCode | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:344 | codeLocked · 请重新获取验证码 | BillingWindow.showLogin / showCode / verifyCode / showCodeUnavailable；users.verifyEmailCode | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:368 | loginDone · 已登录，100 点已到账 | BillingWindow authDidChange；BillingManager.refreshWallet；BillingCoordinator.continueIntent | 按 v0.5 登录后直接恢复原操作；符合条件的新用户赠点用 toast 提醒，无赠点不作到账承诺 |
| 286:397 | loginNoGift · 已登录 | BillingWindow authDidChange；BillingManager.refreshWallet；BillingCoordinator.continueIntent | 按 v0.5 登录后直接恢复原操作；符合条件的新用户赠点用 toast 提醒，无赠点不作到账承诺 |
| 286:428 | loginReturning · 欢迎回来 | BillingWindow authDidChange；BillingManager.refreshWallet；BillingCoordinator.continueIntent | 按 v0.5 登录后直接恢复原操作；符合条件的新用户赠点用 toast 提醒，无赠点不作到账承诺 |
| 286:455 | loginPurchase · 登录后购买 Pro | BillingWindow.showLogin / showCode / verifyCode / showCodeUnavailable；users.verifyEmailCode | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:480 | codeSentPurchase · 输入验证码 | BillingWindow.showLogin / showCode / verifyCode / showCodeUnavailable；users.verifyEmailCode | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:513 | firstPaidNotice · 运行前了解一下 | BillingCoordinator.decide；account/widget-notice；createTask.expectedCreditCost | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:547 | taskSubmitted · 已提交高清放大 | BillingCoordinator.showSubmitted；InspectToastWindow.showAction；WidgetTaskManager.start | 按 v0.5 使用 toast 和排队撤销，任务状态集成现有任务中心 |
| 286:574 | freeSubmitted · 已提交免费图床 | BillingCoordinator.showSubmitted；InspectToastWindow.showAction；WidgetTaskManager.start | 按 v0.5 使用 toast 和排队撤销，任务状态集成现有任务中心 |
| 286:595 | taskUndone · 已撤销，8 点已退回 | WidgetTaskClient / WidgetTaskManager；WidgetTaskCenterWindow；BillingCoordinator.confirmRunningCancellation | 任务中心和 toast 呈现；服务端决定扣点和原价退点，队列满不受理、不扣点；UI 待验收 |
| 286:623 | queueFull · 任务队列已满 | WidgetTaskClient / WidgetTaskManager；WidgetTaskCenterWindow；BillingCoordinator.confirmRunningCancellation | 任务中心和 toast 呈现；服务端决定扣点和原价退点，队列满不受理、不扣点；UI 待验收 |
| 286:647 | highCostConfirm · 确认运行视频去水印 | BillingCoordinator.decide；account/widget-notice；createTask.expectedCreditCost | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:679 | highCostSubmitted · 已提交视频去水印 | BillingCoordinator.showSubmitted；InspectToastWindow.showAction；WidgetTaskManager.start | 按 v0.5 使用 toast 和排队撤销，任务状态集成现有任务中心 |
| 286:704 | priceChanged · 价格已更新 | BillingCoordinator.decide；account/widget-notice；createTask.expectedCreditCost | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:736 | priceChangedSubmitted · 已提交高清放大 | BillingCoordinator.showSubmitted；InspectToastWindow.showAction；WidgetTaskManager.start | 按 v0.5 使用 toast 和排队撤销，任务状态集成现有任务中心 |
| 286:761 | taskQueued · 高清放大排队中 | WidgetTaskClient / WidgetTaskManager；WidgetTaskCenterWindow；BillingCoordinator.confirmRunningCancellation | 任务中心和 toast 呈现；服务端决定扣点和原价退点，队列满不受理、不扣点；UI 待验收 |
| 286:789 | taskRunning · 高清放大处理中 | WidgetTaskClient / WidgetTaskManager；WidgetTaskCenterWindow；BillingCoordinator.confirmRunningCancellation | 任务中心和 toast 呈现；服务端决定扣点和原价退点，队列满不受理、不扣点；UI 待验收 |
| 286:817 | cancelRunningConfirm · 取消正在处理的任务？ | WidgetTaskClient / WidgetTaskManager；WidgetTaskCenterWindow；BillingCoordinator.confirmRunningCancellation | 任务中心和 toast 呈现；服务端决定扣点和原价退点，队列满不受理、不扣点；UI 待验收 |
| 286:840 | taskCancelled · 任务已取消 | WidgetTaskClient / WidgetTaskManager；WidgetTaskCenterWindow；BillingCoordinator.confirmRunningCancellation | 任务中心和 toast 呈现；服务端决定扣点和原价退点，队列满不受理、不扣点；UI 待验收 |
| 286:867 | taskDone · 高清放大完成 | WidgetTaskClient / WidgetTaskManager；WidgetTaskCenterWindow；BillingCoordinator.confirmRunningCancellation | 任务中心和 toast 呈现；服务端决定扣点和原价退点，队列满不受理、不扣点；UI 待验收 |
| 286:894 | taskFailedRefund · 处理失败，8 点已退回 | WidgetTaskClient / WidgetTaskManager；WidgetTaskCenterWindow；BillingCoordinator.confirmRunningCancellation | 任务中心和 toast 呈现；服务端决定扣点和原价退点，队列满不受理、不扣点；UI 待验收 |
| 286:923 | taskExpiredRefund · 排队超时，8 点已退回 | WidgetTaskClient / WidgetTaskManager；WidgetTaskCenterWindow；BillingCoordinator.confirmRunningCancellation | 任务中心和 toast 呈现；服务端决定扣点和原价退点，队列满不受理、不扣点；UI 待验收 |
| 286:952 | insufficient · 还差 6 点 | BillingWindow.showTopup；BillingCoordinator.Intent / decide | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:994 | insufficientUSD · 还差 6 点 | BillingWindow.showTopup；BillingCoordinator.Intent / decide | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:1036 | insufficientManual · 还差 6 点 | BillingWindow.showTopup；BillingCoordinator.Intent / decide | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:1076 | awaitTask · 请在浏览器完成支付 | BillingCoordinator.showPayment / poll；orders API | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:1107 | pancakeTask · Glance 点数 · 330 点 | Pancake hosted checkout；official SDK priceSnapshot / includePaymentMethods / darkMode / language | 外部收银台；App 不仿制支付页面。待商户配置后实测渠道 UI |
| 286:1136 | returnTask · 付款完成，正在返回 Glance | site/pay/return；website-static/src/pages/50-payment-return.html；handlePaymentReturn | 官网尝试唤起 App，仅服务端验签通知发放权益；待真实浏览器回跳联调 |
| 286:1160 | confirmingTask · 正在确认付款结果 | BillingCoordinator.showPayment / poll；orders API | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:1192 | abandonTask · 放弃本次支付？ | BillingCoordinator.confirmAbandon；abandonOrder；billingWebhook | 明确放弃只改变本站待付状态，不假装取消渠道订单；迟到成功仍交付 |
| 286:1217 | creditedAutoSubmit · 330 点已到账，任务已提交 | BillingCoordinator.fulfilled / restorePendingPayments；BillingTaskContext | 自动提交仅本次勾选；重新校验价格和源窗口；到账不等于任务已受理，统计基于任务记录 |
| 286:1249 | creditedManual · 330 点已到账 | BillingCoordinator.fulfilled / restorePendingPayments；BillingTaskContext | 自动提交仅本次勾选；重新校验价格和源窗口；到账不等于任务已受理，统计基于任务记录 |
| 286:1280 | resumedSubmitted · 已提交高清放大 | BillingCoordinator.showSubmitted；InspectToastWindow.showAction；WidgetTaskManager.start | 按 v0.5 使用 toast 和排队撤销，任务状态集成现有任务中心 |
| 286:1303 | walletPending · 点数钱包 | BillingWindow.showWallet；wallet API | 按 v0.5 合并钱包和最近 100 条可滚动流水；保留待任务入口与负余额说明 |
| 286:1329 | wallet · 点数钱包 | BillingWindow.showWallet；wallet API | 按 v0.5 合并钱包和最近 100 条可滚动流水；保留待任务入口与负余额说明 |
| 286:1357 | ledgerAll · 点数记录 | BillingWindow.showWallet；wallet API | 按 v0.5 合并钱包和最近 100 条可滚动流水；保留待任务入口与负余额说明 |
| 286:1389 | topup · 充值点数 | BillingWindow.showTopup；BillingCoordinator.Intent / decide | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:1430 | topupUSD · 充值点数 | BillingWindow.showTopup；BillingCoordinator.Intent / decide | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:1470 | awaitWallet · 请在浏览器完成支付 | BillingCoordinator.showPayment / poll；orders API | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:1502 | pancakeWallet · Glance 点数 · 330 点 | Pancake hosted checkout；official SDK priceSnapshot / includePaymentMethods / darkMode / language | 外部收银台；App 不仿制支付页面。待商户配置后实测渠道 UI |
| 286:1531 | returnWallet · 付款完成，正在返回 Glance | site/pay/return；website-static/src/pages/50-payment-return.html；handlePaymentReturn | 官网尝试唤起 App，仅服务端验签通知发放权益；待真实浏览器回跳联调 |
| 286:1555 | confirmingWallet · 正在确认付款结果 | BillingCoordinator.showPayment / poll；orders API | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:1587 | abandonWallet · 放弃本次支付？ | BillingCoordinator.confirmAbandon；abandonOrder；billingWebhook | 明确放弃只改变本站待付状态，不假装取消渠道订单；迟到成功仍交付 |
| 286:1612 | walletCredited · 330 点已到账 | BillingCoordinator.fulfilled / restorePendingPayments；BillingTaskContext | 自动提交仅本次勾选；重新校验价格和源窗口；到账不等于任务已受理，统计基于任务记录 |
| 286:1639 | walletAfter · 点数钱包 | BillingWindow.showWallet；wallet API | 按 v0.5 合并钱包和最近 100 条可滚动流水；保留待任务入口与负余额说明 |
| 286:1667 | walletNegative · 点数钱包 | BillingWindow.showWallet；wallet API | 按 v0.5 合并钱包和最近 100 条可滚动流水；保留待任务入口与负余额说明 |
| 286:1694 | proOffer · Glance Pro | BillingWindow.showPro；BillingManager.createOrder(displayedPrice)；readPricing | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:1726 | proOfferSignedIn · Glance Pro | BillingWindow.showPro；BillingManager.createOrder(displayedPrice)；readPricing | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:1764 | proOfferUSD · Glance Pro | BillingWindow.showPro；BillingManager.createOrder(displayedPrice)；readPricing | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:1801 | proPriceChanged · 价格已更新 | BillingCoordinator.checkout；createOrder 409 price_changed / pending_order | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:1831 | awaitPro · 请在浏览器完成支付 | BillingCoordinator.showPayment / poll；orders API | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:1863 | pancakePro · Glance Pro | Pancake hosted checkout；official SDK priceSnapshot / includePaymentMethods / darkMode / language | 外部收银台；App 不仿制支付页面。待商户配置后实测渠道 UI |
| 286:1892 | returnPro · 付款完成，正在返回 Glance | site/pay/return；website-static/src/pages/50-payment-return.html；handlePaymentReturn | 官网尝试唤起 App，仅服务端验签通知发放权益；待真实浏览器回跳联调 |
| 286:1916 | confirmingPro · 正在确认付款结果 | BillingCoordinator.showPayment / poll；orders API | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:1948 | abandonPro · 放弃本次支付？ | BillingCoordinator.confirmAbandon；abandonOrder；billingWebhook | 明确放弃只改变本站待付状态，不假装取消渠道订单；迟到成功仍交付 |
| 286:1973 | proActivated · Pro 已激活 | BillingCoordinator.fulfilled；BillingManager.refreshEntitlements | 续购完成使用独立说明，不再误报新买断或赠点 |
| 286:2008 | account · 账户与授权 | BillingWindow.showAccount / confirmSignOut；AuthManager.signOut | 退出清空待提交任务和本机授权，回到原窗口；无需单独的退出确认结果页 |
| 286:2041 | accountFree · 账户与授权 | BillingWindow.showAccount / confirmSignOut；AuthManager.signOut | 退出清空待提交任务和本机授权，回到原窗口；无需单独的退出确认结果页 |
| 286:2068 | signOut · 退出登录？ | BillingWindow.showAccount / confirmSignOut；AuthManager.signOut | 退出清空待提交任务和本机授权，回到原窗口；无需单独的退出确认结果页 |
| 286:2092 | accountSignedOut · 已退出登录 | BillingWindow.showAccount / confirmSignOut；AuthManager.signOut | 退出清空待提交任务和本机授权，回到原窗口；无需单独的退出确认结果页 |
| 286:2116 | devices · 你的 Mac | BillingWindow.showDevices / confirmRelease；activateDevice / releaseDevice | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:2140 | devicesFull · 设备名额已用满 | BillingWindow.showDevices / confirmRelease；activateDevice / releaseDevice | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:2167 | releaseLimit · 本月释放次数已用完 | BillingWindow.showDevices / confirmRelease；activateDevice / releaseDevice | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:2191 | deviceReleased · 这台 iMac 已激活 | BillingWindow.showDevices / confirmRelease；activateDevice / releaseDevice | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:2215 | releasedMac · 这台 Mac 已被释放 | BillingCoordinator.requireLocalTool；BillingManager.verifiedClaims / needsUpdates | 入口可见并带锁；区分免费版、更新资格、离线过期和被释放设备。待用户运行 UI 验收 |
| 286:2239 | offlineExpired · 请联网验证 Pro | BillingCoordinator.requireLocalTool；BillingManager.verifiedClaims / needsUpdates | 入口可见并带锁；区分免费版、更新资格、离线过期和被释放设备。待用户运行 UI 验收 |
| 286:2264 | refundRequest · 申请退款 | BillingWindow.showOrderDetails / showRefund；requestRefund / denyRefund；billingWebhook | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:2295 | refundSubmitted · 退款申请已提交 | BillingWindow.showOrderDetails / showRefund；requestRefund / denyRefund；billingWebhook | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:2319 | refundedPro · Pro 已退款 | BillingWindow.showOrderDetails / showRefund；requestRefund / denyRefund；billingWebhook | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:2348 | refundFailed · 退款暂未完成 | BillingWindow.showOrderDetails / showRefund；requestRefund / denyRefund；billingWebhook | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:2370 | refundRequestCredits · 申请退款 | BillingWindow.showOrderDetails / showRefund；requestRefund / denyRefund；billingWebhook | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:2402 | refundedCredits · 充值已退款 | BillingWindow.showOrderDetails / showRefund；requestRefund / denyRefund；billingWebhook | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:2428 | refundRejectedUsed · 这笔充值无法退款 | BillingWindow.showOrderDetails / showRefund；requestRefund / denyRefund；billingWebhook | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:2453 | confirmTimeout · 付款确认较慢 | BillingCoordinator.showPayment / poll；BillingWindow.showOrderDetails | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:2480 | pendingOrder · 你有一笔订单还没付款 | BillingCoordinator.checkout；createOrder 409 price_changed / pending_order | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:2510 | orderExpired · 订单已失效 | BillingCoordinator.showPayment / poll；BillingWindow.showOrderDetails | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:2536 | wechatLimit · 本月微信支付额度已用完 | BillingCoordinator.showWeChatHelp；abandonOrder；BillingWindow.paymentSwitch | 渠道不会回传未付款的限额原因；提供明确帮助入口，用户选择后释放本站待付名额并切换 USD，不伪造限额探测 |
| 286:2560 | lateCredit · 330 点已到账 | BillingCoordinator.fulfilled / restorePendingPayments；BillingTaskContext | 自动提交仅本次勾选；重新校验价格和源窗口；到账不等于任务已受理，统计基于任务记录 |
| 286:2582 | updateLocked · 此版本需要续购更新 | BillingCoordinator.requireLocalTool；BillingManager.verifiedClaims / needsUpdates | 入口可见并带锁；区分免费版、更新资格、离线过期和被释放设备。待用户运行 UI 验收 |
| 286:2612 | renewOffer · 续购功能更新 | BillingWindow.showPro；BillingManager.createOrder(displayedPrice)；readPricing | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:2638 | awaitRenew · 请在浏览器完成支付 | BillingCoordinator.showPayment / poll；orders API | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:2669 | pancakeRenew · Pro 功能更新 · 1 年 | Pancake hosted checkout；official SDK priceSnapshot / includePaymentMethods / darkMode / language | 外部收银台；App 不仿制支付页面。待商户配置后实测渠道 UI |
| 286:2698 | returnRenew · 付款完成，正在返回 Glance | site/pay/return；website-static/src/pages/50-payment-return.html；handlePaymentReturn | 官网尝试唤起 App，仅服务端验签通知发放权益；待真实浏览器回跳联调 |
| 286:2722 | confirmingRenew · 正在确认付款结果 | BillingCoordinator.showPayment / poll；orders API | 客户端代码覆盖；待用户运行 UI 验收 |
| 286:2754 | abandonRenew · 放弃本次支付？ | BillingCoordinator.confirmAbandon；abandonOrder；billingWebhook | 明确放弃只改变本站待付状态，不假装取消渠道订单；迟到成功仍交付 |
| 286:2779 | renewDone · 更新期已延长 | BillingCoordinator.fulfilled；BillingManager.refreshEntitlements | 续购完成使用独立说明，不再误报新买断或赠点 |

共 93 个原型状态。服务端自动化检查验证业务状态和账务不变量；客户端类型检查验证接口接线。运行时视觉效果、键盘交互、Google / 邮箱真实投递、支付和退款渠道联调，仍需用户运行验收。
