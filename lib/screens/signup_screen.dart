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

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

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

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      
      if (image != null) {
        setState(() {
          _imageFile = File(image.path);
        });
        
        // Show loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        );
        
        // Extract MyKad number
        final extractedNumber = await extractMyKadNumber(_imageFile!);
        
        // Hide loading indicator
        Navigator.pop(context);
        
        if (extractedNumber != null) {
          setState(() {
            _myKadController.text = extractedNumber;
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not detect MyKad number. Please enter manually.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (e is PlatformException && e.code == 'already_active') {
        return;
      }
      print('Error picking image: $e');
    }
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
              ),
              SizedBox(height: 20),
              reusableTextField(
                "Name",
                Icons.person_outline,
                false,
                _nameController,
                isModern: true,
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
                  width: double.infinity,
                  height: 150,
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
                            height: 150,
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