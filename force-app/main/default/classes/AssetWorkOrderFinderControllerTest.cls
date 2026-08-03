@IsTest
private class AssetWorkOrderFinderControllerTest {
    @TestSetup
    static void setupData() {
        Account account = new Account(Name = 'Onsite Lookup Account');
        insert account;
        Schema.Location locationRecord = new Schema.Location(
            Name = 'Onsite Lookup Location',
            LocationType = 'Site',
            Account__c = account.Id
        );
        insert locationRecord;
        Product2 product = new Product2(Name = 'Onsite Instrument', IsActive = true);
        insert product;
        Asset assetRecord = new Asset(
            Name = 'Instrument A',
            AccountId = account.Id,
            Product2Id = product.Id,
            Location__c = locationRecord.Id,
            SerialNumber = 'SERIAL-100',
            Asset_QR_Code__c = 'QR-LOOKUP-100'
        );
        insert assetRecord;

        List<WorkOrder> workOrders = new List<WorkOrder>{
            new WorkOrder(
                AssetId = assetRecord.Id,
                AccountId = account.Id,
                Subject = 'Older open repair',
                Status = 'New',
                Priority = 'Medium'
            ),
            new WorkOrder(
                AssetId = assetRecord.Id,
                AccountId = account.Id,
                Subject = 'Newest open repair',
                Status = 'New',
                Priority = 'High'
            ),
            new WorkOrder(
                AssetId = assetRecord.Id,
                AccountId = account.Id,
                Subject = 'Finished repair',
                Status = 'Closed',
                Priority = 'Low'
            )
        };
        insert workOrders;
        Test.setCreatedDate(workOrders[0].Id, Datetime.newInstance(2026, 1, 1, 8, 0, 0));
        Test.setCreatedDate(workOrders[1].Id, Datetime.newInstance(2026, 2, 1, 8, 0, 0));
    }

    @IsTest
    static void qrLookupNormalizesAndReturnsNewestOpenWorkFirst() {
        Test.startTest();
        AssetWorkOrderFinderController.LookupResult result =
            AssetWorkOrderFinderController.findByQrCode('  qr-LOOKUP-100  ');
        Test.stopTest();

        System.assertEquals('Instrument A', result.asset.assetName);
        System.assertEquals('QR-LOOKUP-100', result.asset.qrCode);
        System.assertEquals('SERIAL-100', result.asset.serialNumber);
        System.assertEquals('Onsite Instrument', result.asset.productName);
        System.assertEquals('Onsite Lookup Account', result.asset.accountName);
        System.assertEquals('Onsite Lookup Location', result.asset.locationName);
        System.assertEquals(2, result.openWorkOrders.size());
        System.assertEquals('Newest open repair', result.openWorkOrders[0].subject);
        System.assertEquals('Older open repair', result.openWorkOrders[1].subject);
        System.assertEquals(false, result.workOrderLimitReached);
    }

    @IsTest
    static void confirmedAssetLookupReturnsSameAssetAndOpenWork() {
        Asset assetRecord = [SELECT Id FROM Asset WHERE Asset_QR_Code__c = 'QR-LOOKUP-100'];

        Test.startTest();
        AssetWorkOrderFinderController.LookupResult result =
            AssetWorkOrderFinderController.findByAssetId(assetRecord.Id);
        Test.stopTest();

        System.assertEquals(assetRecord.Id, result.asset.assetId);
        System.assertEquals(2, result.openWorkOrders.size());
        for (AssetWorkOrderFinderController.OpenWorkOrder workItem : result.openWorkOrders) {
            System.assertNotEquals('Finished repair', workItem.subject);
        }
    }

    @IsTest
    static void rejectsBlankOversizeAndUnknownQrCodes() {
        assertQrRejected(null);
        assertQrRejected('   ');
        assertQrRejected(makeText(256));
        assertQrRejected('QR-DOES-NOT-EXIST');
    }

    @IsTest
    static void rejectsInvalidAndUnavailableAssetIds() {
        Account account = [SELECT Id FROM Account WHERE Name = 'Onsite Lookup Account'];
        assertAssetRejected(null);
        assertAssetRejected(account.Id);

        Asset unavailable = new Asset(Name = 'Deleted Asset', AccountId = account.Id);
        insert unavailable;
        delete unavailable;
        assertAssetRejected(unavailable.Id);
    }

    @IsTest
    static void rejectsAmbiguousNormalizedQrMatchesDefensively() {
        List<Asset> candidates = new List<Asset>{
            new Asset(Name = 'First', Asset_QR_Code__c = 'QR-DUPLICATE'),
            new Asset(Name = 'Second', Asset_QR_Code__c = ' qr-duplicate ')
        };

        Boolean rejected = false;
        try {
            AssetWorkOrderFinderController.selectExactQrMatch(candidates, 'qr-duplicate');
        } catch (AuraHandledException ex) {
            rejected = true;
        }
        System.assertEquals(true, rejected, 'Ambiguous normalized matches must be rejected.');
    }

    @IsTest
    static void capsOpenWorkOrdersAtSafeLimit() {
        Asset assetRecord = [
            SELECT Id, AccountId
            FROM Asset
            WHERE Asset_QR_Code__c = 'QR-LOOKUP-100'
        ];
        List<WorkOrder> extraWork = new List<WorkOrder>();
        for (Integer index = 0; index < 50; index++) {
            extraWork.add(new WorkOrder(
                AssetId = assetRecord.Id,
                AccountId = assetRecord.AccountId,
                Subject = 'Extra open work ' + index,
                Status = 'New'
            ));
        }
        insert extraWork;

        Test.startTest();
        AssetWorkOrderFinderController.LookupResult result =
            AssetWorkOrderFinderController.findByAssetId(assetRecord.Id);
        Test.stopTest();

        System.assertEquals(50, result.openWorkOrders.size());
        System.assertEquals(true, result.workOrderLimitReached);
    }

    private static void assertQrRejected(String code) {
        Boolean rejected = false;
        try {
            AssetWorkOrderFinderController.findByQrCode(code);
        } catch (AuraHandledException ex) {
            rejected = true;
        }
        System.assertEquals(true, rejected, 'Expected the QR input to be rejected.');
    }

    private static void assertAssetRejected(Id assetId) {
        Boolean rejected = false;
        try {
            AssetWorkOrderFinderController.findByAssetId(assetId);
        } catch (AuraHandledException ex) {
            rejected = true;
        }
        System.assertEquals(true, rejected, 'Expected the Asset input to be rejected.');
    }

    private static String makeText(Integer length) {
        String value = '';
        while (value.length() < length) {
            value += 'X';
        }
        return value;
    }
}
