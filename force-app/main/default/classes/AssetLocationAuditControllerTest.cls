@IsTest
private class AssetLocationAuditControllerTest {
    private static final String LOCATION_ONE = 'Paris Customer Site';
    private static final String LOCATION_TWO = 'Lyon Customer Site';

    @TestSetup
    static void setupData() {
        PermissionSet auditPermissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Asset_Location_Audit_User'
            LIMIT 1
        ];
        if ([
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
                AND PermissionSetId = :auditPermissionSet.Id
        ] == 0) {
            insert new PermissionSetAssignment(
                AssigneeId = UserInfo.getUserId(),
                PermissionSetId = auditPermissionSet.Id
            );
        }

        System.runAs(new User(Id = UserInfo.getUserId())) {
            createBusinessData();
        }
    }

    private static void createBusinessData() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Paris Account'),
            new Account(Name = 'Lyon Account')
        };
        insert accounts;

        List<Schema.Location> locations = new List<Schema.Location>{
            new Schema.Location(
                Name = LOCATION_ONE,
                LocationType = 'Site',
                Account__c = accounts[0].Id,
                ERP_Anomaly_Email__c = 'paris-erp@example.com',
                Geo_Coordinates__Latitude__s = 48.856600,
                Geo_Coordinates__Longitude__s = 2.352200
            ),
            new Schema.Location(
                Name = LOCATION_TWO,
                LocationType = 'Site',
                Account__c = accounts[1].Id,
                Geo_Coordinates__Latitude__s = 45.764000,
                Geo_Coordinates__Longitude__s = 4.835700
            )
        };
        insert locations;

        insert new List<Asset>{
            new Asset(
                Name = 'Paris Asset One',
                AccountId = accounts[0].Id,
                Location__c = locations[0].Id,
                Asset_QR_Code__c = 'PAR-001'
            ),
            new Asset(
                Name = 'Paris Asset Two',
                AccountId = accounts[0].Id,
                Location__c = locations[0].Id,
                Asset_QR_Code__c = 'PAR-002'
            ),
            new Asset(
                Name = 'Paris Asset Without QR',
                AccountId = accounts[0].Id,
                Location__c = locations[0].Id
            ),
            new Asset(
                Name = 'Lyon Asset',
                AccountId = accounts[1].Id,
                Location__c = locations[1].Id,
                Asset_QR_Code__c = 'LYO-001'
            )
        };
    }

    @IsTest
    static void spotCheckPersistsUnknownAndWrongLocationOnly() {
        Schema.Location paris = locationByName(LOCATION_ONE);

        Test.startTest();
        AssetLocationAuditController.AuditResult result =
            finalizeAudit(
                paris,
                new List<String>{ ' PAR-001 ', 'par-001', 'LYO-001', 'NOT-IN-SF', null, ' ' },
                false
            );
        Test.stopTest();

        System.assertNotEquals(null, result.auditId);
        System.assertNotEquals(null, result.auditName);
        System.assertEquals(3, result.scannedCount, 'Codes should be trimmed and deduplicated case-insensitively.');
        System.assertEquals(3, result.expectedCount);
        System.assertEquals(2, result.anomalyCount);
        System.assertEquals('1 unknown, 1 at the wrong location', result.summary);

        Asset_Location_Audit__c auditRecord = [
            SELECT Location__c, Audit_Mode__c, Status__c, Scanned_Count__c,
                Expected_Count__c, Anomaly_Count__c, Geo_Validation_Status__c,
                Device_Location__Latitude__s, Device_Location__Longitude__s,
                Expected_Location__Latitude__s, Expected_Location__Longitude__s,
                Device_Accuracy_Meters__c, Location_Distance_Meters__c,
                Applied_Radius_Meters__c, Device_Geo_Captured_At__c
            FROM Asset_Location_Audit__c
            WHERE Id = :result.auditId
        ];
        System.assertEquals(paris.Id, auditRecord.Location__c);
        System.assertEquals('Spot Check', auditRecord.Audit_Mode__c);
        System.assertEquals('Completed with Anomalies', auditRecord.Status__c);
        System.assertEquals('Within Tolerance', auditRecord.Geo_Validation_Status__c);
        System.assertEquals(48.856600, auditRecord.Device_Location__Latitude__s);
        System.assertEquals(250, auditRecord.Applied_Radius_Meters__c);
        System.assertNotEquals(null, auditRecord.Device_Geo_Captured_At__c);

        List<Asset_Location_Anomaly__c> anomalies = [
            SELECT Anomaly_Type__c, Asset__c, Scanned_Code__c, Scanned_Location__c,
                Salesforce_Location__c, ERP_Notified__c, ERP_Notified_At__c, Notification_Error__c
            FROM Asset_Location_Anomaly__c
            WHERE Audit__c = :result.auditId
            ORDER BY Anomaly_Type__c
        ];
        System.assertEquals(2, anomalies.size());
        System.assertEquals('Unknown Asset', anomalies[0].Anomaly_Type__c);
        System.assertEquals(null, anomalies[0].Asset__c);
        System.assertEquals('NOT-IN-SF', anomalies[0].Scanned_Code__c);
        System.assertEquals('Wrong Location', anomalies[1].Anomaly_Type__c);
        System.assertNotEquals(null, anomalies[1].Asset__c);
        System.assertNotEquals(paris.Id, anomalies[1].Salesforce_Location__c);
        for (Asset_Location_Anomaly__c anomaly : anomalies) {
            System.assertEquals(paris.Id, anomaly.Scanned_Location__c);
            System.assertEquals(true, anomaly.ERP_Notified__c);
            System.assertNotEquals(null, anomaly.ERP_Notified_At__c);
            System.assertEquals(null, anomaly.Notification_Error__c);
        }
    }

    @IsTest
    static void completeInventoryAlsoPersistsEveryMissingAsset() {
        Schema.Location paris = locationByName(LOCATION_ONE);

        Test.startTest();
        AssetLocationAuditController.AuditResult result =
            finalizeAudit(
                paris,
                new List<String>{ 'PAR-001' },
                true
            );
        Test.stopTest();

        System.assertEquals(1, result.scannedCount);
        System.assertEquals(3, result.expectedCount);
        System.assertEquals(2, result.anomalyCount);
        System.assertEquals('2 missing', result.summary);

        Asset_Location_Audit__c auditRecord = [
            SELECT Audit_Mode__c, Status__c
            FROM Asset_Location_Audit__c
            WHERE Id = :result.auditId
        ];
        System.assertEquals('Complete Inventory', auditRecord.Audit_Mode__c);
        System.assertEquals('Completed with Anomalies', auditRecord.Status__c);

        List<Asset_Location_Anomaly__c> anomalies = [
            SELECT Anomaly_Type__c, Asset__r.Name, Scanned_Code__c
            FROM Asset_Location_Anomaly__c
            WHERE Audit__c = :result.auditId
        ];
        System.assertEquals(2, anomalies.size());
        Set<String> missingNames = new Set<String>();
        for (Asset_Location_Anomaly__c anomaly : anomalies) {
            System.assertEquals('Missing at Location', anomaly.Anomaly_Type__c);
            missingNames.add(anomaly.Asset__r.Name);
        }
        System.assertEquals(
            new Set<String>{ 'Paris Asset Two', 'Paris Asset Without QR' },
            missingNames
        );
    }

    @IsTest
    static void cleanSpotCheckCompletesWithoutQueueingEmail() {
        Schema.Location paris = locationByName(LOCATION_ONE);

        Test.startTest();
        AssetLocationAuditController.AuditResult result =
            finalizeAudit(
                paris,
                new List<String>{ 'PAR-001', 'PAR-002' },
                false
            );
        Integer jobsBeforeStop = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(0, result.anomalyCount);
        System.assertEquals('No anomalies', result.summary);
        System.assertEquals(0, jobsBeforeStop);
        System.assertEquals(
            'Completed',
            [SELECT Status__c FROM Asset_Location_Audit__c WHERE Id = :result.auditId].Status__c
        );
    }

    @IsTest
    static void missingRecipientRecordsNotificationError() {
        Schema.Location lyon = locationByName(LOCATION_TWO);

        AssetLocationAuditController.AuditResult result =
            finalizeAudit(
                lyon,
                new List<String>{ 'UNKNOWN-LYON' },
                false
            );

        new AssetLocationAuditEmailJob(result.auditId).execute(null);

        Asset_Location_Anomaly__c anomaly = [
            SELECT ERP_Notified__c, ERP_Notified_At__c, Notification_Error__c
            FROM Asset_Location_Anomaly__c
            WHERE Audit__c = :result.auditId
        ];
        System.assertEquals(false, anomaly.ERP_Notified__c);
        System.assertEquals(null, anomaly.ERP_Notified_At__c);
        System.assert(
            anomaly.Notification_Error__c.contains('No ERP anomaly email is configured'),
            anomaly.Notification_Error__c
        );
    }

    @IsTest
    static void locationRecipientTakesPrecedenceAndNullInputIsAllowed() {
        Schema.Location paris = locationByName(LOCATION_ONE);
        System.assertEquals(
            'paris-erp@example.com',
            AssetLocationAuditEmailJob.resolveRecipient(paris)
        );

        AssetLocationAuditController.AuditResult result =
            finalizeAudit(paris, null, false);
        System.assertEquals(0, result.scannedCount);
        System.assertEquals(0, result.anomalyCount);
    }

    @IsTest
    static void rejectsAnIdThatIsNotALocation() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Boolean rejected = false;
        try {
            AssetLocationAuditController.finalizeAudit(
                account.Id,
                new List<String>(),
                false,
                48.856600,
                2.352200,
                10,
                System.now().getTime()
            );
        } catch (AuraHandledException ex) {
            rejected = true;
        }
        System.assertEquals(true, rejected);
        System.assertEquals(0, [SELECT COUNT() FROM Asset_Location_Audit__c]);
    }

    private static Schema.Location locationByName(String locationName) {
        return [
            SELECT Id, Name, Account__c, ERP_Anomaly_Email__c,
                Geo_Coordinates__Latitude__s, Geo_Coordinates__Longitude__s
            FROM Location
            WHERE Name = :locationName
            LIMIT 1
        ];
    }

    private static AssetLocationAuditController.AuditResult finalizeAudit(
        Schema.Location locationRecord,
        List<String> scannedCodes,
        Boolean completeInventory
    ) {
        return AssetLocationAuditController.finalizeAudit(
            locationRecord.Id,
            scannedCodes,
            completeInventory,
            locationRecord.Geo_Coordinates__Latitude__s,
            locationRecord.Geo_Coordinates__Longitude__s,
            10,
            System.now().getTime()
        );
    }

    @IsTest
    static void outsideLocationRadiusCreatesGpsAnomaly() {
        Schema.Location paris = locationByName(LOCATION_ONE);

        Test.startTest();
        AssetLocationAuditController.AuditResult result =
            AssetLocationAuditController.finalizeAudit(
                paris.Id,
                new List<String>{ 'PAR-001' },
                false,
                48.866600,
                2.352200,
                10,
                System.now().getTime()
            );
        Test.stopTest();

        System.assertEquals(1, result.anomalyCount);
        System.assertEquals('Outside Tolerance', result.geoValidationStatus);
        System.assert(result.distanceMeters > 1000, String.valueOf(result.distanceMeters));
        Asset_Location_Anomaly__c anomaly = [
            SELECT Anomaly_Type__c, Asset__c, Scanned_Location__c, Details__c
            FROM Asset_Location_Anomaly__c
            WHERE Audit__c = :result.auditId
        ];
        System.assertEquals('Outside Location Radius', anomaly.Anomaly_Type__c);
        System.assertEquals(null, anomaly.Asset__c);
        System.assertEquals(paris.Id, anomaly.Scanned_Location__c);
    }

    @IsTest
    static void rejectsInaccurateDeviceLocation() {
        Schema.Location paris = locationByName(LOCATION_ONE);
        Boolean rejected = false;
        try {
            AssetLocationAuditController.finalizeAudit(
                paris.Id,
                new List<String>{ 'PAR-001' },
                false,
                48.856600,
                2.352200,
                101,
                System.now().getTime()
            );
        } catch (AuraHandledException ex) {
            rejected = true;
        }
        System.assertEquals(true, rejected);
        System.assertEquals(0, [SELECT COUNT() FROM Asset_Location_Audit__c]);
    }

    @IsTest
    static void cameraConfirmedAssetWithoutQrIsAuditedById() {
        Schema.Location paris = locationByName(LOCATION_ONE);
        Asset assetWithoutQr = [
            SELECT Id
            FROM Asset
            WHERE Name = 'Paris Asset Without QR'
            LIMIT 1
        ];

        Test.startTest();
        AssetLocationAuditController.AuditResult result =
            AssetLocationAuditController.finalizeAuditWithAssets(
                paris.Id,
                new List<String>(),
                false,
                paris.Geo_Coordinates__Latitude__s,
                paris.Geo_Coordinates__Longitude__s,
                10,
                System.now().getTime(),
                new List<Id>{ assetWithoutQr.Id }
            );
        Test.stopTest();

        System.assertEquals(1, result.scannedCount);
        System.assertEquals(0, result.anomalyCount);
    }
}
