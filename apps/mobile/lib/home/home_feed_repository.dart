import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/post.dart';

abstract class HomeFeedRepository {
  Future<List<Post>> fetchPosts();

  Future<void> createPost({
    required String caption,
    List<XFile> photos = const [],
    XFile? video,
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
    List<XFile> photos = const [],
    XFile? video,
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
  static const videoBucket = 'family-video-media';

  final SupabaseClient _client;

  // How long a signed media URL stays valid.
  static const _signedUrlTtl = Duration(hours: 1);

  // Caps how many posts are signed concurrently so a big feed doesn't burst
  // the network/CPU at once.
  static const _signingConcurrency = 6;

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

    final postRows = rows.whereType<Map<String, dynamic>>().toList();
    final posts = <Post>[];
    for (var start = 0; start < postRows.length; start += _signingConcurrency) {
      final batch = postRows.skip(start).take(_signingConcurrency);
      final batchPosts = await Future.wait(
        batch.map((row) async {
          final rawItems = row['media_items'];
          final paths = row['media_paths'];

          List<PostMediaItem> mediaItems;
          List<String> mediaUrls;

          if (rawItems is List && rawItems.isNotEmpty) {
            mediaItems = await _signedMediaItemsFor(rawItems);
            mediaUrls = mediaItems.map((m) => m.url).toList(growable: false);
          } else if (paths is List && paths.isNotEmpty) {
            mediaUrls = await _signedUrlsFor(paths.whereType<String>().toList());
            mediaItems = mediaUrls
                .map((u) => PostMediaItem(url: u, type: PostMediaType.photo))
                .toList(growable: false);
          } else {
            mediaUrls = const [];
            mediaItems = const [];
          }

          return Post.fromJson({
            ...row,
            'is_mine': row['author_id'] == _client.auth.currentUser?.id,
            'liked_by_me': row['liked_by_me'] == true,
            'media_urls': mediaUrls,
            'media_items': mediaItems
                .map((m) => {
                      'url': m.url,
                      'media_type': m.type.name,
                      'duration_seconds': m.durationSeconds,
                      'thumbnail_url': m.thumbnailUrl,
                    })
                .toList(),
          });
        }),
      );
      posts.addAll(batchPosts);
    }
    return posts;
  }

  /// Signs structured media items by their specific storage bucket
  /// ('family-post-media' or 'family-video-media').
  Future<List<PostMediaItem>> _signedMediaItemsFor(List<dynamic> rawItems) async {
    if (rawItems.isEmpty) return const [];
    final bucketToIndicesAndPaths = <String, List<MapEntry<int, String>>>{};
    for (var i = 0; i < rawItems.length; i++) {
      final item = rawItems[i];
      if (item is Map<String, dynamic>) {
        final b = item['storage_bucket'] as String? ?? bucket;
        final p = item['storage_path'] as String?;
        if (p != null && p.isNotEmpty) {
          bucketToIndicesAndPaths.putIfAbsent(b, () => []).add(MapEntry(i, p));
        }
      }
    }

    final signedUrlMap = <int, String>{};
    for (final entry in bucketToIndicesAndPaths.entries) {
      final bucketName = entry.key;
      final pairs = entry.value;
      final paths = pairs.map((p) => p.value).toList();
      try {
        final results = await _client.storage
            .from(bucketName)
            .createSignedUrlsResult(paths, _signedUrlTtl.inSeconds);
        var idx = 0;
        for (final res in results) {
          if (res is SignedUrlSuccess && idx < pairs.length) {
            signedUrlMap[pairs[idx].key] = res.signedUrl;
          }
          idx++;
        }
      } on StorageException {
        // A signing failure for one post's media item must not blank out the feed.
      }
    }

    final items = <PostMediaItem>[];
    for (var i = 0; i < rawItems.length; i++) {
      final item = rawItems[i];
      if (item is Map<String, dynamic>) {
        final url = signedUrlMap[i] ?? '';
        if (url.isNotEmpty) {
          items.add(
            PostMediaItem(
              url: url,
              type: PostMediaType.fromString(item['media_type'] as String?),
              durationSeconds: item['duration_seconds'] as int?,
            ),
          );
        }
      }
    }
    return items;
  }

  /// Legacy photo batch signer.
  Future<List<String>> _signedUrlsFor(List<String> paths) async {
    if (paths.isEmpty) return const [];
    try {
      final results = await _client.storage
          .from(bucket)
          .createSignedUrlsResult(paths, _signedUrlTtl.inSeconds);
      return results
          .whereType<SignedUrlSuccess>()
          .map((r) => r.signedUrl)
          .toList(growable: false);
    } on StorageException {
      return const [];
    }
  }

  @override
  Future<void> createPost({
    required String caption,
    List<XFile> photos = const [],
    XFile? video,
  }) async {
    final trimmedCaption = caption.trim();
    if (trimmedCaption.isEmpty && photos.isEmpty && video == null) {
      throw const HomeFeedException('Add a caption, photos, or a video.');
    }
    if (photos.isNotEmpty && video != null) {
      throw const HomeFeedException('Choose photos or a video, not both.');
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
      await _deletePostRowBestEffort(postId);
      throw const HomeFeedException('Sign in again before posting.');
    }

    // Video upload flow
    if (video != null) {
      final uploadedVideoPaths = <String>[];
      try {
        final bytes = await video.readAsBytes();
        final path = _videoPathFor(userId, postId, video.name);
        await _client.storage
            .from(videoBucket)
            .uploadBinary(
              path,
              Uint8List.fromList(bytes),
              fileOptions: FileOptions(
                contentType: _videoContentTypeFor(video.name),
                upsert: false,
              ),
            );
        uploadedVideoPaths.add(path);
        await _client.from('home_post_media').insert({
          'post_id': postId,
          'storage_bucket': videoBucket,
          'storage_path': path,
          'position': 0,
          'media_type': 'video',
        });
        return;
      } catch (error) {
        if (uploadedVideoPaths.isNotEmpty) {
          try {
            await _client.storage.from(videoBucket).remove(uploadedVideoPaths);
          } catch (_) {}
        }
        await _deletePostRowBestEffort(postId);
        if (error is PostgrestException) throw _friendlyError(error);
        rethrow;
      }
    }

    // Photo upload flow
    final uploadedPaths = <String>[];
    try {
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
        uploadedPaths.add(path);
        await _client.from('home_post_media').insert({
          'post_id': postId,
          'storage_bucket': bucket,
          'storage_path': path,
          'position': index,
          'media_type': 'photo',
        });
      }
    } catch (error) {
      if (uploadedPaths.isNotEmpty) {
        try {
          await _client.storage.from(bucket).remove(uploadedPaths);
        } catch (_) {}
      }
      await _deletePostRowBestEffort(postId);
      if (error is PostgrestException) throw _friendlyError(error);
      rethrow;
    }
  }

  /// Used only to clean up a home_posts row created by createPost when a
  /// later step in the same call fails.
  Future<void> _deletePostRowBestEffort(String postId) async {
    try {
      await _client.rpc<void>('delete_home_post', params: {'p_post_id': postId});
    } catch (_) {}
  }

  @override
  Future<void> deletePost(Post post) async {
    try {
      final paths = await _client.rpc<List<dynamic>>(
        'get_home_post_delete_paths',
        params: {'p_post_id': post.id},
      );

      final bucketToPaths = <String, List<String>>{};
      for (final row in paths) {
        if (row is Map<String, dynamic>) {
          final b = row['storage_bucket'] as String? ?? bucket;
          final p = row['storage_path'] as String?;
          if (p != null && p.isNotEmpty) {
            bucketToPaths.putIfAbsent(b, () => []).add(p);
          }
        }
      }

      await _client.rpc<void>(
        'delete_home_post',
        params: {'p_post_id': post.id},
      );

      for (final entry in bucketToPaths.entries) {
        try {
          await _client.storage.from(entry.key).remove(entry.value);
        } on StorageException {
          // Best-effort storage cleanup after DB row was deleted.
        }
      }
    } on PostgrestException catch (error) {
      throw _friendlyError(error);
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

  String _videoPathFor(String userId, String postId, String name) {
    final extension = name.contains('.') ? name.split('.').last.toLowerCase() : 'mp4';
    return '$userId/$postId/video_${DateTime.now().millisecondsSinceEpoch}.$extension';
  }

  String _videoContentTypeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.3gp')) return 'video/3gpp';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    return 'video/mp4';
  }
}

class HomeFeedException implements Exception {
  const HomeFeedException(this.message);
  final String message;
  @override
  String toString() => message;
}
