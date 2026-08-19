# Ulink BatteryLab

Scanner-first Flutter Android app for connecting to one uniquely identified Ulink ESP32 gateway and reading/writing calibration data over BLE or local-network REST.

## Run

Demo mode is enabled by default so the complete UI works in an emulator:

```shell
flutter run
```

Use real hardware with:

```shell
flutter run --dart-define=DEMO_MODE=false
```

The switch and connection timeout live in `lib/config/app_config.dart`.

## Temporary device contract

All replaceable firmware assumptions are centralized in `lib/config/device_contract.dart`: Code 128 labels, serial/device-ID patterns, BLE advertising-name construction, the default service UUID, the test `/status` shape, and Wi-Fi discovery mode.

QR labels may contain a plain ID such as `ULINK-GW-TEST01`. Legacy structured payloads remain supported:

```json
{"mode":"ble","deviceId":"ESP32-CAL-01","serviceUuid":"0000181a-0000-1000-8000-00805f9b34fb"}
```

```json
{"mode":"wifi","deviceId":"ESP32-CAL-01","ip":"192.168.1.42","port":80}
```

Wi-Fi discovery currently resolves `_ulink._tcp.local` with mDNS. Change `DeviceContract.kWifiDiscoveryMode` to `WifiDiscoveryMode.softAp` when firmware moves to SoftAP; the SoftAP implementation point is marked with a TODO. Manual IP connection remains available and requires the expected device ID so `/status` identity can be verified.

BLE characteristic UUIDs were not specified in the device payload. The BLE adapter therefore discovers the first readable/notifiable and first writable characteristics within the QR-provided service. A keyed read writes `{"key":"..."}` before reading the response characteristic.

Calibration history is local-only (`sqflite`). The history toolbar contains the requested Firebase sync TODO stub, with no backend implementation.
