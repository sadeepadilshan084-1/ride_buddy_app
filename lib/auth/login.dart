import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:io';
import '../l10n/app_localizations.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscure = true;
  bool _keepLoggedIn = true;
  bool _loading = false;
  String? _resultMessage;
  bool? _resultIsSuccess;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Helper function to save user profile to database
  Future<void> _saveUserProfile(User user) async {
    try {
      final email = user.email;
      final fullName =
          user.userMetadata?['full_name'] as String? ??
              email?.split('@').first ??
              'User';
      final photoUrl = user.userMetadata?['picture'] as String?;

      final profileData = {
        'id': user.id,
        'name': fullName,
        'email': email,
        if (photoUrl != null) 'avatar_url': photoUrl,
      };

      // Check if profile already exists
      final existing = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();

      if (existing == null) {
        try {
          await Supabase.instance.client
              .from('profiles')
              .upsert(profileData, onConflict: 'id');
          print('✓ Profile created/upserted during login');
        } catch (insertError) {
          print('✗ Failed to create profile during login: $insertError');
          throw Exception('Database error creating profile: $insertError');
        }
      } else {
        try {
          await Supabase.instance.client
              .from('profiles')
              .update(profileData)
              .eq('id', user.id);
          print('✓ Profile updated during login');
        } catch (updateError) {
          print('✗ Failed to update profile during login: $updateError');
          throw Exception('Database error updating profile: $updateError');
        }
      }
    } catch (e) {
      print('✗ Error saving profile: $e');
      rethrow;
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (response.user != null) {
        if (!mounted) return;

        // Save user profile to database
        await _saveUserProfile(response.user!);

        setState(() {
          _resultMessage = 'Login successful! Welcome back.';
          _resultIsSuccess = true;
        });

        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;

        Navigator.pushReplacementNamed(context, '/home');
      }
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _resultMessage = 'Login failed: ${error.message}';
        _resultIsSuccess = false;
      });
    } on SocketException catch (error) {
      if (!mounted) return;
      setState(() {
        _resultMessage = 'Network error: Cannot reach server. Please check your connection.';
        _resultIsSuccess = false;
      });
      print('Network Error: $error');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _resultMessage = 'Login error. Please try again.';
        _resultIsSuccess = false;
      });
      print('Login Error: $error');
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    try {
      setState(() => _loading = true);

      // Replace with your Web Client ID from Google Cloud Console
      const String webClientId =
          '939594160329-lb1if49fg9eks1kjujgjd5kqr483n1s4.apps.googleusercontent.com';

      final GoogleSignIn googleSignIn = GoogleSignIn(
        clientId: webClientId,
        scopes: ['email', 'profile'],
      );

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        if (!mounted) return;
        setState(() {
          _resultMessage = 'Google sign-in was cancelled.';
          _resultIsSuccess = false;
          _loading = false;
        });
        return;
      }

      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;
      final String? accessToken = googleAuth.accessToken;
      final String? idToken = googleAuth.idToken;

      if (accessToken == null || idToken == null) {
        if (!mounted) return;
        setState(() {
          _resultMessage = 'Failed to get authentication tokens from Google.';
          _resultIsSuccess = false;
          _loading = false;
        });
        return;
      }

      final response = await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      if (response.user != null) {
        if (!mounted) return;

        // Save user profile to database
        await _saveUserProfile(response.user!);

        setState(() {
          _resultMessage = 'Google login successful! Welcome back.';
          _resultIsSuccess = true;
        });

        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;

        Navigator.pushReplacementNamed(context, '/home');
      }
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _resultMessage = 'Google sign-in failed: ${error.message}';
        _resultIsSuccess = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _resultMessage = 'Google sign-in error. Please try again.';
        _resultIsSuccess = false;
      });
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Top banner
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.asset(
                      'assets/images/login_banner.png',
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
                    ),
                    Positioned(
                      bottom: 18,
                      child: Column(
                        children: const [
                          Text(
                            'Ride Buddy',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Log in to your account',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(AppLocalizations.of(context)!.email),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: 'example@gmail.com',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Email is required';
                          }
                          if (!value.contains('@')) {
                            return 'Enter valid email';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      Text(AppLocalizations.of(context)!.password),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          hintText: '********',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscure = !_obscure;
                              });
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Password is required';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 8),

                      Row(
                        children: [
                          Checkbox(
                            value: _keepLoggedIn,
                            onChanged: (value) {
                              setState(() {
                                _keepLoggedIn = value ?? true;
                              });
                            },
                          ),
                          Text(AppLocalizations.of(context)!.keepMeLoggedIn),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              Navigator.pushNamed(context, '/forgot-password');
                            },
                            child: Text(
                              AppLocalizations.of(context)!.forgotPassword,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Social login buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _loading ? null : _signInWithGoogle,
                              icon: Image.asset(
                                'assets/images/google.png',
                                width: 18,
                                height: 18,
                              ),
                              label: const Text(
                                'Google',
                                style: TextStyle(fontSize: 13),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.black87,
                                backgroundColor: Colors.white,
                                side: BorderSide(color: Colors.grey.shade300),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _loading ? null : null,
                              icon: const Icon(Icons.apple, size: 18),
                              label: const Text(
                                'Apple',
                                style: TextStyle(fontSize: 13),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.black87,
                                backgroundColor: Colors.white,
                                side: BorderSide(color: Colors.grey.shade300),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Email/Password login
                      ElevatedButton(
                        onPressed: _loading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF038124),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : Text(
                          AppLocalizations.of(context)!.login,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Result message box
                      if (_resultMessage != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _resultIsSuccess == true
                                ? Colors.green.shade50
                                : _resultIsSuccess == false
                                ? Colors.red.shade50
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _resultIsSuccess == true
                                  ? Colors.green.shade200
                                  : _resultIsSuccess == false
                                  ? Colors.red.shade200
                                  : Colors.grey.shade300,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _resultIsSuccess == true
                                    ? Icons.check_circle
                                    : _resultIsSuccess == false
                                    ? Icons.error_outline
                                    : Icons.info_outlined,
                                color: _resultIsSuccess == true
                                    ? Colors.green.shade700
                                    : _resultIsSuccess == false
                                    ? Colors.red.shade700
                                    : Colors.grey.shade700,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _resultMessage!,
                                  style: TextStyle(
                                    color: _resultIsSuccess == true
                                        ? Colors.green.shade900
                                        : _resultIsSuccess == false
                                        ? Colors.red.shade900
                                        : Colors.grey.shade900,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 8),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(AppLocalizations.of(context)!.dontHaveAccount),
                          GestureDetector(
                            onTap: () {
                              Navigator.pushNamed(context, '/signup');
                            },
                            child: const Text(
                              'Sign up',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
