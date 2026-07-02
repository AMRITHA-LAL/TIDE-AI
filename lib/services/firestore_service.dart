import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  final FirebaseAuth auth = FirebaseAuth.instance;

  CollectionReference tasksCollection() {
    final uid = auth.currentUser!.uid;

    return firestore.collection("users").doc(uid).collection("tasks");
  }

  Future<void> addTask({
    required String title,
    required String category,
    required String priority,
    required String dueDate,
    required bool done,
  }) async {
    await tasksCollection().add({
      "title": title,
      "category": category,
      "priority": priority,
      "dueDate": dueDate,
      "done": done,
    });
  }

  Stream<QuerySnapshot> getTasks() {
    return tasksCollection().snapshots();
  }

  Future<void> updateTask(
    String id,
    bool done,
  ) async {
    await tasksCollection().doc(id).update({
      "done": done,
    });
  }

  Future<void> editTask(
    String id,
    String title,
    String category,
    String priority,
  ) async {
    await tasksCollection().doc(id).update({
      "title": title,
      "category": category,
      "priority": priority,
    });
  }

  Future<void> deleteTask(String id) async {
    await tasksCollection().doc(id).delete();
  }

  Future<String> shareTask({
    required String taskId,
    required String title,
    required String category,
    required String priority,
  }) async {
    final uid = auth.currentUser!.uid;

    DocumentReference doc = await firestore
        .collection("users")
        .doc(uid)
        .collection("tasks")
        .doc(taskId)
        .collection("shares")
        .add({
      "ownerId": uid,
      "title": title,
      "category": category,
      "priority": priority,
      "done": false,
    });

    return doc.id;
  }
}
