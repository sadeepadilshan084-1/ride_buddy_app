import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MediaPage extends StatefulWidget {
  const MediaPage({Key? key}) : super(key: key);

  @override
  State<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<MediaPage> {
  late Future<List<Map<String, dynamic>>> _approvedPosts;
  final SupabaseClient _client = Supabase.instance.client;

  String getPublicMediaUrl(String mediaPath) {
    if (mediaPath.isEmpty) return '';
    if (mediaPath.startsWith('http://') || mediaPath.startsWith('https://')) {
      return mediaPath;
    }
    final normalizedPath = mediaPath.startsWith('/') ? mediaPath.substring(1) : mediaPath;
    return _client.storage.from('media').getPublicUrl(normalizedPath);
  }

  @override
  void initState() {
    super.initState();
    _refreshMedia();
  }

  void _refreshMedia() {
    setState(() {
      _approvedPosts = _fetchApprovedPosts();
    });
  }

  Future<List<Map<String, dynamic>>> _fetchApprovedPosts() async {
    try {
      final response = await _client
          .from('posts')
          .select('''
            id,
            user_id,
            media_url,
            thumbnail_url,
            description,
            media_type,
            created_at,
            profiles:user_id(name)
          ''')
          .eq('status', 'approved')
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching approved posts: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Media',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).pushNamed('/media-add');
        },
        icon: const Icon(Icons.add),
        label: const Text('Upload'),
        backgroundColor: const Color(0xFF038124),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _approvedPosts,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('Error loading media'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _refreshMedia,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final posts = snapshot.data ?? [];

          if (posts.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => _refreshMedia(),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.image_not_supported,
                      size: 80,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No approved media yet',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    const Text('Upload your photos and videos!'),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refreshMedia(),
            child: ListView.builder(
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                final mediaUrl = post['media_url'] as String?;
                final description = post['description'] as String?;
                final mediaType = post['media_type'] as String;
                final userName = post['profiles']?['name'] ?? 'Anonymous';
                final createdAt = DateTime.parse(post['created_at']);
                final formattedDate = DateFormat('MMM d, y').format(createdAt);

                // Use thumbnail for video and full file for image
                final rawDisplayPath = mediaType == 'video'
                    ? (post['thumbnail_url'] as String? ?? mediaUrl)
                    : mediaUrl;
                String displayUrl = '';
                if (rawDisplayPath != null && rawDisplayPath.isNotEmpty) {
                  // If URL string already contains supabase URL path, convert to local storage path
                  String normalizedPath = rawDisplayPath;
                  if (rawDisplayPath.contains('supabase.co') && rawDisplayPath.contains('/media/')) {
                    normalizedPath = rawDisplayPath.substring(rawDisplayPath.indexOf('/media/') + 1);
                  }
                  if (normalizedPath.startsWith('media/')) {
                    normalizedPath = normalizedPath.substring(6);
                  }
                  displayUrl = getPublicMediaUrl(normalizedPath);
                }

                return Card(
                  margin: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Media preview
                      Stack(
                        children: [
                          Container(
                            width: double.infinity,
                            height: 250,
                            color: Colors.grey.shade200,
                            child: displayUrl.isEmpty
                                ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    mediaType == 'video'
                                        ? Icons.videocam
                                        : Icons.image,
                                    size: 48,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(height: 8),
                                  Text('No media URL found'),
                                ],
                              ),
                            )
                                : CachedNetworkImage(
                              imageUrl: displayUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                              errorWidget: (context, url, error) => Center(
                                child: Column(
                                  mainAxisAlignment:
                                  MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      mediaType == 'video'
                                          ? Icons.videocam
                                          : Icons.image,
                                      size: 48,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(height: 8),
                                    Text('Failed to load $mediaType'),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Check if media bucket is public',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Video icon overlay
                          if (mediaType == 'video')
                            Positioned(
                              right: 12,
                              bottom: 12,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // User info
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  child: Text(userName.substring(0, 1)),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      userName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      formattedDate,
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Description
                            if (description != null && description.isNotEmpty)
                              Text(
                                description,
                                style: const TextStyle(fontSize: 14),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
