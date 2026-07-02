// lib/ai_category_service.dart
// Tide AI Task Manager — Local AI Category Engine (No API)

class AiCategoryService {
  // ─────────────────────────────────────────────
  // KEYWORD MAPS — order matters (most specific first)
  // ─────────────────────────────────────────────

  static const Map<String, List<String>> _categoryKeywords = {
    'Study': [
      // Academic subjects
      'dbms', 'database', 'sql', 'algorithm', 'data structure',
      'physics', 'chemistry', 'biology', 'mathematics', 'maths', 'math',
      'history', 'geography', 'economics', 'psychology', 'sociology',
      'computer science', 'programming', 'coding', 'software',
      'circuit', 'electronics', 'mechanical', 'civil engineering',
      // Study activities
      'assignment', 'homework', 'notes', 'note', 'lecture', 'class',
      'study', 'revision', 'revise', 'read', 'reading', 'chapter',
      'exam', 'test', 'quiz', 'viva', 'practicals', 'lab', 'practical',
      'project report', 'thesis', 'dissertation', 'seminar', 'presentation',
      'submission', 'submit', 'college', 'university', 'school',
      'semester', 'syllabus', 'textbook', 'reference book',
      'preparation', 'prepare', 'learn', 'learning',
      'tutorial', 'worksheet', 'research paper', 'internship report',
    ],
    'Work': [
      // Meetings & communication
      'meeting', 'standup', 'stand-up', 'daily scrum', 'sprint',
      'call', 'zoom', 'teams', 'google meet', 'client call',
      'conference', 'interview', 'presentation', 'demo',
      // Work tasks
      'report', 'proposal', 'email', 'mail', 'reply', 'follow up',
      'task', 'deadline', 'project', 'milestone', 'deliverable',
      'review', 'feedback', 'appraisal', 'performance',
      'office', 'work', 'job', 'career', 'professional',
      'colleague', 'manager', 'boss', 'team', 'department',
      'salary', 'invoice', 'client', 'customer', 'vendor',
      'contract', 'agreement', 'document', 'approve', 'approval',
      'hr', 'resign', 'promotion', 'training', 'onboarding',
      'kpi', 'target', 'quota', 'strategy', 'plan',
    ],
    'Health': [
      // Medical appointments
      'doctor', 'physician', 'dentist', 'dermatologist', 'cardiologist',
      'hospital', 'clinic', 'appointment', 'checkup', 'check-up',
      'consultation', 'specialist', 'pharmacy', 'medicine', 'medication',
      'prescription', 'tablet', 'dose', 'injection', 'vaccine',
      // Wellness & fitness
      'gym', 'exercise', 'workout', 'run', 'jogging', 'walking',
      'yoga', 'meditation', 'diet', 'nutrition', 'calories',
      'sleep', 'rest', 'health', 'wellness', 'fitness',
      'blood test', 'scan', 'x-ray', 'mri', 'ecg', 'report',
      'sugar level', 'blood pressure', 'bp', 'weight',
      'therapy', 'physiotherapy', 'counselling',
    ],
    'Finance': [
      // Bills & payments
      'bill', 'electricity bill', 'water bill', 'internet bill',
      'rent', 'emi', 'loan', 'insurance', 'premium',
      'pay', 'payment', 'transfer', 'send money', 'recharge',
      // Banking & investment
      'bank', 'account', 'savings', 'investment', 'mutual fund',
      'stock', 'share', 'dividend', 'tax', 'itr', 'gst',
      'budget', 'expense', 'income', 'salary credit',
      'credit card', 'debit card', 'upi', 'transaction',
      'withdraw', 'deposit', 'fd', 'rd', 'ppf', 'nps',
      'receipt', 'invoice', 'billing', 'due', 'overdue',
    ],
    'Shopping': [
      'buy',
      'purchase',
      'order',
      'shop',
      'shopping',
      'amazon',
      'flipkart',
      'myntra',
      'swiggy',
      'zomato',
      'grocery',
      'vegetables',
      'fruits',
      'milk',
      'bread',
      'clothes',
      'shoes',
      'accessories',
      'gift',
      'return',
      'delivery',
      'pickup',
      'cart',
      'wishlist',
      'coupon',
      'market',
      'mall',
      'supermarket',
      'store',
    ],
    'Personal': [
      'family',
      'parents',
      'mom',
      'dad',
      'brother',
      'sister',
      'friend',
      'birthday',
      'anniversary',
      'party',
      'celebration',
      'travel',
      'trip',
      'vacation',
      'holiday',
      'tour',
      'visit',
      'clean',
      'cleaning',
      'house',
      'home',
      'room',
      'organize',
      'cook',
      'cooking',
      'recipe',
      'food',
      'movie',
      'series',
      'book',
      'hobby',
      'game',
      'music',
      'call mom',
      'call dad',
      'catch up',
      'hangout',
      'plan',
      'journal',
      'diary',
    ],
  };

  // ─────────────────────────────────────────────
  // MAIN METHOD — predict category from title
  // ─────────────────────────────────────────────

  static String predictCategory(String title) {
    if (title.trim().isEmpty) return 'Personal';

    final lowerTitle = title.toLowerCase().trim();

    // Score each category by how many keywords match
    final Map<String, int> scores = {};

    for (final entry in _categoryKeywords.entries) {
      final category = entry.key;
      final keywords = entry.value;

      int score = 0;
      for (final keyword in keywords) {
        if (lowerTitle.contains(keyword)) {
          // Longer keyword match = stronger signal
          score += keyword.split(' ').length;
        }
      }
      if (score > 0) {
        scores[category] = score;
      }
    }

    if (scores.isEmpty) return 'Personal';

    // Return the category with the highest score
    final best = scores.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return best.key;
  }

  // ─────────────────────────────────────────────
  // HELPER — get icon for category
  // ─────────────────────────────────────────────

  static String getCategoryIcon(String category) {
    switch (category) {
      case 'Study':
        return '📚';
      case 'Work':
        return '💼';
      case 'Health':
        return '❤️';
      case 'Finance':
        return '💰';
      case 'Shopping':
        return '🛒';
      case 'Personal':
        return '🏠';
      default:
        return '📝';
    }
  }

  // ─────────────────────────────────────────────
  // HELPER — all available categories
  // ─────────────────────────────────────────────

  static List<String> get allCategories => _categoryKeywords.keys.toList();
}
