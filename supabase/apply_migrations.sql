-- Migra todo lo necesario para la pestaña Roles del panel administrativo.
-- Seguro de ejecutar mas de una vez. Pegar COMPLETO en el SQL Editor y Run.

-- 1) Control + transformar clientes en control + listar clientes.
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

create or replace function public.can_manage_requests()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin() or public.is_control();
$$;

drop policy if exists "ver perfil propio o admin" on public.profiles;
drop policy if exists "ver perfil propio o admin o control" on public.profiles;
create policy "ver perfil propio o admin o control"
on public.profiles for select to authenticated
using (id = auth.uid() or public.is_admin() or public.is_control());

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

-- 2) Asignacion de roles desde el panel (sin administrador).
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

notify pgrst, 'reload schema';
