# Asset Location QR Audit — Design and Decision Brief

## Decision summary

Build the audit as a reconciliation process, not as an automatic Asset-location update. A service engineer selects the physical location, scans one or more asset QR codes, and finalizes either a spot check or a complete inventory. Salesforce records the audit and every discrepancy; a single summary email per audit should then be sent to the responsible ERP resource.

The confirmed business model uses the standard `Location` object. `Location.Account__c` relates the physical location to its parent Account, `Asset.Location__c` is the Salesforce location of record, and `Location.ERP_Anomaly_Email__c` holds the local ERP recipient. Therefore, comparison must use `Asset.Location__c`—not `Asset.AccountId`.

## Camera identification MVP

The audit also supports a provider-ready nameplate-photo workflow when a QR label cannot be used:

1. The engineer photographs the whole device and is guided to move closer to the serial-number label.
2. The image is resized in the LWC, validated server-side, passed transiently to the recognition-provider interface, and discarded. It is not stored in Salesforce Files, audit records, logs, or ERP email.
3. An extracted serial is advisory and editable. When the scratch-org provider is unconfigured, the UI states this clearly and asks the engineer to enter the visible serial manually.
4. Salesforce performs an exact `Asset.SerialNumber` search under sharing and user-mode field access.
5. The engineer selects and explicitly confirms a candidate Asset. Visual appearance alone never confirms a unique Asset.
6. Finalization submits confirmed Asset IDs in addition to QR codes. The server re-queries those Assets, de-duplicates QR and camera observations, and reconciles Assets that have no QR value.

Production AI extraction remains disabled until an enterprise-approved vision/OCR provider, Named Credential, External Credential, and privacy/data-processing review are supplied.

## Process flow

1. The engineer opens the scanner from a Location record or selects a Location, optionally filtered by its parent Account.
2. The engineer chooses:
   - **Spot Check**: evaluate only scanned codes.
   - **Complete Inventory**: also identify Salesforce assets expected at the location but not scanned.
3. The client trims codes, ignores duplicates, and supports manual entry when the device camera is unavailable.
4. On finalization, the server validates the location, normalizes and de-duplicates the codes again, and queries the assets in one bulk operation.
5. Salesforce creates one `Asset_Location_Audit__c` record containing the location, mode, completion time, counts, and outcome.
6. Salesforce creates an `Asset_Location_Anomaly__c` child for every applicable discrepancy.
7. After the audit and anomalies commit, the notification process sends one digest to the ERP recipient. It records success or failure on the anomaly records and supports an idempotent retry.
8. An authorized owner reviews each anomaly and moves it from Open to Confirmed, Resolved, or Dismissed. Correction of the system of record follows the agreed ERP/Salesforce ownership process.

## Anomaly rules

| Type | Create when | Applicability | Minimum evidence |
|---|---|---|---|
| Unknown Asset | A normalized scanned code does not match a Salesforce Asset QR identifier | Spot Check and Complete Inventory | Audit, scanned location, raw/normalized scanned code |
| Wrong Location | The code matches an Asset, but its canonical Salesforce location differs from the scanned location | Spot Check and Complete Inventory | Audit, Asset, scanned location, Salesforce location, scanned code |
| Missing at Location | An in-scope Asset assigned to the selected location was not included in the finalized scan set | Complete Inventory only | Audit, Asset, selected location, Asset QR code or explanation that no code exists |

Additional rules:

- Compare a canonical normalized code (at minimum trim and consistent case handling). The new Asset field is case-insensitive and unique, so client and server duplicate rules should match it.
- Decide which Asset statuses and product classes are in scope. Retired, transferred, returned, parent/child, loaner, demo, and uninstalled assets should not be treated implicitly.
- Decide how expected Assets without `Asset_QR_Code__c` behave. Recommended: exclude them from “missing” until labels are issued, but surface a separate data-quality report.
- A blank Asset location for a known scan should be treated as Wrong Location, with a blank Salesforce-location snapshot.
- Re-finalizing the same submitted scan must not create a duplicate audit or send a duplicate email. Use a client request key or server-side idempotency key for production hardening.
- Cap codes per request and return a clear message for oversized scans; do not rely only on platform governor limits.

## System-of-record implications

- **Recommended initial behavior:** Salesforce detects and records; it does not relocate an Asset automatically. A physical scan is evidence, not sufficient authority to overwrite installed-base ownership or location.
- Use standard `Location` and `Asset.Location__c` as the canonical comparison key.
- Use `Location.Account__c` to retain customer context and to validate that a selected Location belongs to the expected Account where the UI starts from an Account.
- Keep Account as the parent customer/ERP-routing context, not as a substitute for physical location. Using `Asset.AccountId` would collapse multiple child locations and produce false matches or false anomalies.
- Confirm whether Salesforce or ERP owns installed-asset location. If ERP owns it, the ERP team validates/corrects ERP and the existing integration updates Salesforce. If Salesforce owns it, the anomaly-resolution action may update the Asset under controlled authorization and then publish the change downstream.
- Keep audit/anomaly records as reconciliation evidence. Do not delete them when an Asset is corrected. The current master-detail design appropriately makes anomaly sharing follow the audit.
- Lookup fields preserve record identity but not a human-readable point-in-time location snapshot. For long-term audit evidence, consider adding immutable snapshot fields for location name, ERP ship-to/site ID, Asset serial number, and QR code.

## ERP email behavior

- Send **one digest per completed audit**, listing all anomalies, rather than one email per anomaly.
- Recipient precedence:
  1. `Location.ERP_Anomaly_Email__c` on the selected Location.
  2. `Asset_Audit_Setting__mdt.Default.Default_ERP_Recipient__c`.
  3. If neither is configured, persist a notification error and surface the audit as requiring support attention; do not mark it notified.
- Send after database commit, preferably with Queueable Apex or a platform-event subscriber. This prevents a mail failure from losing the audit and makes retry behavior explicit.
- Set `ERP_Notified__c` and `ERP_Notified_At__c` only after a successful send. Preserve the latest error and retry count/time; do not resend records already marked successful unless an authorized user explicitly requests it.
- Use an approved org-wide sender, a stable subject containing audit number and location/ERP ID, and a concise body with anomaly number, type, asset identifier/serial, Salesforce location, and scanned location.
- Confirm whether an email is merely a human work instruction or is parsed by ERP automation. If machine processing is required, a versioned API/middleware message is safer than free-form email; at minimum use a stable CSV attachment or strictly versioned template.
- Validate Salesforce deliverability, daily email limits, recipient allow-listing, and non-production suppression/rerouting before enabling the process.

## Security and controls

- Run the Apex entry point `with sharing` and explicitly enforce CRUD/FLS for Location, its parent Account, Asset, audit, anomaly, and all referenced fields. Do not depend on Lightning field visibility to secure server-side access.
- Give engineers only the permissions needed to read eligible locations/assets and create/read audits. Restrict edits to anomaly disposition and ERP notification-control fields to support/integration roles.
- Because anomalies inherit audit sharing, set the audit object's organization-wide default to the intended confidentiality level. The current `ReadWrite` metadata exposes all audits broadly; recommended production posture is Private unless business reporting requires broader access.
- Treat QR values as untrusted input. Validate length and allowed format, escape all email/HTML output, and do not encode secrets or personal data in QR labels. An opaque asset identifier is preferable to a URL carrying credentials.
- Confirm mobile camera support, HTTPS, and Salesforce mobile/browser permissions. Manual entry is a useful fallback but should be logged equivalently.
- Preserve CreatedBy, timestamps, status history, and notification outcome. Consider a validation rule that prevents engineers from changing completed audit counts or anomaly evidence.
- Avoid exposing customer location and installed-base data in email beyond what the ERP recipient requires. Confirm retention, works-council, and regional privacy requirements.

## Rollout and data preparation

1. Confirm the location entity/field, ERP ownership, eligible Asset statuses, and notification contract.
2. Profile existing Assets for QR-code completeness, duplicates after trim/case normalization, blank/invalid locations, and inactive records.
3. Generate/backfill stable QR identifiers and physically label assets. Load only after duplicate and format validation; retain a mapping to serial number/ERP asset ID.
4. Populate and validate location-specific ERP recipients; configure a non-production fallback recipient before activating email.
5. Deploy metadata and permissions, add the component to the relevant mobile Location page, and provide audit/anomaly layouts, list views, reports, and operational dashboards.
6. Pilot with a small set of locations whose installed inventory has been independently verified. Run notifications in “capture only” or sandbox-rerouted mode first.
7. Establish anomaly ownership, response SLA, retry/support queue, and data-correction procedure before broad enablement.
8. Roll out by region/business unit and monitor unknown-code rate, wrong-location rate, missing rate, email failures, and time to resolution.

Existing assets do not require historical audit/anomaly migration. They do require QR and canonical-location data preparation. If historical discrepancies exist, load them only when the source, detection date, and resolution state can be preserved.

## Test focus

- Exact match, unknown code, wrong location, blank Salesforce location, and mixed scans.
- Spot Check never creates Missing anomalies; Complete Inventory creates them only for the agreed eligible population.
- Empty input, invalid Location ID, Location/Account mismatch, inaccessible location, duplicate input, whitespace, case variants, 255-character boundary, unsupported characters, and QR codes absent from expected assets.
- Retired/transferred/parent-child/demo assets according to the approved scope rules.
- Multiple scans of the same code and repeated/replayed finalization requests.
- Large locations and maximum supported batch size: constant-number SOQL/DML behavior, no per-code queries or per-anomaly emails.
- Audit/anomaly transaction consistency, counts, master-detail cascade behavior, field history, and lookup deletion constraints.
- Recipient precedence, invalid/missing email, send failure, retry, no duplicate send, org-wide sender, deliverability, and daily-limit behavior.
- Engineer versus support/integration permission tests, record sharing, CRUD/FLS failures, and input/email-injection attempts.
- Salesforce mobile camera path, desktop/manual fallback, Location record-page context, app-page location selection, Account filtering, accessibility, and offline/poor-network recovery.

## Metadata validation and likely deploy issues

Local XML parsing confirms the new object, field, and custom-metadata files are well-formed XML.

Two master-detail declarations were corrected during review:

- `Asset_Location_Anomaly__c` now uses `ControlledByParent` for internal and external sharing because `Audit__c` is master-detail.
- `Asset_Location_Anomaly__c.Audit__c` now declares `relationshipOrder` 0.

Other deployment and enablement considerations:

- The custom metadata default recipient is intentionally null. Deployment can succeed, but notification cannot fall back until the record is configured.
- Deploy the custom metadata type/field and its `Asset_Audit_Setting.Default` record together; deploying only the record first will fail.
- The standalone `Asset/fields/Asset_QR_Code__c` source is a supported decomposition pattern; an `Asset.object-meta.xml` file is not required merely to add the field.
- `Asset_Location_Audit__c.Location__c`, `Asset_Location_Anomaly__c.Scanned_Location__c`, and `Asset_Location_Anomaly__c.Salesforce_Location__c` must reference standard `Location`; the Lightning picker and record-page configuration must use the same object.
- Unique external-ID creation can fail or become unusable during backfill if existing normalized QR values are duplicated. Preflight the source data before loading.
- `Completed_At__c` is required and audit Status defaults to Completed. This is compatible with create-on-finalize, but not with saving an in-progress audit. Add a Draft lifecycle before introducing resumable/offline scans.
- No tabs, layouts, report types, validation rules, or retention automation are defined in the reviewed object metadata. They are not required for structural deployment, but the operational experience and controls remain incomplete without them.
- Metadata parsing is not an org validation. A target-org dry-run is still required to detect edition/license, API-version, existing-name, relationship, email, and permission dependencies.

## Decisions required before production

| Decision | Recommended default |
|---|---|
| Physical location entity and Asset field | Standard `Location`; compare with `Asset.Location__c`; parent context is `Location.Account__c` |
| System of record for relocation | ERP if existing installed-base integration is ERP-led; otherwise name Salesforce owner explicitly |
| Automatic Asset update | No; resolve through a reviewed anomaly workflow |
| Complete-inventory eligible population | Active, installed, independently auditable assets only |
| Expected Asset without QR | Exclude from missing anomaly; report as data-quality backlog |
| Email granularity | One digest per audit |
| Missing recipient/send failure | Persist failure, alert support, allow idempotent retry |
| Audit visibility | Private by default, expanded through roles/permission sets as required |
| Machine ERP integration | Prefer API/middleware; use versioned structured email only if email is mandatory |
| Idempotency | Required before production to prevent duplicate audits and emails |

## Confidence and assumptions

Confidence is high in the reconciliation pattern, metadata relationship correction, and confirmed API-level location mapping. The brief assumes the QR value is a stable asset identifier, an email is explicitly required for the first release, and the scan is finalized while online.
