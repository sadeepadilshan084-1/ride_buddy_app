import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../l10n/app_localizations.dart';
import '../services/share_service.dart';

class SharePage extends StatefulWidget {
  const SharePage({Key? key}) : super(key: key);

  @override
  State<SharePage> createState() => _SharePageState();
}

class _SharePageState extends State<SharePage> {
  bool isSharing = false;

  Future<void> _handleShare() async {
    try {
      setState(() => isSharing = true);

      // Show native share sheet with all installed sharing apps
      await ShareService.shareApp();

      _showSuccessMessage('Shared successfully!');
    } catch (e) {
      _showErrorMessage('Error sharing: $e');
    } finally {
      setState(() => isSharing = false);
    }
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showInfoMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Share ${AppLocalizations.of(context)?.appName ?? 'Ride Buddy'}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // Information Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share Ride Buddy',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      ShareService.appDescription,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(
                          context,
                        ).colorScheme.onPrimaryContainer.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Main Share Button
              Text(
                'Share Options',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),

              // Share App Button
              _buildShareButton(
                icon: Icons.share,
                title: 'Share App with Friends',
                subtitle: 'Opens your device\'s native share sheet',
                onTap: isSharing ? null : _handleShare,
                isLoading: isSharing,
              ),

              const SizedBox(height: 32),

              // Why Different Apps Section
              Text(
                'Why Do Different Phones Show Different Apps?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),

              _buildInfoCard(
                icon: Icons.phone_android,
                title: 'Installed Apps Vary',
                description:
                'Each device has different apps. Your phone might show WhatsApp, Telegram, and Messages, while another device shows different apps based on what\'s installed.',
              ),
              const SizedBox(height: 12),

              _buildInfoCard(
                icon: Icons.info_outlined,
                title: 'Android Version Matters',
                description:
                'Android 11+ enforces stricter app visibility. Older Android versions show more apps. The Target API level also affects which sharing apps are visible.',
              ),
              const SizedBox(height: 12),

              _buildInfoCard(
                icon: Icons.security,
                title: 'QUERY_ALL_PACKAGES Permission',
                description:
                'The app includes the QUERY_ALL_PACKAGES permission in AndroidManifest.xml. This allows discovering all available sharing-capable apps on Android 11+.',
              ),
              const SizedBox(height: 12),

              _buildInfoCard(
                icon: Icons.build,
                title: 'Device Customization',
                description:
                'Different manufacturers (Samsung, Xiaomi, OnePlus, etc.) pre-install different apps and customize what\'s visible in the share menu.',
              ),
              const SizedBox(height: 12),

              _buildInfoCard(
                icon: Icons.settings,
                title: 'User Settings & Controls',
                description:
                'Users can disable, hide, or freeze apps. Parental controls and app management features affect which apps appear in share dialogs.',
              ),

              const SizedBox(height: 32),

              // Play Store Information
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outlined, color: Colors.blue.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Play Store Behavior',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'When you publish on Play Store, each user will see their own unique share sheet based on their device configuration. This is intentional and provides the best experience for each user. Different phones showing different apps is NORMAL behavior.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Technical Details
              ExpansionTile(
                title: Text(
                  'Technical Details',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTechItem(
                          'Package: share_plus',
                          'Flutter plugin for native sharing',
                        ),
                        const SizedBox(height: 8),
                        _buildTechItem(
                          'Intent: ACTION_SEND',
                          'Uses Android intent system for sharing',
                        ),
                        const SizedBox(height: 8),
                        _buildTechItem(
                          'Manifest Queries',
                          'Declares SEND and SEND_MULTIPLE intents',
                        ),
                        const SizedBox(height: 8),
                        _buildTechItem(
                          'No App Selection',
                          'User chooses app from native system dialog',
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShareButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    required bool isLoading,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
          color: isLoading
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Theme.of(context).colorScheme.surface,
        ),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  icon,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
                if (isLoading)
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTechItem(String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/home'),
            child: _buildNavItem(Icons.home, false),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/petrol-station'),
            child: _buildNavItem(Icons.location_on, false),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/media'),
            child: _buildNavItem(Icons.videocam, false),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/stats'),
            child: _buildNavItem(Icons.bar_chart, false),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/profile'),
            child: _buildNavItem(Icons.person, true),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, bool isActive) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? Colors.green : Colors.grey.shade200,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: isActive ? Colors.white : Colors.grey),
    );
  }
}
