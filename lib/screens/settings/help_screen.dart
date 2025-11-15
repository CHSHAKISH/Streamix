import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help'),
      ),
      body: const Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How to send a request:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              '1. From the home screen, tap on the user you want to ping.\n'
                  '2. On the chat screen, tap the "+" icon.\n'
                  '3. Select the service, set the time, and tap "Send Request".',
            ),
            SizedBox(height: 20),
            Text(
              'How to accept a request:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              '1. From the home screen, tap the "My Requests" button.\n'
                  '2. You will see a list of all pending requests.\n'
                  '3. Tap "Accept" on the request you want to fulfill.',
            ),
          ],
        ),
      ),
    );
  }
}