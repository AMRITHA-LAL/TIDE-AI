import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SharedTaskScreen extends StatelessWidget {
  final String userId;
  final String taskId;
  final String shareId;

  const SharedTaskScreen({
    super.key,
    required this.userId,
    required this.taskId,
    required this.shareId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Shared Task",
        ),
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection("users")
            .doc(userId)
            .collection("tasks")
            .doc(taskId)
            .collection("shares")
            .doc(shareId)
            .get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (!snapshot.data!.exists) {
            return const Center(
              child: Text("Task not found"),
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Title: ${data["title"]}",
                  style: const TextStyle(
                    fontSize: 20,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "Category: ${data["category"]}",
                  style: const TextStyle(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "Priority: ${data["priority"]}",
                  style: const TextStyle(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Read Only",
                  style: TextStyle(
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
