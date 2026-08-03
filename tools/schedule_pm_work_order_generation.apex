String jobName = 'newMBD PM Work Order Generation - Daily';
List<CronTrigger> existingJobs = [
    SELECT Id
    FROM CronTrigger
    WHERE CronJobDetail.Name = :jobName
        AND State IN ('WAITING', 'ACQUIRED', 'PAUSED', 'BLOCKED')
];
if (existingJobs.isEmpty()) {
    String jobId = System.schedule(jobName, '0 0 2 * * ?', new PMWorkOrderScheduler());
    System.debug('Scheduled PM Work Order generation job: ' + jobId);
} else {
    System.debug('PM Work Order generation job already scheduled: ' + existingJobs[0].Id);
}
