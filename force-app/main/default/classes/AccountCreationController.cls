public with sharing class AccountCreationController {
    private static final Integer MAX_RESULTS = 10;
    private static final Decimal MATCH_THRESHOLD = 0.74;

    public class SearchResponse {
        @AuraEnabled public List<MatchResult> dbMatches { get; set; }
        @AuraEnabled public List<AccountMatch> accountMatches { get; set; }
        @AuraEnabled public Boolean canCreateLead { get; set; }
        @AuraEnabled public String searchedName { get; set; }
    }

    public class MatchResult {
        @AuraEnabled public Id dbDataId { get; set; }
        @AuraEnabled public String dbDataName { get; set; }
        @AuraEnabled public String companyName { get; set; }
        @AuraEnabled public String dunsNumber { get; set; }
        @AuraEnabled public String street { get; set; }
        @AuraEnabled public String city { get; set; }
        @AuraEnabled public String state { get; set; }
        @AuraEnabled public String postalCode { get; set; }
        @AuraEnabled public String country { get; set; }
        @AuraEnabled public Decimal score { get; set; }
    }

    public class AccountMatch {
        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public Decimal score { get; set; }
    }

    public class LeadRequest {
        @AuraEnabled public Id dbDataId { get; set; }
        @AuraEnabled public String company { get; set; }
        @AuraEnabled public String firstName { get; set; }
        @AuraEnabled public String lastName { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String website { get; set; }
        @AuraEnabled public String street { get; set; }
        @AuraEnabled public String city { get; set; }
        @AuraEnabled public String state { get; set; }
        @AuraEnabled public String postalCode { get; set; }
        @AuraEnabled public String country { get; set; }
    }

    public class LeadCreateResponse {
        @AuraEnabled public Id leadId { get; set; }
        @AuraEnabled public String leadName { get; set; }
        @AuraEnabled public String company { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static SearchResponse search(String accountName) {
        validateName(accountName);
        return searchInternal(accountName.trim());
    }

    @AuraEnabled
    public static LeadCreateResponse createLead(LeadRequest request) {
        if (request == null) {
            throw handled('Enter Lead details before saving.');
        }
        validateName(request.company);
        if (String.isBlank(request.lastName)) {
            throw handled('Enter the Lead last name.');
        }

        SearchResponse duplicateCheck = searchInternal(request.company.trim());
        if (!duplicateCheck.accountMatches.isEmpty()) {
            throw handled('A matching Salesforce Account already exists. Open that Account instead of creating a Lead.');
        }

        if (request.dbDataId == null) {
            if (!duplicateCheck.dbMatches.isEmpty()) {
                throw handled('A matching D&B record exists. Select it before creating the Lead.');
            }
        } else {
            if (request.dbDataId.getSObjectType() != DB_Data__c.SObjectType) {
                throw handled('Select a valid D&B record.');
            }
            List<DB_Data__c> selectedRecords = [
                SELECT Id, Duns_Name__c
                FROM DB_Data__c
                WHERE Id = :request.dbDataId
                WITH USER_MODE
            ];
            if (selectedRecords.isEmpty()) {
                throw handled('The selected D&B record is unavailable. Search again.');
            }
        }

        Lead newLead = new Lead(
            Company = clean(request.company),
            FirstName = clean(request.firstName),
            LastName = clean(request.lastName),
            Email = clean(request.email),
            Phone = clean(request.phone),
            Website = clean(request.website),
            Street = clean(request.street),
            City = clean(request.city),
            State = clean(request.state),
            PostalCode = clean(request.postalCode),
            Country = clean(request.country),
            Status = defaultLeadStatus(),
            D_B_Record__c = request.dbDataId
        );
        try {
            insert as user newLead;
        } catch (DmlException error) {
            throw handled(error.getDmlMessage(0));
        }

        LeadCreateResponse result = new LeadCreateResponse();
        result.leadId = newLead.Id;
        result.leadName = String.isBlank(request.firstName)
            ? request.lastName.trim()
            : request.firstName.trim() + ' ' + request.lastName.trim();
        result.company = newLead.Company;
        return result;
    }

    private static SearchResponse searchInternal(String accountName) {
        String normalizedSearch = normalizeCompanyName(accountName);
        Map<Id, DB_Data__c> dbCandidates = new Map<Id, DB_Data__c>();
        Map<Id, Account> accountCandidates = new Map<Id, Account>();

        String containsPattern = '%' + escapeLike(accountName.trim()) + '%';
        String prefixPattern = escapeLike(accountName.trim().left(2)) + '%';
        String suffixPattern = '%' + escapeLike(accountName.trim().substring(1)) + '%';
        Map<String, Object> patternBinds = new Map<String, Object>{
            'containsPattern' => containsPattern,
            'prefixPattern' => prefixPattern,
            'suffixPattern' => suffixPattern
        };
        List<SObject> dbRows = Database.queryWithBinds(
            'SELECT Id, Name, Duns_Name__c, Duns_Number__c, Geocoded_Address__c, ' +
            'Geocoded_City__c, Geocoded_State__c, Geocoded_Zip__c, Geocoded_Country__c ' +
            'FROM DB_Data__c WHERE Duns_Name__c LIKE :containsPattern ' +
            'OR Duns_Name__c LIKE :prefixPattern OR Duns_Name__c LIKE :suffixPattern LIMIT 200',
            patternBinds,
            AccessLevel.USER_MODE
        );
        for (SObject row : dbRows) {
            DB_Data__c item = (DB_Data__c)row;
            dbCandidates.put(item.Id, item);
        }

        List<SObject> accountRows = Database.queryWithBinds(
            'SELECT Id, Name FROM Account WHERE Name LIKE :containsPattern ' +
            'OR Name LIKE :prefixPattern OR Name LIKE :suffixPattern LIMIT 200',
            patternBinds,
            AccessLevel.USER_MODE
        );
        for (SObject row : accountRows) {
            Account item = (Account)row;
            accountCandidates.put(item.Id, item);
        }

        SearchResponse response = new SearchResponse();
        response.searchedName = accountName;
        response.dbMatches = new List<MatchResult>();
        response.accountMatches = new List<AccountMatch>();

        for (DB_Data__c item : dbCandidates.values()) {
            Decimal score = matchScore(normalizedSearch, normalizeCompanyName(item.Duns_Name__c));
            if (score >= MATCH_THRESHOLD) response.dbMatches.add(mapDbMatch(item, score));
        }
        for (Account item : accountCandidates.values()) {
            Decimal score = matchScore(normalizedSearch, normalizeCompanyName(item.Name));
            if (score >= MATCH_THRESHOLD) response.accountMatches.add(mapAccountMatch(item, score));
        }
        sortAndLimitDbMatches(response.dbMatches);
        sortAndLimitAccountMatches(response.accountMatches);
        response.canCreateLead = response.dbMatches.isEmpty() && response.accountMatches.isEmpty();
        return response;
    }

    private static MatchResult mapDbMatch(DB_Data__c item, Decimal score) {
        MatchResult result = new MatchResult();
        result.dbDataId = item.Id;
        result.dbDataName = item.Name;
        result.companyName = item.Duns_Name__c;
        result.dunsNumber = item.Duns_Number__c;
        result.street = item.Geocoded_Address__c;
        result.city = item.Geocoded_City__c;
        result.state = item.Geocoded_State__c;
        result.postalCode = item.Geocoded_Zip__c;
        result.country = item.Geocoded_Country__c;
        result.score = (score * 100).setScale(0);
        return result;
    }

    private static AccountMatch mapAccountMatch(Account item, Decimal score) {
        AccountMatch result = new AccountMatch();
        result.accountId = item.Id;
        result.accountName = item.Name;
        result.score = (score * 100).setScale(0);
        return result;
    }

    private static void sortAndLimitDbMatches(List<MatchResult> results) {
        for (Integer i = 0; i < results.size(); i++) {
            Integer best = i;
            for (Integer j = i + 1; j < results.size(); j++) {
                if (results[j].score > results[best].score) best = j;
            }
            if (best != i) {
                MatchResult swap = results[i]; results[i] = results[best]; results[best] = swap;
            }
        }
        while (results.size() > MAX_RESULTS) results.remove(results.size() - 1);
    }

    private static void sortAndLimitAccountMatches(List<AccountMatch> results) {
        for (Integer i = 0; i < results.size(); i++) {
            Integer best = i;
            for (Integer j = i + 1; j < results.size(); j++) {
                if (results[j].score > results[best].score) best = j;
            }
            if (best != i) {
                AccountMatch swap = results[i]; results[i] = results[best]; results[best] = swap;
            }
        }
        while (results.size() > MAX_RESULTS) results.remove(results.size() - 1);
    }

    @TestVisible
    static Decimal matchScore(String searchValue, String candidateValue) {
        if (String.isBlank(searchValue) || String.isBlank(candidateValue)) return 0;
        if (searchValue == candidateValue) return 1;

        Decimal coverage = Decimal.valueOf(searchValue.length()) / candidateValue.length();
        if (candidateValue.startsWith(searchValue)) {
            return 0.90 + (0.10 * coverage);
        }
        if (candidateValue.contains(searchValue)) {
            return 0.80 + (0.10 * coverage);
        }
        return similarity(searchValue, candidateValue);
    }

    @TestVisible
    static Decimal similarity(String first, String second) {
        if (String.isBlank(first) || String.isBlank(second)) return 0;
        if (first == second) return 1;
        Integer longest = Math.max(first.length(), second.length());
        return Decimal.valueOf(longest - levenshtein(first, second)) / longest;
    }

    private static Integer levenshtein(String first, String second) {
        List<Integer> previous = new List<Integer>();
        for (Integer j = 0; j <= second.length(); j++) previous.add(j);
        for (Integer i = 1; i <= first.length(); i++) {
            List<Integer> current = new List<Integer>{ i };
            for (Integer j = 1; j <= second.length(); j++) {
                Integer cost = first.substring(i - 1, i) == second.substring(j - 1, j) ? 0 : 1;
                current.add(Math.min(Math.min(current[j - 1] + 1, previous[j] + 1), previous[j - 1] + cost));
            }
            previous = current;
        }
        return previous[second.length()];
    }

    @TestVisible
    static String normalizeCompanyName(String value) {
        if (String.isBlank(value)) return '';
        String normalized = value.toLowerCase().replaceAll('[^a-z0-9 ]', ' ')
            .replaceAll('\\s+', ' ').trim();
        normalized = normalized.replaceAll('(?: corporation| incorporated| company| limited| corp| inc| llc| ltd| gmbh| s a)$', '');
        return normalized.replaceAll(' ', '');
    }

    private static String escapeLike(String value) {
        return value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }

    private static String clean(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static void validateName(String value) {
        if (String.isBlank(value) || value.trim().length() < 3) {
            throw handled('Enter at least three characters of the Account name.');
        }
        if (value.trim().length() > 255) throw handled('Account Name cannot exceed 255 characters.');
    }

    private static String defaultLeadStatus() {
        for (Schema.PicklistEntry entry : Lead.Status.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.isDefaultValue()) return entry.getValue();
        }
        for (Schema.PicklistEntry entry : Lead.Status.getDescribe().getPicklistValues()) {
            if (entry.isActive()) return entry.getValue();
        }
        throw handled('No active Lead status is configured. Contact your Salesforce administrator.');
    }

    private static AuraHandledException handled(String message) {
        return new AuraHandledException(message);
    }
}
