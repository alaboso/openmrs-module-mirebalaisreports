set sql_safe_updates = 0;

DROP TEMPORARY TABLE IF EXISTS temp_ncd_program;
DROP TEMPORARY TABLE IF EXISTS temp_ncd_last_ncd_enc;
DROP TEMPORARY TABLE IF EXISTS temp_ncd_first_ncd_enc;

select patient_identifier_type_id INTO @zlId FROM patient_identifier_type where name = "ZL EMR ID";
select patient_identifier_type_id INTO @dosId FROM patient_identifier_type where name = "Nimewo Dosye";
select encounter_type_id INTO @NCDInitEnc FROM encounter_type where UUID = "ae06d311-1866-455b-8a64-126a9bd74171";
select encounter_type_id INTO @NCDFollowEnc FROM encounter_type where UUID = "5cbfd6a2-92d9-4ad0-b526-9d29bfe1d10c";

-- latest NCD enc table
create temporary table temp_ncd_last_ncd_enc
(
encounter_id int,
patient_id int,
encounter_datetime datetime,
zlemr_id varchar(255),
dossier_id varchar(255)
);
insert into temp_ncd_last_ncd_enc(patient_id, encounter_datetime)
select patient_id, max(encounter_datetime) from encounter where voided = 0
and encounter_type in (@NCDInitEnc, @NCDFollowEnc) group by patient_id order by patient_id;

update temp_ncd_last_ncd_enc tlne
inner join encounter e on tlne.patient_id = e.patient_id and tlne.encounter_datetime = e.encounter_datetime
set tlne.encounter_id = e.encounter_id;

update temp_ncd_last_ncd_enc tlne
-- Most recent ZL EMR ID
inner join (select patient_id, identifier from patient_identifier where identifier_type = @zlId
            and voided = 0 and preferred = 1 order by date_created desc) zl on tlne.patient_id = zl.patient_id
set tlne.zlemr_id = zl.identifier;

update temp_ncd_last_ncd_enc tlne
-- -- Dossier ID
inner join (select patient_id, max(identifier) dos_id from patient_identifier where identifier_type = @dosId
            and voided = 0 group by patient_id) dos on tlne.patient_id = dos.patient_id
set tlne.dossier_id = dos.dos_id;

-- initial ncd enc table(ideally it should be ncd initital form only)
create temporary table temp_ncd_first_ncd_enc
(
encounter_id int,
patient_id int,
encounter_datetime datetime
);
insert into temp_ncd_first_ncd_enc(patient_id, encounter_datetime)
select patient_id, min(encounter_datetime) from encounter where voided = 0
and encounter_type in (@NCDInitEnc, @NCDFollowEnc) group by patient_id order by patient_id;

update temp_ncd_first_ncd_enc tfne
inner join encounter e on tfne.patient_id = e.patient_id and tfne.encounter_datetime = e.encounter_datetime
set tfne.encounter_id = e.encounter_id;

-- ncd program
create temporary table temp_ncd_program(
patient_program_id int,
patient_id int,
date_enrolled datetime,
date_completed datetime,
location_id int,
outcome_concept_id int,
given_name varchar(255),
family_name varchar(255),
birthdate datetime,
birthdate_estimated varchar(50),
gender varchar(50),
country varchar(255),
department varchar(255),
commune varchar(255),
section_communal varchar(255),
locality varchar(255),
street_landmark varchar(255),
telephone_number varchar(255),
contact_telephone_number  varchar(255),
program_state varchar(255),
program_outcome varchar(255),
first_ncd_encounter datetime,
last_ncd_encounter datetime,
next_ncd_appointment datetime,
thirty_days_past_app varchar(11),
disposition varchar(255),
deceased varchar(255),
HbA1c_result double,
HbA1c_collection_date datetime,
HbA1c_result_date datetime,
bp_diastolic double,
bp_systolic double,
height double,
weight double,
creatinine_result double,
creatinine_collection_date datetime,
creatinine_result_date datetime,
nyha_classes text,
lack_of_meds text,
visit_adherence text,
recent_hospitalization text,
ncd_meds_prescribed text,
prescribed_insulin text,
hypertension int,
diabetes int,
heart_Failure int,
stroke int,
respiratory int,
rehab int,
anemia int,
epilepsy int,
other_Category int,
last_diagnosis_1 text,
last_diagnosis_2 text,
last_diagnosis_3 text,
last_non_coded_diagnosis text
);

insert into temp_ncd_program (patient_program_id, patient_id, date_enrolled, date_completed, location_id, outcome_concept_id)
select
patient_program_id,
patient_id,
DATE(date_enrolled),
DATE(date_completed),
location_id,
outcome_concept_id
from patient_program where voided = 0 and program_id in (select program_id from program where uuid = '515796ec-bf3a-11e7-abc4-cec278b6b50a') -- uuid of the NCD program
order by patient_id;

update temp_ncd_program p inner join current_name_address d on d.person_id = p.patient_id
set p.given_name = d.given_name,
	p.family_name = d.family_name,
	p.birthdate = d.birthdate,
    p.birthdate_estimated = d.birthdate_estimated,
    p.gender = d.gender,
    p.country = d.country,
    p.department = d.department,
    p.commune = d.commune,
    p.section_communal = d.section_communal,
    p.locality = d.locality,
    p.street_landmark = d.street_landmark;

-- Telephone number
update temp_ncd_program p
LEFT OUTER JOIN person_attribute pa on pa.person_id = p.patient_id and pa.voided = 0 and pa.person_attribute_type_id = (select person_attribute_type_id
from person_attribute_type where uuid = "14d4f066-15f5-102d-96e4-000c29c2a5d7")
set p.telephone_number = pa.value;

-- telephone number of contact
update temp_ncd_program p
LEFT OUTER JOIN obs contact_telephone on contact_telephone.person_id = p.patient_id and contact_telephone.voided = 0 and contact_telephone.concept_id = (select concept_id from
report_mapping where source="PIH" and code="TELEPHONE NUMBER OF CONTACT")
set p.contact_telephone_number = contact_telephone.value_text;

update temp_ncd_program p
-- patient state
LEFT OUTER JOIN patient_state ps on ps.patient_program_id = p.patient_program_id and ps.end_date is null and ps.voided = 0
LEFT OUTER JOIN program_workflow_state pws on pws.program_workflow_state_id = ps.state and pws.retired = 0
LEFT OUTER JOIN concept_name cn_state on cn_state.concept_id = pws.concept_id  and cn_state.locale = 'en' and cn_state.locale_preferred = '1'  and cn_state.voided = 0
-- outcome
LEFT OUTER JOIN concept_name cn_out on cn_out.concept_id = p.outcome_concept_id and cn_out.locale = 'en' and cn_out.locale_preferred = '1'  and cn_out.voided = 0
set p.program_state = cn_state.name,
	p.program_outcome = cn_out.name;

update temp_ncd_program p
-- first ncd encounter
LEFT OUTER JOIN temp_ncd_first_ncd_enc first_ncd_enc on first_ncd_enc.patient_id = p.patient_id
set p.first_ncd_encounter = DATE(first_ncd_enc.encounter_datetime);

update temp_ncd_program p
-- last visit
LEFT OUTER JOIN temp_ncd_last_ncd_enc last_ncd_enc on last_ncd_enc.patient_id = p.patient_id
-- next visit (obs)
LEFT OUTER JOIN obs obs_next_appt on obs_next_appt.encounter_id = last_ncd_enc.encounter_id and obs_next_appt.concept_id =
     (select concept_id from report_mapping rm_next where rm_next.source = 'PIH' and rm_next.code = 'RETURN VISIT DATE')
     and obs_next_appt.voided = 0
set p.last_ncd_encounter = DATE(last_ncd_enc.encounter_datetime),
	p.next_ncd_appointment = DATE(obs_next_appt.value_datetime),
    p.thirty_days_past_app = IF(DATEDIFF(CURDATE(), obs_next_appt.value_datetime) > 30, "Oui", NULL);

update temp_ncd_program p
left outer join temp_ncd_last_ncd_enc on p.patient_id = temp_ncd_last_ncd_enc.patient_id
-- latest disposition
LEFT OUTER JOIN obs obs_disposition on obs_disposition.encounter_id = temp_ncd_last_ncd_enc.encounter_id and obs_disposition.voided = 0 and obs_disposition.concept_id =
     (select concept_id from report_mapping rm_dispostion where rm_dispostion.source = 'PIH' and rm_dispostion.code = '8620')
LEFT OUTER JOIN concept_name cn_disposition on cn_disposition.concept_id = obs_disposition.value_coded and cn_disposition.locale = 'fr'
and cn_disposition.voided = 0 and cn_disposition.locale_preferred = 1
set p.disposition = cn_disposition.name,
    p.deceased = IF(obs_disposition.value_coded = (select concept_id from report_mapping rm_dispostion where rm_dispostion.source = 'PIH' and rm_dispostion.code = 'DEATH')
OR p.outcome_concept_id = (select concept_id from report_mapping rm_dispostion where rm_dispostion.source = 'PIH' and rm_dispostion.code = 'PATIENT DIED')
, "Oui", NULL
);

update temp_ncd_program p
-- last collected HbA1c test
LEFT OUTER JOIN
    (SELECT person_id, value_numeric, HbA1c_test.encounter_id, DATE(obs_datetime), DATE(edate.encounter_datetime) HbA1c_coll_date from obs HbA1c_test JOIN encounter
    edate ON edate.patient_id = HbA1c_test.person_id and HbA1c_test.encounter_id = edate.encounter_id AND
    HbA1c_test.voided = 0 and HbA1c_test.concept_id =
    (select concept_id from report_mapping rm_HbA1c where rm_HbA1c.source = 'PIH' and rm_HbA1c.code = 'HbA1c') and
    obs_datetime IN (select max(obs_datetime) from obs o2 where o2.voided = 0 and o2.concept_id = (select concept_id from report_mapping rm_HbA1c
    where rm_HbA1c.source = 'PIH' and rm_HbA1c.code = 'HbA1c')
    group by o2.person_id)) HbA1c_results on HbA1c_results.person_id = p.patient_id
LEFT OUTER JOIN obs HbA1c_date on HbA1c_date.encounter_id = HbA1c_results.encounter_id and HbA1c_date.voided = 0
  and HbA1c_date.concept_id =
      (select concept_id from report_mapping rm_HbA1c_date where rm_HbA1c_date.source = 'PIH' and rm_HbA1c_date.code = 'DATE OF LABORATORY TEST')
set p.HbA1c_result = HbA1c_results.value_numeric,
	p.HbA1c_collection_date = HbA1c_results.HbA1c_coll_date,
	p.HbA1c_result_date = DATE(HbA1c_date.value_datetime);

update temp_ncd_program p
-- last collected Blood Pressure
LEFT OUTER JOIN obs bp_syst on bp_syst.obs_id =
   (select obs_id from obs o2 where o2.person_id = p.patient_id
    and o2.concept_id =
      (select concept_id from report_mapping rm_syst where rm_syst.source = 'PIH' and rm_syst.code = 'Systolic Blood Pressure')
    order by o2.obs_datetime desc limit 1
    ) and bp_syst.voided = 0
LEFT OUTER JOIN obs bp_diast on bp_diast.encounter_id = bp_syst.encounter_id
  and bp_diast.concept_id =
   (select concept_id from report_mapping rm_diast where rm_diast.source = 'PIH' and rm_diast.code = 'Diastolic Blood Pressure')
  and bp_diast.voided = 0
set p.bp_diastolic  = bp_diast.value_numeric,
	p.bp_systolic = bp_syst.value_numeric;

update temp_ncd_program p
-- last collected Creatinine test
LEFT OUTER JOIN
(SELECT person_id, value_numeric, creat_test.encounter_id, DATE(obs_datetime), DATE(edate.encounter_datetime) creat_coll_date from obs creat_test JOIN encounter
    edate ON edate.patient_id = creat_test.person_id and creat_test.encounter_id = edate.encounter_id AND
    creat_test.voided = 0 and creat_test.concept_id =
    (select concept_id from report_mapping rm_syst where rm_syst.source = 'PIH' and rm_syst.code = 'Creatinine mg per dL') and
    obs_datetime IN (select max(obs_datetime) from obs o2 where o2.voided = 0 and o2.concept_id = (select concept_id from report_mapping rm_syst
    where rm_syst.source = 'PIH' and rm_syst.code = 'HbA1c')
    group by o2.person_id)) creat_results on creat_results.person_id = p.patient_id
LEFT OUTER JOIN obs creat_date on creat_date.encounter_id = creat_results.encounter_id
  and creat_date.concept_id =
      (select concept_id from report_mapping rm_creat_date where rm_creat_date.source = 'PIH' and rm_creat_date.code = 'DATE OF LABORATORY TEST')
   and creat_date.voided = 0
set p.creatinine_result = creat_results.value_numeric ,
	p.creatinine_collection_date = DATE(creat_results.creat_coll_date),
	p.creatinine_result_date = DATE(creat_date.value_datetime);

update temp_ncd_program p
-- last collected Height, Weight
LEFT OUTER JOIN obs height on height.obs_id =
   (select obs_id from obs o2 where o2.person_id = p.patient_id
    and o2.concept_id =
      (select concept_id from report_mapping rm_syst where rm_syst.source = 'PIH' and rm_syst.code = 'HEIGHT (CM)')
    order by o2.obs_datetime desc limit 1
    ) and height.voided = 0
LEFT OUTER JOIN obs weight on weight.obs_id =
   (select obs_id from obs o2 where o2.person_id = p.patient_id
    and o2.concept_id =
      (select concept_id from report_mapping rm_syst where rm_syst.source = 'PIH' and rm_syst.code = 'WEIGHT (KG)')
    order by o2.obs_datetime desc limit 1
    ) and weight.voided = 0
set p.height = height.value_numeric,
	p.weight = weight.value_numeric;

update temp_ncd_program p
left outer join temp_ncd_last_ncd_enc on p.patient_id = temp_ncd_last_ncd_enc.patient_id
-- NYHA
LEFT OUTER JOIN
  (SELECT obs_nyha.encounter_id, GROUP_CONCAT(cn_nyha.name separator " | ") "classes"
  from obs obs_nyha
  LEFT OUTER JOIN concept_name cn_nyha on cn_nyha.concept_id = obs_nyha.value_coded and cn_nyha.locale = 'fr' and cn_nyha.locale_preferred = 1
  where obs_nyha.concept_id =
 (select concept_id from report_mapping rm_next where rm_next.source = 'PIH' and rm_next.code = 'NYHA CLASS')
 and obs_nyha.voided = 0
 group by 1
 ) nyha on  nyha.encounter_id = temp_ncd_last_ncd_enc.encounter_id
 set p.nyha_classes = nyha.classes;

update temp_ncd_program p
left outer join temp_ncd_last_ncd_enc on p.patient_id = temp_ncd_last_ncd_enc.patient_id
-- Lack of meds
LEFT OUTER JOIN obs obs_lack_meds on obs_lack_meds.encounter_id = temp_ncd_last_ncd_enc.encounter_id and obs_lack_meds.concept_id =
    (select concept_id from report_mapping rm_next where rm_next.source = 'PIH' and rm_next.code = 'Lack of meds in last 2 days')
    and obs_lack_meds.voided = 0
LEFT OUTER JOIN concept_name cn_lack_meds on cn_lack_meds.concept_id = obs_lack_meds.value_coded and cn_lack_meds.locale = 'fr' and cn_lack_meds.locale_preferred = 1
set p.lack_of_meds = cn_lack_meds.name;

update temp_ncd_program p
left outer join temp_ncd_last_ncd_enc on p.patient_id = temp_ncd_last_ncd_enc.patient_id
-- visit adherence
LEFT OUTER JOIN obs obs_visit_adherence on obs_visit_adherence.encounter_id = temp_ncd_last_ncd_enc.encounter_id and obs_visit_adherence.concept_id =
    (select concept_id from report_mapping rm_next where rm_next.source = 'PIH' and rm_next.code = 'Appearance at appointment time')
    and obs_visit_adherence.voided = 0
LEFT OUTER JOIN concept_name cn_visit_adherence on cn_visit_adherence.concept_id = obs_visit_adherence.value_coded
  and cn_visit_adherence.locale = 'fr' and cn_visit_adherence.locale_preferred = 1 and cn_visit_adherence.voided = 0
set p.visit_adherence = cn_visit_adherence.name;

update temp_ncd_program p
left outer join temp_ncd_last_ncd_enc on p.patient_id = temp_ncd_last_ncd_enc.patient_id
-- recent hospitalization
LEFT OUTER JOIN obs obs_recent_hosp on obs_recent_hosp.encounter_id = temp_ncd_last_ncd_enc.encounter_id and obs_recent_hosp.concept_id =
    (select concept_id from report_mapping rm_next where rm_next.source = 'PIH' and rm_next.code = 'PATIENT HOSPITALIZED SINCE LAST VISIT')
    and obs_recent_hosp.voided = 0
LEFT OUTER JOIN concept_name cn_recent_hosp on cn_recent_hosp.concept_id = obs_recent_hosp.value_coded and cn_recent_hosp.locale = 'fr'
  and cn_recent_hosp.locale_preferred = 1 and cn_recent_hosp.voided = 0
set p.recent_hospitalization = cn_recent_hosp.name;

update temp_ncd_program p
left outer join temp_ncd_last_ncd_enc on p.patient_id = temp_ncd_last_ncd_enc.patient_id
-- meds
LEFT OUTER JOIN
  (SELECT obs_meds.encounter_id, GROUP_CONCAT(cn_meds.name separator " | ") "meds"
  from obs obs_meds
  LEFT OUTER JOIN concept_name cn_meds on cn_meds.concept_id = obs_meds.value_coded and cn_meds.locale = 'fr' and cn_meds.locale_preferred = 1 and cn_meds.voided = 0
  where obs_meds.concept_id =
 (select concept_id from report_mapping rm_next where rm_next.source = 'PIH' and rm_next.code = 'Medications prescribed at end of visit')
 and obs_meds.voided = 0
 group by obs_meds.encounter_id
 ) meds on meds.encounter_id = temp_ncd_last_ncd_enc.encounter_id
 set p.ncd_meds_prescribed = meds.meds,
	 p.prescribed_insulin = (case when lower(ncd_meds_prescribed) like '%insulin%' then 'oui' else 'non' end) ;

update temp_ncd_program p
left outer join temp_ncd_last_ncd_enc on p.patient_id = temp_ncd_last_ncd_enc.patient_id
-- NCD category
LEFT OUTER JOIN
  (SELECT obs_cat.encounter_id,
  max(case when rm_cat.source = 'PIH' and rm_cat.code = 'HYPERTENSION' then '1' end) 'Hypertension',
  max(case when rm_cat.source = 'PIH' and rm_cat.code = 'DIABETES' then '1' end) 'Diabetes',
  max(case when rm_cat.source = 'PIH' and rm_cat.code = 'HEART FAILURE' then '1' end) 'Heart_Failure',
  max(case when rm_cat.source = 'PIH' and rm_cat.code = 'Cerebrovascular Accident' then '1' end) 'Stroke',
  max(case when rm_cat.source = 'PIH' and rm_cat.code = 'Chronic respiratory disease program' then '1' end) 'Respiratory',
  max(case when rm_cat.source = 'PIH' and rm_cat.code = 'Rehab program' then '1' end) 'Rehab',
  max(case when rm_cat.source = 'PIH' and rm_cat.code = 'Sickle-Cell Anemia' then '1' end) 'Anemia',
  max(case when rm_cat.source = 'PIH' and rm_cat.code = 'EPILEPSY' then '1' end) 'Epilepsy',
  max(case when rm_cat.source = 'PIH' and rm_cat.code = 'OTHER' then '1' end) 'Other_Category'
  from obs obs_cat
  LEFT OUTER JOIN report_mapping rm_cat on rm_cat.concept_id = obs_cat.value_coded
  where obs_cat.concept_id =
 (select concept_id from report_mapping rm_next where rm_next.source = 'PIH' and rm_next.code = 'NCD category')
 and obs_cat.voided = 0
 group by 1
 ) cats on cats.encounter_id = temp_ncd_last_ncd_enc.encounter_id
 set p.hypertension = cats.Hypertension,
	 p.diabetes = cats.Diabetes,
	 p.heart_Failure = cats.Heart_Failure,
	 p.stroke = cats.Stroke,
	 p.respiratory = cats.Respiratory,
	 p.rehab = cats.Rehab,
	 p.anemia = cats.Anemia,
	 p.epilepsy = cats.Epilepsy,
	 p.other_category = cats.Other_Category;

update temp_ncd_program p
left outer join temp_ncd_last_ncd_enc on p.patient_id = temp_ncd_last_ncd_enc.patient_id
-- last 3 diagnoses
inner join report_mapping diag on diag.source = 'PIH' and diag.code = 'DIAGNOSIS'
inner join report_mapping diag_nc on diag_nc.source = 'PIH' and diag_nc.code = 'Diagnosis or problem, non-coded'
left outer join obs diag1 on diag1.obs_id =
  (select obs_id from obs d1
  where d1.concept_id = diag.concept_id
  and d1.voided = 0
  and d1.encounter_id = temp_ncd_last_ncd_enc.encounter_id
  order by d1.obs_datetime asc limit 1)
left outer join concept_name diagname1 on diagname1.concept_id = diag1.value_coded and diagname1.locale = 'fr' and diagname1.voided = 0 and diagname1.locale_preferred=1
left outer join obs diag2 on diag2.obs_id =
  (select obs_id from obs d2
  where d2.concept_id = diag.concept_id
  and d2.voided = 0
  and d2.encounter_id = temp_ncd_last_ncd_enc.encounter_id
  and d2.value_coded <> diag1.value_coded
  order by d2.obs_datetime asc limit 1)
left outer join concept_name diagname2 on diagname2.concept_id = diag2.value_coded and diagname2.locale = 'fr' and diagname2.voided = 0 and diagname2.locale_preferred=1
left outer join obs diag3 on diag3.obs_id =
  (select obs_id from obs d3
  where d3.concept_id = diag.concept_id
  and d3.voided = 0
  and d3.encounter_id = temp_ncd_last_ncd_enc.encounter_id
  and d3.value_coded not in (diag1.value_coded,diag2.value_coded)
  order by d3.obs_datetime asc limit 1)
 left outer join concept_name diagname3 on diagname3.concept_id = diag3.value_coded and diagname3.locale = 'fr' and diagname3.voided = 0 and diagname3.locale_preferred=1
 left outer join obs d_nc on d_nc.concept_id = diag_nc.concept_id and d_nc.voided = 0 and d_nc.encounter_id = temp_ncd_last_ncd_enc.encounter_id
set p.last_diagnosis_1 = diagname1.name,
	p.last_diagnosis_2 = diagname2.name,
	p.last_diagnosis_3 = diagname3.name,
    p.last_non_coded_diagnosis = d_nc.value_text;

select
p.patient_id "patient_id",
ZLemr_id,
dossier_id,
given_name,
family_name,
birthdate,
birthdate_estimated,
gender,
country,
department,
commune,
section_communal,
locality,
street_landmark,
telephone_number,
contact_telephone_number,
DATE(date_enrolled) "enrolled_in_program",
program_state,
program_outcome,
disposition,
first_ncd_encounter,
last_ncd_encounter,
next_ncd_appointment,
thirty_days_past_app "30_days_past_app",
deceased,
hypertension,
diabetes,
heart_Failure,
stroke,
respiratory,
rehab,
anemia,
epilepsy,
other_category,
nyha_classes,
lack_of_meds,
visit_adherence,
recent_hospitalization,
ncd_meds_prescribed,
prescribed_insulin,
HbA1c_result,
HbA1c_collection_date,
HbA1c_result_date,
bp_diastolic,
bp_systolic,
height,
weight,
creatinine_result,
creatinine_collection_date,
creatinine_result_date,
last_diagnosis_1,
last_diagnosis_2,
last_diagnosis_3,
last_non_coded_diagnosis
from temp_ncd_program p left outer join temp_ncd_last_ncd_enc tlne on p.patient_id = tlne.patient_id;