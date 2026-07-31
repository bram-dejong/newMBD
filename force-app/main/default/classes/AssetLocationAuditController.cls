public with sharing class AssetLocationAuditController {
    private static final Integer MAX_SCANNED_CODES = 1000;
    private static final String MODE_SPOT_CHECK = 'Spot Check';
    private static final String MODE_COMPLETE_INVENTORY = 'Complete Inventory';
    private static final Decimal DEFAULT_MAXIMUM_DISTANCE_METERS = 250;
    private static final Decimal DEFAULT_MAXIMUM_ACCURACY_METERS = 100;
    private static final Long DEFAULT_MAX_LOCATION_AGE_MILLISECONDS = 60000;

    public class AuditResult {
        @AuraEnabled public Id auditId { get; set; }
        @AuraEnabled public String auditName { get; set; }
        @AuraEnabled public Integer scannedCount { get; set; }
        @AuraEnabled public Integer expectedCount { get; set; }
        @AuraEnabled public Integer anomalyCount { get; set; }
        @AuraEnabled public Decimal distanceMeters { get; set; }
        @AuraEnabled public String geoValidationStatus { get; set; }
        @AuraEnabled public String summary { get; set; }
        @AuraEnabled public String message { get; set; }
    }

    @AuraEnabled
    public static AuditResult finalizeAudit(
        Id locationId,
        List<String> scannedCodes,
        Boolean completeInventory,
        Decimal deviceLatitude,
        Decimal deviceLongitude,
        Decimal deviceAccuracyMeters,
        Long capturedAtEpochMs
    ) {
        return finalizeAuditInternal(
            locationId,
            scannedCodes,
            completeInventory,
            deviceLatitude,
            deviceLongitude,
            deviceAccuracyMeters,
            capturedAtEpochMs,
            new List<Id>()
        );
    }

    @AuraEnabled
    public static AuditResult finalizeAuditWithAssets(
        Id locationId,
        List<String> scannedCodes,
        Boolean completeInventory,
        Decimal deviceLatitude,
        Decimal deviceLongitude,
        Decimal deviceAccuracyMeters,
        Long capturedAtEpochMs,
        List<Id> confirmedAssetIds
    ) {
        return finalizeAuditInternal(
            locationId,
            scannedCodes,
            completeInventory,
            deviceLatitude,
            deviceLongitude,
            deviceAccuracyMeters,
            capturedAtEpochMs,
            confirmedAssetIds
        );
    }

    private static AuditResult finalizeAuditInternal(
        Id locationId,
        List<String> scannedCodes,
        Boolean completeInventory,
        Decimal deviceLatitude,
        Decimal deviceLongitude,
        Decimal deviceAccuracyMeters,
        Long capturedAtEpochMs,
        List<Id> confirmedAssetIds
    ) {
        validateLocationId(locationId);
        Map<String, String> normalizedCodes = normalizeCodes(scannedCodes);
        Set<Id> submittedAssetIds = normalizeAssetIds(confirmedAssetIds);
        if (normalizedCodes.size() + submittedAssetIds.size() > MAX_SCANNED_CODES) {
            throw new AuraHandledException(
                'A maximum of ' + MAX_SCANNED_CODES + ' unique asset codes can be submitted in one audit.'
            );
        }

        List<Schema.Location> locations = [
            SELECT Id, Name, Account__c,
                Geo_Coordinates__Latitude__s, Geo_Coordinates__Longitude__s,
                Audit_Radius_Meters__c
            FROM Location
            WHERE Id = :locationId
            WITH USER_MODE
            LIMIT 1
        ];
        if (locations.isEmpty()) {
            throw new AuraHandledException('The selected location is unavailable.');
        }

        List<Asset> expectedAssets = [
            SELECT Id, Name, Location__c, Asset_QR_Code__c
            FROM Asset
            WHERE Location__c = :locationId
            WITH USER_MODE
            ORDER BY Name
        ];

        Map<String, Asset> scannedAssetsByCode = new Map<String, Asset>();
        if (!normalizedCodes.isEmpty()) {
            for (Asset item : [
                SELECT Id, Name, Location__c, Location__r.Name, Asset_QR_Code__c
                FROM Asset
                WHERE Asset_QR_Code__c IN :normalizedCodes.values()
                WITH USER_MODE
            ]) {
                scannedAssetsByCode.put(normalizeKey(item.Asset_QR_Code__c), item);
            }
        }

        Map<Id, Asset> confirmedAssetsById = new Map<Id, Asset>();
        if (!submittedAssetIds.isEmpty()) {
            confirmedAssetsById = new Map<Id, Asset>([
                SELECT Id, Name, SerialNumber, Location__c, Location__r.Name, Asset_QR_Code__c
                FROM Asset
                WHERE Id IN :submittedAssetIds
                WITH USER_MODE
            ]);
            if (confirmedAssetsById.size() != submittedAssetIds.size()) {
                throw new AuraHandledException(
                    'One or more camera-identified Assets are unavailable. Search and confirm them again.'
                );
            }
        }

        Boolean isCompleteInventory = completeInventory == true;
        Set<Id> foundExpectedAssetIds = new Set<Id>();
        Set<Id> observedAssetIds = new Set<Id>();
        List<Asset_Location_Anomaly__c> anomalies = new List<Asset_Location_Anomaly__c>();
        Map<String, Integer> typeCounts = new Map<String, Integer>{
            'Unknown Asset' => 0,
            'Wrong Location' => 0,
            'Missing at Location' => 0,
            'Outside Location Radius' => 0
        };

        Schema.Location auditedLocation = locations[0];
        Decimal distanceMeters;
        String geoValidationStatus;
        GeoSettings settings = geoSettings();
        validateDeviceLocation(
            deviceLatitude,
            deviceLongitude,
            deviceAccuracyMeters,
            capturedAtEpochMs,
            settings
        );
        Decimal maximumDistanceMeters = auditedLocation.Audit_Radius_Meters__c != null &&
                auditedLocation.Audit_Radius_Meters__c > 0
            ? auditedLocation.Audit_Radius_Meters__c
            : settings.maximumDistanceMeters;

        if (
            auditedLocation.Geo_Coordinates__Latitude__s == null ||
            auditedLocation.Geo_Coordinates__Longitude__s == null
        ) {
            throw new AuraHandledException(
                'The selected Location has no stored geolocation coordinates. ' +
                'Add coordinates before completing the audit.'
            );
        } else {
            distanceMeters = calculateDistanceMeters(
                deviceLatitude,
                deviceLongitude,
                auditedLocation.Geo_Coordinates__Latitude__s,
                auditedLocation.Geo_Coordinates__Longitude__s
            );
            if (distanceMeters + deviceAccuracyMeters <= maximumDistanceMeters) {
                geoValidationStatus = 'Within Tolerance';
            } else if (distanceMeters - deviceAccuracyMeters > maximumDistanceMeters) {
                geoValidationStatus = 'Outside Tolerance';
                anomalies.add(newAnomaly(
                    locationId,
                    null,
                    locationId,
                    null,
                    'Outside Location Radius',
                    'The device was ' + String.valueOf(distanceMeters) +
                        ' metres from the stored Location coordinates. The allowed radius was ' +
                        String.valueOf(maximumDistanceMeters) + ' metres; device accuracy was ' +
                        String.valueOf(deviceAccuracyMeters) + ' metres.'
                ));
                increment(typeCounts, 'Outside Location Radius');
            } else {
                throw new AuraHandledException(
                    'The device location accuracy overlaps the Location boundary. ' +
                    'Move to an area with a better GPS signal and try again.'
                );
            }
        }

        for (String codeKey : normalizedCodes.keySet()) {
            String submittedCode = normalizedCodes.get(codeKey);
            Asset matchedAsset = scannedAssetsByCode.get(codeKey);
            if (matchedAsset == null) {
                anomalies.add(newAnomaly(
                    locationId,
                    null,
                    null,
                    submittedCode,
                    'Unknown Asset',
                    'The scanned QR code does not match an Asset in Salesforce.'
                ));
                increment(typeCounts, 'Unknown Asset');
            } else if (observedAssetIds.contains(matchedAsset.Id)) {
                continue;
            } else if (matchedAsset.Location__c != locationId) {
                observedAssetIds.add(matchedAsset.Id);
                anomalies.add(newAnomaly(
                    locationId,
                    matchedAsset.Id,
                    matchedAsset.Location__c,
                    submittedCode,
                    'Wrong Location',
                    'Asset ' + matchedAsset.Name + ' is assigned to ' +
                        (matchedAsset.Location__r == null ? 'no Salesforce location' : matchedAsset.Location__r.Name) + '.'
                ));
                increment(typeCounts, 'Wrong Location');
            } else {
                observedAssetIds.add(matchedAsset.Id);
                foundExpectedAssetIds.add(matchedAsset.Id);
            }
        }

        for (Asset confirmedAsset : confirmedAssetsById.values()) {
            if (observedAssetIds.contains(confirmedAsset.Id)) {
                continue;
            }
            observedAssetIds.add(confirmedAsset.Id);
            if (confirmedAsset.Location__c != locationId) {
                anomalies.add(newAnomaly(
                    locationId,
                    confirmedAsset.Id,
                    confirmedAsset.Location__c,
                    confirmedAsset.SerialNumber,
                    'Wrong Location',
                    'Camera-identified Asset ' + confirmedAsset.Name + ' is assigned to ' +
                        (confirmedAsset.Location__r == null ? 'no Salesforce location' : confirmedAsset.Location__r.Name) + '.'
                ));
                increment(typeCounts, 'Wrong Location');
            } else {
                foundExpectedAssetIds.add(confirmedAsset.Id);
            }
        }

        Integer scannedItemCount = observedAssetIds.size() +
            countUnknownCodes(normalizedCodes, scannedAssetsByCode);

        if (isCompleteInventory) {
            for (Asset expectedAsset : expectedAssets) {
                if (!foundExpectedAssetIds.contains(expectedAsset.Id)) {
                    anomalies.add(newAnomaly(
                        locationId,
                        expectedAsset.Id,
                        expectedAsset.Location__c,
                        expectedAsset.Asset_QR_Code__c,
                        'Missing at Location',
                        'Asset ' + expectedAsset.Name + ' was expected at this location but was not scanned.'
                    ));
                    increment(typeCounts, 'Missing at Location');
                }
            }
        }

        Asset_Location_Audit__c auditRecord = new Asset_Location_Audit__c(
            Location__c = locationId,
            Audit_Mode__c = isCompleteInventory ? MODE_COMPLETE_INVENTORY : MODE_SPOT_CHECK,
            Completed_At__c = System.now(),
            Scanned_Count__c = scannedItemCount,
            Expected_Count__c = expectedAssets.size(),
            Anomaly_Count__c = anomalies.size(),
            Device_Location__Latitude__s = deviceLatitude,
            Device_Location__Longitude__s = deviceLongitude,
            Device_Accuracy_Meters__c = deviceAccuracyMeters,
            Device_Geo_Captured_At__c = Datetime.newInstance(capturedAtEpochMs),
            Location_Distance_Meters__c = distanceMeters,
            Expected_Location__Latitude__s = auditedLocation.Geo_Coordinates__Latitude__s,
            Expected_Location__Longitude__s = auditedLocation.Geo_Coordinates__Longitude__s,
            Applied_Radius_Meters__c = maximumDistanceMeters,
            Geo_Validation_Status__c = geoValidationStatus,
            Status__c = anomalies.isEmpty() ? 'Completed' : 'Completed with Anomalies'
        );

        try {
            insert as user auditRecord;
            for (Asset_Location_Anomaly__c anomaly : anomalies) {
                anomaly.Audit__c = auditRecord.Id;
            }
            if (!anomalies.isEmpty()) {
                insert as user anomalies;
                System.enqueueJob(new AssetLocationAuditEmailJob(auditRecord.Id));
            }
        } catch (DmlException ex) {
            throw new AuraHandledException('The audit could not be saved. ' + firstDmlMessage(ex));
        }

        auditRecord = [
            SELECT Id, Name
            FROM Asset_Location_Audit__c
            WHERE Id = :auditRecord.Id
            WITH USER_MODE
        ];

        AuditResult result = new AuditResult();
        result.auditId = auditRecord.Id;
        result.auditName = auditRecord.Name;
        result.scannedCount = scannedItemCount;
        result.expectedCount = expectedAssets.size();
        result.anomalyCount = anomalies.size();
        result.distanceMeters = distanceMeters;
        result.geoValidationStatus = geoValidationStatus;
        result.summary = buildSummary(typeCounts);
        result.message = anomalies.isEmpty()
            ? 'Audit completed. No location anomalies were detected.'
            : 'Audit completed with ' + anomalies.size() + ' location ' +
                (anomalies.size() == 1 ? 'anomaly.' : 'anomalies.');
        return result;
    }

    private static Asset_Location_Anomaly__c newAnomaly(
        Id scannedLocationId,
        Id assetId,
        Id salesforceLocationId,
        String scannedCode,
        String anomalyType,
        String details
    ) {
        return new Asset_Location_Anomaly__c(
            Asset__c = assetId,
            Scanned_Location__c = scannedLocationId,
            Salesforce_Location__c = salesforceLocationId,
            Scanned_Code__c = scannedCode,
            Anomaly_Type__c = anomalyType,
            Details__c = details,
            Status__c = 'Open',
            ERP_Notified__c = false
        );
    }

    private static Map<String, String> normalizeCodes(List<String> scannedCodes) {
        Map<String, String> result = new Map<String, String>();
        if (scannedCodes == null) {
            return result;
        }
        for (String value : scannedCodes) {
            if (String.isBlank(value)) {
                continue;
            }
            String trimmedValue = value.trim();
            String key = normalizeKey(trimmedValue);
            if (!result.containsKey(key)) {
                result.put(key, trimmedValue);
            }
        }
        return result;
    }

    private static Set<Id> normalizeAssetIds(List<Id> assetIds) {
        Set<Id> result = new Set<Id>();
        if (assetIds == null) {
            return result;
        }
        for (Id assetId : assetIds) {
            if (assetId == null || assetId.getSObjectType() != Asset.SObjectType) {
                throw new AuraHandledException('Only confirmed Salesforce Assets can be submitted.');
            }
            result.add(assetId);
        }
        return result;
    }

    private static Integer countUnknownCodes(
        Map<String, String> normalizedCodes,
        Map<String, Asset> scannedAssetsByCode
    ) {
        Integer count = 0;
        for (String codeKey : normalizedCodes.keySet()) {
            if (!scannedAssetsByCode.containsKey(codeKey)) {
                count++;
            }
        }
        return count;
    }

    private static String normalizeKey(String value) {
        return value == null ? null : value.trim().toLowerCase();
    }

    private static void validateLocationId(Id locationId) {
        if (locationId == null || locationId.getSObjectType() != Schema.Location.SObjectType) {
            throw new AuraHandledException('Select a valid Location before completing the audit.');
        }
    }

    private static void validateDeviceLocation(
        Decimal latitude,
        Decimal longitude,
        Decimal accuracyMeters,
        Long capturedAtEpochMs,
        GeoSettings settings
    ) {
        if (latitude == null || latitude < -90 || latitude > 90 ||
            longitude == null || longitude < -180 || longitude > 180) {
            throw new AuraHandledException(
                'A valid current device location is required to complete the audit.'
            );
        }
        if (accuracyMeters == null || accuracyMeters < 0 ||
            accuracyMeters > settings.maximumAccuracyMeters) {
            throw new AuraHandledException(
                'The device location accuracy must be ' +
                String.valueOf(settings.maximumAccuracyMeters) + ' metres or better.'
            );
        }
        Long ageMilliseconds = capturedAtEpochMs == null
            ? null
            : System.now().getTime() - capturedAtEpochMs;
        if (ageMilliseconds == null || ageMilliseconds < 0 ||
            ageMilliseconds > settings.maximumLocationAgeMilliseconds) {
            throw new AuraHandledException(
                'The device location reading is stale. Capture a new location and try again.'
            );
        }
    }

    private class GeoSettings {
        Decimal maximumDistanceMeters;
        Decimal maximumAccuracyMeters;
        Long maximumLocationAgeMilliseconds;
    }

    private static GeoSettings geoSettings() {
        Asset_Audit_Setting__mdt setting = Asset_Audit_Setting__mdt.getInstance('Default');
        GeoSettings result = new GeoSettings();
        result.maximumDistanceMeters = setting != null &&
                setting.Maximum_Distance_Meters__c != null &&
                setting.Maximum_Distance_Meters__c > 0
            ? setting.Maximum_Distance_Meters__c
            : DEFAULT_MAXIMUM_DISTANCE_METERS;
        result.maximumAccuracyMeters = setting != null &&
                setting.Maximum_Accuracy_Meters__c != null &&
                setting.Maximum_Accuracy_Meters__c > 0
            ? setting.Maximum_Accuracy_Meters__c
            : DEFAULT_MAXIMUM_ACCURACY_METERS;
        Decimal ageSeconds = setting != null &&
                setting.Maximum_Fix_Age_Seconds__c != null &&
                setting.Maximum_Fix_Age_Seconds__c > 0
            ? setting.Maximum_Fix_Age_Seconds__c
            : Decimal.valueOf(DEFAULT_MAX_LOCATION_AGE_MILLISECONDS / 1000);
        result.maximumLocationAgeMilliseconds =
            Long.valueOf(String.valueOf(ageSeconds.setScale(0))) * 1000;
        return result;
    }

    @TestVisible
    private static Decimal calculateDistanceMeters(
        Decimal latitudeOne,
        Decimal longitudeOne,
        Decimal latitudeTwo,
        Decimal longitudeTwo
    ) {
        Double radiansPerDegree = 3.141592653589793 / 180;
        Double firstLatitude = Double.valueOf(String.valueOf(latitudeOne)) * radiansPerDegree;
        Double secondLatitude = Double.valueOf(String.valueOf(latitudeTwo)) * radiansPerDegree;
        Double latitudeDelta =
            Double.valueOf(String.valueOf(latitudeTwo - latitudeOne)) * radiansPerDegree;
        Double longitudeDelta =
            Double.valueOf(String.valueOf(longitudeTwo - longitudeOne)) * radiansPerDegree;
        Double sinLatitude = Math.sin(latitudeDelta / 2);
        Double sinLongitude = Math.sin(longitudeDelta / 2);
        Double haversine = sinLatitude * sinLatitude +
            Math.cos(firstLatitude) * Math.cos(secondLatitude) *
            sinLongitude * sinLongitude;
        if (haversine > 1) {
            haversine = 1;
        }
        Double distance = 6371000 * 2 * Math.asin(Math.sqrt(haversine));
        return Decimal.valueOf(String.valueOf(distance)).setScale(2);
    }

    private static void increment(Map<String, Integer> counts, String anomalyType) {
        counts.put(anomalyType, counts.get(anomalyType) + 1);
    }

    private static String buildSummary(Map<String, Integer> counts) {
        List<String> parts = new List<String>();
        if (counts.get('Unknown Asset') > 0) {
            parts.add(counts.get('Unknown Asset') + ' unknown');
        }
        if (counts.get('Wrong Location') > 0) {
            parts.add(counts.get('Wrong Location') + ' at the wrong location');
        }
        if (counts.get('Missing at Location') > 0) {
            parts.add(counts.get('Missing at Location') + ' missing');
        }
        if (counts.get('Outside Location Radius') > 0) {
            parts.add(counts.get('Outside Location Radius') + ' outside the location radius');
        }
        return parts.isEmpty() ? 'No anomalies' : String.join(parts, ', ');
    }

    private static String firstDmlMessage(DmlException ex) {
        return ex.getNumDml() > 0 ? ex.getDmlMessage(0) : ex.getMessage();
    }
}
