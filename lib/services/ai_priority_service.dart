// lib/ai_priority_service.dart
// Tide AI Task Manager — Local AI Priority Recommendation (No API)

class PriorityResult {
  final String priority; // 'High', 'Medium', 'Low'
  final String reason;

  const PriorityResult({required this.priority, required this.reason});
}

class AiPriorityService {
  // ─────────────────────────────────────────────
  // KEYWORDS that always suggest HIGH priority
  // ─────────────────────────────────────────────

  static const List<String> _highKeywords = [
    'exam',
    'exams',
    'final exam',
    'test',
    'submission',
    'submit',
    'deadline',
    'project',
    'assignment',
    'urgent',
    'important',
    'critical',
    'asap',
    'interview',
    'viva',
    'presentation',
    'due today',
    'last date',
    'report',
    'thesis',
    'dissertation',
  ];

  // ─────────────────────────────────────────────
  // KEYWORDS that suggest MEDIUM priority
  // ─────────────────────────────────────────────

  static const List<String> _mediumKeywords = [
    'meeting',
    'call',
    'review',
    'follow up',
    'plan',
    'prepare',
    'study',
    'notes',
    'revision',
    'practice',
    'read',
    'appointment',
    'visit',
  ];

  // ─────────────────────────────────────────────
  // CATEGORIES that default to LOW
  // ─────────────────────────────────────────────

  static const List<String> _lowCategories = [
    'Personal',
    'Shopping',
  ];

  // ─────────────────────────────────────────────
  // MAIN METHOD
  // ─────────────────────────────────────────────

  static PriorityResult recommendPriority({
    required String title,
    DateTime? dueDate,
    String? category,
  }) {
    final lowerTitle = title.toLowerCase().trim();
    final now = DateTime.now();

    // ── STEP 1: Check due date proximity ──────
    if (dueDate != null) {
      final difference =
          dueDate.difference(DateTime(now.year, now.month, now.day)).inDays;

      if (difference <= 0) {
        return const PriorityResult(
          priority: 'High',
          reason: 'This task is due today — complete it immediately.',
        );
      }

      if (difference == 1) {
        return const PriorityResult(
          priority: 'High',
          reason: 'Deadline is tomorrow — start now.',
        );
      }

      if (difference <= 3) {
        // Still check keywords — if urgent word found, stay High
        if (_containsHighKeyword(lowerTitle)) {
          return PriorityResult(
            priority: 'High',
            reason: 'Deadline in $difference days and task seems critical.',
          );
        }
        return PriorityResult(
          priority: 'High',
          reason: 'Deadline approaching in $difference days.',
        );
      }

      if (difference <= 7) {
        if (_containsHighKeyword(lowerTitle)) {
          return PriorityResult(
            priority: 'High',
            reason: 'Due in $difference days and this looks important.',
          );
        }
        return PriorityResult(
          priority: 'Medium',
          reason: 'Due within this week — plan ahead.',
        );
      }

      if (difference <= 14) {
        return PriorityResult(
          priority: 'Medium',
          reason: 'Due in about ${difference} days — keep it on your radar.',
        );
      }
    }

    // ── STEP 2: Check high-priority keywords ──
    if (_containsHighKeyword(lowerTitle)) {
      return const PriorityResult(
        priority: 'High',
        reason: 'Task title suggests this is urgent or important.',
      );
    }

    // ── STEP 3: Check medium-priority keywords ─
    if (_containsMediumKeyword(lowerTitle)) {
      return const PriorityResult(
        priority: 'Medium',
        reason: 'Task requires attention but is not immediately urgent.',
      );
    }

    // ── STEP 4: Check category ─────────────────
    if (category != null && _lowCategories.contains(category)) {
      return const PriorityResult(
        priority: 'Low',
        reason: 'Personal or shopping tasks are usually low priority.',
      );
    }

    // ── STEP 5: No due date, no special keyword ─
    if (dueDate == null) {
      return const PriorityResult(
        priority: 'Low',
        reason: 'No deadline set — marked as low priority.',
      );
    }

    // Default
    return const PriorityResult(
      priority: 'Medium',
      reason: 'Assigned medium priority based on task details.',
    );
  }

  // ─────────────────────────────────────────────
  // PRIVATE HELPERS
  // ─────────────────────────────────────────────

  static bool _containsHighKeyword(String lowerTitle) {
    for (final keyword in _highKeywords) {
      if (lowerTitle.contains(keyword)) return true;
    }
    return false;
  }

  static bool _containsMediumKeyword(String lowerTitle) {
    for (final keyword in _mediumKeywords) {
      if (lowerTitle.contains(keyword)) return true;
    }
    return false;
  }

  // ─────────────────────────────────────────────
  // HELPER — priority colour (for UI use)
  // ─────────────────────────────────────────────

  static Map<String, dynamic> priorityStyle(String priority) {
    switch (priority) {
      case 'High':
        return {'color': 0xFFE53935, 'icon': '🔴', 'label': 'High'};
      case 'Medium':
        return {'color': 0xFFFF9800, 'icon': '🟡', 'label': 'Medium'};
      case 'Low':
      default:
        return {'color': 0xFF43A047, 'icon': '🟢', 'label': 'Low'};
    }
  }
}
