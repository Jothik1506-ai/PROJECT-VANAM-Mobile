import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

type PushEvent = {
  id: string;
  sender_id: string;
  chat_type: 'family' | 'direct';
  group_id?: string | null;
  conversation_id?: string | null;
};

type ServiceAccount = {
  client_email: string;
  private_key: string;
  project_id: string;
};

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const webhookSecret = Deno.env.get('PUSH_WEBHOOK_SECRET') ?? '';
const serviceAccountJson = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON') ?? '';

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false },
});

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  if (webhookSecret) {
    const supplied = req.headers.get('x-vanam-push-secret') ?? '';
    if (supplied !== webhookSecret) return json({ error: 'Unauthorized' }, 401);
  }

  try {
    const body = await req.json();
    const event = normalizeEvent(body);
    if (!event) return json({ ok: true, skipped: 'No push event record' });

    await sendPushForEvent(event);
    await supabase
      .from('push_notification_events')
      .update({ processed_at: new Date().toISOString() })
      .eq('id', event.id);

    return json({ ok: true });
  } catch (error) {
    console.error(error);
    return json({ error: 'Push notification failed' }, 500);
  }
});

function normalizeEvent(body: Record<string, unknown>): PushEvent | null {
  const record = (body.record ?? body.new ?? body) as Record<string, unknown>;
  if (record.chat_type !== 'family' && record.chat_type !== 'direct') {
    return null;
  }
  const id = value(record.id);
  const senderId = value(record.sender_id);
  if (!id || !senderId) return null;
  return {
    id,
    sender_id: senderId,
    chat_type: record.chat_type,
    group_id: value(record.group_id),
    conversation_id: value(record.conversation_id),
  };
}

async function sendPushForEvent(event: PushEvent) {
  const senderName = await profileName(event.sender_id);
  const recipients = event.chat_type === 'family'
    ? await familyRecipients(event.sender_id)
    : await directRecipients(event);

  if (recipients.length === 0) return;

  const { data: tokens, error } = await supabase
    .from('push_tokens')
    .select('fcm_token, member_id')
    .in('member_id', recipients);
  if (error) throw error;

  const uniqueTokens = [
    ...new Set((tokens ?? []).map((row) => row.fcm_token).filter(Boolean)),
  ];
  if (uniqueTokens.length === 0) return;

  const title = event.chat_type === 'family'
    ? 'New message in Family Group'
    : `New message from ${senderName}`;

  const data = event.chat_type === 'family'
    ? {
      chat_type: 'family',
      group_id: event.group_id ?? 'family-group',
      sender_id: event.sender_id,
      sender_name: senderName,
    }
    : {
      chat_type: 'direct',
      conversation_id: event.conversation_id ?? '',
      sender_id: event.sender_id,
      sender_name: senderName,
    };

  await sendFcm(uniqueTokens, {
    title,
    body: 'Open Vanam to read it.',
    data,
  });
}

async function profileName(memberId: string): Promise<string> {
  const { data } = await supabase
    .from('profiles')
    .select('display_name')
    .eq('id', memberId)
    .maybeSingle();
  return data?.display_name ?? 'Family Member';
}

async function familyRecipients(senderId: string): Promise<string[]> {
  const { data, error } = await supabase
    .from('profiles')
    .select('id')
    .neq('id', senderId)
    .eq('status', 'active');
  if (error) throw error;
  return (data ?? []).map((row) => row.id);
}

async function directRecipients(event: PushEvent): Promise<string[]> {
  if (!event.conversation_id) return [];
  const { data, error } = await supabase
    .from('conversation_participants')
    .select('user_id')
    .eq('conversation_id', event.conversation_id)
    .neq('user_id', event.sender_id);
  if (error) throw error;
  return (data ?? []).map((row) => row.user_id);
}

async function sendFcm(
  tokens: string[],
  notification: {
    title: string;
    body: string;
    data: Record<string, string>;
  },
) {
  const account = JSON.parse(serviceAccountJson) as ServiceAccount;
  const accessToken = await accessTokenFor(account);
  const endpoint =
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`;

  for (const token of tokens) {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${accessToken}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          notification: {
            title: notification.title,
            body: notification.body,
          },
          data: notification.data,
          android: {
            priority: 'HIGH',
            notification: {
              channel_id: 'vanam_messages',
              // Matches AndroidManifest.xml's default_notification_icon —
              // set explicitly here too rather than relying solely on the
              // manifest default, since FCM sometimes needs it per-message
              // to reliably override the OS's fallback bell icon.
              icon: 'ic_stat_vanam',
            },
          },
        },
      }),
    });

    if (!response.ok) {
      console.error('FCM send failed', response.status, await response.text());
    }
  }
}

async function accessTokenFor(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claim = {
    iss: account.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${base64url(JSON.stringify(header))}.${
    base64url(JSON.stringify(claim))
  }`;
  const signature = await sign(unsigned, account.private_key);

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${signature}`,
    }),
  });
  if (!response.ok) throw new Error(await response.text());
  const jsonBody = await response.json();
  return jsonBody.access_token;
}

async function sign(input: string, privateKeyPem: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(privateKeyPem),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(input),
  );
  return base64url(signature);
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s+/g, '');
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

function base64url(input: string | ArrayBuffer): string {
  const bytes = typeof input === 'string'
    ? new TextEncoder().encode(input)
    : new Uint8Array(input);
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function value(input: unknown): string | null {
  return typeof input === 'string' && input.trim().length > 0
    ? input.trim()
    : null;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}
