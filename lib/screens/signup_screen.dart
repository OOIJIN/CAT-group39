import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cat304/reusable_widgets/reusable_widget.dart';
//import 'package:cat304/screens/home_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cat304/screens/signin_screen.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
//import 'package:cat304/utils/color_utils.dart';
import 'package:flutter/services.dart';
import 'package:cat304/noti.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:camera/camera.dart';
import 'dart:math' as math;
import 'package:permission_handler/permission_handler.dart';

class SignUpScreen extends StatefulWidget {
  final List<CameraDescription>? cameras;
  const SignUpScreen({Key? key, this.cameras}) : super(key: key);

  @override
  _SignUpScreenState createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final TextEditingController _myKadController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  File? _imageFile;
  bool _agreementChecked = false;
  late List<CameraDescription> cameras;
  bool camerasInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.cameras != null) {
      cameras = widget.cameras!;
      camerasInitialized = true;
    } else {
      initCameras();
    }
  }

  Future<void> initCameras() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      cameras = await availableCameras();
      if (mounted) {
        setState(() {
          camerasInitialized = true;
        });
      }
    } catch (e) {
      print('Failed to initialize cameras: $e');
    }
  }

  Future<void> _pickImage() async {
    try {
      // Request camera permission first
      final status = await Permission.camera.request();
      if (status.isDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera permission is required to capture MyKad image')),
        );
        return;
      }

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: Text('Select Image Source', 
              style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  ListTile(
                    leading: Icon(Icons.camera_alt, color: Colors.white),
                    title: Text('Take Photo', 
                      style: TextStyle(color: Colors.white)),
                    onTap: () async {
                      Navigator.pop(context);
                      try {
                        if (!camerasInitialized) {
                          await initCameras();
                        }
                        
                        if (!camerasInitialized || cameras.isEmpty) {
                          throw CameraException(
                            'No cameras available',
                            'Camera is not initialized or no cameras found.'
                          );
                        }
                        
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CameraScreen(camera: cameras.first),
                          ),
                        );
                        
                        if (result != null) {
                          await _handleImageCapture(File(result));
                        }
                      } catch (e) {
                        print('Camera error: $e');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to use camera. Please try using gallery instead.')),
                        );
                      }
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.photo_library, color: Colors.white),
                    title: Text('Choose from Gallery', 
                      style: TextStyle(color: Colors.white)),
                    onTap: () async {
                      Navigator.pop(context);
                      final ImagePicker picker = ImagePicker();
                      final XFile? image = await picker.pickImage(
                        source: ImageSource.gallery
                      );
                      if (image != null) {
                        await _handleImageCapture(File(image.path));
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      print('Error picking image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error accessing camera or gallery. Please try again.')),
      );
    }
  }

  void _showGalleryOnlyDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text('Select Image Source', 
            style: TextStyle(color: Colors.white)),
          content: ListTile(
            leading: Icon(Icons.photo_library, color: Colors.white),
            title: Text('Choose from Gallery', 
              style: TextStyle(color: Colors.white)),
            onTap: () async {
              Navigator.pop(context);
              final ImagePicker picker = ImagePicker();
              final XFile? image = await picker.pickImage(
                source: ImageSource.gallery
              );
              if (image != null) {
                await _handleImageCapture(File(image.path));
              }
            },
          ),
        );
      },
    );
  }

  void _showImageSourceDialog(CameraDescription camera) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text('Select Image Source', 
            style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                ListTile(
                  leading: Icon(Icons.camera_alt, color: Colors.white),
                  title: Text('Take Photo', 
                    style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(context);
                    try {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CameraScreen(camera: camera),
                        ),
                      );
                      
                      if (result != null) {
                        await _handleImageCapture(File(result));
                      }
                    } catch (e) {
                      print('Camera error: $e');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to use camera. Please try using gallery instead.')),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: Icon(Icons.photo_library, color: Colors.white),
                  title: Text('Choose from Gallery', 
                    style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(context);
                    final ImagePicker picker = ImagePicker();
                    final XFile? image = await picker.pickImage(
                      source: ImageSource.gallery
                    );
                    if (image != null) {
                      await _handleImageCapture(File(image.path));
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool isValidMyKad(String myKad) {
    // Remove any hyphens from the IC number
    String cleanMyKad = myKad.replaceAll('-', '');
    
    // Check if it's exactly 12 digits
    if (cleanMyKad.length != 12) {
      return false;
    }
    
    // Check if all characters are digits
    if (!RegExp(r'^[0-9]+$').hasMatch(cleanMyKad)) {
      return false;
    }
    
    return true;
  }

  Future<String?> extractMyKadNumber(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      
      // Pattern for Malaysian IC number (12 digits, may include hyphens)
      RegExp icPattern = RegExp(r'\d{6}[-]?\d{2}[-]?\d{4}');
      
      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          final match = icPattern.firstMatch(line.text);
          if (match != null) {
            // Clean the IC number (remove hyphens)
            String icNumber = match.group(0)!.replaceAll('-', '');
            
            // Validate the extracted number
            if (isValidMyKad(icNumber)) {
              return icNumber;
            }
          }
        }
      }
      
      textRecognizer.close();
      return null;
    } catch (e) {
      print('Error extracting MyKad number: $e');
      return null;
    }
  }

  Future<void> _handleImageCapture(File imageFile) async {
    setState(() {
      _imageFile = imageFile;
      // Clear MyKad field before attempting extraction
      _myKadController.text = '';
    });
    
    final extractedNumber = await extractMyKadNumber(_imageFile!);
    if (extractedNumber != null) {
      setState(() {
        _myKadController.text = extractedNumber;
      });
    }
  }

  Future<void> signUp() async {
    if (!_agreementChecked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please agree to the terms')),
      );
      return;
    }

    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload your MyKad image')),
      );
      return;
    }

    // Extract MyKad number from the image
    final extractedNumber = await extractMyKadNumber(_imageFile!);

    // Validate MyKad format and match with extracted number
    if (!isValidMyKad(_myKadController.text) || _myKadController.text != extractedNumber) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid MyKad number or does not match the image. Please enter the correct MyKad number.'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    try {
      // Check if MyKad already exists
      final existingUsers = await FirebaseFirestore.instance
          .collection('users')
          .where('myKadNumber', isEqualTo: _myKadController.text)
          .get();

      if (existingUsers.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This MyKad number is already registered')),
        );
        return;
      }

      // Convert image to base64
      final bytes = await _imageFile!.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Create user with email and password
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
              email: _emailController.text,
              password: _passwordController.text);

      // Save user data to Firestore
      String userId = userCredential.user!.uid;
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'myKadNumber': _myKadController.text,
        'name': _nameController.text,
        'phone': _phoneController.text,
        'email': _emailController.text,
        'password': _passwordController.text,
        'myKadImage': base64Image,
        'status': 'pending',
        'loginStatus': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Sign out immediately after registration
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      // Show approval message and navigate
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registration successful! Please wait for admin approval.'),
          duration: Duration(seconds: 3),
        ),
      );

      // Navigate immediately without delay
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => SignInScreen(
            hasNotificationPermission: false,
            clearFields: true,
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "Sign Up",
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Image.asset(
                  "images/logo.png",
                  height: 100,
                ),
              ),
              SizedBox(height: 30),
              reusableTextField(
                "No.MyKad",
                Icons.person_outline,
                false,
                _myKadController,
                isModern: true,
                inputType: TextInputType.number,
                readOnly: true,
              ),
              SizedBox(height: 20),
              reusableTextField(
                "Name",
                Icons.person_outline,
                false,
                _nameController,
                isModern: true,
                placeholder: "Enter name as shown in MyKad",
              ),
              SizedBox(height: 20),
              reusableTextField(
                "Phone number",
                Icons.phone,
                false,
                _phoneController,
                isModern: true,
                inputType: TextInputType.phone,
              ),
              SizedBox(height: 20),
              reusableTextField(
                "Email",
                Icons.email,
                false,
                _emailController,
                isModern: true,
              ),
              SizedBox(height: 20),
              reusableTextField(
                "Password",
                Icons.lock_outline,
                true,
                _passwordController,
                isModern: true,
              ),
              
              SizedBox(height: 20),
              Text(
                "Attach your MyKad picture",
                style: TextStyle(color: Colors.white),
              ),
              SizedBox(height: 10),
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  height: (MediaQuery.of(context).size.width * 0.85) / (8.5 / 5.4),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _imageFile == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_circle_outline,
                                color: Colors.grey, size: 40),
                            SizedBox(height: 5),
                            Text(
                              "Add image",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            _imageFile!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
                ),
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Checkbox(
                    value: _agreementChecked,
                    onChanged: (bool? value) {
                      setState(() {
                        _agreementChecked = value ?? false;
                      });
                    },
                    fillColor: WidgetStateProperty.resolveWith(
                      (states) => Colors.grey[800],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      "By using this application, I hereby agree to provide relevant information, including my true personal information.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
              Container(
                width: double.infinity,
                height: 50,
                margin: EdgeInsets.symmetric(vertical: 20),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  onPressed: signUp,
                  child: Text(
                    "Sign Up",
                    style: TextStyle(color: Colors.white, fontSize: 18),
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

class MyKadCameraOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // MyKad aspect ratio is 8.5:5.4 ≈ 1.574
    final myKadAspectRatio = 8.5 / 5.4;
    
    // Get screen dimensions
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    // Calculate frame size based on screen width
    final frameWidth = screenWidth * 0.85; // Use 85% of screen width
    final frameHeight = frameWidth / myKadAspectRatio;
    
    return Stack(
      children: [
        Container(
          color: Colors.black54,
          width: screenWidth,
          height: screenHeight,
          child: Stack(
            children: [
              // Frame for MyKad
              Positioned(
                top: screenHeight * 0.3,
                left: screenWidth * 0.075,
                child: Container(
                  width: frameWidth,
                  height: frameHeight,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
              // Guide text
              Positioned(
                bottom: screenHeight * 0.3,
                left: 0,
                right: 0,
                child: Text(
                  'Align MyKad within the frame',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;

  const CameraScreen({Key? key, required this.camera}) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                CameraPreview(_controller),
                MyKadCameraOverlay(),
                Positioned(
                  bottom: 30,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back, color: Colors.white, size: 30),
                        onPressed: () => Navigator.pop(context),
                      ),
                      FloatingActionButton(
                        backgroundColor: Colors.white,
                        child: Icon(Icons.camera_alt, color: Colors.black),
                        onPressed: () async {
                          try {
                            await _initializeControllerFuture;
                            final image = await _controller.takePicture();
                            Navigator.pop(context, image.path);
                          } catch (e) {
                            print(e);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          } else {
            return Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}
