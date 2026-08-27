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

  // How long a signed media URL stays valid. The bucket used to be public
  // (bypassing storage RLS entirely — anyone with a URL could open a
  // family photo without being a member), so URLs are now signed
  // per-request instead. An hour comfortably covers one feed session
  // without needing to re-sign mid-scroll, while still expiring rather
  // than being a permanent link if it ever leaks.
  static const _signedUrlTtl = Duration(hours: 1);

  // fetchPosts() can return up to 50 posts, each needing its own
  // sign-URLs request — running all 50 through Future.wait at once fired
  // ~50 simultaneous Storage requests the instant the feed loaded. This
  // caps how many posts are signed concurrently so a big feed doesn't
  // burst the network/CPU at once (this is exactly the kind of startup
  // burst already fixed for image *building* via Home's lazy SliverList —
  // this fixes the equivalent burst one layer down, in the network calls
  // that produce the URLs those images load from).
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
          final paths = row['media_paths'];
          final mediaUrls = paths is List
              ? await _signedUrlsFor(paths.whereType<String>().toList())
              : const <String>[];
          return Post.fromJson({
            ...row,
            'is_mine': row['author_id'] == _client.auth.currentUser?.id,
            'liked_by_me': row['liked_by_me'] == true,
            'media_urls': mediaUrls,
          });
        }),
      );
      posts.addAll(batchPosts);
    }
    return posts;
  }

  /// Signs every path in one batch call rather than one request per photo —
  /// createSignedUrls still enforces the same storage RLS (is_active_member())
  /// as the per-file API, just without an extra round trip per photo.
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
      // A signing failure for one post must not blank out the whole feed —
      // that post's photos just show the existing error/broken-image state.
      return const [];
    }
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
      // The home_posts row above already exists with no media — clean it
      // up rather than leaving an orphaned empty post in the feed.
      await _deletePostRowBestEffort(postId);
      throw const HomeFeedException('Sign in again before posting.');
    }

    // If any photo fails partway through (upload or the row insert), the
    // home_posts row created above would otherwise be left behind empty or
    // with only some photos attached. Track what's been uploaded so far so
    // a failure can be cleaned up instead of leaving a broken post visible
    // to the whole family.
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
        } catch (_) {
          // Best-effort — the DB row cleanup below is what actually keeps
          // the post from appearing broken; a leftover orphaned file just
          // wastes storage space.
        }
      }
      await _deletePostRowBestEffort(postId);
      if (error is PostgrestException) throw _friendlyError(error);
      rethrow;
    }
  }

  /// Used only to clean up a home_posts row created by createPost when a
  /// later step in the same call fails — must never let a cleanup failure
  /// mask the original error being thrown to the caller.
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

      final storagePaths = paths
          .whereType<Map<String, dynamic>>()
          .map((row) => row['storage_path'] as String?)
          .nonNulls
          .toList(growable: false);

      // Delete the DB row (and, via cascade, its home_post_media rows)
      // *before* removing the storage files — the reverse order used to
      // mean a failure here after storage had already been wiped left a
      // post visibly stuck in the feed pointing at permanently-missing
      // media. This way, if the row delete succeeds, the post disappears
      // from the feed immediately regardless of what happens next; if the
      // storage removal below then fails, the leftover files are just
      // wasted (harmless) space rather than user-visible breakage.
      await _client.rpc<void>(
        'delete_home_post',
        params: {'p_post_id': post.id},
      );

      if (storagePaths.isNotEmpty) {
        try {
          await _client.storage.from(bucket).remove(storagePaths);
        } on StorageException {
          // The post is already gone from the feed at this point — an
          // orphaned file is a cleanup nice-to-have, not something the
          // user needs to see an error for.
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
}

class HomeFeedException implements Exception {
  const HomeFeedException(this.message);
  final String message;
  @override
  String toString() => message;
}
