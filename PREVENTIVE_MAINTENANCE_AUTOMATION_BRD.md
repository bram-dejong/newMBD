# Business Requirements Document: Preventive Maintenance Work Order Automation

**Version:** 0.1 MVP  
**Status:** Draft for business validation  
**Date:** 3 August 2026  
**Target:** newMBD Salesforce scratch org  
**Primary classification:** Code/automation logic  
**Secondary classification:** Process and data

## 1. Executive summary

newMBD will not contain the ServiceMax managed package. It therefore needs a package-independent replacement for the automated process that creates preventive-maintenance (PM) Work Orders from installed-base and service-contract data.

The MVP uses standard Salesforce `Asset` as the installed-product record, standard `Entitlement` as the explicit Asset-to-Service-Contract coverage record, and standard `WorkOrder` as the generated service record. A daily Batch Apex process evaluates opted-in PM Entitlements, calculates the next due cycle from Asset PM dates and the configured interval, validates the effective entitlement and contract dates, enforces the entitled Work Order count, and creates at most one idempotent Work Order per Entitlement in each run.

> **Decision requested:** approve the MVP rules and pilot boundaries in this BRD, then validate them against 10-20 representative ServiceMax UAT examples before production design is declared functionally equivalent.

## 2. Situation and desired outcome

### 2.1 Current state

ServiceMax UAT stores the installed base in `SVMXC__Installed_Product__c` and uses managed-package PM automation. Read-only metadata discovery confirmed these current rule inputs:

- product `Requires Maintenance` eligibility;
- Installed Product `PM base date` and `Last PM` dates;
- next PM due date precedence of PM base date, then Last PM, then Service Contract start date, plus a configured interval in days;
- a creation horizon based on next due date minus the Service Contract lead time;
- Service Contract frequency and total/remaining PM Work Order allowance;
- prevention of generation beyond the Service Contract end date; and
- scheduled ServiceMax preventive-maintenance classes.

### 2.2 Problem statement

Removing the ServiceMax package removes the objects, formulas, and scheduled services that currently qualify records and create PM work. Without a replacement, due maintenance may not become actionable Work Orders and service-contract entitlement may be applied inconsistently.

### 2.3 Desired outcome

Every eligible, contract-entitled Asset receives one traceable standard Work Order for each due PM cycle early enough for service coordination, without duplicates on retries or concurrent runs.

## 3. Objectives and success measures

- Generate a Work Order within 24 hours after an eligible PM cycle enters its creation horizon.
- Create zero duplicate automated Work Orders for the same Entitlement and due date.
- Relate every generated Work Order to its Asset, Entitlement, Service Contract, account, due date, and deterministic generation key.
- Isolate record-level errors so one invalid Entitlement does not stop valid records in the batch.
- Provide a package-independent implementation with no `SVMXC` references.
- For production readiness, expose skipped/error reasons and reconcile evaluated, created, skipped, and failed counts. This is a post-MVP operational requirement unless added before pilot.

## 4. Stakeholders and ownership

| Role | Responsibility |
|---|---|
| Service Process Owner | Approves PM policy, cadence, lead time, overdue behavior, and parity decisions. |
| Installed Base / Asset Data Owner | Owns Asset, Product, PM base date, and Last PM data quality. |
| Service Contract / Entitlement Owner | Owns contract coverage, effective dates, and entitled visit counts. |
| Salesforce Product Owner / Technical Lead | Owns solution design, delivery, security, scheduling, and support model. |
| Service Operations / Dispatch | Confirms generated Work Order content and downstream usability. |
| UAT / Release Owner | Approves test evidence and rollout readiness. |

## 5. Scope

### 5.1 MVP scope

- Standard `Asset` as the Installed Product replacement.
- Existing `Product2.Requires_Maintenance__c` as the product eligibility gate.
- Standard `Entitlement` as the explicit Asset-to-Service-Contract coverage relationship.
- One PM cadence per PM-enabled Entitlement.
- Asset PM automation opt-in, PM base date, and Last PM date.
- Entitlement interval, creation lead time, and standard `WorkOrdersPerEntitlement` allowance.
- Daily scheduled/batched evaluation and standard Work Order creation.
- Work Order PM marker, due date, and unique external generation key.
- Partial-success processing, repeat-safe execution, automated tests, and administrator permission set.
- Scratch-org deployment and representative MVP validation.

### 5.2 Out of scope for MVP

- Multiple competing PM Entitlements for the same Asset; the pilot must maintain one active PM-enabled Entitlement per Asset.
- Usage-, counter-, event-, or predictive-maintenance schedules.
- Missed-cycle bulk backfill; the MVP creates at most one cycle per Entitlement per run.
- Service Appointments, dispatch, optimization, technician assignment, task/parts templates, and customer notifications.
- Full ServiceMax PM Plan/template and field-map parity.
- Historical data migration, contract-renewal automation, and production monitoring dashboards.
- Automatic update of Asset Last PM Date from Work Order completion; the pilot retains the existing data-owner/integration responsibility until completion evidence is agreed.

## 6. Source-to-target mapping

| ServiceMax concept | newMBD MVP target | Notes |
|---|---|---|
| Installed Product | `Asset` | Standard Salesforce installed-base record. |
| Product maintenance gate | `Product2.Requires_Maintenance__c` | Existing newMBD field. |
| Installed Product PM base date | `Asset.PM_Base_Date__c` | Initial schedule anchor. |
| Installed Product Last PM | `Asset.Last_PM_Date__c` | Fallback anchor when PM base date is blank. |
| Package Service Contract / covered product | `ServiceContract` + `Entitlement` | Entitlement explicitly links Asset, account, and Service Contract. |
| Contract PM interval | `Entitlement.PM_Interval_Days__c` | Positive whole days; MVP default 365. |
| Contract creation lead | `Entitlement.PM_Creation_Lead_Days__c` | Non-negative calendar days; MVP default 30. |
| PM Work Orders allowed | `Entitlement.WorkOrdersPerEntitlement` | Standard field; counts generated PM Work Orders for that Entitlement. |
| PM generated work | `WorkOrder` | Uses standard Asset, Entitlement, Service Contract, account, and Start Date. |
| PM traceability | Work Order PM fields | System-generated marker, due date, and immutable unique generation key. |

## 7. Future-state process

1. A data owner marks the Product as requiring maintenance.
2. A data owner enables PM automation on the Asset and supplies PM base/Last PM data as available.
3. A PM-specific Entitlement links the Asset to the correct Service Contract and carries interval, lead time, effective dates, and total allowed Work Orders.
4. The daily scheduler launches a Batch Apex evaluation.
5. The evaluator validates the Asset, Product, Entitlement, Service Contract, dates, cadence, and remaining allowance.
6. The evaluator calculates the next due date and creation horizon.
7. If eligible, the evaluator upserts a standard Work Order using a deterministic unique key.
8. Reruns or overlapping jobs resolve to the same key and do not create a duplicate.
9. Service Operations manages the Work Order through the normal newMBD process.

## 8. Business rules

| ID | Rule |
|---|---|
| PM-BR-01 | `Asset.PM_Automation_Enabled__c` is the explicit installed-base gate. |
| PM-BR-02 | The Asset must reference a Product where `Requires_Maintenance__c = true`. |
| PM-BR-03 | The Entitlement must be PM enabled and must reference both an Asset and a Service Contract. |
| PM-BR-04 | Effective start is the later populated value of Entitlement start and Service Contract start; effective end is the earlier populated value of Entitlement end and Service Contract end. |
| PM-BR-05 | The run date and calculated due date must be within the effective coverage window. |
| PM-BR-06 | Interval must be a positive whole number of days. Lead time must be zero or a positive whole number of days. Defaults are 365 and 30. |
| PM-BR-07 | Initial anchor precedence is PM base date, then Last PM date, then effective coverage start. The first due date is anchor plus interval, matching the observed ServiceMax UAT formula. |
| PM-BR-08 | After a PM Work Order exists, the latest generated PM due date becomes the cadence anchor; the next due date is that date plus interval. This avoids mutating the Asset base date during creation. |
| PM-BR-09 | A cycle is in the creation horizon when run date is on or after due date minus lead time. Overdue cycles remain eligible. |
| PM-BR-10 | The number of generated PM Work Orders for an Entitlement must remain below standard `WorkOrdersPerEntitlement`. Blank, zero, or negative allowance is not eligible. |
| PM-BR-11 | At most one Work Order is proposed for one Entitlement in one run; historical catch-up flooding is not allowed. |
| PM-BR-12 | Generation key format is `AssetId:EntitlementId:YYYY-MM-DD`. It is unique and immutable. |
| PM-BR-13 | Work Order creation does not change Last PM Date. Last PM means completed maintenance, not generated work. |
| PM-BR-14 | Missing or inconsistent data causes a skip; the automation never guesses an alternate contract or Asset. |
| PM-BR-15 | Existing generated Work Orders remain after contract expiry or PM disablement; only future creation stops. |

## 9. Functional requirements

| ID | Priority | Requirement |
|---|---|---|
| PM-FR-001 | Must | Run through scheduled Batch Apex once per day; pilot schedule is 02:00 in the scheduling user's Salesforce time zone. |
| PM-FR-002 | Must | Support an authorized on-demand batch execution for testing and recovery. |
| PM-FR-003 | Must | Evaluate only explicitly PM-enabled Entitlements related to an opted-in Asset. |
| PM-FR-004 | Must | Require a maintenance-eligible Product. |
| PM-FR-005 | Must | Validate Entitlement and Service Contract effective dates against both run date and calculated due date. |
| PM-FR-006 | Must | Use Asset PM base date, Last PM date, coverage start, interval, lead time, and existing PM Work Orders to calculate eligibility. |
| PM-FR-007 | Must | Enforce `WorkOrdersPerEntitlement` as the PM visit allowance. |
| PM-FR-008 | Must | Create a standard Work Order related to Asset, Entitlement, Service Contract, and account. |
| PM-FR-009 | Must | Populate Subject, Start Date, PM due date, PM marker, and generation key. |
| PM-FR-010 | Must | Enforce duplicate protection at database level with a unique external-id key. |
| PM-FR-011 | Must | Process records in bulk and allow partial DML success. |
| PM-FR-012 | Must | Run without ServiceMax objects, fields, classes, or Field Service Maintenance Plan licensing. |
| PM-FR-013 | Must | Grant configuration and operation through a least-privilege permission set. |
| PM-FR-014 | Should | Provide run-level and record-level skip/error telemetry before production pilot. |
| PM-FR-015 | Should | Provide a dry-run preview and due-soon/overdue exception reporting. |
| PM-FR-016 | Should | Update Asset Last PM Date from controlled Work Order completion evidence once business completion rules are approved. |

## 10. Work Order mapping

| Work Order field | Source / value |
|---|---|
| `AssetId` | Entitlement Asset |
| `EntitlementId` | Evaluated PM Entitlement |
| `ServiceContractId` | Entitlement Service Contract |
| `AccountId` | Entitlement account, otherwise Asset account |
| `Subject` | `Preventive Maintenance - {Asset Name}` |
| `StartDate` | PM due date at 08:00 org time |
| `System_Generated_PM__c` | `true` |
| `PM_Due_Date__c` | Calculated cycle due date |
| `PM_Generation_Key__c` | `AssetId:EntitlementId:YYYY-MM-DD` |
| `Status` | Standard object default (`New` in scratch) |

## 11. Exceptions and recovery

The MVP skips a candidate when PM is disabled, Product is missing/ineligible, Asset or Service Contract is missing, interval/lead/allowance is invalid, effective dates are missing or not current, due date is outside coverage, the creation horizon has not been reached, or allowance is exhausted. Database insert errors are isolated with `Database.upsert(..., false)`.

The unique external generation key is the concurrency control. After data correction, rerunning the batch is safe. Production readiness requires stable reason codes and an administrator-facing run/exception report; Apex Jobs and generated Work Orders provide interim scratch-org evidence.

## 12. Security and nonfunctional requirements

- Scheduled processing runs in system context and must use a named automation user with an explicitly governed Salesforce time zone in production.
- The PM Automation Administrator permission set grants only required object, field, and class access.
- Batch queries and DML must remain bulk-safe with no query or DML inside record loops.
- One record failure must not roll back other eligible records.
- The generation key is a unique external ID and must not be user-editable outside PM administration.
- No sensitive contract narrative is copied into Work Orders or diagnostic output.
- Production volume must be measured and tested against the overnight processing window before release.

## 13. Acceptance criteria

| ID | Given / When / Then |
|---|---|
| AC-01 | Given an opted-in Asset, maintenance Product, valid PM Entitlement and Service Contract, remaining allowance, and due date inside the horizon, when the job runs, then exactly one correctly related standard Work Order is created. |
| AC-02 | Given PM base date is populated, when no PM Work Order exists, then first due is PM base date plus interval. |
| AC-03 | Given PM base date is blank and Last PM is populated, then first due is Last PM plus interval. |
| AC-04 | Given both Asset dates are blank, then effective coverage start plus interval is used. |
| AC-05 | Given due date is one day outside the lead horizon, then no Work Order is created; on the exact horizon boundary it is eligible. |
| AC-06 | Given Product does not require maintenance or Asset/Entitlement PM is disabled, then no Work Order is created. |
| AC-07 | Given run date or due date is outside Entitlement/contract dates, then no Work Order is created. |
| AC-08 | Given the allowed Work Order count is exhausted, then no additional PM Work Order is created. |
| AC-09 | Given the same evaluator runs twice or overlaps, then only one Work Order exists for the Entitlement and due date. |
| AC-10 | Given an eligible record and an invalid record share a batch, then the valid Work Order succeeds and the invalid candidate does not stop the batch. |
| AC-11 | Given a created Work Order, then Asset, Entitlement, Service Contract, Account, Start Date, PM due date, PM marker, and generation key are traceable. |
| AC-12 | Given an expired contract, PM disablement, or future data correction, then prior generated Work Orders are retained unchanged. |
| AC-13 | Metadata deploy and Apex tests succeed in newMBD scratch without any `SVMXC` dependency. |

## 14. Data readiness and migration

Before pilot, profile the in-scope population for Product maintenance eligibility, Asset PM opt-in, PM base/Last PM dates, one unambiguous PM Entitlement per Asset, Service Contract links and dates, valid interval/lead values, and visit allowance. Create PM Entitlements only after business ownership confirms the covered Asset and contract.

No production migration is included in this MVP. Representative scratch test data proves rule behavior, not source-data readiness.

## 15. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Incomplete or incorrect PM data | Missing or mistimed work | Readiness report, explicit opt-in, skip invalid data, accountable data owner. |
| UAT rule divergence | Functional parity gap | Compare 10-20 representative UAT cases and record each divergence as a business decision. |
| Duplicate/concurrent execution | Duplicate service demand | Unique external generation key plus idempotent upsert. |
| Multiple PM coverages per Asset | Ambiguous schedule | Pilot restriction to one PM-enabled Entitlement; add schedule/junction design in Phase 2. |
| Missing operational telemetry | Silent skipped work | Add run and reason-code logging before production pilot. |
| Production Work Order validation rules | Insert failures | Validate required mappings using production-like UAT data and partial-success behavior. |
| High volume | Overnight job overrun | Batch processing, volume baseline, indexes/selectivity review, and load test. |

## 16. Assumptions and open decisions

### 16.1 Assumptions

- This is a functional replacement MVP, not feature-for-feature ServiceMax PM Plan parity.
- Entitlement is the authoritative PM coverage relationship and each pilot Asset has at most one active PM-enabled Entitlement.
- PM cadence is a whole number of calendar days.
- Product `Requires_Maintenance__c` is authoritative for product eligibility.
- Standard Asset, Entitlement, ServiceContract, and WorkOrder are available in the target org.
- Last PM Date is initially loaded and then maintained by an agreed operational/integration process.

### 16.2 Decisions required before production

1. Confirm fixed, calendar-anchored cadence versus rolling cadence after actual completion.
2. Confirm the Service Contract business-active rule in addition to date coverage.
3. Confirm whether multiple PM plans per Asset require a dedicated `Asset_PM_Schedule__c` model.
4. Confirm completion evidence and whether a closed PM Work Order updates Last PM automatically.
5. Confirm Work Order record type, ownership queue, priority, duration, required fields, and downstream dispatch behavior.
6. Confirm overdue/backfill policy and handling of cancelled PM Work Orders.
7. Approve production telemetry, pause control, support dashboard, retention, and SLA.
8. Confirm schedule time, named automation user, and that user's Salesforce time zone. The scratch job is scheduled for 02:00 Pacific time because that is the scratch scheduling user's current setting.

## 17. UAT approach and approval

Select 10-20 representative ServiceMax UAT scenarios: new Asset, PM base present, Last PM fallback, overdue, future horizon, expired contract, exhausted allowance, multiple coverage, and cancelled/existing Work Order. For each scenario compare source inputs, calculated due date, expected creation decision, and mapped Work Order. Treat differences as rule decisions until the business owner confirms intended parity.

Approval is required from the Service Process Owner, Asset Data Owner, Service Contract/Entitlement Owner, Salesforce Product Owner/Technical Lead, Service Operations, and UAT/Release Owner.
