-- =====================================================================
-- 酒链 B2B · Supabase 数据库初始化脚本（整理版：新库/旧库均可执行）
-- 建表 + RLS 策略 + 触发器 + 索引 + 自检
--
-- 设计原则：只增不改（无 DROP / DELETE），可重复执行
-- 用法：Supabase 控制台 → SQL Editor → 全文粘贴 → Run
-- 自检预期：业务表 5 行、策略 15 行、触发器 8 个
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- 1. profiles ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  role text not null default 'buyer' check (role in ('buyer', 'supplier')),
  company_name text,
  contact_name text,
  phone text,
  region text,
  bio text,
  created_at timestamptz not null default now()
);

-- ---------- 2. wines ----------
create table if not exists public.wines (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.profiles (id) on delete cascade,
  name text not null,
  origin text,
  vintage integer,
  variety text,
  wine_type text,
  price numeric(10,2) not null default 0 check (price >= 0),
  stock integer not null default 0 check (stock >= 0),
  description text,
  image_url text,
  status text not null default 'on_sale',
  created_at timestamptz not null default now()
);

-- ---------- 3. inquiries ----------
create table if not exists public.inquiries (
  id uuid primary key default gen_random_uuid(),
  wine_id uuid not null references public.wines (id) on delete cascade,
  buyer_id uuid not null references public.profiles (id) on delete cascade,
  message text,
  expected_price numeric(10,2),
  status text not null default 'pending',
  reply text,
  replied_at timestamptz,
  created_at timestamptz not null default now()
);

-- ---------- 4. orders ----------
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  wine_id uuid not null references public.wines (id) on delete cascade,
  supplier_id uuid not null references public.profiles (id) on delete cascade,
  buyer_id uuid not null references public.profiles (id) on delete cascade,
  quantity integer not null check (quantity > 0),
  unit_price numeric(10,2) not null,
  total_amount numeric(10,2) not null,
  status text not null default 'pending_confirm',
  remark text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- 5. messages ----------
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles (id) on delete cascade,
  receiver_id uuid not null references public.profiles (id) on delete cascade,
  content text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

-- ---------- 补列：旧表结构缺列时自动补齐（新库无影响，只增不改） ----------
-- 原因：create table if not exists 遇到同名旧表会整张跳过，
--       后续索引/策略引用缺失的列就会报 42703。
-- 补列统一不加 not null（旧行没有值），约束以新建表时为准。
alter table public.profiles
  add column if not exists email text,
  add column if not exists role text default 'buyer',
  add column if not exists company_name text,
  add column if not exists contact_name text,
  add column if not exists phone text,
  add column if not exists region text,
  add column if not exists bio text,
  add column if not exists created_at timestamptz default now();

alter table public.wines
  add column if not exists supplier_id uuid references public.profiles (id) on delete cascade,
  add column if not exists name text,
  add column if not exists origin text,
  add column if not exists vintage integer,
  add column if not exists variety text,
  add column if not exists wine_type text,
  add column if not exists price numeric(10,2) default 0,
  add column if not exists stock integer default 0,
  add column if not exists description text,
  add column if not exists image_url text,
  add column if not exists status text default 'on_sale',
  add column if not exists created_at timestamptz default now();

alter table public.inquiries
  add column if not exists wine_id uuid references public.wines (id) on delete cascade,
  add column if not exists buyer_id uuid references public.profiles (id) on delete cascade,
  add column if not exists message text,
  add column if not exists expected_price numeric(10,2),
  add column if not exists status text default 'pending',
  add column if not exists reply text,
  add column if not exists replied_at timestamptz,
  add column if not exists created_at timestamptz default now();

alter table public.orders
  add column if not exists wine_id uuid references public.wines (id) on delete cascade,
  add column if not exists supplier_id uuid references public.profiles (id) on delete cascade,
  add column if not exists buyer_id uuid references public.profiles (id) on delete cascade,
  add column if not exists quantity integer,
  add column if not exists unit_price numeric(10,2),
  add column if not exists total_amount numeric(10,2),
  add column if not exists status text default 'pending_confirm',
  add column if not exists remark text,
  add column if not exists created_at timestamptz default now(),
  add column if not exists updated_at timestamptz default now();

alter table public.messages
  add column if not exists sender_id uuid references public.profiles (id) on delete cascade,
  add column if not exists receiver_id uuid references public.profiles (id) on delete cascade,
  add column if not exists content text,
  add column if not exists is_read boolean default false,
  add column if not exists created_at timestamptz default now();

-- ---------- 索引 ----------
create index if not exists idx_wines_supplier     on public.wines (supplier_id);
create index if not exists idx_wines_status       on public.wines (status);
create index if not exists idx_inquiries_wine     on public.inquiries (wine_id);
create index if not exists idx_inquiries_buyer    on public.inquiries (buyer_id);
create index if not exists idx_orders_wine        on public.orders (wine_id);
create index if not exists idx_orders_supplier    on public.orders (supplier_id);
create index if not exists idx_orders_buyer       on public.orders (buyer_id);
create index if not exists idx_messages_sender    on public.messages (sender_id);
create index if not exists idx_messages_receiver  on public.messages (receiver_id);

-- ---------- 触发器函数 1：注册后自动创建 profile ----------
-- 修正：role 只允许 buyer / supplier，防止注册时传入任意角色
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, role, company_name, contact_name, phone)
  values (
    new.id,
    new.email,
    case when new.raw_user_meta_data ->> 'role' = 'supplier' then 'supplier' else 'buyer' end,
    new.raw_user_meta_data ->> 'company_name',
    new.raw_user_meta_data ->> 'contact_name',
    new.raw_user_meta_data ->> 'phone'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

do $$ begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'on_auth_user_created' and tgrelid = 'auth.users'::regclass
  ) then
    create trigger on_auth_user_created
      after insert on auth.users
      for each row execute function public.handle_new_user();
  end if;
end $$;

-- ---------- 触发器函数 2：下单时由酒款推导供应商/单价/总额 ----------
-- 修正：强制初始状态 pending_confirm（原版可直接插入 confirmed 绕过状态机）；
--       校验酒款在售、禁止自己买自己的酒
create or replace function public.orders_derive_from_wine()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  w_supplier uuid;
  w_price numeric(10,2);
  w_status text;
begin
  select supplier_id, price, status into w_supplier, w_price, w_status
  from public.wines where id = new.wine_id;
  if not found then
    raise exception '酒款不存在';
  end if;
  if w_status <> 'on_sale' then
    raise exception '该酒款已下架';
  end if;
  if w_supplier = new.buyer_id then
    raise exception '不能购买自己的酒款';
  end if;
  new.supplier_id  := w_supplier;
  new.unit_price   := w_price;
  new.total_amount := round((new.quantity * w_price)::numeric, 2);
  new.status       := 'pending_confirm';
  return new;
end;
$$;

do $$ begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'orders_derive_from_wine_t' and tgrelid = 'public.orders'::regclass
  ) then
    create trigger orders_derive_from_wine_t
      before insert on public.orders
      for each row execute function public.orders_derive_from_wine();
  end if;
end $$;

-- ---------- 触发器函数 3：订单状态机 ----------
-- 修正：按"该订单的供应商/采购商"校验，而不是看 profiles.role
--       （原版中角色是供应商的用户，作为买家也能确认自己的订单）
create or replace function public.check_order_transition()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if old.status = 'pending_confirm' then
    if new.status = 'confirmed' then
      if auth.uid() is distinct from new.supplier_id then
        raise exception '只有该订单的供应商可以确认订单';
      end if;
      update public.wines w
         set stock = w.stock - new.quantity
       where w.id = new.wine_id
         and w.stock >= new.quantity;
      if not found then
        raise exception '库存不足，无法确认订单';
      end if;
    elsif new.status = 'cancelled' then
      if auth.uid() is distinct from new.buyer_id
         and auth.uid() is distinct from new.supplier_id then
        raise exception '无权取消该订单';
      end if;
    else
      raise exception '待确认订单只能流转为：已确认 或 已取消';
    end if;

  elsif old.status = 'confirmed' then
    if new.status <> 'shipped' or auth.uid() is distinct from new.supplier_id then
      raise exception '已确认订单只能由供应商发货';
    end if;

  elsif old.status = 'shipped' then
    if new.status <> 'completed' or auth.uid() is distinct from new.buyer_id then
      raise exception '已发货订单只能由采购商确认收货';
    end if;

  else
    raise exception '该状态的订单不可再变更';
  end if;

  return new;
end;
$$;

do $$ begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'check_order_transition_t' and tgrelid = 'public.orders'::regclass
  ) then
    create trigger check_order_transition_t
      before update of status on public.orders
      for each row execute function public.check_order_transition();
  end if;
end $$;

-- ---------- 触发器函数 4：刷新 updated_at ----------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$ begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'orders_set_updated_at_t' and tgrelid = 'public.orders'::regclass
  ) then
    create trigger orders_set_updated_at_t
      before update on public.orders
      for each row execute function public.set_updated_at();
  end if;
end $$;

-- ---------- 触发器函数 5（新增）：锁定不可改字段 ----------
-- 修正：RLS 只管"哪一行"，不管"哪一列"。
--   orders：买卖双方原本可直接改 quantity / total_amount / wine_id
--   profiles：用户原本可自行把 role 改成 supplier
--   inquiries：供应商原本可改买家的 message / expected_price
--   messages：接收方原本可改消息 content
-- auth.uid() 为空（SQL Editor / service_role）时放行，便于后台维护
create or replace function public.protect_immutable_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if auth.uid() is null then
    return new;
  end if;

  if tg_table_name = 'profiles' then
    if new.role is distinct from old.role then
      raise exception '不能修改账号角色';
    end if;

  elsif tg_table_name = 'orders' then
    if (new.wine_id, new.supplier_id, new.buyer_id, new.quantity,
        new.unit_price, new.total_amount, new.created_at)
       is distinct from
       (old.wine_id, old.supplier_id, old.buyer_id, old.quantity,
        old.unit_price, old.total_amount, old.created_at) then
      raise exception '订单的酒款、数量、金额等核心字段不可修改';
    end if;

  elsif tg_table_name = 'inquiries' then
    if (new.wine_id, new.buyer_id, new.message, new.expected_price, new.created_at)
       is distinct from
       (old.wine_id, old.buyer_id, old.message, old.expected_price, old.created_at) then
      raise exception '询价内容不可修改，只能回复';
    end if;

  elsif tg_table_name = 'messages' then
    if (new.sender_id, new.receiver_id, new.content, new.created_at)
       is distinct from
       (old.sender_id, old.receiver_id, old.content, old.created_at) then
      raise exception '消息内容不可修改，只能标记已读';
    end if;
  end if;

  return new;
end;
$$;

do $$ begin
  if not exists (select 1 from pg_trigger
    where tgname = 'profiles_protect_t' and tgrelid = 'public.profiles'::regclass) then
    create trigger profiles_protect_t
      before update on public.profiles
      for each row execute function public.protect_immutable_columns();
  end if;
  if not exists (select 1 from pg_trigger
    where tgname = 'orders_protect_t' and tgrelid = 'public.orders'::regclass) then
    create trigger orders_protect_t
      before update on public.orders
      for each row execute function public.protect_immutable_columns();
  end if;
  if not exists (select 1 from pg_trigger
    where tgname = 'inquiries_protect_t' and tgrelid = 'public.inquiries'::regclass) then
    create trigger inquiries_protect_t
      before update on public.inquiries
      for each row execute function public.protect_immutable_columns();
  end if;
  if not exists (select 1 from pg_trigger
    where tgname = 'messages_protect_t' and tgrelid = 'public.messages'::regclass) then
    create trigger messages_protect_t
      before update on public.messages
      for each row execute function public.protect_immutable_columns();
  end if;
end $$;

-- ---------- 开启 RLS ----------
alter table public.profiles  enable row level security;
alter table public.wines     enable row level security;
alter table public.inquiries enable row level security;
alter table public.orders    enable row level security;
alter table public.messages  enable row level security;

-- ---------- 授权（真正的门在 RLS 策略） ----------
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to anon, authenticated;
grant execute on all functions in schema public to anon, authenticated;

-- ---------- 策略：共 15 条 ----------
-- 修正：存在判断同时匹配 schemaname + tablename + policyname
do $$ begin

  -- profiles
  if not exists (select 1 from pg_policies where schemaname = 'public'
                 and tablename = 'profiles' and policyname = 'profiles_select_all') then
    create policy profiles_select_all on public.profiles
      for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public'
                 and tablename = 'profiles' and policyname = 'profiles_insert_own') then
    create policy profiles_insert_own on public.profiles
      for insert to authenticated
      with check (id = auth.uid() and role in ('buyer', 'supplier'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public'
                 and tablename = 'profiles' and policyname = 'profiles_update_own') then
    create policy profiles_update_own on public.profiles
      for update to authenticated
      using (id = auth.uid()) with check (id = auth.uid());
  end if;

  -- wines：仅供应商可上架
  if not exists (select 1 from pg_policies where schemaname = 'public'
                 and tablename = 'wines' and policyname = 'wines_select_browse') then
    create policy wines_select_browse on public.wines
      for select to public using (status = 'on_sale' or auth.uid() = supplier_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public'
                 and tablename = 'wines' and policyname = 'wines_insert_own') then
    create policy wines_insert_own on public.wines
      for insert to authenticated
      with check (
        supplier_id = auth.uid()
        and exists (select 1 from public.profiles p
                    where p.id = auth.uid() and p.role = 'supplier')
      );
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public'
                 and tablename = 'wines' and policyname = 'wines_update_own') then
    create policy wines_update_own on public.wines
      for update to authenticated
      using (supplier_id = auth.uid()) with check (supplier_id = auth.uid());
  end if;

  -- inquiries：发起时必须是 pending 且无回复
  if not exists (select 1 from pg_policies where schemaname = 'public'
                 and tablename = 'inquiries' and policyname = 'inquiries_select_participant') then
    create policy inquiries_select_participant on public.inquiries
      for select to authenticated
      using (
        buyer_id = auth.uid()
        or exists (
          select 1 from public.wines w
          where w.id = inquiries.wine_id and w.supplier_id = auth.uid()
        )
      );
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public'
                 and tablename = 'inquiries' and policyname = 'inquiries_insert_buyer') then
    create policy inquiries_insert_buyer on public.inquiries
      for insert to authenticated
      with check (buyer_id = auth.uid() and status = 'pending' and reply is null);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public'
                 and tablename = 'inquiries' and policyname = 'inquiries_update_supplier') then
    create policy inquiries_update_supplier on public.inquiries
      for update to authenticated
      using (
        exists (
          select 1 from public.wines w
          where w.id = inquiries.wine_id and w.supplier_id = auth.uid()
        )
      )
      with check (status in ('pending', 'replied'));
  end if;

  -- orders
  if not exists (select 1 from pg_policies where schemaname = 'public'
                 and tablename = 'orders' and policyname = 'orders_select_participant') then
    create policy orders_select_participant on public.orders
      for select to authenticated
      using (buyer_id = auth.uid() or supplier_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public'
                 and tablename = 'orders' and policyname = 'orders_insert_buyer') then
    create policy orders_insert_buyer on public.orders
      for insert to authenticated with check (buyer_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public'
                 and tablename = 'orders' and policyname = 'orders_update_participant') then
    create policy orders_update_participant on public.orders
      for update to authenticated
      using (buyer_id = auth.uid() or supplier_id = auth.uid())
      with check (buyer_id = auth.uid() or supplier_id = auth.uid());
  end if;

  -- messages：新消息必须是未读
  if not exists (select 1 from pg_policies where schemaname = 'public'
                 and tablename = 'messages' and policyname = 'messages_select_participant') then
    create policy messages_select_participant on public.messages
      for select to authenticated
      using (sender_id = auth.uid() or receiver_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public'
                 and tablename = 'messages' and policyname = 'messages_insert_sender') then
    create policy messages_insert_sender on public.messages
      for insert to authenticated
      with check (sender_id = auth.uid() and is_read = false);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public'
                 and tablename = 'messages' and policyname = 'messages_update_receiver') then
    create policy messages_update_receiver on public.messages
      for update to authenticated
      using (receiver_id = auth.uid())
      with check (receiver_id = auth.uid() and is_read = true);
  end if;

end $$;

-- ---------- Realtime ----------
do $$ begin
  begin
    alter publication supabase_realtime add table public.messages;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;
end $$;

-- =====================================================================
-- 自检 1：表名 / 记录数（应输出 5 行）
-- =====================================================================
select 'profiles'  as "表名", count(*) as "记录数" from public.profiles
union all
select 'wines',     count(*) from public.wines
union all
select 'inquiries', count(*) from public.inquiries
union all
select 'orders',    count(*) from public.orders
union all
select 'messages',  count(*) from public.messages
order by 1;

-- =====================================================================
-- 自检 2：表 / 策略 / 适用操作（应输出 15 行，每表 3 条）
-- =====================================================================
select tablename as "表", policyname as "策略", cmd as "适用操作"
from pg_policies
where schemaname = 'public'
order by 1, 2;

-- =====================================================================
-- 自检 3：汇总（应输出 业务表数=5 / 策略数=15 / 触发器数=8）
-- =====================================================================
select
  (select count(*) from information_schema.tables
    where table_schema = 'public' and table_type = 'BASE TABLE'
      and table_name in ('profiles','wines','inquiries','orders','messages')) as "业务表数",
  (select count(*) from pg_policies where schemaname = 'public') as "策略数",
  (select count(*) from pg_trigger
    where not tgisinternal
      and tgname in ('on_auth_user_created','orders_derive_from_wine_t',
                     'check_order_transition_t','orders_set_updated_at_t',
                     'profiles_protect_t','orders_protect_t',
                     'inquiries_protect_t','messages_protect_t')) as "触发器数";