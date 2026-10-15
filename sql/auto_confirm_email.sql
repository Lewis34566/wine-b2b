-- ============================================================
-- 酒链 B2B · 邮箱自动确认（注册即可登录）
-- ------------------------------------------------------------
-- 什么时候用：
--   1) Supabase 后台找不到「Confirm email」开关（新版界面挪到了
--      Authentication → Sign In / Providers 顶部的「User Signups」区域，
--      已不在 Email 弹窗里）；
--   2) 或者不想动那个开关，只想让本站用户注册完就能直接登录。
--
-- 做了什么：
--   ① 把历史遗留的「未验证」用户一次性确认掉；
--   ② 新注册用户插入 auth.users 时自动打上「已验证」标记，
--      于是注册后可以直接用邮箱 + 密码登录（无需点邮件链接）。
--
-- 执行位置：Supabase 控制台 → SQL Editor → New query → 粘贴全文 → Run
-- 幂等：重复执行安全（可放心重跑）。
-- 注意：直接改 auth.users 属于「绕过邮箱验证」，适合课程演示 / 内测；
--       正式生产环境建议保留邮箱验证。
-- ============================================================

-- ① 一次性确认所有历史未验证用户
update auth.users
   set email_confirmed_at = coalesce(email_confirmed_at, now()),
       confirmed_at       = coalesce(confirmed_at, now())
 where email_confirmed_at is null;

-- ② 新注册用户自动确认（BEFORE INSERT 直接改写即将写入的行）
create or replace function public.auto_confirm_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.email_confirmed_at is null then
    new.email_confirmed_at := now();
  end if;
  if new.confirmed_at is null then
    new.confirmed_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_auto_confirm on auth.users;
create trigger on_auth_user_auto_confirm
  before insert on auth.users
  for each row execute function public.auto_confirm_new_user();

-- ③ 自检：未确认数应为 0，用户总数 = 已确认数
select count(*)                                              as "用户总数",
       count(email_confirmed_at)                             as "已确认数",
       count(*) filter (where email_confirmed_at is null)     as "未确认数"
  from auth.users;

-- ------------------------------------------------------------
-- 如需撤销（恢复「必须点邮件验证」的原状）：
--   drop trigger if exists on_auth_user_auto_confirm on auth.users;
--   drop function if exists public.auto_confirm_new_user();
-- （已确认过的用户不会回退，属正常现象）
-- ============================================================
