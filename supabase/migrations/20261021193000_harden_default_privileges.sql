-- Stop overbroad default grants from reappearing on objects created by future migrations.
-- Existing objects retain their explicit, reviewed grants; this only affects future objects.
-- The public schema default ACL was observed on the connected project as:
-- tables/sequences/functions granted broadly to anon, authenticated, service_role.
-- Remove client access by default; new application objects must opt in explicitly.

-- PostgreSQL grants EXECUTE on newly created functions to PUBLIC unless changed.
-- Revoke globally so private-schema functions are also not executable by every database role.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;

-- Supabase's observed schema-specific defaults also give client roles access in public.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON TABLES FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON SEQUENCES FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;
