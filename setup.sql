-- Pouch: shared topics with lists, a link + password per topic.
-- Paste this whole file into Supabase -> SQL Editor -> New query, then press Run.
-- Safe to run again later: it only creates what's missing and replaces the functions.
--
-- Naming in the database:
--   lists     = Topics (shared, with link + password, people, categories, memory)
--   sublists  = Lists inside a topic (e.g. one per shopping trip)
--   items     = things on a list

create extension if not exists pgcrypto with schema extensions;

-- ---------- Tables ----------
create table if not exists public.lists (
  id         text primary key,
  name       text not null check (char_length(name) between 1 and 60),
  pass_hash  text not null,
  done_mode  text not null default 'hide' check (done_mode in ('hide', 'delete')),
  created_at timestamptz not null default now()
);
alter table public.lists add column if not exists sort_mode text not null default 'cat'
  check (sort_mode in ('cat', 'alpha', 'person', 'time'));

create table if not exists public.sublists (
  id          uuid primary key default gen_random_uuid(),
  list_id     text not null references public.lists(id) on delete cascade,   -- the topic
  name        text not null check (char_length(name) between 1 and 40),
  created_at  timestamptz not null default now(),
  archived_at timestamptz                                                    -- set when nothing is left
);
create index if not exists sublists_topic_idx on public.sublists(list_id, created_at desc);

create table if not exists public.items (
  id         uuid primary key default gen_random_uuid(),
  list_id    text not null references public.lists(id) on delete cascade,   -- the topic
  text       text not null check (char_length(text) between 1 and 120),
  done       boolean not null default false,
  created_at timestamptz not null default now(),
  done_at    timestamptz
);
-- (columns added over time; also brings older databases up to date)
alter table public.items add column if not exists qty text not null default '1' check (char_length(qty) between 1 and 20);
alter table public.items add column if not exists added_by text;
alter table public.items add column if not exists done_by text;
alter table public.items add column if not exists cats uuid[] not null default '{}';
alter table public.items add column if not exists sublist_id uuid references public.sublists(id) on delete cascade;
create index if not exists items_list_idx on public.items(list_id);
create index if not exists items_sublist_idx on public.items(sublist_id);

-- What has been typed into each topic before (suggestions, remembered categories)
create table if not exists public.memory (
  list_id   text not null references public.lists(id) on delete cascade,
  key       text not null,
  label     text not null,
  uses      int  not null default 1,
  last_used timestamptz not null default now(),
  primary key (list_id, key)
);
alter table public.memory add column if not exists cats uuid[] not null default '{}';

-- Who has opened each topic (a name per device, no accounts)
create table if not exists public.members (
  list_id   text not null references public.lists(id) on delete cascade,
  device_id text not null check (char_length(device_id) between 8 and 64),
  name      text not null check (char_length(name) between 1 and 40),
  joined_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  primary key (list_id, device_id)
);

-- Each topic's categories (tags); pos is their order and the order of items on a list
create table if not exists public.categories (
  id         uuid primary key default gen_random_uuid(),
  list_id    text not null references public.lists(id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 30),
  key        text,                       -- starter category it came from (used for automatic tagging)
  pos        int  not null default 0,
  created_at timestamptz not null default now()
);
create unique index if not exists categories_name_idx on public.categories (list_id, lower(name));

-- Lock the tables. With row level security on and no policies, the public key
-- cannot read or write them directly. Everything goes through the functions below,
-- which check the topic's password first.
alter table public.lists      enable row level security;
alter table public.sublists   enable row level security;
alter table public.items      enable row level security;
alter table public.memory     enable row level security;
alter table public.members    enable row level security;
alter table public.categories enable row level security;

-- Helpers live in a private schema the public API can't reach.
create schema if not exists pouch_private;

-- ---------- Helpers ----------
-- ---------- Password check ----------
create or replace function pouch_private.check_pass(p_list text, p_pass text)
returns public.lists
language plpgsql security definer set search_path = public, extensions as $$
declare l public.lists;
begin
  select * into l from public.lists where id = p_list;
  if l.id is null or l.pass_hash <> crypt(coalesce(p_pass, ''), l.pass_hash) then
    raise exception 'wrong_password';
  end if;
  return l;
end $$;

-- Keep only ids that belong to this list, in category order
create or replace function pouch_private.valid_cats(p_list text, p_cats uuid[])
returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(c.id order by c.pos, c.created_at), '{}')
  from public.categories c
  where c.list_id = p_list and c.id = any(coalesce(p_cats, '{}'::uuid[]))
$$;

-- Archive a list when nothing is left on it; bring it back when something is.
create or replace function pouch_private.sync_archive(p_sub uuid, p_crossed boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare open_n int; done_n int;
begin
  if p_sub is null then return; end if;
  select count(*) filter (where not done), count(*) filter (where done)
    into open_n, done_n from public.items where sublist_id = p_sub;
  if open_n > 0 then
    update public.sublists set archived_at = null where id = p_sub and archived_at is not null;
  elsif done_n > 0 or p_crossed then
    update public.sublists set archived_at = coalesce(archived_at, now()) where id = p_sub;
  end if;
end $$;

-- The list a page gets when it doesn't say (older app versions): the newest one, made if needed
create or replace function pouch_private.default_sub(p_list text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare s uuid;
begin
  select id into s from public.sublists where list_id = p_list
   order by (archived_at is null) desc, created_at desc limit 1;
  if s is null then
    insert into public.sublists (list_id, name) values (p_list, to_char(now() at time zone 'Europe/Oslo', 'DD.MM.YYYY'))
    returning id into s;
  end if;
  return s;
end $$;

-- One item as the page sees it
create or replace function pouch_private.item_json(i public.items)
returns json
language sql stable as $$
  select json_build_object(
    'id', i.id, 'list', i.sublist_id, 'text', i.text, 'qty', i.qty, 'done', i.done, 'cats', i.cats,
    'created_at', i.created_at, 'done_at', i.done_at, 'added_by', i.added_by, 'done_by', i.done_by)
$$;

-- Everything the page needs for a topic. Items of archived lists are only included for a few days;
-- older ones are loaded when you open that list from History.
create or replace function pouch_private.snapshot(p_list text)
returns json
language sql security definer set search_path = public as $$
  select json_build_object(
    'id', l.id,
    'name', l.name,
    'done_mode', l.done_mode,
    'sort_mode', l.sort_mode,
    'created_at', l.created_at,
    'lists', coalesce((
      select json_agg(json_build_object(
        'id', s.id, 'name', s.name, 'created_at', s.created_at, 'archived_at', s.archived_at,
        'open', (select count(*) from public.items i where i.sublist_id = s.id and not i.done),
        'total', (select count(*) from public.items i where i.sublist_id = s.id))
        order by s.created_at desc)
      from (select * from public.sublists where list_id = l.id order by created_at desc limit 200) s), '[]'::json),
    'categories', coalesce((
      select json_agg(json_build_object('id', c.id, 'name', c.name, 'key', c.key, 'pos', c.pos)
        order by c.pos, c.created_at)
      from public.categories c where c.list_id = l.id), '[]'::json),
    'items', coalesce((
      select json_agg(pouch_private.item_json(i) order by i.created_at)
      from public.items i
      left join public.sublists s on s.id = i.sublist_id
      where i.list_id = l.id
        and (s.id is null or s.archived_at is null or s.archived_at > now() - interval '3 days')), '[]'::json),
    'memory', coalesce((
      select json_agg(json_build_object('key', m.key, 'label', m.label, 'uses', m.uses, 'cats', m.cats)
        order by m.uses desc, m.last_used desc)
      from (select * from public.memory where list_id = l.id
            order by uses desc, last_used desc limit 500) m), '[]'::json),
    'members', coalesce((
      select json_agg(json_build_object('device', p.device_id, 'name', p.name,
        'joined_at', p.joined_at, 'last_seen', p.last_seen) order by p.joined_at)
      from public.members p where p.list_id = l.id), '[]'::json)
  ) from public.lists l where l.id = p_list
$$;

-- Adds one item to a list in the topic (the newest list if none is given).
-- Tags: what the topic remembers for the word wins; otherwise the page's guess.
create or replace function pouch_private.add_one(p_list text, p_text text, p_qty text, p_device text, p_cats uuid[], p_sub uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare t text := left(regexp_replace(trim(coalesce(p_text, '')), '\s+', ' ', 'g'), 120);
        k text := lower(t);
        q text := nullif(left(trim(coalesce(p_qty, '')), 20), '');
        d text := nullif(left(coalesce(p_device, ''), 64), '');
        sub uuid;
        remembered uuid[];
        c uuid[];
        existing public.items;
begin
  if t = '' then return; end if;
  select id into sub from public.sublists where id = p_sub and list_id = p_list;
  if sub is null then sub := pouch_private.default_sub(p_list); end if;

  insert into public.memory (list_id, key, label) values (p_list, k, t)
  on conflict (list_id, key) do update
    set uses = public.memory.uses + 1, last_used = now()
  returning cats into remembered;
  c := pouch_private.valid_cats(p_list, remembered);
  if cardinality(c) = 0 then c := pouch_private.valid_cats(p_list, p_cats); end if;

  -- Already on this list and not crossed off? Just update its amount.
  select * into existing from public.items
   where sublist_id = sub and lower(text) = k and not done limit 1;
  if existing.id is not null then
    update public.items
       set qty = coalesce(q, existing.qty),
           cats = case when cardinality(existing.cats) = 0 then c else existing.cats end
     where id = existing.id;
  else
    -- clock_timestamp keeps the typed order when several items are added at once
    insert into public.items (list_id, sublist_id, text, qty, added_by, cats, created_at)
    values (p_list, sub, t, coalesce(q, '1'), d, c, clock_timestamp());
  end if;
  perform pouch_private.sync_archive(sub, false);
end $$;

create or replace function pouch_private.add_one(p_list text, p_text text, p_qty text, p_device text, p_cats uuid[])
returns void
language sql security definer set search_path = public as $$
  select pouch_private.add_one(p_list, p_text, p_qty, p_device, p_cats, null)
$$;

-- ---------- Public functions ----------
-- ---------- Public functions ----------
create or replace function public.pouch_create(p_name text, p_pass text)
returns text
language plpgsql security definer set search_path = public, extensions as $$
declare new_id text;
begin
  if char_length(coalesce(p_pass, '')) < 4 then raise exception 'password_too_short'; end if;
  new_id := translate(encode(gen_random_bytes(12), 'base64'), '+/=', '-_');
  insert into public.lists (id, name, pass_hash)
  values (new_id, left(trim(p_name), 60), crypt(p_pass, gen_salt('bf', 8)));
  return new_id;
end $$;

create or replace function public.pouch_open(p_list text, p_pass text)
returns json
language plpgsql security definer set search_path = public as $$
begin
  perform pouch_private.check_pass(p_list, p_pass);
  return pouch_private.snapshot(p_list);
end $$;

create or replace function public.pouch_join(p_list text, p_pass text, p_device text, p_name text)
returns json
language plpgsql security definer set search_path = public as $$
declare n text := left(regexp_replace(trim(coalesce(p_name, '')), '\s+', ' ', 'g'), 40);
begin
  perform pouch_private.check_pass(p_list, p_pass);
  if n = '' then raise exception 'empty_name'; end if;
  insert into public.members (list_id, device_id, name) values (p_list, p_device, n)
  on conflict (list_id, device_id) do update set name = excluded.name, last_seen = now();
  return pouch_private.snapshot(p_list);
end $$;

create or replace function public.pouch_rename(p_list text, p_pass text, p_name text)
returns json
language plpgsql security definer set search_path = public as $$
declare n text := left(trim(coalesce(p_name, '')), 60);
begin
  perform pouch_private.check_pass(p_list, p_pass);
  if n = '' then raise exception 'empty_name'; end if;
  update public.lists set name = n where id = p_list;
  return pouch_private.snapshot(p_list);
end $$;

create or replace function public.pouch_set_password(p_list text, p_pass text, p_new text)
returns json
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform pouch_private.check_pass(p_list, p_pass);
  if char_length(coalesce(p_new, '')) < 4 then raise exception 'password_too_short'; end if;
  update public.lists set pass_hash = crypt(p_new, gen_salt('bf', 8)) where id = p_list;
  return pouch_private.snapshot(p_list);
end $$;

-- How the open items are sorted, shared by everyone on the list
create or replace function public.pouch_set_sort(p_list text, p_pass text, p_mode text)
returns json
language plpgsql security definer set search_path = public as $$
begin
  perform pouch_private.check_pass(p_list, p_pass);
  if p_mode not in ('cat', 'alpha', 'person', 'time') then raise exception 'bad_sort'; end if;
  update public.lists set sort_mode = p_mode where id = p_list;
  return pouch_private.snapshot(p_list);
end $$;

create or replace function public.pouch_set_mode(p_list text, p_pass text, p_mode text)
returns json
language plpgsql security definer set search_path = public as $$
begin
  perform pouch_private.check_pass(p_list, p_pass);
  update public.lists set done_mode = p_mode where id = p_list;
  if p_mode = 'delete' then
    delete from public.items where list_id = p_list and done;
  end if;
  return pouch_private.snapshot(p_list);
end $$;

-- Deletes the whole list, its items, suggestions and people
create or replace function public.pouch_delete_list(p_list text, p_pass text)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  perform pouch_private.check_pass(p_list, p_pass);
  delete from public.lists where id = p_list;
  return true;
end $$;

-- New list in the topic. With p_move_from, the unbought items of that list move over.
-- Returns the topic plus "new_list": the new list's id.
create or replace function public.pouch_sub_create(p_list text, p_pass text, p_name text, p_move_from uuid)
returns json
language plpgsql security definer set search_path = public as $$
declare n text := left(regexp_replace(trim(coalesce(p_name, '')), '\s+', ' ', 'g'), 40);
        sub uuid; src uuid;
begin
  perform pouch_private.check_pass(p_list, p_pass);
  if n = '' then n := to_char(now() at time zone 'Europe/Oslo', 'DD.MM.YYYY'); end if;
  insert into public.sublists (list_id, name) values (p_list, n) returning id into sub;
  select id into src from public.sublists where id = p_move_from and list_id = p_list;
  if src is not null then
    update public.items set sublist_id = sub, created_at = clock_timestamp()
     where sublist_id = src and not done;
    perform pouch_private.sync_archive(src, false);
    -- a list left with nothing at all goes to History too
    update public.sublists set archived_at = coalesce(archived_at, now())
     where id = src and not exists (select 1 from public.items where sublist_id = src);
  end if;
  return (pouch_private.snapshot(p_list)::jsonb || jsonb_build_object('new_list', sub))::json;
end $$;

create or replace function public.pouch_sub_rename(p_list text, p_pass text, p_sub uuid, p_name text)
returns json
language plpgsql security definer set search_path = public as $$
declare n text := left(regexp_replace(trim(coalesce(p_name, '')), '\s+', ' ', 'g'), 40);
begin
  perform pouch_private.check_pass(p_list, p_pass);
  if n = '' then raise exception 'empty_name'; end if;
  update public.sublists set name = n where id = p_sub and list_id = p_list;
  return pouch_private.snapshot(p_list);
end $$;

-- Items of one list (used for older lists in History)
create or replace function public.pouch_sub_items(p_list text, p_pass text, p_sub uuid)
returns json
language plpgsql security definer set search_path = public as $$
begin
  perform pouch_private.check_pass(p_list, p_pass);
  return coalesce((select json_agg(pouch_private.item_json(i) order by i.created_at)
                     from public.items i where i.sublist_id = p_sub and i.list_id = p_list), '[]'::json);
end $$;

-- Deletes one list in a topic and everything on it
create or replace function public.pouch_sub_delete(p_list text, p_pass text, p_sub uuid)
returns json
language plpgsql security definer set search_path = public as $$
begin
  perform pouch_private.check_pass(p_list, p_pass);
  delete from public.sublists where id = p_sub and list_id = p_list;
  return pouch_private.snapshot(p_list);
end $$;

create or replace function public.pouch_add(p_list text, p_pass text, p_text text, p_qty text, p_device text, p_cats uuid[], p_sub uuid)
returns json
language plpgsql security definer set search_path = public as $$
begin
  perform pouch_private.check_pass(p_list, p_pass);
  if trim(coalesce(p_text, '')) = '' then raise exception 'empty_item'; end if;
  perform pouch_private.add_one(p_list, p_text, p_qty, p_device, p_cats, p_sub);
  return pouch_private.snapshot(p_list);
end $$;

-- p_items: [{"text": "...", "qty": "...", "cats": ["<uuid>", ...]}, ...] (max 50)
create or replace function public.pouch_add_many(p_list text, p_pass text, p_items json, p_device text, p_sub uuid)
returns json
language plpgsql security definer set search_path = public as $$
declare e json; c uuid[];
begin
  perform pouch_private.check_pass(p_list, p_pass);
  for e in select value from json_array_elements(p_items) limit 50 loop
    c := null;
    if json_typeof(e->'cats') = 'array' then
      select array_agg(x::uuid) into c
        from json_array_elements_text(e->'cats') x
       where x ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
    end if;
    perform pouch_private.add_one(p_list, e->>'text', e->>'qty', p_device, c, p_sub);
  end loop;
  return pouch_private.snapshot(p_list);
end $$;

create or replace function public.pouch_set_qty(p_list text, p_pass text, p_item uuid, p_qty text)
returns json
language plpgsql security definer set search_path = public as $$
begin
  perform pouch_private.check_pass(p_list, p_pass);
  update public.items set qty = coalesce(nullif(left(trim(coalesce(p_qty, '')), 20), ''), '1')
   where id = p_item and list_id = p_list;
  return pouch_private.snapshot(p_list);
end $$;

create or replace function public.pouch_set_done(p_list text, p_pass text, p_item uuid, p_done boolean, p_device text)
returns json
language plpgsql security definer set search_path = public as $$
declare l public.lists; sub uuid;
begin
  l := pouch_private.check_pass(p_list, p_pass);
  select sublist_id into sub from public.items where id = p_item and list_id = p_list;
  if p_done and l.done_mode = 'delete' then
    delete from public.items where id = p_item and list_id = p_list;
  else
    update public.items
       set done = p_done,
           done_at = case when p_done then now() end,
           done_by = case when p_done then nullif(left(coalesce(p_device, ''), 64), '') end
     where id = p_item and list_id = p_list;
  end if;
  perform pouch_private.sync_archive(sub, p_done);
  return pouch_private.snapshot(p_list);
end $$;

-- Removes the given items (used after the Undo window for "×" and "Clear"), then archives lists with nothing left
create or replace function public.pouch_delete_items(p_list text, p_pass text, p_ids uuid[])
returns json
language plpgsql security definer set search_path = public as $$
declare subs uuid[]; s uuid;
begin
  perform pouch_private.check_pass(p_list, p_pass);
  select array_agg(distinct sublist_id) into subs from public.items where list_id = p_list and id = any(p_ids);
  delete from public.items where list_id = p_list and id = any(p_ids);
  foreach s in array coalesce(subs, '{}') loop perform pouch_private.sync_archive(s, false); end loop;
  return pouch_private.snapshot(p_list);
end $$;

create or replace function public.pouch_forget(p_list text, p_pass text, p_key text)
returns json
language plpgsql security definer set search_path = public as $$
begin
  perform pouch_private.check_pass(p_list, p_pass);
  delete from public.memory where list_id = p_list and key = p_key;
  return pouch_private.snapshot(p_list);
end $$;

-- Set an item's tags; the list remembers them for next time.
create or replace function public.pouch_set_cats(p_list text, p_pass text, p_item uuid, p_cats uuid[])
returns json
language plpgsql security definer set search_path = public as $$
declare c uuid[]; k text;
begin
  perform pouch_private.check_pass(p_list, p_pass);
  c := pouch_private.valid_cats(p_list, p_cats);
  update public.items set cats = c where id = p_item and list_id = p_list returning lower(text) into k;
  if k is not null then
    update public.memory set cats = c where list_id = p_list and key = k;
  end if;
  return pouch_private.snapshot(p_list);
end $$;

-- New category (at the end). With p_item, also tags that item with it.
create or replace function public.pouch_cat_add(p_list text, p_pass text, p_name text, p_item uuid)
returns json
language plpgsql security definer set search_path = public as $$
declare n text := left(regexp_replace(trim(coalesce(p_name, '')), '\s+', ' ', 'g'), 30);
        cid uuid; cur uuid[];
begin
  perform pouch_private.check_pass(p_list, p_pass);
  if n = '' then raise exception 'empty_name'; end if;
  select id into cid from public.categories where list_id = p_list and lower(name) = lower(n);
  if cid is null then
    insert into public.categories (list_id, name, pos)
    values (p_list, n, coalesce((select max(pos) + 1 from public.categories where list_id = p_list), 0))
    returning id into cid;
  end if;
  if p_item is not null then
    select cats into cur from public.items where id = p_item and list_id = p_list;
    if cur is not null and not (cid = any(cur)) then
      perform public.pouch_set_cats(p_list, p_pass, p_item, cur || cid);
    end if;
  end if;
  return pouch_private.snapshot(p_list);
end $$;

create or replace function public.pouch_cat_rename(p_list text, p_pass text, p_cat uuid, p_name text)
returns json
language plpgsql security definer set search_path = public as $$
declare n text := left(regexp_replace(trim(coalesce(p_name, '')), '\s+', ' ', 'g'), 30);
begin
  perform pouch_private.check_pass(p_list, p_pass);
  if n = '' then raise exception 'empty_name'; end if;
  begin
    update public.categories set name = n where id = p_cat and list_id = p_list;
  exception when unique_violation then raise exception 'name_taken';
  end;
  return pouch_private.snapshot(p_list);
end $$;

-- New order: p_cats lists the category ids first to last.
create or replace function public.pouch_cat_order(p_list text, p_pass text, p_cats uuid[])
returns json
language plpgsql security definer set search_path = public as $$
begin
  perform pouch_private.check_pass(p_list, p_pass);
  update public.categories c set pos = array_position(p_cats, c.id) - 1
   where c.list_id = p_list and c.id = any(p_cats);
  return pouch_private.snapshot(p_list);
end $$;

-- Starter categories: p_cats is [{"key": "dairy", "name": "Meieri og egg"}, ...] in order.
-- Names the list already has are skipped; new ones go after the existing ones.
create or replace function public.pouch_cat_init(p_list text, p_pass text, p_cats json)
returns json
language plpgsql security definer set search_path = public as $$
declare base int;
begin
  perform pouch_private.check_pass(p_list, p_pass);
  base := coalesce((select max(pos) + 1 from public.categories where list_id = p_list), 0);
  insert into public.categories (list_id, name, key, pos)
  select p_list, left(trim(e.value->>'name'), 30), nullif(left(e.value->>'key', 30), ''), base + e.ord::int - 1
    from json_array_elements(p_cats) with ordinality as e(value, ord)
   where trim(coalesce(e.value->>'name', '')) <> ''
   limit 60
  on conflict (list_id, lower(name)) do nothing;
  return pouch_private.snapshot(p_list);
end $$;

-- Copy categories and learned tags from another list (needs both passwords).
create or replace function public.pouch_cat_copy(p_list text, p_pass text, p_src text, p_src_pass text)
returns json
language plpgsql security definer set search_path = public as $$
declare base int;
begin
  perform pouch_private.check_pass(p_list, p_pass);
  perform pouch_private.check_pass(p_src, p_src_pass);
  base := coalesce((select max(pos) + 1 from public.categories where list_id = p_list), 0);
  insert into public.categories (list_id, name, key, pos)
  select p_list, s.name, s.key, base + s.pos
    from public.categories s where s.list_id = p_src
  on conflict (list_id, lower(name)) do nothing;

  -- learned words, with their tags mapped to this list's categories by name
  insert into public.memory (list_id, key, label, uses, cats)
  select p_list, m.key, m.label, 0,
         coalesce((select array_agg(t.id order by t.pos)
                     from unnest(m.cats) sc
                     join public.categories s on s.id = sc
                     join public.categories t on t.list_id = p_list and lower(t.name) = lower(s.name)), '{}')
    from public.memory m
   where m.list_id = p_src and cardinality(m.cats) > 0
  on conflict (list_id, key) do update
    set cats = case when cardinality(public.memory.cats) = 0 then excluded.cats else public.memory.cats end;
  return pouch_private.snapshot(p_list);
end $$;

-- Remove a category from the list, and from every item and remembered word that had it
create or replace function public.pouch_cat_delete(p_list text, p_pass text, p_cat uuid)
returns json
language plpgsql security definer set search_path = public as $$
begin
  perform pouch_private.check_pass(p_list, p_pass);
  update public.items  set cats = array_remove(cats, p_cat) where list_id = p_list and p_cat = any(cats);
  update public.memory set cats = array_remove(cats, p_cat) where list_id = p_list and p_cat = any(cats);
  delete from public.categories where id = p_cat and list_id = p_list;
  return pouch_private.snapshot(p_list);
end $$;

-- Used by the scheduled GitHub job so the free project never pauses
create or replace function public.pouch_ping()
returns boolean
language sql security definer set search_path = public as $$
  select exists (select 1 from public.lists limit 1) or true
$$;

-- Rename an item (fix a typo). The topic also remembers the new word for suggestions.
create or replace function public.pouch_set_text(p_list text, p_pass text, p_item uuid, p_text text)
returns json
language plpgsql security definer set search_path = public as $$
declare t text := left(regexp_replace(trim(coalesce(p_text, '')), '\s+', ' ', 'g'), 120);
        c uuid[]; old text;
begin
  perform pouch_private.check_pass(p_list, p_pass);
  if t = '' then raise exception 'empty_item'; end if;
  select text into old from public.items where id = p_item and list_id = p_list;
  update public.items set text = t where id = p_item and list_id = p_list returning cats into c;
  -- the misspelled word stops being suggested (it is kept, just not counted)
  if old is not null and lower(old) <> lower(t) then
    update public.memory set uses = greatest(uses - 1, 0) where list_id = p_list and key = lower(old);
  end if;
  insert into public.memory (list_id, key, label, cats) values (p_list, lower(t), t, coalesce(c, '{}'))
  on conflict (list_id, key) do nothing;
  return pouch_private.snapshot(p_list);
end $$;

-- Put every item of one list (e.g. a finished one in History) onto another list, with amounts and categories
create or replace function public.pouch_sub_copy(p_list text, p_pass text, p_from uuid, p_to uuid, p_device text)
returns json
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  perform pouch_private.check_pass(p_list, p_pass);
  if not exists (select 1 from public.sublists where id = p_to and list_id = p_list) then raise exception 'no_such_list'; end if;
  for r in select text, qty, cats from public.items where sublist_id = p_from and list_id = p_list order by created_at loop
    perform pouch_private.add_one(p_list, r.text, nullif(r.qty, '1'), p_device, r.cats, p_to);
  end loop;
  return pouch_private.snapshot(p_list);
end $$;

-- ---------- Older versions of functions, kept so older copies of the page keep working ----------
create or replace function public.pouch_add(p_list text, p_pass text, p_text text, p_qty text, p_device text, p_cats uuid[])
returns json
language sql security definer set search_path = public as $$
  select public.pouch_add(p_list, p_pass, p_text, p_qty, p_device, p_cats, null)
$$;

create or replace function public.pouch_add(p_list text, p_pass text, p_text text, p_qty text, p_device text)
returns json
language sql security definer set search_path = public as $$
  select public.pouch_add(p_list, p_pass, p_text, p_qty, p_device, null)
$$;

-- Older versions, kept so older copies of the page keep working
create or replace function public.pouch_add(p_list text, p_pass text, p_text text, p_qty text)
returns json
language sql security definer set search_path = public as $$
  select public.pouch_add(p_list, p_pass, p_text, p_qty, null)
$$;

create or replace function public.pouch_add(p_list text, p_pass text, p_text text)
returns json
language sql security definer set search_path = public as $$
  select public.pouch_add(p_list, p_pass, p_text, null, null)
$$;

create or replace function public.pouch_add_many(p_list text, p_pass text, p_items json, p_device text)
returns json
language sql security definer set search_path = public as $$
  select public.pouch_add_many(p_list, p_pass, p_items, p_device, null)
$$;

-- Older version, kept so older copies of the page keep working
create or replace function public.pouch_set_done(p_list text, p_pass text, p_item uuid, p_done boolean)
returns json
language sql security definer set search_path = public as $$
  select public.pouch_set_done(p_list, p_pass, p_item, p_done, null)
$$;

create or replace function public.pouch_delete_item(p_list text, p_pass text, p_item uuid)
returns json
language plpgsql security definer set search_path = public as $$
begin
  perform pouch_private.check_pass(p_list, p_pass);
  delete from public.items where id = p_item and list_id = p_list;
  return pouch_private.snapshot(p_list);
end $$;

create or replace function public.pouch_clear_done(p_list text, p_pass text)
returns json
language plpgsql security definer set search_path = public as $$
begin
  perform pouch_private.check_pass(p_list, p_pass);
  delete from public.items where list_id = p_list and done;
  return pouch_private.snapshot(p_list);
end $$;

-- ---------- Bring older data up to date ----------
-- Topics from before lists existed: put their items into one list, named after the day the topic was made
insert into public.sublists (list_id, name, created_at)
select l.id, to_char(l.created_at at time zone 'Europe/Oslo', 'DD.MM.YYYY'), l.created_at
  from public.lists l
 where exists (select 1 from public.items i where i.list_id = l.id and i.sublist_id is null)
   and not exists (select 1 from public.sublists s where s.list_id = l.id);
update public.items i set sublist_id = (select s.id from public.sublists s where s.list_id = i.list_id order by s.created_at desc limit 1)
 where i.sublist_id is null;
update public.sublists s set archived_at = now()
 where archived_at is null
   and exists (select 1 from public.items i where i.sublist_id = s.id)
   and not exists (select 1 from public.items i where i.sublist_id = s.id and not i.done);

-- ---------- Who may call what ----------
-- Only the public functions; the private helpers can't be reached with the public key.
grant execute on function
  public.pouch_create(text,text),
  public.pouch_open(text,text),
  public.pouch_join(text,text,text,text),
  public.pouch_rename(text,text,text),
  public.pouch_set_password(text,text,text),
  public.pouch_set_sort(text,text,text),
  public.pouch_set_mode(text,text,text),
  public.pouch_delete_list(text,text),
  public.pouch_sub_create(text,text,text,uuid),
  public.pouch_sub_rename(text,text,uuid,text),
  public.pouch_sub_items(text,text,uuid),
  public.pouch_sub_delete(text,text,uuid),
  public.pouch_add(text,text,text,text,text,uuid[],uuid),
  public.pouch_add_many(text,text,json,text,uuid),
  public.pouch_set_qty(text,text,uuid,text),
  public.pouch_set_done(text,text,uuid,boolean,text),
  public.pouch_delete_items(text,text,uuid[]),
  public.pouch_forget(text,text,text),
  public.pouch_set_cats(text,text,uuid,uuid[]),
  public.pouch_cat_add(text,text,text,uuid),
  public.pouch_cat_rename(text,text,uuid,text),
  public.pouch_cat_order(text,text,uuid[]),
  public.pouch_cat_init(text,text,json),
  public.pouch_cat_copy(text,text,text,text),
  public.pouch_cat_delete(text,text,uuid),
  public.pouch_ping(),
  public.pouch_set_text(text, text, uuid, text),
  public.pouch_sub_copy(text, text, uuid, uuid, text),
  public.pouch_add(text,text,text,text,text,uuid[]),
  public.pouch_add(text,text,text,text,text),
  public.pouch_add(text,text,text,text),
  public.pouch_add(text,text,text),
  public.pouch_add_many(text,text,json,text),
  public.pouch_set_done(text,text,uuid,boolean),
  public.pouch_delete_item(text,text,uuid),
  public.pouch_clear_done(text,text)
to anon, authenticated;
