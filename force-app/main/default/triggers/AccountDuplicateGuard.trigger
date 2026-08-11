trigger AccountDuplicateGuard on Account (before insert, before update) {
    AccountDuplicateGuard.applyNormalizedNames(Trigger.new);
}
