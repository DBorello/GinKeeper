create sequence if not exists gin_seq;
create table if not exists gin_docs(
  league text not null, id text not null, kind text not null,
  data jsonb, deleted boolean not null default false,
  u bigint not null, seq bigint not null default nextval('gin_seq'),
  primary key(league,id));
alter table gin_docs enable row level security;
revoke all on gin_docs from anon, authenticated;
create or replace function gin_push(p_league text, p_docs jsonb) returns int
language plpgsql security definer set search_path=public as $$
declare d jsonb; n int:=0;
begin
  if length(p_league)<12 then raise exception 'sync code too short'; end if;
  for d in select * from jsonb_array_elements(p_docs) loop
    insert into gin_docs(league,id,kind,data,deleted,u,seq)
    values(p_league,d->>'id',d->>'kind',d->'data',coalesce((d->>'deleted')::boolean,false),(d->>'u')::bigint,nextval('gin_seq'))
    on conflict(league,id) do update set kind=excluded.kind,data=excluded.data,
      deleted=excluded.deleted,u=excluded.u,seq=excluded.seq
    where gin_docs.u < excluded.u;
    n:=n+1;
  end loop;
  return n;
end $$;
create or replace function gin_pull(p_league text, p_since bigint)
returns table(id text, kind text, data jsonb, deleted boolean, u bigint, seq bigint)
language sql stable security definer set search_path=public as $$
  select id,kind,data,deleted,u,seq from gin_docs
  where league=p_league and seq>p_since order by seq limit 1000 $$;
grant execute on function gin_push(text,jsonb) to anon;
grant execute on function gin_pull(text,bigint) to anon;