/// Snapshot values are intentionally categorical: they must never contain a
/// BLE address, settings, credentials, headers, tokens, or an API body.
class UlinkFlashBleDiagnostics {
  const UlinkFlashBleDiagnostics({
    this.advertisementName = 'not observed',
    this.serviceUuidMatch = 'not observed',
    this.connection = 'not attempted',
    this.discovery = 'not attempted',
    this.notifications = 'not attempted',
    this.developerOpen = 'not attempted',
    this.settingsAck = 'not attempted',
    this.setUcodeWrite = 'not sent',
    this.responseCategory = 'not observed',
    this.assignedAdvertisementVerification = 'not attempted',
  });

  final String advertisementName;
  final String serviceUuidMatch;
  final String connection;
  final String discovery;
  final String notifications;
  final String developerOpen;
  final String settingsAck;
  final String setUcodeWrite;
  final String responseCategory;
  final String assignedAdvertisementVerification;
}

class UlinkFlashApiDiagnostics {
  const UlinkFlashApiDiagnostics({
    this.assignmentHttpStatus = 'not attempted',
    this.assignmentResult = 'not attempted',
  });

  final String assignmentHttpStatus;
  final String assignmentResult;
}

abstract interface class UlinkFlashBleDiagnosticSource {
  UlinkFlashBleDiagnostics get flashDiagnostics;
}

abstract interface class UlinkFlashApiDiagnosticSource {
  UlinkFlashApiDiagnostics get flashDiagnostics;
}
