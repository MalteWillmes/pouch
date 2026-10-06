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
  done       boolean not null default false,
  created_at timestamptz not null default now(),
  done_at    timestamptz
);
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
alter table public.lists  enable row level security;
alter table public.items  enable row level security;
alter table public.memory enable row level security;

-- ---------- Password check ----------
create or replace function public._pouch_check(p_list text, p_pass text)
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
create or replace function public._pouch_snapshot(p_list text)
returns json
language sql security definer set search_path = public as $$
  select json_build_object(
    'id', l.id,
    'name', l.name,
    'done_mode', l.done_mode,
    'items', coalesce((
      select json_agg(json_build_object(
        'id', i.id, 'text', i.text, 'done', i.done,
        'created_at', i.created_at, 'done_at', i.done_at) order by i.created_at)
      from public.items i where i.list_id = l.id), '[]'::json),
    'memory', coalesce((
      select json_agg(json_build_object('key', m.key, 'label', m.label, 'uses', m.uses)
        order by m.uses desc, m.last_used desc)
      from (select * from public.memory where list_id = l.id
            order by uses desc, last_used desc limit 300) m), '[]'::json)
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
  perform public._pouch_check(p_list, p_pass);
  return public._pouch_snapshot(p_list);
end $$;

create or replace function public.pouch_add(p_list text, p_pass text, p_text text)
returns json
language plpgsql security definer set search_path = public as $$
declare t text := left(regexp_replace(trim(p_text), '\s+', ' ', 'g'), 120);
        k text := lower(t);
        existing public.items;
begin
  perform public._pouch_check(p_list, p_pass);
  if t = '' then raise exception 'empty_item'; end if;

  insert into public.memory (list_id, key, label) values (p_list, k, t)
  on conflict (list_id, key) do update
    set uses = public.memory.uses + 1, last_used = now();

  -- Same item already on the list? Bring it back instead of adding a duplicate.
  select * into existing from public.items
   where list_id = p_list and lower(text) = k order by done asc limit 1;
  if existing.id is not null then
    update public.items set done = false, done_at = null where id = existing.id;
  else
    insert into public.items (list_id, text) values (p_list, t);
  end if;
  return public._pouch_snapshot(p_list);
end $$;

create or replace function public.pouch_set_done(p_list text, p_pass text, p_item uuid, p_done boolean)
returns json
language plpgsql security definer set search_path = public as $$
declare l public.lists;
begin
  l := public._pouch_check(p_list, p_pass);
  if p_done and l.done_mode = 'delete' then
    delete from public.items where id = p_item and list_id = p_list;
  else
    update public.items set done = p_done, done_at = case when p_done then now() end
     where id = p_item and list_id = p_list;
  end if;
  return public._pouch_snapshot(p_list);
end $$;

create or replace function public.pouch_delete_item(p_list text, p_pass text, p_item uuid)
returns json
language plpgsql security definer set search_path = public as $$
begin
  perform public._pouch_check(p_list, p_pass);
  delete from public.items where id = p_item and list_id = p_list;
  return public._pouch_snapshot(p_list);
end $$;

create or replace function public.pouch_clear_done(p_list text, p_pass text)
returns json
language plpgsql security definer set search_path = public as $$
begin
  perform public._pouch_check(p_list, p_pass);
  delete from public.items where list_id = p_list and done;
  return public._pouch_snapshot(p_list);
end $$;

create or replace function public.pouch_set_mode(p_list text, p_pass text, p_mode text)
returns json
language plpgsql security definer set search_path = public as $$
begin
  perform public._pouch_check(p_list, p_pass);
  update public.lists set done_mode = p_mode where id = p_list;
  if p_mode = 'delete' then
    delete from public.items where list_id = p_list and done;
  end if;
  return public._pouch_snapshot(p_list);
end $$;

create or replace function public.pouch_forget(p_list text, p_pass text, p_key text)
returns json
language plpgsql security definer set search_path = public as $$
begin
  perform public._pouch_check(p_list, p_pass);
  delete from public.memory where list_id = p_list and key = p_key;
  return public._pouch_snapshot(p_list);
end $$;

-- ---------- Who may call what ----------
revoke all on function public._pouch_check(text, text)  from public, anon, authenticated;
revoke all on function public._pouch_snapshot(text)     from public, anon, authenticated;
grant execute on function
  public.pouch_create(text, text),
  public.pouch_open(text, text),
  public.pouch_add(text, text, text),
  public.pouch_set_done(text, text, uuid, boolean),
  public.pouch_delete_item(text, text, uuid),
  public.pouch_clear_done(text, text),
  public.pouch_set_mode(text, text, text),
  public.pouch_forget(text, text, text)
to anon, authenticated;
