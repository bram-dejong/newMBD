public with sharing class AssetWorkOrderFinderController {
    private static final Integer MAX_QR_CODE_LENGTH = 255;
    private static final Integer MAX_OPEN_WORK_ORDERS = 50;

    public class LookupResult {
        @AuraEnabled public AssetDetails asset { get; set; }
        @AuraEnabled public List<OpenWorkOrder> openWorkOrders { get; set; }
        @AuraEnabled public Boolean workOrderLimitReached { get; set; }
    }

    public class AssetDetails {
        @AuraEnabled public Id assetId { get; set; }
        @AuraEnabled public String assetName { get; set; }
        @AuraEnabled public String qrCode { get; set; }
        @AuraEnabled public String serialNumber { get; set; }
        @AuraEnabled public Id productId { get; set; }
        @AuraEnabled public String productName { get; set; }
        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public Id locationId { get; set; }
        @AuraEnabled public String locationName { get; set; }
    }

    public class OpenWorkOrder {
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String priority { get; set; }
        @AuraEnabled public Datetime startDate { get; set; }
        @AuraEnabled public Datetime endDate { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public Datetime lastModifiedDate { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static LookupResult findByQrCode(String qrCode) {
        String normalizedCode = normalizeQrCode(qrCode);
        List<Asset> candidates = [
            SELECT Id, Name, Asset_QR_Code__c, SerialNumber,
                Product2Id, Product2.Name, AccountId, Account.Name,
                Location__c, Location__r.Name
            FROM Asset
            WHERE Asset_QR_Code__c = :normalizedCode
            WITH USER_MODE
            LIMIT 2
        ];
        return buildResult(selectExactQrMatch(candidates, normalizedCode));
    }

    @AuraEnabled(cacheable=true)
    public static LookupResult findByAssetId(Id assetId) {
        if (assetId == null || assetId.getSObjectType() != Asset.SObjectType) {
            throw new AuraHandledException('Select a valid Salesforce Asset before continuing.');
        }

        List<Asset> assets = [
            SELECT Id, Name, Asset_QR_Code__c, SerialNumber,
                Product2Id, Product2.Name, AccountId, Account.Name,
                Location__c, Location__r.Name
            FROM Asset
            WHERE Id = :assetId
            WITH USER_MODE
            LIMIT 1
        ];
        if (assets.isEmpty()) {
            throw new AuraHandledException(
                'The selected Asset is unavailable or you no longer have access to it.'
            );
        }
        return buildResult(assets[0]);
    }

    @TestVisible
    private static Asset selectExactQrMatch(List<Asset> candidates, String normalizedCode) {
        List<Asset> exactMatches = new List<Asset>();
        for (Asset candidate : candidates) {
            if (normalizeKey(candidate.Asset_QR_Code__c) == normalizedCode) {
                exactMatches.add(candidate);
            }
        }
        if (exactMatches.isEmpty()) {
            throw new AuraHandledException(
                'No accessible Asset matches the scanned QR code.'
            );
        }
        if (exactMatches.size() > 1) {
            throw new AuraHandledException(
                'The scanned QR code matches more than one Asset. Contact your Salesforce administrator.'
            );
        }
        return exactMatches[0];
    }

    private static LookupResult buildResult(Asset matchedAsset) {
        List<WorkOrder> workOrders = [
            SELECT Id, WorkOrderNumber, Subject, Status, Priority,
                StartDate, EndDate, CreatedDate, LastModifiedDate
            FROM WorkOrder
            WHERE AssetId = :matchedAsset.Id
                AND IsClosed = false
            WITH USER_MODE
            ORDER BY StartDate ASC NULLS LAST, CreatedDate DESC
            LIMIT :MAX_OPEN_WORK_ORDERS
        ];

        LookupResult result = new LookupResult();
        result.asset = mapAsset(matchedAsset);
        result.openWorkOrders = mapWorkOrders(workOrders);
        result.workOrderLimitReached = workOrders.size() == MAX_OPEN_WORK_ORDERS;
        return result;
    }

    private static AssetDetails mapAsset(Asset item) {
        AssetDetails result = new AssetDetails();
        result.assetId = item.Id;
        result.assetName = item.Name;
        result.qrCode = item.Asset_QR_Code__c;
        result.serialNumber = item.SerialNumber;
        result.productId = item.Product2Id;
        result.productName = item.Product2 == null ? null : item.Product2.Name;
        result.accountId = item.AccountId;
        result.accountName = item.Account == null ? null : item.Account.Name;
        result.locationId = item.Location__c;
        result.locationName = item.Location__r == null ? null : item.Location__r.Name;
        return result;
    }

    private static List<OpenWorkOrder> mapWorkOrders(List<WorkOrder> records) {
        List<OpenWorkOrder> results = new List<OpenWorkOrder>();
        for (WorkOrder item : records) {
            OpenWorkOrder result = new OpenWorkOrder();
            result.workOrderId = item.Id;
            result.workOrderNumber = item.WorkOrderNumber;
            result.subject = item.Subject;
            result.status = item.Status;
            result.priority = item.Priority;
            result.startDate = item.StartDate;
            result.endDate = item.EndDate;
            result.createdDate = item.CreatedDate;
            result.lastModifiedDate = item.LastModifiedDate;
            results.add(result);
        }
        return results;
    }

    private static String normalizeQrCode(String scannedQrCode) {
        if (String.isBlank(scannedQrCode)) {
            throw new AuraHandledException('Scan a valid Asset QR code before continuing.');
        }
        String trimmedCode = scannedQrCode.trim();
        if (trimmedCode.length() > MAX_QR_CODE_LENGTH) {
            throw new AuraHandledException(
                'The scanned QR code is longer than the supported 255 characters.'
            );
        }
        return normalizeKey(trimmedCode);
    }

    private static String normalizeKey(String value) {
        return value == null ? null : value.trim().toLowerCase();
    }
}
