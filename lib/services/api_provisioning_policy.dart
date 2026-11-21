import '../models/ulink_api_models.dart';

/// Guards destructive API operations at the application boundary.
class ApiProvisioningPolicy {
  const ApiProvisioningPolicy._();

  static bool canProvisionDevice(ApiSession session) => session.userRole == 'CA';

  static bool freshPasswordIsValid(DateTime? authenticatedAtUtc, {DateTime? now}) {
    if (authenticatedAtUtc == null) return false;
    final current = (now ?? DateTime.now()).toUtc();
    return !current.isBefore(authenticatedAtUtc.toUtc()) &&
        current.difference(authenticatedAtUtc.toUtc()) <= const Duration(minutes: 5);
  }

  static String resetWarning(String objectName) =>
      'Resetting $objectName deletes its child device data. Enter your API password again to continue.';
}
