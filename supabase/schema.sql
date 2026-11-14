-- Zemmita duomenų bazė (Supabase / Postgres).
-- Paleiskite Supabase „SQL Editor“ lange. Scenarijų galima leisti kelis kartus.
-- Prieš paleisdami sukurkite savo vartotoją (Authentication > Users), nes
-- anksčiausiai sukurtas vartotojas tampa administratoriumi.

-- 1. Lentelės -----------------------------------------------------------------

create table if not exists public.admins (
  user_id uuid primary key references auth.users (id) on delete cascade
);

create table if not exists public.submissions (
  id              uuid primary key default gen_random_uuid(),
  token           uuid not null default gen_random_uuid(),
  status          text not null default 'pending'
                    check (status in ('pending', 'approved', 'rejected', 'removed')),
  reason          text not null default '' check (char_length(reason) <= 300),
  created_at      timestamptz not null default now(),
  reviewed_at     timestamptz,

  seller_name     text not null check (char_length(btrim(seller_name)) between 1 and 80),
  phone           text not null check (phone ~ '^\+?[0-9 ()-]{8,24}$'),
  email           text not null default '' check (char_length(email) <= 120),
  seller_status   text not null
                    check (seller_status in ('perteklius', 'sodininkas', 'ukininkas', 'registruotas')),
  vmvt_no         text not null default '' check (char_length(vmvt_no) <= 40),

  title           text not null check (char_length(btrim(title)) between 1 and 70),
  category        text not null
                    check (category in ('darzoves', 'vaisiai', 'uogos', 'zalumynai', 'bulves', 'medus', 'kiausiniai')),
  description     text not null check (char_length(btrim(description)) between 10 and 600),
  variety         text not null default '' check (char_length(variety) <= 60),
  origin          text not null default 'Lietuva' check (char_length(btrim(origin)) between 1 and 40),
  bees_registered boolean not null default false,

  qty             numeric(10, 2) not null check (qty > 0),
  unit            text not null
                    check (unit in ('kg', 'vnt.', 'ryšulėlis', 'dėžutė', 'maišas', 'stiklainis', 'l', '10 vnt.')),
  price           numeric(10, 2) not null check (price > 0 and price <= 10000),
  negotiable      boolean not null default false,

  available_from  date not null,
  available_to    date,
  city            text not null check (char_length(btrim(city)) between 1 and 50),
  area            text not null check (char_length(btrim(area)) between 1 and 50),
  pickup          boolean not null default true,
  delivery        boolean not null default false,
  delivery_note   text not null default '' check (char_length(delivery_note) <= 100),

  confirm_own     boolean not null,
  confirm_resp    boolean not null,
  confirm_show    boolean not null,

  photo           text check (photo is null or (char_length(photo) < 220000
                    and photo ~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$')),
  has_photo       boolean generated always as (photo is not null) stored,

  constraint submissions_confirmations check (confirm_own and confirm_resp and confirm_show),
  constraint submissions_handover check (pickup or delivery),
  constraint submissions_eggs_need_number check (category <> 'kiausiniai' or btrim(vmvt_no) <> ''),
  constraint submissions_dates check (available_to is null or available_to >= available_from)
);

create unique index if not exists submissions_token_idx on public.submissions (token);
create index if not exists submissions_status_idx on public.submissions (status, created_at);

alter table public.admins enable row level security;
alter table public.submissions enable row level security;

-- 2. Funkcijos ----------------------------------------------------------------

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.admins a where a.user_id = (select auth.uid()));
$$;

-- Kiekvienas naujas skelbimas visada pradeda nuo „laukia patikros“,
-- kad ir ką atsiųstų naršyklė. Kartu ribojamas pateikimų srautas.
create or replace function public.submissions_before_insert()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  recent  integer;
  waiting integer;
begin
  new.status := 'pending';
  new.reason := '';
  new.reviewed_at := null;
  new.created_at := now();
  select count(*) into recent from public.submissions s where s.created_at > now() - interval '1 hour';
  select count(*) into waiting from public.submissions s where s.status = 'pending';
  if recent >= 40 or waiting >= 300 then
    raise exception 'too_many_submissions' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists submissions_before_insert on public.submissions;
create trigger submissions_before_insert
  before insert on public.submissions
  for each row execute function public.submissions_before_insert();

-- Pardavėjas savo skelbimus mato pagal slaptą raktą, saugomą jo įrenginyje.
create or replace function public.my_listings(p_tokens uuid[])
returns table (id uuid, title text, category text, qty numeric, unit text, price numeric,
               city text, area text, status text, reason text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select s.id, s.title, s.category, s.qty, s.unit, s.price, s.city, s.area, s.status, s.reason, s.created_at
  from public.submissions s
  where coalesce(array_length(p_tokens, 1), 0) between 1 and 50
    and s.token = any (p_tokens)
  order by s.created_at desc;
$$;

create or replace function public.withdraw_listing(p_id uuid, p_token uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  cur text;
begin
  select s.status into cur from public.submissions s where s.id = p_id and s.token = p_token;
  if cur is null then
    return 'not_found';
  end if;
  if cur = 'approved' then
    update public.submissions s
       set status = 'removed', reason = 'Nuimta pardavėjo prašymu.', reviewed_at = now()
     where s.id = p_id and s.token = p_token;
    return 'removed';
  end if;
  delete from public.submissions s where s.id = p_id and s.token = p_token;
  return 'deleted';
end;
$$;

-- 3. Vieši rodiniai: tik patvirtinti, galiojantys skelbimai ir tik vieši laukai ---

create or replace view public.listings with (security_invoker = false) as
  select s.id, s.title, s.category, s.description, s.variety, s.origin, s.qty, s.unit, s.price,
         s.negotiable, s.available_from, s.available_to, s.city, s.area, s.pickup, s.delivery,
         s.delivery_note, s.seller_name, s.phone, s.vmvt_no, s.has_photo, s.reviewed_at as approved_at
  from public.submissions s
  where s.status = 'approved' and (s.available_to is null or s.available_to >= current_date);

create or replace view public.listing_photos with (security_invoker = false) as
  select s.id, s.photo
  from public.submissions s
  where s.status = 'approved' and s.photo is not null
    and (s.available_to is null or s.available_to >= current_date);

-- 4. Prieigos taisyklės --------------------------------------------------------

drop policy if exists "anyone can submit" on public.submissions;
create policy "anyone can submit" on public.submissions
  for insert to anon, authenticated with check (true);

drop policy if exists "admins read submissions" on public.submissions;
create policy "admins read submissions" on public.submissions
  for select to authenticated using ((select public.is_admin()));

drop policy if exists "admins review submissions" on public.submissions;
create policy "admins review submissions" on public.submissions
  for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists "admins delete submissions" on public.submissions;
create policy "admins delete submissions" on public.submissions
  for delete to authenticated using ((select public.is_admin()));

drop policy if exists "see own admin row" on public.admins;
create policy "see own admin row" on public.admins
  for select to authenticated using (user_id = (select auth.uid()));

grant usage on schema public to anon, authenticated;

revoke all on public.submissions from anon, authenticated;
revoke all on public.admins from anon, authenticated;
grant insert on public.submissions to anon, authenticated;
grant select, delete on public.submissions to authenticated;
grant update (status, reason, reviewed_at) on public.submissions to authenticated;
grant select on public.admins to authenticated;
grant select on public.listings to anon, authenticated;
grant select on public.listing_photos to anon, authenticated;

revoke execute on function public.is_admin() from public;
revoke execute on function public.my_listings(uuid[]) from public;
revoke execute on function public.withdraw_listing(uuid, uuid) from public;
revoke execute on function public.submissions_before_insert() from public;
grant execute on function public.is_admin() to anon, authenticated;
grant execute on function public.my_listings(uuid[]) to anon, authenticated;
grant execute on function public.withdraw_listing(uuid, uuid) to anon, authenticated;

-- 5. Administratorius: anksčiausiai sukurtas vartotojas -------------------------

insert into public.admins (user_id)
select u.id from auth.users u
where not exists (select 1 from public.admins)
order by u.created_at asc
limit 1;

notify pgrst, 'reload schema';

select (select count(*) from public.admins) as administratoriu,
       (select count(*) from auth.users)    as vartotoju;
