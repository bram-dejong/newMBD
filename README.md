# newMBD
## Opportunity Metadata Notes

The following Opportunity formula fields were intentionally removed from local metadata because the current scratch org was created without MultiCurrency, so `CurrencyIsoCode` is unavailable:

- `Amount_USD_Active_Currency__c`
- `Renewal_Calculator_USD_Active_Currency__c`

Add them back from FL1 after recreating the scratch org with the `MultiCurrency` feature enabled.

## New Opportunity Flow Notes

`New_Opportunity` was adjusted so it can deploy to the current non-MultiCurrency scratch org:

- Removed the Opportunity currency picker and `CurrencyIsoCode` assignments/filters, including `PricebookEntry.CurrencyIsoCode`.
- Removed Opportunity `RecordTypeId` assignment/lookup logic because this scratch org does not have the FL1 Opportunity record type setup.
- Neutralized missing custom-permission formula checks for the US/EU access permissions.
- Added supporting metadata used by the flow, including `User_Region_Settings__c`, `Account.MBD_Status__c`, `Account.MBD_Account_Type__c`, `OpportunityLineItem.Revenue_Months__c`, and `ServiceContract.Opportunity__c`.

Revisit these flow changes after recreating the scratch org with the needed FL1 features and record type/custom permission setup.
