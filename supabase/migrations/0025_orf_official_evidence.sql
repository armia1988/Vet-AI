-- Add Orf (contagious ecthyma / sore mouth) from authoritative public-health sources.
-- This closes an important sheep/goat differential gap that can otherwise over-rank FMD
-- when a photo shows thick proliferative scabs around the lips and muzzle.

insert into public.disease_catalog
(slug,display_name,animal_groups,agent_type,cause,zoonotic,reportable_or_listed,default_risk,isolation_guidance,lab_confirmation_required,source_org,source_url,source_reviewed_at,condition_type,body_systems,species_scope,preclinical_notes,diagnostics_summary,prevention_summary,epidemiology_summary,curation_status)
values
(
  'orf',
  'Orf (contagious ecthyma / sore mouth)',
  array['livestock']::public.animal_group[],
  'virus',
  'Orf virus (Parapoxvirus)',
  true,
  false,
  'orange',
  'Separate animals with active mouth or muzzle lesions from unaffected sheep/goats when practical. Wear gloves and avoid direct contact with lesions or scabs because Orf is zoonotic. Clean and disinfect shared equipment and obtain veterinary advice if feeding is impaired, lesions are extensive, or a serious reportable disease such as FMD cannot be excluded.',
  true,
  'CDC',
  'https://www.cdc.gov/orf-virus/about/orf-virus-in-animals.html',
  '2026-09-05',
  'disease',
  array['skin','oral'],
  array['sheep','lambs','goats','kids'],
  'Small papules or pustules can develop before the characteristic proliferative crusts become obvious.',
  'Clinical appearance is often strongly suggestive, but PCR or other veterinary laboratory testing can confirm infection when needed. Important look-alikes, especially foot-and-mouth disease in susceptible regions, must be excluded using the full clinical picture and official veterinary guidance.',
  'Reduce trauma to the lips and mouth, disinfect shared feeders/equipment, isolate newly introduced animals with suspicious lesions, use gloves, and discuss flock vaccination strategy with a veterinarian where Orf is established.',
  'A contagious parapoxvirus infection of sheep and goats. Lesions commonly occur around the lips, muzzle and mouth; scabs can remain infectious in the environment, and people can become infected after contact with lesions or contaminated equipment.',
  'reviewed'
)
on conflict (slug) do update set
  display_name=excluded.display_name,
  animal_groups=excluded.animal_groups,
  agent_type=excluded.agent_type,
  cause=excluded.cause,
  zoonotic=excluded.zoonotic,
  reportable_or_listed=excluded.reportable_or_listed,
  default_risk=excluded.default_risk,
  isolation_guidance=excluded.isolation_guidance,
  lab_confirmation_required=excluded.lab_confirmation_required,
  source_org=excluded.source_org,
  source_url=excluded.source_url,
  source_reviewed_at=excluded.source_reviewed_at,
  condition_type=excluded.condition_type,
  body_systems=excluded.body_systems,
  species_scope=excluded.species_scope,
  preclinical_notes=excluded.preclinical_notes,
  diagnostics_summary=excluded.diagnostics_summary,
  prevention_summary=excluded.prevention_summary,
  epidemiology_summary=excluded.epidemiology_summary,
  curation_status=excluded.curation_status;

with d as (
  select id, slug, source_url from public.disease_catalog where slug='orf'
)
insert into public.disease_signs(disease_id,phase,sign,visible_in_image,visible_in_video,sensor_detectable,source_url)
select d.id,x.phase,x.sign,x.img,x.vid,x.sensor,d.source_url
from d
join (values
  ('orf','early','Papules or pustules around the lips, muzzle or nostrils',true,true,false),
  ('orf','clinical','Thick proliferative scabs and crusted lesions around the lips and muzzle',true,true,false),
  ('orf','clinical','Crusted sores at the mouth that can interfere with suckling or feeding',true,true,true),
  ('orf','clinical','Lesions can also occur on teats or lower legs',true,true,false)
) as x(slug,phase,sign,img,vid,sensor) on x.slug=d.slug
on conflict (disease_id,phase,sign) do nothing;
