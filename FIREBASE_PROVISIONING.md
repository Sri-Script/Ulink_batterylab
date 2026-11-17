# SI U-Link provisioning backend contract

The app uses the existing Cloud Firestore product and Firebase Auth. It does
not contain Admin SDK credentials or service-account JSON.

## Collections

`companies/{companyId}`: `name`, `systemIntegratorIds` (Firebase Auth UID
array).

`ucodes/{ucode}`: `ucode`, `assignedSiUid`, `status` (`available`,
`reserving`, `flashed`, `pending_verification`, or `recovery_required`),
`companyId`, `flashedByUid`, `flashedAt`, `reservationId`,
`reservationExpiresAt`, `verifiedAdvertisementAt`.

`provisioningEvents/{eventId}`: `ucode`, `companyId`, `siUid`, `type`,
`status`, `createdAt`. Do not store SSID, password, APN, BLE keys, tokens, or
raw BLE frames here.

## Required callable finalizer

Mobile Firestore rules cannot prove a BLE acknowledgement or advertisement was
observed. Deploy a privileged callable Cloud Function named
`finalizeUlinkProvisioning` before enabling a firmware UCode write command.
It accepts only `ucode`, `companyId`, and `reservationId`; obtains `siUid` from
the verified Auth context; then performs one Admin SDK transaction that checks:

1. the caller is an SI assigned to `companies/{companyId}`;
2. `ucodes/{ucode}` belongs to that SI and is still `reserving` with the same
   reservation ID and no company; and
3. a server-side verification attestation produced after the firmware ACK
   confirms that this U-Link advertised exactly that UCode.

Only then it changes the UCode to `flashed`, writes `companyId`,
`flashedByUid`, `flashedAt` and `verifiedAdvertisementAt` with server
timestamps, and creates the final provisioning event. The app deliberately
does not expose a client-side direct finalization path.
