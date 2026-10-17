import 'dart:convert';
import 'dart:typed_data';

/// Checks the file served at `http://<clinic server>/ca.crt` before the app
/// trusts it (2026-10-17). It must be a self-signed certificate authority —
/// Caddy's local root (`tls internal`) — exactly the check the Windows
/// client makes (`Subject == Issuer` and basic constraints `CA:TRUE`).
///
/// dart:io can't parse a certificate on its own (an `X509Certificate` only
/// comes from a TLS connection) and no ASN.1 package is in pubspec, so this
/// reads the few DER fields it needs itself.
class CaCertificate {
  CaCertificate._(this.der);

  /// The certificate, DER-encoded.
  final Uint8List der;

  /// The same certificate as PEM, the form `SecurityContext` loads.
  String get pem {
    final b64 = base64.encode(der);
    final lines = <String>[];
    for (var i = 0; i < b64.length; i += 64) {
      lines.add(b64.substring(i, i + 64 > b64.length ? b64.length : i + 64));
    }
    return '-----BEGIN CERTIFICATE-----\n${lines.join('\n')}\n-----END CERTIFICATE-----\n';
  }

  /// Parses [body] (PEM or DER) and accepts it only if it's a self-signed
  /// CA certificate. Throws [FormatException] otherwise.
  static CaCertificate parse(List<int> body) {
    final der = _toDer(body);
    final cert = _Der(der);
    final certSeq = cert.read(0);
    if (certSeq.tag != 0x30) throw const FormatException('not a certificate');
    final tbs = cert.read(certSeq.contentStart);
    if (tbs.tag != 0x30) throw const FormatException('not a certificate');

    // tbsCertificate: [0] version?, serial, signature, issuer, validity,
    // subject, subjectPublicKeyInfo, [1]?, [2]?, [3] extensions?
    final fields = cert.children(tbs);
    var i = 0;
    if (fields.isNotEmpty && fields[0].tag == 0xA0) i++;
    if (fields.length < i + 6) throw const FormatException('not a certificate');
    final issuer = fields[i + 2];
    final subject = fields[i + 4];
    if (issuer.tag != 0x30 || subject.tag != 0x30) throw const FormatException('not a certificate');

    final selfSigned = _sameBytes(cert.bytesOf(issuer), cert.bytesOf(subject));
    var isCa = false;
    for (final f in fields.skip(i + 6)) {
      if (f.tag != 0xA3) continue;
      final extensions = cert.read(f.contentStart);
      for (final ext in cert.children(extensions)) {
        final parts = cert.children(ext);
        if (parts.isEmpty || parts.first.tag != 0x06) continue;
        if (!_sameBytes(cert.contentOf(parts.first), _basicConstraintsOid)) continue;
        final value = parts.last;
        if (value.tag != 0x04) continue;
        final bc = cert.read(value.contentStart);
        if (bc.tag != 0x30) continue;
        final bcFields = cert.children(bc);
        if (bcFields.isNotEmpty && bcFields.first.tag == 0x01) {
          final v = cert.contentOf(bcFields.first);
          isCa = v.isNotEmpty && v.first != 0;
        }
      }
    }
    if (!selfSigned || !isCa) throw const FormatException('not a root certificate');
    return CaCertificate._(der);
  }

  /// 2.5.29.19
  static const _basicConstraintsOid = [0x55, 0x1D, 0x13];

  static Uint8List _toDer(List<int> body) {
    final bytes = Uint8List.fromList(body);
    if (bytes.isNotEmpty && bytes.first == 0x30) return bytes;
    final text = latin1.decode(bytes, allowInvalid: true);
    final m = RegExp(r'-----BEGIN CERTIFICATE-----([A-Za-z0-9+/=\s]+)-----END CERTIFICATE-----').firstMatch(text);
    if (m == null) throw const FormatException('not a certificate');
    try {
      return base64.decode(m.group(1)!.replaceAll(RegExp(r'\s'), ''));
    } catch (_) {
      throw const FormatException('not a certificate');
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _Tlv {
  const _Tlv(this.tag, this.start, this.contentStart, this.end);
  final int tag;
  final int start;
  final int contentStart;
  final int end;
}

/// Minimal DER reader: tag-length-value with definite lengths only (DER
/// never uses indefinite ones). Every read is bounds-checked.
class _Der {
  _Der(this.data);
  final Uint8List data;

  _Tlv read(int offset) {
    if (offset + 2 > data.length) throw const FormatException('truncated certificate');
    final tag = data[offset];
    var pos = offset + 1;
    var len = data[pos++];
    if (len & 0x80 != 0) {
      final n = len & 0x7F;
      if (n == 0 || n > 4 || pos + n > data.length) throw const FormatException('bad certificate length');
      len = 0;
      for (var k = 0; k < n; k++) {
        len = (len << 8) | data[pos++];
      }
    }
    final end = pos + len;
    if (end > data.length) throw const FormatException('truncated certificate');
    return _Tlv(tag, offset, pos, end);
  }

  List<_Tlv> children(_Tlv parent) {
    final out = <_Tlv>[];
    var pos = parent.contentStart;
    while (pos < parent.end) {
      final c = read(pos);
      if (c.end > parent.end) throw const FormatException('bad certificate structure');
      out.add(c);
      pos = c.end;
    }
    return out;
  }

  Uint8List bytesOf(_Tlv t) => Uint8List.sublistView(data, t.start, t.end);
  Uint8List contentOf(_Tlv t) => Uint8List.sublistView(data, t.contentStart, t.end);
}
