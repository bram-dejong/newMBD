@IsTest
private class AccountCreationControllerTest {
    @TestSetup
    static void grantGuidedCreationAccess() {
        PermissionSet permissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Guided_Account_Creation'
            LIMIT 1
        ];
        List<PermissionSetAssignment> existingAssignments = [
            SELECT Id
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
                AND PermissionSetId = :permissionSet.Id
            LIMIT 1
        ];
        if (existingAssignments.isEmpty()) {
            insert new PermissionSetAssignment(
                AssigneeId = UserInfo.getUserId(),
                PermissionSetId = permissionSet.Id
            );
        }
    }

    @IsTest
    static void existingAccountMatchBlocksLeadCreation() {
        Account existingAccount = new Account(Name = 'Acme Medical Research Center');
        insert existingAccount;

        Test.startTest();
        AccountCreationController.SearchResponse result =
            AccountCreationController.search('Acme Medcal Research Center');
        Test.stopTest();

        System.assertEquals(false, result.canCreateLead);
        System.assertEquals(1, result.accountMatches.size());
        System.assertEquals(existingAccount.Id, result.accountMatches[0].accountId);

        AccountCreationController.LeadRequest request = requestFor('Acme Medical Research Center');
        try {
            AccountCreationController.createLead(request);
            System.assert(false, 'A matching Account must block Lead creation.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected);
        }
    }

    @IsTest
    static void partialAccountNameReturnsPrefixMatch() {
        Account existingAccount = new Account(Name = 'Test Account');
        insert existingAccount;

        Test.startTest();
        AccountCreationController.SearchResponse result =
            AccountCreationController.search('Tes');
        Test.stopTest();

        System.assertEquals(false, result.canCreateLead);
        System.assertEquals(1, result.accountMatches.size());
        System.assertEquals(existingAccount.Id, result.accountMatches[0].accountId);
        System.assert(result.accountMatches[0].score >= 90);
    }

    @IsTest
    static void partialDbNameReturnsContainedMatch() {
        DB_Data__c dbRecord = new DB_Data__c(Duns_Name__c = 'Global Test Laboratories');
        insert dbRecord;

        Test.startTest();
        AccountCreationController.SearchResponse result =
            AccountCreationController.search('Test');
        Test.stopTest();

        System.assertEquals(false, result.canCreateLead);
        System.assertEquals(1, result.dbMatches.size());
        System.assertEquals(dbRecord.Id, result.dbMatches[0].dbDataId);
        System.assert(result.dbMatches[0].score >= 80);
    }

    @IsTest
    static void fuzzyDbSearchRequiresSelectionBeforeLeadCreation() {
        DB_Data__c dbRecord = new DB_Data__c(
            Duns_Name__c = 'Thermo Fisher Scientific Inc',
            Duns_Number__c = '123456789',
            Geocoded_Address__c = '1 Science Way',
            Geocoded_City__c = 'Waltham',
            Geocoded_State__c = 'MA',
            Geocoded_Zip__c = '02451',
            Geocoded_Country__c = 'United States'
        );
        insert dbRecord;

        AccountCreationController.SearchResponse result =
            AccountCreationController.search('Thermo Fiser Scientific');
        System.assertEquals(false, result.canCreateLead);
        System.assertEquals(1, result.dbMatches.size());
        System.assertEquals(dbRecord.Id, result.dbMatches[0].dbDataId);

        try {
            AccountCreationController.createLead(requestFor('Thermo Fisher Scientific'));
            System.assert(false, 'A matching D&B record must be selected.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected);
        }
    }

    @IsTest
    static void selectedDbDataPrepopulatesAndLinksLead() {
        DB_Data__c dbRecord = new DB_Data__c(
            Duns_Name__c = 'Northwind Research Europe',
            Geocoded_Address__c = '10 Rue de Science',
            Geocoded_City__c = 'Paris',
            Geocoded_State__c = 'Ile-de-France',
            Geocoded_Zip__c = '75001',
            Geocoded_Country__c = 'France'
        );
        insert dbRecord;

        AccountCreationController.LeadRequest request = requestFor(dbRecord.Duns_Name__c);
        request.dbDataId = dbRecord.Id;
        request.firstName = 'Marie';
        request.lastName = 'Curie';
        request.email = 'marie.curie@example.test';
        request.street = dbRecord.Geocoded_Address__c;
        request.city = dbRecord.Geocoded_City__c;
        request.state = dbRecord.Geocoded_State__c;
        request.postalCode = dbRecord.Geocoded_Zip__c;
        request.country = dbRecord.Geocoded_Country__c;

        Test.startTest();
        AccountCreationController.LeadCreateResponse created =
            AccountCreationController.createLead(request);
        Test.stopTest();

        Lead saved = [
            SELECT Company, FirstName, LastName, Email, Street, City, State,
                PostalCode, Country, D_B_Record__c
            FROM Lead
            WHERE Id = :created.leadId
        ];
        System.assertEquals(dbRecord.Duns_Name__c, saved.Company);
        System.assertEquals(dbRecord.Id, saved.D_B_Record__c);
        System.assertEquals('Marie', saved.FirstName);
        System.assertEquals('10 Rue de Science', saved.Street);
    }

    @IsTest
    static void noAccountOrDbMatchAllowsLeadCreation() {
        AccountCreationController.LeadRequest request = requestFor('Unique Alpine Research Group');
        request.firstName = 'Ada';
        request.lastName = 'Lovelace';
        request.phone = '+33 1 23 45 67 89';
        request.website = 'https://example.test';

        Test.startTest();
        AccountCreationController.LeadCreateResponse created =
            AccountCreationController.createLead(request);
        Test.stopTest();

        Lead saved = [SELECT Company, FirstName, LastName, D_B_Record__c FROM Lead WHERE Id = :created.leadId];
        System.assertEquals(request.company, saved.Company);
        System.assertEquals(null, saved.D_B_Record__c);
    }

    @IsTest
    static void oneDbRecordCanSupportMultipleLeads() {
        DB_Data__c dbRecord = new DB_Data__c(Duns_Name__c = 'Global Parent Organization');
        insert dbRecord;

        AccountCreationController.LeadRequest first = requestFor(dbRecord.Duns_Name__c);
        first.dbDataId = dbRecord.Id;
        first.lastName = 'Prospect One';
        AccountCreationController.LeadRequest second = requestFor(dbRecord.Duns_Name__c);
        second.dbDataId = dbRecord.Id;
        second.lastName = 'Prospect Two';

        Test.startTest();
        AccountCreationController.createLead(first);
        AccountCreationController.createLead(second);
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM Lead WHERE D_B_Record__c = :dbRecord.Id]);
    }

    @IsTest
    static void normalizedAccountNameStillPreventsExactAccountDuplicates() {
        insert new Account(Name = 'ACME, Inc.');
        Database.SaveResult result = Database.insert(new Account(Name = 'acme inc'), false);
        System.assertEquals(false, result.isSuccess());
        System.assertEquals(StatusCode.DUPLICATE_VALUE, result.getErrors()[0].getStatusCode());
    }

    @IsTest
    static void normalizationAndSimilarityAreDeterministic() {
        System.assertEquals('acme', AccountCreationController.normalizeCompanyName(' Acme, Inc. '));
        System.assertEquals('acmeinc', AccountDuplicateGuard.normalize(' ACME, Inc. '));
        System.assert(AccountCreationController.similarity('thermofisher', 'thermofiser') > 0.9);
        System.assert(AccountCreationController.matchScore('tes', 'testaccount') > 0.9);
        System.assert(AccountCreationController.matchScore('test', 'globaltestlaboratories') > 0.8);
    }

    private static AccountCreationController.LeadRequest requestFor(String company) {
        AccountCreationController.LeadRequest request = new AccountCreationController.LeadRequest();
        request.company = company;
        request.lastName = 'Unknown Contact';
        return request;
    }
}
