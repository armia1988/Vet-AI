-- Vet AI reviewed veterinary knowledge expansion. Applied to production on 2026-09-04.
-- This deliberately remains source-reviewed rather than claiming exhaustive world coverage.

alter table public.disease_catalog
  add column if not exists condition_type text not null default 'disease',
  add column if not exists body_systems text[] not null default '{}',
  add column if not exists species_scope text[] not null default '{}',
  add column if not exists preclinical_notes text,
  add column if not exists diagnostics_summary text,
  add column if not exists prevention_summary text,
  add column if not exists epidemiology_summary text,
  add column if not exists curation_status text not null default 'reviewed';

alter table public.disease_signs drop constraint if exists disease_signs_phase_check;
alter table public.disease_signs add constraint disease_signs_phase_check
  check (phase in ('preclinical','early','clinical','severe','recovery'));

insert into public.disease_catalog
(slug,display_name,animal_groups,agent_type,cause,zoonotic,reportable_or_listed,default_risk,isolation_guidance,lab_confirmation_required,source_org,source_url,source_reviewed_at,condition_type,body_systems,species_scope,preclinical_notes,diagnostics_summary,prevention_summary,epidemiology_summary,curation_status)
values
('brucellosis','Brucellosis',array['livestock']::public.animal_group[],'bacterium','Brucella spp.',true,true,'red','Separate animals associated with abortion or reproductive losses, restrict contact with birth fluids/placentae, and contact veterinary and competent authorities.',true,'WOAH','https://www.woah.org/en/disease/brucellosis/','2026-09-04','disease',array['reproductive','systemic'],array['cattle','sheep','goats','buffalo'],'Animals may show few signs before abortion or reproductive failure.','Confirmation requires prescribed laboratory testing such as serology and organism detection/isolation interpreted with epidemiology.','Control relies on surveillance, vaccination where appropriate, movement control, biosecurity and official eradication programs.','Contagious livestock disease and important zoonosis; abortion materials and raw milk are important exposure routes.','reviewed'),
('bluetongue','Bluetongue',array['livestock']::public.animal_group[],'virus','Bluetongue virus',false,true,'red','Reduce animal movement, protect susceptible ruminants from biting midges when feasible, and seek veterinary/official guidance.',true,'WOAH','https://www.woah.org/en/disease/bluetongue/','2026-09-04','disease',array['vascular','oral','respiratory','musculoskeletal'],array['sheep','goats','cattle','buffalo'],'Many infections, especially in cattle and goats, may be inapparent before clinical disease.','Laboratory confirmation is required; molecular/virological and serological methods are used in context.','Vaccination matched to relevant strains, vector control and surveillance are key measures.','Vector-borne disease transmitted mainly by Culicoides biting midges; not a public-health risk.','reviewed'),
('lumpy-skin-disease','Lumpy skin disease',array['livestock']::public.animal_group[],'virus','Lumpy skin disease virus (Capripoxvirus)',false,true,'red','Restrict movement of affected cattle/buffalo, strengthen vector control and contact veterinary/competent authorities.',true,'WOAH','https://www.woah.org/en/disease/lumpy-skin-disease/','2026-09-04','disease',array['skin','lymphatic','systemic','reproductive'],array['cattle','water buffalo'],'Fever can precede characteristic skin nodules.','Diagnosis requires veterinary assessment and confirmatory laboratory testing under official guidance.','Vaccination, surveillance, movement controls and arthropod-vector control are important prevention tools.','Primarily affects cattle and water buffalo and is transmitted predominantly by blood-feeding arthropods.','reviewed'),
('bovine-respiratory-disease-complex','Bovine respiratory disease complex',array['livestock']::public.animal_group[],'multifactorial','Complex interaction of host, environment and respiratory pathogens',false,false,'orange','Separate clearly ill animals when practical, improve ventilation/stressors and arrange prompt veterinary evaluation.',true,'Merck Veterinary Manual','https://www.merckvetmanual.com/respiratory-system/bovine-respiratory-disease-complex/overview-of-bovine-respiratory-disease-complex','2026-09-04','disease_complex',array['respiratory','systemic'],array['cattle','calves'],'Reduced feed intake, depression or fever may precede obvious respiratory signs.','Diagnosis combines history, examination and, when indicated, pathogen testing and further diagnostics.','Reduce transport/crowding stress, optimize ventilation, vaccination strategy and herd management.','Multifactorial respiratory disease strongly influenced by stress, environment, immunity and coinfection.','reviewed'),
('mastitis-cattle','Mastitis in cattle',array['livestock']::public.animal_group[],'multifactorial','Inflammation of mammary gland, most often due to intramammary infection',false,false,'orange','Use hygienic milking/biosecurity, segregate milk from affected quarters as directed locally, and seek veterinary assessment for systemic illness.',true,'Merck Veterinary Manual','https://www.merckvetmanual.com/reproductive-system/mastitis-in-large-animals/mastitis-in-cattle','2026-09-04','inflammatory_condition',array['mammary','systemic'],array['dairy cattle'],'Subclinical mastitis may show no visible inflammation; falling milk yield or increased somatic cell count can precede clinical signs.','Milk examination/culture and herd somatic-cell monitoring help determine infection and etiology.','Hygienic milking routines, teat antisepsis, clean dry bedding and herd monitoring reduce risk.','Pathogens may be contagious or environmental; severity ranges from subclinical to systemic disease.','reviewed'),
('poultry-coccidiosis','Coccidiosis in poultry',array['poultry']::public.animal_group[],'protozoa','Eimeria spp. and related coccidia',false,false,'orange','Reduce litter/feed/water contamination, review flock hygiene and obtain veterinary evaluation when diarrhea, weight loss or mortality rises.',true,'Merck Veterinary Manual','https://www.merckvetmanual.com/poultry/coccidiosis-in-poultry/coccidiosis-in-poultry','2026-09-04','disease',array['gastrointestinal','systemic'],array['chickens','turkeys','game birds'],'Reduced feed/water intake and poor growth may occur before severe diarrhea or mortality.','Diagnosis uses flock history, lesion pattern, fecal/oocyst examination and necropsy findings.','Prevention relies on vaccination and/or approved anticoccidial programs plus management that limits heavy exposure.','Worldwide enteric protozoal disease; clinical severity depends on species, exposure burden, age, immunity and concurrent disease.','reviewed'),
('infectious-bronchitis-chickens','Infectious bronchitis in chickens',array['poultry']::public.animal_group[],'virus','Infectious bronchitis virus (avian gammacoronavirus)',false,false,'orange','Separate affected groups where practical, tighten biosecurity and obtain veterinary testing because respiratory signs overlap with other important diseases.',true,'Merck Veterinary Manual','https://www.merckvetmanual.com/poultry/infectious-bronchitis/infectious-bronchitis-in-chickens','2026-09-04','disease',array['respiratory','renal','reproductive'],array['chickens'],'Incubation is short; reduced feed intake and huddling may accompany or precede obvious respiratory disease.','Laboratory confirmation commonly uses RT-PCR/RT-qPCR, sequencing and/or serology in context.','Vaccination and biosecurity are central; circulating antigenic types matter for vaccine choice.','Acute highly contagious chicken disease spread through respiratory/fecal routes and contaminated equipment.','reviewed'),
('infectious-bursal-disease','Infectious bursal disease (Gumboro)',array['poultry']::public.animal_group[],'virus','Infectious bursal disease virus',false,false,'orange','Strengthen flock biosecurity and seek veterinary diagnostic support, especially with young birds and rising morbidity/mortality.',true,'Merck Veterinary Manual','https://www.merckvetmanual.com/poultry/infectious-bursal-disease/infectious-bursal-disease-in-poultry','2026-09-04','disease',array['immune','gastrointestinal','systemic'],array['young chickens'],'Early/subclinical infection can cause important immunosuppression before obvious clinical disease.','Diagnosis combines bursal lesions with molecular detection/characterization of viral RNA and, when needed, virus isolation.','Vaccination programs and biosecurity are the main control measures.','Highly contagious disease of young chickens; virulence and maternal immunity strongly affect outcomes.','reviewed'),
('canine-leptospirosis','Leptospirosis in dogs',array['dogs']::public.animal_group[],'bacterium','Pathogenic Leptospira spp.',true,false,'orange','Limit contact with urine/body fluids, use hygiene precautions and obtain urgent veterinary assessment because kidney, liver or respiratory failure can occur.',true,'Merck Veterinary Manual','https://www.merckvetmanual.com/infectious-diseases/leptospirosis/leptospirosis-in-dogs','2026-09-04','disease',array['renal','hepatic','respiratory','systemic'],array['dogs'],'Mild or subclinical infection is possible; lethargy and anorexia can precede organ-specific signs.','Diagnosis generally combines serology with PCR/organism detection, interpreted with vaccination and clinical history.','Vaccination, reducing exposure to contaminated urine/water and hygiene precautions reduce risk.','Worldwide zoonotic infection with variable clinical presentations and environmental/wildlife reservoirs.','reviewed'),
('canine-pyometra','Pyometra in dogs',array['dogs']::public.animal_group[],'bacterial','Uterine bacterial infection associated with hormonal changes in intact females',false,false,'red','Seek urgent veterinary assessment; closed-cervix disease may have no discharge and can progress rapidly to shock or uterine rupture.',true,'Merck Veterinary Manual','https://www.merckvetmanual.com/dog-owners/reproductive-disorders-of-dogs/reproductive-disorders-of-female-dogs','2026-09-04','disease',array['reproductive','systemic'],array['intact female dogs'],'Lethargy, poor appetite or increased thirst/urination may occur before obvious discharge or abdominal enlargement.','Diagnosis uses history/examination, imaging and laboratory testing.','Spaying prevents pyometra in dogs not intended for breeding.','Typically occurs after estrus in intact females and may be open- or closed-cervix.','reviewed'),
('anemia-syndrome','Anemia syndrome',array['livestock','dogs']::public.animal_group[],'syndrome','Reduced red blood cell mass/hemoglobin/packed cell volume from blood loss, destruction or inadequate production',false,false,'orange','Treat anemia as a sign requiring cause-finding; severe weakness, collapse, breathing difficulty or circulatory compromise needs urgent veterinary care.',true,'Merck Veterinary Manual','https://www.merckvetmanual.com/circulatory-system/anemia/overview-of-anemia-in-animals','2026-09-04','syndrome',array['hematologic','cardiovascular','systemic'],array['mammals'],'Chronic anemia may first appear as reduced activity, performance or appetite before obvious pallor.','CBC/PCV and additional testing are required to confirm anemia and identify the underlying cause.','Prevention depends on the underlying cause, including parasite control, nutrition, toxin avoidance and management of chronic disease.','Anemia is a clinical syndrome/sign, not a single diagnosis; causes include blood loss, hemolysis and reduced red-cell production.','reviewed')
on conflict (slug) do update set
  display_name=excluded.display_name,
  condition_type=excluded.condition_type,
  body_systems=excluded.body_systems,
  species_scope=excluded.species_scope,
  preclinical_notes=excluded.preclinical_notes,
  diagnostics_summary=excluded.diagnostics_summary,
  prevention_summary=excluded.prevention_summary,
  epidemiology_summary=excluded.epidemiology_summary,
  source_reviewed_at=excluded.source_reviewed_at,
  curation_status=excluded.curation_status;

with d as (select id,slug,source_url from public.disease_catalog)
insert into public.disease_signs(disease_id,phase,sign,visible_in_image,visible_in_video,sensor_detectable,source_url)
select d.id,x.phase,x.sign,x.img,x.vid,x.sensor,d.source_url
from d join (values
('brucellosis','preclinical','Few or no obvious signs before reproductive failure',false,false,false),
('brucellosis','clinical','Abortion, stillbirth or weak offspring',false,true,true),
('brucellosis','clinical','Retained placenta or infertility',false,false,true),
('brucellosis','clinical','Testicular swelling in males',true,true,false),
('bluetongue','early','Fever and depression',false,true,true),
('bluetongue','clinical','Oral/nasal ulceration, salivation or facial swelling',true,true,false),
('bluetongue','clinical','Coronary-band inflammation and lameness',true,true,true),
('bluetongue','clinical','Cyanosis of tongue can occur but is uncommon',true,false,false),
('lumpy-skin-disease','early','Fever before skin nodules',false,true,true),
('lumpy-skin-disease','clinical','Multiple firm skin papules or nodules',true,true,false),
('lumpy-skin-disease','clinical','Enlarged superficial lymph nodes or limb/udder oedema',true,true,false),
('lumpy-skin-disease','clinical','Marked reduction in milk yield',false,false,true),
('bovine-respiratory-disease-complex','early','Reduced feed intake, depression or fever',false,true,true),
('bovine-respiratory-disease-complex','clinical','Cough, nasal discharge or increased respiratory effort',true,true,true),
('bovine-respiratory-disease-complex','severe','Marked dyspnoea, weakness or rapid deterioration',false,true,true),
('mastitis-cattle','preclinical','Reduced milk yield or increased somatic cell count without obvious local inflammation',false,false,true),
('mastitis-cattle','clinical','Abnormal milk with clots, discoloration or watery secretion',true,true,false),
('mastitis-cattle','clinical','Udder swelling, heat, pain or redness',true,true,false),
('mastitis-cattle','severe','Fever, anorexia, weakness or shock with severe mastitis',false,true,true),
('poultry-coccidiosis','early','Reduced feed/water intake or poor growth',false,true,true),
('poultry-coccidiosis','clinical','Diarrhoea, weight loss, lethargy or ruffled feathers',true,true,true),
('poultry-coccidiosis','severe','Rapidly rising morbidity or mortality',false,false,true),
('infectious-bronchitis-chickens','early','Huddling, reduced feed intake, coughing or sneezing',false,true,true),
('infectious-bronchitis-chickens','clinical','Tracheal rales, conjunctivitis or dyspnoea',true,true,true),
('infectious-bronchitis-chickens','clinical','Drop in egg production or abnormal egg shells',true,true,true),
('infectious-bursal-disease','preclinical','Subclinical immunosuppression in young birds',false,false,true),
('infectious-bursal-disease','clinical','Listlessness, watery diarrhoea, ruffled feathers or dehydration',true,true,true),
('infectious-bursal-disease','severe','High morbidity with strain-dependent mortality',false,false,true),
('canine-leptospirosis','early','Lethargy, anorexia, vomiting or abdominal discomfort',false,true,true),
('canine-leptospirosis','clinical','Changes in urination consistent with kidney injury',false,true,true),
('canine-leptospirosis','clinical','Jaundice or respiratory disease can occur',true,true,true),
('canine-pyometra','early','Lethargy, reduced appetite, increased thirst or urination',false,true,true),
('canine-pyometra','clinical','Purulent or blood-tinged vaginal discharge when cervix is open',true,true,false),
('canine-pyometra','clinical','Abdominal enlargement may occur when cervix is closed',true,true,false),
('canine-pyometra','severe','Collapse or shock',false,true,true),
('anemia-syndrome','preclinical','Reduced activity, exercise tolerance, growth or production',false,true,true),
('anemia-syndrome','clinical','Pale mucous membranes',true,true,false),
('anemia-syndrome','clinical','Weakness, lethargy, anorexia or increased heart rate',false,true,true),
('anemia-syndrome','severe','Collapse, hypotension or shock with acute severe anemia',false,true,true)
) as x(slug,phase,sign,img,vid,sensor) on x.slug=d.slug
on conflict (disease_id,phase,sign) do nothing;
