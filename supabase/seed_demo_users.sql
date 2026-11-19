-- =============================================================================
-- seed_demo_users.sql
-- Crea las filas en profiles/persona/chofer/control/vehiculo para los 4
-- usuarios demo creados con la Auth Admin API.
--
-- EJECUTAR DESPUÉS de chofer_control_migration.sql.
-- Idempotente: se puede repetir.
-- =============================================================================

-- UUIDs de los usuarios creados (auth.users):
--   admin@trufi.cbba    → a3cfe6ba-e942-467a-826d-55e50cb21b2d
--   control@trufi.cbba  → 702b67ce-a97f-475e-aee2-9fba5021362e
--   chofer@trufi.cbba   → 7f2f170f-f2e2-4807-8182-8dee3fbb4dfa
--   cliente@trufi.cbba  → fbfb8bf6-0fe5-4fca-929d-98eda04e1041

-- ---------------------------------------------------------------------------
-- 1. PROFILES: asignar rol a cada usuario.
--    (El trigger on_auth_user_created de schema.sql ya creo la fila en
--    profiles al crear el auth user; aquí sólo actualizamos el rol.)
-- ---------------------------------------------------------------------------
update public.profiles set role = 'admin'    where id = 'a3cfe6ba-e942-467a-826d-55e50cb21b2d';
update public.profiles set role = 'control'  where id = '702b67ce-a97f-475e-aee2-9fba5021362e';
update public.profiles set role = 'chofer'   where id = '7f2f170f-f2e2-4807-8182-8dee3fbb4dfa';
update public.profiles set role = 'cliente'  where id = 'fbfb8bf6-0fe5-4fca-929d-98eda04e1041';

-- ---------------------------------------------------------------------------
-- 2. PERSONA + USUARIO: el trigger on_auth_user_created_full de la migración
--    debería haberlos creado, pero si la migración se aplicó DESPUÉS de
--    crear los auth users, hay que hacerlo a mano. Insert or nothing.
-- ---------------------------------------------------------------------------
insert into public.usuario (id_usuario, email)
select id::text, email from auth.users
where id in (
  'a3cfe6ba-e942-467a-826d-55e50cb21b2d',
  '702b67ce-a97f-475e-aee2-9fba5021362e',
  '7f2f170f-f2e2-4807-8182-8dee3fbb4dfa',
  'fbfb8bf6-0fe5-4fca-929d-98eda04e1041'
)
on conflict (id_usuario) do nothing;

insert into public.persona (id_usuario, nombre, ci, telefono, activo)
select u.id::text,
       coalesce(u.raw_user_meta_data->>'full_name', ''),
       '',
       '',
       true
  from auth.users u
 where u.id in (
  'a3cfe6ba-e942-467a-826d-55e50cb21b2d',
  '702b67ce-a97f-475e-aee2-9fba5021362e',
  '7f2f170f-f2e2-4807-8182-8dee3fbb4dfa',
  'fbfb8bf6-0fe5-4fca-929d-98eda04e1041'
)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 3. CLIENTE: fila para el cliente demo y para los demás (por consistencia).
-- ---------------------------------------------------------------------------
insert into public.cliente (id_persona, tipo_cliente, activo)
select p.id_persona, 'regular', true
  from public.persona p
 where p.id_usuario in (
  'a3cfe6ba-e942-467a-826d-55e50cb21b2d',
  '702b67ce-a97f-475e-aee2-9fba5021362e',
  '7f2f170f-f2e2-4807-8182-8dee3fbb4dfa',
  'fbfb8bf6-0fe5-4fca-929d-98eda04e1041'
 )
 and not exists (select 1 from public.cliente c where c.id_persona = p.id_persona)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 4. LÍNEA DEMO + RUTAS (si no hay líneas, crea una para que chofer y
--    control tengan algo que gestionar).
-- ---------------------------------------------------------------------------
insert into public.linea (nombre_linea, descripcion, activo)
select 'Línea 701 - Trufi', 'Trufi Cochabamba demo', true
where not exists (select 1 from public.linea where nombre_linea = 'Línea 701 - Trufi')
on conflict do nothing;

insert into public.ruta (id_linea, nombre_ruta, descripcion_trazado, activo)
select l.id_linea, 'Ruta Norte-Sur', 'Recorrido demo norte a sur', true
  from public.linea l
 where l.nombre_linea = 'Línea 701 - Trufi'
   and not exists (select 1 from public.ruta r where r.id_linea = l.id_linea and r.nombre_ruta = 'Ruta Norte-Sur')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 5. CHOFER: fila para chofer@trufi.cbba (vinculada a su persona).
-- ---------------------------------------------------------------------------
insert into public.chofer (id_persona, licencia, foto_url, activo)
select p.id_persona, 'CHOFER-DEMO-001', null, true
  from public.persona p
 where p.id_usuario = '7f2f170f-f2e2-4807-8182-8dee3fbb4dfa'
   and not exists (select 1 from public.chofer c where c.id_persona = p.id_persona)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 6. CONTROL: fila para control@trufi.cbba (vinculada a su persona y a la
--    línea demo).
-- ---------------------------------------------------------------------------
insert into public.control (id_persona, id_admin, id_linea, activo)
select p.id_persona, null, l.id_linea, true
  from public.persona p
  cross join public.linea l
 where p.id_usuario = '702b67ce-a97f-475e-aee2-9fba5021362e'
   and l.nombre_linea = 'Línea 701 - Trufi'
   and not exists (select 1 from public.control c where c.id_persona = p.id_persona)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 7. VEHÍCULO: asigna un vehículo al chofer demo, en la línea demo.
-- ---------------------------------------------------------------------------
insert into public.vehiculo (placa, foto_url, latitud, longitud, id_chofer, id_linea, activo)
select 'TRUFI-001', null, -17.3988354, -66.1626903, c.id_chofer, l.id_linea, true
  from public.chofer c
  cross join public.linea l
  cross join public.persona p
 where p.id_usuario = '7f2f170f-f2e2-4807-8182-8dee3fbb4dfa'
   and c.id_persona = p.id_persona
   and l.nombre_linea = 'Línea 701 - Trufi'
   and not exists (select 1 from public.vehiculo v where v.placa = 'TRUFI-001')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 8. Verificación (sólo muestra, no modifica).
-- ---------------------------------------------------------------------------
select 'perfiles' as tabla, id::text, role::text, full_name
  from public.profiles
 where id in (
  'a3cfe6ba-e942-467a-826d-55e50cb21b2d',
  '702b67ce-a97f-475e-aee2-9fba5021362e',
  '7f2f170f-f2e2-4807-8182-8dee3fbb4dfa',
  'fbfb8bf6-0fe5-4fca-929d-98eda04e1041'
 )
union all
select 'personas', id_usuario::text, nombre, ci
  from public.persona
 where id_usuario in (
  'a3cfe6ba-e942-467a-826d-55e50cb21b2d',
  '702b67ce-a97f-475e-aee2-9fba5021362e',
  '7f2f170f-f2e2-4807-8182-8dee3fbb4dfa',
  'fbfb8bf6-0fe5-4fca-929d-98eda04e1041'
 )
union all
select 'choferes', c.id_chofer::text, c.licencia, p.id_usuario
  from public.chofer c
  join public.persona p on p.id_persona = c.id_persona
 where p.id_usuario = '7f2f170f-f2e2-4807-8182-8dee3fbb4dfa'
union all
select 'controles', c.id_control::text, c.id_linea::text, p.id_usuario
  from public.control c
  join public.persona p on p.id_persona = c.id_persona
 where p.id_usuario = '702b67ce-a97f-475e-aee2-9fba5021362e'
union all
select 'vehiculos', v.id_vehiculo::text, v.placa, v.id_chofer::text
  from public.vehiculo v
 where v.placa = 'TRUFI-001';

-- =============================================================================
-- FIN.
-- =============================================================================
