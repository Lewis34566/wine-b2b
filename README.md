# 酒链 B2B —— 葡萄酒 B2B 商家对接平台

纯前端项目（HTML + CSS + 原生 JS），后端用 **Supabase**（PostgreSQL + Auth + RLS），
不需要自建服务器。手机优先响应式，酒红 × 金色主题。

视觉基础取自「Yantai Wine Hub」落地页（酒红 `#8b1e3f`）。

## 🌐 在线演示

浏览器直接打开，无需安装任何东西：

**https://lewis34566.github.io/wine-b2b/**

（GitHub Pages 托管，源码仓库：https://github.com/Lewis34566/wine-b2b ；备用演示：https://winelink-b2b.app.workbuddy.host/ ）

界面支持 **中文 / English / Русский** 三语，右上角切换，选择会被记住。

演示账号（先在 Supabase SQL Editor 执行 `sql/demo_seed.sql`）：
- 供应商：`demo@jiutong-wine.cn` / `Demo123456`
- 采购商：`demo@yunxuan-trade.cn` / `Demo123456`

## 功能

| 页面 | 功能 |
| --- | --- |
| `index.html` | 首页 —— Yantai Wine Hub 落地页（供应商数据库预览 + 定价 + 流程），含登录/注册入口 |
| `login.html` | 登录 / 注册（角色选择：供应商 / 采购商） |
| `home.html` | 酒款一览（搜索 + 产地/年份/品种/价格筛选），游客可浏览 |
| `product.html` | 酒款详情（询价 / 下单，底部弹层，金额实时联动） |
| `supplier-dashboard.html` | 供应商后台（酒款管理 / 询价回复 / 订单状态流转） |
| `buyer-dashboard.html` | 采购商后台（我的询价 / 我的订单 / 确认收货） |
| `messages.html` | 站内消息（会话列表 + 实时聊天 + 轮询兜底） |
| `profile.html` | 个人资料 |

## 文件结构

```
酒链B2B/
├── index.html               首页（Yantai Wine Hub 落地页）
├── login.html               登录/注册（角色选择）
├── home.html                酒款一览（搜索 + 筛选）
├── product.html             酒款详情（询价 / 下单，底部弹层）
├── supplier-dashboard.html  供应商后台
├── buyer-dashboard.html     采购商后台
├── messages.html            站内消息
├── profile.html             个人资料
├── css/style.css            全站样式
├── js/config.js             ★ 唯一需要填密钥的文件（第 10、13 行）
├── js/supabase.js           公共模块：客户端初始化 + 工具函数 + 导航 + 弹层
├── js/i18n.js               三语字典与切换逻辑（zh 默认 / en / ru，localStorage 记忆）
├── js/vendor-supabase.js    本地化的 supabase-js v2 UMD 版（约 213KB，勿改）
├── sql/supabase_setup.sql   建表 + RLS 策略 + 触发器（幂等，可重复执行）
├── sql/demo_seed.sql        演示种子数据（2 个演示账号 + 8 款三语酒，幂等）
├── assets/favicon.svg       站点图标
├── docs/冒烟测试清单.md       按顺序验证全流程
└── docs/Supabase控制台操作指南.md  从零配置 Supabase
```

## 快速开始（3 步）

1. **建库**：按 `docs/Supabase控制台操作指南.md` 在 Supabase 建项目，
   把 `sql/supabase_setup.sql` 全文粘贴到 SQL Editor 执行（末尾输出自检表）。
2. **填密钥**：打开 `js/config.js`，把第 10、13 行的两个占位符换成
   Project URL 和 Publishable key。
3. **起服务**：在本目录运行
   ```bash
   python -m http.server 8000
   ```
   浏览器打开 <http://localhost:8000/index.html>（或直接用上面的在线演示链接）。

> ⚠️ 不要用 `file://` 双击直接打开 html。浏览器会限制 localStorage，
> 登录态会丢。一定要走 http 服务。

## 手机同 WiFi 访问

1. 电脑查局域网 IP：`ipconfig`（Windows）/ `ifconfig`（Mac），
   找 WLAN 无线网卡的 IPv4 地址（示例 `192.168.x.x`，以你本机实际为准）。
2. 手机连同一 WiFi，浏览器打开 `http://192.168.243.174:8000/index.html`。
3. Windows 防火墙若拦截 8000 端口，以管理员身份运行：
   ```
   netsh advfirewall firewall add rule name="WineB2B 8000" dir=in action=allow protocol=TCP localport=8000
   ```
   （通常首次启动服务时会弹「允许访问」对话框，点允许即可。）

## 设计说明（为什么这么建）

- **5 张表、15 条 RLS 策略、4 个触发器**：profiles / wines / inquiries / orders / messages，
  每表 3 条策略（查/增/改 各按角色收紧）。策略全部写在数据库里，前端代码泄漏密钥也拿不走别人数据。
- **金额的唯一真相在数据库**：下单时前端只传 `quantity`，单价和总额由
  `orders_derive_from_wine` 触发器从酒款表推导回填，前端显示的合计只是预览。
- **订单状态机在数据库**：待确认→已确认→已发货→已完成，由 `check_order_transition`
  触发器强制（供应商才能确认/发货，采购商才能收货），确认订单时自动扣库存，库存不足会报错。
- **`js/supabase.js` 里的客户端实例叫 `sb`**，不能叫 `supabase`：
  UMD 版 SDK 已占用 `window.supabase` 全局名，重名会报
  `Identifier 'supabase' has already been declared`。
- **SQL 脚本「只增不改」**：不用 DROP / DELETE，表用 `IF NOT EXISTS`，
  策略用 `pg_policies` 判断，触发器用 `pg_trigger` 判断，可放心重复执行。

## 发布到公网（让所有人访问）

本项目已发布在 **GitHub Pages**：https://lewis34566.github.io/wine-b2b/ （每次 push 到 `main` 自动更新）。

本项目是纯静态站点，任何静态托管平台都可以发布（GitHub Pages / Netlify / Vercel / 任意 Nginx），任何人（不限于同一 WiFi）打开链接就能注册 / 登录 / 浏览。
发布后请务必确认下面这一项，否则别人能注册但登不进去：

- **让"注册即登录"生效**（二选一，推荐方式 B）：
  - **方式 A**：**Authentication → Sign In / Providers** 页面**顶部**的 **User Signups** 区域，关掉 **Confirm email** 并 Save。
    （注意：新版界面里它**不在 Email 弹窗内**；老教程说的 Settings → Enable email confirmations 路径已失效）
  - **方式 B（推荐，不受界面改版影响）**：SQL Editor 里执行 `sql/auto_confirm_email.sql`
    —— 会把历史未验证用户一次性确认，并让新注册用户自动变成"已验证"，注册完直接能登录。
  两者都能达到效果：注册成功即刻获得登录态，无需收邮件；Supabase 默认发信额度有限，公网演示强烈建议关闭。

页面已内置兜底：如果邮箱确认仍开着，注册/登录时会明确提示"请先完成邮箱验证"，并提供
**「重新发送验证邮件」** 按钮，不会再出现"注册了却一脸茫然"的情况。

## 常见问题

| 问题 | 原因 / 解决 |
| --- | --- |
| 页面顶部黄色横幅提示密钥未填 | `js/config.js` 里还是占位符，按操作指南填好并**刷新页面** |
| 注册后提示"请先完成邮箱验证" | Supabase 开启了邮箱确认。最省事：SQL Editor 执行 `sql/auto_confirm_email.sql`；或在 Sign In / Providers 顶部 User Signups 区域关掉 Confirm email |
| 注册成功但点登录报 Invalid login credentials | 邮箱确认没关（见上），或密码错 |

| 消息不实时、要等几秒 | Realtime 未开启时前端自动 8 秒轮询兜底，功能不受影响 |
| 供应商确认订单报「库存不足」 | 库存小于订单数量，先在酒款管理里补库存 |
| 手机打不开页面 | 电脑和手机必须在同一 WiFi；检查防火墙是否放行 8000 |
| 换了浏览器/清缓存后要重新登录 | 登录态存在 localStorage，换浏览器就是另一份 |
