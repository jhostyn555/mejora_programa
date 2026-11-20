-- =============================================================================
-- app_ready_migration.sql
-- Deja las tablas de transporte listas para usarse desde la app Flutter:
--   1. Permisos (GRANT) para anon/authenticated en todas las tablas.
--   2. RLS habilitado + políticas por rol.
--   3. persona.ci pasa a ser opcional (la app no pide CI al registrarse).
--   4. Trigger de registro completo (profiles + usuario + persona + cliente).
--   5. Backfill de usuarios existentes.
--   6. Datos demo: líneas, rutas, choferes, control y vehículos.
--
-- IDEMPOTENTE: se puede ejecutar más de una vez sin duplicar datos.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Permisos de tabla
-- ---------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;

-- Catálogo público (la app puede mostrar líneas y rutas sin iniciar sesión).
grant select on public.linea to anon, authenticated;
grant select on public.ruta to anon, authenticated;

-- El resto: solo usuarios autenticados (las políticas limitan por fila).
grant select, insert, update, delete on public.linea to authenticated;
grant select, insert, update, delete on public.ruta to authenticated;
grant select, insert, update, delete on public.persona to authenticated;
grant select, insert, update, delete on public.usuario to authenticated;
grant select, insert, update, delete on public.cliente to authenticated;
grant select, insert, update, delete on public.chofer to authenticated;
grant select, insert, update, delete on public.control to authenticated;
grant select, insert, update, delete on public.administrador to authenticated;
grant select, insert, update, delete on public.vehiculo to authenticated;
grant select, insert, update, delete on public.historial_vehiculo_viaje to authenticated;
grant select, insert, update, delete on public.historial_chofer_control to authenticated;
grant select, insert, update, delete on public.multa to authenticated;
grant select, insert, update, delete on public.pago to authenticated;
grant select, insert, update, delete on public.aviso to authenticated;
grant select on public.profiles to anon, authenticated;
grant update (full_name, requested_role) on public.profiles to authenticated;

grant usage, select on all sequences in schema public to authenticated;

-- ---------------------------------------------------------------------------
-- 2. persona.ci opcional (el registro desde la app no pide CI)
-- ---------------------------------------------------------------------------
alter table public.persona alter column ci drop not null;
alter table public.persona alter column telefono drop not null;

-- ---------------------------------------------------------------------------
-- 3. RLS en todas las tablas
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

-- ---------------------------------------------------------------------------
-- 4. Políticas
-- ---------------------------------------------------------------------------
-- profiles
drop policy if exists "ver perfil propio o admin o control" on public.profiles;
create policy "ver perfil propio o admin o control"
  on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin() or public.is_control());

drop policy if exists "editar perfil propio" on public.profiles;
create policy "editar perfil propio"
  on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid() and (requested_role is null or requested_role in ('chofer','control')));

-- persona / usuario
drop policy if exists "persona select self o gestor" on public.persona;
create policy "persona select self o gestor"
  on public.persona for select to authenticated
  using (id_usuario = auth.uid() or public.is_admin() or public.is_control());

drop policy if exists "persona insert self" on public.persona;
create policy "persona insert self"
  on public.persona for insert to authenticated
  with check (id_usuario = auth.uid() or public.is_admin() or public.is_control());

drop policy if exists "persona update self" on public.persona;
create policy "persona update self"
  on public.persona for update to authenticated
  using (id_usuario = auth.uid() or public.is_admin() or public.is_control())
  with check (id_usuario = auth.uid() or public.is_admin() or public.is_control());

drop policy if exists "usuario select self o gestor" on public.usuario;
create policy "usuario select self o gestor"
  on public.usuario for select to authenticated
  using (id_usuario = auth.uid() or public.is_admin() or public.is_control());

-- cliente
drop policy if exists "cliente select self o gestor" on public.cliente;
create policy "cliente select self o gestor"
  on public.cliente for select to authenticated
  using (id_persona = public.my_persona_id() or public.is_admin() or public.is_control());

-- chofer
drop policy if exists "chofer select self o gestores" on public.chofer;
create policy "chofer select self o gestores"
  on public.chofer for select to authenticated
  using (id_persona = public.my_persona_id() or public.is_admin() or public.is_control());

drop policy if exists "chofer write gestores" on public.chofer;
create policy "chofer write gestores"
  on public.chofer for all to authenticated
  using (public.is_admin() or public.is_control())
  with check (public.is_admin() or public.is_control());

-- control
drop policy if exists "control select self o admin" on public.control;
create policy "control select self o admin"
  on public.control for select to authenticated
  using (id_persona = public.my_persona_id() or public.is_admin());

drop policy if exists "control write admin" on public.control;
create policy "control write admin"
  on public.control for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- administrador
drop policy if exists "admin select solo admin" on public.administrador;
create policy "admin select solo admin"
  on public.administrador for select to authenticated using (public.is_admin());

drop policy if exists "admin write solo admin" on public.administrador;
create policy "admin write solo admin"
  on public.administrador for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- linea / ruta (lectura pública, escritura admin/control)
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

-- vehiculo
drop policy if exists "vehiculo select" on public.vehiculo;
create policy "vehiculo select"
  on public.vehiculo for select to authenticated
  using (
    id_chofer = public.my_chofer_id()
    or public.is_admin()
    or exists (
      select 1 from public.control c
      where c.id_control = public.my_control_id() and c.id_linea = vehiculo.id_linea
    )
    or activo = true
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

drop policy if exists "vehiculo delete gestores" on public.vehiculo;
create policy "vehiculo delete gestores"
  on public.vehiculo for delete to authenticated
  using (public.is_admin() or public.is_control());

-- historial_vehiculo_viaje
drop policy if exists "hv select self o gestores" on public.historial_vehiculo_viaje;
create policy "hv select self o gestores"
  on public.historial_vehiculo_viaje for select to authenticated
  using (id_chofer = public.my_chofer_id() or public.is_admin() or public.is_control());

drop policy if exists "hv write gestores o self" on public.historial_vehiculo_viaje;
create policy "hv write gestores o self"
  on public.historial_vehiculo_viaje for insert to authenticated
  with check (id_chofer = public.my_chofer_id() or public.is_admin() or public.is_control());

drop policy if exists "hv update self o gestores" on public.historial_vehiculo_viaje;
create policy "hv update self o gestores"
  on public.historial_vehiculo_viaje for update to authenticated
  using (id_chofer = public.my_chofer_id() or public.is_admin() or public.is_control())
  with check (id_chofer = public.my_chofer_id() or public.is_admin() or public.is_control());

-- historial_chofer_control
drop policy if exists "hcc select self o gestores" on public.historial_chofer_control;
create policy "hcc select self o gestores"
  on public.historial_chofer_control for select to authenticated
  using (id_chofer = public.my_chofer_id() or public.is_admin() or public.is_control());

drop policy if exists "hcc write gestores o self" on public.historial_chofer_control;
create policy "hcc write gestores o self"
  on public.historial_chofer_control for insert to authenticated
  with check (id_chofer = public.my_chofer_id() or id_control = public.my_control_id() or public.is_admin());

-- multa
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

-- pago
drop policy if exists "pago select self o gestores" on public.pago;
create policy "pago select self o gestores"
  on public.pago for select to authenticated
  using (id_cliente = public.my_cliente_id() or public.is_admin() or public.is_control());

drop policy if exists "pago write gestores" on public.pago;
create policy "pago write gestores"
  on public.pago for insert to authenticated
  with check (public.is_admin() or public.is_control());

-- aviso
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
-- 5. Registro completo de usuarios nuevos
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nombre text := coalesce(new.raw_user_meta_data->>'full_name', '');
begin
  insert into public.profiles (id, full_name)
  values (new.id, v_nombre)
  on conflict (id) do nothing;

  insert into public.usuario (id_usuario, email)
  values (new.id, new.email)
  on conflict (id_usuario) do update set email = excluded.email, updated_at = now();

  insert into public.persona (id_usuario, nombre, activo)
  select new.id, v_nombre, true
  where not exists (select 1 from public.persona p where p.id_usuario = new.id);

  insert into public.cliente (id_persona, tipo_cliente, activo)
  select p.id_persona, 'normal', true
    from public.persona p
   where p.id_usuario = new.id
     and not exists (select 1 from public.cliente c where c.id_persona = p.id_persona);

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_full on auth.users;
revoke all on function public.handle_new_user() from public, anon;

-- ---------------------------------------------------------------------------
-- 6. Backfill de usuarios existentes
-- ---------------------------------------------------------------------------
insert into public.usuario (id_usuario, email)
select u.id, u.email from auth.users u
on conflict (id_usuario) do update set email = excluded.email, updated_at = now();

insert into public.persona (id_usuario, nombre, activo)
select u.id,
       coalesce(nullif(p.full_name, ''), split_part(u.email, '@', 1)),
       true
  from auth.users u
  left join public.profiles p on p.id = u.id
 where not exists (select 1 from public.persona pe where pe.id_usuario = u.id);

insert into public.cliente (id_persona, tipo_cliente, activo)
select pe.id_persona, 'normal', true
  from public.persona pe
 where not exists (select 1 from public.cliente c where c.id_persona = pe.id_persona);

-- ---------------------------------------------------------------------------
-- 7. Roles de las cuentas demo
-- ---------------------------------------------------------------------------
update public.profiles set role = 'admin'   where id = 'a3cfe6ba-e942-467a-826d-55e50cb21b2d' and role <> 'admin';
update public.profiles set role = 'control' where id = '702b67ce-a97f-475e-aee2-9fba5021362e' and role = 'cliente';
update public.profiles set role = 'chofer'  where id = '7f2f170f-f2e2-4807-8182-8dee3fbb4dfa' and role = 'cliente';
update public.profiles set role = 'cliente' where id = 'fbfb8bf6-0fe5-4fca-929d-98eda04e1041';

-- ---------------------------------------------------------------------------
-- 8. Datos demo
-- ---------------------------------------------------------------------------
insert into public.linea (nombre_linea, descripcion, activo) values
  ('Línea 701 - Trufi',  'Servicio troncal Trufi Cochabamba', true),
  ('Línea 101 - Centro', 'Recorrido por el centro histórico', true),
  ('Línea 202 - Norte',  'Conexión con la zona norte', true)
on conflict (nombre_linea) do nothing;

insert into public.ruta (id_linea, nombre_ruta, descripcion_trazado, activo)
select l.id_linea, v.nombre_ruta, v.descripcion, true
  from (values
    ('Línea 701 - Trufi',  'Ruta Norte-Sur',   'Plaza 14 de Septiembre → Coronilla'),
    ('Línea 701 - Trufi',  'Ruta Sur-Norte',   'Coronilla → Plaza 14 de Septiembre'),
    ('Línea 101 - Centro', 'Circuito Centro',  'Vuelta por el casco viejo'),
    ('Línea 202 - Norte',  'Ruta Aeropuerto',  'Centro → Aeropuerto Jorge Wilstermann')
  ) as v(linea, nombre_ruta, descripcion)
  join public.linea l on l.nombre_linea = v.linea
 where not exists (
   select 1 from public.ruta r
    where r.id_linea = l.id_linea and r.nombre_ruta = v.nombre_ruta
 );

-- Persona del chofer demo adicional (sin cuenta de Auth)
insert into public.persona (id_usuario, nombre, ci, telefono, activo)
select null, 'Carlos Mamani', '8123456', '71234567', true
 where not exists (select 1 from public.persona where ci = '8123456');

-- Chofer: cuenta demo + chofer adicional
insert into public.chofer (id_persona, licencia, activo)
select p.id_persona, 'CHOFER-DEMO-001', true
  from public.persona p
 where p.id_usuario = '7f2f170f-f2e2-4807-8182-8dee3fbb4dfa'
   and not exists (select 1 from public.chofer c where c.id_persona = p.id_persona);

insert into public.chofer (id_persona, licencia, activo)
select p.id_persona, 'CHOFER-DEMO-002', true
  from public.persona p
 where p.ci = '8123456'
   and not exists (select 1 from public.chofer c where c.id_persona = p.id_persona);

-- Control: cuenta demo, asignada a la línea 701
insert into public.control (id_persona, id_admin, id_linea, activo)
select p.id_persona, null, l.id_linea, true
  from public.persona p
  join public.linea l on l.nombre_linea = 'Línea 701 - Trufi'
 where p.id_usuario = '702b67ce-a97f-475e-aee2-9fba5021362e'
   and not exists (select 1 from public.control c where c.id_persona = p.id_persona);

-- Vehículos activos con ubicación
insert into public.vehiculo (placa, latitud, longitud, id_chofer, id_linea, activo)
select 'TRUFI-001', -17.3895000, -66.1568000, c.id_chofer, l.id_linea, true
  from public.persona p
  join public.chofer c on c.id_persona = p.id_persona
  join public.linea l on l.nombre_linea = 'Línea 701 - Trufi'
 where p.id_usuario = '7f2f170f-f2e2-4807-8182-8dee3fbb4dfa'
   and not exists (select 1 from public.vehiculo v where v.placa = 'TRUFI-001');

insert into public.vehiculo (placa, latitud, longitud, id_chofer, id_linea, activo)
select 'TRUFI-002', -17.3932000, -66.1601000, c.id_chofer, l.id_linea, true
  from public.persona p
  join public.chofer c on c.id_persona = p.id_persona
  join public.linea l on l.nombre_linea = 'Línea 701 - Trufi'
 where p.ci = '8123456'
   and not exists (select 1 from public.vehiculo v where v.placa = 'TRUFI-002');

insert into public.vehiculo (placa, latitud, longitud, id_chofer, id_linea, activo)
select 'TRUFI-003', -17.3801000, -66.1512000, null, l.id_linea, true
  from public.linea l
 where l.nombre_linea = 'Línea 202 - Norte'
   and not exists (select 1 from public.vehiculo v where v.placa = 'TRUFI-003');

-- ---------------------------------------------------------------------------
-- 9. Recargar la caché del esquema en PostgREST
-- ---------------------------------------------------------------------------
notify pgrst, 'reload schema';

-- =============================================================================
-- FIN.
-- =============================================================================
