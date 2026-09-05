-- Rulați în SQL Editor, într-un proiect Supabase dedicat acestui buget.
-- Nu introduceți codul privat în GitHub sau în config.js.
begin;
create table if not exists public.budget_access (
 id boolean primary key default true check (id),
 code_hash text not null
);
create table if not exists public.budget_months (
 month text primary key check (month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
 data jsonb not null,
 version integer not null default 1,
 updated_at timestamptz not null default now()
);
alter table public.budget_access enable row level security;
alter table public.budget_months enable row level security;
revoke all on public.budget_access, public.budget_months from public, anon, authenticated;

create or replace function public.check_budget_access(p_code text)
returns void language plpgsql security definer set search_path = '' as $$
begin
 if p_code is null or length(p_code) <> 64 or not exists (
   select 1 from public.budget_access where id = true
   and code_hash = encode(sha256(convert_to(p_code, 'UTF8')), 'hex')
 ) then raise exception 'ACCESS_DENIED'; end if;
end; $$;
revoke all on function public.check_budget_access(text) from public, anon, authenticated;

create or replace function public.read_budget(p_code text, p_month text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
 perform public.check_budget_access(p_code);
 if p_month is null or p_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'INVALID_MONTH'; end if;
 select jsonb_build_object('data', data, 'version', version, 'updated_at', updated_at)
 into result from public.budget_months where month = p_month;
 return coalesce(result, jsonb_build_object('data', null, 'version', 0, 'updated_at', null));
end; $$;
revoke all on function public.read_budget(text,text) from public, anon, authenticated;
grant execute on function public.read_budget(text,text) to anon;

create or replace function public.save_budget(p_code text, p_month text, p_data jsonb, p_version integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare old_version integer; result jsonb; r jsonb;
begin
 perform public.check_budget_access(p_code);
 if p_month is null or p_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'INVALID_MONTH'; end if;
 if p_version is null or p_version < 0 then raise exception 'INVALID_VERSION'; end if;
 if p_data is null or jsonb_typeof(p_data) <> 'object' or octet_length(p_data::text)>250000
 or jsonb_typeof(p_data->'rows') is distinct from 'array'
 or jsonb_typeof(p_data->'transfers') is distinct from 'array' then raise exception 'INVALID_DATA'; end if;
 if jsonb_array_length(p_data->'rows')>200 or jsonb_array_length(p_data->'transfers')>200 then raise exception 'TOO_MANY_ROWS'; end if;
 for r in select value from jsonb_array_elements(p_data->'rows') loop
  if not (r ?& array['id','owner','kind','label','planned','actual','date'])
  or jsonb_typeof(r->'id') is distinct from 'string' or length(r->>'id') not between 1 and 100
  or coalesce(r->>'owner','') not in ('Marius','Diana')
  or coalesce(r->>'kind','') not in ('income','expense')
  or jsonb_typeof(r->'label') is distinct from 'string' or length(trim(r->>'label')) not between 1 and 100
  or jsonb_typeof(r->'planned') is distinct from 'number'
  or (r->>'planned') !~ '^[0-9]+$' or (r->>'planned')::numeric>100000000
  or (r->'actual' <> 'null'::jsonb and (jsonb_typeof(r->'actual') <> 'number'
      or (r->>'actual') !~ '^[0-9]+$' or (r->>'actual')::numeric>100000000))
  or jsonb_typeof(r->'date') is distinct from 'string'
  or (r->>'date' <> '' and (r->>'date') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$')
  then raise exception 'INVALID_ROW'; end if;
 end loop;
 for r in select value from jsonb_array_elements(p_data->'transfers') loop
  if not (r ?& array['id','from','amount','date'])
  or jsonb_typeof(r->'id') is distinct from 'string' or length(r->>'id') not between 1 and 100
  or coalesce(r->>'from','') not in ('Marius','Diana')
  or jsonb_typeof(r->'amount') is distinct from 'number' or (r->>'amount') !~ '^[0-9]+$'
  or (r->>'amount')::numeric not between 1 and 100000000
  or jsonb_typeof(r->'date') is distinct from 'string' or (r->>'date') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  then raise exception 'INVALID_TRANSFER'; end if;
 end loop;
 if exists(select id from (
   select value->>'id' id from jsonb_array_elements(p_data->'rows')
   union all select value->>'id' from jsonb_array_elements(p_data->'transfers')
 ) all_rows group by id having count(*)>1) then raise exception 'DUPLICATE_ID'; end if;
 -- Protejează inclusiv prima salvare a aceleiași luni.
 perform pg_advisory_xact_lock(hashtext('impreuna:' || p_month));
 select version into old_version from public.budget_months where month=p_month;
 if coalesce(old_version,0) <> p_version then raise exception 'CONFLICT'; end if;
 insert into public.budget_months(month,data,version,updated_at) values(p_month,p_data,p_version+1,now())
 on conflict(month) do update set data=excluded.data,version=excluded.version,updated_at=excluded.updated_at;
 select jsonb_build_object('version',version,'updated_at',updated_at) into result from public.budget_months where month=p_month;
 return result;
end; $$;
revoke all on function public.save_budget(text,text,jsonb,integer) from public, anon, authenticated;
grant execute on function public.save_budget(text,text,jsonb,integer) to anon;
commit;

-- Prima rulare returnează codul privat în Results. Copiați-l într-un loc sigur.
-- Rulările următoare păstrează codul existent și nu șterg bugetele.
with secret as materialized (
 select replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '') as code
), inserted as (
 insert into public.budget_access(id,code_hash)
 select true, encode(sha256(convert_to(code,'UTF8')),'hex') from secret
 on conflict(id) do nothing returning id
)
select case when exists(select 1 from inserted) then (select code from secret)
 else 'Codul există deja. Folosiți codul salvat la prima configurare.' end as cod_privat;
