public with sharing class ServiceContractFileFromTemplateAction {
    public class Request {
        @InvocableVariable(required=true label='Service Contract Id')
        public String serviceContractId;

        @InvocableVariable(required=true label='Template Content Version Id')
        public String templateContentVersionId;

        @InvocableVariable(label='New File Title')
        public String newFileTitle;
    }

    public class Result {
        @InvocableVariable(label='Content Document Id')
        public Id contentDocumentId;

        @InvocableVariable(label='Content Version Id')
        public Id contentVersionId;
    }

    @InvocableMethod(
        label='Create Service Contract File from Template'
        description='Copies a selected template file and publishes the new file to a Service Contract.'
    )
    public static List<Result> createFiles(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return new List<Result>();
        }

        Set<Id> templateVersionIds = new Set<Id>();
        for (Request request : requests) {
            if (request == null || request.serviceContractId == null || request.templateContentVersionId == null) {
                throw new FlowException('Service Contract Id and Template Content Version Id are required.');
            }
            templateVersionIds.add((Id) request.templateContentVersionId);
        }

        Map<Id, ContentVersion> templatesById = new Map<Id, ContentVersion>([
            SELECT Id, Title, FileExtension, VersionData
            FROM ContentVersion
            WHERE Id IN :templateVersionIds
        ]);

        List<ContentVersion> filesToCreate = new List<ContentVersion>();
        for (Request request : requests) {
            ContentVersion template = templatesById.get((Id) request.templateContentVersionId);
            if (template == null) {
                throw new FlowException('The selected template file could not be found.');
            }

            String title = String.isBlank(request.newFileTitle)
                ? template.Title + ' - Service Contract'
                : request.newFileTitle.trim();

            filesToCreate.add(new ContentVersion(
                Title = title,
                PathOnClient = title + getExtensionSuffix(template.FileExtension),
                VersionData = template.VersionData,
                FirstPublishLocationId = (Id) request.serviceContractId
            ));
        }

        insert filesToCreate;

        List<Result> results = new List<Result>();
        for (ContentVersion createdFile : [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id IN :filesToCreate
            ORDER BY CreatedDate ASC
        ]) {
            Result result = new Result();
            result.contentVersionId = createdFile.Id;
            result.contentDocumentId = createdFile.ContentDocumentId;
            results.add(result);
        }
        return results;
    }

    private static String getExtensionSuffix(String fileExtension) {
        return String.isBlank(fileExtension) ? '' : '.' + fileExtension;
    }
}
