import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:xml/xml.dart' as xml;

/// Logger instance for UPnPClient
final _log = Logger('UPnPClient');

/// UPnP IGD (Internet Gateway Device) client for port forwarding
///
/// Implements UPnP IGD protocol for automatic port forwarding.
/// Supports discovery, port mapping, and port deletion.
class UPnPClient {
  /// UPnP discovery multicast address
  static final InternetAddress SSDP_ADDRESS =
      InternetAddress.fromRawAddress(Uint8List.fromList([239, 255, 255, 250]));
  static const int SSDP_PORT = 1900;
  static const String SSDP_MX = '3';
  static const String SSDP_ST =
      'urn:schemas-upnp-org:device:InternetGatewayDevice:1';

  /// Discovered gateway device
  GatewayDevice? _gateway;

  /// HTTP client timeout
  final Duration timeout;

  UPnPClient({this.timeout = const Duration(seconds: 5)});

  /// Discover UPnP gateway device on the network
  ///
  /// Returns [GatewayDevice] if found, null otherwise
  Future<GatewayDevice?> discoverGateway() async {
    try {
      _log.info('Discovering UPnP gateway...');
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

      try {
        // Send M-SEARCH request
        final searchRequest = _buildMSearchRequest();
        socket.send(
          searchRequest.codeUnits,
          SSDP_ADDRESS,
          SSDP_PORT,
        );

        // Wait for response
        final completer = Completer<GatewayDevice?>();
        Timer? timeoutTimer;
        StreamSubscription<RawSocketEvent>? subscription;

        subscription = socket.listen((event) {
          if (event == RawSocketEvent.read) {
            final datagram = socket.receive();
            if (datagram == null) return;

            final response = String.fromCharCodes(datagram.data);
            if (response.contains('HTTP/1.1 200 OK')) {
              timeoutTimer?.cancel();
              subscription?.cancel();

              // Parse response to get location URL
              final location = _parseLocation(response);
              if (location != null) {
                _parseDeviceDescription(location).then((device) {
                  if (device != null && !completer.isCompleted) {
                    _gateway = device;
                    completer.complete(device);
                  }
                }).catchError((e) {
                  _log.warning('Failed to parse device description', e);
                  if (!completer.isCompleted) {
                    completer.complete(null);
                  }
                });
              } else {
                if (!completer.isCompleted) {
                  completer.complete(null);
                }
              }
            }
          }
        });

        timeoutTimer = Timer(timeout, () {
          subscription?.cancel();
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        });

        final device = await completer.future;
        if (device != null) {
          _log.info('UPnP gateway discovered: ${device.controlUrl}');
        } else {
          _log.warning('UPnP gateway not found');
        }
        return device;
      } finally {
        socket.close();
      }
    } catch (e, stackTrace) {
      _log.warning('UPnP discovery failed', e, stackTrace);
      return null;
    }
  }

  /// Build M-SEARCH request for SSDP discovery
  String _buildMSearchRequest() {
    return 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: ${SSDP_ADDRESS.address}:$SSDP_PORT\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: $SSDP_MX\r\n'
        'ST: $SSDP_ST\r\n'
        '\r\n';
  }

  /// Parse location URL from SSDP response
  Uri? _parseLocation(String response) {
    final lines = response.split('\r\n');
    for (var line in lines) {
      if (line.toUpperCase().startsWith('LOCATION:')) {
        final location = line.substring(9).trim();
        return Uri.tryParse(location);
      }
    }
    return null;
  }

  /// Parse device description XML and extract control URL
  Future<GatewayDevice?> _parseDeviceDescription(Uri location) async {
    try {
      final response = await http.get(location).timeout(timeout);
      if (response.statusCode != 200) {
        return null;
      }

      final document = xml.XmlDocument.parse(response.body);
      final root = document.rootElement;

      // Find IGD service
      String? serviceType;
      String? controlUrl;
      String? scpdUrl;

      // Search for WANIPConnection or WANPPPConnection service
      final serviceList = root.findAllElements('serviceList');
      for (var serviceListElement in serviceList) {
        final services = serviceListElement.findElements('service');
        for (var service in services) {
          final serviceTypeElement =
              service.findElements('serviceType').firstOrNull;
          if (serviceTypeElement != null) {
            final st = serviceTypeElement.innerText;
            if (st.contains('WANIPConnection') ||
                st.contains('WANPPPConnection')) {
              serviceType = st;
              controlUrl =
                  service.findElements('controlURL').firstOrNull?.innerText;
              scpdUrl = service.findElements('SCPDURL').firstOrNull?.innerText;
              break;
            }
          }
        }
        if (serviceType != null) break;
      }

      if (serviceType == null || controlUrl == null) {
        return null;
      }

      // Build control URL
      final baseUri = Uri(
        scheme: location.scheme,
        host: location.host,
        port: location.port,
      );
      final controlUri = baseUri.resolve(controlUrl);

      return GatewayDevice(
        location: location,
        controlUrl: controlUri,
        serviceType: serviceType,
        scpdUrl: scpdUrl != null ? baseUri.resolve(scpdUrl) : null,
      );
    } catch (e, stackTrace) {
      _log.warning(
          'Failed to parse device description from $location', e, stackTrace);
      return null;
    }
  }

  /// Add port mapping (forward port)
  ///
  /// [externalPort] - External port to forward
  /// [internalPort] - Internal port (usually same as external)
  /// [internalClient] - Internal IP address (usually local IP)
  /// [protocol] - 'TCP' or 'UDP'
  /// [description] - Description for the port mapping
  /// [leaseDuration] - Lease duration in seconds (0 = permanent)
  Future<bool> addPortMapping({
    required int externalPort,
    required int internalPort,
    required String internalClient,
    String protocol = 'TCP',
    String description = 'dtorrent_task_v2',
    int leaseDuration = 0,
  }) async {
    try {
      // Discover gateway if not already discovered
      if (_gateway == null) {
        _gateway = await discoverGateway();
        if (_gateway == null) {
          _log.warning('Cannot add port mapping: gateway not found');
          return false;
        }
      }

      _log.info(
          'Adding port mapping: $externalPort -> $internalClient:$internalPort ($protocol)');

      // Build SOAP request
      final soapAction =
          'urn:schemas-upnp-org:service:WANIPConnection:1#AddPortMapping';
      final soapBody = _buildAddPortMappingSoap(
        externalPort: externalPort,
        internalPort: internalPort,
        internalClient: internalClient,
        protocol: protocol,
        description: description,
        leaseDuration: leaseDuration,
      );

      final response = await http
          .post(
            _gateway!.controlUrl,
            headers: {
              'Content-Type': 'text/xml; charset="utf-8"',
              'SOAPAction': '"$soapAction"',
            },
            body: soapBody,
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        // Check for SOAP errors in response body
        try {
          final document = xml.XmlDocument.parse(response.body);
          final fault = document.findAllElements('Fault').firstOrNull;
          if (fault != null) {
            final faultCode =
                fault.findElements('faultcode').firstOrNull?.innerText;
            final faultString =
                fault.findElements('faultstring').firstOrNull?.innerText;
            final detail = fault
                .findElements('detail')
                .firstOrNull
                ?.findElements('UPnPError')
                .firstOrNull;
            final errorCode =
                detail?.findElements('errorCode').firstOrNull?.innerText;
            final errorDescription =
                detail?.findElements('errorDescription').firstOrNull?.innerText;

            _log.warning(
                'UPnP SOAP error: $faultCode/$faultString (code: $errorCode, desc: $errorDescription)');
            return false;
          }
        } catch (e) {
          // If parsing fails, assume success (some routers return non-XML)
        }
        _log.info('Port mapping added successfully');
        return true;
      } else {
        _log.warning(
            'Failed to add port mapping: HTTP ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e, stackTrace) {
      _log.warning('Error adding port mapping', e, stackTrace);
      return false;
    }
  }

  /// Build SOAP request for AddPortMapping
  String _buildAddPortMappingSoap({
    required int externalPort,
    required int internalPort,
    required String internalClient,
    required String protocol,
    required String description,
    required int leaseDuration,
  }) {
    return '''<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:AddPortMapping xmlns:u="urn:schemas-upnp-org:service:WANIPConnection:1">
      <NewRemoteHost></NewRemoteHost>
      <NewExternalPort>$externalPort</NewExternalPort>
      <NewProtocol>$protocol</NewProtocol>
      <NewInternalPort>$internalPort</NewInternalPort>
      <NewInternalClient>$internalClient</NewInternalClient>
      <NewEnabled>1</NewEnabled>
      <NewPortMappingDescription>$description</NewPortMappingDescription>
      <NewLeaseDuration>$leaseDuration</NewLeaseDuration>
    </u:AddPortMapping>
  </s:Body>
</s:Envelope>''';
  }

  /// Delete port mapping (remove port forward)
  ///
  /// [externalPort] - External port to remove
  /// [protocol] - 'TCP' or 'UDP'
  Future<bool> deletePortMapping({
    required int externalPort,
    String protocol = 'TCP',
  }) async {
    try {
      if (_gateway == null) {
        _gateway = await discoverGateway();
        if (_gateway == null) {
          _log.warning('Cannot delete port mapping: gateway not found');
          return false;
        }
      }

      _log.info('Deleting port mapping: $externalPort ($protocol)');

      final soapAction =
          'urn:schemas-upnp-org:service:WANIPConnection:1#DeletePortMapping';
      final soapBody = _buildDeletePortMappingSoap(
        externalPort: externalPort,
        protocol: protocol,
      );

      final response = await http
          .post(
            _gateway!.controlUrl,
            headers: {
              'Content-Type': 'text/xml; charset="utf-8"',
              'SOAPAction': '"$soapAction"',
            },
            body: soapBody,
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        _log.info('Port mapping deleted successfully');
        return true;
      } else {
        _log.warning(
            'Failed to delete port mapping: HTTP ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e, stackTrace) {
      _log.warning('Error deleting port mapping', e, stackTrace);
      return false;
    }
  }

  /// Build SOAP request for DeletePortMapping
  String _buildDeletePortMappingSoap({
    required int externalPort,
    required String protocol,
  }) {
    return '''<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:DeletePortMapping xmlns:u="urn:schemas-upnp-org:service:WANIPConnection:1">
      <NewRemoteHost></NewRemoteHost>
      <NewExternalPort>$externalPort</NewExternalPort>
      <NewProtocol>$protocol</NewProtocol>
    </u:DeletePortMapping>
  </s:Body>
</s:Envelope>''';
  }

  /// Get external IP address
  Future<String?> getExternalIP() async {
    try {
      if (_gateway == null) {
        _gateway = await discoverGateway();
        if (_gateway == null) {
          return null;
        }
      }

      final soapAction =
          'urn:schemas-upnp-org:service:WANIPConnection:1#GetExternalIPAddress';
      final soapBody = '''<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:GetExternalIPAddress xmlns:u="urn:schemas-upnp-org:service:WANIPConnection:1">
    </u:GetExternalIPAddress>
  </s:Body>
</s:Envelope>''';

      final response = await http
          .post(
            _gateway!.controlUrl,
            headers: {
              'Content-Type': 'text/xml; charset="utf-8"',
              'SOAPAction': '"$soapAction"',
            },
            body: soapBody,
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final document = xml.XmlDocument.parse(response.body);
        final ipElement =
            document.findAllElements('NewExternalIPAddress').firstOrNull;
        if (ipElement != null) {
          return ipElement.innerText;
        }
      }
      return null;
    } catch (e, stackTrace) {
      _log.warning('Error getting external IP', e, stackTrace);
      return null;
    }
  }
}

/// Represents a discovered UPnP gateway device
class GatewayDevice {
  /// Device description location URL
  final Uri location;

  /// Control URL for SOAP requests
  final Uri controlUrl;

  /// Service type
  final String serviceType;

  /// Service description URL (optional)
  final Uri? scpdUrl;

  GatewayDevice({
    required this.location,
    required this.controlUrl,
    required this.serviceType,
    this.scpdUrl,
  });

  @override
  String toString() {
    return 'GatewayDevice(controlUrl: $controlUrl, serviceType: $serviceType)';
  }
}
