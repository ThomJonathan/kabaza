import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kabanza/routes.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class VehicleDetailsScreen extends StatefulWidget {
  const VehicleDetailsScreen({super.key});

  @override
  _VehicleDetailsScreenState createState() => _VehicleDetailsScreenState();
}

class _VehicleDetailsScreenState extends State<VehicleDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  // Controllers
  final _makeController = TextEditingController();
  final _modelController = TextEditingController();
  final _licenseNumberController = TextEditingController();
  final _insuranceNumberController = TextEditingController();

  // State variables
  bool _isLoading = false;
  String _vehicleType = 'car';
  File? _vehiclePhoto;
  File? _licensePhoto;
  File? _insurancePhoto;

  final List<String> _vehicleTypes = [
    'car',
    'motorcycle'
  ];

  @override
  void dispose() {
    _makeController.dispose();
    _modelController.dispose();
    _licenseNumberController.dispose();
    _insuranceNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(String type) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (image != null) {
        setState(() {
          switch (type) {
            case 'vehicle':
              _vehiclePhoto = File(image.path);
              break;
            case 'license':
              _licensePhoto = File(image.path);
              break;
            case 'insurance':
              _insurancePhoto = File(image.path);
              break;
          }
        });
      }
    } catch (e) {
      _showErrorSnackBar('Error picking image: $e');
    }
  }

  Future<String?> _uploadImage(File image, String folder) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      final fileName = '${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = '$folder/$fileName';

      await _supabase.storage
          .from('vehicle-documents')
          .upload(filePath, image);

      final publicUrl = _supabase.storage
          .from('vehicle-documents')
          .getPublicUrl(filePath);

      return publicUrl;
    } catch (e) {
      _showErrorSnackBar('Error uploading image: $e');
      return null;
    }
  }

  Future<void> _saveVehicleDetails() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        _showErrorSnackBar('User not authenticated');
        return;
      }

      // Upload images if available
      String? vehiclePhotoUrl;
      String? licensePhotoUrl;
      String? insurancePhotoUrl;

      if (_vehiclePhoto != null) {
        vehiclePhotoUrl = await _uploadImage(_vehiclePhoto!, 'vehicle-photos');
      }

      if (_licensePhoto != null) {
        licensePhotoUrl = await _uploadImage(_licensePhoto!, 'license-photos');
      }

      if (_insurancePhoto != null) {
        insurancePhotoUrl = await _uploadImage(_insurancePhoto!, 'insurance-photos');
      }

      // Insert vehicle details
      await _supabase.from('vehicles').insert({
        'user_id': user.id,
        'vehicle_type': _vehicleType,
        'make': _makeController.text.trim(),
        'model': _modelController.text.trim(),
        'license_number': _licenseNumberController.text.trim(),
        'insurance_number': _insuranceNumberController.text.trim(),
        'vehicle_photo_url': vehiclePhotoUrl,
        'license_photo_url': licensePhotoUrl,
        'insurance_photo_url': insurancePhotoUrl,
        'is_verified': false,
        'is_active': true,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vehicle details saved successfully! Your account is under review.'),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate to main app (you can change this to your desired route)
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.login, // or wherever you want to redirect
            (route) => false,
      );

    } on PostgrestException catch (error) {
      _showErrorSnackBar('Database error: ${error.message}');
    } catch (error) {
      _showErrorSnackBar('An unexpected error occurred: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Widget _buildImagePicker(String title, File? image, String type) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _pickImage(type),
          child: Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[400]!),
            ),
            child: image != null
                ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                image,
                fit: BoxFit.cover,
              ),
            )
                : const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.camera_alt, size: 40, color: Colors.grey),
                SizedBox(height: 8),
                Text('Tap to select image', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          'Vehicle Details',
          style: TextStyle(color: Colors.black),
        ),
        automaticallyImplyLeading: false, // Remove back button
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title
                  Center(
                    child: Text(
                      'Add Your Vehicle',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Center(
                    child: Text(
                      'Please provide your vehicle details for verification',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Vehicle Type
                  const Text(
                    'Vehicle Type',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _vehicleType,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.directions_car),
                    ),
                    items: _vehicleTypes.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type.capitalize()),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _vehicleType = value!;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // Make
                  TextFormField(
                    controller: _makeController,
                    decoration: InputDecoration(
                      labelText: 'Make (e.g., Toyota, Honda)',
                      prefixIcon: const Icon(Icons.build),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter vehicle make';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Model
                  TextFormField(
                    controller: _modelController,
                    decoration: InputDecoration(
                      labelText: 'Model (e.g., Camry, Civic)',
                      prefixIcon: const Icon(Icons.car_rental),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter vehicle model';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // License Number
                  TextFormField(
                    controller: _licenseNumberController,
                    decoration: InputDecoration(
                      labelText: 'Driver License Number',
                      prefixIcon: const Icon(Icons.badge),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter license number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Insurance Number (Optional)
                  TextFormField(
                    controller: _insuranceNumberController,
                    decoration: InputDecoration(
                      labelText: 'Insurance Number (Optional)',
                      prefixIcon: const Icon(Icons.security),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Vehicle Photo
                  _buildImagePicker('Vehicle Photo', _vehiclePhoto, 'vehicle'),
                  const SizedBox(height: 16),

                  // License Photo
                  _buildImagePicker('Driver License Photo', _licensePhoto, 'license'),
                  const SizedBox(height: 16),

                  // Insurance Photo (Optional)
                  _buildImagePicker('Insurance Document (Optional)', _insurancePhoto, 'insurance'),
                  const SizedBox(height: 30),

                  // Submit Button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _saveVehicleDetails,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                        : const Text(
                      'Save Vehicle Details',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Info text
                  const Text(
                    'Your vehicle details will be reviewed by our team. You will be notified once approved.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Extension to capitalize first letter
extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}