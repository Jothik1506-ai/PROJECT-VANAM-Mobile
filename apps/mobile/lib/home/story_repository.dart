import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/story.dart';

abstract class StoryRepository {
  Future<List<StoryGroup>> fetchActiveStoryGroups();

  Future<void> postStory(XFile photo);

  Future<void> markViewed(String storyId);

  Future<void> deleteOwnStory(String storyId);
}

class EmptyStoryRepository implements StoryRepository {
  const EmptyStoryRepository();

  @override
  Future<List<StoryGroup>> fetchActiveStoryGroups() async => const [];

  @override
  Future<void> postStory(XFile photo) async {
    throw const StoryException('Preview mode cannot post a story.');
  }

  @override
  Future<void> markViewed(String storyId) async {}

  @override
  Future<void> deleteOwnStory(String storyId) async {}
}

class SupabaseStoryRepository implements StoryRepository {
  SupabaseStoryRepository(this._client);

  static const bucket = 'family-story-media';
  static const _signedUrlTtl = Duration(hours: 25); // outlives the 24h story

  final SupabaseClient _client;

  @override
  Future<List<StoryGroup>> fetchActiveStoryGroups() async {
    final List<dynamic> rows;
    try {
      rows = await _client.rpc<List<dynamic>>('list_active_stories');
    } on PostgrestException catch (error) {
      throw _friendlyError(error);
    }

    final stories = <Story>[];
    for (final row in rows.whereType<Map<String, dynamic>>()) {
      final path = row['storage_path'] as String?;
      if (path == null) continue;
      final url = await _signedUrlFor(path);
      if (url == null) continue;
      stories.add(Story.fromJson({...row, 'media_url': url}));
    }
    return StoryGroup.group(stories);
  }

  Future<String?> _signedUrlFor(String path) async {
    try {
      return await _client.storage
          .from(bucket)
          .createSignedUrl(path, _signedUrlTtl.inSeconds);
    } on StorageException {
      return null;
    }
  }

  @override
  Future<void> postStory(XFile photo) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const StoryException('Sign in again before posting a story.');
    }

    final bytes = await photo.readAsBytes();
    final path = _pathFor(userId, photo.name);
    try {
      await _client.storage
          .from(bucket)
          .uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: FileOptions(
              contentType: _contentTypeFor(photo.name),
              upsert: false,
            ),
          );
      await _client.rpc('create_story', params: {'p_storage_path': path});
    } on PostgrestException catch (error) {
      // The upload succeeded but the DB row failed — clean up the orphaned
      // file rather than leaving it with nothing pointing at it (same
      // failure-cleanup pattern as HomeFeedRepository.createPost).
      await _removeBestEffort([path]);
      throw _friendlyError(error);
    } on StorageException catch (error) {
      throw StoryException('Could not upload photo. ${error.message}');
    }
  }

  @override
  Future<void> markViewed(String storyId) async {
    try {
      await _client.rpc('mark_story_viewed', params: {'p_story_id': storyId});
    } catch (_) {
      // Viewed-state is a nice-to-have (drives the seen/unseen ring) —
      // never worth surfacing an error for.
    }
  }

  @override
  Future<void> deleteOwnStory(String storyId) async {
    try {
      final path = await _client.rpc<String?>(
        'get_own_story_storage_path',
        params: {'p_story_id': storyId},
      );
      await _client.rpc('delete_own_story', params: {'p_story_id': storyId});
      if (path != null) {
        await _removeBestEffort([path]);
      }
    } on PostgrestException catch (error) {
      throw _friendlyError(error);
    }
  }

  Future<void> _removeBestEffort(List<String> paths) async {
    try {
      await _client.storage.from(bucket).remove(paths);
    } catch (_) {}
  }

  StoryException _friendlyError(PostgrestException error) {
    if (error.code == 'PGRST205' || error.message.contains('stories')) {
      return const StoryException(
        'Stories are not set up in Supabase yet. Apply the stories migration, then try again.',
      );
    }
    return StoryException(error.message);
  }

  String _pathFor(String userId, String name) {
    final extension = name.contains('.') ? name.split('.').last : 'jpg';
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return '$userId/$timestamp.$extension';
  }

  String _contentTypeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}

class StoryException implements Exception {
  const StoryException(this.message);
  final String message;
  @override
  String toString() => message;
}
