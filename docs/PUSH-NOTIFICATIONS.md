# Vanam Push Notifications

Android-first OS notifications for encrypted Vanam chat.

## Privacy rule

Messages are end-to-end encrypted. Push payloads must never include message
content, ciphertext, private keys, recovery codes, or key wraps.

Allowed payload fields:

- `chat_type`
- `group_id`
- `conversation_id`
- `sender_id`
- `sender_name`

Notification text:

- Family group: `New message in Family Group`
- Direct chat: `New message from <sender_name>`

## Firebase setup

1. Create a Firebase project.
2. Add Android app:
   `in.aivafreelancia.vanam.vanam_mobile`
3. Download `google-services.json`.
4. Put it here:
   `apps/mobile/android/app/google-services.json`

Do not commit Firebase service account private keys. The Android
`google-services.json` is not a service account key; it is required for FCM.

## Supabase setup

Apply:

```text
supabase/migrations/20260820050000_push_notifications.sql
```

Deploy the Edge Function:

```bash
supabase functions deploy push-notifications
```

Set Edge Function secrets:

```bash
supabase secrets set FCM_SERVICE_ACCOUNT_JSON='<firebase service account json>'
supabase secrets set PUSH_WEBHOOK_SECRET='<long random secret>'
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided by Supabase.

## Database Webhook

Create a Supabase Database Webhook:

- Table: `push_notification_events`
- Event: `INSERT`
- Method: `POST`
- URL:
  `https://<project-ref>.functions.supabase.co/push-notifications`
- Header:
  `x-vanam-push-secret: <same PUSH_WEBHOOK_SECRET>`

The `messages` and `direct_messages` triggers enqueue metadata-only events into
`push_notification_events`. The Edge Function resolves recipients and sends FCM.

## Verification

1. Install a build with `google-services.json` included.
2. Sign into two different real Vanam accounts on two Android devices.
3. Put one device in the background.
4. Send a Family Group message from the other device.
5. Confirm the backgrounded device receives:
   `New message in Family Group`
6. Send a direct message.
7. Confirm the notification says:
   `New message from <sender_name>`
8. Tap each notification and confirm it opens the correct chat.
