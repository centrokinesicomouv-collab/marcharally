-- MarchaRally · base de datos compartida (Supabase / PostgreSQL)
create extension if not exists pgcrypto;

create table if not exists public.rooms(
  code text primary key,
  name text not null,
  phase text not null default 'lobby' check (phase in ('lobby','active','closed')),
  auto_start boolean not null default false,
  starts_at bigint,
  ends_at bigint,
  created_at timestamptz not null default now()
);

-- El PIN docente (hash) queda en una tabla aparte que el navegador no puede leer.
create table if not exists public.room_secrets(
  code text primary key references public.rooms(code) on delete cascade,
  teacher_hash text not null
);

create table if not exists public.teams(
  id uuid primary key default gen_random_uuid(),
  room_code text not null references public.rooms(code) on delete cascade,
  name text not null check (char_length(name) between 3 and 40),
  created_at timestamptz not null default now()
);
create unique index if not exists teams_room_name on public.teams(room_code, lower(name));

create table if not exists public.students(
  id uuid primary key default gen_random_uuid(),
  room_code text not null references public.rooms(code) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  name text not null check (char_length(name) between 6 and 85),
  rut text not null,
  joined_at timestamptz not null default now(),
  answers jsonb not null default '{}'::jsonb,
  drafts jsonb not null default '{}'::jsonb,
  overrides jsonb not null default '{}'::jsonb,
  events jsonb not null default '[]'::jsonb,
  last_seen bigint,
  away boolean not null default false,
  finished_at timestamptz,
  unique(room_code, rut)
);
create index if not exists students_room on public.students(room_code);
create index if not exists students_team on public.students(team_id);

-- Seguridad: lectura abierta; escrituras sensibles solo mediante funciones.
alter table public.rooms enable row level security;
alter table public.room_secrets enable row level security;
alter table public.teams enable row level security;
alter table public.students enable row level security;

drop policy if exists rooms_read on public.rooms;
create policy rooms_read on public.rooms for select using (true);
drop policy if exists teams_read on public.teams;
create policy teams_read on public.teams for select using (true);
drop policy if exists students_read on public.students;
create policy students_read on public.students for select using (true);
drop policy if exists students_update on public.students;
create policy students_update on public.students for update using (true) with check (true);

revoke all on public.rooms, public.room_secrets, public.teams, public.students from anon, authenticated;
grant select on public.rooms, public.teams, public.students to anon, authenticated;
grant update (answers, drafts, overrides, events, last_seen, away, finished_at) on public.students to anon, authenticated;

create or replace function public.now_ms() returns bigint
language sql stable as $$ select (extract(epoch from clock_timestamp())*1000)::bigint $$;

create or replace function public.server_now() returns bigint
language sql stable security definer set search_path = public as $$ select public.now_ms() $$;

create or replace function public.create_room(p_name text, p_hash text, p_auto boolean default false)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare v_code text; r public.rooms;
begin
  if coalesce(length(p_hash),0) < 4 then raise exception 'PIN docente inválido.'; end if;
  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random()*31)::int, 1);
    end loop;
    exit when not exists(select 1 from public.rooms where code = v_code);
  end loop;
  insert into public.rooms(code, name, auto_start)
  values (v_code, coalesce(nullif(trim(p_name),''),'MarchaRally · Marchas neurológicas'), coalesce(p_auto,false))
  returning * into r;
  insert into public.room_secrets(code, teacher_hash) values (v_code, p_hash);
  return r;
end $$;

create or replace function public.teacher_check(p_code text, p_hash text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.room_secrets where code = upper(trim(p_code)) and teacher_hash = p_hash)
$$;

create or replace function public.set_room_phase(p_code text, p_hash text, p_phase text)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare r public.rooms; t bigint := public.now_ms();
begin
  if not public.teacher_check(p_code, p_hash) then raise exception 'PIN docente incorrecto para esta sala.'; end if;
  select * into r from public.rooms where code = upper(trim(p_code)) for update;
  if p_phase = 'active' then
    if r.phase <> 'lobby' then raise exception 'La evaluación ya fue iniciada o cerrada.'; end if;
    if not exists(select 1 from public.students where room_code = r.code) then raise exception 'No hay estudiantes inscritos.'; end if;
    update public.rooms set phase='active', starts_at=t, ends_at=t+3600000 where code=r.code returning * into r;
  elsif p_phase = 'closed' then
    update public.rooms set phase='closed', ends_at=least(coalesce(ends_at,t),t) where code=r.code returning * into r;
    update public.students set finished_at = coalesce(finished_at, now()) where room_code=r.code;
  else
    raise exception 'Estado no válido.';
  end if;
  return r;
end $$;

create or replace function public.rut_valid(p text) returns boolean
language plpgsql immutable as $$
declare body text; dv text; s int := 0; m int := 2; k int; expected text;
begin
  if coalesce(p,'') !~ '^[0-9]{7,8}-[0-9K]$' then return false; end if;
  body := split_part(p,'-',1); dv := split_part(p,'-',2);
  for i in reverse length(body)..1 loop
    s := s + substr(body,i,1)::int * m;
    m := case when m = 7 then 2 else m + 1 end;
  end loop;
  k := 11 - s % 11;
  expected := case k when 11 then '0' when 10 then 'K' else k::text end;
  return expected = dv;
end $$;

create or replace function public.register_student(p_room text, p_name text, p_rut text, p_team_id uuid, p_new_team text)
returns public.students language plpgsql security definer set search_path = public as $$
declare r public.rooms; v_team uuid; v_count int; s public.students; t bigint := public.now_ms();
begin
  -- Bloquea la sala: las inscripciones simultáneas se procesan de a una (evita equipos de 9 o RUT duplicados).
  select * into r from public.rooms where code = upper(trim(coalesce(p_room,''))) for update;
  if not found then raise exception 'La sala "%" no existe. Revisa el código.', p_room; end if;
  if r.phase <> 'lobby' then raise exception 'La inscripción está cerrada.'; end if;
  if char_length(trim(coalesce(p_name,''))) < 6 or char_length(trim(p_name)) > 85 then raise exception 'Ingresa nombre y apellidos.'; end if;
  if not public.rut_valid(p_rut) then raise exception 'El RUT es incorrecto. Revisa su dígito verificador.'; end if;
  if exists(select 1 from public.students where room_code=r.code and rut=p_rut) then raise exception 'Este RUT ya se encuentra registrado en esta sala.'; end if;
  if nullif(trim(coalesce(p_new_team,'')),'') is not null then
    if char_length(trim(p_new_team)) < 3 or char_length(trim(p_new_team)) > 40 then raise exception 'Nombre del equipo: entre 3 y 40 caracteres.'; end if;
    if exists(select 1 from public.teams where room_code=r.code and lower(name)=lower(trim(p_new_team))) then raise exception 'Ya existe un equipo con ese nombre.'; end if;
    insert into public.teams(room_code, name) values (r.code, trim(p_new_team)) returning id into v_team;
  else
    select id into v_team from public.teams where id = p_team_id and room_code = r.code;
    if not found then raise exception 'Selecciona un equipo válido.'; end if;
    select count(*) into v_count from public.students where team_id = v_team;
    if v_count >= 8 then raise exception 'Equipo completo (máximo 8).'; end if;
  end if;
  insert into public.students(room_code, team_id, name, rut, events, last_seen)
  values (r.code, v_team, trim(p_name), p_rut,
    jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'kind','entrada', 'reason','Registro inicial',
      'at', to_char(now() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'), 'waived', false)), t)
  returning * into s;
  if r.auto_start then
    update public.rooms set phase='active', starts_at=t, ends_at=t+3600000 where code=r.code;
  end if;
  return s;
end $$;

revoke all on function public.create_room(text,text,boolean), public.teacher_check(text,text),
  public.set_room_phase(text,text,text), public.register_student(text,text,text,uuid,text), public.server_now() from public;
grant execute on function public.create_room(text,text,boolean), public.teacher_check(text,text),
  public.set_room_phase(text,text,text), public.register_student(text,text,text,uuid,text), public.server_now() to anon, authenticated;

-- Tiempo real
do $$ begin
  begin alter publication supabase_realtime add table public.rooms; exception when others then null; end;
  begin alter publication supabase_realtime add table public.teams; exception when others then null; end;
  begin alter publication supabase_realtime add table public.students; exception when others then null; end;
end $$;

-- Retomar sesión (estudiante que cerró el navegador o cambió de teléfono)
create or replace function public.resume_student(p_room text, p_rut text, p_name text)
returns public.students language plpgsql security definer set search_path = public as $$
declare s public.students;
begin
  select * into s from public.students where room_code = upper(trim(coalesce(p_room,''))) and rut = p_rut;
  if not found then raise exception 'No hay una inscripción con ese RUT en esta sala.'; end if;
  if lower(regexp_replace(trim(s.name),'[[:space:]]+',' ','g')) <> lower(regexp_replace(trim(coalesce(p_name,'')),'[[:space:]]+',' ','g')) then
    raise exception 'El nombre no coincide con el registrado para ese RUT. Escríbelo igual que al inscribirte.';
  end if;
  return s;
end $$;
revoke all on function public.resume_student(text,text,text) from public;
grant execute on function public.resume_student(text,text,text) to anon, authenticated;
