public without sharing class AccountDuplicateGuard {
    public static void applyNormalizedNames(List<Account> accounts) {
        for (Account item : accounts) {
            item.Normalized_Account_Name__c = normalize(item.Name);
        }
    }

    @TestVisible
    static String normalize(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String normalized = value.trim().toLowerCase().replaceAll('[^a-z0-9]', '');
        return String.isBlank(normalized) ? null : normalized.left(255);
    }
}
