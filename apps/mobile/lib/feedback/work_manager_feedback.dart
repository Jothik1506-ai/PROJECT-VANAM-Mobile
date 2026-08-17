import 'dart:convert';
import 'dart:io';

class WorkManagerFeedback {
  const WorkManagerFeedback._();

  static const endpoint = String.fromEnvironment(
    'WORK_MANAGER_FEEDBACK_URL',
    defaultValue: 'https://aiva-work-manager-by4q.onrender.com/api/feedback',
  );

  static Future<void> send({
    required String name,
    required String feedback,
    required String screen,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(endpoint));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'source': 'vanam-mobile-app',
          'category': 'other',
          'message': [
            'Project: Project Vanam',
            'App: Mobile App',
            'Screen: $screen',
            'Name: ${name.trim()}',
            '',
            feedback.trim(),
          ].join('\n'),
          'pageUrl': 'app://vanam-mobile/${_screenSlug(screen)}',
          'platform': '${Platform.operatingSystem} ${Platform.version}',
        }),
      );

      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const HttpException('Work Manager rejected feedback.');
      }
    } finally {
      client.close(force: true);
    }
  }

  static String _screenSlug(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }
}
