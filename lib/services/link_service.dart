import 'package:url_launcher/url_launcher.dart';

class LinkService {
  static final LinkService instance = LinkService._();
  LinkService._();

  /// Overridable by tests to observe/stub open() without touching the real
  /// url_launcher plugin (which has no platform implementation registered
  /// under flutter_test) - same pattern as NotificationService.debugOnSchedule.
  Future<bool> Function(String url)? debugOpen;

  /// Opens [url] in an external app (browser, mail client, etc., depending
  /// on its scheme) - returns whether it succeeded, so a caller with a
  /// BuildContext (see note_body_view.dart) can tell the user a tapped link
  /// couldn't be opened (a malformed URL, or nothing installed to handle
  /// it) rather than the tap silently doing nothing.
  Future<bool> open(String url) async {
    if (debugOpen != null) return debugOpen!(url);
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
