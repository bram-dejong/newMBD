public without sharing class PMWorkOrderGenerationService {
    public class GenerationResult {
        public Integer evaluatedCount = 0;
        public Integer createdCount = 0;
        public Integer skippedCount = 0;
        public Integer errorCount = 0;
    }

    public static GenerationResult generate(List<Entitlement> entitlements, Date runDate) {
        GenerationResult outcome = new GenerationResult();
        if (entitlements == null || entitlements.isEmpty()) {
            return outcome;
        }
        Date effectiveRunDate = runDate == null ? Date.today() : runDate;
        Set<Id> entitlementIds = new Set<Id>();
        for (Entitlement item : entitlements) {
            if (item != null && item.Id != null) {
                entitlementIds.add(item.Id);
            }
        }

        Map<Id, Integer> workOrderCounts = new Map<Id, Integer>();
        for (AggregateResult aggregateItem : [
            SELECT EntitlementId entitlementId, COUNT(Id) workOrderCount
            FROM WorkOrder
            WHERE EntitlementId IN :entitlementIds
                AND System_Generated_PM__c = true
            GROUP BY EntitlementId
        ]) {
            workOrderCounts.put(
                (Id) aggregateItem.get('entitlementId'),
                (Integer) aggregateItem.get('workOrderCount')
            );
        }

        Map<Id, Date> latestGeneratedDueDates = new Map<Id, Date>();
        Set<Id> entitlementsWithOpenPM = new Set<Id>();
        Set<String> existingKeys = new Set<String>();
        for (WorkOrder keyedWork : [
            SELECT PM_Generation_Key__c
            FROM WorkOrder
            WHERE EntitlementId IN :entitlementIds
                AND PM_Generation_Key__c != null
        ]) {
            existingKeys.add(keyedWork.PM_Generation_Key__c);
        }
        for (WorkOrder existingWork : [
            SELECT EntitlementId, PM_Due_Date__c, PM_Generation_Key__c, IsClosed
            FROM WorkOrder
            WHERE EntitlementId IN :entitlementIds
                AND System_Generated_PM__c = true
        ]) {
            if (!existingWork.IsClosed) {
                entitlementsWithOpenPM.add(existingWork.EntitlementId);
            }
            Date currentLatest = latestGeneratedDueDates.get(existingWork.EntitlementId);
            if (existingWork.PM_Due_Date__c != null &&
                (currentLatest == null || existingWork.PM_Due_Date__c > currentLatest)) {
                latestGeneratedDueDates.put(existingWork.EntitlementId, existingWork.PM_Due_Date__c);
            }
        }

        List<WorkOrder> candidates = new List<WorkOrder>();
        for (Entitlement item : entitlements) {
            outcome.evaluatedCount++;
            WorkOrder candidate = buildCandidate(
                item,
                effectiveRunDate,
                workOrderCounts.get(item.Id),
                latestGeneratedDueDates.get(item.Id),
                entitlementsWithOpenPM.contains(item.Id)
            );
            if (candidate == null || existingKeys.contains(candidate.PM_Generation_Key__c)) {
                outcome.skippedCount++;
                continue;
            }
            candidates.add(candidate);
        }

        if (candidates.isEmpty()) {
            return outcome;
        }
        Database.UpsertResult[] results = Database.upsert(
            candidates,
            WorkOrder.Fields.PM_Generation_Key__c,
            false
        );
        for (Database.UpsertResult result : results) {
            if (result.isSuccess()) {
                outcome.createdCount++;
            } else {
                outcome.errorCount++;
            }
        }
        return outcome;
    }

    @TestVisible
    private static WorkOrder buildCandidate(
        Entitlement item,
        Date runDate,
        Integer existingWorkOrderCount,
        Date latestGeneratedDueDate,
        Boolean hasOpenPM
    ) {
        if (item == null || item.Id == null || !item.PM_Generation_Enabled__c ||
            item.AssetId == null || item.ServiceContractId == null || item.Asset == null ||
            item.Asset.Product2 == null || !item.Asset.Product2.Requires_Maintenance__c ||
            !item.Asset.PM_Automation_Enabled__c || item.PM_Interval_Days__c == null ||
            item.PM_Interval_Days__c <= 0 ||
            (item.PM_Creation_Lead_Days__c != null && item.PM_Creation_Lead_Days__c < 0) ||
            hasOpenPM) {
            return null;
        }
        Integer currentCount = existingWorkOrderCount == null ? 0 : existingWorkOrderCount;
        if (item.WorkOrdersPerEntitlement == null || item.WorkOrdersPerEntitlement <= 0 ||
            currentCount >= item.WorkOrdersPerEntitlement) {
            return null;
        }
        if (item.AccountId == null ||
            (item.Asset.AccountId != null && item.Asset.AccountId != item.AccountId) ||
            (item.ServiceContract != null && item.ServiceContract.AccountId != null &&
                item.ServiceContract.AccountId != item.AccountId)) {
            return null;
        }

        Date entitlementStart = item.StartDate;
        Date contractStart = item.ServiceContract == null ? null : item.ServiceContract.StartDate;
        Date anchorDate = item.Asset.PM_Base_Date__c;
        if (anchorDate == null) {
            anchorDate = item.Asset.Last_PM_Date__c;
        }
        if (anchorDate == null) {
            anchorDate = laterDate(entitlementStart, contractStart);
        }
        if (anchorDate == null) {
            return null;
        }
        if (latestGeneratedDueDate != null && latestGeneratedDueDate > anchorDate) {
            anchorDate = latestGeneratedDueDate;
        }

        Integer intervalDays = item.PM_Interval_Days__c.intValue();
        Integer leadDays = item.PM_Creation_Lead_Days__c == null
            ? 30
            : item.PM_Creation_Lead_Days__c.intValue();
        Date dueDate = anchorDate.addDays(intervalDays);
        Date entitlementEnd = item.EndDate;
        Date contractEnd = item.ServiceContract == null ? null : item.ServiceContract.EndDate;
        if (entitlementStart == null || entitlementEnd == null || contractStart == null ||
            contractEnd == null || entitlementStart > entitlementEnd || contractStart > contractEnd) {
            return null;
        }
        Date coverageEnd = earlierDate(entitlementEnd, contractEnd);
        Date coverageStart = laterDate(entitlementStart, contractStart);
        if (runDate < coverageStart || runDate > coverageEnd || dueDate < coverageStart ||
            dueDate > coverageEnd ||
            runDate < dueDate.addDays(-leadDays)) {
            return null;
        }

        return new WorkOrder(
            AccountId = item.AccountId == null ? item.Asset.AccountId : item.AccountId,
            AssetId = item.AssetId,
            EntitlementId = item.Id,
            ServiceContractId = item.ServiceContractId,
            Subject = 'Preventive Maintenance - ' + item.Asset.Name,
            Status = 'New',
            Priority = 'Medium',
            StartDate = Datetime.newInstance(dueDate, Time.newInstance(8, 0, 0, 0)),
            System_Generated_PM__c = true,
            PM_Due_Date__c = dueDate,
            PM_Generation_Key__c = buildGenerationKey(item.AssetId, item.Id, dueDate)
        );
    }

    @TestVisible
    private static String buildGenerationKey(Id assetId, Id entitlementId, Date dueDate) {
        return String.valueOf(assetId) + ':' + String.valueOf(entitlementId) + ':' +
            String.valueOf(dueDate);
    }

    private static Date laterDate(Date leftDate, Date rightDate) {
        if (leftDate == null) return rightDate;
        if (rightDate == null) return leftDate;
        return leftDate >= rightDate ? leftDate : rightDate;
    }

    private static Date earlierDate(Date leftDate, Date rightDate) {
        if (leftDate == null) return rightDate;
        if (rightDate == null) return leftDate;
        return leftDate <= rightDate ? leftDate : rightDate;
    }
}
