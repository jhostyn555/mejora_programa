-- =============================================================================
-- chofer_control_migration.sql
-- Migración para: (1) añadir rol "chofer", (2) arreglar GRANTs y RLS en las 14
-- tablas de transporte, (3) añadir helpers y funciones RPC para las vistas de
-- chofer, control y cliente.
--
-- IDEMPOTENTE: se puede pegar completo en el SQL Editor y ejecutar cuantas
-- veces sea necesario. No borra datos existentes.
--
-- NOTA: No se envuelve en BEGIN/COMMIT porque ALTER TYPE ... ADD VALUE no
-- puede ejecutarse dentro de una transacción. Las sentencias son
-- idempotentes (CREATE OR REPLACE, DROP IF EXISTS, CREATE INDEX IF NOT
-- EXISTS) así que un fallo a mitad no deja el esquema inconsistente.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor → New query → pegar → Run.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 0. Asegurar enum app_role con 'chofer' y migrar 'transportista' -> 'chofer'
-- ---------------------------------------------------------------------------
do $$
begin
  -- Añade 'chofer' al enum si no existe.
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'app_role' and n.nspname = 'public'
  ) then
    execute 'create type public.app_role as enum (''cliente'', ''chofer'', ''control'', ''admin'')';
  elsif not exists (
    select 1 from pg_enum
    where enumlabel = 'chofer'
      and enumtypid = (select oid from pg_type where typname = 'app_role' and typnamespace = 'public'::regnamespace)
  ) then
    execute 'alter type public.app_role add value if not exists ''chofer''';
  end if;
end $$;

-- Migrar cualquier fila con role='transportista' a 'chofer' (sólo si la
-- columna role es de tipo app_role y contiene 'transportista').
do $$
begin
  if exists (
    select 1 from information_schema.columns c
    join information_schema.tables t on t.table_schema = c.table_schema and t.table_name = c.table_name
    where c.table_schema = 'public' and c.table_name = 'profiles' and c.column_name = 'role'
      and c.data_type = 'USER-DEFINED'
  ) then
    -- Sólo si 'transportista' sigue siendo un valor válido del enum, migrarlo.
    if exists (
      select 1 from pg_enum
      where enumlabel = 'transportista'
        and enumtypid = (select oid from pg_type where typname = 'app_role')
    ) then
      -- Si 'chofer' ya existe en el enum, actualizamos las filas y luego
      -- (en otra sesión, no aquí) se puede quitar 'transportista'. No
      -- removemos el valor aquí porque ALTER TYPE ... DROP VALUE no se
      -- soporta en una transacción.
      update public.profiles set role = 'chofer'::public.app_role
        where role = 'transportista'::public.app_role;
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. GRANTs sobre las 14 tablas de transporte + profiles.
-- Sin esto TODA lectura falla con 42501 "permission denied for table".
-- ---------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;

-- Lectura pública de tablas "informativas" (líneas y rutas) para que la app
-- cliente las pueda mostrar sin login.
grant select on public.linea to anon, authenticated;
grant select on public.ruta to anon, authenticated;

-- Las demás tablas: SELECT para authenticated; INSERT/UPDATE/DELETE sólo
-- para authenticated (las policies más abajo limitan por rol y por usuario).
grant select on public.profiles to anon, authenticated;
grant select on public.persona to authenticated;
grant select on public.usuario to authenticated;
grant select on public.cliente to authenticated;
grant select on public.chofer to authenticated;
grant select on public.control to authenticated;
grant select on public.administrador to authenticated;
grant select on public.vehiculo to authenticated;
grant select on public.historial_vehiculo_viaje to authenticated;
grant select on public.historial_chofer_control to authenticated;
grant select on public.multa to authenticated;
grant select on public.pago to authenticated;
grant select on public.aviso to authenticated;

grant insert, update, delete on public.profiles to authenticated;
grant insert, update, delete on public.persona to authenticated;
grant insert, update, delete on public.usuario to authenticated;
grant insert, update, delete on public.cliente to authenticated;
grant insert, update, delete on public.chofer to authenticated;
grant insert, update, delete on public.control to authenticated;
grant insert, update, delete on public.administrador to authenticated;
grant insert, update, delete on public.vehiculo to authenticated;
grant insert, update, delete on public.historial_vehiculo_viaje to authenticated;
grant insert, update, delete on public.historial_chofer_control to authenticated;
grant insert, update, delete on public.multa to authenticated;
grant insert, update, delete on public.pago to authenticated;
grant insert, update, delete on public.aviso to authenticated;

-- Permisos de secuencia para INSERT con id serial.
grant usage, select on all sequences in schema public to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Funciones helper y RPC ya existentes (re-crear por si faltan GRANTs).
-- ---------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
     where id = auth.uid() and role = 'admin'
  );
$$;

create or replace function public.is_control()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'control'
  );
$$;

create or replace function public.is_chofer()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'chofer'
  );
$$;

create or replace function public.can_manage_requests()
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin() or public.is_control();
$$;

-- ---------------------------------------------------------------------------
-- 3. Nuevos helpers: ¿cuál es mi persona / chofer / control?
-- ---------------------------------------------------------------------------
create or replace function public.my_role()
returns text language sql stable security definer set search_path = public as $$
  select coalesce((select role::text from public.profiles where id = auth.uid()), 'cliente');
$$;

create or replace function public.my_persona_id()
returns integer language sql stable security definer set search_path = public as $$
  select p.id_persona from public.persona p where p.id_usuario = auth.uid()::text limit 1;
$$;

create or replace function public.my_chofer_id()
returns integer language sql stable security definer set search_path = public as $$
  select c.id_chofer from public.chofer c where c.id_persona = public.my_persona_id() limit 1;
$$;

create or replace function public.my_control_id()
returns integer language sql stable security definer set search_path = public as $$
  select c.id_control from public.control c where c.id_persona = public.my_persona_id() limit 1;
$$;

create or replace function public.my_cliente_id()
returns integer language sql stable security definer set search_path = public as $$
  select c.id_cliente from public.cliente c where c.id_persona = public.my_persona_id() limit 1;
$$;

-- ---------------------------------------------------------------------------
-- 4. RLS — habilitar y crear políticas por tabla
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.persona enable row level security;
alter table public.usuario enable row level security;
alter table public.cliente enable row level security;
alter table public.chofer enable row level security;
alter table public.control enable row level security;
alter table public.administrador enable row level security;
alter table public.linea enable row level security;
alter table public.ruta enable row level security;
alter table public.vehiculo enable row level security;
alter table public.historial_vehiculo_viaje enable row level security;
alter table public.historial_chofer_control enable row level security;
alter table public.multa enable row level security;
alter table public.pago enable row level security;
alter table public.aviso enable row level security;

-- profiles: ya tiene policies; las reforzamos por si faltan.
drop policy if exists "ver perfil propio o admin o control" on public.profiles;
create policy "ver perfil propio o admin o control"
  on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin() or public.is_control());

drop policy if exists "editar perfil propio" on public.profiles;
create policy "editar perfil propio"
  on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid() and (requested_role is null or requested_role in ('chofer','control')));

revoke update on public.profiles from authenticated;
grant update (full_name, requested_role) on public.profiles to authenticated;

-- persona / usuario: self + admin/control leen todo.
drop policy if exists "persona select self o gestor" on public.persona;
create policy "persona select self o gestor"
  on public.persona for select to authenticated
  using (id_usuario = auth.uid()::text or public.is_admin() or public.is_control());

drop policy if exists "persona upsert self" on public.persona;
create policy "persona upsert self"
  on public.persona for insert to authenticated with check (id_usuario = auth.uid()::text);

drop policy if exists "persona update self" on public.persona;
create policy "persona update self"
  on public.persona for update to authenticated using (id_usuario = auth.uid()::text)
  with check (id_usuario = auth.uid()::text);

drop policy if exists "usuario select self o gestor" on public.usuario;
create policy "usuario select self o gestor"
  on public.usuario for select to authenticated
  using (id_usuario = auth.uid()::text or public.is_admin() or public.is_control());

-- cliente: self + admin/control.
drop policy if exists "cliente select self o gestor" on public.cliente;
create policy "cliente select self o gestor"
  on public.cliente for select to authenticated
  using (id_persona = public.my_persona_id() or public.is_admin() or public.is_control());

-- chofer: self + control + admin.
drop policy if exists "chofer select self o gestores" on public.chofer;
create policy "chofer select self o gestores"
  on public.chofer for select to authenticated
  using (id_persona = public.my_persona_id() or public.is_admin() or public.is_control());

-- control: self + admin.
drop policy if exists "control select self o admin" on public.control;
create policy "control select self o admin"
  on public.control for select to authenticated
  using (id_persona = public.my_persona_id() or public.is_admin());

-- administrador: sólo admin lee.
drop policy if exists "admin select solo admin" on public.administrador;
create policy "admin select solo admin"
  on public.administrador for select to authenticated using (public.is_admin());

-- linea / ruta: lectura pública para cualquiera autenticado.
drop policy if exists "linea select any" on public.linea;
create policy "linea select any" on public.linea for select to anon, authenticated using (true);

drop policy if exists "linea write admin control" on public.linea;
create policy "linea write admin control"
  on public.linea for all to authenticated
  using (public.is_admin() or public.is_control())
  with check (public.is_admin() or public.is_control());

drop policy if exists "ruta select any" on public.ruta;
create policy "ruta select any" on public.ruta for select to anon, authenticated using (true);

drop policy if exists "ruta write admin control" on public.ruta;
create policy "ruta write admin control"
  on public.ruta for all to authenticated
  using (public.is_admin() or public.is_control())
  with check (public.is_admin() or public.is_control());

-- vehiculo: chofer ve el suyo; control/admin ven todos; authenticated ven
-- activos (para mostrar ubicación en el mapa del cliente).
drop policy if exists "vehiculo select" on public.vehiculo;
create policy "vehiculo select"
  on public.vehiculo for select to authenticated
  using (
    id_chofer = public.my_chofer_id()
    or public.is_admin()
    or public.is_control()
    or activo = true   -- cliente ve vehículos activos (para mapa)
  );

drop policy if exists "vehiculo update self chofer" on public.vehiculo;
create policy "vehiculo update self chofer"
  on public.vehiculo for update to authenticated
  using (id_chofer = public.my_chofer_id() or public.is_admin() or public.is_control())
  with check (true);

drop policy if exists "vehiculo write gestores" on public.vehiculo;
create policy "vehiculo write gestores"
  on public.vehiculo for insert to authenticated
  with check (public.is_admin() or public.is_control());

-- historial_vehiculo_viaje: chofer ve los suyos; control/admin todos.
drop policy if exists "hv select self o gestores" on public.historial_vehiculo_viaje;
create policy "hv select self o gestores"
  on public.historial_vehiculo_viaje for select to authenticated
  using (id_chofer = public.my_chofer_id() or public.is_admin() or public.is_control());

drop policy if exists "hv write gestores o self" on public.historial_vehiculo_viaje;
create policy "hv write gestores o self"
  on public.historial_vehiculo_viaje for insert to authenticated
  with check (id_chofer = public.my_chofer_id() or public.is_admin() or public.is_control());

-- historial_chofer_control: chofer ve los suyos; control/admin todos.
drop policy if exists "hcc select self o gestores" on public.historial_chofer_control;
create policy "hcc select self o gestores"
  on public.historial_chofer_control for select to authenticated
  using (id_chofer = public.my_chofer_id() or public.is_admin() or public.is_control());

drop policy if exists "hcc write gestores o self" on public.historial_chofer_control;
create policy "hcc write gestores o self"
  on public.historial_chofer_control for insert to authenticated
  with check (id_chofer = public.my_chofer_id() or id_control = public.my_control_id() or public.is_admin());

-- multa: chofer ve las suyas; control/admin todos.
drop policy if exists "multa select self o gestores" on public.multa;
create policy "multa select self o gestores"
  on public.multa for select to authenticated
  using (id_chofer = public.my_chofer_id() or public.is_admin() or public.is_control());

drop policy if exists "multa write gestores" on public.multa;
create policy "multa write gestores"
  on public.multa for insert to authenticated
  with check (id_control = public.my_control_id() or public.is_admin());

drop policy if exists "multa update gestores" on public.multa;
create policy "multa update gestores"
  on public.multa for update to authenticated
  using (id_control = public.my_control_id() or public.is_admin())
  with check (true);

-- pago: cliente ve los suyos; control/admin todos.
drop policy if exists "pago select self o gestores" on public.pago;
create policy "pago select self o gestores"
  on public.pago for select to authenticated
  using (id_cliente = public.my_cliente_id() or public.is_admin() or public.is_control());

-- aviso: cliente ve los dirigidos a él; control/admin ven todos los que emitió.
drop policy if exists "aviso select" on public.aviso;
create policy "aviso select"
  on public.aviso for select to authenticated
  using (
    id_cliente = public.my_cliente_id()
    or id_control = public.my_control_id()
    or public.is_admin()
    or public.is_control()
  );

drop policy if exists "aviso write control" on public.aviso;
create policy "aviso write control"
  on public.aviso for insert to authenticated
  with check (id_control = public.my_control_id() or public.is_admin());

-- ---------------------------------------------------------------------------
-- 5. Funciones de aplicación para las vistas
-- ---------------------------------------------------------------------------

-- Vehículo asignado al chofer autenticado (o null si no tiene).
create or replace function public.my_assigned_vehicle()
returns table (
  id_vehiculo integer, placa text, foto_url text,
  latitud double precision, longitud double precision,
  id_chofer integer, id_linea integer, activo boolean
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_chofer() then
    raise exception 'Solo un chofer puede ver su vehículo asignado';
  end if;
  return query select * from public.vehiculo where id_chofer = public.my_chofer_id() limit 1;
end;
$$;

-- Líneas gestionadas por el control autenticado (o todas si es admin).
create or replace function public.my_lines()
returns table (id_linea integer, nombre_linea text, descripcion text, activo boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if public.is_admin() then
    return query select * from public.linea order by nombre_linea;
  elsif public.is_control() then
    return query
      select l.* from public.linea l
      join public.control c on c.id_linea = l.id_linea
      where c.id_control = public.my_control_id()
      order by l.nombre_linea;
  else
    raise exception 'Solo un control o admin puede listar sus lineas';
  end if;
end;
$$;

-- Vehículos activos con chofer y línea (para mapa de control).
create or replace function public.active_vehicles()
returns table (
  id_vehiculo integer, placa text, latitud double precision, longitud double precision,
  id_chofer integer, id_linea integer, nombre_linea text, nombre_chofer text
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_admin() or public.is_control()) then
    raise exception 'Solo control o admin pueden ver vehículos activos';
  end if;
  return query
    select v.id_vehiculo, v.placa, v.latitud, v.longitud,
           v.id_chofer, v.id_linea, l.nombre_linea,
           coalesce(p.nombre, '') as nombre_chofer
      from public.vehiculo v
      left join public.linea l on l.id_linea = v.id_linea
      left join public.chofer ch on ch.id_chofer = v.id_chofer
      left join public.persona p on p.id_persona = ch.id_persona
      where v.activo = true
      order by v.id_vehiculo;
end;
$$;

-- Chofer actualiza su ubicación.
create or replace function public.upsert_vehicle_location(
  new_lat double precision, new_lng double precision
)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_chofer() then
    raise exception 'Solo un chofer puede actualizar la ubicación';
  end if;
  update public.vehiculo
     set latitud = new_lat, longitud = new_lng, updated_at = now()
   where id_chofer = public.my_chofer_id();
end;
$$;

-- Chofer o control registra un incidente / reporte.
create or replace function public.report_incident(
  p_id_chofer integer, p_estado text, p_observacion text
)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_control integer;
begin
  if not (public.is_chofer() or public.is_control() or public.is_admin()) then
    raise exception 'No autorizado';
  end if;
  -- Si es chofer, sólo puede reportar sobre sí mismo; el control lo elige.
  if public.is_chofer() and p_id_chofer <> public.my_chofer_id() then
    raise exception 'Un chofer solo puede reportar sobre si mismo';
  end if;
  -- Busca el control de la línea del chofer.
  select c.id_control into v_control
    from public.control c
    join public.vehiculo v on v.id_linea = c.id_linea
   where v.id_chofer = p_id_chofer limit 1;
  insert into public.historial_chofer_control
    (id_chofer, id_control, fecha_hora, estado_reporte, observacion)
  values (p_id_chofer, v_control, now(), p_estado, p_observacion);
end;
$$;

-- Control envía un aviso a un cliente o a todos los de una ruta.
create or replace function public.create_aviso(
  p_id_ruta integer default null,
  p_id_cliente integer default null,
  p_mensaje text
)
returns integer language plpgsql security definer set search_path = public as $$
declare p_id integer;
begin
  if not (public.is_control() or public.is_admin()) then
    raise exception 'Solo control o admin pueden emitir avisos';
  end if;
  insert into public.aviso (id_control, id_ruta, id_cliente, mensaje, fecha_hora)
  values (public.my_control_id(), p_id_ruta, p_id_cliente, p_mensaje, now())
  returning id_aviso into p_id;
  return p_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. GRANT EXECUTE sobre todas las funciones RPC
-- ---------------------------------------------------------------------------
revoke all on function public.is_admin() from public, anon;
revoke all on function public.is_control() from public, anon;
revoke all on function public.is_chofer() from public, anon;
revoke all on function public.can_manage_requests() from public, anon;
revoke all on function public.my_role() from public, anon;
revoke all on function public.my_persona_id() from public, anon;
revoke all on function public.my_chofer_id() from public, anon;
revoke all on function public.my_control_id() from public, anon;
revoke all on function public.my_cliente_id() from public, anon;
revoke all on function public.my_assigned_vehicle() from public, anon;
revoke all on function public.my_lines() from public, anon;
revoke all on function public.active_vehicles() from public, anon;
revoke all on function public.upsert_vehicle_location(double precision, double precision) from public, anon;
revoke all on function public.report_incident(integer, text, text) from public, anon;
revoke all on function public.create_aviso(integer, integer, text) from public, anon;
revoke all on function public.ensure_profile() from public, anon;
revoke all on function public.handle_new_user() from public, anon;
revoke all on function public.decide_request(uuid, boolean) from public, anon;
revoke all on function public.promote_to_control(uuid) from public, anon;
revoke all on function public.list_clients() from public, anon;
revoke all on function public.list_users() from public, anon;
revoke all on function public.admin_set_role(uuid, public.app_role) from public, anon;

grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_control() to authenticated;
grant execute on function public.is_chofer() to authenticated;
grant execute on function public.can_manage_requests() to authenticated;
grant execute on function public.my_role() to authenticated;
grant execute on function public.my_persona_id() to authenticated;
grant execute on function public.my_chofer_id() to authenticated;
grant execute on function public.my_control_id() to authenticated;
grant execute on function public.my_cliente_id() to authenticated;
grant execute on function public.my_assigned_vehicle() to authenticated;
grant execute on function public.my_lines() to authenticated;
grant execute on function public.active_vehicles() to authenticated;
grant execute on function public.upsert_vehicle_location(double precision, double precision) to authenticated;
grant execute on function public.report_incident(integer, text, text) to authenticated;
grant execute on function public.create_aviso(integer, integer, text) to authenticated;
grant execute on function public.ensure_profile() to authenticated;
grant execute on function public.decide_request(uuid, boolean) to authenticated;
grant execute on function public.promote_to_control(uuid) to authenticated;
grant execute on function public.list_clients() to authenticated;
grant execute on function public.list_users() to authenticated;
grant execute on function public.admin_set_role(uuid, public.app_role) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Índices para acelerar las búsquedas por auth.uid()
-- ---------------------------------------------------------------------------
create index if not exists idx_persona_id_usuario on public.persona (id_usuario);
create index if not exists idx_chofer_id_persona on public.chofer (id_persona);
create index if not exists idx_control_id_persona on public.control (id_persona);
create index if not exists idx_cliente_id_persona on public.cliente (id_persona);
create index if not exists idx_vehiculo_id_chofer on public.vehiculo (id_chofer);
create index if not exists idx_vehiculo_activo on public.vehiculo (activo) where activo = true;
create index if not exists idx_aviso_id_cliente on public.aviso (id_cliente);
create index if not exists idx_multa_id_chofer on public.multa (id_chofer);
create index if not exists idx_historial_viaje_id_chofer on public.historial_vehiculo_viaje (id_chofer);

-- ---------------------------------------------------------------------------
-- 8. Trigger: al crear un usuario, también crear persona + cliente por defecto.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user_full()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- profiles (rol por defecto: cliente)
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''))
  on conflict (id) do nothing;

  -- usuario (espejo del auth user para el modelo relacional)
  insert into public.usuario (id_usuario, email)
  values (new.id::text, new.email)
  on conflict (id_usuario) do update set email = excluded.email, updated_at = now();

  -- persona (linked por id_usuario = auth.uid)
  insert into public.persona (id_usuario, nombre, activo)
  values (new.id::text, coalesce(new.raw_user_meta_data->>'full_name', ''), true)
  on conflict do nothing;

  -- cliente por defecto (lo mantiene como cliente hasta que un admin lo promueva)
  insert into public.cliente (id_persona, tipo_cliente, activo)
  select p.id_persona, 'regular', true
    from public.persona p
   where p.id_usuario = new.id::text
     and not exists (select 1 from public.cliente c where c.id_persona = p.id_persona)
  limit 1;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_full on auth.users;
create trigger on_auth_user_created_full
after insert on auth.users
for each row execute function public.handle_new_user_full();

notify pgrst, 'reload schema';

-- =============================================================================
-- FIN. Después de ejecutar, crear el primer admin a mano:
--   update public.profiles set role = 'admin' where id = '<uuid-del-admin>';
-- =============================================================================
