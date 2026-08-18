import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/post.dart';

abstract class HomeFeedRepository {
  Future<List<Post>> fetchPosts();

  Future<void> createPost({
    required String caption,
    required List<XFile> photos,
  });
}

class EmptyHomeFeedRepository implements HomeFeedRepository {
  const EmptyHomeFeedRepository();

  @override
  Future<List<Post>> fetchPosts() async => const [];

  @override
  Future<void> createPost({
    required String caption,
    required List<XFile> photos,
  }) async {
    throw const HomeFeedException('Preview mode cannot create posts.');
  }
}

class SupabaseHomeFeedRepository implements HomeFeedRepository {
  SupabaseHomeFeedRepository(this._client);

  static const maxPhotosPerPost = 20;
  static const bucket = 'family-post-media';

  final SupabaseClient _client;

  @override
  Future<List<Post>> fetchPosts() async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_home_posts',
      params: {'p_limit': 50},
    );
    return rows
        .whereType<Map<String, dynamic>>()
        .map((row) {
          final paths = row['media_paths'];
          return Post.fromJson({
            ...row,
            'media_urls': paths is List
                ? paths
                      .whereType<String>()
                      .map(
                        (path) =>
                            _client.storage.from(bucket).getPublicUrl(path),
                      )
                      .toList(growable: false)
                : const <String>[],
          });
        })
        .toList(growable: false);
  }

  @override
  Future<void> createPost({
    required String caption,
    required List<XFile> photos,
  }) async {
    final trimmedCaption = caption.trim();
    if (trimmedCaption.isEmpty && photos.isEmpty) {
      throw const HomeFeedException('Add a caption or at least one photo.');
    }
    if (photos.length > maxPhotosPerPost) {
      throw const HomeFeedException('Choose 20 photos or fewer.');
    }

    final post = await _client
        .from('home_posts')
        .insert({'caption': trimmedCaption})
        .select('id')
        .single();
    final postId = post['id'] as String;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const HomeFeedException('Sign in again before posting.');
    }

    for (var index = 0; index < photos.length; index++) {
      final photo = photos[index];
      final bytes = await photo.readAsBytes();
      final path = _pathFor(userId, postId, index, photo.name);
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
      await _client.from('home_post_media').insert({
        'post_id': postId,
        'storage_bucket': bucket,
        'storage_path': path,
        'position': index,
        'media_type': 'photo',
      });
    }
  }

  String _pathFor(String userId, String postId, int index, String name) {
    final extension = name.contains('.') ? name.split('.').last : 'jpg';
    return '$userId/$postId/${index + 1}.$extension';
  }

  String _contentTypeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}

class HomeFeedException implements Exception {
  const HomeFeedException(this.message);
  final String message;
  @override
  String toString() => message;
}
