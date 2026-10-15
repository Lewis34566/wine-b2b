-- =====================================================================
-- 酒链 B2B · 演示种子数据（三语版）
-- 内容：1 个演示供应商账号 + 1 个演示采购商账号 + 8 款三语示例酒款
-- 用法：Supabase 控制台 → SQL Editor → 全文粘贴 → Run（可重复执行，幂等）
-- 依赖：先执行 supabase_setup.sql（handle_new_user 触发器会自动建 profile）
-- 自检预期：演示账号数 = 2、演示酒款数 = 8
--
-- 演示账号（密码公开属演示惯例，请勿在本库放真实业务数据）：
--   供应商：demo@jiutong-wine.cn    / Demo123456
--   采购商：demo@yunxuan-trade.cn   / Demo123456
--
-- 说明：SQL Editor 以 postgres 身份执行（auth.uid() 为空），
--       触发器 protect_immutable_columns 对空 auth.uid() 放行，RLS 不拦截。
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- 1. 演示供应商（固定 UUID，幂等） ----------
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000',
  '10000000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated',
  'demo@jiutong-wine.cn', crypt('Demo123456', gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}',
  '{"role":"supplier","company_name":"烟台九彤酒业有限公司","contact_name":"王丽萍","phone":"+86 138 0535 9266"}',
  now(), now()
where not exists (select 1 from auth.users where id = '10000000-0000-4000-8000-000000000001');

-- profile 由 handle_new_user 触发器自动创建；补齐地区/简介（幂等 UPDATE）
update public.profiles
   set region = '山东·烟台',
       bio = '蓬莱产区原酒供应与 OEM 贴牌定制服务商。Penglai-based bulk wine & OEM private-label supplier.'
 where id = '10000000-0000-4000-8000-000000000001';

-- ---------- 2. 演示采购商（同上） ----------
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000',
  '10000000-0000-4000-8000-000000000002',
  'authenticated', 'authenticated',
  'demo@yunxuan-trade.cn', crypt('Demo123456', gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}',
  '{"role":"buyer","company_name":"江西云选商贸有限公司","contact_name":"李强","phone":"+86 139 7008 2331"}',
  now(), now()
where not exists (select 1 from auth.users where id = '10000000-0000-4000-8000-000000000002');

update public.profiles
   set region = '江西·南昌',
       bio = '酒类批发与商超渠道采购商。'
 where id = '10000000-0000-4000-8000-000000000002';

-- ---------- 3. 8 款三语示例酒款（全部 on_sale，游客立即可见） ----------
-- 每条的幂等守卫：同名（同供应商）不存在才插入
insert into public.wines
  (supplier_id, name, name_en, name_ru, origin, vintage, variety, wine_type,
   price, stock, description, description_en, description_ru, status)
select
  '10000000-0000-4000-8000-000000000001',
  '蓬莱赤霞珠干红葡萄酒 2019', 'Penglai Cabernet Sauvignon Dry Red 2019', 'Пэнлай Каберне Совиньон сухое красное 2019',
  '烟台·蓬莱', 2019, '赤霞珠', '红葡萄酒', 128, 360,
  '蓬莱核心产区老藤赤霞珠，18 个月法国橡木桶陈酿，黑醋栗与雪松香气。',
  'Old-vine Cabernet from the heart of Penglai, aged 18 months in French oak; cassis and cedar aromas.',
  'Каберне Совиньон со старых лоз из Пэнлая, 18 месяцев во французском дубе; ароматы чёрной смородины и кедра.',
  'on_sale'
where not exists (
  select 1 from public.wines
  where supplier_id = '10000000-0000-4000-8000-000000000001' and name = '蓬莱赤霞珠干红葡萄酒 2019');

insert into public.wines
  (supplier_id, name, name_en, name_ru, origin, vintage, variety, wine_type,
   price, stock, description, description_en, description_ru, status)
select
  '10000000-0000-4000-8000-000000000001',
  '九彤珍藏梅洛干红 2021', 'Jiutong Reserve Merlot Dry Red 2021', 'Резервное красное «Цзютун» Мерло 2021',
  '烟台', 2021, '梅洛', '红葡萄酒', 168, 240,
  '酒庄自产梅洛，柔顺单宁，红色浆果与可可气息，适合日常佐餐。',
  'Estate-grown Merlot with silky tannins, red-berry fruit and cocoa notes; a fine everyday red.',
  'Мерло с собственных виноградников, мягкие танины, ноты красных ягод и какао; отлично к столу.',
  'on_sale'
where not exists (
  select 1 from public.wines
  where supplier_id = '10000000-0000-4000-8000-000000000001' and name = '九彤珍藏梅洛干红 2021');

insert into public.wines
  (supplier_id, name, name_en, name_ru, origin, vintage, variety, wine_type,
   price, stock, description, description_en, description_ru, status)
select
  '10000000-0000-4000-8000-000000000001',
  '烟台龙口霞多丽干白 2022', 'Yantai Longkou Chardonnay Dry White 2022', 'Сухое белое Шардоне Лункоу 2022',
  '烟台·龙口', 2022, '霞多丽', '白葡萄酒', 88, 500,
  '龙口海岸产区霞多丽，清新柑橘与矿物感，酸度明亮。',
  'Chardonnay from the Longkou coast: bright citrus, a saline-mineral edge and crisp acidity.',
  'Шардоне с побережья Лункоу: яркие цитрусы, минеральность и свежая кислотность.',
  'on_sale'
where not exists (
  select 1 from public.wines
  where supplier_id = '10000000-0000-4000-8000-000000000001' and name = '烟台龙口霞多丽干白 2022');

insert into public.wines
  (supplier_id, name, name_en, name_ru, origin, vintage, variety, wine_type,
   price, stock, description, description_en, description_ru, status)
select
  '10000000-0000-4000-8000-000000000001',
  '宁夏贺兰山雷司令半甜白 2023', 'Helan Riesling Semi-Sweet White 2023', 'Полусладкое белое Рислинг Хэлань 2023',
  '宁夏', 2023, '雷司令', '白葡萄酒', 98, 300,
  '宁夏贺兰山东麓雷司令，青苹果与蜂蜜香气，微甜易饮。',
  'Riesling from the eastern Helan foothills in Ningxia; green apple and honey, gently sweet and easy-drinking.',
  'Рислинг с восточных склонов Хэланя (Нинся); зелёное яблоко и мёд, лёгкая сладость.',
  'on_sale'
where not exists (
  select 1 from public.wines
  where supplier_id = '10000000-0000-4000-8000-000000000001' and name = '宁夏贺兰山雷司令半甜白 2023');

insert into public.wines
  (supplier_id, name, name_en, name_ru, origin, vintage, variety, wine_type,
   price, stock, description, description_en, description_ru, status)
select
  '10000000-0000-4000-8000-000000000001',
  '蓬莱经典干型起泡酒 2022', 'Penglai Classic Brut Sparkling 2022', 'Классическое брют игристое Пэнлай 2022',
  '烟台·蓬莱', 2022, '混酿', '起泡酒', 138, 180,
  '传统瓶内二次发酵，细腻气泡，烤面包与白花香气。',
  'Traditional-method sparkling with a fine mousse and aromas of toasted bread and white flowers.',
  'Игристое традиционным методом, тонкий перляж, ароматы поджаренного хлеба и белых цветов.',
  'on_sale'
where not exists (
  select 1 from public.wines
  where supplier_id = '10000000-0000-4000-8000-000000000001' and name = '蓬莱经典干型起泡酒 2022');

insert into public.wines
  (supplier_id, name, name_en, name_ru, origin, vintage, variety, wine_type,
   price, stock, description, description_en, description_ru, status)
select
  '10000000-0000-4000-8000-000000000001',
  '半干桃红葡萄酒 2023', 'Semi-Dry Rosé 2023', 'Полусухое розовое 2023',
  '烟台', 2023, '混酿', '桃红葡萄酒', 68, 260,
  '草莓与树莓果香，冰镇后风味更佳。',
  'Strawberry and raspberry fruit; serve chilled.',
  'Тоны клубники и малины; подавать охлаждённым.',
  'on_sale'
where not exists (
  select 1 from public.wines
  where supplier_id = '10000000-0000-4000-8000-000000000001' and name = '半干桃红葡萄酒 2023');

insert into public.wines
  (supplier_id, name, name_en, name_ru, origin, vintage, variety, wine_type,
   price, stock, description, description_en, description_ru, status)
select
  '10000000-0000-4000-8000-000000000001',
  'OEM 定制干红（贴牌）', 'OEM Custom Dry Red (Private Label)', 'OEM красное сухое (собственная марка)',
  '烟台', null, '赤霞珠', 'OEM定制', 38, 600,
  '支持贴牌定制：起订 500 箱，酒标/瓶型/纸箱均可按客户要求定制。',
  'Private-label program: MOQ 500 cases; labels, bottle shape and cartons fully customizable.',
  'Программа OEM: от 500 коробов; этикетка, бутылка и упаковка — под заказчика.',
  'on_sale'
where not exists (
  select 1 from public.wines
  where supplier_id = '10000000-0000-4000-8000-000000000001' and name = 'OEM 定制干红（贴牌）');

insert into public.wines
  (supplier_id, name, name_en, name_ru, origin, vintage, variety, wine_type,
   price, stock, description, description_en, description_ru, status)
select
  '10000000-0000-4000-8000-000000000001',
  '蓬莱西拉干红 2020', 'Penglai Syrah Dry Red 2020', 'Сухое красное Сира Пэнлай 2020',
  '烟台·蓬莱', 2020, '西拉', '红葡萄酒', 388, 120,
  '精品西拉，紫罗兰与黑胡椒香气，单宁紧实，陈年潜力 8 年以上。',
  'Premium Syrah with violet and black-pepper aromas, firm tannins and 8+ years of ageing potential.',
  'Премиальная Сира, ароматы фиалки и чёрного перца, плотные танины, потенциал выдержки 8+ лет.',
  'on_sale'
where not exists (
  select 1 from public.wines
  where supplier_id = '10000000-0000-4000-8000-000000000001' and name = '蓬莱西拉干红 2020');

-- =====================================================================
-- 自检：应输出 演示账号数 = 2、演示酒款数 = 8
-- =====================================================================
select
  (select count(*) from public.profiles
    where id::text like '10000000-0000%') as "演示账号数",
  (select count(*) from public.wines
    where supplier_id = '10000000-0000-4000-8000-000000000001') as "演示酒款数";
