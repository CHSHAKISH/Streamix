import 'package:flutter/material.dart';

class FaqsScreen extends StatelessWidget {
  const FaqsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FAQs'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: const [
          Text(
            'Is this app free?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            'Yes, this app is completely free to use.\n',
          ),
          Text(
            'Is my data safe?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            'Yes. All requests are sent over a secure connection, and live streams are ephemeral. Location data is deleted immediately after a session ends.\n',
          ),
          Text(
            'Why is the video stream a black screen?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            'Live video streaming requires a direct P2P connection, which can fail on some networks. A future update will include a relay (TURN) server to fix this in all cases.\n',
          ),
        ],
      ),
    );
  }
}