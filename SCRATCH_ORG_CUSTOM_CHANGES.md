# newMBD Scratch Org Custom Changes

Generated: July 3, 2026

This document summarizes the custom Salesforce metadata and scratch-org adjustments captured in this repository for the `newMBD` scratch org. It is intended as a handoff/change log rather than a complete field-by-field metadata export.

## Executive Summary

The scratch org has been customized to support the new MBD configuration by restoring and adapting metadata from the source org, adding missing object fields, enabling deployable Opportunity and contract workflows, and introducing supporting access, layouts, and helper tooling.

Major themes:

- Restored large sets of custom fields for Account, Contact, Case, Opportunity, Opportunity Product, Product, Service Contract, and related revenue objects.
- Enabled the `New_Opportunity` flow to deploy in the scratch org while preserving multi-currency behavior.
- Added contract/CLM support around Service Contract records, including record types, layouts, Lightning pages, and file generation from contract templates.
- Added D&B data support through a custom `DB_Data__c` object and Account lookup fields.
- Added third-party compliance tracking through a custom `Third_Party_Compliance__c` object and Service Contract relationships.
- Added permission sets and profile updates needed for import/load and compliance use cases.
- Added manifests, reports, and helper scripts used to retrieve, sanitize, deploy, and validate metadata in the scratch org.

## Source Inventory

Current metadata inventory under `force-app/main/default`:

| Area | Count / Notes |
| --- | --- |
| Objects represented | 14 |
| Custom/object field metadata files | 944 |
| Apex classes | 2 classes plus metadata files |
| Flows | 2 |
| Permission sets | 3 |
| Lightning record pages | 12 |
| Layouts | 4 |
| Manifests/destructive packages | 10 files |

Object-level field inventory:

| Object | Fields | Record Types | List Views |
| --- | ---: | ---: | ---: |
| Account | 58 | 0 | 3 |
| Case | 168 | 0 | 0 |
| Contact | 166 | 0 | 0 |
| DB_Data__c | 48 | 0 | 1 |
| GSP_Revenue_Target__c | 14 | 0 | 0 |
| Opportunity | 275 | 0 | 1 |
| OpportunityLineItem | 15 | 0 | 0 |
| Partner_Performance__c | 7 | 0 | 0 |
| Product2 | 106 | 0 | 0 |
| Revenue_Schedule__c | 33 | 0 | 0 |
| ServiceContract | 30 | 4 | 2 |
| Third_Party_Compliance__c | 15 | 0 | 1 |
| User | 5 | 0 | 0 |
| User_Region_Settings__c | 4 | 0 | 0 |

## Opportunity Changes

Opportunity received the largest set of customizations. The scratch org includes 275 Opportunity field metadata files, a default Opportunity pipeline list view, and the `New_Opportunity` flow.

Key changes:

- Restored MBD Opportunity fields used for opportunity classification, sales process, tender workflow, renewal calculations, revenue forecasting, product interest, ownership, region, lead sharing, and closed-won/closed-lost analytics.
- Restored multi-currency dependent Opportunity formula fields:
  - `Amount_USD_Active_Currency__c`
  - `Renewal_Calculator_USD_Active_Currency__c`
- Added or restored fields required by related revenue scheduling and Service Contract metadata, including `ServiceContract.Opportunity__c`.
- Added supporting Account fields required by the Opportunity flow:
  - `Account.MBD_Status__c`
  - `Account.MBD_Account_Type__c`
- Added supporting Opportunity Product field:
  - `OpportunityLineItem.Revenue_Months__c`

### New Opportunity Flow Adjustments

The `New_Opportunity` flow was adapted so it can deploy to the scratch org while keeping the restored multi-currency behavior.

Changes made:

- Restored the Opportunity currency picker.
- Restored `CurrencyIsoCode` assignments and filters, including `PricebookEntry.CurrencyIsoCode`.
- Removed Opportunity `RecordTypeId` assignment and lookup logic because this scratch org does not currently include the FL1 Opportunity record type setup.
- Neutralized missing custom-permission formula checks for US/EU access permissions.
- Added supporting metadata required by the flow, including `User_Region_Settings__c`, Account MBD fields, Opportunity Product revenue fields, and the Service Contract Opportunity lookup.

Follow-up note: revisit the remaining flow adaptations after recreating the scratch org with the needed FL1 Opportunity record types and custom permissions.

## Account Changes

Account metadata was expanded with 58 fields and supporting list views/compact layouts.

Key changes:

- Restored core account enrichment fields for region, division, sales ownership, status, ERP/service identifiers, account type, and translated/local account values.
- Added ServiceMax-related Account fields such as ERP account identifiers, sold-to/ship-to values, sales organization, preferred technician, geolocation, business hours, and external ID support.
- Added D&B relationship support through `Account.D_B_Record__c`.
- Added Account page and compact layout metadata used by the MBD UI.

## Contact Changes

Contact metadata was expanded with 166 custom/object fields.

Key changes:

- Restored a broad Contact field set from the source org for MBD data loading and user-facing record completeness.
- Added tooling to generate Contact fields from FieldTrack/describe output.
- Added profile/FLS support for Contact field access through local scripts.

Supporting files:

- `tools/generate_contact_fields_from_fieldtrack.py`
- `tools/contact_fields_from_org.json`
- `tools/set_contact_fls_all_profiles.py`
- `manifest/contact-custom-fields-package.xml`

## Case Changes

Case metadata was expanded with 168 fields.

Key changes:

- Restored Case fields required for MBD/service data loading and scratch-org parity.
- Added a `Case_Data_Load` permission set.
- Captured compare and sanitization reports for generated/missing Case fields.

Supporting reports:

- `reports/case-fields-uat.json`
- `reports/case-fields-scratch.json`
- `reports/case-fields-scratch-after.json`
- `reports/case-generated-fields.csv`
- `reports/case-missing-fields-normalized.csv`
- `reports/case-skipped-fields.csv`

## Product2 Changes

Product metadata was expanded with 106 fields.

Key changes:

- Restored Product2 fields used for SKU/product hierarchy, product classification, manufacturing, serviceability, metrics, support routing, ERP identifiers, installation/decontamination flags, and ServiceMax product behavior.
- Added Product2 manifests separating safer deployable fields from load/config-specific fields:
  - `manifest/product2-safe-fields.xml`
  - `manifest/product2-load-config-fields.xml`
- Added Product Lightning record page and compact layout metadata.

## Revenue Scheduling Changes

Revenue scheduling support was added through the `Revenue_Schedule__c` and `GSP_Revenue_Target__c` objects.

Key changes:

- Added `Revenue_Schedule__c` with 33 fields, including schedule dates, scheduled amounts, forecast values, weighted revenue, status, year/period formula fields, and Opportunity/Product relationships.
- Added `GSP_Revenue_Target__c` with 14 fields for target-related scheduling support.
- Added Opportunity rollup/summary-style fields related to schedule revenue, forecasted amount, latest forecast, and schedule counts.

## Service Contract and CLM Changes

Service Contract metadata was expanded with 30 fields, 4 record types, 2 list views, layouts, Lightning pages, and a contract-file generation flow.

Record types added:

- `Distrbution_Agreement`
- `NDA`
- `Reagent_Rental`
- `Service`

Key changes:

- Added Service Contract fields for Opportunity linkage, third-party compliance linkage/status, pricing totals, contract dates, and core contract details.
- Added Service Contract layouts:
  - `ServiceContract-Service Contract Layout`
  - `ServiceContract-CLM Layout`
- Added Service Contract Lightning pages:
  - `Service_Contract_Record_Page`
  - `CLM_Page`
- Added Malbek/alternative CLM support through the latest repository changes.
- Added a contract file generation flow and invocable Apex action.

### Contract File Generation

Added `ServiceContractFileFromTemplateAction` and `Create_Service_Contract_File_From_Template`.

Behavior:

- Flow passes a Service Contract Id, template ContentVersion Id, and optional new file title.
- Apex validates that the selected template title starts with `Contract template|`.
- Apex validates that the selected template is stored in the `Contract Templates` library.
- Apex copies the template file into the `Contracts` library.
- Apex links the generated file back to the Service Contract using `ContentDocumentLink`.

Test coverage:

- `SvcContractFileTemplateActionTest`

## Third-Party Compliance Changes

Added `Third_Party_Compliance__c` to track compliance records connected to Accounts and Service Contracts.

Key changes:

- Added custom object `Third_Party_Compliance__c` with 15 fields.
- Added formula fields that derive Account address and reference values, preferring linked D&B data when present and falling back to Account billing data.
- Added compliance details such as approval date, expiration date, compliance type, proof-document requirement, and review notes.
- Added Service Contract lookup/status fields:
  - `ServiceContract.Third_Party_Compliance__c`
  - `ServiceContract.Third_Party_Compliance_Status__c`
- Added `Third_Party_Compliance_Access` permission set with object access and field permissions.
- Added layout and list view metadata for the compliance object.

Supporting validation:

- `tools/third_party_compliance_file_smoke.apex`

## D&B Data Changes

Added custom object `DB_Data__c` labeled `D&B Data`.

Key changes:

- Added 48 fields covering DUNS identifiers, parent DUNS details, geocoded address values, HQ location, NAICS values, revenue, employees, financing, sector/subsector, and account segmentation/enrichment values.
- Added `Account__c` lookup back to Account.
- Added `Account_Key__c` as an external ID field for load/matching support.
- Added Account field `D_B_Record__c` to associate Accounts with D&B records.
- Added list view and layout metadata.
- Added deployment manifest:
  - `manifest/db-data-package.xml`

## User Region Settings

Added `User_Region_Settings__c` to support the Opportunity flow and regional behavior.

Fields:

- `UserId__c`
- `Region__c`
- `Division__c`
- `Malbek_User__c`

Purpose:

- Provides a deployable scratch-org substitute for region/division/user behavior expected by the restored Opportunity flow and CLM/Malbek logic.

## Permissions and Profiles

Permission sets added:

- `Case_Data_Load`
- `newMBD_Import_Access`
- `Third_Party_Compliance_Access`

Profile metadata included:

- `System Administrator`
- `Trial Customer Portal User`
- `Chatter Free User`
- `Analytics Cloud Security User`
- `Analytics Cloud Integration User`

Purpose:

- Grant field/object access needed by restored metadata.
- Support data import/load work.
- Support third-party compliance object usage.
- Preserve deployability for profile-dependent metadata in the scratch org.

## Lightning Pages and Layouts

Lightning record pages added or restored:

- `Account_Record_Page`
- `Contact_Record_Page`
- `MBD_Account_Record_Page`
- `MBD_Contact_Record_Page`
- `MBD_Event_Record_Page`
- `MBD_Opportunity_Record_Page1`
- `MBD_Task_Record_Page`
- `Product_Record_Page`
- `Schedule_Record_Page`
- `Service_Contract_Record_Page`
- `TF_Cases1_Admin`
- `CLM_Page`

Layouts added:

- `DB_Data__c-D&B Data Layout`
- `ServiceContract-Service Contract Layout`
- `ServiceContract-CLM Layout`
- `Third_Party_Compliance__c-Third Party Compliance Layout`

## Deployment and Scratch-Org Configuration

Scratch definition:

- `config/project-scratch-def.json`

Important deployment/package files:

- `manifest/deploy-without-multicurrency-fields.xml`
- `manifest/account-custom-fields-package.xml`
- `manifest/contact-custom-fields-package.xml`
- `manifest/db-data-package.xml`
- `manifest/product2-safe-fields.xml`
- `manifest/product2-load-config-fields.xml`
- `manifest/delete-site-field/destructiveChangesPre.xml`
- `manifest/delete-site-field/package.xml`
- `manifest/revert-contract-name-workaround/destructiveChanges.xml`
- `manifest/revert-contract-name-workaround/package.xml`

Notes:

- MultiCurrency is enabled in the scratch org, allowing restored USD active-currency formula fields to remain in local metadata.
- A separate deploy manifest exists for deploying without multi-currency fields when needed.
- Destructive-change manifests were used for cleanup/workaround activities around Account Site and Contract Name metadata.

## Helper Scripts and Reports

Helper scripts:

- `tools/Generate-CaseFieldsFromDescribe.ps1`
- `tools/generate_contact_fields_from_fieldtrack.py`
- `tools/set_contact_fls_all_profiles.py`
- `tools/third_party_compliance_file_smoke.apex`

Reports and generated comparison outputs:

- `reports/opportunity-field-sanitization.csv`
- `reports/opportunity-field-sanitization-summary.json`
- `reports/case-fields-uat.json`
- `reports/case-fields-scratch.json`
- `reports/case-fields-scratch-after.json`
- `reports/case-generated-fields.csv`
- `reports/case-missing-fields-normalized.csv`
- `reports/case-skipped-fields.csv`

These files document the field-reconstruction and sanitization work used to make retrieved metadata deploy cleanly into the scratch org.

## Known Gaps / Follow-Up Items

- Revisit `New_Opportunity` once the scratch org includes the FL1 Opportunity record type setup.
- Reintroduce or validate the custom permission checks that were neutralized for scratch-org deployability.
- Confirm all restored fields have the intended field-level security for target user profiles.
- Validate CLM/Malbek file-library prerequisites in each recreated scratch org:
  - `Contract Templates`
  - `Contracts`
- Confirm Service Contract record type spelling and naming, especially `Distrbution_Agreement`, before promoting metadata beyond the scratch-org context.
- Review deployment manifests before using them against a non-scratch org; several were created for staged/safe deployment and cleanup workflows.

## Preventive Maintenance Work Order Automation MVP

Deployed to `newMBD-scratch` on 3 August 2026 using `manifest/pm-work-order-mvp-package.xml`.

The MVP replaces the ServiceMax package dependency with standard Salesforce records:

- `Asset` for installed equipment, with PM automation, base-date, and Last-PM fields.
- `Entitlement` for the Asset-to-Service-Contract coverage, interval, lead time, and standard Work Order allowance.
- `Product2.Requires_Maintenance__c` as the product eligibility gate.
- `WorkOrder` for generated PM work, with a due date, system-generated marker, and unique external generation key.
- `PMWorkOrderGenerationService`, `PMWorkOrderBatch`, and `PMWorkOrderScheduler` for bulk-safe daily generation.
- `Preventive_Maintenance_Automation_Admin` for configuration and scheduler administration.

Validation evidence:

- Deployment ID: `0AfSv00000L7oOzKAJ`
- Seven of seven `PMWorkOrderGenerationServiceTest` methods passed.
- Batch and scheduler coverage: 100%; generation-service coverage: 120 of 127 executable locations (94.5%).
- Daily scheduled job: `newMBD PM Work Order Generation - Daily`, cron `0 0 2 * * ?`.
- The scratch scheduling user is set to Pacific time, so the current next fire is 02:00 Pacific (09:00 UTC). Production must use a named automation user with an explicitly governed time zone.

Design and operating assumptions are documented in `PREVENTIVE_MAINTENANCE_AUTOMATION_BRD.md` and the generated Word BRD in `output/newMBD_Preventive_Maintenance_Automation_BRD.docx`.
