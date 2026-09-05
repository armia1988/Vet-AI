-- Vet AI V30 global disease index.
-- IMPORTANT: imported/indexed entries are provenance-backed but are NOT eligible for AI diagnosis
-- until curation_status is promoted to 'reviewed' after signs, diagnostics, prevention and management are verified.

insert into public.veterinary_sources (organization, source_type, authority_level, geographic_scope, base_url, active)
select * from (values
  ('Australia DAFF','national notifiable animal disease authority','government','Australia','https://www.agriculture.gov.au/biosecurity-trade/pests-diseases-weeds/animal/notifiable',true),
  ('Japan MAFF','monitored livestock infectious diseases authority','government','Japan','https://www.maff.go.jp/e/policies/ap_health/animal/',true),
  ('China MARA','national animal disease catalogue authority','government','China','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',true),
  ('US CDC','zoonotic disease public health authority','government','United States','https://www.cdc.gov/healthy-pets/about/index.html',true)
) v(organization,source_type,authority_level,geographic_scope,base_url,active)
where not exists (select 1 from public.veterinary_sources s where s.organization=v.organization);

with seed(slug,display_name,groups,species,source_org,source_url,reportable) as (values
('anthrax','Anthrax',array['livestock'],array['cattle','sheep','goats','buffalo','camels'],'WOAH','https://www.woah.org/en/disease/anthrax/',true),
('q-fever','Q fever (Coxiellosis)',array['livestock'],array['cattle','sheep','goats'],'WOAH','https://www.woah.org/en/disease/q-fever/',true),
('epizootic-haemorrhagic-disease','Epizootic haemorrhagic disease',array['livestock'],array['cattle','ruminants'],'WOAH','https://www.woah.org/en/disease/epizootic-haemorrhagic-disease/',true),
('rift-valley-fever','Rift Valley fever',array['livestock'],array['cattle','sheep','goats','buffalo','camels'],'WOAH','https://www.woah.org/en/disease/rift-valley-fever/',true),
('bovine-tuberculosis','Bovine tuberculosis',array['livestock'],array['cattle','buffalo','goats'],'USDA APHIS','https://www.aphis.usda.gov/livestock-poultry-disease/bovine-tuberculosis',true),
('paratuberculosis-johnes','Paratuberculosis (Johne’s disease)',array['livestock'],array['cattle','sheep','goats','buffalo'],'USDA APHIS','https://www.aphis.usda.gov/livestock-poultry-disease/johnes-disease',true),
('bovine-anaplasmosis','Bovine anaplasmosis',array['livestock'],array['cattle','buffalo'],'WOAH','https://www.woah.org/en/disease/bovine-anaplasmosis/',true),
('bovine-babesiosis','Bovine babesiosis',array['livestock'],array['cattle','buffalo'],'WOAH','https://www.woah.org/en/disease/bovine-babesiosis/',true),
('bovine-genital-campylobacteriosis','Bovine genital campylobacteriosis',array['livestock'],array['cattle'],'WOAH','https://www.woah.org/en/disease/bovine-genital-campylobacteriosis/',true),
('bse','Bovine spongiform encephalopathy',array['livestock'],array['cattle'],'WOAH','https://www.woah.org/en/disease/bovine-spongiform-encephalopathy/',true),
('enzootic-bovine-leukosis','Enzootic bovine leukosis',array['livestock'],array['cattle','buffalo'],'WOAH','https://www.woah.org/en/disease/enzootic-bovine-leukosis/',true),
('haemorrhagic-septicaemia','Haemorrhagic septicaemia',array['livestock'],array['cattle','buffalo'],'WOAH','https://www.woah.org/en/disease/haemorrhagic-septicaemia/',true),
('bovine-viral-diarrhoea','Bovine viral diarrhoea / pestivirus infection',array['livestock'],array['cattle','buffalo'],'Japan MAFF','https://www.maff.go.jp/aqs/hou/42.html',true),
('contagious-bovine-pleuropneumonia','Contagious bovine pleuropneumonia',array['livestock'],array['cattle','buffalo'],'WOAH','https://www.woah.org/en/disease/contagious-bovine-pleuropneumonia/',true),
('bovine-theileriosis','Bovine theileriosis',array['livestock'],array['cattle','buffalo'],'WOAH','https://www.woah.org/en/disease/theileriosis/',true),
('infectious-bovine-rhinotracheitis','Infectious bovine rhinotracheitis / IPV',array['livestock'],array['cattle','buffalo'],'WOAH','https://www.woah.org/en/disease/infectious-bovine-rhinotracheitis-infectious-pustular-vulvovaginitis/',true),
('bovine-trichomonosis','Bovine trichomonosis',array['livestock'],array['cattle'],'WOAH','https://www.woah.org/en/disease/trichomonosis/',true),
('malignant-catarrhal-fever','Malignant catarrhal fever',array['livestock'],array['cattle','buffalo','sheep','deer'],'Australia DAFF','https://www.agriculture.gov.au/biosecurity-trade/pests-diseases-weeds/animal/notifiable',true),
('bovine-ephemeral-fever','Bovine ephemeral fever',array['livestock'],array['cattle','buffalo'],'Japan MAFF','https://www.maff.go.jp/aqs/hou/42.html',true),
('bovine-coronavirus','Bovine coronavirus infection',array['livestock'],array['cattle','calves'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('akabane-disease','Akabane disease',array['livestock'],array['cattle','buffalo','sheep','goats'],'Japan MAFF','https://www.maff.go.jp/aqs/hou/42.html',true),
('contagious-agalactia','Contagious agalactia',array['livestock'],array['sheep','goats'],'WOAH','https://www.woah.org/en/disease/contagious-agalactia/',true),
('contagious-caprine-pleuropneumonia','Contagious caprine pleuropneumonia',array['livestock'],array['goats'],'WOAH','https://www.woah.org/en/disease/contagious-caprine-pleuropneumonia/',true),
('chlamydia-abortus','Enzootic abortion of ewes (Chlamydia abortus)',array['livestock'],array['sheep','goats'],'WOAH','https://www.woah.org/en/disease/enzootic-abortion-of-ewes-ovine-chlamydiosis/',true),
('caprine-arthritis-encephalitis','Caprine arthritis encephalitis',array['livestock'],array['goats'],'WOAH','https://www.woah.org/en/disease/caprine-arthritis-encephalitis/',true),
('maedi-visna','Maedi-visna',array['livestock'],array['sheep'],'WOAH','https://www.woah.org/en/disease/maedi-visna/',true),
('ovine-pulmonary-adenomatosis','Ovine pulmonary adenomatosis',array['livestock'],array['sheep'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('caseous-lymphadenitis','Caseous lymphadenitis',array['livestock'],array['sheep','goats'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('scrapie','Scrapie',array['livestock'],array['sheep','goats'],'USDA APHIS','https://www.aphis.usda.gov/livestock-poultry-disease/scrapie',true),
('sheep-goat-pox','Sheep pox and goat pox',array['livestock'],array['sheep','goats'],'WOAH','https://www.woah.org/en/disease/sheep-pox-and-goat-pox/',true),
('brucella-ovis-epididymitis','Ovine epididymitis (Brucella ovis)',array['livestock'],array['sheep'],'WOAH','https://www.woah.org/en/disease/ovine-epididymitis-brucella-ovis/',true),
('salmonella-abortusovis','Salmonella Abortusovis infection',array['livestock'],array['sheep'],'WOAH','https://www.woah.org/en/disease/salmonellosis-s-abortusovis/',true),
('vesicular-stomatitis','Vesicular stomatitis',array['livestock'],array['cattle','buffalo'],'USDA APHIS','https://www.aphis.usda.gov/livestock-poultry-disease/vesicular-stomatitis',true),
('leptospirosis-livestock','Leptospirosis in livestock',array['livestock'],array['cattle','sheep','goats','buffalo'],'Japan MAFF','https://www.maff.go.jp/aqs/hou/42.html',true),
('listeriosis-ruminants','Listeriosis in ruminants',array['livestock'],array['cattle','sheep','goats'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('clostridial-enterotoxemia','Clostridial enterotoxemia',array['livestock'],array['sheep','goats','cattle'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('blackleg','Blackleg / black quarter',array['livestock'],array['cattle','sheep','goats'],'Japan MAFF','https://www.maff.go.jp/aqs/hou/42.html',true),
('tetanus-livestock','Tetanus in livestock',array['livestock'],array['cattle','sheep','goats','buffalo'],'Japan MAFF','https://www.maff.go.jp/aqs/hou/42.html',true),
('pasteurellosis-ruminants','Pasteurellosis in ruminants',array['livestock'],array['cattle','sheep','goats'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('mannheimiosis-ruminants','Mannheimiosis in ruminants',array['livestock'],array['cattle','sheep','goats'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('cryptosporidiosis-ruminants','Cryptosporidiosis in ruminants',array['livestock'],array['calves','lambs','kids'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('haemonchosis','Haemonchosis',array['livestock'],array['sheep','goats'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('fasciolosis','Fasciolosis (liver fluke disease)',array['livestock'],array['cattle','sheep','goats','buffalo'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('toxoplasmosis-ruminants','Toxoplasmosis in small ruminants',array['livestock'],array['sheep','goats'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('surra','Surra (Trypanosoma evansi infection)',array['livestock'],array['camels','cattle','buffalo'],'WOAH','https://www.woah.org/en/disease/surra/',true),
('camelpox','Camelpox',array['livestock'],array['camels'],'USDA APHIS','https://www.aphis.usda.gov/animal-product-import/organisms-vectors/livestock-poultry-pathogens',false),
('avian-chlamydiosis','Avian chlamydiosis',array['poultry'],array['chickens','turkeys','ducks','geese'],'WOAH','https://www.woah.org/en/disease/avian-chlamydiosis/',true),
('infectious-laryngotracheitis','Infectious laryngotracheitis',array['poultry'],array['chickens'],'WOAH','https://www.woah.org/en/disease/infectious-laryngotracheitis/',true),
('fowl-typhoid','Fowl typhoid',array['poultry'],array['chickens','turkeys'],'WOAH','https://www.woah.org/en/disease/fowl-typhoid-and-pullorum-disease/',true),
('pullorum-disease','Pullorum disease',array['poultry'],array['chickens','turkeys','chicks'],'WOAH','https://www.woah.org/en/disease/fowl-typhoid-and-pullorum-disease/',true),
('mycoplasma-gallisepticum','Mycoplasma gallisepticum infection',array['poultry'],array['chickens','turkeys'],'WOAH','https://www.woah.org/en/disease/avian-mycoplasmosis-mycoplasma-gallisepticum/',true),
('mycoplasma-synoviae','Mycoplasma synoviae infection',array['poultry'],array['chickens','turkeys'],'WOAH','https://www.woah.org/en/disease/avian-mycoplasmosis-mycoplasma-synoviae/',true),
('duck-viral-hepatitis','Duck viral hepatitis',array['poultry'],array['ducklings','ducks'],'WOAH','https://www.woah.org/en/disease/duck-virus-hepatitis/',true),
('avian-metapneumovirus','Avian metapneumovirus / turkey rhinotracheitis',array['poultry'],array['turkeys','chickens'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('avian-tuberculosis','Avian tuberculosis',array['poultry'],array['chickens','turkeys','birds'],'WOAH','https://www.woah.org/en/disease/avian-tuberculosis/',true),
('salmonella-enteritidis-poultry','Salmonella Enteritidis infection in poultry',array['poultry'],array['chickens','layers','breeders'],'WOAH','https://www.woah.org/en/disease/salmonellosis/',true),
('mareks-disease','Marek’s disease',array['poultry'],array['chickens'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('fowlpox','Fowlpox',array['poultry'],array['chickens','turkeys'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('infectious-coryza','Infectious coryza',array['poultry'],array['chickens'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('avian-leukosis','Avian leukosis',array['poultry'],array['chickens'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('reticuloendotheliosis','Reticuloendotheliosis',array['poultry'],array['chickens','turkeys'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('avian-reovirus-arthritis','Avian viral arthritis / reovirus infection',array['poultry'],array['chickens','turkeys'],'USDA APHIS','https://www.aphis.usda.gov/animal-product-import/organisms-vectors/livestock-poultry-pathogens',false),
('avian-encephalomyelitis','Avian encephalomyelitis',array['poultry'],array['chickens','chicks','turkeys'],'USDA APHIS','https://www.aphis.usda.gov/animal-product-import/organisms-vectors/livestock-poultry-pathogens',false),
('avian-adenovirus','Avian adenovirus infection',array['poultry'],array['chickens','turkeys'],'USDA APHIS','https://www.aphis.usda.gov/animal-product-import/organisms-vectors/livestock-poultry-pathogens',false),
('chicken-infectious-anemia','Chicken infectious anemia',array['poultry'],array['chickens','chicks'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('poultry-red-mite','Poultry red mite infestation',array['poultry'],array['chickens','layers'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('necrotic-enteritis-poultry','Necrotic enteritis in poultry',array['poultry'],array['chickens','broilers'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('riemerella-duck-septicemia','Riemerella anatipestifer infection / duck septicemia',array['poultry'],array['ducks','ducklings'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('low-path-avian-influenza','Low pathogenic avian influenza',array['poultry'],array['chickens','turkeys','ducks','geese'],'Japan MAFF','https://www.maff.go.jp/e/policies/ap_health/animal/',true),
('aspergillosis-poultry','Aspergillosis in poultry',array['poultry'],array['chickens','chicks','turkeys','ducks'],'USDA APHIS','https://www.aphis.usda.gov/animal-product-import/organisms-vectors/livestock-poultry-pathogens',false),
('colibacillosis-poultry','Avian colibacillosis',array['poultry'],array['chickens','chicks','turkeys'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('salmonellosis-poultry','Salmonellosis in poultry',array['poultry'],array['chickens','chicks','turkeys','ducks'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('fowl-cholera','Fowl cholera',array['poultry'],array['chickens','turkeys','ducks'],'Japan MAFF','https://www.maff.go.jp/e/policies/ap_health/animal/',true),
('avian-nephritis','Avian nephritis virus infection',array['poultry'],array['chickens','chicks'],'USDA APHIS','https://www.aphis.usda.gov/animal-product-import/organisms-vectors/livestock-poultry-pathogens',false),
('avian-rotavirus','Avian rotavirus infection',array['poultry'],array['chickens','turkeys'],'USDA APHIS','https://www.aphis.usda.gov/animal-product-import/organisms-vectors/livestock-poultry-pathogens',false),
('avian-hepatitis-e','Avian hepatitis E',array['poultry'],array['chickens'],'USDA APHIS','https://www.aphis.usda.gov/animal-product-import/organisms-vectors/livestock-poultry-pathogens',false),
('infectious-canine-hepatitis','Infectious canine hepatitis',array['dogs'],array['dogs','puppies'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('canine-babesiosis','Canine babesiosis',array['dogs'],array['dogs'],'China MARA','https://xmsyj.moa.gov.cn/gzdt/202206/t20220629_6403635.htm',false),
('canine-leishmaniosis','Canine leishmaniosis',array['dogs'],array['dogs'],'WOAH','https://www.woah.org/en/disease/leishmaniosis/',true),
('brucella-canis','Canine brucellosis (Brucella canis)',array['dogs'],array['dogs'],'Australia DAFF','https://www.agriculture.gov.au/biosecurity-trade/pests-diseases-weeds/animal/notifiable',true),
('canine-ehrlichiosis','Canine ehrlichiosis',array['dogs'],array['dogs'],'Australia DAFF','https://www.agriculture.gov.au/biosecurity-trade/pests-diseases-weeds/animal/notifiable',true),
('canine-anaplasmosis','Canine anaplasmosis',array['dogs'],array['dogs'],'USDA APHIS','https://www.aphis.usda.gov/animal-product-import/organisms-vectors/livestock-poultry-pathogens',false),
('canine-heartworm','Canine heartworm disease',array['dogs'],array['dogs'],'Merck Veterinary Manual','https://www.merckvetmanual.com/circulatory-system/heartworm-disease/heartworm-disease-in-dogs-cats-and-ferrets',false),
('canine-respiratory-disease-complex','Canine infectious respiratory disease complex',array['dogs'],array['dogs'],'Merck Veterinary Manual','https://www.merckvetmanual.com/respiratory-system/respiratory-diseases-of-small-animals/canine-infectious-respiratory-disease-complex',false),
('canine-influenza','Canine influenza',array['dogs'],array['dogs'],'Merck Veterinary Manual','https://www.merckvetmanual.com/respiratory-system/respiratory-diseases-of-small-animals/canine-influenza',false),
('canine-giardiasis','Giardiasis in dogs',array['dogs'],array['dogs','puppies'],'Merck Veterinary Manual','https://www.merckvetmanual.com/digestive-system/giardiasis/giardiasis-in-animals',false),
('canine-sarcoptic-mange','Sarcoptic mange in dogs',array['dogs'],array['dogs'],'Merck Veterinary Manual','https://www.merckvetmanual.com/integumentary-system/mange/mange-in-dogs-and-cats',false),
('canine-demodicosis','Demodicosis in dogs',array['dogs'],array['dogs'],'Merck Veterinary Manual','https://www.merckvetmanual.com/integumentary-system/mange/mange-in-dogs-and-cats',false),
('canine-dermatophytosis','Dermatophytosis (ringworm) in dogs',array['dogs'],array['dogs'],'Merck Veterinary Manual','https://www.merckvetmanual.com/integumentary-system/dermatophytosis/dermatophytosis-in-dogs-and-cats',false),
('canine-enteric-coronavirus','Canine enteric coronavirus infection',array['dogs'],array['dogs','puppies'],'Merck Veterinary Manual','https://www.merckvetmanual.com/digestive-system/infectious-diseases-of-the-gastrointestinal-tract-in-small-animals/canine-coronavirus-enteritis',false),
('bordetella-bronchiseptica-dogs','Bordetella bronchiseptica infection in dogs',array['dogs'],array['dogs'],'Merck Veterinary Manual','https://www.merckvetmanual.com/respiratory-system/respiratory-diseases-of-small-animals/canine-infectious-respiratory-disease-complex',false),
('lyme-disease-dogs','Lyme borreliosis in dogs',array['dogs'],array['dogs'],'Merck Veterinary Manual','https://www.merckvetmanual.com/infectious-diseases/borreliosis/lyme-borreliosis-in-animals',false),
('neosporosis-dogs','Neosporosis in dogs',array['dogs'],array['dogs','puppies'],'Merck Veterinary Manual','https://www.merckvetmanual.com/generalized-conditions/neosporosis/neosporosis-in-dogs',false),
('canine-toxoplasmosis','Toxoplasmosis in dogs',array['dogs'],array['dogs'],'Merck Veterinary Manual','https://www.merckvetmanual.com/generalized-conditions/toxoplasmosis/toxoplasmosis-in-animals',false),
('canine-kennel-cough','Kennel cough syndrome',array['dogs'],array['dogs'],'Merck Veterinary Manual','https://www.merckvetmanual.com/respiratory-system/respiratory-diseases-of-small-animals/canine-infectious-respiratory-disease-complex',false),
('canine-tetanus','Tetanus in dogs',array['dogs'],array['dogs'],'Merck Veterinary Manual','https://www.merckvetmanual.com/nervous-system/tetanus/tetanus-in-animals',false),
('canine-botulism','Botulism in dogs',array['dogs'],array['dogs'],'Merck Veterinary Manual','https://www.merckvetmanual.com/nervous-system/botulism/botulism-in-animals',false),
('canine-coccidiosis','Coccidiosis in dogs',array['dogs'],array['dogs','puppies'],'Merck Veterinary Manual','https://www.merckvetmanual.com/digestive-system/coccidiosis/coccidiosis-in-dogs',false)
)
insert into public.disease_catalog (slug,display_name,animal_groups,agent_type,reportable_or_listed,default_risk,source_org,source_url,source_reviewed_at,curation_status,species_scope)
select slug,display_name,groups::public.animal_group[],'not_curated',reportable,
       case when reportable then 'red'::public.risk_level else 'yellow'::public.risk_level end,
       source_org,source_url,current_date,'indexed',species
from seed
on conflict (slug) do nothing;

insert into public.disease_source_refs (disease_id,source_org,jurisdiction,source_title,source_url,evidence_scope,source_reviewed_at)
select d.id,d.source_org,
  case d.source_org when 'USDA APHIS' then 'United States' when 'Australia DAFF' then 'Australia' when 'Japan MAFF' then 'Japan' when 'China MARA' then 'China' when 'US CDC' then 'United States' else 'global' end,
  d.display_name,d.source_url,array['disease_listing','species_scope'],d.source_reviewed_at
from public.disease_catalog d
where d.source_url is not null and d.source_org is not null
on conflict (disease_id,source_url) do nothing;

insert into public.disease_aliases (disease_id,alias,language_code,source_org,source_url)
select id,display_name,'en',source_org,source_url from public.disease_catalog
on conflict (disease_id,alias,language_code) do nothing;
