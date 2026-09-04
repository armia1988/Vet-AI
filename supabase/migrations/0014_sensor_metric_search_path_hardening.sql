-- Vet AI V19 security hardening.
-- Pin the helper function search_path so object resolution cannot be changed by
-- a caller-controlled role/session search_path.

alter function private.sensor_metric_value(public.sensor_readings, text)
  set search_path = pg_catalog, public, private;
