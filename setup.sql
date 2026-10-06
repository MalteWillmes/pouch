-- Pouch: shared lists with a link + password per list.
-- Paste this whole file into Supabase → SQL Editor → New query, then press Run.
-- Safe to run again later: it only creates what's missing and replaces the functions.

create extension if not exists pgcrypto with schema extensions;

-- ---------- Tables ----------
create table if not exists public.lists (
  id         text primary key,
  name       text not null check (char_length(name) between 1 and 60),
  pass_hash  text not null,
  done_mode  text not null default 'hide' check (done_mode in ('hide', 'delete')),
  created_at timestamptz not null default now()
);

create table if not exists public.items (
  id         uuid primary key default gen_random_uuid(),
  list_id    text not null references public.lists(id) on delete cascade,
  text       text not null check (char_length(text) between 1 and 120),
  qty        text not null default '1' check (char_length(qty) between 1 and 20),
  done       boolean not null default false,
  created_at timestamptz not null default now(),
  done_at    timestamptz
);
-- (for databases created before quantities existed)
alter table public.items add column if not exists qty text not null default '1' check (char_length(qty) between 1 and 20);
create index if not exists items_list_idx on public.items(list_id);

-- What has been typed into each list before (for suggestions)
create table if not exists public.memory (
  list_id   text not null references public.lists(id) on delete cascade,
  key       text not null,
  label     text not null,
  uses      int  not null default 1,
  last_used timestamptz not null default now(),
  primary key (list_id, key)
);

-- Lock the tables. With row level security on and no policies, the public key
-- cannot read or write them directly. Everything goes through the functions below,
-- which check the list's password first.
-- Who has opened each list (a name per device, no accounts)
create table if not exists public.members (
  list_id   text not null references public.lists(id) on delete cascade,
  device_id text not null check (char_length(device_id) between 8 and 64),
  name      text not null check (char_length(name) between 1 and 40),
  joined_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  primary key (list_id, device_id)
);

alter table public.members enable row level security;
alter table public.lists  enable row level security;
alter table public.items  enable row level security;
alter table public.memory enable row level security;

-- Helpers live in a private schema the public API can't reach.
create schema if not exists pouch_private;

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

-- ---------- Snapshot of a whole list ----------
create or replace function pouch_private.snapshot(p_list text)
returns json
language sql security definer set search_path = public as $$
  select json_build_object(
    'id', l.id,
    'name', l.name,
    'done_mode', l.done_mode,
    'created_at', l.created_at,
    'items', coalesce((
      select json_agg(json_build_object(
        'id', i.id, 'text', i.text, 'qty', i.qty, 'done', i.done,
        'created_at', i.created_at, 'done_at', i.done_at) order by i.created_at)
      from public.items i where i.list_id = l.id), '[]'::json),
    'memory', coalesce((
      select json_agg(json_build_object('key', m.key, 'label', m.label, 'uses', m.uses)
        order by m.uses desc, m.last_used desc)
      from (select * from public.memory where list_id = l.id
            order by uses desc, last_used desc limit 300) m), '[]'::json),
    'members', coalesce((
      select json_agg(json_build_object('device', p.device_id, 'name', p.name,
        'joined_at', p.joined_at, 'last_seen', p.last_seen) order by p.joined_at)
      from public.members p where p.list_id = l.id), '[]'::json)
  ) from public.lists l where l.id = p_list
$$;

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

create or replace function public.pouch_add(p_list text, p_pass text, p_text text, p_qty text)
returns json
language plpgsql security definer set search_path = public as $$
declare t text := left(regexp_replace(trim(p_text), '\s+', ' ', 'g'), 120);
        k text := lower(t);
        q text := nullif(left(trim(coalesce(p_qty, '')), 20), '');
        existing public.items;
begin
  perform pouch_private.check_pass(p_list, p_pass);
  if t = '' then raise exception 'empty_item'; end if;

  insert into public.memory (list_id, key, label) values (p_list, k, t)
  on conflict (list_id, key) do update
    set uses = public.memory.uses + 1, last_used = now();

  -- Already on the list and not crossed off? Just update its amount.
  -- (A crossed-off copy stays in the pile; the item is added anew.)
  select * into existing from public.items
   where list_id = p_list and lower(text) = k and not done limit 1;
  if existing.id is not null then
    update public.items set qty = coalesce(q, existing.qty) where id = existing.id;
  else
    insert into public.items (list_id, text, qty) values (p_list, t, coalesce(q, '1'));
  end if;
  return pouch_private.snapshot(p_list);
end $$;

-- Older three-argument version, kept so older copies of the page keep working
create or replace function public.pouch_add(p_list text, p_pass text, p_text text)
returns json
language sql security definer set search_path = public as $$
  select public.pouch_add(p_list, p_pass, p_text, null)
$$;

create or replace function public.pouch_set_qty(p_list text, p_pass text, p_item uuid, p_qty text)
returns json
language plpgsql security definer set search_path = public as $$
begin
  perform pouch_private.check_pass(p_list, p_pass);
  update public.items set qty = coalesce(nullif(left(trim(coalesce(p_qty, '')), 20), ''), '1')
   where id = p_item and list_id = p_list;
  return pouch_private.snapshot(p_list);
end $$;

create or replace function public.pouch_set_done(p_list text, p_pass text, p_item uuid, p_done boolean)
returns json
language plpgsql security definer set search_path = public as $$
declare l public.lists;
begin
  l := pouch_private.check_pass(p_list, p_pass);
  if p_done and l.done_mode = 'delete' then
    delete from public.items where id = p_item and list_id = p_list;
  else
    update public.items set done = p_done, done_at = case when p_done then now() end
     where id = p_item and list_id = p_list;
  end if;
  return pouch_private.snapshot(p_list);
end $$;

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

create or replace function public.pouch_forget(p_list text, p_pass text, p_key text)
returns json
language plpgsql security definer set search_path = public as $$
begin
  perform pouch_private.check_pass(p_list, p_pass);
  delete from public.memory where list_id = p_list and key = p_key;
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

-- ---------- Who may call what ----------
grant execute on function
  public.pouch_create(text, text),
  public.pouch_open(text, text),
  public.pouch_add(text, text, text),
  public.pouch_add(text, text, text, text),
  public.pouch_set_qty(text, text, uuid, text),
  public.pouch_set_done(text, text, uuid, boolean),
  public.pouch_delete_item(text, text, uuid),
  public.pouch_clear_done(text, text),
  public.pouch_set_mode(text, text, text),
  public.pouch_forget(text, text, text),
  public.pouch_join(text, text, text, text)
to anon, authenticated;
