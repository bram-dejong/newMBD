@IsTest
private class NewMBD_SAP2CaseHandlerTest {
    private static final String SAMPLE_DESCRIPTION =
        'From: Brown, Robert <robert.brown@thermofisher.com>\n' +
        'Sent: Friday, July 24, 2026 3:39:29 PM\n' +
        'To: Noreply.SDG.Service\n' +
        'Subject: SAP2CASE Send to SVMX QM-num: 000004041703\n' +
        'Notification: 000004041703\n' +
        'Subject: ST Neph Creeping/Flashing LEDs (FSE)\n' +
        'Body: What exact issue is the customer experiencing?\n' +
        'Nephelometer, creeping low/flashing lights following service.\n' +
        'Summary of issues: 0\n' +
        'Instrument is down.\n' +
        'SAP shows an active bronze service contract.|\n' +
        'AccountId : 0000456495-CA01\n' +
        'Owner: ' + UserInfo.getName() + '\n' +
        'Equipment: 000000000010082614\n' +
        'Type: QC/Calibration\n' +
        'Division : MBD\n' +
        'ContactId: 549209\n' +
        'Material: NEPHELOMETER(YV3011)\n' +
        'Symptom: To be determined\n' +
        'Status: OSNO NOTI ATCO';

    @IsTest
    static void mapsSampleEmailToNewMbdFields() {
        Account customer = new Account(
            Name = 'PHAC',
            SVMX_ERP_Account_ID__c = '0000456495-CA01'
        );
        insert customer;

        SObject serviceLocation = Schema.getGlobalDescribe().get('Location').newSObject();
        serviceLocation.put('Name', 'PHAC Site');
        serviceLocation.put('Account__c', customer.Id);
        insert serviceLocation;
        Id serviceLocationId = (Id) serviceLocation.get('Id');

        Asset equipment = new Asset(
            Name = 'Nephelometer',
            AccountId = customer.Id,
            Location__c = serviceLocationId,
            ERP_Equipment_ID__c = '000000000010082614'
        );
        insert equipment;

        Contact sapContact = new Contact(
            LastName = 'Grewal',
            AccountId = customer.Id,
            SAPExternalId__c = '549209'
        );
        insert sapContact;

        Case inboundCase = new Case(
            Subject = 'SAP2CASE Send to SVMX QM-num: 000004041703',
            Description = SAMPLE_DESCRIPTION,
            Status = 'New'
        );

        Test.startTest();
        insert inboundCase;
        Test.stopTest();

        Case actual = [
            SELECT Subject, Description, AccountId, ContactId, AssetId, Component__c,
                Site__c, CAPA_ID__c, Division__c, Symptom__c, Type, SuppliedName,
                Origin, Priority, Perform_Auto_Entitlement__c
            FROM Case
            WHERE Id = :inboundCase.Id
        ];

        System.assertEquals('ST Neph Creeping/Flashing LEDs (FSE)', actual.Subject);
        System.assert(actual.Description.contains('Summary of issues: 0'));
        System.assert(!actual.Description.contains('AccountId'));
        System.assertEquals(customer.Id, actual.AccountId);
        System.assertEquals(sapContact.Id, actual.ContactId);
        System.assertEquals(equipment.Id, actual.AssetId);
        System.assertEquals(equipment.Id, actual.Component__c);
        System.assertEquals(serviceLocationId, actual.Site__c);
        System.assertEquals('000004041703', actual.CAPA_ID__c);
        System.assertEquals('MBD', actual.Division__c);
        System.assertEquals('To be determined', actual.Symptom__c);
        System.assertEquals('QC/Calibration', actual.Type);
        System.assertEquals('SAP2CASE', actual.SuppliedName);
        System.assertEquals('Email', actual.Origin);
        System.assertEquals('Medium', actual.Priority);
        System.assertEquals(true, actual.Perform_Auto_Entitlement__c);
    }

    @IsTest
    static void ignoresNonMbdAndNonSapCases() {
        Case nonMbd = new Case(
            Subject = 'SAP2CASE other division',
            Description = SAMPLE_DESCRIPTION.replace('Division : MBD', 'Division : CDD')
        );
        Case normalEmail = new Case(
            Subject = 'Normal customer email',
            Description = SAMPLE_DESCRIPTION
        );

        NewMBD_SAP2CaseHandler.beforeInsert(new List<Case>{ nonMbd, normalEmail });

        System.assertEquals('SAP2CASE other division', nonMbd.Subject);
        System.assertEquals(null, nonMbd.SuppliedName);
        System.assertEquals('Normal customer email', normalEmail.Subject);
        System.assertEquals(null, normalEmail.SuppliedName);
    }

    @IsTest
    static void handlesBulkMessagesWithoutQueriesInLoops() {
        List<Case> inboundCases = new List<Case>();
        for (Integer index = 0; index < 200; index++) {
            inboundCases.add(new Case(
                Subject = 'SAP2CASE bulk ' + index,
                Description = SAMPLE_DESCRIPTION
            ));
        }

        Test.startTest();
        NewMBD_SAP2CaseHandler.beforeInsert(inboundCases);
        Integer queryCount = Limits.getQueries();
        Test.stopTest();

        System.assert(queryCount <= 4, 'The handler should use at most four bulk queries.');
        for (Case caseRecord : inboundCases) {
            System.assertEquals('MBD', caseRecord.Division__c);
            System.assertEquals('ST Neph Creeping/Flashing LEDs (FSE)', caseRecord.Subject);
            System.assert(caseRecord.Description.contains('Summary of issues: 0'));
        }
    }
}
