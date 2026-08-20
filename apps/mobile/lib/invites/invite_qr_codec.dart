/// Encodes/decodes the username + password pair carried in the QR code
/// shown on the admin's "member created" sheet and read back by the Login
/// screen's scanner. Kept as pure functions (no widgets, no camera) so both
/// sides — and a plain unit test — can agree on the exact same format.
///
/// Format: `VANAM2:<username>:<password>` — a short version prefix so a
/// future format change can be told apart from today's QR codes instead of
/// being silently misparsed. (`VANAM1` was the old invite-code+PIN format,
/// retired with the move to username/password accounts.)
class InviteQrCodec {
  const InviteQrCodec._();

  static const _prefix = 'VANAM2';

  static String encode({required String username, required String password}) {
    return '$_prefix:$username:$password';
  }

  /// Returns null for anything that isn't a `VANAM2:username:password`
  /// payload — e.g. a random QR code scanned by mistake. Never throws.
  static (String username, String password)? decode(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length != 3 || parts[0] != _prefix) return null;
    final username = parts[1].trim();
    final password = parts[2].trim();
    if (username.isEmpty || password.isEmpty) return null;
    return (username, password);
  }
}
