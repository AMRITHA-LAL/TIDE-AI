import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'firestore_service.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'auth_service.dart';
import 'shared_task_screen.dart';
import 'ai_category_service.dart';
import 'widgets/ai_priority_banner.dart';
import 'ai_priority_service.dart';
import 'ai_assistant_screen.dart';
import 'ai_search_service.dart';

// NOTE: ai_search_service.dart (Gemini API) is intentionally NOT imported.
// Search is handled locally below via LocalSearchService.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const TideAIApp());
}

// =====================
// COLORS
// =====================

class TideColors {
  static const background = Color(0xFF0F1017);
  static const card = Color(0xFF1B1D2A);
  static const primary = Color(0xFFFF9D4D);
  static const accent = Color(0xFFFF7A45);

  static const text = Colors.white;
  static const muted = Color(0xFF9CA3AF);

  static const success = Color(0xFF4CAF50);
  static const danger = Color(0xFFE57373);
}

// =====================
// TASK MODEL
// =====================

class Task {
  String? id;
  String title;
  String category;
  String priority;
  bool done;

  Task({
    this.id,
    required this.title,
    required this.category,
    required this.priority,
    this.done = false,
  });

  Map<String, dynamic> toJson() {
    return {
      "title": title,
      "category": category,
      "priority": priority,
      "done": done,
    };
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      title: json["title"] ?? "",
      category: json["category"] ?? "Work",
      priority: json["priority"] ?? "Medium",
      done: json["done"] ?? false,
    );
  }
}

// =====================
// LOCAL SMART SEARCH
// (No API — looks and feels like AI)
// =====================

class SmartSearchResult {
  final String taskId;
  final String title;
  final String category;
  final String priority;
  final bool done;
  final String matchReason;

  const SmartSearchResult({
    required this.taskId,
    required this.title,
    required this.category,
    required this.priority,
    required this.done,
    required this.matchReason,
  });
}

class LocalSearchService {
  /// Searches tasks by title, category, and priority keywords.
  /// Returns a list of [SmartSearchResult] with a human-friendly reason.
  static List<SmartSearchResult> search({
    required String query,
    required List<Map<String, dynamic>> tasks,
  }) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return [];

    final results = <SmartSearchResult>[];

    for (final task in tasks) {
      final title = (task['title'] ?? '').toString().toLowerCase();
      final category = (task['category'] ?? '').toString().toLowerCase();
      final priority = (task['priority'] ?? '').toString().toLowerCase();
      final done = task['done'] ?? false;

      String? reason;

      // Priority keyword matches
      if ((q == 'urgent' || q == 'high' || q == 'critical') &&
          priority == 'high') {
        reason = 'Matched high priority task';
      } else if ((q == 'medium' || q == 'normal') && priority == 'medium') {
        reason = 'Matched medium priority task';
      } else if ((q == 'low' || q == 'easy') && priority == 'low') {
        reason = 'Matched low priority task';
      }
      // Status keyword matches
      else if ((q == 'done' || q == 'completed' || q == 'finished') &&
          done == true) {
        reason = 'Task is already completed';
      } else if ((q == 'pending' || q == 'incomplete' || q == 'todo') &&
          done == false) {
        reason = 'Task is still pending';
      }
      // Category keyword match
      else if (category.contains(q)) {
        reason = 'Matched category: ${task['category']}';
      }
      // Title keyword match
      else if (title.contains(q)) {
        reason = 'Matched title keyword';
      }

      if (reason != null) {
        results.add(SmartSearchResult(
          taskId: task['id'] ?? '',
          title: task['title'] ?? '',
          category: task['category'] ?? '',
          priority: task['priority'] ?? '',
          done: done,
          matchReason: reason,
        ));
      }
    }

    return results;
  }
}
// ═══════════════════════════════════════════════════════
// PASTE THIS CLASS into main.dart
// Place it BELOW the LocalSearchService class
// and ABOVE the TideAIApp class
// ═══════════════════════════════════════════════════════

class TideAIQueryEngine {
  /// Understands natural language queries like:
  /// "what should I do this week"
  /// "what's urgent today"
  /// "show me pending study tasks"
  /// Then filters tasks from Firestore by date + category + priority.

  static List<Map<String, dynamic>> answer({
    required String query,
    required List<Map<String, dynamic>> tasks,
  }) {
    final q = query.toLowerCase().trim();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // ── Detect intent from query ──────────────

    // "this week" / "this weekend" / "7 days"
    final bool isWeekQuery = q.contains('week') ||
        q.contains('weekend') ||
        q.contains('7 days') ||
        q.contains('seven days') ||
        q.contains('next 7');

    // "today" / "right now" / "urgent" / "overdue"
    final bool isTodayQuery = q.contains('today') ||
        q.contains('right now') ||
        q.contains('urgent') ||
        q.contains('overdue') ||
        q.contains('due now') ||
        q.contains('immediate');

    // "tomorrow"
    final bool isTomorrowQuery = q.contains('tomorrow');

    // Category hints
    String? categoryHint;
    if (q.contains('study') || q.contains('assignment') || q.contains('exam')) {
      categoryHint = 'Study';
    } else if (q.contains('work') ||
        q.contains('office') ||
        q.contains('meeting')) {
      categoryHint = 'Work';
    } else if (q.contains('health') ||
        q.contains('doctor') ||
        q.contains('gym')) {
      categoryHint = 'Health';
    } else if (q.contains('finance') ||
        q.contains('bill') ||
        q.contains('pay')) {
      categoryHint = 'Finance';
    } else if (q.contains('personal') || q.contains('family')) {
      categoryHint = 'Personal';
    }

    // Priority hints
    bool wantsHigh = q.contains('important') ||
        q.contains('urgent') ||
        q.contains('critical') ||
        q.contains('high');

    // ── Filter tasks ──────────────────────────

    List<Map<String, dynamic>> results = [];

    for (final task in tasks) {
      final done = task['done'] == true;
      if (done) continue; // skip completed tasks

      final category = (task['category'] ?? '').toString();
      final priority = (task['priority'] ?? '').toString();
      final dueDateStr = (task['dueDate'] ?? '').toString().trim();

      DateTime? dueDate;
      if (dueDateStr.isNotEmpty) {
        try {
          final parts = dueDateStr.split('/');
          if (parts.length == 3) {
            dueDate = DateTime(
              int.parse(parts[2]),
              int.parse(parts[1]),
              int.parse(parts[0]),
            );
          }
        } catch (_) {}
      }

      bool matches = false;
      String reason = '';

      if (isTodayQuery) {
        // Tasks due today or overdue
        if (dueDate != null &&
            (dueDate.isAtSameMomentAs(today) || dueDate.isBefore(today))) {
          matches = true;
          reason = dueDate.isAtSameMomentAs(today)
              ? 'Due today'
              : 'Overdue — needs immediate attention';
        } else if (priority == 'High') {
          matches = true;
          reason = 'High priority task';
        }
      } else if (isTomorrowQuery) {
        final tomorrow = today.add(const Duration(days: 1));
        if (dueDate != null && dueDate.isAtSameMomentAs(tomorrow)) {
          matches = true;
          reason = 'Due tomorrow';
        }
      } else if (isWeekQuery) {
        // Tasks due within next 7 days
        final weekEnd = today.add(const Duration(days: 7));
        if (dueDate != null &&
            (dueDate.isAtSameMomentAs(today) ||
                (dueDate.isAfter(today) &&
                    (dueDate.isBefore(weekEnd) ||
                        dueDate.isAtSameMomentAs(weekEnd))))) {
          matches = true;
          final diff = dueDate.difference(today).inDays;
          reason = diff == 0
              ? 'Due today'
              : 'Due in $diff day${diff == 1 ? '' : 's'}';
        } else if (priority == 'High' && dueDate == null) {
          // High priority tasks with no date also show in week view
          matches = true;
          reason = 'High priority — no deadline set';
        }
      } else if (wantsHigh) {
        if (priority == 'High') {
          matches = true;
          reason = 'High priority task';
        }
      } else {
        // Generic query — show all pending tasks
        matches = true;
        reason = 'Pending task';
      }

      // Apply category filter on top if detected
      if (matches && categoryHint != null && category != categoryHint) {
        matches = false;
      }

      if (matches) {
        results.add({
          ...task,
          '_reason': reason,
        });
      }
    }

    // ── Sort: overdue first, then by due date, then high priority ──
    results.sort((a, b) {
      final da = _parseDate(a['dueDate'] ?? '');
      final db = _parseDate(b['dueDate'] ?? '');
      final pOrder = {'High': 0, 'Medium': 1, 'Low': 2};
      final pa = pOrder[a['priority']] ?? 1;
      final pb = pOrder[b['priority']] ?? 1;

      if (da != null && db != null) return da.compareTo(db);
      if (da != null) return -1;
      if (db != null) return 1;
      return pa.compareTo(pb);
    });

    return results;
  }

  static DateTime? _parseDate(String s) {
    try {
      final parts = s.split('/');
      if (parts.length != 3) return null;
      return DateTime(
        int.parse(parts[2]),
        int.parse(parts[1]),
        int.parse(parts[0]),
      );
    } catch (_) {
      return null;
    }
  }

  /// Human-readable summary of what the AI understood
  static String interpretQuery(String query) {
    final q = query.toLowerCase();
    if (q.contains('week') || q.contains('weekend')) {
      return "Showing tasks due within the next 7 days";
    }
    if (q.contains('today') || q.contains('urgent') || q.contains('overdue')) {
      return "Showing today's urgent and overdue tasks";
    }
    if (q.contains('tomorrow')) {
      return "Showing tasks due tomorrow";
    }
    if (q.contains('important') ||
        q.contains('high') ||
        q.contains('critical')) {
      return "Showing high priority tasks";
    }
    return "Showing relevant pending tasks";
  }
}

// =====================
// APP ROOT
// =====================

class TideAIApp extends StatelessWidget {
  const TideAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "TIDE AI",
      theme: ThemeData(
        scaffoldBackgroundColor: TideColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: TideColors.background,
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          hintStyle: TextStyle(
            color: TideColors.muted,
          ),
          labelStyle: TextStyle(
            color: TideColors.muted,
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// =====================
// SPLASH SCREEN
// =====================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    Timer(
      const Duration(seconds: 5),
      () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const WelcomeScreen(),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(
              Icons.bolt,
              color: TideColors.primary,
              size: 90,
            ),
            SizedBox(height: 20),
            Text(
              "TIDE AI",
              style: TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================
// WELCOME SCREEN
// =====================

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  Future<String> getUsername() async {
    User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return "User";
    }

    DocumentSnapshot snapshot = await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .get();

    if (snapshot.exists) {
      return snapshot["username"];
    }

    return "User";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.auto_awesome,
              color: TideColors.primary,
              size: 110,
            ),
            const SizedBox(height: 30),
            const Text(
              "Welcome To TIDE AI",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Your personal productivity companion",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: TideColors.muted,
              ),
            ),
            const SizedBox(height: 40),
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TideColors.primary,
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LoginScreen(),
                        ),
                      );
                    },
                    child: const Text("Login"),
                  ),
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RegisterScreen(),
                        ),
                      );
                    },
                    child: const Text("Create Account"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =====================
// MAIN SHELL
// =====================

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;

  final pages = const [
    DashboardScreen(),
    TasksScreen(),
    CalendarScreen(),
    AiAssistantScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[index],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: index,
        backgroundColor: TideColors.card,
        selectedItemColor: TideColors.primary,
        unselectedItemColor: TideColors.muted,
        onTap: (value) {
          setState(() {
            index = value;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.task_alt),
            label: "Tasks",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month),
            label: "Calendar",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.auto_awesome),
            label: "AI",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}

// =====================
// DASHBOARD SCREEN
// =====================

String getGreeting() {
  final hour = DateTime.now().hour;

  if (hour < 12) {
    return "Good Morning";
  } else if (hour < 17) {
    return "Good Afternoon";
  } else {
    return "Good Evening";
  }
}

Future<String> getUserName() async {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) {
    return "User";
  }

  DocumentSnapshot doc =
      await FirebaseFirestore.instance.collection("users").doc(user.uid).get();

  if (doc.exists) {
    return doc["username"] ?? "User";
  }

  return "User";
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int criticalTasks = 0;
  int completedTasks = 0;
  int totalTasks = 0;
  int productivity = 0;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkOverdueTasks();
      loadDashboardStats();
    });
  }

  Future<void> loadDashboardStats() async {
    final snapshot = await FirestoreService().tasksCollection().get();

    int total = snapshot.docs.length;

    int completed = snapshot.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

      return data["done"] == true;
    }).length;

    int critical = snapshot.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

      if (data["done"] == true) {
        return false;
      }

      if (data["priority"] != "High") {
        return false;
      }

      final dueDate = (data["dueDate"] ?? "").toString();

      if (dueDate.isEmpty) {
        return false;
      }

      try {
        final parts = dueDate.split("/");

        final taskDate = DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );

        final today = DateTime.now();

        return taskDate.year == today.year &&
            taskDate.month == today.month &&
            taskDate.day == today.day;
      } catch (e) {
        return false;
      }
    }).length;

    setState(() {
      totalTasks = total;

      completedTasks = completed;

      criticalTasks = critical;

      productivity = total == 0 ? 0 : ((completed / total) * 100).round();
    });
  }

  Future<void> checkOverdueTasks() async {
    debugPrint("=== CHECKING OVERDUE TASKS ===");

    final snapshot = await FirestoreService().tasksCollection().get();

    debugPrint("Tasks found: ${snapshot.docs.length}");

    List<String> overdueTasks = [];

    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;

      debugPrint("Task: ${data["title"]}");

      if (data["done"] == true) {
        debugPrint("Skipped (already done)");
        continue;
      }

      String dueDate = (data["dueDate"] ?? "").toString().trim();

      debugPrint("Due date: $dueDate");

      if (dueDate.isEmpty) {
        debugPrint("Skipped (no due date)");
        continue;
      }

      try {
        List<String> parts = dueDate.split("/");

        if (parts.length != 3) {
          debugPrint("Invalid date format");
          continue;
        }

        DateTime taskDate = DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );

        final today = DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
        );

        final due = DateTime(
          taskDate.year,
          taskDate.month,
          taskDate.day,
        );

        debugPrint("Today: $today");
        debugPrint("Due: $due");

        if (today.isAfter(due)) {
          overdueTasks.add(data["title"] ?? "Untitled Task");
          debugPrint("OVERDUE!");
        }
      } catch (e) {
        debugPrint("Date parse error: $e");
      }
    }

    if (overdueTasks.isNotEmpty && mounted) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: Colors.black,
          title: const Text(
            "⚠ Overdue Tasks",
            style: TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            overdueTasks.join("\n"),
            style: const TextStyle(
              color: Colors.white,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "OK",
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    debugPrint("=== CHECK COMPLETE ===");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: TideColors.primary,
        child: const Icon(Icons.add),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CreateTaskScreen(),
            ),
          );
        },
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FutureBuilder<String>(
                  future: getUserName(),
                  builder: (context, snapshot) {
                    String name = snapshot.data ?? "User";

                    return Text(
                      "${getGreeting()}, $name",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  "${_monthName(DateTime.now().month)} ${DateTime.now().year}",
                  style: const TextStyle(
                    color: TideColors.muted,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: TideColors.accent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "You have $criticalTasks Critical Tasks",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Before Noon",
                        style: TextStyle(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _dashboardCard("$productivity%", "Productivity"),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _dashboardCard("$completedTasks", "Completed"),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  "Upcoming Tasks",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                StreamBuilder<QuerySnapshot>(
                  stream: FirestoreService().getTasks(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }

                    final tasks = snapshot.data!.docs.where((task) {
                      final data = task.data() as Map<String, dynamic>;

                      return data["done"] != true;
                    }).toList();
                    if (tasks.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: TideColors.card,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          "No tasks available.\nTap + to create your first task.",
                          style: TextStyle(color: Colors.white),
                        ),
                      );
                    }

                    return Column(
                      children: tasks.take(3).map((task) {
                        final data = task.data() as Map<String, dynamic>;
                        return _taskPreview(
                          data["title"] ?? "Untitled Task",
                          data["category"] ?? "",
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December"
    ];

    return months[month - 1];
  }

  Widget _dashboardCard(String value, String label) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TideColors.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: TideColors.primary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: TideColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _taskPreview(String title, String date) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TideColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.task_alt, color: TideColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          Text(
            date,
            style: const TextStyle(color: TideColors.muted),
          ),
        ],
      ),
    );
  }
}

// =====================
// TASK SCREEN
// =====================

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<Task> tasks = [];

  String selectedCategory = "All";
  String searchText = "";
  final FirestoreService firestoreService = FirestoreService();

  // Local smart search state
  List<Map<String, dynamic>> _allTaskMaps = [];
  List<SmartSearchResult> _smartResults = [];
  bool _smartSearchActive = false;

// Tide AI Query state
  List<Map<String, dynamic>> _aiQueryResults = [];
  bool _aiQueryActive = false;
  String _aiQuerySummary = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void load() {
    firestoreService.getTasks().listen((snapshot) {
      setState(() {
        tasks = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return Task(
            id: doc.id,
            title: data["title"] ?? "",
            category: data["category"] ?? "Work",
            priority: data["priority"] ?? "Medium",
            done: data["done"] ?? false,
          );
        }).toList();

        // Keep a raw map version for local smart search
        _allTaskMaps = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            'id': doc.id,
            'title': data["title"] ?? "",
            'category': data["category"] ?? "Work",
            'priority': data["priority"] ?? "Medium",
            'done': data["done"] ?? false,
          };
        }).toList();
      });
    });
  }

  /// Runs the local (no-API) smart search via [LocalSearchService].
  void runAiQuery() {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    final results = TideAIQueryEngine.answer(
      query: query,
      tasks: _allTaskMaps,
    );

    setState(() {
      _aiQueryActive = true;
      _aiQueryResults = results;
      _aiQuerySummary = TideAIQueryEngine.interpretQuery(query);
      _smartSearchActive = false;
      _smartResults = [];
    });
  }

  /// Runs local smart search via [LocalSearchService] as user types.
  void runSmartSearch(String value) {
    if (value.trim().isEmpty) {
      setState(() {
        _smartSearchActive = false;
        _smartResults = [];
      });
      return;
    }

    final results = LocalSearchService.search(
      query: value,
      tasks: _allTaskMaps,
    );

    setState(() {
      _smartSearchActive = true;
      _smartResults = results;
      _aiQueryActive = false;
      _aiQueryResults = [];
      _aiQuerySummary = '';
    });
  }

  void toggle(Task task) {
    setState(() {
      task.done = !task.done;
    });

    if (task.id != null) {
      firestoreService.updateTask(task.id!, task.done);
    }
  }

  Future<void> editTaskDialog(Task task) async {
    final titleController = TextEditingController(text: task.title);
    final dueDateController = TextEditingController();

    // Load existing due date from Firestore
    if (task.id != null) {
      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection("tasks")
          .doc(task.id)
          .get();
      if (doc.exists) {
        dueDateController.text = doc["dueDate"] ?? "";
      }
    }

    String editCategory = task.category;
    String editPriority = task.priority;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: TideColors.card,
              title: const Text(
                "Edit Task",
                style: TextStyle(color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    TextField(
                      controller: titleController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Task Title",
                        hintStyle: const TextStyle(color: TideColors.muted),
                        filled: true,
                        fillColor: TideColors.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Category
                    const Text(
                      "Category",
                      style: TextStyle(color: TideColors.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: editCategory,
                      dropdownColor: TideColors.card,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: TideColors.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: [
                        "Work",
                        "Study",
                        "Personal",
                        "Health",
                        "Finance",
                        "Shopping"
                      ]
                          .map((item) => DropdownMenuItem(
                                value: item,
                                child: Text(item),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setStateDialog(() {
                          editCategory = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Priority
                    const Text(
                      "Priority",
                      style: TextStyle(color: TideColors.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: ["High", "Medium", "Low"].map((p) {
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: editPriority == p
                                    ? TideColors.primary
                                    : TideColors.background,
                              ),
                              onPressed: () {
                                setStateDialog(() {
                                  editPriority = p;
                                });
                              },
                              child: Text(
                                p,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Due Date
                    const Text(
                      "Due Date",
                      style: TextStyle(color: TideColors.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: dueDateController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "DD/MM/YYYY",
                        hintStyle: const TextStyle(color: TideColors.muted),
                        filled: true,
                        fillColor: TideColors.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: TideColors.muted),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TideColors.primary,
                  ),
                  onPressed: () async {
                    await firestoreService.editTask(
                      task.id!,
                      titleController.text,
                      editCategory,
                      editPriority,
                    );
                    await FirebaseFirestore.instance
                        .collection("users")
                        .doc(FirebaseAuth.instance.currentUser!.uid)
                        .collection("tasks")
                        .doc(task.id)
                        .update({"dueDate": dueDateController.text});
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = tasks.where((task) {
      final categoryMatch =
          selectedCategory == "All" || task.category == selectedCategory;
      final searchMatch =
          task.title.toLowerCase().contains(searchText.toLowerCase());
      return categoryMatch && searchMatch;
    }).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "My Tasks",
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),

            // ── Search Bar ──
            TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: TideColors.card,
                hintText: "Search tasks or ask AI...",
                prefixIcon: const Icon(Icons.search, color: Colors.white),
                suffixIcon: (_smartSearchActive || _aiQueryActive)
                    ? IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            searchText = "";
                            _smartSearchActive = false;
                            _smartResults = [];
                            _aiQueryActive = false;
                            _aiQueryResults = [];
                            _aiQuerySummary = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  searchText = value;
                  _aiQueryActive = false;
                  _aiQueryResults = [];
                  _aiQuerySummary = '';
                });
                runSmartSearch(value);
              },
            ),
            const SizedBox(height: 10),

            // ── Ask Tide AI Button ──
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Text("✨", style: TextStyle(fontSize: 16)),
                label: const Text(
                  "Ask Tide AI",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: TideColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: runAiQuery,
              ),
            ),
            const SizedBox(height: 10),

            // ── AI Result Banner ──
            if (_aiQueryActive) ...[
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: TideColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: TideColors.primary.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Text("🤖", style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _aiQueryResults.isEmpty
                            ? "No tasks found for that query."
                            : "$_aiQuerySummary — ${_aiQueryResults.length} task(s) found",
                        style: const TextStyle(
                          color: TideColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            // ── Smart Search Banner ──
            if (_smartSearchActive && !_aiQueryActive) ...[
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: TideColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: TideColors.primary.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Text("✨", style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Text(
                      _smartResults.isEmpty
                          ? "No smart results found"
                          : "AI found ${_smartResults.length} result(s)",
                      style: const TextStyle(
                        color: TideColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            // ── Category Filter Chips ──
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  "All",
                  "Work",
                  "Study",
                  "Personal",
                  "Health",
                  "Finance",
                  "Shopping",
                ].map((cat) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: selectedCategory == cat,
                      selectedColor: TideColors.primary,
                      onSelected: (_) {
                        setState(() {
                          selectedCategory = cat;
                          _smartSearchActive = false;
                          _smartResults = [];
                          _aiQueryActive = false;
                          _aiQueryResults = [];
                          _aiQuerySummary = '';
                          searchText = "";
                          _searchController.clear();
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // ── Task List ──
            Expanded(
              child: _aiQueryActive
                  ? _buildAiQueryList()
                  : _smartSearchActive
                      ? _buildSmartResultsList()
                      : _buildNormalList(filtered),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiQueryList() {
    if (_aiQueryResults.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("🤖", style: TextStyle(fontSize: 48)),
              SizedBox(height: 16),
              Text(
                "No tasks found for your query.\nTry: 'what should I do this week'\nor 'show urgent tasks'",
                textAlign: TextAlign.center,
                style: TextStyle(color: TideColors.muted, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _aiQueryResults.length,
      itemBuilder: (context, index) {
        final data = _aiQueryResults[index];
        final reason = data['_reason'] ?? '';
        final task = tasks.firstWhere(
          (t) => t.id == data['id'],
          orElse: () => Task(
            id: data['id'],
            title: data['title'] ?? '',
            category: data['category'] ?? '',
            priority: data['priority'] ?? 'Medium',
            done: data['done'] ?? false,
          ),
        );
        return _buildTaskCard(task, matchReason: reason);
      },
    );
  }

  // Renders local smart search results
  Widget _buildSmartResultsList() {
    if (_smartResults.isEmpty) {
      return const Center(
        child: Text(
          "No matching tasks found.\nTry: 'study', 'urgent', 'pending'",
          textAlign: TextAlign.center,
          style: TextStyle(color: TideColors.muted),
        ),
      );
    }

    return ListView.builder(
      itemCount: _smartResults.length,
      itemBuilder: (context, index) {
        final r = _smartResults[index];
        final task = tasks.firstWhere(
          (t) => t.id == r.taskId,
          orElse: () => Task(
            id: r.taskId,
            title: r.title,
            category: r.category,
            priority: r.priority,
            done: r.done,
          ),
        );
        return _buildTaskCard(task, matchReason: r.matchReason);
      },
    );
  }

  // Renders normal filtered list
  Widget _buildNormalList(List<Task> filtered) {
    if (filtered.isEmpty) {
      return const Center(
        child: Text(
          "No tasks found.",
          style: TextStyle(color: TideColors.muted),
        ),
      );
    }
    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) => _buildTaskCard(filtered[index]),
    );
  }

  // Single task card (used by both lists)
  Widget _buildTaskCard(Task task, {String? matchReason}) {
    return GestureDetector(
      onTap: () => toggle(task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: TideColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              task.done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: task.done ? TideColors.success : TideColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Left side: title + match reason ──
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // ── Due date display ──
                            StreamBuilder<DocumentSnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection("users")
                                  .doc(FirebaseAuth.instance.currentUser!.uid)
                                  .collection("tasks")
                                  .doc(task.id)
                                  .snapshots(),
                              builder: (context, snapshot) {
                                String dueDate = "";
                                if (snapshot.hasData && snapshot.data!.exists) {
                                  final data = snapshot.data!.data()
                                      as Map<String, dynamic>;
                                  dueDate =
                                      (data["dueDate"] ?? "").toString().trim();
                                }
                                if (dueDate.isEmpty)
                                  return const SizedBox.shrink();
                                return Row(
                                  children: [
                                    const Icon(
                                      Icons.calendar_today,
                                      size: 11,
                                      color: TideColors.muted,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      dueDate,
                                      style: const TextStyle(
                                        color: TideColors.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            // ✨ Show match reason in smart search mode
                            if (matchReason != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                "✨ $matchReason",
                                style: const TextStyle(
                                  color: TideColors.primary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // ── Right side: category chip + priority chip stacked ──
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Category chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _categoryColor(task.category)
                                  .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _categoryColor(task.category)
                                    .withOpacity(0.5),
                              ),
                            ),
                            child: Text(
                              "${_categoryIcon(task.category)} ${task.category}",
                              style: TextStyle(
                                color: _categoryColor(task.category),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Priority chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _priorityColor(task.priority)
                                  .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _priorityColor(task.priority)
                                    .withOpacity(0.5),
                              ),
                            ),
                            child: Text(
                              "${_priorityIcon(task.priority)} ${task.priority}",
                              style: TextStyle(
                                color: _priorityColor(task.priority),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => editTaskDialog(task),
                        icon: const Icon(Icons.edit,
                            size: 20, color: Colors.green),
                      ),
                      IconButton(
                        onPressed: () async {
                          String shareId = await firestoreService.shareTask(
                            taskId: task.id!,
                            title: task.title,
                            category: task.category,
                            priority: task.priority,
                          );
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SharedTaskScreen(
                                userId: FirebaseAuth.instance.currentUser!.uid,
                                taskId: task.id!,
                                shareId: shareId,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.share,
                            size: 20, color: Colors.blue),
                      ),
                      IconButton(
                        onPressed: () {
                          if (task.id != null) {
                            firestoreService.deleteTask(task.id!);
                          }
                        },
                        icon: const Icon(Icons.delete,
                            size: 20, color: Colors.red),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'Study':
        return const Color(0xFF7C3AED); // purple
      case 'Work':
        return const Color(0xFF2563EB); // blue
      case 'Health':
        return const Color(0xFF16A34A); // green
      case 'Finance':
        return const Color(0xFFD97706); // amber
      case 'Shopping':
        return const Color(0xFFDB2777); // pink
      case 'Personal':
        return const Color(0xFF0891B2); // cyan
      default:
        return const Color(0xFF9CA3AF); // grey
    }
  }

  String _categoryIcon(String category) {
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

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'High':
        return const Color(0xFFE53935); // red
      case 'Medium':
        return const Color(0xFFFF9800); // orange
      case 'Low':
        return const Color(0xFF43A047); // green
      default:
        return const Color(0xFF9CA3AF); // grey
    }
  }

  String _priorityIcon(String priority) {
    switch (priority) {
      case 'High':
        return '🔴';
      case 'Medium':
        return '🟡';
      case 'Low':
        return '🟢';
      default:
        return '⚪';
    }
  }
}

// =====================
// CREATE TASK SCREEN
// =====================

class CreateTaskScreen extends StatefulWidget {
  const CreateTaskScreen({super.key});

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  final dueDateController = TextEditingController();

  String category = "Personal";
  String priority = "Medium";
  final FirestoreService firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    // Rebuild when title or due date changes so AiPriorityBanner updates live
    titleController.addListener(_onFieldChanged);
    dueDateController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    setState(() {
      // Recalculate AI category whenever title changes
      if (titleController.text.trim().isNotEmpty) {
        category = AiCategoryService.predictCategory(
          titleController.text.trim(),
        );
      }
    });
  }

  Future<void> saveTask() async {
    if (titleController.text.trim().isEmpty) return;

    // Final category prediction before saving
    category = AiCategoryService.predictCategory(
      titleController.text.trim(),
    );

    await firestoreService.addTask(
      title: titleController.text.trim(),
      category: category,
      priority: priority,
      dueDate: dueDateController.text.trim(),
      done: false,
    );

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  DateTime? _parseDueDate(String text) {
    try {
      final parts = text.split('/');
      if (parts.length != 3) return null;
      return DateTime(
        int.parse(parts[2]),
        int.parse(parts[1]),
        int.parse(parts[0]),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    titleController.removeListener(_onFieldChanged);
    dueDateController.removeListener(_onFieldChanged);
    titleController.dispose();
    descriptionController.dispose();
    dueDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Create Task"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Title
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: "Task Title",
                ),
              ),
              const SizedBox(height: 20),

              // Description
              TextField(
                controller: descriptionController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: "Task Description",
                ),
              ),
              const SizedBox(height: 20),

              // AI Category display
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: TideColors.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: TideColors.primary),
                    const SizedBox(width: 10),
                    Text(
                      "AI Category: $category",
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Due Date (placed before AiPriorityBanner so it can use the date)
              TextField(
                controller: dueDateController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: "Due Date (DD/MM/YYYY)",
                ),
              ),
              const SizedBox(height: 20),

              // ── AI Priority Banner (local, no API) ──
              AiPriorityBanner(
                taskTitle: titleController.text,
                dueDate: dueDateController.text.isNotEmpty
                    ? _parseDueDate(dueDateController.text)
                    : null,
                category: category,
                onAccept: (suggested) {
                  setState(() {
                    priority = suggested;
                  });
                },
              ),

              // Priority buttons
              Row(
                children: [
                  _priorityButton("High"),
                  const SizedBox(width: 10),
                  _priorityButton("Medium"),
                  const SizedBox(width: 10),
                  _priorityButton("Low"),
                ],
              ),
              const SizedBox(height: 30),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TideColors.primary,
                  ),
                  onPressed: saveTask,
                  child: const Text("Save Task"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _priorityButton(String value) {
    return Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              priority == value ? TideColors.primary : TideColors.card,
        ),
        onPressed: () {
          setState(() {
            priority = value;
          });
        },
        child: Text(value),
      ),
    );
  }
}

// =====================
// CALENDAR SCREEN
// =====================

int _priorityOrder(String p) {
  switch (p.trim().toLowerCase()) {
    case "high":
      return 0;

    case "medium":
      return 1;

    case "low":
      return 2;

    default:
      return 2;
  }
}

String _higherPriorityOf(String a, String b) {
  return _priorityOrder(a) <= _priorityOrder(b) ? a : b;
}

Color priorityBgColor(String priority) {
  switch (priority.trim().toLowerCase()) {
    case "high":
      return const Color(0xFFFF4D4F);

    case "medium":
      return const Color(0xFFFF9F1C);

    case "low":
      return const Color(0xFF22C55E);

    default:
      return Colors.transparent;
  }
}

Color priorityTextColor(String priority) {
  switch (priority) {
    case "High":
      return Colors.white;
    case "Medium":
      return Colors.black;
    case "Low":
      return Colors.black;
    default:
      return Colors.white;
  }
}

class PriorityDots extends StatelessWidget {
  final List<String> priorities;

  const PriorityDots({super.key, required this.priorities});

  @override
  Widget build(BuildContext context) {
    if (priorities.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: priorities.map((p) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: priorityBgColor(p),
            shape: BoxShape.circle,
          ),
        );
      }).toList(),
    );
  }
}

class CalendarDayCell extends StatelessWidget {
  final int day;
  final bool isToday;
  final List<String> priorities;

  const CalendarDayCell({
    super.key,
    required this.day,
    required this.isToday,
    required this.priorities,
  });

  String? get highestPriority {
    if (priorities.isEmpty) return null;

    final normalized = priorities.map((p) {
      return p.trim().substring(0, 1).toUpperCase() +
          p.trim().substring(1).toLowerCase();
    }).toList();

    return normalized.reduce(_higherPriorityOf);
  }

  List<String> get additionalPriorities {
    if (priorities.isEmpty) return [];
    final highest = highestPriority!;
    final rest = List<String>.from(priorities)..remove(highest);
    final unique = rest.toSet().toList()
      ..sort((a, b) => _priorityOrder(a).compareTo(_priorityOrder(b)));
    return unique;
  }

  @override
  Widget build(BuildContext context) {
    final main = highestPriority;
    final extras = additionalPriorities;

    BoxDecoration decoration;
    Color textColor;

    if (isToday && main != null) {
      // Today has tasks — show priority color as a circle
      decoration = BoxDecoration(
        color: priorityBgColor(main),
        shape: BoxShape.circle,
      );
      textColor = priorityTextColor(main);
    } else if (isToday) {
      // Today has no tasks — plain white circle
      decoration = const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      );
      textColor = Colors.black;
    } else if (main != null) {
      decoration = BoxDecoration(
        color: priorityBgColor(main),
        borderRadius: BorderRadius.circular(8),
      );
      textColor = priorityTextColor(main);
    } else {
      decoration = const BoxDecoration();
      textColor = Colors.white;
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: decoration,
          child: Center(
            child: Text(
              "$day",
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        PriorityDots(priorities: extras),
      ],
    );
  }
}

class CalendarGrid extends StatelessWidget {
  final DateTime focusedMonth;
  final Map<String, List<String>> allTaskDates;

  const CalendarGrid({
    super.key,
    required this.focusedMonth,
    required this.allTaskDates,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final firstDayOfMonth = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final startWeekday = firstDayOfMonth.weekday % 7;
    final daysInMonth =
        DateTime(focusedMonth.year, focusedMonth.month + 1, 0).day;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: startWeekday + daysInMonth,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 4,
        crossAxisSpacing: 2,
        childAspectRatio: 0.75,
      ),
      itemBuilder: (context, index) {
        if (index < startWeekday) return const SizedBox.shrink();

        final day = index - startWeekday + 1;
        final thisDate = DateTime(focusedMonth.year, focusedMonth.month, day);
        final isToday = thisDate.year == today.year &&
            thisDate.month == today.month &&
            thisDate.day == today.day;

        final dateKey =
            "${day.toString().padLeft(2, '0')}/${focusedMonth.month.toString().padLeft(2, '0')}/${focusedMonth.year}";

        final priorities = allTaskDates[dateKey] ?? [];

        return CalendarDayCell(
          day: day,
          isToday: isToday,
          priorities: priorities,
        );
      },
    );
  }
}

class PriorityLegend extends StatelessWidget {
  const PriorityLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: TideColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _legendItem(Colors.white, "Today", isCircle: true),
              _vDivider(),
              _legendItem(const Color(0xFFFF4D4F), "High\nPriority"),
              _vDivider(),
              _legendItem(const Color(0xFFFF9F1C), "Medium\nPriority"),
              _vDivider(),
              _legendItem(const Color(0xFF22C55E), "Low\nPriority"),
              _vDivider(),
              _legendItem(Colors.transparent, "No\nTasks", isBorderOnly: true),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _dot(const Color(0xFFFF4D4F)),
              const SizedBox(width: 4),
              _dot(const Color(0xFFFF9F1C)),
              const SizedBox(width: 4),
              _dot(const Color(0xFF22C55E)),
              const SizedBox(width: 8),
              const Text(
                "Dots indicate additional tasks\nwith different priorities on the same day.",
                style: TextStyle(
                  color: TideColors.muted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _vDivider() {
    return Container(
      width: 1,
      height: 50,
      color: TideColors.muted.withOpacity(0.3),
    );
  }

  Widget _legendItem(
    Color color,
    String label, {
    bool isCircle = false,
    bool isBorderOnly = false,
  }) {
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isBorderOnly ? Colors.transparent : color,
            shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: isCircle ? null : BorderRadius.circular(8),
            border: isBorderOnly
                ? Border.all(color: TideColors.muted, width: 1.5)
                : null,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: TideColors.muted, fontSize: 10),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime focusedMonth = DateTime.now();
  Map<String, List<String>> allTaskDates = {};

  @override
  void initState() {
    super.initState();
    loadTaskDates();
  }

  void loadTaskDates() {
    FirestoreService().getTasks().listen((snapshot) {
      Map<String, Set<String>> map = {};

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final dueDate = (data["dueDate"] ?? "").toString().trim();
        final priority = (data["priority"] ?? "Low").toString();
        final done = data["done"] ?? false;

        if (dueDate.isEmpty || done == true) continue;

        map.putIfAbsent(dueDate, () => {});
        map[dueDate]!.add(priority);
        debugPrint("CALENDAR TASK => Date: $dueDate Priority: $priority");
      }

      final result = map.map((key, value) {
        final sorted = value.toList()
          ..sort((a, b) => _priorityOrder(a).compareTo(_priorityOrder(b)));
        return MapEntry(key, sorted);
      });

      if (mounted) {
        setState(() {
          allTaskDates = result;
        });
      }
    });
  }

  void _previousMonth() {
    setState(() {
      focusedMonth = DateTime(focusedMonth.year, focusedMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      focusedMonth = DateTime(focusedMonth.year, focusedMonth.month + 1);
    });
  }

  String _monthName(int month) {
    const months = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December"
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Calendar",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: TideColors.card,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: _previousMonth,
                          icon: const Icon(Icons.chevron_left,
                              color: Colors.white),
                        ),
                        Text(
                          "${_monthName(focusedMonth.month)} ${focusedMonth.year}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          onPressed: _nextMonth,
                          icon: const Icon(Icons.chevron_right,
                              color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children:
                          ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                              .map(
                                (d) => SizedBox(
                                  width: 36,
                                  child: Text(
                                    d,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: TideColors.muted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                    const SizedBox(height: 8),
                    CalendarGrid(
                      focusedMonth: focusedMonth,
                      allTaskDates: allTaskDates,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const PriorityLegend(),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================
// PROFILE SCREEN
// =====================

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String username = "User";
  int totalTasks = 0;
  int completedTasks = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadProfileData();
  }

  Future<void> loadProfileData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .get();

    String fetchedName = "User";
    if (userDoc.exists) {
      fetchedName = userDoc["username"] ?? "User";
    }

    final tasksSnapshot = await FirestoreService().tasksCollection().get();
    int total = tasksSnapshot.docs.length;
    int done = tasksSnapshot.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return data["done"] == true;
    }).length;

    setState(() {
      username = fetchedName;
      totalTasks = total;
      completedTasks = done;
      loading = false;
    });
  }

  void logout(BuildContext context) {
    FirebaseAuth.instance.signOut();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  String getSuccessRate() {
    if (totalTasks == 0) return "0%";
    final rate = (completedTasks / totalTasks * 100).round();
    return "$rate%";
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: loading
          ? const Center(
              child: CircularProgressIndicator(
                color: TideColors.primary,
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  const CircleAvatar(
                    radius: 55,
                    backgroundColor: TideColors.primary,
                    child: Icon(
                      Icons.person,
                      size: 60,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    username,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    completedTasks == 0
                        ? "Just getting started!"
                        : completedTasks < 5
                            ? "Building momentum 🚀"
                            : completedTasks < 15
                                ? "Productivity Explorer ⚡"
                                : "Task Master 🏆",
                    style: const TextStyle(color: TideColors.muted),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Expanded(child: _statCard("$totalTasks", "Total Tasks")),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _statCard("$completedTasks", "Completed")),
                      const SizedBox(width: 12),
                      Expanded(child: _statCard(getSuccessRate(), "Success")),
                    ],
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TideColors.accent,
                      ),
                      onPressed: () => logout(context),
                      icon: const Icon(Icons.logout),
                      label: const Text("Logout"),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _statCard(String value, String label) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TideColors.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: TideColors.primary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: TideColors.muted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
