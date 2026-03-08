/// Matter PASE Spake2+ 구현
/// matter.js Spake2p.js 포팅 (순수 Dart, pointycastle 사용)
library;

import 'dart:convert' show utf8;
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// P-256 상수
final _curve = ECCurve_secp256r1();
final _n = _curve.n;
final _G = _curve.G;

/// Matter Spake2+ M, N 포인트 (compressed hex)
final _M = _curve.curve.decodePoint(
  _hexToBytes('02886e2f97ace46e55ba9dd7242579f2993b64e16ef3dcab95afd497333d8fa12f'),
)!;
final _N = _curve.curve.decodePoint(
  _hexToBytes('03d8bbd6c639c62937b04d997f38c3770719c629d7014d49a24b4f98baa1292b49'),
)!;

const int _cryptoWSize = 40; // CRYPTO_GROUP_SIZE_BYTES + 8

/// PBKDF2로 w0, w1 계산
Future<({BigInt w0, BigInt w1})> computeW0W1({
  required int iterations,
  required Uint8List salt,
  required int pin,
}) async {
  // pin을 uint32 LE로 직렬화
  final pinBytes = Uint8List(4);
  final bd = ByteData.sublistView(pinBytes);
  bd.setUint32(0, pin, Endian.little);

  // PBKDF2-HMAC-SHA256
  final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, iterations, _cryptoWSize * 2));
  final ws = pbkdf2.process(pinBytes);

  final w0 = _bytesToBigInt(ws.sublist(0, 40)) % _n;
  final w1 = _bytesToBigInt(ws.sublist(40, 80)) % _n;
  return (w0: w0, w1: w1);
}

/// Spake2+ 클라이언트 (initiator/prover)
class Spake2pClient {
  final Uint8List _context;
  final BigInt _random;
  final BigInt _w0;

  Spake2pClient._(this._context, this._random, this._w0);

  factory Spake2pClient.create(Uint8List context, BigInt w0) {
    final rng = FortunaRandom();
    rng.seed(KeyParameter(_secureRandomBytes(32)));
    final random = _randomBigInt(rng, _n);
    return Spake2pClient._(context, random, w0);
  }

  /// X = G*random + M*w0
  Uint8List computeX() {
    final x = (_G * _random)! + (_M * _w0)!;
    return Uint8List.fromList(x!.getEncoded(false));
  }

  /// Y(서버에서 받은 것)로부터 secret + verifier 계산
  Future<({Uint8List ke, Uint8List hAY, Uint8List hBX})> computeSecretAndVerifiersFromY(
    BigInt w1,
    Uint8List X,
    Uint8List Y,
  ) async {
    final yPoint = _curve.curve.decodePoint(Y)!;
    // Z = (Y - N*w0) * random
    final yMinusNw0 = yPoint + (-(_N * _w0)!);
    final z = yMinusNw0! * _random;
    // V = (Y - N*w0) * w1
    final v = yMinusNw0 * w1;

    return _computeSecretAndVerifiers(
      X, Y,
      Uint8List.fromList(z!.getEncoded(false)),
      Uint8List.fromList(v!.getEncoded(false)),
    );
  }

  Future<({Uint8List ke, Uint8List hAY, Uint8List hBX})> _computeSecretAndVerifiers(
    Uint8List X,
    Uint8List Y,
    Uint8List Z,
    Uint8List V,
  ) async {
    // TT = context || "" || "" || M || N || X || Y || Z || V || w0
    final tt = BytesBuilder();
    _addToTT(tt, _context);
    _addToTT(tt, Uint8List(0)); // idProver
    _addToTT(tt, Uint8List(0)); // idVerifier
    _addToTT(tt, Uint8List.fromList(_M.getEncoded(false)));
    _addToTT(tt, Uint8List.fromList(_N.getEncoded(false)));
    _addToTT(tt, X);
    _addToTT(tt, Y);
    _addToTT(tt, Z);
    _addToTT(tt, V);
    _addToTT(tt, _bigIntToBytes32(_w0));

    final ttHash = _sha256(tt.toBytes());
    final ka = ttHash.sublist(0, 16);
    final ke = Uint8List.fromList(ttHash.sublist(16, 32));

    // KcAB = HKDF(Ka, "", "ConfirmationKeys", 32)
    final kcAB = _hkdf(ka, Uint8List(0), 'ConfirmationKeys', 32);
    final kcA = kcAB.sublist(0, 16);
    final kcB = kcAB.sublist(16, 32);

    // hAY = HMAC(KcA, Y), hBX = HMAC(KcB, X)
    final hAY = _hmacSha256(kcA, Y);
    final hBX = _hmacSha256(kcB, X);

    return (ke: ke, hAY: hAY, hBX: hBX);
  }

  void _addToTT(BytesBuilder tt, Uint8List data) {
    // uint64 LE length + data
    final lenBytes = Uint8List(8);
    final bd = ByteData.sublistView(lenBytes);
    bd.setUint64(0, data.length, Endian.little);
    tt.add(lenBytes);
    tt.add(data);
  }
}

// --- Crypto helpers ---

Uint8List _sha256(Uint8List data) {
  return Uint8List.fromList(SHA256Digest().process(data));
}

Uint8List _hmacSha256(Uint8List key, Uint8List data) {
  final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(key));
  return Uint8List.fromList(hmac.process(data));
}

Uint8List _hkdf(Uint8List ikm, Uint8List salt, String info, int length) {
  final hkdf = HKDFKeyDerivator(SHA256Digest())
    ..init(HkdfParameters(ikm, length, salt, _utf8Encode(info)));
  final out = Uint8List(length);
  hkdf.deriveKey(null, 0, out, 0);
  return out;
}

Uint8List _utf8Encode(String s) => Uint8List.fromList(utf8.encode(s));

Uint8List _hexToBytes(String hex) {
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

BigInt _bytesToBigInt(Uint8List bytes) {
  var result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b);
  }
  return result;
}

Uint8List _bigIntToBytes32(BigInt v) {
  final bytes = Uint8List(32);
  var val = v;
  for (int i = 31; i >= 0; i--) {
    bytes[i] = (val & BigInt.from(0xFF)).toInt();
    val >>= 8;
  }
  return bytes;
}

BigInt _randomBigInt(FortunaRandom rng, BigInt max) {
  final bytes = rng.nextBytes(32);
  return _bytesToBigInt(Uint8List.fromList(bytes)) % max;
}

Uint8List _secureRandomBytes(int length) {
  final rng = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
}
