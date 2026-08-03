/**
 * Bulk-safe parser and resolver for MBD SAP2CASE email-to-case messages.
 *
 * The incoming Case description contains a human-readable Body followed by a
 * set of SAP key/value lines. Parsing is deliberately label-based so colons and
 * line breaks inside the human-readable body are preserved.
 */
public without sharing class NewMBD_SAP2CaseHandler {
    private static final String SAP_MARKER = 'SAP2CASE';
    private static final String MBD_DIVISION = 'MBD';

    private static final Set<String> KNOWN_KEYS = new Set<String>{
        'notification', 'subject', 'body', 'accountid', 'owner', 'equipment',
        'type', 'division', 'contactid', 'material', 'symptom', 'status'
    };

    private static final Set<String> BODY_TERMINATORS = new Set<String>{
        'accountid', 'owner', 'equipment', 'type', 'division', 'contactid',
        'material', 'symptom', 'status'
    };

    public static void beforeInsert(List<Case> newCases) {
        List<WorkItem> workItems = new List<WorkItem>();
        Set<String> accountNumbers = new Set<String>();
        Set<String> equipmentNumbers = new Set<String>();
        Set<String> contactNumbers = new Set<String>();
        Set<String> ownerNames = new Set<String>();

        for (Case caseRecord : newCases) {
            if (!isSap2Case(caseRecord)) {
                continue;
            }

            ParsedEmail parsed = parse(caseRecord.Description);
            if (!MBD_DIVISION.equalsIgnoreCase(parsed.getValue('division'))) {
                continue;
            }

            workItems.add(new WorkItem(caseRecord, parsed));
            addIfPresent(accountNumbers, parsed.getValue('accountid'));
            addIfPresent(equipmentNumbers, parsed.getValue('equipment'));
            addIfPresent(contactNumbers, parsed.getValue('contactid'));
            addIfPresent(ownerNames, parsed.getValue('owner'));
        }

        if (workItems.isEmpty()) {
            return;
        }

        Map<String, Account> accountsByNumber = loadAccounts(accountNumbers);
        Map<String, Asset> assetsByNumber = loadAssets(equipmentNumbers);
        Map<String, List<Contact>> contactsByNumber = loadContacts(contactNumbers);
        Map<String, List<User>> usersByName = loadUsers(ownerNames);

        for (WorkItem item : workItems) {
            applyParsedValues(
                item,
                accountsByNumber,
                assetsByNumber,
                contactsByNumber,
                usersByName
            );
        }
    }

    private static Boolean isSap2Case(Case caseRecord) {
        return caseRecord.Subject != null
            && caseRecord.Description != null
            && caseRecord.Subject.toUpperCase().contains(SAP_MARKER);
    }

    @TestVisible
    private static ParsedEmail parse(String rawDescription) {
        ParsedEmail parsed = new ParsedEmail();
        if (String.isBlank(rawDescription)) {
            return parsed;
        }

        String normalized = rawDescription.replace('\r\n', '\n').replace('\r', '\n');
        List<String> bodyLines = new List<String>();
        Boolean payloadStarted = false;
        Boolean readingBody = false;

        for (String line : normalized.split('\n')) {
            LabelValue pair = parseKnownLabel(line);

            // Forwarded messages can contain an Outlook Subject header before
            // the SAP payload. The Notification line is the payload boundary.
            if (!payloadStarted) {
                if (pair != null && pair.key == 'notification') {
                    payloadStarted = true;
                    parsed.putIfAbsent(pair.key, pair.value);
                }
                continue;
            }

            if (readingBody) {
                if (pair != null && BODY_TERMINATORS.contains(pair.key)) {
                    readingBody = false;
                    parsed.putIfAbsent(pair.key, pair.value);
                } else {
                    bodyLines.add(line);
                    continue;
                }
            } else if (pair != null && pair.key == 'body') {
                readingBody = true;
                if (!String.isBlank(pair.value)) {
                    bodyLines.add(pair.value);
                }
            } else if (pair != null) {
                parsed.putIfAbsent(pair.key, pair.value);
            }
        }

        parsed.body = String.join(bodyLines, '\n').trim();
        return parsed;
    }

    private static LabelValue parseKnownLabel(String line) {
        Integer colonPosition = line == null ? -1 : line.indexOf(':');
        if (colonPosition < 0) {
            return null;
        }

        String key = line.substring(0, colonPosition).trim().toLowerCase();
        if (!KNOWN_KEYS.contains(key)) {
            return null;
        }

        return new LabelValue(key, line.substring(colonPosition + 1).trim());
    }

    private static void applyParsedValues(
        WorkItem item,
        Map<String, Account> accountsByNumber,
        Map<String, Asset> assetsByNumber,
        Map<String, List<Contact>> contactsByNumber,
        Map<String, List<User>> usersByName
    ) {
        Case caseRecord = item.caseRecord;
        ParsedEmail parsed = item.parsed;

        caseRecord.SuppliedName = SAP_MARKER;
        caseRecord.Origin = 'Email';
        caseRecord.Priority = 'Medium';
        caseRecord.Perform_Auto_Entitlement__c = true;
        caseRecord.Division__c = MBD_DIVISION;

        setIfPresent(caseRecord, 'Subject', parsed.getValue('subject'), 255);
        setIfPresent(caseRecord, 'Description', parsed.body, 32000);
        setIfPresent(caseRecord, 'CAPA_ID__c', parsed.getValue('notification'), 25);
        setIfPresent(caseRecord, 'Type', parsed.getValue('type'), 40);
        setIfPresent(caseRecord, 'Symptom__c', parsed.getValue('symptom'), 18);

        Account matchedAccount = accountsByNumber.get(parsed.getValue('accountid'));
        if (matchedAccount != null) {
            caseRecord.AccountId = matchedAccount.Id;
        }

        Asset matchedAsset = assetsByNumber.get(parsed.getValue('equipment'));
        if (matchedAsset != null) {
            caseRecord.AssetId = matchedAsset.Id;
            caseRecord.Component__c = matchedAsset.Id;
            caseRecord.Site__c = matchedAsset.Location__c;
            if (caseRecord.AccountId == null) {
                caseRecord.AccountId = matchedAsset.AccountId;
            }
        }

        Contact matchedContact = chooseContact(
            contactsByNumber.get(parsed.getValue('contactid')),
            caseRecord.AccountId
        );
        if (matchedContact != null) {
            caseRecord.ContactId = matchedContact.Id;
        }

        User matchedOwner = chooseUniqueUser(usersByName.get(parsed.getValue('owner')));
        if (matchedOwner != null) {
            caseRecord.OwnerId = matchedOwner.Id;
            if (matchedOwner.CurrencyIsoCode != null) {
                caseRecord.CurrencyIsoCode = matchedOwner.CurrencyIsoCode;
            }
        }
    }

    private static Map<String, Account> loadAccounts(Set<String> accountNumbers) {
        Map<String, Account> result = new Map<String, Account>();
        if (accountNumbers.isEmpty()) {
            return result;
        }
        for (Account accountRecord : [
            SELECT Id, SVMX_ERP_Account_ID__c
            FROM Account
            WHERE SVMX_ERP_Account_ID__c IN :accountNumbers
        ]) {
            result.put(accountRecord.SVMX_ERP_Account_ID__c, accountRecord);
        }
        return result;
    }

    private static Map<String, Asset> loadAssets(Set<String> equipmentNumbers) {
        Map<String, Asset> result = new Map<String, Asset>();
        if (equipmentNumbers.isEmpty()) {
            return result;
        }
        for (Asset assetRecord : [
            SELECT Id, AccountId, Location__c, ERP_Equipment_ID__c
            FROM Asset
            WHERE ERP_Equipment_ID__c IN :equipmentNumbers
        ]) {
            result.put(assetRecord.ERP_Equipment_ID__c, assetRecord);
        }
        return result;
    }

    private static Map<String, List<Contact>> loadContacts(Set<String> contactNumbers) {
        Map<String, List<Contact>> result = new Map<String, List<Contact>>();
        if (contactNumbers.isEmpty()) {
            return result;
        }
        for (Contact contactRecord : [
            SELECT Id, AccountId, SAPExternalId__c
            FROM Contact
            WHERE SAPExternalId__c IN :contactNumbers
            ORDER BY CreatedDate ASC
        ]) {
            if (!result.containsKey(contactRecord.SAPExternalId__c)) {
                result.put(contactRecord.SAPExternalId__c, new List<Contact>());
            }
            result.get(contactRecord.SAPExternalId__c).add(contactRecord);
        }
        return result;
    }

    private static Map<String, List<User>> loadUsers(Set<String> ownerNames) {
        Map<String, List<User>> result = new Map<String, List<User>>();
        if (ownerNames.isEmpty()) {
            return result;
        }
        for (User userRecord : [
            SELECT Id, Name, CurrencyIsoCode
            FROM User
            WHERE IsActive = true AND Name IN :ownerNames
            ORDER BY CreatedDate ASC
        ]) {
            if (!result.containsKey(userRecord.Name)) {
                result.put(userRecord.Name, new List<User>());
            }
            result.get(userRecord.Name).add(userRecord);
        }
        return result;
    }

    private static Contact chooseContact(List<Contact> candidates, Id accountId) {
        if (candidates == null || candidates.isEmpty()) {
            return null;
        }
        if (candidates.size() == 1) {
            return candidates[0];
        }

        Contact accountMatch;
        for (Contact candidate : candidates) {
            if (accountId != null && candidate.AccountId == accountId) {
                if (accountMatch != null) {
                    return null;
                }
                accountMatch = candidate;
            }
        }
        return accountMatch;
    }

    private static User chooseUniqueUser(List<User> candidates) {
        return candidates != null && candidates.size() == 1 ? candidates[0] : null;
    }

    private static void setIfPresent(SObject record, String fieldName, String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return;
        }
        record.put(fieldName, value.length() > maxLength ? value.substring(0, maxLength) : value);
    }

    private static void addIfPresent(Set<String> values, String value) {
        if (!String.isBlank(value)) {
            values.add(value);
        }
    }

    private class WorkItem {
        Case caseRecord;
        ParsedEmail parsed;

        WorkItem(Case caseRecord, ParsedEmail parsed) {
            this.caseRecord = caseRecord;
            this.parsed = parsed;
        }
    }

    @TestVisible
    private class ParsedEmail {
        @TestVisible Map<String, String> values = new Map<String, String>();
        @TestVisible String body = '';

        String getValue(String key) {
            return values.get(key);
        }

        void putIfAbsent(String key, String value) {
            if (!values.containsKey(key)) {
                values.put(key, value);
            }
        }
    }

    private class LabelValue {
        String key;
        String value;

        LabelValue(String key, String value) {
            this.key = key;
            this.value = value;
        }
    }
}
