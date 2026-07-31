@IsTest
private class AssetPhotoIdentificationControllerTest {
    private class ExtractingProvider implements AssetNameplateRecognitionProvider {
        public AssetPhotoIdentificationController.ProviderResponse analyze(
            AssetPhotoIdentificationController.ProviderRequest request
        ) {
            System.assertEquals('image/jpeg', request.mimeType);
            System.assertEquals('NAMEPLATE', request.stage);
            System.assert(request.imageBody.size() > 0);
            AssetPhotoIdentificationController.ProviderResponse response =
                new AssetPhotoIdentificationController.ProviderResponse();
            response.providerName = 'Test provider';
            response.status = 'EXTRACTED';
            response.extractedSerial = ' sn-100 ';
            response.extractedModel = 'Test Model';
            response.confidence = 94.5;
            response.guidance = 'Confirm the extracted serial.';
            return response;
        }
    }

    @TestSetup
    static void setupData() {
        Account account = new Account(Name = 'Photo Test Account');
        insert account;
        Schema.Location locationRecord = new Schema.Location(
            Name = 'Photo Test Location',
            LocationType = 'Site',
            Account__c = account.Id
        );
        insert locationRecord;
        Product2 product = new Product2(Name = 'Test Instrument', IsActive = true);
        insert product;
        insert new List<Asset>{
            new Asset(
                Name = 'Matched Instrument',
                AccountId = account.Id,
                Location__c = locationRecord.Id,
                Product2Id = product.Id,
                SerialNumber = 'SN-100'
            ),
            new Asset(
                Name = 'Duplicate Serial Instrument',
                AccountId = account.Id,
                Product2Id = product.Id,
                SerialNumber = 'SN-100'
            )
        };
    }

    @IsTest
    static void unconfiguredProviderIsTransparentAndTransient() {
        AssetPhotoIdentificationController.PhotoAnalysisResult result =
            AssetPhotoIdentificationController.analyzePhoto(
                EncodingUtil.base64Encode(Blob.valueOf('test image')),
                'image/jpeg',
                'DEVICE'
            );
        System.assertEquals('UNAVAILABLE', result.status);
        System.assertEquals('Unconfigured provider', result.providerName);
        System.assert(result.guidance.contains('not configured'));
    }

    @IsTest
    static void providerOutputIsNormalized() {
        AssetPhotoIdentificationController.providerOverride = new ExtractingProvider();
        AssetPhotoIdentificationController.PhotoAnalysisResult result =
            AssetPhotoIdentificationController.analyzePhoto(
                EncodingUtil.base64Encode(Blob.valueOf('test image')),
                'IMAGE/JPEG',
                'NAMEPLATE'
            );
        System.assertEquals('SN-100', result.extractedSerial);
        System.assertEquals('Test Model', result.extractedModel);
        System.assertEquals(94.5, result.confidence);
    }

    @IsTest
    static void exactSerialReturnsBoundedCandidates() {
        Schema.Location locationRecord = [SELECT Id FROM Location WHERE Name = 'Photo Test Location'];
        List<AssetPhotoIdentificationController.Candidate> results =
            AssetPhotoIdentificationController.findCandidates(' sn-100 ', null, locationRecord.Id);
        System.assertEquals(2, results.size());
        Integer atLocation = 0;
        for (AssetPhotoIdentificationController.Candidate item : results) {
            System.assertEquals('SN-100', item.serialNumber);
            System.assertEquals('Test Instrument', item.productName);
            if (item.atSelectedLocation) atLocation++;
        }
        System.assertEquals(1, atLocation);
    }

    @IsTest
    static void rejectsUnsupportedImageAndInvalidLocation() {
        Boolean imageRejected = false;
        try {
            AssetPhotoIdentificationController.analyzePhoto('dGVzdA==', 'text/plain', 'DEVICE');
        } catch (AuraHandledException ex) {
            imageRejected = true;
        }
        System.assertEquals(true, imageRejected);

        Account account = [SELECT Id FROM Account LIMIT 1];
        Boolean locationRejected = false;
        try {
            AssetPhotoIdentificationController.findCandidates('SN-100', null, account.Id);
        } catch (AuraHandledException ex) {
            locationRejected = true;
        }
        System.assertEquals(true, locationRejected);
    }
}
