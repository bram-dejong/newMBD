public without sharing class PMWorkOrderScheduler implements Schedulable {
    public void execute(SchedulableContext context) {
        Database.executeBatch(new PMWorkOrderBatch(), 200);
    }
}
