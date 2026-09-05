-- Doar dacă ați pierdut codul sau vreți să îl schimbați.
-- Bugetele rămân salvate. Ambele telefoane vor trebui să introducă noul cod.
with secret as materialized (
 select replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '') as code
), changed as (
 update public.budget_access
 set code_hash = encode(sha256(convert_to((select code from secret), 'UTF8')), 'hex')
 where id = true
 returning id
)
select case
 when exists(select 1 from changed) then (select code from secret)
 else 'Rulați mai întâi setup.sql.'
end as cod_privat_nou;
