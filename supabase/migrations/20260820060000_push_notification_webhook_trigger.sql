-- Calls the push-notifications Edge Function directly from a trigger via
-- pg_net, instead of a Supabase Dashboard Database Webhook — this project's
-- plan doesn't have the `supabase_functions` extension available, which
-- Database Webhooks depend on. `net.http_post` (pg_net) is the documented
-- fallback and is functionally identical: fires once per INSERT, fire-and-
-- forget, doesn't block the original insert if the HTTP call is slow.
--
-- IMPORTANT: replace the placeholder secret below with the real value of
-- the PUSH_WEBHOOK_SECRET Edge Function secret before applying this to any
-- project — never commit the real secret to git. Keep the two in sync;
-- if you rotate PUSH_WEBHOOK_SECRET, update this function to match (or
-- re-run this migration with the new value substituted in).

create extension if not exists pg_net;

create or replace function public.send_push_notification_event_webhook()
returns trigger
language plpgsql
set search_path = public, net, pg_temp
as $$
begin
  perform net.http_post(
    url := 'https://yweghwsgxstrdodjrvey.functions.supabase.co/push-notifications',
    body := jsonb_build_object(
      'type', TG_OP,
      'table', TG_TABLE_NAME,
      'schema', TG_TABLE_SCHEMA,
      'record', to_jsonb(new),
      'old_record', null
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-vanam-push-secret', '<REPLACE_WITH_PUSH_WEBHOOK_SECRET_VALUE>'
    ),
    timeout_milliseconds := 5000
  );

  return new;
end;
$$;

drop trigger if exists push_notification_events_webhook on public.push_notification_events;
create trigger push_notification_events_webhook
  after insert on public.push_notification_events
  for each row execute function public.send_push_notification_event_webhook();
