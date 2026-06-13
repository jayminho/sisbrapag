-- Auto-expiry for stale deposits. Runs the expire-deposits edge function every 5 minutes.
-- Requires extensions pg_cron + pg_net (both enabled on the project).

create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule(
  'expire-deposits-5min',
  '*/5 * * * *',
  $$ select net.http_post(
       url := 'https://iiclntwwutsaoorbncfp.supabase.co/functions/v1/expire-deposits',
       headers := '{"Content-Type":"application/json"}'::jsonb,
       body := '{}'::jsonb
     ); $$
);

-- To inspect:  select * from cron.job where jobname = 'expire-deposits-5min';
-- To remove:   select cron.unschedule('expire-deposits-5min');
