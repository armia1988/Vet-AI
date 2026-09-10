-- Vet AI V67 — distinguish WebRTC endpoints even when two devices/tabs use the same auth account.

alter table public.support_webrtc_signals
  add column if not exists sender_role text,
  add column if not exists sender_client_id text;

create index if not exists support_webrtc_signals_call_created_idx
  on public.support_webrtc_signals(call_id, created_at);

comment on column public.support_webrtc_signals.sender_client_id is
  'Ephemeral per-call endpoint identifier so two Vet AI clients using the same auth account can still exchange WebRTC signaling safely.';
