// lib/ai_assistant_screen.dart
// Tide AI Assistant — Local AI Dashboard + Chat (No API)

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firestore_service.dart';

// ── Colors ──────────────────────────────────
class _C {
  static const background = Color(0xFF0F1017);
  static const card = Color(0xFF1B1D2A);
  static const primary = Color(0xFFFF9D4D);
  static const accent = Color(0xFFFF7A45);
  static const muted = Color(0xFF9CA3AF);
  static const success = Color(0xFF4CAF50);
  static const danger = Color(0xFFE57373);
}

// ══════════════════════════════════════════
// DATA MODEL
// ══════════════════════════════════════════

class _AiInsight {
  final String username;
  final int total;
  final int pending;
  final int completed;
  final String? todayTask;
  final String? todayReason;
  final List<String> upcoming;
  final String topCategory;
  final String productivityTip;
  final double completionRate;

  const _AiInsight({
    required this.username,
    required this.total,
    required this.pending,
    required this.completed,
    this.todayTask,
    this.todayReason,
    required this.upcoming,
    required this.topCategory,
    required this.productivityTip,
    required this.completionRate,
  });
}

// ══════════════════════════════════════════
// CHAT MESSAGE MODEL
// ══════════════════════════════════════════

class _ChatMessage {
  final String text;
  final bool isUser;
  _ChatMessage({required this.text, required this.isUser});
}

// ══════════════════════════════════════════
// LOCAL ANALYSER
// ══════════════════════════════════════════

class _TideAnalyser {
  static Future<_AiInsight> analyse() async {
    final user = FirebaseAuth.instance.currentUser;
    String username = "User";
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .get();
      if (doc.exists) username = doc["username"] ?? "User";
    }

    final snapshot = await FirestoreService().tasksCollection().get();
    final docs = snapshot.docs;

    int total = docs.length;
    int completed = 0;
    int pending = 0;

    String? todayTask;
    String? todayReason;

    final List<Map<String, dynamic>> pendingTasks = [];
    final Map<String, int> categoryCount = {};

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final done = data["done"] == true;
      final title = (data["title"] ?? "Untitled").toString();
      final category = (data["category"] ?? "Personal").toString();
      final priority = (data["priority"] ?? "Medium").toString();
      final dueDateStr = (data["dueDate"] ?? "").toString().trim();

      categoryCount[category] = (categoryCount[category] ?? 0) + 1;

      if (done) {
        completed++;
      } else {
        pending++;
        pendingTasks.add({
          "title": title,
          "priority": priority,
          "dueDate": dueDateStr,
        });

        if (dueDateStr.isNotEmpty) {
          try {
            final parts = dueDateStr.split("/");
            if (parts.length == 3) {
              final due = DateTime(
                int.parse(parts[2]),
                int.parse(parts[1]),
                int.parse(parts[0]),
              );
              if (due.isAtSameMomentAs(today) || due.isBefore(today)) {
                if (todayTask == null || priority == "High") {
                  todayTask = title;
                  todayReason = due.isAtSameMomentAs(today)
                      ? "Due today and ${priority.toLowerCase()} priority"
                      : "Overdue — should be completed immediately";
                }
              }
            }
          } catch (_) {}
        }
      }
    }

    const pOrder = {"High": 0, "Medium": 1, "Low": 2};
    pendingTasks.sort((a, b) {
      final pa = pOrder[a["priority"]] ?? 1;
      final pb = pOrder[b["priority"]] ?? 1;
      return pa.compareTo(pb);
    });

    final upcoming =
        pendingTasks.take(3).map((t) => t["title"] as String).toList();

    String topCategory = "Study";
    if (categoryCount.isNotEmpty) {
      topCategory = categoryCount.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
    }

    final rate = total == 0 ? 0.0 : completed / total;
    String tip;
    if (total == 0) {
      tip = "Start by creating your first task.";
    } else if (rate >= 0.8) {
      tip = "Excellent work! You are completing most of your tasks.";
    } else if (rate >= 0.5) {
      tip = "Good progress. Focus on high-priority $topCategory tasks next.";
    } else if (pending > 5) {
      tip =
          "You have many pending tasks. Try completing 2–3 $topCategory tasks today.";
    } else {
      tip = "Most of your tasks belong to $topCategory. Focus on those first.";
    }

    return _AiInsight(
      username: username,
      total: total,
      pending: pending,
      completed: completed,
      todayTask: todayTask,
      todayReason: todayReason,
      upcoming: upcoming,
      topCategory: topCategory,
      productivityTip: tip,
      completionRate: rate,
    );
  }

  // ── Chat reply engine ─────────────────────────────────────────────────────
  static Future<String> chatReply(
    String query,
    List<Map<String, dynamic>> taskMaps,
    String username,
  ) async {
    final q = query.toLowerCase().trim();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final pending = taskMaps.where((t) => t['done'] != true).toList();
    final done = taskMaps.where((t) => t['done'] == true).toList();

    // ── Most overdue task ──────────────────────────────────────────────────
    if (q.contains('overdue') ||
        (q.contains('most') && q.contains('overdue'))) {
      List<Map<String, dynamic>> overdue = [];
      for (final t in pending) {
        final ds = (t['dueDate'] ?? '').toString().trim();
        if (ds.isEmpty) continue;
        try {
          final parts = ds.split('/');
          if (parts.length == 3) {
            final due = DateTime(
                int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
            if (due.isBefore(today)) overdue.add({...t, '_due': due});
          }
        } catch (_) {}
      }
      if (overdue.isEmpty) {
        return "🎉 Great news, $username! You have no overdue tasks right now.";
      }
      overdue.sort(
          (a, b) => (a['_due'] as DateTime).compareTo(b['_due'] as DateTime));
      final t = overdue.first;
      final daysLate = today.difference(t['_due'] as DateTime).inDays;
      return "⚠️ Your most overdue task is:\n\n\"${t['title']}\"\n\nIt was due ${t['dueDate']} ($daysLate day${daysLate == 1 ? '' : 's'} ago). Please complete it as soon as possible!";
    }

    // ── Summarize this week ────────────────────────────────────────────────
    if (q.contains('summar') || q.contains('this week') || q.contains('week')) {
      final total = taskMaps.length;
      final doneCount = done.length;
      final pendingCount = pending.length;
      final rate = total == 0 ? 0 : ((doneCount / total) * 100).round();

      final categories =
          taskMaps.map((t) => t['category'] ?? 'Personal').toSet().join(', ');

      final highPending = pending.where((t) => t['priority'] == 'High').length;

      return "📊 Here's your week summary, $username:\n\n"
          "• Total tasks: $total\n"
          "• ✅ Completed: $doneCount\n"
          "• ⏳ Pending: $pendingCount\n"
          "• 🔴 High priority pending: $highPending\n"
          "• 📁 Categories: $categories\n"
          "• 🏆 Completion rate: $rate%\n\n"
          "${rate >= 70 ? 'Excellent progress! Keep it up! 🚀' : rate >= 40 ? 'Good effort! Focus on your high priority tasks next.' : 'You have a lot pending. Try to knock out 2–3 tasks today!'}";
    }

    // ── Suggest tasks for project ──────────────────────────────────────────
    if (q.contains('suggest') ||
        q.contains('project') ||
        q.contains('what should') ||
        q.contains('recommend')) {
      if (pending.isEmpty) {
        return "🎉 You've completed everything, $username! Time to add new goals.";
      }
      const pOrder = {'High': 0, 'Medium': 1, 'Low': 2};
      final sorted = List<Map<String, dynamic>>.from(pending)
        ..sort((a, b) =>
            (pOrder[a['priority']] ?? 1).compareTo(pOrder[b['priority']] ?? 1));
      final top = sorted.take(3).toList();
      final buffer = StringBuffer();
      buffer.writeln(
          "🎯 Here are the top tasks I suggest you focus on, $username:\n");
      for (int i = 0; i < top.length; i++) {
        final t = top[i];
        final icons = ['🥇', '🥈', '🥉'];
        buffer.writeln(
            "${icons[i]} ${t['title']} (${t['priority']} priority, ${t['category']})");
      }
      buffer.writeln(
          "\nStart with the first one — high priority tasks should be tackled first! 💪");
      return buffer.toString();
    }

    // ── How many tasks ─────────────────────────────────────────────────────
    if (q.contains('how many') || q.contains('count') || q.contains('total')) {
      return "📋 You have ${taskMaps.length} task(s) in total:\n"
          "• ✅ Completed: ${done.length}\n"
          "• ⏳ Pending: ${pending.length}";
    }

    // ── Today's tasks ──────────────────────────────────────────────────────
    if (q.contains('today') || q.contains('right now')) {
      final todayTasks = <String>[];
      for (final t in pending) {
        final ds = (t['dueDate'] ?? '').toString().trim();
        if (ds.isEmpty) continue;
        try {
          final parts = ds.split('/');
          if (parts.length == 3) {
            final due = DateTime(
                int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
            if (due.isAtSameMomentAs(today)) todayTasks.add(t['title']);
          }
        } catch (_) {}
      }
      if (todayTasks.isEmpty) {
        return "✅ No tasks are due today, $username. You're on track!";
      }
      return "📅 Tasks due today:\n\n${todayTasks.map((t) => '• $t').join('\n')}";
    }

    // ── High priority ──────────────────────────────────────────────────────
    if (q.contains('urgent') ||
        q.contains('important') ||
        q.contains('high priority')) {
      final high = pending.where((t) => t['priority'] == 'High').toList();
      if (high.isEmpty) {
        return "✅ You have no high priority pending tasks right now, $username!";
      }
      return "🔴 Your high priority pending tasks:\n\n${high.map((t) => '• ${t['title']}').join('\n')}";
    }

    // ── Hello / Hi ─────────────────────────────────────────────────────────
    if (q.startsWith('hi') || q.startsWith('hello') || q.startsWith('hey')) {
      return "👋 Hello, $username! I'm Tide AI. Try asking me:\n\n"
          "• \"What's my most overdue task?\"\n"
          "• \"Summarize this week\"\n"
          "• \"Suggest tasks for my project\"\n"
          "• \"How many tasks do I have?\"\n"
          "• \"Show today's tasks\"";
    }

    // ── Default fallback ───────────────────────────────────────────────────
    return "🤖 I'm not sure about that, $username. Try asking:\n\n"
        "• \"What's my most overdue task?\"\n"
        "• \"Summarize this week\"\n"
        "• \"Suggest tasks for my project\"\n"
        "• \"Show today's tasks\"\n"
        "• \"Show urgent tasks\"";
  }
}

// ══════════════════════════════════════════
// MAIN SCREEN — with tab bar for Dashboard + Chat
// ══════════════════════════════════════════

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  _AiInsight? _insight;
  bool _loading = true;

  // Chat state
  final List<_ChatMessage> _messages = [];
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _chatTyping = false;

  // All tasks (for chat)
  List<Map<String, dynamic>> _taskMaps = [];
  String _username = "User";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();

    // Welcome message
    _messages.add(_ChatMessage(
      text:
          "👋 Hi! I'm Tide AI. Ask me anything about your tasks!\n\nTry:\n• \"What's my most overdue task?\"\n• \"Summarize this week\"\n• \"Suggest tasks for my project\"",
      isUser: false,
    ));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final insight = await _TideAnalyser.analyse();

    // Also load raw task maps for chat
    final snapshot = await FirestoreService().tasksCollection().get();
    final maps = snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return {
        'id': doc.id,
        'title': data['title'] ?? '',
        'category': data['category'] ?? 'Personal',
        'priority': data['priority'] ?? 'Medium',
        'dueDate': data['dueDate'] ?? '',
        'done': data['done'] ?? false,
      };
    }).toList();

    if (mounted) {
      setState(() {
        _insight = insight;
        _taskMaps = maps;
        _username = insight.username;
        _loading = false;
      });
    }
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Good Morning";
    if (hour < 17) return "Good Afternoon";
    return "Good Evening";
  }

  // ── Chat send ────────────────────────────────────────────────────────────

  void _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _chatController.clear();
      _chatTyping = true;
    });
    _scrollToBottom();

    // Small delay so it feels like the AI is thinking
    await Future.delayed(const Duration(milliseconds: 700));

    final reply = await _TideAnalyser.chatReply(text, _taskMaps, _username);

    if (mounted) {
      setState(() {
        _messages.add(_ChatMessage(text: reply, isUser: false));
        _chatTyping = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.background,
      appBar: AppBar(
        backgroundColor: _C.background,
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Text("✨", style: TextStyle(fontSize: 20)),
            SizedBox(width: 8),
            Text(
              "Tide AI Assistant",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _load,
            tooltip: "Refresh",
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _C.primary,
          labelColor: _C.primary,
          unselectedLabelColor: _C.muted,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined), text: "Dashboard"),
            Tab(icon: Icon(Icons.chat_bubble_outline), text: "Chat"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Tab 1: Dashboard ────────────────────────────────────────────
          _loading
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: _C.primary),
                      SizedBox(height: 16),
                      Text(
                        "AI is analysing your tasks...",
                        style: TextStyle(color: _C.muted),
                      ),
                    ],
                  ),
                )
              : _buildDashboard(_insight!),

          // ── Tab 2: Chat ─────────────────────────────────────────────────
          _buildChat(),
        ],
      ),
    );
  }

  // ════════════════════════════════════════
  // DASHBOARD TAB
  // ════════════════════════════════════════

  Widget _buildDashboard(_AiInsight insight) {
    return RefreshIndicator(
      color: _C.primary,
      backgroundColor: _C.card,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _greetingBanner(insight),
            const SizedBox(height: 20),
            _sectionTitle("📊 Task Overview"),
            const SizedBox(height: 10),
            _overviewCard(insight),
            const SizedBox(height: 20),
            _sectionTitle("🎯 Today's Recommendation"),
            const SizedBox(height: 10),
            _todayCard(insight),
            const SizedBox(height: 20),
            _sectionTitle("📅 Upcoming Tasks"),
            const SizedBox(height: 10),
            _upcomingCard(insight),
            const SizedBox(height: 20),
            _sectionTitle("💡 Productivity Insight"),
            const SizedBox(height: 10),
            _insightCard(insight),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _greetingBanner(_AiInsight insight) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_C.accent, _C.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$_greeting, ${insight.username} 👋",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            insight.pending == 0
                ? "You have no pending tasks. Great job! 🎉"
                : "You have ${insight.pending} pending task${insight.pending > 1 ? 's' : ''} to tackle today.",
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _overviewCard(_AiInsight insight) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("You have:",
              style: TextStyle(color: _C.muted, fontSize: 13)),
          const SizedBox(height: 16),
          Row(
            children: [
              _statBubble("${insight.total}", "Total", _C.primary),
              const SizedBox(width: 12),
              _statBubble("${insight.pending}", "Pending", _C.accent),
              const SizedBox(width: 12),
              _statBubble("${insight.completed}", "Done", _C.success),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: insight.total == 0 ? 0 : insight.completionRate,
              backgroundColor: _C.background,
              color: _C.success,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            insight.total == 0
                ? "No tasks yet."
                : "${(insight.completionRate * 100).round()}% completed",
            style: const TextStyle(color: _C.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _statBubble(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: _C.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _todayCard(_AiInsight insight) {
    final hasTask = insight.todayTask != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: hasTask
            ? _C.danger.withOpacity(0.12)
            : _C.success.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasTask
              ? _C.danger.withOpacity(0.4)
              : _C.success.withOpacity(0.3),
        ),
      ),
      child: hasTask
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Complete first:",
                    style: TextStyle(color: _C.muted, fontSize: 13)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text("🔴", style: TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(insight.todayTask!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.info_outline, color: _C.muted, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text("Reason: ${insight.todayReason}",
                          style:
                              const TextStyle(color: _C.muted, fontSize: 12)),
                    ),
                  ],
                ),
              ],
            )
          : const Row(
              children: [
                Text("✅", style: TextStyle(fontSize: 22)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "No urgent tasks due today. You're on track!",
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _upcomingCard(_AiInsight insight) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: _C.card, borderRadius: BorderRadius.circular(20)),
      child: insight.upcoming.isEmpty
          ? const Text("No pending tasks. All caught up! 🎉",
              style: TextStyle(color: Colors.white))
          : Column(
              children: insight.upcoming.asMap().entries.map((entry) {
                final i = entry.key;
                final title = entry.value;
                final icons = ["🥇", "🥈", "🥉"];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      Text(icons[i], style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(title,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _insightCard(_AiInsight insight) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: _C.card, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text("📌", style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    "Most of your tasks belong to: ${insight.topCategory}",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _C.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _C.primary.withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("💡", style: TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text("Suggestion: ${insight.productivityTip}",
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(text,
        style: const TextStyle(
            color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold));
  }

  // ════════════════════════════════════════
  // CHAT TAB
  // ════════════════════════════════════════

  Widget _buildChat() {
    return Column(
      children: [
        // ── Message list ──────────────────────────────────────────────────
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length + (_chatTyping ? 1 : 0),
            itemBuilder: (context, index) {
              // Typing indicator
              if (_chatTyping && index == _messages.length) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _C.card,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("✨", style: TextStyle(fontSize: 14)),
                        SizedBox(width: 8),
                        Text("Tide AI is thinking...",
                            style: TextStyle(color: _C.muted, fontSize: 13)),
                      ],
                    ),
                  ),
                );
              }

              final msg = _messages[index];
              return Align(
                alignment:
                    msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                  ),
                  decoration: BoxDecoration(
                    color: msg.isUser ? _C.primary : _C.card,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    msg.text,
                    style: TextStyle(
                      color: msg.isUser ? Colors.white : Colors.white,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // ── Quick suggestion chips ────────────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              "Most overdue task",
              "Summarize this week",
              "Suggest tasks",
              "Today's tasks",
              "Urgent tasks",
            ].map((chip) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  label: Text(chip,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12)),
                  backgroundColor: _C.card,
                  side: BorderSide(color: _C.primary.withOpacity(0.5)),
                  onPressed: () {
                    _chatController.text = chip;
                    _sendMessage();
                  },
                ),
              );
            }).toList(),
          ),
        ),

        // ── Input bar ─────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          decoration: const BoxDecoration(
            color: _C.card,
            border: Border(top: BorderSide(color: Color(0xFF2A2D3E))),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  style: const TextStyle(color: Colors.white),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: InputDecoration(
                    hintText: "Ask anything about your tasks...",
                    hintStyle: const TextStyle(color: _C.muted, fontSize: 13),
                    filled: true,
                    fillColor: _C.background,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _sendMessage,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: _C.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
