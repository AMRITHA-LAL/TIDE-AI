// lib/widgets/ai_priority_banner.dart
// Drop this widget inside your task creation / edit screen

import 'package:flutter/material.dart';
import '../ai_priority_service.dart';

class AiPriorityBanner extends StatelessWidget {
  final String taskTitle;
  final DateTime? dueDate;
  final String? category;
  final void Function(String priority) onAccept;

  const AiPriorityBanner({
    Key? key,
    required this.taskTitle,
    required this.dueDate,
    required this.category,
    required this.onAccept,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Only show when title has at least 3 characters
    if (taskTitle.trim().length < 3) return const SizedBox.shrink();

    final result = AiPriorityService.recommendPriority(
      title: taskTitle,
      dueDate: dueDate,
      category: category,
    );

    final style = AiPriorityService.priorityStyle(result.priority);
    final color = Color(style['color'] as int);
    final icon = style['icon'] as String;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const Text('✨', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              const Text(
                'AI Suggested Priority',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Priority badge
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                result.priority,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // Reason
          Text(
            'Reason: ${result.reason}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
            ),
          ),

          const SizedBox(height: 10),

          // Accept button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => onAccept(result.priority),
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text('Use ${result.priority} Priority'),
            ),
          ),
        ],
      ),
    );
  }
}
