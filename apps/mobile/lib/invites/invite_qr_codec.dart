/// Encodes/decodes the invite code + PIN pair carried in the QR code shown
/// on the admin's invite-created sheet and read back by the Login screen's
/// scanner. Kept as pure functions (no widgets, no camera) so both sides —
/// and a plain unit test — can agree on the exact same format.
///
/// Format: `VANAM1:<code>:<pin>` — a short version prefix so a future
/// format change can be told apart from today's QR codes instead of being
/// silently misparsed.
class InviteQrCodec {
  const InviteQrCodec._();

  static const _prefix = 'VANAM1';

  static String encode({required String code, required String pin}) {
    return '$_prefix:$code:$pin';
  }

  /// Returns null for anything that isn't a `VANAM1:code:pin` payload —
  /// e.g. a random QR code scanned by mistake. Never throws.
  static (String code, String pin)? decode(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length != 3 || parts[0] != _prefix) return null;
    final code = parts[1].trim();
    final pin = parts[2].trim();
    if (code.isEmpty || pin.isEmpty) return null;
    return (code, pin);
  }
}
