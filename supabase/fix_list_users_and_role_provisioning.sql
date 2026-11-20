-- =============================================================================
-- fix_list_users_and_role_provisioning.sql
-- Corrige el buscador de usuarios del panel administrativo y hace que los
-- cambios de rol creen automáticamente las filas relacionales (chofer/control).
--
-- Causa del fallo: auth.users.email es varchar(255) y las funciones
-- list_users()/list_clients() declaran la columna como text. Postgres lanzaba
-- 42804 "structure of query does not match function result type" y la app
-- mostraba "No se encontraron usuarios".
-- =============================================================================

create or replace function public.list_users()
returns table (id uuid, full_name text, email text, role public.app_role)
language plpgsql
stable
security definer
set search_path = public
as $fn$
begin
  if not public.is_admin() then
    raise exception 'Solo un administrador puede listar usuarios';
  end if;

  return query
    select p.id, p.full_name, coalesce(u.email, '')::text, p.role
      from public.profiles p
      join auth.users u on u.id = p.id
     where p.role <> 'admin'
     order by p.full_name, u.email;
end;
$fn$;

create or replace function public.list_clients()
returns table (id uuid, full_name text, email text)
language plpgsql
stable
security definer
set search_path = public
as $fn$
begin
  if not public.is_admin() then
    raise exception 'Solo un administrador puede listar clientes';
  end if;

  return query
    select p.id, p.full_name, coalesce(u.email, '')::text
      from public.profiles p
      join auth.users u on u.id = p.id
     where p.role = 'cliente'
     order by p.full_name, u.email;
end;
$fn$;

-- Un control puede existir sin línea asignada (el panel no asigna líneas).
alter table public.control alter column id_linea drop not null;

-- Crea usuario/persona/cliente y, según el rol, chofer o control.
create or replace function public.sync_role_records(target uuid)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_role public.app_role;
  v_nombre text;
  v_email text;
  v_persona integer;
  v_linea integer;
begin
  select role, full_name into v_role, v_nombre
    from public.profiles where id = target;
  if v_role is null then
    return;
  end if;

  select email::text into v_email from auth.users where id = target;

  insert into public.usuario (id_usuario, email)
  values (target, coalesce(v_email, ''))
  on conflict (id_usuario) do update
    set email = excluded.email, updated_at = now();

  select id_persona into v_persona
    from public.persona where id_usuario = target limit 1;

  if v_persona is null then
    insert into public.persona (id_usuario, nombre, activo)
    values (target, coalesce(nullif(v_nombre, ''), split_part(coalesce(v_email, ''), '@', 1)), true)
    returning id_persona into v_persona;
  end if;

  insert into public.cliente (id_persona, tipo_cliente, activo)
  select v_persona, 'normal', true
   where not exists (select 1 from public.cliente c where c.id_persona = v_persona);

  if v_role = 'chofer' then
    insert into public.chofer (id_persona, licencia, activo)
    select v_persona, 'AUTO-' || replace(target::text, '-', ''), true
     where not exists (select 1 from public.chofer c where c.id_persona = v_persona);
  end if;

  if v_role = 'control' then
    if not exists (select 1 from public.control c where c.id_persona = v_persona) then
      select id_linea into v_linea
        from public.linea where activo order by id_linea limit 1;
      insert into public.control (id_persona, id_admin, id_linea, activo)
      values (v_persona, null, v_linea, true);
    end if;
  end if;
end;
$fn$;

revoke all on function public.sync_role_records(uuid) from public, anon;
grant execute on function public.sync_role_records(uuid) to authenticated;

create or replace function public.admin_set_role(target uuid, new_role public.app_role)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if not public.is_admin() then
    raise exception 'Solo un administrador puede asignar roles';
  end if;

  if new_role = 'admin' then
    raise exception 'El rol de administrador no se asigna desde el panel';
  end if;

  if target = auth.uid() then
    raise exception 'No puedes cambiar tu propio rol';
  end if;

  update public.profiles
     set role = new_role, requested_role = null
   where id = target and role <> 'admin';

  if found then
    perform public.sync_role_records(target);
  end if;
end;
$fn$;

create or replace function public.decide_request(target uuid, approve boolean)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if not public.can_manage_requests() then
    raise exception 'Solo un administrador o control puede decidir solicitudes';
  end if;

  update public.profiles
     set role = case when approve then requested_role else role end,
         requested_role = null
   where id = target and requested_role is not null;

  if found and approve then
    perform public.sync_role_records(target);
  end if;
end;
$fn$;

-- Un control sin línea ve todas las líneas y vehículos.
create or replace function public.my_lines()
returns table (id_linea integer, nombre_linea text, descripcion text, activo boolean)
language plpgsql
stable
security definer
set search_path = public
as $fn$
begin
  if public.is_admin() then
    return query select l.id_linea, l.nombre_linea::text, l.descripcion::text, l.activo
      from public.linea l order by l.nombre_linea;
  elsif public.is_control() then
    if exists (
      select 1 from public.control c
       where c.id_control = public.my_control_id() and c.id_linea is not null
    ) then
      return query
        select l.id_linea, l.nombre_linea::text, l.descripcion::text, l.activo
          from public.linea l
          join public.control c on c.id_linea = l.id_linea
         where c.id_control = public.my_control_id()
         order by l.nombre_linea;
    else
      return query select l.id_linea, l.nombre_linea::text, l.descripcion::text, l.activo
        from public.linea l order by l.nombre_linea;
    end if;
  else
    raise exception 'Solo un control o admin puede listar sus lineas';
  end if;
end;
$fn$;

create or replace function public.active_vehicles()
returns table (
  id_vehiculo integer, placa text, latitud double precision, longitud double precision,
  id_chofer integer, id_linea integer, nombre_linea text, nombre_chofer text
)
language plpgsql
stable
security definer
set search_path = public
as $fn$
begin
  if not (public.is_admin() or public.is_control()) then
    raise exception 'Solo control o admin pueden ver vehículos activos';
  end if;
  return query
    select v.id_vehiculo, v.placa::text, v.latitud::double precision, v.longitud::double precision,
           v.id_chofer, v.id_linea, l.nombre_linea::text,
           coalesce(p.nombre, '')::text
      from public.vehiculo v
      left join public.linea l on l.id_linea = v.id_linea
      left join public.chofer ch on ch.id_chofer = v.id_chofer
      left join public.persona p on p.id_persona = ch.id_persona
     where v.activo
       and (
         public.is_admin()
         or exists (
           select 1 from public.control c
            where c.id_control = public.my_control_id() and c.id_linea = v.id_linea
         )
         or not exists (
           select 1 from public.control c2
            where c2.id_control = public.my_control_id() and c2.id_linea is not null
         )
       )
     order by v.id_vehiculo;
end;
$fn$;

-- Sincroniza las cuentas que ya existen.
do $block$
declare r record;
begin
  for r in select id from public.profiles loop
    perform public.sync_role_records(r.id);
  end loop;
end;
$block$;

notify pgrst, 'reload schema';
