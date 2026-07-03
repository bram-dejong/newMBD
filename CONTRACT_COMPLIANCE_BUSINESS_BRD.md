# Business Requirements Document: Contract and Compliance Process

Generated: July 3, 2026

## Purpose

This document defines the business requirements for managing contract creation, contract lifecycle tracking, and third-party compliance review for the newMBD process. It is written for business stakeholders and is intentionally separate from the technical requirements specification.

## Business Need

The business needs a consistent way to manage contracts and third-party compliance in one process. Today, contract information, document generation, and compliance status can be difficult to track across teams, tools, and manual handoffs. This creates risk when contract work proceeds without clear visibility into approval status, compliance standing, required documents, or account reference information.

The future process should give commercial, legal, contract, and compliance teams a shared view of contract progress and third-party readiness.

## Business Goals

- Make contract status visible to the teams that need to act on it.
- Standardize the contract lifecycle across supported contract types.
- Reduce manual document creation by using approved contract templates.
- Ensure generated contract documents are linked to the correct contract record.
- Track third-party compliance status before and during contract execution.
- Make it clear whether a reseller, distributor, partner, or other third party is approved, under review, expired, rejected, or not yet started.
- Reduce duplicate account lookups by using trusted account and D&B reference information.
- Improve auditability for contract and compliance decisions.

## Business Outcomes

The process will be successful when:

- Users can quickly understand where a contract is in its lifecycle.
- Contract owners can generate the right contract document from an approved template.
- Legal and business approvers can see which contracts need review or approval.
- Compliance users can maintain third-party status in a structured way.
- Contract users can see the compliance status related to a contract.
- Business teams can report on contracts by type, status, account, and compliance standing.
- Expired, rejected, or missing compliance records are easier to identify.

## Stakeholders

| Stakeholder | Business Interest |
| --- | --- |
| Sales / Commercial Teams | Need to initiate contract work and understand readiness to proceed. |
| Contract Owners | Need to manage contract details, documents, status, and handoffs. |
| Legal / CLM Team | Need visibility into review, approval, signature, and execution stages. |
| Compliance Team | Need to assess and maintain third-party compliance status. |
| Sales Operations | Need clean data, reporting, and process consistency. |
| Leadership / Management | Need visibility into contract progress and compliance risk. |

## In Scope

- Contract lifecycle tracking.
- Contract type classification.
- Contract document generation from approved templates.
- Storage and linking of generated contract documents.
- Third-party compliance tracking.
- Account and third-party reference information.
- Contract-to-compliance visibility.
- Business reporting needs.

## Out of Scope

- Final production integration design.
- Detailed Salesforce field, flow, Apex, or metadata specifications.
- Automated e-signature.
- Automated external compliance screening.
- Full CLM platform integration.
- Data migration plan.
- Detailed security implementation.

## Current Business Challenges

- Contract status is not always visible in one shared place.
- Users may not know which contracts are awaiting business approval, legal review, signatures, or execution.
- Contract document creation can rely on manual template selection and file handling.
- Generated contract documents may not always be clearly tied back to the contract record.
- Compliance status for a third party may be tracked separately from the contract process.
- Contract teams may not know whether a third party is approved, expired, rejected, or still under review.
- Account and third-party reference details may require manual lookup across systems.
- Reporting on contract readiness and compliance risk is limited when process data is not structured.

## Future-State Business Process

### Contract Lifecycle

1. A business user identifies the need for a contract.
2. A contract record is created and assigned the correct contract type.
3. The contract is linked to the relevant account, opportunity, and contact where applicable.
4. The contract owner enters or confirms key contract information.
5. The contract progresses through standard lifecycle stages.
6. Legal, business, or contract teams review and update the contract status as work progresses.
7. A contract document is generated from an approved template when needed.
8. The generated document remains associated with the contract for future reference.
9. The contract proceeds through approval, signature, execution, or closure.

### Third-Party Compliance

1. A compliance record is created for the relevant reseller, distributor, partner, or other third party.
2. The compliance record is linked to the relevant account.
3. Compliance users review and maintain the compliance status.
4. Supporting dates, proof document requirements, and review notes are captured.
5. Contract owners link the relevant compliance record to the contract.
6. Contract teams use the linked compliance status to understand whether the contract can proceed.

## Contract Types

The business process should support these contract types:

- Distribution Agreement
- NDA
- Reagent Rental
- Service

Business note: the current configuration contains a spelling issue for Distribution Agreement. The business should confirm the final label before broader rollout.

## Contract Lifecycle Stages

The business process should support these lifecycle stages:

- Draft
- Offline Business Approval
- Legal Review
- Legal Approved
- Signatures
- Executed
- Inactive

## Compliance Types

The compliance process should support these third-party types:

- Reseller
- Distributor
- Partner
- Other Third Party

## Compliance Statuses

The compliance process should support these statuses:

- Not Started
- In Review
- Approved
- Conditionally Approved
- Expired
- Rejected

## Business Requirements

| ID | Requirement |
| --- | --- |
| BR-001 | The business must be able to classify each contract by contract type. |
| BR-002 | The business must be able to track each contract through a standard lifecycle. |
| BR-003 | The business must be able to associate contracts with the relevant customer or third-party account. |
| BR-004 | The business must be able to associate contracts with the related commercial opportunity where applicable. |
| BR-005 | Contract owners must be able to create contract documents using approved templates. |
| BR-006 | Generated contract documents must remain linked to the related contract. |
| BR-007 | The business must be able to identify which contracts are awaiting legal review, approval, signature, execution, or closure. |
| BR-008 | The business must be able to track compliance status for resellers, distributors, partners, and other third parties. |
| BR-009 | The business must be able to link a compliance record to the relevant account. |
| BR-010 | The business must be able to link a compliance record to the relevant contract. |
| BR-011 | Contract users must be able to see the compliance status associated with a contract. |
| BR-012 | Compliance users must be able to record approval date, expiration date, proof document requirement, and review notes. |
| BR-013 | The business must be able to identify third parties with expired, rejected, conditionally approved, or not-started compliance. |
| BR-014 | The business must be able to report on contracts by type, lifecycle stage, account, and compliance status. |
| BR-015 | The business must be able to report on third-party compliance records by account, type, status, approval date, and expiration date. |

## Business Rules

- A contract should not be considered ready for execution unless required business and legal reviews are complete.
- A contract involving a third party should have a related compliance record when compliance review is required.
- Compliance status should be visible to contract users before execution.
- Approved templates should be used for generated contract documents.
- Generated contract documents should be retained with the related contract.
- Compliance records should include enough information to determine whether the third party is approved, conditionally approved, expired, rejected, under review, or not started.
- Where trusted account enrichment data exists, it should be used to reduce manual account reference work.

## Reporting Requirements

The business needs reporting to answer:

- How many contracts are in each lifecycle stage?
- Which contracts are awaiting legal review?
- Which contracts are awaiting signatures?
- Which contracts are executed or inactive?
- Which contracts are tied to third parties with expired or rejected compliance?
- Which third parties are approved, conditionally approved, in review, expired, rejected, or not started?
- Which compliance records are approaching expiration?
- Which third parties require proof documents?
- Which contracts are associated with each account or opportunity?

## Controls and Governance

- Contract templates should be governed by the appropriate business or legal owner.
- Template changes should be controlled so users generate documents from current approved templates.
- Compliance status should be maintained by authorized users.
- Compliance decisions should be supported by review notes and relevant dates.
- Contract lifecycle stages should be updated by the responsible business, legal, or contract owner.
- Reporting should be reviewed periodically to identify stalled contracts and compliance risks.

## Key Decisions Needed

| Decision | Owner |
| --- | --- |
| Confirm final contract type labels, including Distribution Agreement spelling. | Business / Legal |
| Define which contract types require compliance review before execution. | Business / Compliance / Legal |
| Define who owns each lifecycle stage transition. | Business / Legal |
| Define who may approve or conditionally approve compliance records. | Compliance |
| Define whether expired or rejected compliance should block contract execution. | Compliance / Legal / Business |
| Define whether reminder or escalation reporting is required for approaching compliance expiration. | Compliance / Operations |
| Confirm whether Malbek or another CLM process will remain a manual handoff or become integrated. | Business / Legal / IT |

## Success Measures

- Reduced manual contract document creation effort.
- Reduced uncertainty about contract status.
- Improved visibility into contracts awaiting review, approval, or signature.
- Improved visibility into third-party compliance risk.
- Fewer contracts progressing without known compliance status where compliance is required.
- Improved reporting quality for contract and compliance leadership.
- Better audit trail for contract and compliance decisions.

## Open Questions

- Which contract types require third-party compliance review?
- Should compliance approval be mandatory before a contract can move to Executed?
- Should conditionally approved compliance allow contract execution?
- Who owns ongoing monitoring of expiration dates?
- What evidence or proof documents are required by compliance type?
- Are different countries, regions, or business units subject to different compliance requirements?
- Should business users be allowed to create compliance records, or should that remain with Compliance?
- What reporting cadence is needed for leadership review?

