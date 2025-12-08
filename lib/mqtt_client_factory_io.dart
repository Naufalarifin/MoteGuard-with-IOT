import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

MqttClient createMqttClient() {
  final client = MqttServerClient.withPort(
    'broker.hivemq.com',
    'flutter_mobile_${DateTime.now().millisecondsSinceEpoch}',
    1883,
  );
  client.secure = false;
  return client;
}

