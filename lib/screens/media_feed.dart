import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/enhanced_supabase_service.dart';
import 'video_player_screen.dart';

class MediaFeedPage extends StatefulWidget {
  const MediaFeedPage({Key? key}) : super(key: key);

  @override
  State<MediaFeedPage> createState() => _MediaFeedPageState();
}

class _MediaFeedPageState extends State<MediaFeedPage> {
  final EnhancedSupabaseService _supabaseService = EnhancedSupabaseService();
  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;
  int _offset = 0;
  final int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    try {
      setState(() => _isLoading = true);
      print('📹 Loading approved video posts...');
      final posts = await _supabaseService.getApprovedPosts(
        limit: _pageSize,
        offset: _offset,
      );
      print('📹 Fetched ${posts.length} posts');
      final videoPosts = posts.where((p) => p['media_type'] == 'video').toList();
      print('📹 Filtered to ${videoPosts.length} videos');
      setState(() {
        _posts.addAll(videoPosts);
        _offset += _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading posts: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading posts: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMorePosts() async {
    if (!_isLoading) {
      await _loadPosts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.green.shade400,
        elevation: 0,
        title: const Text(
          'Media Feed',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _posts.isEmpty
          ? Center(
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('No posts available'),
            )
          : ListView.builder(
              itemCount: _posts.length + 1,
              itemBuilder: (context, index) {
                if (index == _posts.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _loadMorePosts,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Load More'),
                    ),
                  );
                }

                final post = _posts[index];
                return _PostCard(post: post);
              },
            ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(Icons.home, false),
          _buildNavItem(Icons.search, false),
          _buildNavItem(Icons.add, false),
          _buildNavItem(Icons.notifications, false),
          _buildNavItem(Icons.person, false),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, bool isActive) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? Colors.green : Colors.transparent,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: isActive ? Colors.white : Colors.grey),
    );
  }
}

class _PostCard extends StatefulWidget {
  final Map<String, dynamic> post;

  const _PostCard({required this.post});

  @override
  State<_PostCard> createState() => __PostCardState();
}

class __PostCardState extends State<_PostCard> {
  final EnhancedSupabaseService _supabaseService = EnhancedSupabaseService();

  void _openVideoPlayer() {
    print('🎬 _openVideoPlayer called');
    print('🎬 Post data: ${widget.post}');
    if (widget.post['media_type'] == 'video') {
      print('✅ Navigating to VideoPlayerScreen');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(video: widget.post),
        ),
      ).then((_) {
        print('✅ Returned from VideoPlayerScreen');
      });
    } else {
      print('❌ Not a video post');
    }
  }

  Widget _buildMediaContent() {
    final mediaType = widget.post['media_type'] as String? ?? 'image';
    if (mediaType == 'image') {
      final url = widget.post['media_url'] as String? ?? '';
      return CachedNetworkImage(
        imageUrl: _supabaseService.getPublicMediaUrl(url),
        placeholder: (context, url) => Container(
          height: 300,
          color: Colors.grey.shade300,
          child: const Center(child: CircularProgressIndicator()),
        ),
        fit: BoxFit.cover,
        width: double.infinity,
      );
    }

    if (mediaType == 'video') {
      final thumbnailPath = widget.post['thumbnail_url'] as String? ?? widget.post['video_url'] as String? ?? '';
      return Stack(
        alignment: Alignment.center,
        children: [
          CachedNetworkImage(
            imageUrl: _supabaseService.getPublicMediaUrl(thumbnailPath),
            placeholder: (context, url) => Container(
              height: 200,
              color: Colors.grey.shade300,
            ),
            fit: BoxFit.cover,
            width: double.infinity,
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(16),
            child: const Icon(
              Icons.play_arrow,
              color: Colors.white,
              size: 40,
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 4)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User info
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.green,
                  child: Text(
                    (widget.post['profiles']?['name'] ?? 'U')[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.post['profiles']?['name'] ?? 'Anonymous',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        widget.post['media_type'] == 'image' ? 'Photo' : 'Video',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Media
          GestureDetector(
            onTap: () {
              print('🎬 Tapped media - type: ${widget.post['media_type']}');
              if (widget.post['media_type'] == 'video') {
                print('🎬 Opening video player for post: ${widget.post['id']}');
                _openVideoPlayer();
              } else {
                print('📷 Image post - no action');
              }
            },
            child: _buildMediaContent(),
          ),

          // Description
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.post['description'] != null)
                  Text(
                    widget.post['description'],
                    style: const TextStyle(fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 8),
                Text(
                  'Posted ${_formatDate(widget.post['created_at'])}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return 'Unknown';
    }
  }
}
