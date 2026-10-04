import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../shared/providers/backend_providers.dart';
import '../../../shared/widgets/da_image.dart';
import '../../../shared/models/music_models.dart';
import '../../../../domain/entities/artist.dart' as domain;
import '../../../domain/entities/value_objects.dart';
import '../../../core/services/logger_service.dart';
import '../../taste_engine/presentation/providers/taste_engine_providers.dart';
import '../../../core/services/session_manager.dart';

class GuestOnboardingPage extends ConsumerStatefulWidget {
  const GuestOnboardingPage({super.key});

  @override
  ConsumerState<GuestOnboardingPage> createState() => _GuestOnboardingPageState();
}

class _GuestOnboardingPageState extends ConsumerState<GuestOnboardingPage> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Step 1: Username
  final TextEditingController _usernameController = TextEditingController();
  String _usernameError = '';

  // Step 2: Languages
  final Set<String> _selectedLanguages = {};
  final List<String> _languagesList = const [
    'English', 'Hindi', 'Punjabi', 'Tamil', 'Telugu', 
    'Malayalam', 'Kannada', 'Bengali', 'Marathi', 
    'Korean', 'Japanese', 'Spanish'
  ];

  // Step 3: Region
  String? _selectedRegion;
  final List<String> _regionsList = const [
    'India', 'United States', 'United Kingdom', 'Canada', 
    'Australia', 'Japan', 'South Korea'
  ];

  // Step 4: Genres
  final Set<String> _selectedGenres = {};
  final List<String> _genresList = const [
    'Pop', 'Hip-Hop', 'Punjabi', 'Rap', 'Rock', 
    'EDM', 'Lo-fi', 'Metal', 'Jazz', 'Classical', 
    'Indie', 'R&B', 'Phonk', 'Electronic', 'K-Pop', 'J-Pop'
  ];

  // Step 5: Artists
  final Set<domain.Artist> _selectedArtists = {};
  final TextEditingController _artistSearchController = TextEditingController();
  List<domain.Artist> _searchedArtists = [];
  bool _isSearchingArtists = false;
  Timer? _debounceTimer;

  // Predefined popular artist suggestions
  final List<domain.Artist> _popularArtists = [
    domain.Artist(id: 'Karan Aujla', name: 'Karan Aujla', image: Artwork(''), subscriberCount: 0, description: '', genres: const []),
    domain.Artist(id: 'Shubh', name: 'Shubh', image: Artwork(''), subscriberCount: 0, description: '', genres: const []),
    domain.Artist(id: 'Diljit Dosanjh', name: 'Diljit Dosanjh', image: Artwork(''), subscriberCount: 0, description: '', genres: const []),
    domain.Artist(id: 'Sidhu Moose Wala', name: 'Sidhu Moose Wala', image: Artwork(''), subscriberCount: 0, description: '', genres: const []),
    domain.Artist(id: 'AP Dhillon', name: 'AP Dhillon', image: Artwork(''), subscriberCount: 0, description: '', genres: const []),
    domain.Artist(id: 'Eminem', name: 'Eminem', image: Artwork(''), subscriberCount: 0, description: '', genres: const []),
    domain.Artist(id: 'Drake', name: 'Drake', image: Artwork(''), subscriberCount: 0, description: '', genres: const []),
    domain.Artist(id: 'The Weeknd', name: 'The Weeknd', image: Artwork(''), subscriberCount: 0, description: '', genres: const []),
    domain.Artist(id: 'Taylor Swift', name: 'Taylor Swift', image: Artwork(''), subscriberCount: 0, description: '', genres: const []),
    domain.Artist(id: 'Arijit Singh', name: 'Arijit Singh', image: Artwork(''), subscriberCount: 0, description: '', genres: const []),
  ];

  // Final screen saving state
  bool _isFinishing = false;
  String _finishStatusText = 'Creating your music profile...';

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(_validateUsername);
  }

  @override
  void dispose() {
    _usernameController.removeListener(_validateUsername);
    _usernameController.dispose();
    _artistSearchController.dispose();
    _pageController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _validateUsername() {
    final val = _usernameController.text.trim();
    setState(() {
      if (val.isEmpty) {
        _usernameError = 'Name cannot be empty';
      } else if (val.length > 20) {
        _usernameError = 'Name is too long (max 20 characters)';
      } else {
        _usernameError = '';
      }
    });
  }

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _searchArtists(query);
    });
  }

  Future<void> _searchArtists(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchedArtists = [];
        _isSearchingArtists = false;
      });
      return;
    }
    setState(() {
      _isSearchingArtists = true;
    });
    try {
      final sourceManager = ref.read(sourceManagerProvider);
      final searchResult = await sourceManager.activeAdapter.search(query);
      setState(() {
        _searchedArtists = searchResult.artists;
        _isSearchingArtists = false;
      });
    } catch (e) {
      DALogger.error('GuestOnboarding: Search artists failed', e);
      setState(() {
        _isSearchingArtists = false;
      });
    }
  }

  Future<void> _requestPermissions() async {
    if (!Platform.isAndroid) return;

    final prefs = await SharedPreferences.getInstance();
    final alreadyAskedBattery = prefs.getBool('ytm_battery_asked') ?? false;

    // 1. Request Notification Permission
    final notificationStatus = await Permission.notification.status;
    if (!notificationStatus.isGranted) {
      await Permission.notification.request();
    }

    // 2. Request Battery Optimization Exemption
    if (!alreadyAskedBattery) {
      final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
      if (!batteryStatus.isGranted && mounted) {
        // Show explaining dialog
        final proceed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            final colors = context.daColors;
            final typography = context.daTypography;
            return AlertDialog(
              backgroundColor: colors.surfaceCard,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DATokens.radiusLarge)),
              title: Text(
                'Exempt from Battery Optimization',
                style: typography.title.copyWith(fontSize: 18.0, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'To ensure uninterrupted listening, DA Tunes requires background execution permissions. This prevents the Android system from killing the audio player during playback.',
                    style: typography.body.copyWith(color: colors.textSecondary, fontSize: 14.0),
                  ),
                  const SizedBox(height: DATokens.spacingMedium),
                  Text(
                    'Why this is needed:',
                    style: typography.body.copyWith(fontWeight: FontWeight.bold, fontSize: 14.0),
                  ),
                  const SizedBox(height: DATokens.spacingTiny),
                  Text(
                    '• Reliable background playback\n• Stable lockscreen notifications\n• Prevents playback from being killed unexpectedly',
                    style: typography.body.copyWith(color: colors.textSecondary, fontSize: 13.0),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DATokens.radiusMedium)),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Proceed', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );

        await prefs.setBool('ytm_battery_asked', true);

        if (proceed == true) {
          await Permission.ignoreBatteryOptimizations.request();
        }
      }
    }
  }

  Future<void> _saveAndFinish() async {
    await _requestPermissions();

    setState(() {
      _isFinishing = true;
      _finishStatusText = 'Creating your music profile...';
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Save Username
      final cleanedName = _usernameController.text.trim();
      await ref.read(sessionManagerProvider).updateGuestUsername(cleanedName);
      await Future.delayed(const Duration(milliseconds: 600));

      // 2. Save Language preferences
      setState(() => _finishStatusText = 'Saving onboarding preferences...');
      await prefs.setStringList('ytm_guest_languages', _selectedLanguages.toList());
      await Future.delayed(const Duration(milliseconds: 600));

      // 3. Save Region
      if (_selectedRegion != null) {
        await prefs.setString('ytm_guest_region', _selectedRegion!);
      }

      // 4. Save Genres
      setState(() => _finishStatusText = 'Initializing recommendation data...');
      await prefs.setStringList('ytm_guest_genres', _selectedGenres.toList());
      await Future.delayed(const Duration(milliseconds: 600));

      // 5. Save Artists
      await prefs.setStringList(
        'ytm_guest_artists',
        _selectedArtists.map((a) => a.name).toList(),
      );

      // 6. Complete onboarding & trigger Home initialization
      setState(() => _finishStatusText = 'Preparing your Home feed...');
      await Future.delayed(const Duration(milliseconds: 800));

      await ref.read(tasteEngineNotifierProvider.notifier).reload();

      // Pre-warm and cache the recommendations in the background during finishing screen
      try {
        await ref.read(personalizedSectionsProvider.future);
      } catch (e, stack) {
        DALogger.error('GuestOnboarding: Failed to pre-generate recommendations', e, stack);
      }

      await ref.read(sessionManagerProvider).completeGuestOnboarding();
      // Onboarding complete automatically redirects guest to '/'
    } catch (e, stack) {
      DALogger.error('GuestOnboarding: Save preferences failed', e, stack);
      setState(() {
        _isFinishing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save profile. Please try again.')),
        );
      }
    }
  }

  void _nextStep() {
    if (_currentStep < 4) {
      setState(() {
        _currentStep++;
      });
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _saveAndFinish();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  Widget _buildStepIndicator(dynamic colors, dynamic typography) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DATokens.spacingLarge, vertical: DATokens.spacingSmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Step ${_currentStep + 1} of 5',
                style: typography.body.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13.0,
                ),
              ),
              Text(
                '${((_currentStep + 1) / 5 * 100).toInt()}% Complete',
                style: typography.caption.copyWith(
                  color: colors.textSecondary,
                  fontSize: 12.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: DATokens.spacingTiny),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / 5,
              backgroundColor: colors.surfaceCard.withValues(alpha: 0.3),
              color: colors.primary,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1(dynamic colors, dynamic typography) {
    final val = _usernameController.text.trim();
    final greetingText = val.isNotEmpty ? 'Welcome, $val' : 'Welcome, Voyager';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(DATokens.spacingLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'Choose your username',
              style: typography.display.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 28.0,
              ),
            ),
          ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),
          const SizedBox(height: DATokens.spacingTiny),
          Text(
            'We will use this name to personalize your screens and greetings throughout the app.',
            style: typography.body.copyWith(
              color: colors.textSecondary,
              fontSize: 14.0,
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
          const SizedBox(height: 20.0),
          TextField(
            controller: _usernameController,
            maxLength: 20,
            style: typography.title.copyWith(fontSize: 18.0),
            decoration: InputDecoration(
              hintText: 'Enter your name...',
              errorText: _usernameError.isNotEmpty ? _usernameError : null,
              counterText: '',
              hintStyle: typography.title.copyWith(fontSize: 18.0, color: colors.textSecondary.withValues(alpha: 0.4)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DATokens.radiusMedium),
                borderSide: BorderSide(color: colors.border.withValues(alpha: 0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DATokens.radiusMedium),
                borderSide: BorderSide(color: colors.primary, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: DATokens.spacingMedium, vertical: DATokens.spacingMedium),
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
          const SizedBox(height: 24.0),
          Center(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(DATokens.spacingLarge),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DATokens.radiusLarge),
                gradient: LinearGradient(
                  colors: [
                    colors.primary.withValues(alpha: 0.15),
                    colors.surfaceCard,
                  ],
                ),
                border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Icon(Icons.face_retouching_natural_outlined, size: 40.0, color: colors.primary),
                  const SizedBox(height: DATokens.spacingSmall),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      greetingText,
                      style: typography.title.copyWith(fontSize: 22.0, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    'Your music heaven avatar is ready.',
                    style: typography.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ).animate().scale(duration: 500.ms, delay: 300.ms, curve: Curves.easeOutBack),
        ],
      ),
    );
  }

  Widget _buildStep2(dynamic colors, dynamic typography) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(DATokens.spacingLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'Select languages',
              style: typography.display.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 28.0,
              ),
            ),
          ).animate().fadeIn(duration: 400.ms),
          const SizedBox(height: DATokens.spacingTiny),
          Text(
            'Which languages do you listen to? We will customize charts and suggestions accordingly.',
            style: typography.body.copyWith(
              color: colors.textSecondary,
              fontSize: 14.0,
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
          const SizedBox(height: 20.0),
          Wrap(
            spacing: 12.0,
            runSpacing: 12.0,
            children: _languagesList.map((lang) {
              final isSelected = _selectedLanguages.contains(lang);
              return ChoiceChip(
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    lang,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.black : colors.textPrimary,
                    ),
                  ),
                ),
                selected: isSelected,
                selectedColor: colors.primary,
                backgroundColor: colors.surfaceCard,
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      _selectedLanguages.add(lang);
                    } else {
                      _selectedLanguages.remove(lang);
                    }
                  });
                },
              );
            }).toList(),
          ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
        ],
      ),
    );
  }

  Widget _buildStep3(dynamic colors, dynamic typography) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(DATokens.spacingLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'Choose your region',
              style: typography.display.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 28.0,
              ),
            ),
          ).animate().fadeIn(duration: 400.ms),
          const SizedBox(height: DATokens.spacingTiny),
          Text(
            'Select your country to get local charts, regional recommendations, and trending songs.',
            style: typography.body.copyWith(
              color: colors.textSecondary,
              fontSize: 14.0,
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
          const SizedBox(height: 20.0),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _regionsList.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16.0,
              crossAxisSpacing: 16.0,
              childAspectRatio: 2.2,
            ),
            itemBuilder: (context, idx) {
              final region = _regionsList[idx];
              final isSelected = _selectedRegion == region;

              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedRegion = region;
                  });
                },
                borderRadius: BorderRadius.circular(DATokens.radiusMedium),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? colors.primary.withValues(alpha: 0.15) : colors.surfaceCard,
                    borderRadius: BorderRadius.circular(DATokens.radiusMedium),
                    border: Border.all(
                      color: isSelected ? colors.primary : colors.border.withValues(alpha: 0.1),
                      width: isSelected ? 2.0 : 1.0,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: isSelected ? colors.primary : colors.textSecondary,
                          size: 18.0,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              region,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: typography.title.copyWith(
                                fontSize: 15.0,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? colors.primary : colors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
        ],
      ),
    );
  }

  Widget _buildStep4(dynamic colors, dynamic typography) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(DATokens.spacingLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'Favorite genres',
              style: typography.display.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 28.0,
              ),
            ),
          ).animate().fadeIn(duration: 400.ms),
          const SizedBox(height: DATokens.spacingTiny),
          Text(
            'Select at least 3 genres to define your core music taste.',
            style: typography.body.copyWith(
              color: _selectedGenres.length >= 3 ? colors.textSecondary : Colors.amberAccent,
              fontSize: 14.0,
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
          const SizedBox(height: 20.0),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _genresList.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12.0,
              crossAxisSpacing: 12.0,
              childAspectRatio: 2.2,
            ),
            itemBuilder: (context, idx) {
              final genre = _genresList[idx];
              final isSelected = _selectedGenres.contains(genre);

              return InkWell(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedGenres.remove(genre);
                    } else {
                      _selectedGenres.add(genre);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(DATokens.radiusMedium),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(DATokens.radiusMedium),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isSelected
                          ? [colors.primary.withValues(alpha: 0.3), colors.primary.withValues(alpha: 0.1)]
                          : [colors.surfaceCard, colors.surfaceCard.withValues(alpha: 0.6)],
                    ),
                    border: Border.all(
                      color: isSelected ? colors.primary : colors.border.withValues(alpha: 0.05),
                      width: isSelected ? 2.0 : 1.0,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              genre,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: typography.title.copyWith(
                                fontSize: 15.0,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? colors.primary : colors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (isSelected)
                          Icon(Icons.check_circle, color: colors.primary, size: 20.0)
                        else
                          Icon(Icons.add_circle_outline, color: colors.textSecondary.withValues(alpha: 0.4), size: 20.0),
                      ],
                    ),
                  ),
                ),
              );
            },
          ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
        ],
      ),
    );
  }

  Widget _buildStep5(dynamic colors, dynamic typography) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(DATokens.spacingLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'Who are your favorite artists?',
              style: typography.display.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 28.0,
              ),
            ),
          ).animate().fadeIn(duration: 400.ms),
          const SizedBox(height: DATokens.spacingTiny),
          Text(
            'Search and select multiple artists. Selected artists will seed your initial recommendation feed.',
            style: typography.body.copyWith(
              color: colors.textSecondary,
              fontSize: 14.0,
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
          const SizedBox(height: 24.0),
          TextField(
            controller: _artistSearchController,
            onChanged: _onSearchChanged,
            style: typography.body.copyWith(fontSize: 16.0),
            decoration: InputDecoration(
              hintText: 'Search for artists...',
              hintStyle: TextStyle(color: colors.textSecondary.withValues(alpha: 0.5)),
              prefixIcon: Icon(Icons.search, color: colors.primary),
              suffixIcon: _artistSearchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _artistSearchController.clear();
                        _searchArtists('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: colors.surfaceCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DATokens.radiusMedium),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
          const SizedBox(height: 24.0),
          if (_isSearchingArtists)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0),
                child: CircularProgressIndicator(color: colors.primary),
              ),
            )
          else if (_artistSearchController.text.trim().isNotEmpty && _searchedArtists.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0),
                child: Text('No artists found. Try another search.', style: typography.body.copyWith(color: colors.textSecondary)),
              ),
            )
          else ...[
            Text(
              _artistSearchController.text.trim().isEmpty ? 'POPULAR SUGGESTIONS' : 'SEARCH RESULTS',
              style: typography.caption.copyWith(color: colors.textSecondary, letterSpacing: 1.1, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12.0),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _artistSearchController.text.trim().isEmpty ? _popularArtists.length : _searchedArtists.length,
              itemBuilder: (context, idx) {
                final artist = _artistSearchController.text.trim().isEmpty
                    ? _popularArtists[idx]
                    : _searchedArtists[idx];

                final isSelected = _selectedArtists.any((a) => a.name.toLowerCase().trim() == artist.name.toLowerCase().trim());

                return Card(
                  color: isSelected ? colors.primary.withValues(alpha: 0.1) : colors.surfaceCard.withValues(alpha: 0.3),
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DATokens.radiusMedium),
                    side: BorderSide(
                      color: isSelected ? colors.primary : colors.border.withValues(alpha: 0.1),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: DATokens.spacingMedium, vertical: 4.0),
                    leading: _buildArtistAvatar(artist, colors, typography),
                    title: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        artist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typography.title.copyWith(fontSize: 15.0, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle, color: colors.primary)
                        : Icon(Icons.add_circle_outline, color: colors.textSecondary.withValues(alpha: 0.4)),
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedArtists.removeWhere((a) => a.name.toLowerCase().trim() == artist.name.toLowerCase().trim());
                        } else {
                          _selectedArtists.add(artist);
                        }
                      });
                    },
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildArtistAvatar(domain.Artist artist, dynamic colors, dynamic typography) {
    if (artist.image.url.isNotEmpty && artist.image.url.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: DAImage(
          url: artist.image.url,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
        ),
      );
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            colors.primary.withValues(alpha: 0.4),
            colors.primary.withValues(alpha: 0.1),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        artist.name.isNotEmpty ? artist.name[0].toUpperCase() : 'A',
        style: typography.title.copyWith(
          fontSize: 16.0,
          fontWeight: FontWeight.bold,
          color: colors.primary,
        ),
      ),
    );
  }

  Widget _buildFinishingScreen(dynamic colors, dynamic typography) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.surface,
            colors.surfaceCard,
            Colors.black,
          ],
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(DATokens.spacingLarge),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primary.withValues(alpha: 0.1),
                  border: Border.all(color: colors.primary.withValues(alpha: 0.3), width: 2),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.auto_awesome,
                  size: 48,
                  color: colors.primary,
                ),
              )
              .animate(onPlay: (controller) => controller.repeat(reverse: true))
              .scale(duration: 1.seconds, begin: const Offset(0.95, 0.95), end: const Offset(1.05, 1.05))
              .fadeIn(),
              const SizedBox(height: 40.0),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Enter to Your Music Heaven',
                  style: typography.display.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 26.0,
                  ),
                  textAlign: TextAlign.center,
                ),
              ).animate().fadeIn(duration: 400.ms),
              const SizedBox(height: DATokens.spacingSmall),
              Text(
                'Your music preferences profile is set. We are fetching your personalized recommendation tracks.',
                style: typography.body.copyWith(
                  color: colors.textSecondary,
                  fontSize: 14.0,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
              const SizedBox(height: 50.0),
              SizedBox(
                width: 180,
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      backgroundColor: colors.surfaceCard,
                      color: colors.primary,
                    ),
                    const SizedBox(height: 12.0),
                    Text(
                      _finishStatusText,
                      style: typography.caption.copyWith(color: colors.textSecondary, fontSize: 12.0),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.daColors;
    final typography = context.daTypography;

    if (_isFinishing) {
      return Scaffold(
        body: _buildFinishingScreen(colors, typography),
      );
    }

    final isStep1Valid = _usernameController.text.trim().isNotEmpty && _usernameError.isEmpty;
    final isStep4Valid = _selectedGenres.length >= 3;
    final isStep5Valid = true;

    bool isCurrentStepValid() {
      switch (_currentStep) {
        case 0:
          return isStep1Valid;
        case 3:
          return isStep4Valid;
        case 4:
          return isStep5Valid;
        default:
          return true;
      }
    }

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _prevStep,
              )
            : null,
        title: Text(
          'Personalize Profile',
          style: typography.title.copyWith(fontSize: 18.0),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildStepIndicator(colors, typography),
            const SizedBox(height: DATokens.spacingSmall),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStep1(colors, typography),
                  _buildStep2(colors, typography),
                  _buildStep3(colors, typography),
                  _buildStep4(colors, typography),
                  _buildStep5(colors, typography),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(DATokens.spacingLarge),
              child: Row(
                children: [
                  if (_currentStep > 0) ...[
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.textPrimary,
                          side: BorderSide(color: colors.border.withValues(alpha: 0.15)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(DATokens.radiusMedium),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: DATokens.spacingMedium),
                        ),
                        onPressed: _prevStep,
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Back'),
                        ),
                      ),
                    ),
                    const SizedBox(width: DATokens.spacingMedium),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isCurrentStepValid() ? colors.primary : colors.surfaceCard,
                        foregroundColor: isCurrentStepValid() ? Colors.black : colors.textSecondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(DATokens.radiusMedium),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: DATokens.spacingMedium),
                      ),
                      onPressed: isCurrentStepValid() ? _nextStep : null,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _currentStep == 4 ? 'Finish' : 'Continue',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
