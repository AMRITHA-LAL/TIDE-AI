// lib/ai_search_service.dart
// Tide AI Task Manager — Smart Search (No API, Pure Dart)

class SmartSearchResult {
  final String taskId;
  final String title;
  final String category;
  final String priority;
  final bool done;
  final String matchReason; // why this task was returned

  const SmartSearchResult({
    required this.taskId,
    required this.title,
    required this.category,
    required this.priority,
    required this.done,
    required this.matchReason,
  });
}

class AISearchService {
  // ─────────────────────────────────────────────
  // SYNONYM MAP
  // Search word → what categories/keywords it relates to
  // ─────────────────────────────────────────────

  static const Map<String, List<String>> _synonyms = {
    // Intent → category names
    'study': ['Study'],
    'academic': ['Study'],
    'school': ['Study'],
    'college': ['Study'],
    'learning': ['Study'],
    'education': ['Study'],

    'work': ['Work'],
    'office': ['Work'],
    'job': ['Work'],
    'career': ['Work'],
    'professional': ['Work'],
    'business': ['Work'],

    'health': ['Health'],
    'medical': ['Health'],
    'fitness': ['Health'],
    'wellness': ['Health'],
    'hospital': ['Health'],
    'doctor': ['Health'],

    'finance': ['Finance'],
    'money': ['Finance'],
    'payment': ['Finance'],
    'bill': ['Finance'],
    'bank': ['Finance'],
    'budget': ['Finance'],

    'personal': ['Personal'],
    'home': ['Personal'],
    'family': ['Personal'],
    'life': ['Personal'],

    'shopping': ['Shopping'],
    'buy': ['Shopping'],
    'purchase': ['Shopping'],
    'shop': ['Shopping'],

    // Intent → priority
    'important': ['High'],
    'urgent': ['High'],
    'critical': ['High'],
    'priority': ['High'],
    'high': ['High'],

    'medium': ['Medium'],
    'normal': ['Medium'],
    'moderate': ['Medium'],

    'low': ['Low'],
    'minor': ['Low'],
    'later': ['Low'],

    // Intent → status
    'pending': ['pending'],
    'incomplete': ['pending'],
    'done': ['done'],
    'complete': ['done'],
    'finished': ['done'],
    'completed': ['done'],
  };

  // ─────────────────────────────────────────────
  // MAIN SEARCH METHOD
  // Pass your full task list, returns matched results
  // ─────────────────────────────────────────────

  static List<SmartSearchResult> search({
    required String query,
    required List<Map<String, dynamic>> tasks,
  }) {
    if (query.trim().isEmpty) return [];

    final lowerQuery = query.toLowerCase().trim();
    final queryWords = lowerQuery.split(RegExp(r'\s+'));

    // What categories, priorities, statuses does this query suggest?
    final Set<String> targetCategories = {};
    final Set<String> targetPriorities = {};
    final Set<String> targetStatuses = {};

    for (final word in queryWords) {
      final mapped = _synonyms[word] ?? [];
      for (final val in mapped) {
        if (['Study', 'Work', 'Health', 'Finance', 'Personal', 'Shopping']
            .contains(val)) {
          targetCategories.add(val);
        } else if (['High', 'Medium', 'Low'].contains(val)) {
          targetPriorities.add(val);
        } else if (['pending', 'done'].contains(val)) {
          targetStatuses.add(val);
        }
      }
    }

    final List<SmartSearchResult> results = [];

    for (final task in tasks) {
      final id = task['id'] ?? '';
      final title = (task['title'] ?? '').toString();
      final category = (task['category'] ?? '').toString();
      final priority = (task['priority'] ?? '').toString();
      final done = task['done'] == true;

      final lowerTitle = title.toLowerCase();
      final lowerCategory = category.toLowerCase();

      String? matchReason;

      // ── 1. Direct title match ──────────────
      if (lowerTitle.contains(lowerQuery)) {
        matchReason = 'Title matches "$query"';
      }

      // ── 2. Category synonym match ──────────
      if (matchReason == null && targetCategories.contains(category)) {
        matchReason = 'Belongs to $category category';
      }

      // ── 3. Priority match ──────────────────
      if (matchReason == null && targetPriorities.contains(priority)) {
        matchReason = '$priority priority task';
      }

      // ── 4. Status match ───────────────────
      if (matchReason == null && targetStatuses.isNotEmpty) {
        if (targetStatuses.contains('done') && done) {
          matchReason = 'Completed task';
        } else if (targetStatuses.contains('pending') && !done) {
          matchReason = 'Pending task';
        }
      }

      // ── 5. Word-by-word partial match ─────
      if (matchReason == null) {
        for (final word in queryWords) {
          if (word.length >= 3 &&
              (lowerTitle.contains(word) || lowerCategory.contains(word))) {
            matchReason = 'Related to "$word"';
            break;
          }
        }
      }

      if (matchReason != null) {
        results.add(SmartSearchResult(
          taskId: id,
          title: title,
          category: category,
          priority: priority,
          done: done,
          matchReason: matchReason,
        ));
      }
    }

    // Sort: High priority first, then pending before done
    results.sort((a, b) {
      final pOrder = {'High': 0, 'Medium': 1, 'Low': 2};
      final pa = pOrder[a.priority] ?? 1;
      final pb = pOrder[b.priority] ?? 1;
      if (pa != pb) return pa.compareTo(pb);
      if (a.done != b.done) return a.done ? 1 : -1;
      return 0;
    });

    return results;
  }

  // ─────────────────────────────────────────────
  // LEGACY METHOD (kept so old code doesn't break)
  // ─────────────────────────────────────────────

  static Future<String> searchTasks(
    String query,
    List<String> taskTitles,
  ) async {
    if (query.trim().isEmpty) return 'Please enter a search term.';

    final fakeTasks = taskTitles
        .map((t) => {
              'id': '',
              'title': t,
              'category': '',
              'priority': 'Medium',
              'done': false,
            })
        .toList();

    final results = search(query: query, tasks: fakeTasks);

    if (results.isEmpty) return 'No tasks found for "$query".';

    final lines = results.map((r) => '• ${r.title}').join('\n');
    return 'Smart search results for "$query":\n$lines';
  }
}
