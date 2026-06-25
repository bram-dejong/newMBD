# newMBD
## Opportunity Metadata Notes

The following Opportunity formula fields require MultiCurrency and are now kept in local metadata because the scratch org has MultiCurrency enabled:

- `Amount_USD_Active_Currency__c`
- `Renewal_Calculator_USD_Active_Currency__c`

They were restored from FL1 after MultiCurrency was enabled in the scratch org.

## New Opportunity Flow Notes

`New_Opportunity` was adjusted so it can deploy to the scratch org while preserving the restored MultiCurrency behavior:

- Restored the Opportunity currency picker and `CurrencyIsoCode` assignments/filters, including `PricebookEntry.CurrencyIsoCode`.
- Removed Opportunity `RecordTypeId` assignment/lookup logic because this scratch org does not have the FL1 Opportunity record type setup.
- Neutralized missing custom-permission formula checks for the US/EU access permissions.
- Added supporting metadata used by the flow, including `User_Region_Settings__c`, `Account.MBD_Status__c`, `Account.MBD_Account_Type__c`, `OpportunityLineItem.Revenue_Months__c`, and `ServiceContract.Opportunity__c`.

Revisit the remaining flow changes after recreating the scratch org with the needed FL1 record type/custom permission setup.
