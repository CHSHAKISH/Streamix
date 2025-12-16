import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:streamix/services/ticket_service.dart';
import 'package:streamix/constants/app_colors.dart';

class RequestDialog extends StatefulWidget {
  final String peerUserId;
  const RequestDialog({super.key, required this.peerUserId});

  @override
  State<RequestDialog> createState() => _RequestDialogState();
}

class _RequestDialogState extends State<RequestDialog> {
  final TicketService _ticketService = TicketService();

  String _selectedService = 'location';
  DateTime _startTime = DateTime.now().add(const Duration(minutes: 5));
  DateTime _endTime = DateTime.now().add(const Duration(minutes: 10));
  bool _isLoading = false;

  final List<Map<String, dynamic>> _services = [
    {'id': 'location', 'name': 'Location', 'image': 'assets/images/location.png', 'width': 60.0, 'height': 60.0},
    {'id': 'audio', 'name': 'Audio', 'image': 'assets/images/audio.png', 'width': 36.0, 'height': 36.0},
    {'id': 'front_camera', 'name': 'Front Cam', 'image': 'assets/images/front_image.png', 'width': 36.0, 'height': 36.0},
    {'id': 'back_camera', 'name': 'Back Cam', 'image': 'assets/images/back_image.png', 'width': 36.0, 'height': 36.0},
    {'id': 'front_video', 'name': 'Front Vdo', 'image': 'assets/images/front_video.png', 'width': 36.0, 'height': 36.0},
    {'id': 'back_video', 'name': 'Back Vdo', 'image': 'assets/images/back_video.png', 'width': 36.0, 'height': 36.0},
    {'id': 'front_stream', 'name': 'F - Stream', 'image': 'assets/images/front_live.png', 'width': 36.0, 'height': 36.0},
    {'id': 'back_stream', 'name': 'B - Stream', 'image': 'assets/images/back_live.png', 'width': 36.0, 'height': 36.0},
  ];

  Future<void> _pickDateTime(bool isStartTime) async {
    final date = await showDatePicker(
      context: context,
      initialDate: isStartTime ? _startTime : _endTime,
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(isStartTime ? _startTime : _endTime),
    );
    if (time == null) return;

    final newDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    setState(() {
      if (isStartTime) {
        _startTime = newDateTime;
        if (_endTime.isBefore(_startTime)) {
          _endTime = _startTime.add(const Duration(minutes: 5));
        }
      } else {
        _endTime = newDateTime;
        if (_startTime.isAfter(_endTime)) {
          _startTime = _endTime.subtract(const Duration(minutes: 5));
        }
      }
    });
  }

  void _sendRequest() async {
    // --- VALIDATION: 2-Minute Rule ---
    final DateTime now = DateTime.now();
    final DateTime minAllowedTime = now.add(const Duration(minutes: 2));

    if (_startTime.isBefore(minAllowedTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request must be scheduled at least 2 minutes in the future.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    // --- END VALIDATION ---

    setState(() { _isLoading = true; });

    String result = await _ticketService.createScheduledRequest(
      peerUserId: widget.peerUserId,
      serviceType: _selectedService,
      startTime: Timestamp.fromDate(_startTime),
      endTime: Timestamp.fromDate(_endTime),
    );

    if (mounted) {
      if (result == "Success") {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request sent successfully!')),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result), backgroundColor: Colors.red),
        );
        setState(() { _isLoading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              const Text(
                'Schedule Request',
                textAlign: TextAlign.start,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 20),

              // Service Grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.75,
                ),
                itemCount: _services.length,
                itemBuilder: (context, index) {
                  final service = _services[index];
                  final isSelected = _selectedService == service['id'];
                  
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedService = service['id'];
                      });
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: 60,
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? AppColors.lightBackground 
                                : const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected 
                                  ? AppColors.accent 
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Center(
                            child: Image.asset(
                              service['image'],
                              width: service['width'],
                              height: service['height'],
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          service['name'],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              // Time Pickers Row
              Row(
                children: [
                  // Start Time
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDateTime(true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_outlined, color: Colors.grey[600], size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Start Time',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // End Time
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDateTime(false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_outlined, color: Colors.grey[600], size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'End Time',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Send Request Button
              _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.accent,
                      ),
                    )
                  : SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _sendRequest,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Send Request',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
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