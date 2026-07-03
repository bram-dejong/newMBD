# Business Requirements Document: Contract and Compliance Components

Generated: July 3, 2026

## Document Purpose

This BRD describes the business requirements for the Contract, CLM, and Third-Party Compliance components configured in the `newMBD` setup. It focuses on the business process, user outcomes, data needs, functional requirements, controls, and known assumptions for the Service Contract and Third Party Compliance solution.

## Business Context

The newMBD setup includes Salesforce-native contract and compliance capabilities to support MBD commercial and partner workflows. The configuration provides a structured way to create and manage Service Contract records, generate contract files from approved templates, connect contracts to Opportunities and Accounts, and track third-party compliance status for resellers, distributors, partners, and other third parties.

The current solution is also intended to provide a lightweight Salesforce replacement or bridge for Third Party Manager-style compliance tracking while supporting CLM/Malbek-related contract processes.

## Business Objectives

- Provide a single Salesforce record for managing contract lifecycle information.
- Support multiple contract types with consistent lifecycle statuses.
- Allow users to generate contract documents from approved templates.
- Store generated contract files in a controlled Salesforce library.
- Link generated documents back to the originating Service Contract.
- Track third-party compliance status directly in Salesforce.
- Surface compliance status on Service Contract records.
- Reduce manual lookup of Account, D&B, and third-party reference details.
- Support business, legal, and compliance review processes with auditable Salesforce data.

## Scope

In scope:

- Service Contract record types and lifecycle status values.
- Service Contract layouts and Lightning record pages.
- Contract file generation from Salesforce Files templates.
- Contract template library and generated contract library dependency.
- Third Party Compliance custom object.
- Account and D&B-derived compliance reference fields.
- Service Contract lookup to Third Party Compliance.
- Permission set support for compliance users.
- Scratch-org assumptions and follow-up gaps.

Out of scope for the current implementation:

- Full external CLM/Malbek integration automation.
- E-signature integration.
- Automated legal approval routing.
- Automated compliance screening with an external risk platform.
- Automated expiration notifications unless added in a later phase.
- Production data migration strategy.

## Stakeholders

| Stakeholder Group | Role in Process |
| --- | --- |
| Sales / Commercial Users | Create or initiate contracts tied to Accounts and Opportunities. |
| Contract Owners | Maintain contract details, status, terms, and generated files. |
| Legal / CLM Users | Review contracts, manage legal lifecycle status, and support approval/signature steps. |
| Compliance Users | Create and maintain Third Party Compliance records. |
| Sales Operations / Data Load Users | Support metadata, imports, and field completeness. |
| Salesforce Administrators | Maintain permissions, layouts, flows, libraries, templates, and deployment metadata. |

## Current Process Overview

### Contract Process

1. User creates or opens a Service Contract.
2. User selects the appropriate Service Contract record type.
3. User maintains core contract details such as Account, Contact, Opportunity, dates, pricing, status, and special terms.
4. User optionally links the contract to a Third Party Compliance record.
5. User launches the contract file generation flow.
6. Flow displays available contract templates whose latest file title starts with `Contract template|`.
7. User selects a template and optionally enters a custom file title.
8. Apex copies the selected template file into the `Contracts` library.
9. Apex links the generated file back to the Service Contract.
10. User continues the lifecycle through review, approval, signature, execution, or inactive status.

### Compliance Process

1. Compliance or business user creates a Third Party Compliance record.
2. User links the compliance record to an Account.
3. Salesforce derives account reference and address details from D&B data when an Account has a D&B record.
4. If D&B data is not present, Salesforce falls back to Account billing and sold-to details.
5. User maintains compliance type, status, approval date, expiration date, proof document requirement, and review notes.
6. Contract owner links the relevant Third Party Compliance record to the Service Contract.
7. Service Contract displays the compliance status through a formula field.

## Service Contract Requirements

### Contract Types

The system shall support the following Service Contract record types:

| Record Type API Name | Label |
| --- | --- |
| `Distrbution_Agreement` | Distrbution Agreement |
| `NDA` | NDA |
| `Reagent_Rental` | Reagent Rental |
| `Service` | Service |

Note: `Distrbution_Agreement` and `Distrbution Agreement` appear to be misspelled in the current metadata and should be confirmed before production promotion.

### Contract Lifecycle Statuses

Each configured Service Contract record type supports these status values:

- Draft
- Offline Business Approval
- Legal Review
- Legal Approved
- Signatures
- Executed
- Inactive

### Functional Requirements

| ID | Requirement | Priority |
| --- | --- | --- |
| CON-001 | The system shall allow users to create and manage Service Contract records by contract type. | Must Have |
| CON-002 | The system shall allow Service Contracts to be linked to Accounts. | Must Have |
| CON-003 | The system shall allow Service Contracts to be linked to Contacts. | Should Have |
| CON-004 | The system shall allow Service Contracts to be linked to Opportunities using `Opportunity__c`. | Must Have |
| CON-005 | The system shall support lifecycle tracking using the configured status values. | Must Have |
| CON-006 | The system shall support contract pricing and value fields including subtotal, discount, tax, shipping/handling, total price, and grand total. | Should Have |
| CON-007 | The system shall support contract start date, end date, activation date, and term tracking. | Must Have |
| CON-008 | The system shall allow users to capture special terms and description details. | Should Have |
| CON-009 | The system shall allow a Service Contract to reference a Third Party Compliance record. | Must Have |
| CON-010 | The system shall display the linked compliance status on the Service Contract. | Must Have |
| CON-011 | The system shall provide layouts and Lightning pages for Service Contract and CLM users. | Must Have |

## Contract Document Generation Requirements

### Template Rules

- Contract templates must be stored as Salesforce Files.
- Template file titles must start with `Contract template|`.
- The flow only presents latest ContentVersion records whose titles start with `Contract template|`.
- Apex validates that the selected template belongs to the `Contract Templates` library.
- Generated contract files are published to the `Contracts` library.

### Functional Requirements

| ID | Requirement | Priority |
| --- | --- | --- |
| DOC-001 | The system shall provide a screen flow named `Create Service Contract File From Template`. | Must Have |
| DOC-002 | The flow shall be launchable in the context of a Service Contract record. | Must Have |
| DOC-003 | The flow shall display eligible contract templates for selection. | Must Have |
| DOC-004 | The user shall be able to optionally enter a new file title. | Should Have |
| DOC-005 | If no custom file title is entered, the system shall generate a title using the Service Contract name and selected template name. | Should Have |
| DOC-006 | The system shall copy the selected template file rather than modifying the original template. | Must Have |
| DOC-007 | The generated file shall be published to the `Contracts` library. | Must Have |
| DOC-008 | The generated file shall be linked to the originating Service Contract. | Must Have |
| DOC-009 | The system shall show the user a success message after file creation. | Should Have |
| DOC-010 | The system shall block invalid templates that do not use the required title prefix. | Must Have |
| DOC-011 | The system shall block templates that are not stored in the `Contract Templates` library. | Must Have |

### Error and Exception Requirements

| Scenario | Expected Behavior |
| --- | --- |
| Missing Service Contract Id | User receives an error that Service Contract Id is required. |
| Missing template ContentVersion Id | User receives an error that template selection is required. |
| Template not found | User receives an error that the selected template file could not be found. |
| Template title missing required prefix | User receives an error that the template must start with `Contract template|`. |
| Template not in approved library | User receives an error that the template must be stored in `Contract Templates`. |
| Generated contract library missing | User receives an error that the `Contracts` library could not be found. |

## Third Party Compliance Requirements

### Compliance Object

The solution includes a custom object:

| Object | Label | Purpose |
| --- | --- | --- |
| `Third_Party_Compliance__c` | Third Party Compliance | Tracks reseller and account compliance status as a lightweight Salesforce replacement for Third Party Manager. |

Object behavior:

- Auto-number naming using `TPC-{00000}`.
- Activities enabled.
- Chatter feed enabled.
- Field history enabled.
- Reports enabled.
- Search enabled.
- Sharing enabled.

### Compliance Types

The system shall support these compliance types:

- Reseller
- Distributor
- Partner
- Other Third Party

Default value:

- Reseller

### Compliance Statuses

The system shall support these compliance statuses:

- Not Started
- In Review
- Approved
- Conditionally Approved
- Expired
- Rejected

Default value:

- Not Started

### Functional Requirements

| ID | Requirement | Priority |
| --- | --- | --- |
| CMP-001 | The system shall allow authorized users to create Third Party Compliance records. | Must Have |
| CMP-002 | The system shall allow each compliance record to be linked to an Account. | Must Have |
| CMP-003 | The system shall track compliance type. | Must Have |
| CMP-004 | The system shall track compliance status. | Must Have |
| CMP-005 | The system shall track approval date. | Should Have |
| CMP-006 | The system shall track expiration date. | Should Have |
| CMP-007 | The system shall identify whether proof documents are required. | Should Have |
| CMP-008 | The system shall allow compliance users to capture review notes. | Should Have |
| CMP-009 | The system shall derive account reference details from D&B data when available. | Must Have |
| CMP-010 | The system shall fall back to Account billing and sold-to details when D&B data is not available. | Must Have |
| CMP-011 | The system shall allow a compliance record to be linked to one or more Service Contracts through the Service Contract lookup. | Must Have |
| CMP-012 | The system shall expose compliance records in reports. | Should Have |

## Compliance Data Derivation Rules

| Field | Derivation Rule |
| --- | --- |
| Account Detail Source | `D&B Record` when Account has `D_B_Record__c`; otherwise `Account Sold-To / Billing`. |
| Account Reference Name | D&B DUNS name when available; otherwise Account name. |
| Account Reference Number | D&B DUNS number when available; otherwise Account sold-to ID. |
| Account Address City | D&B geocoded city when available; otherwise Account billing city. |
| Account Address Country | D&B geocoded country when available; otherwise Account billing country. |
| Account Address Postal Code | D&B geocoded zip when available; otherwise Account billing postal code. |
| Account Address State | D&B geocoded state when available; otherwise Account billing state. |
| Account Address Street | Account billing street. |

## Data Model

### Core Relationships

| Source | Relationship | Target |
| --- | --- | --- |
| ServiceContract | Lookup via `Opportunity__c` | Opportunity |
| ServiceContract | Standard lookup via `AccountId` | Account |
| ServiceContract | Standard lookup via `ContactId` | Contact |
| ServiceContract | Lookup via `Third_Party_Compliance__c` | Third Party Compliance |
| Third Party Compliance | Lookup via `Account__c` | Account |
| Account | Lookup via `D_B_Record__c` | D&B Data |

### Key Service Contract Fields

- `AccountId`
- `ContactId`
- `Opportunity__c`
- `Third_Party_Compliance__c`
- `Third_Party_Compliance_Status__c`
- `Status`
- `ApprovalStatus`
- `StartDate`
- `EndDate`
- `ActivationDate`
- `Term`
- `TotalPrice`
- `GrandTotal`
- `SpecialTerms`
- `Description`

### Key Third Party Compliance Fields

- `Account__c`
- `Compliance_Type__c`
- `Compliance_Status__c`
- `Approval_Date__c`
- `Expiration_Date__c`
- `Proof_Documents_Required__c`
- `Review_Notes__c`
- `Account_Detail_Source__c`
- `Account_Reference_Name__c`
- `Account_Reference_Number__c`

## Security and Access Requirements

| ID | Requirement | Priority |
| --- | --- | --- |
| SEC-001 | The system shall provide a permission set for Third Party Compliance access. | Must Have |
| SEC-002 | Authorized users shall be able to create, read, edit, and delete Third Party Compliance records. | Must Have |
| SEC-003 | Authorized users shall have read access to derived Account reference fields. | Must Have |
| SEC-004 | Authorized users shall be able to edit compliance business fields such as type, approval date, expiration date, proof document requirement, and review notes. | Must Have |
| SEC-005 | Service Contract users shall be able to read the linked compliance status. | Must Have |
| SEC-006 | Template and generated contract libraries shall be access-controlled through Salesforce library membership and file permissions. | Must Have |

Implemented permission set:

- `Third_Party_Compliance_Access`

## Reporting Requirements

| ID | Requirement | Priority |
| --- | --- | --- |
| RPT-001 | Users shall be able to report on Third Party Compliance records by Account, type, status, approval date, and expiration date. | Should Have |
| RPT-002 | Users shall be able to report on Service Contracts by contract type and lifecycle status. | Should Have |
| RPT-003 | Users shall be able to identify Service Contracts linked to expired, rejected, or not-started compliance records. | Should Have |
| RPT-004 | Users shall be able to identify compliance records requiring proof documents. | Should Have |
| RPT-005 | Users shall be able to review contract records with generated files through Salesforce Files related lists or reportable file relationships where available. | Could Have |

## Business Rules

- A contract template is valid only when its latest file title starts with `Contract template|`.
- A contract template is approved for generation only when stored in the `Contract Templates` library.
- Generated contract documents must be stored in the `Contracts` library.
- Generated contract documents must be linked to the originating Service Contract.
- Service Contract compliance status is read from the linked Third Party Compliance record.
- Compliance status defaults to `Not Started`.
- Compliance type defaults to `Reseller`.
- D&B data takes precedence over Account billing data for derived compliance reference details when a D&B record is linked to the Account.

## Assumptions

- Salesforce Files and Libraries are enabled in the org.
- The `Contract Templates` library exists before users run the document generation flow.
- The `Contracts` library exists before users run the document generation flow.
- Users who run the flow have access to the selected template file and the target generated-contract library.
- Contract templates follow the required naming convention.
- Compliance users will maintain status, approval, expiration, and review fields manually in the current phase.
- External CLM/Malbek automation may be added later and is not fully represented by the scratch-org metadata.

## Dependencies

- Service Contract object and record types.
- Salesforce Files, ContentVersion, ContentDocumentLink, and ContentWorkspace.
- `ServiceContractFileFromTemplateAction` Apex class.
- `Create_Service_Contract_File_From_Template` flow.
- `Third_Party_Compliance__c` custom object.
- Account D&B relationship field and D&B data object.
- `Third_Party_Compliance_Access` permission set.
- Service Contract and CLM Lightning pages/layouts.

## Risks and Open Items

| Risk / Open Item | Impact | Recommended Action |
| --- | --- | --- |
| `Distrbution_Agreement` appears misspelled. | May create naming/reporting confusion or deployment churn later. | Confirm intended spelling before promoting beyond scratch org. |
| No automated legal approval routing is currently defined. | Status changes may rely on manual discipline. | Define approval flow or governance if required. |
| Compliance expiration is tracked but no reminder automation is documented. | Expired compliance records may be missed. | Add scheduled flow/report subscription in a future phase. |
| Template libraries must exist in each org. | Flow/Apex will fail if libraries are missing. | Include library setup in deployment runbook. |
| Template naming convention is mandatory. | Valid templates may not appear if misnamed. | Document template publishing procedure for admins/legal users. |
| External CLM/Malbek requirements are not fully captured in metadata. | Integration expectations may exceed current scratch-org build. | Confirm target CLM process and integration scope. |
| Compliance object sharing is broad in scratch metadata. | Production access may need tighter control. | Review OWD, sharing rules, and permission sets before production. |

## Acceptance Criteria

- Users can create Service Contract records for the configured contract types.
- Users can move contracts through the configured lifecycle statuses.
- Users can link a Service Contract to an Opportunity.
- Users can create a Third Party Compliance record and link it to an Account.
- Compliance status can be maintained using the configured status values.
- Service Contract displays the status from the linked compliance record.
- Flow displays eligible contract templates with the required title prefix.
- Flow creates a new contract file from a selected template.
- Generated file is stored in the `Contracts` library.
- Generated file is linked back to the Service Contract.
- Unauthorized or invalid template selections are blocked by Apex validation.

## Future Enhancements

- Add automated compliance expiration reminders.
- Add approval routing for Legal Review and Legal Approved transitions.
- Add validation rules requiring compliance approval before contract execution for selected contract types.
- Add report/dashboard package for contract status, compliance status, and expiring compliance records.
- Add guided contract creation from Opportunity.
- Add automated template selection based on record type, country, region, or contract type.
- Add e-signature integration.
- Add deeper CLM/Malbek integration once the target process is finalized.

