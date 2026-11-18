import 'dart:io';
import 'dart:typed_data';
import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart';

/// SHA-256 of the certificate's DER SubjectPublicKeyInfo, independent of renewal.
String certificateKeyPin(Uint8List der) {
  if (der.length > 65536) throw const FormatException('Certificate too large.');
  final certificate = ASN1Parser(der).nextObject() as ASN1Sequence;
  final tbs = certificate.elements.first as ASN1Sequence;
  // X.509 v1 omits the explicit [0] version; v2/v3 include it.
  final offset = tbs.elements.first.tag == 0xa0 ? 1 : 0;
  final spki = tbs.elements[offset + 5] as ASN1Sequence;
  if (spki.elements.length != 2) {
    throw const FormatException('Invalid certificate public key.');
  }
  return sha256.convert(spki.encodedBytes).toString();
}

bool acceptsCertificate(
  X509Certificate certificate,
  String leafPin,
  String? keyPin,
) {
  try {
    final now = DateTime.now();
    if (now.isBefore(certificate.startValidity) ||
        !now.isBefore(certificate.endValidity)) {
      return false;
    }
    return sha256.convert(certificate.der).toString() == leafPin ||
        (keyPin != null && certificateKeyPin(certificate.der) == keyPin);
  } catch (_) {
    return false;
  }
}
