# 原生鸡腿明细

## 范围与界面

从自己的原生个人页点击「鸡腿」进入 UIKit 明细页，不使用 Texture。接口只支持当前登录账号，因此他人个人页的鸡腿统计不提供跳转。

沿用星辰账簿的紧凑布局：40pt 🍗 emoji，无背景；右侧鸡腿余额与昵称，自己的 UID 不显示。每行两层：理由与带正负号的变动数，时间与变动后余额。完整显示原站理由，不擅自改写，也不增加头像、筛选、转账等能力。

初次加载每条记录一整个圆角骨架；支持下拉刷新、上拉或点击加载更多、首屏错误重试、分页失败原位重试、空列表与末页。系统动态颜色与动态字体同时覆盖浅深色及辅助功能大字。

## 已核实的数据契约

来源：https://www.nodeseek.com/credit#/p-1 ，以及网页公开的 credit 脚本。

- GET `/api/account/credit/page-<page>`，依赖当前账号的登录 Cookie，不接受目标用户 uid。
- 响应：`{"success":true,"data":[[变动数,变动后余额,"理由","ISO 时间"]],"total":773}`。
- 每页 20 条，页数按 `ceil(total / 20)` 计算，上限 100，与网页一致。
- 已核对第 1 页与第 39 页真实响应，末页有 13 条。真实余额来自账户资料，不能由当前分页条数推算。
- 无独立记录 ID。App 按返回顺序保留记录，不把同一时间、同一理由的流水误删为重复项。页码分页在服务端新增流水时可能发生跨页重复，刷新会重新读取第一页；这是原接口的限制。
- 未登录、HTTP 或 JSON 错误必须展示失败状态，不能当成空账簿。

## 实现边界与验证

- NodeSeekUserContentClient 增加只读请求，复用现有 JSON 请求指纹及 URLSession。
- UserCreditRecord / UserCreditViewModel 处理元组解码与页码状态；失败不前移页码，过时请求不覆盖刷新结果。
- UserCreditViewController / UserCreditCell 使用普通 UIKit 控件。
- UserProfileViewController 仅在自己的主页启用鸡腿入口，等级和其他入口维持当前行为。
- 窄范围验证覆盖接口路径、元组解析、失败与空数据、页数边界、分页重试、刷新替换、相同流水保留、过时响应，以及模拟数据下的浅深色、骨架、大字、分页与返回。

## 验证结果

- `make xcode-build-tests` 通过。
- iPhone 17 Pro / iOS 26.5 模拟器：NodeSeekUserContentClientTests、UserCreditViewModelTests、UserCreditViewControllerTests、UserStardustViewControllerTests，共 28 个测试通过、0 失败。
- 已查看浅色、深色、整条骨架和辅助功能最大字体的渲染截图。页面与分页测试使用模拟记录，真实网页已核对首末页接口；未做真机登录态全流程检查。
