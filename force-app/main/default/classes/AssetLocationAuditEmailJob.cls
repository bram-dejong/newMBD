public with sharing class AssetLocationAuditEmailJob implements Queueable {
    private final Id auditId;

    @TestVisible
    private static EmailTransport emailTransport = new PlatformEmailTransport();

    public AssetLocationAuditEmailJob(Id auditId) {
        this.auditId = auditId;
    }

    public void execute(QueueableContext context) {
        List<Asset_Location_Audit__c> audits = [
            SELECT Id, Name, Location__c, Location__r.Name, Location__r.ERP_Anomaly_Email__c,
                Location__r.Account__c,
                Audit_Mode__c, Completed_At__c, Scanned_Count__c, Expected_Count__c, Anomaly_Count__c,
                Geo_Validation_Status__c, Location_Distance_Meters__c,
                Device_Accuracy_Meters__c, Applied_Radius_Meters__c
            FROM Asset_Location_Audit__c
            WHERE Id = :auditId
            WITH USER_MODE
            LIMIT 1
        ];
        if (audits.isEmpty()) {
            return;
        }

        Asset_Location_Audit__c auditRecord = audits[0];
        List<Asset_Location_Anomaly__c> anomalies = [
            SELECT Id, Anomaly_Type__c, Asset__c, Asset__r.Name, Scanned_Code__c,
                Salesforce_Location__c, Salesforce_Location__r.Name, Details__c
            FROM Asset_Location_Anomaly__c
            WHERE Audit__c = :auditId
            WITH USER_MODE
            ORDER BY Anomaly_Type__c, CreatedDate
        ];
        if (anomalies.isEmpty()) {
            return;
        }

        String recipient = resolveRecipient(auditRecord.Location__r);
        String errorMessage;
        Boolean sent = false;

        if (String.isBlank(recipient)) {
            errorMessage =
                'No ERP anomaly email is configured on the Location or Asset Audit Setting.Default.';
        } else {
            try {
                Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
                message.setToAddresses(new List<String>{ recipient });
                message.setSubject(
                    'Asset location anomalies - ' + auditRecord.Location__r.Name + ' - ' + auditRecord.Name
                );
                message.setPlainTextBody(buildBody(auditRecord, anomalies));
                Messaging.SendEmailResult sendResult = emailTransport.send(message);
                if (sendResult != null && sendResult.isSuccess()) {
                    sent = true;
                } else {
                    errorMessage = extractSendError(sendResult);
                }
            } catch (Exception ex) {
                errorMessage = ex.getMessage();
            }
        }

        Datetime notificationTime = sent ? System.now() : null;
        String storedError = sent ? null : truncate(errorMessage, 32768);
        List<Asset_Location_Anomaly__c> updates = new List<Asset_Location_Anomaly__c>();
        for (Asset_Location_Anomaly__c anomaly : anomalies) {
            updates.add(new Asset_Location_Anomaly__c(
                Id = anomaly.Id,
                ERP_Notified__c = sent,
                ERP_Notified_At__c = notificationTime,
                Notification_Error__c = storedError
            ));
        }
        update as user updates;
    }

    @TestVisible
    private static String resolveRecipient(Schema.Location location) {
        if (location != null && !String.isBlank(location.ERP_Anomaly_Email__c)) {
            return location.ERP_Anomaly_Email__c.trim();
        }
        Asset_Audit_Setting__mdt setting = Asset_Audit_Setting__mdt.getInstance('Default');
        return setting == null || String.isBlank(setting.Default_ERP_Recipient__c)
            ? null
            : setting.Default_ERP_Recipient__c.trim();
    }

    private static String buildBody(
        Asset_Location_Audit__c auditRecord,
        List<Asset_Location_Anomaly__c> anomalies
    ) {
        List<String> lines = new List<String>{
            'Asset location audit ' + auditRecord.Name,
            'Location: ' + auditRecord.Location__r.Name,
            'Mode: ' + auditRecord.Audit_Mode__c,
            'Completed: ' + String.valueOf(auditRecord.Completed_At__c),
            'Scanned: ' + String.valueOf(auditRecord.Scanned_Count__c),
            'Expected: ' + String.valueOf(auditRecord.Expected_Count__c),
            'Anomalies: ' + String.valueOf(auditRecord.Anomaly_Count__c),
            'GPS validation: ' + auditRecord.Geo_Validation_Status__c,
            'GPS distance (m): ' + String.valueOf(auditRecord.Location_Distance_Meters__c),
            'GPS accuracy (m): ' + String.valueOf(auditRecord.Device_Accuracy_Meters__c),
            'Applied radius (m): ' + String.valueOf(auditRecord.Applied_Radius_Meters__c),
            ''
        };
        Integer sequence = 0;
        for (Asset_Location_Anomaly__c anomaly : anomalies) {
            sequence++;
            lines.add(sequence + '. ' + anomaly.Anomaly_Type__c);
            if (anomaly.Anomaly_Type__c != 'Outside Location Radius') {
                lines.add('   Asset: ' + (anomaly.Asset__r == null ? 'Unknown' : anomaly.Asset__r.Name));
                lines.add('   Scanned code: ' + (anomaly.Scanned_Code__c == null ? '' : anomaly.Scanned_Code__c));
            }
            lines.add(
                '   Salesforce location: ' +
                (anomaly.Salesforce_Location__r == null ? '' : anomaly.Salesforce_Location__r.Name)
            );
            lines.add('   Details: ' + (anomaly.Details__c == null ? '' : anomaly.Details__c));
            lines.add('');
        }
        return String.join(lines, '\n');
    }

    private static String extractSendError(Messaging.SendEmailResult result) {
        if (result == null || result.getErrors() == null || result.getErrors().isEmpty()) {
            return 'Salesforce did not accept the ERP anomaly email.';
        }
        List<String> messages = new List<String>();
        for (Messaging.SendEmailError error : result.getErrors()) {
            messages.add(error.getMessage());
        }
        return String.join(messages, '; ');
    }

    private static String truncate(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return 'Unknown email notification error.';
        }
        return value.length() <= maxLength ? value : value.substring(0, maxLength);
    }

    @TestVisible
    private interface EmailTransport {
        Messaging.SendEmailResult send(Messaging.SingleEmailMessage message);
    }

    private class PlatformEmailTransport implements EmailTransport {
        public Messaging.SendEmailResult send(Messaging.SingleEmailMessage message) {
            return Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ message })[0];
        }
    }
}
