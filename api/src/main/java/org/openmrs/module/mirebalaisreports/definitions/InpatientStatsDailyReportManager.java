/*
 * The contents of this file are subject to the OpenMRS Public License
 * Version 1.0 (the "License"); you may not use this file except in
 * compliance with the License. You may obtain a copy of the License at
 * http://license.openmrs.org
 *
 * Software distributed under the License is distributed on an "AS IS"
 * basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * Copyright (C) OpenMRS, LLC.  All Rights Reserved.
 */

package org.openmrs.module.mirebalaisreports.definitions;

import org.openmrs.EncounterType;
import org.openmrs.Location;
import org.openmrs.module.emrapi.adt.AdtService;
import org.openmrs.module.mirebalaisreports.MirebalaisReportsProperties;
import org.openmrs.module.mirebalaisreports.cohort.definition.InpatientLocationCohortDefinition;
import org.openmrs.module.mirebalaisreports.cohort.definition.InpatientTransferCohortDefinition;
import org.openmrs.module.reporting.cohort.definition.CohortDefinition;
import org.openmrs.module.reporting.cohort.definition.EncounterCohortDefinition;
import org.openmrs.module.reporting.dataset.definition.CohortIndicatorDataSetDefinition;
import org.openmrs.module.reporting.evaluation.parameter.Parameter;
import org.openmrs.module.reporting.indicator.CohortIndicator;
import org.openmrs.module.reporting.report.ReportDesign;
import org.openmrs.module.reporting.report.definition.ReportDefinition;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Date;
import java.util.List;

/**
 *
 */
@Component
public class InpatientStatsDailyReportManager extends BaseMirebalaisReportManager {

    @Autowired
    private AdtService adtService;

    @Override
    public String getUuid() {
        return MirebalaisReportsProperties.INPATIENT_STATS_DAILY_REPORT_DEFINITION_UUID;
    }

    @Override
    protected String getMessageCodePrefix() {
        return "mirebalaisreports.inpatientStatsDaily.";
    }

    @Override
    public List<Parameter> getParameters() {
        List<Parameter> l = new ArrayList<Parameter>();
        l.add(new Parameter("day", "mirebalaisreports.parameter.day", Date.class));
        return l;
    }

    @Override
    public ReportDefinition constructReportDefinition() {
        log.info("Constructing " + getName());

        List<Location> inpatientLocations = adtService.getInpatientLocations();
        EncounterType admissionEncounterType = emrApiProperties.getAdmissionEncounterType();
        EncounterType transferWithinHospitalEncounterType = emrApiProperties.getTransferWithinHospitalEncounterType();

        ReportDefinition rd = new ReportDefinition();
        rd.setName(getMessageCodePrefix() + "name");
        rd.setDescription(getMessageCodePrefix() + "description");
        rd.setUuid(getUuid());
        rd.setParameters(getParameters());


//        InpatientLocationCohortDefinition censusCohortDef = new InpatientLocationCohortDefinition();
//        censusCohortDef.addParameter(getEffectiveDateParameter());


        CohortIndicatorDataSetDefinition dsd = new CohortIndicatorDataSetDefinition();
        dsd.addParameter(getStartDateParameter());
        dsd.addParameter(getEndDateParameter());

        for (Location location : inpatientLocations) {

            // census at start, census at end

            InpatientLocationCohortDefinition censusCohortDef = new InpatientLocationCohortDefinition();
            censusCohortDef.addParameter(getEffectiveDateParameter());
            censusCohortDef.setWard(location);

            CohortIndicator censusStartInd = buildIndicator("Census at start: " + location.getName(), censusCohortDef, "effectiveDate=${startDate}");
            CohortIndicator censusEndInd = buildIndicator("Census at end: " + location.getName(), censusCohortDef, "effectiveDate=${endDate}");

            dsd.addColumn("censusAtStart." + location.getId(), "Census at start: " + location.getName(), map(censusStartInd, "startDate=${startDate}"), "");
            dsd.addColumn("censusAtEnd." + location.getId(), "Census at end: " + location.getName(), map(censusEndInd, "endDate=${endDate}"), "");

            // number of admissions

            EncounterCohortDefinition admissionDuring = new EncounterCohortDefinition();
            admissionDuring.addParameter(new Parameter("onOrAfter", "On or after", Date.class));
            admissionDuring.addParameter(new Parameter("onOrBefore", "On or before", Date.class));
            admissionDuring.addLocation(location);
            admissionDuring.addEncounterType(admissionEncounterType);

            CohortIndicator admissionInd = buildIndicator("Admission: " + location.getName(), admissionDuring, "onOrAfter=${startDate},onOrBefore=${endDate}");
            dsd.addColumn("admission." + location.getId(), "Admission: " + location.getName(), map(admissionInd, "startDate=${startDate},endDate=${endDate}"), "");
            
            // number of transfer ins

            InpatientTransferCohortDefinition transferInDuring = new InpatientTransferCohortDefinition();
            transferInDuring.addParameter(new Parameter("onOrAfter", "On or after", Date.class));
            transferInDuring.addParameter(new Parameter("onOrBefore", "On or before", Date.class));
            transferInDuring.setInToWard(location);

            CohortIndicator transferInInd = buildIndicator("Transfer In: " + location.getName(), transferInDuring, "onOrAfter=${startDate},onOrBefore=${endDate}");
            dsd.addColumn("transferin." + location.getId(), "Transfer In: " + location.getName(), map(transferInInd, "startDate=${startDate},endDate=${endDate}"), "");

            // number of transfer outs

            InpatientTransferCohortDefinition transferOutDuring = new InpatientTransferCohortDefinition();
            transferOutDuring.addParameter(new Parameter("onOrAfter", "On or after", Date.class));
            transferOutDuring.addParameter(new Parameter("onOrBefore", "On or before", Date.class));
            transferOutDuring.setOutOfWard(location);

            CohortIndicator transferOutInd = buildIndicator("Transfer Out: " + location.getName(), transferOutDuring, "onOrAfter=${startDate},onOrBefore=${endDate}");
            dsd.addColumn("transferout." + location.getId(), "Transfer Out: " + location.getName(), map(transferOutInd, "startDate=${startDate},endDate=${endDate}"), "");

            // number of exit-from-inpatient broken down by last disposition

            // length of stay of patients who exited from inpatient (by ward, and in the ER)

            // admissions within 48 hours of previous exit
        }

        // number of ED check-ins
        // TODO change this to count by visits or by encounters, instead of by patients
        EncounterCohortDefinition edCheckIn = new EncounterCohortDefinition();
        edCheckIn.addParameter(new Parameter("onOrAfter", "On or after", Date.class));
        edCheckIn.addParameter(new Parameter("onOrBefore", "On or before", Date.class));
        edCheckIn.addEncounterType(mirebalaisReportsProperties.getCheckInEncounterType());
        edCheckIn.addLocation(mirebalaisReportsProperties.getEmergencyLocation());
        edCheckIn.addLocation(mirebalaisReportsProperties.getEmergencyReceptionLocation());

        CohortIndicator edCheckInInd = buildIndicator("ED Check In", edCheckIn, "onOrAfter=${startDate},onOrBefore=${endDate}");
        dsd.addColumn("edcheckin", "ED Check In", map(edCheckInInd, "startDate=${startDate},endDate=${endDate}"), "");

        // number of surgical op-notes entered
        EncounterCohortDefinition surgicalNotes = new EncounterCohortDefinition();
        surgicalNotes.addParameter(new Parameter("onOrAfter", "On or after", Date.class));
        surgicalNotes.addParameter(new Parameter("onOrBefore", "On or before", Date.class));
        surgicalNotes.addEncounterType(mirebalaisReportsProperties.getPostOpNoteEncounterType());

        CohortIndicator surgicalNotesInd = buildIndicator("OR Volume", surgicalNotes, "onOrAfter=${startDate},onOrBefore=${endDate}");
        dsd.addColumn("orvolume", "OR Volume", map(surgicalNotesInd, "startDate=${startDate},endDate=${endDate}"), "");


        rd.addDataSetDefinition("dsd", map(dsd, "startDate=${day},endDate=${day+1d-1s}"));

        return rd;
    }

//    private Parameter getWardParameter() {
//        return new Parameter("ward", "Ward", Location.class);
//    }

    private Parameter getEffectiveDateParameter() {
        return new Parameter("effectiveDate", "mirebalaisreports.parameter.effectiveDate", Date.class);
    }

    private CohortIndicator buildIndicator(String name, CohortDefinition cd, String mappings) {
        CohortIndicator indicator = new CohortIndicator(name);
        indicator.addParameter(getStartDateParameter());
        indicator.addParameter(getEndDateParameter());
        indicator.addParameter(getLocationParameter());
        indicator.setCohortDefinition(map(cd, mappings));
        return indicator;
    }

    @Override
    public List<ReportDesign> constructReportDesigns(ReportDefinition reportDefinition) {
        return Arrays.asList(xlsReportDesign(reportDefinition));
    }

}