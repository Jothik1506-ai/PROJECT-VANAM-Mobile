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

  Future<void> deletePost(Post post);

  Future<void> toggleLike(Post post);

  Future<List<PostComment>> fetchComments(Post post);

  Future<void> addComment({required Post post, required String body});
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

  @override
  Future<void> deletePost(Post post) async {}

  @override
  Future<void> toggleLike(Post post) async {}

  @override
  Future<List<PostComment>> fetchComments(Post post) async => const [];

  @override
  Future<void> addComment({required Post post, required String body}) async {}
}

class SupabaseHomeFeedRepository implements HomeFeedRepository {
  SupabaseHomeFeedRepository(this._client);

  static const maxPhotosPerPost = 20;
  static const bucket = 'family-post-media';

  final SupabaseClient _client;

  @override
  Future<List<Post>> fetchPosts() async {
    final List<dynamic> rows;
    try {
      rows = await _client.rpc<List<dynamic>>(
        'list_home_posts',
        params: {'p_limit': 50},
      );
    } on PostgrestException catch (error) {
      throw _friendlyError(error);
    }
    return rows
        .whereType<Map<String, dynamic>>()
        .map((row) {
          final paths = row['media_paths'];
          return Post.fromJson({
            ...row,
            'is_mine': row['author_id'] == _client.auth.currentUser?.id,
            'liked_by_me': row['liked_by_me'] == true,
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

    final Map<String, dynamic> post;
    try {
      post = await _client
          .from('home_posts')
          .insert({'caption': trimmedCaption})
          .select('id')
          .single();
    } on PostgrestException catch (error) {
      throw _friendlyError(error);
    }
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
      try {
        await _client.from('home_post_media').insert({
          'post_id': postId,
          'storage_bucket': bucket,
          'storage_path': path,
          'position': index,
          'media_type': 'photo',
        });
      } on PostgrestException catch (error) {
        throw _friendlyError(error);
      }
    }
  }

  @override
  Future<void> deletePost(Post post) async {
    try {
      final paths = await _client.rpc<List<dynamic>>(
        'get_home_post_delete_paths',
        params: {'p_post_id': post.id},
      );

      final storagePaths = paths
          .whereType<Map<String, dynamic>>()
          .map((row) => row['storage_path'] as String?)
          .nonNulls
          .toList(growable: false);

      if (storagePaths.isNotEmpty) {
        await _client.storage.from(bucket).remove(storagePaths);
      }

      await _client.rpc<void>(
        'delete_home_post',
        params: {'p_post_id': post.id},
      );
    } on PostgrestException catch (error) {
      throw _friendlyError(error);
    } on StorageException catch (error) {
      throw HomeFeedException(
        'Could not delete uploaded photos. Nothing was removed yet. ${error.message}',
      );
    }
  }

  @override
  Future<void> toggleLike(Post post) async {
    try {
      await _client.rpc<void>(
        'toggle_home_post_like',
        params: {'p_post_id': post.id},
      );
    } on PostgrestException catch (error) {
      throw _friendlyError(error);
    }
  }

  @override
  Future<List<PostComment>> fetchComments(Post post) async {
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'list_home_post_comments',
        params: {'p_post_id': post.id},
      );
      return rows
          .whereType<Map<String, dynamic>>()
          .map(PostComment.fromJson)
          .toList(growable: false);
    } on PostgrestException catch (error) {
      throw _friendlyError(error);
    }
  }

  @override
  Future<void> addComment({required Post post, required String body}) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw const HomeFeedException('Write a comment first.');
    }
    try {
      await _client.rpc<void>(
        'add_home_post_comment',
        params: {'p_post_id': post.id, 'p_body': trimmed},
      );
    } on PostgrestException catch (error) {
      throw _friendlyError(error);
    }
  }

  HomeFeedException _friendlyError(PostgrestException error) {
    if (error.code == 'PGRST205' || error.message.contains('home_posts')) {
      return const HomeFeedException(
        'Home posting is not set up in Supabase yet. Apply the Home feed migration, then try again.',
      );
    }
    return HomeFeedException(error.message);
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
