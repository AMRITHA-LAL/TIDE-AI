import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  Future<User?> register(
    String username,
    String email,
    String password,
  ) async {
    UserCredential result = await auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    User? user = result.user;

    if (user != null) {
      await firestore.collection("users").doc(user.uid).set({
        "username": username,
        "email": email,
      });
    }

    return user;
  }

  Future<User?> login(
    String email,
    String password,
  ) async {
    UserCredential result = await auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    return result.user;
  }

  Future<void> logout() async {
    await auth.signOut();
  }
}
