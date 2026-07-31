import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:karma_verito/screens/home_screen.dart';

class AuthMobile extends StatefulWidget {
  const AuthMobile({super.key});

  @override
  State<AuthMobile> createState() => _AuthMobileState();
}

class _AuthMobileState extends State<AuthMobile> {
  final TextEditingController _mobileController = TextEditingController();
  String _fetchedUserName = '';
  bool _isLoading = false;
  final userToken = FirebaseAuth.instance.currentUser;
  Timer? _timer;
  int _timeRemaining = 60;
  bool resendAvailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (userToken != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomePage()),
        );
      }
    });
  }

  void _verifyNumberAndSendOtp() async {
    final String mobileNumber = _mobileController.text;
    print("Checking $mobileNumber");

    if (mobileNumber.isEmpty || mobileNumber.length != 10) {
      _showErrorSnackBar('Please enter a valid 10-digit mobile number');
      return;
    }

    print("Checking for $mobileNumber through API...");
    setState(() => _isLoading = true);

    try {
      final fetchUserUrl = Uri.parse(
        'http://192.168.0.128:64/employee?mobile=+$mobileNumber',
      );

      print('Calling: $fetchUserUrl');

      final response = await http
          .get(fetchUserUrl)
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        Map<String, dynamic> employee = jsonDecode(response.body);
        print("Fetched employee: $employee");
        setState(() {
          _fetchedUserName = employee['Employee_Name'].toString();
        });

        final vasudevResponse = await http.post(
          Uri.parse('http://192.168.0.128:64/send-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'phoneNumber': mobileNumber}),
        );

        if (!mounted) return;
        setState(() => _isLoading = false);

        if (vasudevResponse.statusCode == 200) {
          _showSuccessSnackBar('OTP sent successfully.');
          _showOtpDialog(phoneNumber: mobileNumber);
        } else {
          _showErrorSnackBar('Error sending OTP.');
          setState(() => _isLoading = false);
        }
      } else {
        setState(() => _isLoading = false);
        print("Error fetching user: ${response.statusCode}");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("This mobile number is not registered."),
          ),
        );
      }
    } catch (e) {
      print('_verifyNumberAndSendOtp error: $e');
      _showErrorSnackBar('Error fetching user data');
      setState(() => _isLoading = false);
    }
  }

  void _showOtpDialog({required String phoneNumber}) {
    final String mobileNumber = _mobileController.text;
    final focusNodes = List.generate(4, (_) => FocusNode());
    final controllers = List.generate(4, (_) => TextEditingController());
    String errorMessage = '';
    bool _isVerifying = false;
    bool isTimerStarted = true;

    void disposeControllers() {
      for (var controller in controllers) {
        controller.dispose();
      }
      for (var node in focusNodes) {
        node.dispose();
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void _onOtpChanged(String value, int index) {
              setDialogState(() {
                errorMessage = '';
              });
              if (value.isNotEmpty && index < 3) {
                FocusScope.of(context).requestFocus(focusNodes[index + 1]);
              }
              if (value.isEmpty && index > 0) {
                FocusScope.of(context).requestFocus(focusNodes[index - 1]);
              }
            }

            void _startDialogTimer() {
              _timer?.cancel();

              setDialogState(() {
                resendAvailable = false;
                _timeRemaining = 60;
              });

              _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
                if (!mounted) {
                  timer.cancel();
                  return;
                }

                if (_timeRemaining == 0) {
                  setDialogState(() {
                    resendAvailable = true;
                    timer.cancel();
                  });
                } else {
                  setDialogState(() {
                    _timeRemaining--;
                  });
                }
              });
            }

            if(isTimerStarted){
              _startDialogTimer();
              isTimerStarted = false;
            }

            // WidgetsBinding.instance.addPostFrameCallback((_) {
            //   if (_timer == null || !_timer!.isActive) {
            //     _startDialogTimer();
            //   }
            // });

            Future<void> _resendOtp() async {
              _startDialogTimer();
              try {
                final vasudevResponse = await http.post(
                  Uri.parse('http://192.168.0.128:64/send-otp'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({'phoneNumber': mobileNumber}),
                );

                if (!mounted) return;

                if (vasudevResponse.statusCode == 200) {
                  _showSuccessSnackBar('OTP sent.');
                } else {
                  _showErrorSnackBar('Error sending OTP.');
                  _timer?.cancel();
                  setDialogState(() => resendAvailable = true);
                }
              } catch (e) {
                print('_resendOtp error: $e');
                _showErrorSnackBar('Error re-sending OTP.');
                _timer?.cancel();
                setDialogState(() => resendAvailable = true);
              }
            }

            Future<void> _verifyOtp() async {
              final otp = controllers.map((c) => c.text).join();
              print('OTP: $otp');

              if (otp.length != 4 || otp.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid OTP entered.')),
                );
                setDialogState(() => errorMessage = 'Check OTP');
                print('otp.length != 4. Please try again.');
                return;
              }

              setDialogState(() => _isVerifying = true);

              print('Authenticating with mobile and otp credentials');

              try {
                final vasudevResponse = await http.post(
                  Uri.parse('http://192.168.0.128:64/verify-otp'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({'phoneNumber': phoneNumber, 'otp': otp}),
                );

                if (!mounted) return;

                if (vasudevResponse.statusCode == 200) {
                  final data = jsonDecode(vasudevResponse.body);
                  final customToken = data['token'];
                  await FirebaseAuth.instance.signInWithCustomToken(
                    customToken,
                  );
                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Authentication successful.')),
                  );

                  setDialogState(() => _isVerifying = false);
                  _timer?.cancel();
                  // disposeControllers();

                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => HomePage()),
                  );
                } else {
                  setDialogState(() => errorMessage = 'Invalid OTP');
                  _showErrorSnackBar(errorMessage);
                }
              } catch (e) {
                print("Verify OTP error: $e");
                _showErrorSnackBar("Verify OTP error: $e");
              }
              setDialogState(() => _isVerifying = false);
            }

            return PopScope(
              canPop: false,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: EdgeInsets.zero,
                elevation: 0,
                backgroundColor: Color(0xFFF8F0E3),
                content: Container(
                  padding: EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Enter OTP',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal.shade800,
                        ),
                      ),
                      const SizedBox(height: 8),

                      Text(
                        'Hello $_fetchedUserName, A 4-digit code has been sent to your number.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(4, (index) {
                          return Flexible(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 52),
                                child: TextFormField(
                                  controller: controllers[index],
                                  focusNode: focusNodes[index],
                                  onChanged: (value) => _onOtpChanged(value, index),
                                  textAlign: TextAlign.center,
                                  keyboardType: TextInputType.number,
                                  maxLength: 1,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                  decoration: InputDecoration(
                                    counterText: '',
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: Colors.grey.shade300),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(color: Colors.teal.shade700, width: 2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),

                      if (errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          errorMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),

                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            "Didn't receive code? ",
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: resendAvailable ? _resendOtp : null,
                            child: Text(
                              "Resend OTP",
                              style: TextStyle(
                                color: resendAvailable
                                    ? Colors.teal.shade700
                                    : Colors.grey.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (!resendAvailable)
                            Text(
                              " (${_timeRemaining}s)",
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      ElevatedButton(
                        onPressed: _verifyOtp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 8,
                          shadowColor: Colors.teal.withOpacity(0.5),
                        ),
                        child: _isVerifying
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              )
                            : const Text(
                                'Confirm',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        height: double.infinity,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/login_bg.jpg'),
            // alignment: Alignment.center,
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.teal.shade600,
              BlendMode.darken,
            ),
          ),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.only(
                  left: 24.0,
                  right: 24.0,
                  top: 32.0,
                  bottom: 36.0,
                ),
                decoration: BoxDecoration(
                  color: Color(0xFFF8F0E3),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(
                      height: 60,
                      child: Image.asset(
                        'assets/images/karma_logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 20.0),

                    const Text(
                      'Welcome to Verito',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF035C5C),
                      ),
                    ),
                    const SizedBox(height: 2.0),

                    Text(
                      'Enter your mobile number to continue',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 32),

                    TextFormField(
                      controller: _mobileController,
                      keyboardType: TextInputType.phone,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.0,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      // decoration: InputDecoration(
                      //   hintText: 'e.g. 9876543210',
                      //   hintStyle: TextStyle(color: Colors.grey.shade500),
                      //   filled: true,
                      //   fillColor: Colors.white,
                      //   border: OutlineInputBorder(
                      //     borderRadius: BorderRadius.circular(12),
                      //     borderSide: BorderSide.none,
                      //   ),
                      //   contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      // ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'e.g. 9876543210',
                        hintStyle: TextStyle(color: Colors.grey.shade500),
                        filled: true,
                        fillColor: Colors.white,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: Colors.teal.shade700,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    ElevatedButton(
                      onPressed: _verifyNumberAndSendOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 5,
                        shadowColor: Colors.teal.shade200,
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                              padding: EdgeInsets.only(left: 14),
                              constraints: BoxConstraints(
                                minHeight: 16,
                                minWidth: 16,
                              ),
                            )
                          : const Text(
                              'Send OTP',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
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
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}
