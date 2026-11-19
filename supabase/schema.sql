-- Roles y cuentas para Trufi. Ejecutar en el SQL Editor de Supabase.
-- Si ya aplicaste una version anterior, ejecuta supabase/roles_control_migration.sql.

create type public.app_role as enum ('cliente', 'transportista', 'control', 'admin');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role public.app_role not null default 'cliente',
  requested_role public.app_role,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Crea el perfil automaticamente al registrarse. Ignora cualquier "role"
-- que venga en los metadatos: el rol siempre empieza en 'cliente'.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''));
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- Recrea el perfil de cuentas que se registraron antes de existiera el trigger.
create or replace function public.ensure_profile()
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (auth.uid(), coalesce(auth.jwt() ->> 'full_name', ''))
  on conflict (id) do nothing;
  return (select * from public.profiles where id = auth.uid());
end;
$$;

grant execute on function public.ensure_profile() to authenticated;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'admin'
  );
$$;

create or replace function public.is_control()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'control'
  );
$$;

-- Administradores y control pueden decidir solicitudes de rol.
create or replace function public.can_manage_requests()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin() or public.is_control();
$$;

-- Lectura: cada usuario ve su perfil; admin y control ven todos (para gestionar solicitudes).
drop policy if exists "ver perfil propio o admin" on public.profiles;
drop policy if exists "ver perfil propio o admin o control" on public.profiles;
create policy "ver perfil propio o admin o control"
on public.profiles for select to authenticated
using (id = auth.uid() or public.is_admin() or public.is_control());

-- Escritura: solo el nombre y una solicitud de rol, y solo de transportista o control.
-- El campo "role" no se puede modificar desde el cliente (ver GRANT abajo).
drop policy if exists "editar perfil propio" on public.profiles;
create policy "editar perfil propio"
on public.profiles for update to authenticated
using (id = auth.uid())
with check (
  id = auth.uid()
  and (requested_role is null or requested_role in ('transportista', 'control'))
);

revoke update on public.profiles from authenticated;
grant update (full_name, requested_role) on public.profiles to authenticated;

-- Aprueba o rechaza solicitudes. Lo pueden hacer admin y control.
create or replace function public.decide_request(target uuid, approve boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.can_manage_requests() then
    raise exception 'Solo un administrador o control puede decidir solicitudes';
  end if;

  update public.profiles
     set role = case when approve then requested_role else role end,
         requested_role = null
   where id = target and requested_role is not null;
end;
$$;

revoke execute on function public.decide_request(uuid, boolean) from public, anon;
grant execute on function public.decide_request(uuid, boolean) to authenticated;

-- El admin elige una cuenta de cliente existente (por correo) y la transforma en control.
create or replace function public.promote_to_control(target uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Solo un administrador puede asignar el rol de control';
  end if;

  update public.profiles
     set role = 'control', requested_role = null
   where id = target and role = 'cliente';
end;
$$;

revoke execute on function public.promote_to_control(uuid) from public, anon;
grant execute on function public.promote_to_control(uuid) to authenticated;

-- Lista de clientes (con correo) para que el admin elija a quien promover.
create or replace function public.list_clients()
returns table (id uuid, full_name text, email text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Solo un administrador puede listar clientes';
  end if;

  return query
    select p.id, p.full_name, coalesce(u.email, '')
      from public.profiles p
      join auth.users u on u.id = p.id
     where p.role = 'cliente'
     order by p.full_name, u.email;
end;
$$;

revoke execute on function public.list_clients() from public, anon;
grant execute on function public.list_clients() to authenticated;

-- Lista de usuarios NO administradores para asignarles un rol desde el panel.
create or replace function public.list_users()
returns table (id uuid, full_name text, email text, role public.app_role)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Solo un administrador puede listar usuarios';
  end if;

  return query
    select p.id, p.full_name, coalesce(u.email, ''), p.role
      from public.profiles p
      join auth.users u on u.id = p.id
     where p.role <> 'admin'
     order by p.full_name, u.email;
end;
$$;

revoke execute on function public.list_users() from public, anon;
grant execute on function public.list_users() to authenticated;

-- Asigna cliente / transportista / control a un usuario. NUNCA administrador.
create or replace function public.admin_set_role(target uuid, new_role public.app_role)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Solo un administrador puede asignar roles';
  end if;

  if new_role = 'admin' then
    raise exception 'El rol de administrador no se asigna desde el panel';
  end if;

  -- El admin no puede quitarse su propio rol a si mismo.
  if target = auth.uid() then
    raise exception 'No puedes cambiar tu propio rol';
  end if;

  update public.profiles
     set role = new_role, requested_role = null
   where id = target and role <> 'admin';
end;
$$;

revoke execute on function public.admin_set_role(uuid, public.app_role) from public, anon;
grant execute on function public.admin_set_role(uuid, public.app_role) to authenticated;

-- Primer administrador: hacerlo a mano, una sola vez, con el UUID del usuario
-- (Authentication > Users en el panel de Supabase):
-- update public.profiles set role = 'admin' where id = '<uuid-del-admin>';
