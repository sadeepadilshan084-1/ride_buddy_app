import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Enhanced Supabase Service with Video Upload, Thumbnail Generation, and Admin Features
class EnhancedSupabaseService {
  static final EnhancedSupabaseService _instance = EnhancedSupabaseService._internal();

  factory EnhancedSupabaseService() {
    return _instance;
  }

  EnhancedSupabaseService._internal();

  final SupabaseClient _client = Supabase.instance.client;
  static const String _mediaBucket = 'media';
  static const String _videosPrefix = 'videos/';
  static const String _videoThumbnailsPrefix = 'video-thumbnails/';

  String? getCurrentUserId() {
    return _client.auth.currentUser?.id;
  }

  /// Convert a storage path or URL into a public access URL
  String getPublicMediaUrl(String mediaPath, {String bucket = _mediaBucket}) {
    if (mediaPath.isEmpty) {
      return '';
    }

    if (mediaPath.startsWith('http://') || mediaPath.startsWith('https://')) {
      return mediaPath;
    }

    var normalizedPath = mediaPath;

    // If full Supabase media URL is stored, extract the path part
    if (mediaPath.contains('/storage/v1/object/public/')) {
      normalizedPath = mediaPath.split('/storage/v1/object/public/').last;
    } else if (mediaPath.contains('/media/')) {
      normalizedPath = mediaPath.substring(mediaPath.indexOf('/media/') + 7);
    }

    if (normalizedPath.startsWith('/')) {
      normalizedPath = normalizedPath.substring(1);
    }

    if (normalizedPath.startsWith('media/')) {
      normalizedPath = normalizedPath.substring(6);
    }

    if (normalizedPath.startsWith(_videosPrefix) ||
        normalizedPath.startsWith(_videoThumbnailsPrefix)) {
      return _client.storage.from(_mediaBucket).getPublicUrl(normalizedPath);
    }

    return _client.storage.from(bucket).getPublicUrl(normalizedPath);
  }

  String _normalizeStoragePath(String mediaPath) {
    if (mediaPath.isEmpty) return '';

    var path = mediaPath;
    if (path.contains('/storage/v1/object/public/')) {
      path = path.split('/storage/v1/object/public/').last;
    }

    if (path.startsWith('/')) {
      path = path.substring(1);
    }

    if (path.startsWith('media/')) {
      path = path.substring(6);
    }

    return path;
  }

  /// Ensure user profile exists in the profiles table
  /// This prevents foreign key constraint violations when inserting into posts
  Future<bool> _ensureProfileExists(String userId) async {
    try {
      // Check if profile already exists
      final profile = await _client
          .from('profiles')
          .select('id')
          .eq('id', userId)
          .maybeSingle();

      if (profile != null) {
        print('✓ Profile already exists for user: $userId');
        return true;
      }

      // Profile doesn't exist, create one
      print('Creating profile for user: $userId');
      final currentUser = _client.auth.currentUser;
      final name = currentUser?.userMetadata?['name'] ?? 
                   currentUser?.email?.split('@').first ?? 
                   'User';
      final email = currentUser?.email ?? 'user@example.com';

      // Try insert first
      try {
        await _client.from('profiles').insert({
          'id': userId,
          'name': name,
        });
        print('✓ Profile created successfully');
        return true;
      } catch (insertError) {
        print('Insert failed, trying upsert: $insertError');
        // If insert fails, try upsert
        await _client.from('profiles').upsert({
          'id': userId,
          'name': name,
        });
        print('✓ Profile created via upsert');
        return true;
      }
    } catch (e) {
      print('✗ Error ensuring profile exists: $e');
      return false;
    }
  }

  // ===== VIDEO UPLOAD & MANAGEMENT =====

  /// Upload video file to Supabase Storage with metadata
  Future<Map<String, dynamic>?> uploadVideo({
    required Uint8List videoBytes,
    required String videoFileName,
    required String title,
    required String description,
    required Uint8List? thumbnailBytes,
  }) async {
    try {
      final userId = getCurrentUserId();
      if (userId == null) throw Exception('User not authenticated');

      // Generate unique filenames
      final safeFileName = videoFileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final generatedVideoFileName = 'video_${DateTime.now().millisecondsSinceEpoch}_$safeFileName';
      final thumbnailFileName = 'thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Upload video bytes inside the media bucket using a prefix for organization
      final videoPath = '$_videosPrefix$userId/$generatedVideoFileName';
      await _client.storage.from(_mediaBucket).uploadBinary(
            videoPath,
            videoBytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );

      final videoUrl = _client.storage.from(_mediaBucket).getPublicUrl(videoPath);

      // Upload thumbnail if provided
      String? thumbnailUrl;
      if (thumbnailBytes != null && thumbnailBytes.isNotEmpty) {
        final thumbnailPath = '$_videoThumbnailsPrefix$userId/$thumbnailFileName';
        await _client.storage.from(_mediaBucket).uploadBinary(
              thumbnailPath,
              thumbnailBytes,
              fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
            );
        thumbnailUrl = _client.storage.from(_mediaBucket).getPublicUrl(thumbnailPath);
      }

      // Store metadata in database
      final response = await _client.from('videos').insert({
        'user_id': userId,
        'video_url': videoUrl,
        'thumbnail_url': thumbnailUrl,
        'title': title,
        'description': description,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      }).select();

      return response.first as Map<String, dynamic>;
    } catch (e) {
      print('Error uploading video: $e');
      rethrow;
    }
  }

  /// Get all approved videos (public feed)
  Future<List<Map<String, dynamic>>> getApprovedVideos({
    int limit = 10,
    int offset = 0,
  }) async {
    try {
      final response = await _client
          .from('videos')
          .select('*, profiles:user_id(name, email)')
          .eq('status', 'approved')
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching approved videos: $e');
      return [];
    }
  }

  /// Get user's own videos (including pending and rejected)
  Future<List<Map<String, dynamic>>> getUserVideos(String userId) async {
    try {
      final response = await _client
          .from('videos')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching user videos: $e');
      return [];
    }
  }

  /// Get pending videos for admin review
  Future<List<Map<String, dynamic>>> getPendingVideosForReview() async {
    try {
      final userId = getCurrentUserId();
      if (userId == null) throw Exception('User not authenticated');

      // Check if user is admin
      final isAdmin = await isUserAdmin(userId);
      if (!isAdmin) throw Exception('User is not an admin');

      final response = await _client
          .from('videos')
          .select('*, profiles:user_id(name, email)')
          .eq('status', 'pending')
          .order('created_at', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching pending videos: $e');
      return [];
    }
  }

  /// Approve a video (admin only)
  Future<bool> approveVideo(String videoId) async {
    try {
      final userId = getCurrentUserId();
      if (userId == null) throw Exception('User not authenticated');

      final isAdmin = await isUserAdmin(userId);
      if (!isAdmin) throw Exception('User is not an admin');

      await _client.from('videos').update({
        'status': 'approved',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', videoId);

      return true;
    } catch (e) {
      print('Error approving video: $e');
      return false;
    }
  }

  /// Reject a video with reason (admin only)
  Future<bool> rejectVideo(String videoId, String rejectionReason) async {
    try {
      final userId = getCurrentUserId();
      if (userId == null) throw Exception('User not authenticated');

      final isAdmin = await isUserAdmin(userId);
      if (!isAdmin) throw Exception('User is not an admin');

      await _client.from('videos').update({
        'status': 'rejected',
        'rejection_reason': rejectionReason,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', videoId);

      return true;
    } catch (e) {
      print('Error rejecting video: $e');
      return false;
    }
  }

  /// Delete a video
  Future<bool> deleteVideo(String videoId) async {
    try {
      final userId = getCurrentUserId();
      if (userId == null) throw Exception('User not authenticated');

      // Get video details
      final videoData = await _client
          .from('videos')
          .select()
          .eq('id', videoId)
          .single();

      // Check ownership or admin status
      final isOwner = videoData['user_id'] == userId;
      final isAdmin = await isUserAdmin(userId);

      if (!isOwner && !isAdmin) {
        throw Exception('Unauthorized');
      }

      // Delete from storage using the shared media bucket
      if (videoData['video_url'] != null) {
        try {
          final videoPath = _normalizeStoragePath(videoData['video_url'] as String);
          await _client.storage.from(_mediaBucket).remove([videoPath]);
        } catch (e) {
          print('Warning: Could not delete video file: $e');
        }
      }

      if (videoData['thumbnail_url'] != null) {
        try {
          final thumbnailPath = _normalizeStoragePath(videoData['thumbnail_url'] as String);
          await _client.storage.from(_mediaBucket).remove([thumbnailPath]);
        } catch (e) {
          print('Warning: Could not delete thumbnail file: $e');
        }
      }

      // Delete from database
      await _client.from('videos').delete().eq('id', videoId);

      return true;
    } catch (e) {
      print('Error deleting video: $e');
      return false;
    }
  }

  /// Get video details by ID
  Future<Map<String, dynamic>?> getVideoDetails(String videoId) async {
    try {
      final response = await _client
          .from('videos')
          .select('*, profiles:user_id(name, email)')
          .eq('id', videoId)
          .single();

      // Increment view count
      await _client
          .from('videos')
          .update({'views_count': (response['views_count'] ?? 0) + 1}).eq('id', videoId);

      return response as Map<String, dynamic>;
    } catch (e) {
      print('Error fetching video details: $e');
      return null;
    }
  }

  // ===== VIDEO INTERACTIONS =====

  /// Like a video
  Future<bool> likeVideo(String videoId) async {
    try {
      final userId = getCurrentUserId();
      if (userId == null) throw Exception('User not authenticated');

      await _client.from('video_likes').insert({
        'video_id': videoId,
        'user_id': userId,
      });

      // Update likes count
      final currentVideo = await _client
          .from('videos')
          .select('likes_count')
          .eq('id', videoId)
          .single();

      await _client.from('videos').update({
        'likes_count': (currentVideo['likes_count'] ?? 0) + 1,
      }).eq('id', videoId);

      return true;
    } catch (e) {
      print('Error liking video: $e');
      return false;
    }
  }

  /// Unlike a video
  Future<bool> unlikeVideo(String videoId) async {
    try {
      final userId = getCurrentUserId();
      if (userId == null) throw Exception('User not authenticated');

      await _client.from('video_likes').delete().match({'video_id': videoId, 'user_id': userId});

      // Update likes count
      final currentVideo = await _client
          .from('videos')
          .select('likes_count')
          .eq('id', videoId)
          .single();

      await _client.from('videos').update({
        'likes_count': max(0, (currentVideo['likes_count'] ?? 1) - 1),
      }).eq('id', videoId);

      return true;
    } catch (e) {
      print('Error unliking video: $e');
      return false;
    }
  }

  /// Check if user liked a video
  Future<bool> hasUserLikedVideo(String videoId) async {
    try {
      final userId = getCurrentUserId();
      if (userId == null) return false;

      final response = await _client
          .from('video_likes')
          .select()
          .match({'video_id': videoId, 'user_id': userId});

      return response.isNotEmpty;
    } catch (e) {
      print('Error checking like status: $e');
      return false;
    }
  }

  /// Add comment to video
  Future<bool> addVideoComment(String videoId, String commentText) async {
    try {
      final userId = getCurrentUserId();
      if (userId == null) throw Exception('User not authenticated');

      await _client.from('video_comments').insert({
        'video_id': videoId,
        'user_id': userId,
        'comment_text': commentText,
      });

      return true;
    } catch (e) {
      print('Error adding comment: $e');
      return false;
    }
  }

  /// Get video comments
  Future<List<Map<String, dynamic>>> getVideoComments(String videoId) async {
    try {
      final response = await _client
          .from('video_comments')
          .select('*, profiles:user_id(name, email)')
          .eq('video_id', videoId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching comments: $e');
      return [];
    }
  }

  // ===== ADMIN MANAGEMENT =====

  /// Check if user is admin
  Future<bool> isUserAdmin(String userId) async {
    try {
      final response = await _client
          .from('admin_users')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      print('Error checking admin status: $e');
      return false;
    }
  }

  /// Get admin user info
  Future<Map<String, dynamic>?> getAdminUserInfo(String userId) async {
    try {
      final response = await _client
          .from('admin_users')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      return response as Map<String, dynamic>?;
    } catch (e) {
      print('Error fetching admin info: $e');
      return null;
    }
  }

  /// Get admin dashboard stats
  Future<Map<String, dynamic>?> getAdminStats() async {
    try {
      final userId = getCurrentUserId();
      if (userId == null) throw Exception('User not authenticated');

      final isAdmin = await isUserAdmin(userId);
      if (!isAdmin) throw Exception('User is not an admin');

      // Get counts
      final pendingCount = await _client
          .from('videos')
          .select('id')
          .eq('status', 'pending');

      final approvedCount = await _client
          .from('videos')
          .select('id')
          .eq('status', 'approved');

      final rejectedCount = await _client
          .from('videos')
          .select('id')
          .eq('status', 'rejected');

      final totalUsers = await _client
          .from('videos')
          .select('user_id')
          .select('DISTINCT(user_id)');

      return {
        'pending_videos': pendingCount.length,
        'approved_videos': approvedCount.length,
        'rejected_videos': rejectedCount.length,
        'total_users': totalUsers.length,
      };
    } catch (e) {
      print('Error fetching admin stats: $e');
      return null;
    }
  }

  /// Make user an admin
  Future<bool> makeUserAdmin(String userId, {String role = 'moderator'}) async {
    try {
      final currentUserId = getCurrentUserId();
      if (currentUserId == null) throw Exception('User not authenticated');

      final isAdmin = await isUserAdmin(currentUserId);
      if (!isAdmin) throw Exception('User is not an admin');

      await _client.from('admin_users').insert({
        'user_id': userId,
        'role': role,
      });

      return true;
    } catch (e) {
      print('Error making user admin: $e');
      return false;
    }
  }

  /// Remove admin access
  Future<bool> removeAdminAccess(String userId) async {
    try {
      final currentUserId = getCurrentUserId();
      if (currentUserId == null) throw Exception('User not authenticated');

      final isAdmin = await isUserAdmin(currentUserId);
      if (!isAdmin) throw Exception('User is not an admin');

      await _client.from('admin_users').delete().eq('user_id', userId);

      return true;
    } catch (e) {
      print('Error removing admin access: $e');
      return false;
    }
  }

  // ===== PHOTO UPLOAD =====

  /// Upload photo to storage
  Future<Map<String, dynamic>?> uploadPhoto({
    required Uint8List photoBytes,
    required String photoFileName,
    required String title,
    required String description,
  }) async {
    try {
      final userId = getCurrentUserId();
      if (userId == null) throw Exception('User not authenticated');

      final safeFileName = photoFileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}_$safeFileName';
      final photoPath = 'images/$userId/$fileName';

      await _client.storage.from('media').uploadBinary(
            photoPath,
            photoBytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );

      // Ensure profile exists before inserting post
      final profileExists = await _ensureProfileExists(userId);
      if (!profileExists) {
        throw Exception('Could not create user profile. Please try logging in again.');
      }

      // Store only the file path in database (not full URL)
      // Store in posts table
      final response = await _client.from('posts').insert({
        'user_id': userId,
        'media_url': photoPath,
        'thumbnail_url': photoPath,
        'description': description,
        'media_type': 'image',
        'status': 'approved',
      }).select();

      return response.first as Map<String, dynamic>;
    } catch (e) {
      print('Error uploading photo: $e');
      rethrow;
    }
  }

  // ===== POST UPLOAD =====

  /// Create text post
  /// NOTE: Text-only posts are not yet supported. The posts table requires media_url.
  /// TODO: Create a separate 'text_posts' table for text-only content
  Future<bool> createPost({
    required String title,
    required String content,
  }) async {
    try {
      print('Text-only posts are not yet supported');
      return false;
    } catch (e) {
      print('Error creating post: $e');
      return false;
    }
  }

  /// Get all media posts
  Future<List<Map<String, dynamic>>> getAllMediaPosts({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _client
          .from('posts')
          .select('*, profiles:user_id(name, email)')
          .eq('status', 'approved')
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching media posts: $e');
      return [];
    }
  }

  /// Get user's media posts
  Future<List<Map<String, dynamic>>> getUserMediaPosts(String userId) async {
    try {
      final response = await _client
          .from('posts')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching user media posts: $e');
      return [];
    }
  }

  // ===== CLEANUP & UTILITIES =====

  /// Search videos by title or description
  Future<List<Map<String, dynamic>>> searchVideos(String query) async {
    try {
      final response = await _client
          .from('videos')
          .select('*')
          .eq('status', 'approved')
          .or('title.ilike.%$query%,description.ilike.%$query%')
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error searching videos: $e');
      return [];
    }
  }

  /// Get video statistics
  Future<Map<String, dynamic>?> getVideoStats(String videoId) async {
    try {
      final response = await _client
          .from('videos')
          .select('views_count, likes_count, id')
          .eq('id', videoId)
          .single();

      final comments = await _client
          .from('video_comments')
          .select('id')
          .eq('video_id', videoId);

      return {
        ...response,
        'comments_count': comments.length,
      };
    } catch (e) {
      print('Error fetching video stats: $e');
      return null;
    }
  }

  // ===== MEDIA POSTS SYSTEM (New Schema) =====

  /// Upload image post
  Future<Map<String, dynamic>?> uploadImagePost({
    required Uint8List imageBytes,
    required String imageFileName,
    required String description,
  }) async {
    try {
      final userId = getCurrentUserId();
      if (userId == null) throw Exception('User not authenticated');

      // Generate unique filename
      final safeFileName = imageFileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_$safeFileName';
      final imagePath = 'images/$userId/$fileName';

      // Upload to storage
      await _client.storage.from('media').uploadBinary(
            imagePath,
            imageBytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );

      // Ensure profile exists before inserting post
      final profileExists = await _ensureProfileExists(userId);
      if (!profileExists) {
        throw Exception('Could not create user profile. Please try logging in again.');
      }

      // Insert into posts table
      // Store only the file path (not full URL)
      final response = await _client.from('posts').insert({
        'user_id': userId,
        'media_url': imagePath,
        'thumbnail_url': null, // No thumbnail for images
        'description': description,
        'media_type': 'image',
        'status': 'pending',
      }).select();

      return response.first as Map<String, dynamic>;
    } catch (e) {
      print('Error uploading image post: $e');
      rethrow;
    }
  }

  /// Upload video post with thumbnail
  Future<Map<String, dynamic>?> uploadVideoPost({
    required Uint8List videoBytes,
    required String videoFileName,
    required String description,
    required Uint8List thumbnailBytes,
  }) async {
    try {
      final userId = getCurrentUserId();
      if (userId == null) throw Exception('User not authenticated');

      // Generate unique filenames
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeFileName = videoFileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final generatedVideoFileName = 'video_${timestamp}_$safeFileName';
      final thumbnailFileName = 'thumb_${timestamp}.jpg';

      // Upload video to videos bucket
      final videoPath = '$_videosPrefix$userId/$generatedVideoFileName';
      await _client.storage.from(_mediaBucket).uploadBinary(
            videoPath,
            videoBytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );
      final videoUrl = _client.storage.from(_mediaBucket).getPublicUrl(videoPath);

      // Upload thumbnail inside the shared media bucket
      final thumbnailPath = '$_videoThumbnailsPrefix$userId/$thumbnailFileName';
      await _client.storage.from(_mediaBucket).uploadBinary(
            thumbnailPath,
            thumbnailBytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );
      final thumbnailUrl = _client.storage.from(_mediaBucket).getPublicUrl(thumbnailPath);

      // Ensure profile exists before inserting post
      final profileExists = await _ensureProfileExists(userId);
      if (!profileExists) {
        throw Exception('Could not create user profile. Please try logging in again.');
      }

      // Insert into posts table with video metadata
      final response = await _client.from('posts').insert({
        'user_id': userId,
        'media_url': videoUrl,
        'thumbnail_url': thumbnailUrl,
        'description': description,
        'media_type': 'video',
        'status': 'pending',
      }).select();

      return response.first as Map<String, dynamic>;
    } catch (e) {
      print('Error uploading video post: $e');
      rethrow;
    }
  }

  /// Get approved posts for feed
  Future<List<Map<String, dynamic>>> getApprovedPosts({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _client
          .from('posts')
          .select('*, profiles:user_id(name, email)')
          .eq('status', 'approved')
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching approved posts: $e');
      return [];
    }
  }

  /// Get user's own posts (including pending/rejected)
  Future<List<Map<String, dynamic>>> getUserPosts(String userId) async {
    try {
      final response = await _client
          .from('posts')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching user posts: $e');
      return [];
    }
  }

  /// Get pending posts for admin review
  Future<List<Map<String, dynamic>>> getPendingPostsForReview() async {
    try {
      final userId = getCurrentUserId();
      if (userId == null) throw Exception('User not authenticated');

      // Check if user is admin
      final profile = await _client
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .single();
      
      if (profile['role'] != 'admin') throw Exception('User is not an admin');

      final response = await _client
          .from('posts')
          .select('*, profiles:user_id(name, email)')
          .eq('status', 'pending')
          .order('created_at', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching pending posts: $e');
      return [];
    }
  }

  /// Approve a post (admin only)
  Future<bool> approvePost(String postId) async {
    try {
      final userId = getCurrentUserId();
      if (userId == null) throw Exception('User not authenticated');

      final profile = await _client
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .single();
      
      if (profile['role'] != 'admin') throw Exception('User is not an admin');

      await _client.from('posts').update({
        'status': 'approved',
      }).eq('id', postId);

      return true;
    } catch (e) {
      print('Error approving post: $e');
      return false;
    }
  }

  /// Reject a post (admin only)
  Future<bool> rejectPost(String postId) async {
    try {
      final userId = getCurrentUserId();
      if (userId == null) throw Exception('User not authenticated');

      final profile = await _client
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .single();
      
      if (profile['role'] != 'admin') throw Exception('User is not an admin');

      await _client.from('posts').update({
        'status': 'rejected',
      }).eq('id', postId);

      return true;
    } catch (e) {
      print('Error rejecting post: $e');
      return false;
    }
  }

  /// Delete a post
  Future<bool> deletePost(String postId) async {
    try {
      final userId = getCurrentUserId();
      if (userId == null) throw Exception('User not authenticated');

      // Get post details
      final postData = await _client
          .from('posts')
          .select()
          .eq('id', postId)
          .single();

      // Check ownership or admin status
      final isOwner = postData['user_id'] == userId;
      final profile = await _client
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .single();
      final isAdmin = profile['role'] == 'admin';

      if (!isOwner && !isAdmin) {
        throw Exception('Unauthorized');
      }

      // Delete from storage
      final mediaUrl = postData['media_url'];
      final thumbnailUrl = postData['thumbnail_url'];

      if (mediaUrl != null) {
        try {
          final path = _normalizeStoragePath(mediaUrl as String);
          await _client.storage.from(_mediaBucket).remove([path]);
        } catch (e) {
          print('Warning: Could not delete media file: $e');
        }
      }

      if (thumbnailUrl != null) {
        try {
          final path = _normalizeStoragePath(thumbnailUrl as String);
          await _client.storage.from(_mediaBucket).remove([path]);
        } catch (e) {
          print('Warning: Could not delete thumbnail file: $e');
        }
      }

      // Delete from database
      await _client.from('posts').delete().eq('id', postId);

      return true;
    } catch (e) {
      print('Error deleting post: $e');
      return false;
    }
  }
}

// Helper function for max operation
int max(int a, int b) => a > b ? a : b;
