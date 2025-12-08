import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';

MqttClient createMqttClient() {
  final client = MqttBrowserClient(
    'wss://broker.hivemq.com:8884/mqtt',
    'flutter_web_${DateTime.now().millisecondsSinceEpoch}',
  );
  return client;
}

