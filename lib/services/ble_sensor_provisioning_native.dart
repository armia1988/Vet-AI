import 'dart:async';
import 'dart:convert';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_sensor_models.dart';

class VetBleSensorProvisioner {
  VetBleSensorProvisioner._();
  static final instance = VetBleSensorProvisioner._();

  final FlutterReactiveBle _ble = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  final StreamController<VetBleDevice> _scanController =
      StreamController<VetBleDevice>.broadcast();

  bool get supported => true;

  Stream<VetBleAdapterState> get adapterState => _ble.statusStream.map((status) {
        return switch (status) {
          BleStatus.ready => VetBleAdapterState.ready,
          BleStatus.poweredOff => VetBleAdapterState.off,
          BleStatus.unauthorized => VetBleAdapterState.unauthorized,
          BleStatus.unsupported => VetBleAdapterState.unavailable,
          _ => VetBleAdapterState.unknown,
        };
      }).distinct();

  Stream<VetBleDevice> scan() {
    unawaited(stopScan());
    final service = Uuid.parse(VetBleProtocol.serviceUuid);
    _scanSubscription = _ble
        .scanForDevices(withServices: const <Uuid>[], scanMode: ScanMode.lowLatency)
        .listen(
      (device) {
        final compatible = device.serviceUuids.contains(service) ||
            device.name.startsWith(VetBleProtocol.advertisedNamePrefix);
        if (!compatible) return;
        _scanController.add(VetBleDevice(
          id: device.id,
          name: device.name.trim().isEmpty ? 'Vet AI sensor' : device.name.trim(),
          rssi: device.rssi,
          compatible: true,
        ));
      },
      onError: _scanController.addError,
    );
    return _scanController.stream;
  }

  Future<void> stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  QualifiedCharacteristic _characteristic(String deviceId, String id) =>
      QualifiedCharacteristic(
        serviceId: Uuid.parse(VetBleProtocol.serviceUuid),
        characteristicId: Uuid.parse(id),
        deviceId: deviceId,
      );

  Future<T> _withConnection<T>(
    String deviceId,
    Future<T> Function() action,
  ) async {
    final completer = Completer<void>();
    Object? connectionError;
    late final StreamSubscription<ConnectionStateUpdate> sub;
    sub = _ble
        .connectToDevice(
          id: deviceId,
          connectionTimeout: const Duration(seconds: 12),
        )
        .listen(
      (update) {
        if (update.connectionState == DeviceConnectionState.connected &&
            !completer.isCompleted) {
          completer.complete();
        }
        if (update.connectionState == DeviceConnectionState.disconnected &&
            !completer.isCompleted) {
          connectionError = update.failure;
          completer.completeError(
            StateError('Bluetooth device disconnected before setup.'),
          );
        }
      },
      onError: (Object error, StackTrace stack) {
        connectionError = error;
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
    );

    try {
      await completer.future.timeout(const Duration(seconds: 14));
      return await action();
    } catch (error) {
      if (connectionError != null) {
        throw StateError('Bluetooth connection failed: $connectionError');
      }
      rethrow;
    } finally {
      await sub.cancel();
    }
  }

  Future<VetBleDeviceInfo> readDeviceInfo(String deviceId) async {
    await stopScan();
    return _withConnection(deviceId, () async {
      final bytes = await _ble.readCharacteristic(
        _characteristic(deviceId, VetBleProtocol.deviceInfoUuid),
      );
      return VetBleDeviceInfo.fromBytes(bytes);
    });
  }

  Future<VetBleProvisionStatus> provision({
    required String deviceId,
    required VetBleCloudConfig config,
    required void Function(VetBleProvisionStatus status) onStatus,
  }) async {
    await stopScan();
    return _withConnection(deviceId, () async {
      final statusCharacteristic =
          _characteristic(deviceId, VetBleProtocol.statusUuid);
      final configCharacteristic =
          _characteristic(deviceId, VetBleProtocol.configUuid);
      final done = Completer<VetBleProvisionStatus>();

      final statusSub = _ble.subscribeToCharacteristic(statusCharacteristic).listen(
        (bytes) {
          try {
            final status = VetBleProvisionStatus.fromBytes(bytes);
            onStatus(status);
            if (status.success && !done.isCompleted) done.complete(status);
            if (status.code == 'error' && !done.isCompleted) {
              done.completeError(StateError(
                status.message.isEmpty ? 'Sensor setup failed.' : status.message,
              ));
            }
          } catch (_) {}
        },
        onError: (Object error, StackTrace stack) {
          if (!done.isCompleted) done.completeError(error, stack);
        },
      );

      try {
        final payload = utf8.encode(jsonEncode(config.toJson()));
        // Vet AI firmware accepts framed UTF-8 JSON chunks. Keeping chunks well
        // below the common negotiated BLE MTU makes onboarding reliable across
        // iOS and inexpensive sensor controllers.
        const maxChunk = 140;
        final total = (payload.length / maxChunk).ceil();
        for (var i = 0; i < total; i++) {
          final start = i * maxChunk;
          final end = (start + maxChunk).clamp(0, payload.length);
          final frame = utf8.encode(jsonEncode({
            'seq': i,
            'total': total,
            'data': base64Encode(payload.sublist(start, end)),
          }));
          await _ble.writeCharacteristicWithResponse(
            configCharacteristic,
            value: frame,
          );
        }
        final initial = VetBleProvisionStatus(code: 'config_sent');
        onStatus(initial);
        return await done.future.timeout(
          const Duration(seconds: 45),
          onTimeout: () => throw TimeoutException(
            'Sensor received setup but did not confirm internet connection.',
          ),
        );
      } finally {
        await statusSub.cancel();
      }
    });
  }
}
