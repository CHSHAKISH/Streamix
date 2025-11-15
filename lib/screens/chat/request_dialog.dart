import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:streamix/services/ticket_service.dart';

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
    {'id': 'location', 'name': 'Location', 'icon': Icons.location_on},
    {'id': 'audio', 'name': 'Audio', 'icon': Icons.mic},
    {'id': 'front_camera', 'name': 'Front Camera', 'icon': Icons.camera_front},
    {'id': 'back_camera', 'name': 'Back Camera', 'icon': Icons.camera_rear},
    {'id': 'front_video', 'name': 'Front Video', 'icon': Icons.videocam},
    {'id': 'back_video', 'name': 'Back Video', 'icon': Icons.videocam_off},
    {'id': 'front_stream', 'name': 'Front Stream', 'icon': Icons.wifi_tethering},
    {'id': 'back_stream', 'name': 'Back Stream', 'icon': Icons.wifi_tethering_off},
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
        // Ensure end time is always after start time
        if (_endTime.isBefore(_startTime)) {
          _endTime = _startTime.add(const Duration(minutes: 5));
        }
      } else {
        _endTime = newDateTime;
        // Ensure start time is always before end time
        if (_startTime.isAfter(_endTime)) {
          _startTime = _endTime.subtract(const Duration(minutes: 5));
        }
      }
    });
  }

  void _sendRequest() async {
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
        Navigator.pop(context); // Close the dialog
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Schedule a Request',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: 24),

              // Service Dropdown
              DropdownButtonFormField<String>(
                value: _selectedService,
                decoration: const InputDecoration(labelText: 'Service'),
                items: _services.map((service) {
                  return DropdownMenuItem<String>(
                    value: service['id'],
                    child: Row(
                      children: [
                        Icon(service['icon'], color: Theme.of(context).primaryColor),
                        const SizedBox(width: 12),
                        Text(service['name']),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() { _selectedService = value; });
                  }
                },
              ),
              const SizedBox(height: 16),

              // Start Time
              Text('Start Time', style: TextStyle(color: Colors.grey[700])),
              InkWell(
                onTap: () => _pickDateTime(true),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[400]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(DateFormat('MMM d, yyyy  h:mm a').format(_startTime)),
                      const Icon(Icons.calendar_month),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // End Time
              Text('End Time', style: TextStyle(color: Colors.grey[700])),
              InkWell(
                onTap: () => _pickDateTime(false),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[400]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(DateFormat('MMM d, yyyy  h:mm a').format(_endTime)),
                      const Icon(Icons.calendar_month),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Send Button
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                onPressed: _sendRequest,
                child: const Text('Send Request'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}