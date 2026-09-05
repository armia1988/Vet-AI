-- Vet AI V29: persist the production Orf/FMD image-differentiation guidance.
-- A single image is never treated as a definitive diagnosis. These signs only
-- improve differential ranking and preserve FMD as a serious rule-out when the
-- morphology/history is compatible.

with f as (
  select id, source_url from public.disease_catalog where slug = 'fmd'
)
insert into public.disease_signs
  (disease_id, phase, sign, visible_in_image, visible_in_video, sensor_detectable, source_url)
select
  f.id,
  'clinical',
  'High image suspicion for FMD requires compatible true vesicles or fresh erosions and should be strengthened by hypersalivation and/or interdigital or hoof lesions; thick proliferative crusted lip scabs alone are not high-image evidence for FMD.',
  true,
  true,
  false,
  f.source_url
from f
on conflict (disease_id, phase, sign) do nothing;

with o as (
  select id, source_url from public.disease_catalog where slug = 'orf'
)
insert into public.disease_signs
  (disease_id, phase, sign, visible_in_image, visible_in_video, sensor_detectable, source_url)
select
  o.id,
  'clinical',
  'In sheep or goats, thick proliferative crusts and adherent scabs around the lips or muzzle, especially without visible fluid-filled vesicles or foot lesions, strongly support Orf over FMD in the image differential.',
  true,
  true,
  false,
  o.source_url
from o
on conflict (disease_id, phase, sign) do nothing;
