-- Roles y cuentas para Trufi. Ejecutar en el SQL Editor de Supabase.

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
-- La app lo llama al iniciar sesion si no encuentra la fila; asi evita un error
-- despues del login. Es 'security definer' para poder insertar aunque el usuario
-- autenticado no tenga permiso de INSERT.
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

-- Lectura: cada usuario ve su perfil; los administradores ven todos (para aprobar solicitudes).
create policy "ver perfil propio o admin"
on public.profiles for select to authenticated
using (id = auth.uid() or public.is_admin());

-- Escritura: solo el nombre y una solicitud de rol, y solo de transportista o control.
-- El campo "role" no se puede modificar desde el cliente (ver GRANT abajo).
create policy "editar perfil propio"
on public.profiles for update to authenticated
using (id = auth.uid())
with check (
  id = auth.uid()
  and (requested_role is null or requested_role in ('transportista', 'control'))
);

revoke update on public.profiles from authenticated;
grant update (full_name, requested_role) on public.profiles to authenticated;

-- Solo un administrador puede aprobar o rechazar una solicitud.
create or replace function public.decide_request(target uuid, approve boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Solo un administrador puede decidir solicitudes';
  end if;

  update public.profiles
     set role = case when approve then requested_role else role end,
         requested_role = null
   where id = target and requested_role is not null;
end;
$$;

revoke execute on function public.decide_request(uuid, boolean) from public, anon;
grant execute on function public.decide_request(uuid, boolean) to authenticated;

-- Primer administrador: hacerlo a mano, una sola vez, con el UUID del usuario
-- (Authentication > Users en el panel de Supabase):
-- update public.profiles set role = 'admin' where id = '<uuid-del-admin>';