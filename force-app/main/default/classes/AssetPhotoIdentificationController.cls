public with sharing class AssetPhotoIdentificationController {
    private static final Integer MAX_IMAGE_BYTES = 750000;
    private static final Integer MAX_SERIAL_LENGTH = 80;
    private static final Set<String> ALLOWED_MIME_TYPES = new Set<String>{
        'image/jpeg', 'image/png', 'image/webp'
    };

    @TestVisible private static AssetNameplateRecognitionProvider providerOverride;

    public class ProviderRequest {
        public Blob imageBody;
        public String mimeType;
        public String stage;
    }

    public class ProviderResponse {
        public String providerName;
        public String status;
        public String extractedSerial;
        public String extractedModel;
        public Decimal confidence;
        public String guidance;
    }

    public class PhotoAnalysisResult {
        @AuraEnabled public String providerName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String extractedSerial { get; set; }
        @AuraEnabled public String extractedModel { get; set; }
        @AuraEnabled public Decimal confidence { get; set; }
        @AuraEnabled public String guidance { get; set; }
    }

    public class Candidate {
        @AuraEnabled public Id assetId { get; set; }
        @AuraEnabled public String assetName { get; set; }
        @AuraEnabled public String serialNumber { get; set; }
        @AuraEnabled public String productName { get; set; }
        @AuraEnabled public Id salesforceLocationId { get; set; }
        @AuraEnabled public String salesforceLocationName { get; set; }
        @AuraEnabled public Boolean atSelectedLocation { get; set; }
    }

    @AuraEnabled
    public static PhotoAnalysisResult analyzePhoto(String imageBase64, String mimeType, String stage) {
        String normalizedMimeType = String.isBlank(mimeType) ? null : mimeType.trim().toLowerCase();
        if (!ALLOWED_MIME_TYPES.contains(normalizedMimeType)) {
            throw new AuraHandledException('Choose a JPEG, PNG, or WebP image.');
        }
        if (String.isBlank(imageBase64)) {
            throw new AuraHandledException('Capture or choose an image before continuing.');
        }

        Blob imageBody;
        try {
            imageBody = EncodingUtil.base64Decode(imageBase64);
        } catch (Exception ex) {
            throw new AuraHandledException('The selected image could not be read. Choose another image.');
        }
        if (imageBody.size() > MAX_IMAGE_BYTES) {
            throw new AuraHandledException('The processed image must be 750 KB or smaller.');
        }

        ProviderRequest request = new ProviderRequest();
        request.imageBody = imageBody;
        request.mimeType = normalizedMimeType;
        request.stage = clean(stage, 40);
        ProviderResponse response = provider().analyze(request);
        if (response == null) {
            throw new AuraHandledException('Photo analysis is temporarily unavailable. Enter the serial number manually.');
        }

        PhotoAnalysisResult result = new PhotoAnalysisResult();
        result.providerName = clean(response.providerName, 80);
        result.status = clean(response.status, 40);
        result.extractedSerial = normalizeSerial(response.extractedSerial, false);
        result.extractedModel = clean(response.extractedModel, 255);
        result.confidence = clampConfidence(response.confidence);
        result.guidance = clean(response.guidance, 1000);
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<Candidate> findCandidates(String serialNumber, String model, Id locationId) {
        if (locationId != null) {
            validateLocation(locationId);
        }
        String normalizedSerial = normalizeSerial(serialNumber, true);
        List<Asset> assets = [
            SELECT Id, Name, SerialNumber, Product2.Name, Location__c, Location__r.Name
            FROM Asset
            WHERE SerialNumber = :normalizedSerial
            WITH USER_MODE
            ORDER BY Name
            LIMIT 25
        ];

        List<Candidate> results = new List<Candidate>();
        for (Asset item : assets) {
            Candidate candidate = new Candidate();
            candidate.assetId = item.Id;
            candidate.assetName = item.Name;
            candidate.serialNumber = item.SerialNumber;
            candidate.productName = item.Product2 == null ? null : item.Product2.Name;
            candidate.salesforceLocationId = item.Location__c;
            candidate.salesforceLocationName = item.Location__r == null ? null : item.Location__r.Name;
            candidate.atSelectedLocation = locationId != null && item.Location__c == locationId;
            results.add(candidate);
        }
        return results;
    }

    private static AssetNameplateRecognitionProvider provider() {
        return providerOverride == null ? new MockAssetNameplateRecognitionProvider() : providerOverride;
    }

    private static void validateLocation(Id locationId) {
        if (locationId == null || locationId.getSObjectType() != Schema.Location.SObjectType) {
            throw new AuraHandledException('Select a valid Location before identifying an Asset.');
        }
        if ([SELECT COUNT() FROM Location WHERE Id = :locationId WITH USER_MODE] == 0) {
            throw new AuraHandledException('The selected Location is unavailable.');
        }
    }

    private static String normalizeSerial(String value, Boolean required) {
        String result = clean(value, MAX_SERIAL_LENGTH);
        if (required && String.isBlank(result)) {
            throw new AuraHandledException('Enter the serial number visible on the Asset nameplate.');
        }
        return result == null ? null : result.toUpperCase();
    }

    private static Decimal clampConfidence(Decimal confidence) {
        if (confidence == null) return null;
        if (confidence < 0) return 0;
        if (confidence > 100) return 100;
        return confidence;
    }

    private static String clean(String value, Integer maximumLength) {
        if (String.isBlank(value)) return null;
        String result = value.trim();
        return result.length() <= maximumLength ? result : result.substring(0, maximumLength);
    }
}
