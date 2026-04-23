import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_localizations.dart';
import 'dart:math';
import 'dart:ui';
import '../services/supabase_service.dart';

class PetrolStationPage extends StatefulWidget {
  const PetrolStationPage({Key? key}) : super(key: key);

  @override
  State<PetrolStationPage> createState() => _PetrolStationPageState();
}

class _PetrolStationPageState extends State<PetrolStationPage> {
  final TextEditingController _searchController = TextEditingController();
  GoogleMapController? mapController;
  final supabase = Supabase.instance.client;

  LatLng? _userLocation;
  final Set<Marker> _markers = {};
  bool _isLoadingLocation = true;
  bool _isLoadingStations = true;
  bool _isLoadingServiceStations = true;
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  String _searchType = ''; // 'petrol' or 'service'
  List<Map<String, dynamic>> _nearbyStations = [];
  List<Map<String, dynamic>> petrolStations = [];
  List<Map<String, dynamic>> _nearbyServiceStations = [];
  List<Map<String, dynamic>> serviceStations = [];

  @override
  void initState() {
    super.initState();
    _initializeMap();
    _startRealTimeLocationTracking();
    _fetchPetrolStations();
    _fetchServiceStations();
  }

  // Fetch petrol stations from Supabase
  Future<void> _fetchPetrolStations() async {
    try {
      print('🚀 Fetching petrol stations from Supabase...');

      final response = await supabase.from('petrol_stations').select();

      print(
        '📦 Response from Supabase: Type=${response.runtimeType}, Length=${(response as List).length}',
      );
      print('📦 Response content: $response');

      final stationList = List<Map<String, dynamic>>.from(response);

      if (stationList.isNotEmpty) {
        print('✅ Processing ${stationList.length} stations...');

        final stationsWithImages = stationList.map((station) {
          final lat =
              double.tryParse(station['latitude']?.toString() ?? '') ?? 0.0;
          final lng =
              double.tryParse(station['longitude']?.toString() ?? '') ?? 0.0;

          double distance = 0.0;
          String distanceStr = 'N/A';
          String duration = 'N/A';

          // Only calculate distance if user location is available
          if (_userLocation != null) {
            distance = _calculateDistance(
              _userLocation!.latitude,
              _userLocation!.longitude,
              lat,
              lng,
            );
            distanceStr = '${distance.toStringAsFixed(1)} km';
            duration = _calculateDuration(distance);
          }

          return {
            ...station,
            'actualDistance': distance,
            'distance': distanceStr,
            'duration': duration,
            'lat': lat,
            'lng': lng,
          };
        }).toList();

        // Sort by distance
        stationsWithImages.sort((a, b) {
          final distA = a['actualDistance'] ?? double.infinity;
          final distB = b['actualDistance'] ?? double.infinity;
          return distA.compareTo(distB);
        });

        setState(() {
          petrolStations = stationsWithImages;
          _isLoadingStations = false;
        });

        // Update nearby stations list after fetching
        _getNearbyStations();
      }
    } catch (e) {
      print('Error fetching petrol stations: $e');
    }
  }

  // Start real-time location tracking
  void _startRealTimeLocationTracking() {
    try {
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // Update every 10 meters
        ),
      ).listen((Position position) {
        if (mounted) {
          setState(() {
            _userLocation = LatLng(position.latitude, position.longitude);
            _isLoadingLocation = false;
            _addMapMarkers();
            _getNearbyStations();
            _getNearbyServiceStations();
          });

          // Animate map to new location
          if (mapController != null) {
            mapController?.animateCamera(
              CameraUpdate.newLatLng(_userLocation!),
            );
          }

          print(
            'Updated location: ${position.latitude}, ${position.longitude}',
          );
        }
      });
    } catch (e) {
      print('Error tracking location: $e');
    }
  }

  Future<void> _initializeMap() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services are disabled.');
        setState(() {
          _userLocation = const LatLng(6.9271, 80.7789);
          _isLoadingLocation = false;
          _addMapMarkers();
        });
        return;
      }

      // Request location permission
      LocationPermission permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        print('Location permissions are denied.');
        setState(() => _isLoadingLocation = false);
        return;
      }

      // Get user's current position with timeout
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      print('Got location: ${position.latitude}, ${position.longitude}');

      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
        _isLoadingLocation = false;
        _addMapMarkers();
        _getNearbyStations();
        _getNearbyServiceStations();
      });
    } catch (e) {
      print('Error getting location: $e');
      // Set a default location (Colombo, Sri Lanka)
      setState(() {
        _userLocation = const LatLng(6.9271, 80.7789);
        _isLoadingLocation = false;
        _addMapMarkers();
        _getNearbyStations();
        _getNearbyServiceStations();
      });
    }
  }

  void _addMapMarkers() {
    _markers.clear();

    // Add user location marker
    if (_userLocation != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('user_location'),
          position: _userLocation!,
          infoWindow: const InfoWindow(title: 'Your Location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    }

    // Add markers based on search results or all stations
    if (_isSearching && _searchResults.isNotEmpty) {
      // Show search results with different colors based on type
      for (int i = 0; i < _searchResults.length; i++) {
        final station = _searchResults[i];
        final lat = station['lat'] ?? station['latitude'];
        final lng = station['lng'] ?? station['longitude'];

        if (lat != null && lng != null) {
          // Petrol stations = green, Service stations = red
          final isServiceStation = _searchType == 'service';
          final markerColor = isServiceStation
              ? BitmapDescriptor.hueRed
              : BitmapDescriptor.hueGreen;

          _markers.add(
            Marker(
              markerId: MarkerId('search_result_$i'),
              position: LatLng(lat, lng),
              infoWindow: InfoWindow(
                title: station['name'] ?? 'Station',
                snippet: '${station['rating'] ?? 0} ⭐',
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(markerColor),
            ),
          );
        }
      }
    } else {
      // Show all petrol stations (green)
      for (int i = 0; i < petrolStations.length; i++) {
        final station = petrolStations[i];
        final lat = station['lat'] ?? station['latitude'];
        final lng = station['lng'] ?? station['longitude'];

        if (lat != null && lng != null) {
          _markers.add(
            Marker(
              markerId: MarkerId('petrol_$i'),
              position: LatLng(lat, lng),
              infoWindow: InfoWindow(
                title: station['name'] ?? 'Station',
                snippet: '${station['rating'] ?? 0} ⭐',
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen,
              ),
            ),
          );
        }
      }

      // Show all service stations (red)
      for (int i = 0; i < serviceStations.length; i++) {
        final station = serviceStations[i];
        final lat = station['lat'] ?? station['latitude'];
        final lng = station['lng'] ?? station['longitude'];

        if (lat != null && lng != null) {
          _markers.add(
            Marker(
              markerId: MarkerId('service_$i'),
              position: LatLng(lat, lng),
              infoWindow: InfoWindow(
                title: station['name'] ?? 'Station',
                snippet: '${station['rating'] ?? 0} ⭐',
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed,
              ),
            ),
          );
        }
      }
    }
  }

  void _searchStations(String query) {
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
        _searchType = '';
        _addMapMarkers();
      });
      return;
    }

    print('=== SEARCHING FOR: "$query" ===');

    // Search petrol stations
    var petrolResults = petrolStations.where((station) {
      final name = station['name']?.toString() ?? '';
      final city = station['city']?.toString() ?? '';
      final searchQuery = query.toLowerCase();
      return name.toLowerCase().contains(searchQuery) ||
          city.toLowerCase().contains(searchQuery);
    }).toList();

    // Search service stations
    var serviceResults = serviceStations.where((station) {
      final name = station['name']?.toString() ?? '';
      final city = station['city']?.toString() ?? '';
      final searchQuery = query.toLowerCase();
      return name.toLowerCase().contains(searchQuery) ||
          city.toLowerCase().contains(searchQuery);
    }).toList();

    print(
      'Found ${petrolResults.length} petrol stations, ${serviceResults.length} service stations',
    );

    // Determine search type based on what was found first
    var results = petrolResults.isNotEmpty ? petrolResults : serviceResults;
    String searchType = petrolResults.isNotEmpty ? 'petrol' : 'service';

    // Calculate distance for search results
    var refinedResults = <Map<String, dynamic>>[];

    for (var station in results) {
      var lat = station['latitude'] as double?;
      var lng = station['longitude'] as double?;

      if (lat == null) lat = station['lat'] as double?;
      if (lng == null) lng = station['lng'] as double?;

      if (lat != null && lng != null) {
        var refinedStation = Map<String, dynamic>.from(station);
        refinedStation['lat'] = lat;
        refinedStation['lng'] = lng;

        // Calculate distance
        if (_userLocation != null) {
          final distance = _calculateDistance(
            _userLocation!.latitude,
            _userLocation!.longitude,
            lat,
            lng,
          );
          final duration = _calculateDuration(distance);
          refinedStation['actualDistance'] = distance;
          refinedStation['distance'] = '${distance.toStringAsFixed(1)} km';
          refinedStation['duration'] = duration;
        } else {
          refinedStation['distance'] = '-- km';
          refinedStation['duration'] = '-- mins';
        }

        refinedResults.add(refinedStation);
      }
    }

    // Sort by distance if available
    if (_userLocation != null) {
      refinedResults.sort((a, b) {
        final distA = a['actualDistance'] ?? double.infinity;
        final distB = b['actualDistance'] ?? double.infinity;
        return distA.compareTo(distB);
      });
    }

    setState(() {
      _isSearching = true;
      _searchResults = refinedResults;
      _searchType = searchType;
      _addMapMarkers();
    });

    print('State updated. Search Results: ${_searchResults.length}');

    // Animate to first result if available
    if (refinedResults.isNotEmpty && mapController != null) {
      final first = refinedResults[0];
      final lat = first['lat'];
      final lng = first['lng'];

      if (lat != null && lng != null) {
        print('📍 Animating map to: $lat, $lng');
        mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(lat, lng), 15),
        );
      }
    }
  }

  // Show dialog to add new station suggestion
  void _showAddStationDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    String selectedType = 'petrol';
    LatLng? selectedLocation = _userLocation;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.suggestNewStation),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Name field
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.stationName,
                  hintText: AppLocalizations.of(context)!.stationNameHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Phone field
              TextField(
                controller: phoneController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.phoneNumber,
                  hintText: AppLocalizations.of(context)!.phoneNumberHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Type dropdown
              DropdownButtonFormField<String>(
                value: selectedType,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.type,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'petrol',
                    child: Text(AppLocalizations.of(context)!.petrolStation),
                  ),
                  DropdownMenuItem(
                    value: 'service',
                    child: Text(AppLocalizations.of(context)!.serviceCenter),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    selectedType = value;
                  }
                },
              ),
              const SizedBox(height: 12),

              // Current location display
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.locationYourCurrentPosition,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${AppLocalizations.of(context)!.latitude}${selectedLocation?.latitude.toStringAsFixed(4)}\n${AppLocalizations.of(context)!.longitude}${selectedLocation?.longitude.toStringAsFixed(4)}',
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              await _submitStationSuggestion(
                nameController.text,
                phoneController.text,
                selectedType,
                selectedLocation,
              );
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
            child: Text(
              AppLocalizations.of(context)!.submit,
              style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
            ),
          ),
        ],
      ),
    );
  }

  // Show feedback dialog with blur background
  void _showFeedbackDialog() {
    final descriptionController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Stack(
              children: [
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: Container(),
                ),
                Center(
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: 340,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(
                              context,
                            ).colorScheme.shadow.withOpacity(0.1),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Description',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: descriptionController,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Write your feedback here...',
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: isSubmitting
                                      ? null
                                      : () {
                                          Navigator.pop(context);
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: isSubmitting
                                      ? null
                                      : () async {
                                          if (descriptionController
                                              .text
                                              .isEmpty) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Please enter a description',
                                                ),
                                                backgroundColor: Colors.orange,
                                              ),
                                            );
                                            return;
                                          }
                                          setState(() => isSubmitting = true);
                                          try {
                                            // Get current authenticated user
                                            final user =
                                                supabase.auth.currentUser;
                                            if (user == null) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Please log in first',
                                                  ),
                                                  backgroundColor: Colors.red,
                                                ),
                                              );
                                              setState(
                                                () => isSubmitting = false,
                                              );
                                              return;
                                            }

                                            // Get user name from metadata
                                            final fullName =
                                                user.userMetadata?['full_name']
                                                    as String?;
                                            final firstName =
                                                fullName != null &&
                                                    fullName.isNotEmpty
                                                ? fullName.split(' ').first
                                                : (user.email
                                                          ?.split('@')
                                                          .first
                                                          .split('.')
                                                          .first ??
                                                      'User');

                                            final userEmail = user.email ?? '';
                                            final userPhoto =
                                                user.userMetadata?['picture']
                                                    as String?;
                                            final feedbackContent =
                                                descriptionController.text;

                                            // Insert feedback directly
                                            final response = await supabase
                                                .from('feedback')
                                                .insert({
                                                  'user_id': user.id,
                                                  'user_name': firstName,
                                                  'user_email': userEmail,
                                                  'user_photo': userPhoto ?? '',
                                                  'title': 'User Feedback',
                                                  'content': feedbackContent,
                                                });

                                            if (response != null) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Feedback submitted successfully!',
                                                  ),
                                                  backgroundColor: Colors.green,
                                                ),
                                              );
                                              Navigator.pop(context);
                                            } else {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Feedback submitted!',
                                                  ),
                                                  backgroundColor: Colors.green,
                                                ),
                                              );
                                              Navigator.pop(context);
                                            }
                                          } catch (e) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text('Error: $e'),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          } finally {
                                            setState(
                                              () => isSubmitting = false,
                                            );
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: isSubmitting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Submit',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Submit station suggestion to pending_stations table
  Future<void> _submitStationSuggestion(
    String name,
    String phone,
    String type,
    LatLng? location,
  ) async {
    if (name.isEmpty || location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.pleaseFillAllFields),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      print('📝 Submitting station suggestion...');

      // Save to pending_stations table
      await supabase.from('pending_stations').insert({
        'name': name,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'phone': phone,
        'city': 'Sri Lanka',
        'type': type,
        'suggested_by': 'user_${DateTime.now().millisecondsSinceEpoch}',
        'status': 'pending',
      });

      print('✅ Suggestion submitted successfully');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.suggestionSubmitted),
          duration: const Duration(seconds: 3),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );

      // Clear form controllers
      _searchController.clear();
    } catch (e) {
      print('❌ Error submitting suggestion: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.errorSubmitting(e.toString()),
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppLocalizations.of(context)!.petrolStationPage,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      color: Theme.of(
                        context,
                      ).iconTheme.color?.withOpacity(0.6),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _searchStations,
                        onSubmitted: _searchStations,
                        decoration: InputDecoration(
                          hintText: AppLocalizations.of(context)!.searchHint,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    // Search button
                    GestureDetector(
                      onTap: () {
                        _searchStations(_searchController.text);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF038124),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.arrow_forward,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Clear button
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        _searchStations('');
                      },
                      child: Icon(
                        Icons.clear,
                        color: Theme.of(
                          context,
                        ).iconTheme.color?.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Google Map
              Container(
                height: 380,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _isLoadingLocation
                      ? Center(
                          child: CircularProgressIndicator(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        )
                      : _userLocation == null
                      ? Center(
                          child: Text(
                            AppLocalizations.of(
                              context,
                            )!.unableToAccessLocation,
                          ),
                        )
                      : GoogleMap(
                          onMapCreated: (controller) {
                            mapController = controller;
                            if (_userLocation != null) {
                              controller.animateCamera(
                                CameraUpdate.newLatLngZoom(_userLocation!, 15),
                              );
                            } else {
                              controller.animateCamera(
                                CameraUpdate.newLatLngZoom(
                                  const LatLng(6.9271, 80.7789),
                                  15,
                                ),
                              );
                            }
                          },
                          initialCameraPosition: CameraPosition(
                            target:
                                _userLocation ?? const LatLng(6.9271, 80.7789),
                            zoom: 15,
                          ),
                          markers: _markers,
                          myLocationEnabled: _userLocation != null,
                          myLocationButtonEnabled: _userLocation != null,
                          zoomControlsEnabled: true,
                        ),
                ),
              ),
              const SizedBox(height: 24),

              // Search Results Section (displayed as rows)
              if (_isSearching && _searchResults.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${AppLocalizations.of(context)!.searchResults} (${_searchResults.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        _searchStations('');
                      },
                      child: Text(
                        AppLocalizations.of(context)!.cancel,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Search Results List
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final station = _searchResults[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          color: Theme.of(context).cardColor,
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            // Icon
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: _searchType == 'service'
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.errorContainer
                                    : Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  station['image'] ??
                                      (_searchType == 'service' ? '🔧' : '⛽'),
                                  style: const TextStyle(fontSize: 24),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    station['name'] ?? 'Station',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.star,
                                        size: 14,
                                        color: Colors.amber,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${station['rating'] ?? 0.0} (${station['reviews'] ?? 0})',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.secondaryContainer,
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.location_on,
                                              size: 10,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.secondary,
                                            ),
                                            const SizedBox(width: 2),
                                            Text(
                                              station['distance'] ?? '-- km',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.secondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.timer,
                                              size: 10,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                            const SizedBox(width: 2),
                                            Text(
                                              station['duration'] ?? '-- mins',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],

              // Nearby Petrol Stations / Search Results
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isLoadingStations
                        ? AppLocalizations.of(context)!.loadingStations
                        : _isSearching && _searchResults.isEmpty
                        ? AppLocalizations.of(context)!.noStationsFound
                        : '${AppLocalizations.of(context)!.nearbyPetrolStations} (${_nearbyStations.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {},
                    child: Text(
                      AppLocalizations.of(context)!.seeAll,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Loading indicator
              if (_isLoadingStations)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                )
              else
                // Petrol stations list
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _isSearching && _searchResults.isNotEmpty
                      ? _searchResults.length
                      : _nearbyStations.isNotEmpty
                      ? _nearbyStations.length
                      : petrolStations.length,
                  itemBuilder: (context, index) {
                    final station = _isSearching && _searchResults.isNotEmpty
                        ? _searchResults[index]
                        : _nearbyStations.isNotEmpty
                        ? _nearbyStations[index]
                        : petrolStations[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            color: Theme.of(context).colorScheme.surface,
                          ),
                          child: Row(
                            children: [
                              // Image
                              Container(
                                width: 120,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                ),
                                child: Center(
                                  child: Text(
                                    station['image'] ?? '⛽',
                                    style: const TextStyle(fontSize: 40),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Details
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        station['name'] ?? 'Station',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.star,
                                            color: Colors.amber,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${station['rating'] ?? 0.0} (${station['reviews'] ?? 0})',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primaryContainer,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.location_on,
                                                  size: 12,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  station['distance'] ??
                                                      '-- km',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.primary,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade200,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.timer,
                                                  size: 12,
                                                  color: Colors.grey,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  station['duration'] ??
                                                      '-- mins',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),

              const SizedBox(height: 24),

              // Service Stations Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${AppLocalizations.of(context)!.nearbyServiceStations} (${_nearbyServiceStations.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {},
                    child: Text(
                      AppLocalizations.of(context)!.seeAll,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Loading indicator for service stations
              if (_isLoadingServiceStations)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                )
              else if (_nearbyServiceStations.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Text(
                      AppLocalizations.of(context)!.noServiceStationsFound,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                // Service stations list
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _nearbyServiceStations.length,
                  itemBuilder: (context, index) {
                    final station = _nearbyServiceStations[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            color: Theme.of(context).colorScheme.surface,
                          ),
                          child: Row(
                            children: [
                              // Image
                              Container(
                                width: 120,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.secondaryContainer,
                                ),
                                child: Center(
                                  child: Text(
                                    station['image'] ?? '🔧',
                                    style: const TextStyle(fontSize: 40),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Details
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        station['name'] ?? 'Station',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.star,
                                            color: Colors.amber,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${station['rating'] ?? 0.0} (${station['reviews'] ?? 0})',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.secondaryContainer,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.location_on,
                                                  size: 12,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.secondary,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  station['distance'] ??
                                                      '-- km',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.secondary,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade200,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.timer,
                                                  size: 12,
                                                  color: Colors.grey,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  station['duration'] ??
                                                      '-- mins',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),

              const SizedBox(height: 24),

              // Trip Cost Calculate section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.tripCostCalculate,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/trip-cost'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          AppLocalizations.of(context)!.calculateTripCost,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddStationDialog,
        backgroundColor: const Color(0xFF038124),
        label: Text(
          AppLocalizations.of(context)!.suggestStation,
          style: const TextStyle(color: Colors.white),
        ),
        icon: const Icon(Icons.add, color: Colors.white),
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color:
            Theme.of(context).bottomNavigationBarTheme.backgroundColor ??
            Theme.of(context).scaffoldBackgroundColor,
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
            child: _buildNavItem(Icons.location_on, true),
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
            child: _buildNavItem(Icons.person, false),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, bool isActive) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).bottomNavigationBarTheme.unselectedItemColor
                      ?.withOpacity(0.2) ??
                  Colors.grey.shade200,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: isActive
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).bottomNavigationBarTheme.unselectedItemColor ??
                  Colors.grey,
      ),
    );
  }

  double _calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadius = 6371; // km
    final double dLat = (lat2 - lat1) * pi / 180;
    final double dLng = (lng2 - lng1) * pi / 180;
    final double a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  String _calculateDuration(double distance) {
    // Assume average speed of 50 km/h
    final double hours = distance / 50;
    final int minutes = (hours * 60).round();
    return '$minutes min';
  }

  Future<void> _fetchServiceStations() async {
    try {
      print('🚀 Fetching service stations from Supabase...');

      final response = await supabase.from('service_stations').select();

      final stationList = List<Map<String, dynamic>>.from(response);

      if (stationList.isNotEmpty) {
        print('✅ Processing ${stationList.length} service stations...');

        final stationsWithImages = stationList.map((station) {
          final lat =
              double.tryParse(station['latitude']?.toString() ?? '') ?? 0.0;
          final lng =
              double.tryParse(station['longitude']?.toString() ?? '') ?? 0.0;

          double distance = 0.0;
          String distanceStr = 'N/A';
          String duration = 'N/A';

          // Only calculate distance if user location is available
          if (_userLocation != null) {
            distance = _calculateDistance(
              _userLocation!.latitude,
              _userLocation!.longitude,
              lat,
              lng,
            );
            distanceStr = '${distance.toStringAsFixed(1)} km';
            duration = _calculateDuration(distance);
          }

          return {
            ...station,
            'actualDistance': distance,
            'distance': distanceStr,
            'duration': duration,
            'lat': lat,
            'lng': lng,
          };
        }).toList();

        // Sort by distance
        stationsWithImages.sort((a, b) {
          final distA = a['actualDistance'] ?? double.infinity;
          final distB = b['actualDistance'] ?? double.infinity;
          return distA.compareTo(distB);
        });

        setState(() {
          serviceStations = stationsWithImages;
          _isLoadingServiceStations = false;
        });

        // Update nearby service stations list after fetching
        _getNearbyServiceStations();
      }
    } catch (e) {
      print('Error fetching service stations: $e');
      setState(() {
        _isLoadingServiceStations = false;
      });
    }
  }

  void _getNearbyStations() {
    if (_userLocation == null || petrolStations.isEmpty) return;

    final nearby = petrolStations.where((station) {
      final distance = station['actualDistance'] ?? double.infinity;
      return distance <= 50; // Within 50 km
    }).toList();

    setState(() {
      _nearbyStations = nearby;
    });
  }

  void _getNearbyServiceStations() {
    if (serviceStations.isEmpty) {
      setState(() {
        _nearbyServiceStations = [];
      });
      return;
    }

    if (_userLocation == null) {
      // If location not available yet, show all service stations
      // They will be filtered once location is available
      setState(() {
        _nearbyServiceStations = serviceStations;
      });
      return;
    }

    final nearby = serviceStations.where((station) {
      final distance = station['actualDistance'] ?? double.infinity;
      return distance <= 50; // Within 50 km
    }).toList();

    setState(() {
      _nearbyServiceStations = nearby;
    });
  }
}
