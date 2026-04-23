import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/enhanced_supabase_service.dart';

String getPublicMediaUrl(String mediaPath) {
  if (mediaPath.isEmpty) return '';
  if (mediaPath.startsWith('http://') || mediaPath.startsWith('https://')) {
    return mediaPath;
  }
  final normalizedPath = mediaPath.startsWith('/') ? mediaPath.substring(1) : mediaPath;
  return Supabase.instance.client.storage.from('media').getPublicUrl(normalizedPath);
}
class UserPostsPage extends StatefulWidget {
  const UserPostsPage({Key? key}) : super(key: key);

  @override
  State<UserPostsPage> createState() => _UserPostsPageState();
}

class _UserPostsPageState extends State<UserPostsPage> {
  final EnhancedSupabaseService _supabaseService = EnhancedSupabaseService();
  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserPosts();
  }

  Future<void> _loadUserPosts() async {
    try {
      setState(() => _isLoading = true);
      final userId = _supabaseService.getCurrentUserId();
      if (userId != null) {
        final posts = await _supabaseService.getUserPosts(userId);
        setState(() {
          _posts = posts;
          _isLoading = false;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading posts: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deletePost(String postId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Post'),
        content: const Text('Are you sure you want to delete this post?'),
        actions: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
          ),
          Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete', style: TextStyle(color: Colors.red)),
                      ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final success = await _supabaseService.deletePost(postId);
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Post deleted successfully')),
          );
          await _loadUserPosts();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete post')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
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
          'My Posts',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _posts.isEmpty
              ? const Center(child: Text('No posts yet'))
              : ListView.builder(
                  itemCount: _posts.length,
                  itemBuilder: (context, index) {
                    final post = _posts[index];
                    return _PostItem(
                      post: post,
                      onDelete: () => _deletePost(post['id']),
                    );
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
          _buildNavItem(Icons.person, true),
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

class _PostItem extends StatelessWidget {
  final Map<String, dynamic> post;
  final VoidCallback onDelete;

  const _PostItem({
    required this.post,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final status = post['status'] ?? 'pending';
    final statusColor = status == 'approved'
        ? Colors.green
        : status == 'rejected'
            ? Colors.red
            : Colors.orange;

    final mediaType = post['media_type'] as String? ?? 'image';
    final rawMediaPath = mediaType == 'video'
        ? (post['thumbnail_url'] as String? ?? post['media_url'] as String? ?? '')
        : (post['media_url'] as String? ?? '');
    final mediaUrl = getPublicMediaUrl(rawMediaPath);

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
          // Media preview
          if (post['media_url'] != null)
            Stack(
              children: [
                CachedNetworkImage(
                  imageUrl: mediaUrl,
                  placeholder: (context, url) => Container(
                    height: 200,
                    color: Colors.grey.shade300,
                  ),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 200,
                ),
                if (post['media_type'] == 'video')
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),

          // Post info
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Description
                if (post['description'] != null)
                  Text(
                    post['description'],
                    style: const TextStyle(fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 8),

                // Date
                Text(
                  'Posted ${_formatDate(post['created_at'])}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 12),

                // Actions
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete, size: 18),
                      label: const Text('Delete'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade50,
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ],
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
      return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Unknown';
    }
  }
}
