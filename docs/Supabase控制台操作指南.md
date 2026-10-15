# Supabase 控制台操作指南（酒链 B2B）

从零把 Supabase 配好，约 10 分钟。

## 1. 注册 / 登录 Supabase

打开 <https://supabase.com>，点右上角 **Start your project**，
用 GitHub 或邮箱注册登录（免费档足够用）。

## 2. 新建项目

1. 点 **New project**。
2. **Name**：随意，例如 `wine-b2b`。
3. **Database Password**：设一个密码并**记下来**（建库密码，暂时用不到，但别丢）。
4. **Region**：选 **Southeast Asia (Singapore)** 或 **Northeast Asia (Tokyo)**，国内访问快一些。
5. 点 **Create new project**，等 1~2 分钟初始化完成。

## 3. 执行建库脚本（最重要的一步）

1. 左侧边栏找 **SQL Editor**（或顶部 Database → SQL Editor）。
2. 点 **New query**。
3. 打开本项目 `sql/supabase_setup.sql`，**全文复制**，粘贴进去。
4. 点右下角 **Run**（执行约几秒）。

脚本是幂等的（只增不改），以后想重跑/改完再跑都安全。

## 4. 看自检输出（执行成功的样子）

脚本末尾会输出三张自检表：

**自检 1：表名 / 记录数 —— 5 行**（新库记录数都是 0）

| 表名 | 记录数 |
| --- | --- |
| messages | 0 |
| inquiries | 0 |
| orders | 0 |
| profiles | 0 |
| wines | 0 |

**自检 2：表 / 策略 / 适用操作 —— 15 行**（每张表 3 条策略）

**自检 3：汇总 —— 业务表数 = 5、策略数 = 15、触发器数 = 4**

三个数字全对上，数据库就绪 ✅。
如果编辑器只显示最后一个查询的结果，把「自检 1」那一段单独选中再 Run 一次即可。

## 5. 关闭邮箱确认（关键：让别人注册完就能直接登录）

注册后要收验证邮件才能登录，别人用你的网站时很容易卡在这一步。
Supabase 默认开启邮箱确认，**它不在 Email 弹窗里**（2026 年新版界面已挪走），按下面任选一种方式关掉。

### 方式 A（图形界面，1 分钟）

1. 左边栏 **Authentication** → **Sign In / Providers**
2. **别点 Email 进弹窗**——看页面**顶部**的 **User Signups**（用户注册）区域
3. 那里有两个开关：**Allow new users to sign up** 和 **Confirm email**
4. 把 **Confirm email** 关掉 → 点 **Save**

> 直接打开这个地址最快：`https://supabase.com/dashboard/project/<你的项目ref>/auth/providers`
>
> ⚠️ 官方 2026-07 已修正过这个路径：老教程里说的 “Authentication → Settings → Enable email confirmations” 和 “Email 弹窗里的 Confirm email” **都已经不存在了**，正确位置就是 Sign In / Providers 页面的 User Signups 区域。
>
> 另外：关掉开关**只对之后新注册的用户生效**，已经注册过的老账号仍需单独确认。

### 方式 B（执行 SQL，推荐：与后台开关无关，一劳永逸）

不想在界面里找开关，或找不到，直接执行脚本：

1. 左边栏 **SQL Editor** → **New query**
2. 打开本项目 `sql/auto_confirm_email.sql`，**全文复制**粘贴
3. 点 **Run**

它会做两件事：把历史未验证用户一次性确认 + 让新注册用户**自动变为已验证**。
于是任何人注册完，**立刻就能用邮箱 + 密码登录**，不需要点邮件链接，也不依赖那个后台开关。

想恢复原状（要求点邮件验证）：执行脚本末尾注释里的两条 `drop` 语句即可。

> 本站前端已内置双重兜底：注册后会自动尝试登录一次（方式 B 生效时直接进站）；
> 若仍未确认，会提示「请完成邮箱验证」并给出**重新发送验证邮件**按钮。

## 6. 复制 Project URL 和 Publishable key

1. 左侧 **Settings**（齿轮）→ **Data API**（或叫 API Keys）。
2. 复制 **Project URL**：形如 `https://abcdefghijklm.supabase.co`。
3. 复制 **Publishable key**：形如 `sb_publishable_xxxxxxxxxxxxxxxxxxxx`。

> 新版 Supabase 把密钥分三种：
> - **Publishable key**（`sb_publishable_` 开头）→ **前端用这个** ✅
> - **Secret key**（`sb_secret_` 开头）→ 只能放你自己的服务器，**绝对不能进前端**
> - 旧版 **anon key**（`eyJhbGciOi...` 开头的 JWT）→ 等效 Publishable key，也能用

## 7. 填进 config.js

打开 `js/config.js`：

- 第 10 行：`SUPABASE_URL: 'https://abcdefghijklm.supabase.co'`
- 第 13 行：`SUPABASE_ANON_KEY: 'sb_publishable_xxxxxxxxxxxxxxxxxxxx'`

保存，刷新页面，顶部黄色横幅消失 = 配置生效。

## 8. 为什么必须用 Publishable key 而不是 Secret key？

前端代码（HTML/JS）任何人按 F12 都能看到，里面的密钥等于公开的。
所以前端只能放**设计上就可以公开**的密钥：

- **Publishable key 受 RLS 约束**：就算拿着它直接调 API，
  也只能做 RLS 策略允许的事（浏览在售酒款、看自己的订单等）。
  数据库真正的「门」是 15 条 RLS 策略，不是这个 key。
- **Secret key 绕过 RLS**：它拥有数据库全部权限（包括读所有用户的订单、
  改任何数据）。一旦进前端被看到，等于数据库裸奔——任何人都能提走全库数据。

一句话：**前端用 Publishable，Secret 只留在自己的后端服务器，永远不出现在浏览器代码里。**

## 下一步

回到 `README.md` 的「快速开始」：起服务 → 打开 <http://localhost:8000/index.html> → 按 `docs/冒烟测试清单.md` 走流程。
