# Asset Work Order Finder

## Outcome

An onsite field service engineer (FSE) opens the **Asset Work Order Finder** in the Salesforce mobile app, identifies the equipment, reviews the matching Asset, and opens a related Work Order. Results include only Work Orders where `IsClosed = false`.

## Identification paths

- **QR scan:** The device barcode scanner decodes a QR value. The app treats that value as a deterministic identifier and matches it to `Asset.Asset_QR_Code__c`. A QR code is data capture; it does not require computer vision or an AI model.
- **Camera/nameplate:** A photo of the equipment nameplate is sent to the configured recognition provider to extract a serial number and, when available, a model hint. This is computer-vision/OCR-assisted identification. The extracted value is only a search input and must not silently select or update an Asset.
- **Manual fallback:** The FSE can enter the visible serial or QR value when scanning, camera permission, connectivity, or photo recognition is unavailable.

## Match and ambiguity behavior

Navigation happens only after the FSE has an unambiguous Asset and selects an open Work Order. A duplicate exact QR value is treated as a data-quality error and must not expose or choose either Asset. When nameplate recognition returns multiple serial matches, show a choice with Asset name, serial number, and product so the FSE confirms the equipment. If one Asset has multiple open Work Orders, show all of them in a deterministic order and require the FSE to choose. If none are open, retain the confirmed Asset context and clearly state that no open Work Order was found; do not substitute a closed record.

Photo confidence is guidance, not authorization. Low-confidence or incomplete extraction must require confirmation or manual entry. Never use fuzzy model-name similarity alone to navigate to a Work Order.

## Security and privacy

- Apex runs `with sharing` and queries in user mode so record sharing, object access, and field-level security remain authoritative.
- Assign `Asset Work Order Finder User` only to FSEs who need this capability. It grants read-only access to Asset, Product, and Work Order plus only the permissionable fields used by the feature; it does not grant create, edit, delete, View All, or Modify All.
- `Asset.Name`, `Product2.Name`, and `WorkOrder.WorkOrderNumber` are standard non-permissionable fields and therefore are not listed as field permissions. Their visibility follows object/record access.
- Do not log image bodies or retain nameplate photos in Salesforce unless an approved retention, consent, and data-classification design is added. Send images only to an approved recognition provider over an authenticated integration.
- QR payloads are untrusted input: normalize and length-limit them, use bind variables, and never interpret them as a URL or executable action.

## Mobile placement and rollout

Package the finder as a dedicated Lightning App Page exposed through a FlexiPage custom tab. Put that tab first in the **NewMBD Asset Audit** app navigation and enable both `Small` and `Large` form factors. The existing utility item remains a desktop convenience; Salesforce mobile users enter through the navigation tab.

Roll out first to a small FSE pilot with the permission set assigned directly or through a permission-set group. Confirm camera and barcode permissions on managed iOS and Android devices, online and degraded-network behavior, and record-sharing outcomes for representative territories before broad assignment.

## Test focus

- Unique QR; unknown, blank, oversized, and duplicate QR values.
- Unique serial; duplicate serials across products; low-confidence and no-text photos; unsupported/oversized images.
- One, multiple, and zero open Work Orders; closed Work Orders never returned; deterministic ordering.
- User can read an Asset but not its Work Order, and vice versa; field restrictions and sharing are honored without leaking existence through error messages.
- Mobile navigation on `Small`, deep navigation to the selected Work Order, back-navigation, scanner cancellation, denied camera permission, and manual fallback.
- Injection-like QR/text input, high-volume matching, Apex tests using `System.runAs`, and regression tests for the existing Asset Location Audit.
