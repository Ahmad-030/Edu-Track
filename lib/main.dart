import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'admin.dart';
import 'teacher.dart';

// ═══════════════════════════════════════════════════════════════════
//  ENTRY
// ═══════════════════════════════════════════════════════════════════

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  await Firebase.initializeApp();
  runApp(const EduTrackApp());
}

// ═══════════════════════════════════════════════════════════════════
//  FIREBASE SERVICE
// ═══════════════════════════════════════════════════════════════════

class FB {
  static final auth = FirebaseAuth.instance;
  static final db   = FirebaseFirestore.instance;

  static User? get user => auth.currentUser;

  static Future<void> signOut() => auth.signOut();

  static Future<String?> login(String email, String pw) async {
    try {
      await auth.signInWithEmailAndPassword(email: email.trim(), password: pw);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Login failed';
    }
  }

  /// Creates a teacher Firebase Auth account using a secondary app instance
  /// so the admin stays signed in on the primary instance throughout.
  static Future<String> createTeacherAuthAccount(String email, String password) async {
    FirebaseApp? secondaryApp;
    try {
      // Always delete and recreate to avoid stale secondary-app auth events
      try { await Firebase.app('secondary').delete(); } catch (_) {}

      secondaryApp = await Firebase.initializeApp(
        name: 'secondary',
        options: Firebase.app().options,
      );

      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final cred = await secondaryAuth.createUserWithEmailAndPassword(
        email: email.trim(), password: password,
      );
      final uid = cred.user!.uid;
      await secondaryAuth.signOut();
      await secondaryApp.delete(); // prevent stray auth-state events
      return uid;
    } on FirebaseAuthException {
      try { await secondaryApp?.delete(); } catch (_) {}
      rethrow;
    } catch (e) {
      try { await secondaryApp?.delete(); } catch (_) {}
      rethrow;
    }
  }

  // ── Firestore paths ──────────────────────────────────────────────
  static CollectionReference get schools       => db.collection('schools');
  static DocumentReference   school(String id) => schools.doc(id);

  static CollectionReference teachers(String sid)   => school(sid).collection('teachers');
  static CollectionReference classes(String sid)    => school(sid).collection('classes');
  static CollectionReference students(String sid)   => school(sid).collection('students');
  static CollectionReference attendance(String sid) => school(sid).collection('attendance');

  static CollectionReference get users => db.collection('users');
  static Future<Map<String, dynamic>?> userMeta(String uid) async {
    final doc = await users.doc(uid).get();
    return doc.exists ? doc.data() as Map<String, dynamic> : null;
  }
}

// ═══════════════════════════════════════════════════════════════════
//  MODELS
// ═══════════════════════════════════════════════════════════════════

class School {
  final String id, name, adminName, email;
  const School({required this.id, required this.name, required this.adminName, required this.email});
  factory School.fromDoc(DocumentSnapshot d) {
    final j = d.data() as Map<String, dynamic>;
    return School(id: d.id, name: j['name'], adminName: j['adminName'], email: j['email']);
  }
}

class Teacher {
  final String id, name, subject, phone, email;
  final String? classId;
  const Teacher({required this.id, required this.name, required this.subject,
    required this.phone, required this.email, this.classId});
  factory Teacher.fromDoc(DocumentSnapshot d) {
    final j = d.data() as Map<String, dynamic>;
    return Teacher(id: d.id, name: j['name'], subject: j['subject'],
        phone: j['phone'], email: j['email'], classId: j['classId']);
  }
}

class SchoolClass {
  final String id, name;
  final String? teacherId;
  const SchoolClass({required this.id, required this.name, this.teacherId});
  factory SchoolClass.fromDoc(DocumentSnapshot d) {
    final j = d.data() as Map<String, dynamic>;
    return SchoolClass(id: d.id, name: j['name'], teacherId: j['teacherId']);
  }
}

class Student {
  final String id, classId, name, rollNumber, parentPhone;
  final double monthlyFee;
  final bool feePaid;
  const Student({required this.id, required this.classId, required this.name,
    required this.rollNumber, required this.parentPhone,
    required this.monthlyFee, this.feePaid = false});
  factory Student.fromDoc(DocumentSnapshot d) {
    final j = d.data() as Map<String, dynamic>;
    return Student(id: d.id, classId: j['classId'], name: j['name'],
        rollNumber: j['rollNumber'], parentPhone: j['parentPhone'],
        monthlyFee: (j['monthlyFee'] as num).toDouble(), feePaid: j['feePaid'] ?? false);
  }
}

class AttendanceRecord {
  final String id, classId, date;
  final Map<String, bool> attendance;
  const AttendanceRecord({required this.id, required this.classId,
    required this.date, required this.attendance});
  factory AttendanceRecord.fromDoc(DocumentSnapshot d) {
    final j = d.data() as Map<String, dynamic>;
    return AttendanceRecord(id: d.id, classId: j['classId'], date: j['date'],
        attendance: Map<String, bool>.from(j['attendance'] ?? {}));
  }
}

// ═══════════════════════════════════════════════════════════════════
//  SESSION
// ═══════════════════════════════════════════════════════════════════

class Session {
  final String uid, role, schoolId;
  final String? teacherId;
  const Session({required this.uid, required this.role,
    required this.schoolId, this.teacherId});
  bool get isAdmin => role == 'admin';
}

final sessionNotifier = ValueNotifier<Session?>(null);
Session? get currentSession => sessionNotifier.value;

// Global flag — set true before intentional signOut so _AuthGate ignores
// the repeated null-user events Firebase fires (can fire 2-3 times).
bool suppressAuthEvents = false;

// ═══════════════════════════════════════════════════════════════════
//  THEME
// ═══════════════════════════════════════════════════════════════════

class T {
  static const Color blue        = Color(0xFF2563EB);
  static const Color blueMid     = Color(0xFF3B82F6);
  static const Color blueLight   = Color(0xFFEFF6FF);
  static const Color blueDark    = Color(0xFF1D4ED8);
  static const Color green       = Color(0xFF059669);
  static const Color greenLight  = Color(0xFFECFDF5);
  static const Color greenMid    = Color(0xFF10B981);
  static const Color red         = Color(0xFFDC2626);
  static const Color redLight    = Color(0xFFFEF2F2);
  static const Color redMid      = Color(0xFFEF4444);
  static const Color amber       = Color(0xFFD97706);
  static const Color amberLight  = Color(0xFFFFFBEB);
  static const Color purple      = Color(0xFF7C3AED);
  static const Color purpleLight = Color(0xFFF5F3FF);
  static const Color purpleMid   = Color(0xFF8B5CF6);
  static const Color teal        = Color(0xFF0891B2);
  static const Color tealLight   = Color(0xFFECFEFF);
  static const Color tealMid     = Color(0xFF06B6D4);
  static const Color bg          = Color(0xFFF8FAFC);
  static const Color surface     = Colors.white;
  static const Color ink         = Color(0xFF0F172A);
  static const Color inkMid      = Color(0xFF334155);
  static const Color inkLight    = Color(0xFF64748B);
  static const Color inkFaint    = Color(0xFF94A3B8);
  static const Color divider     = Color(0xFFE2E8F0);
  static const Color dividerFaint= Color(0xFFF1F5F9);

  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    fontFamily: 'Nunito',
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme.fromSeed(seedColor: blue, primary: blue, surface: surface),
    appBarTheme: const AppBarTheme(
      backgroundColor: surface, foregroundColor: ink, elevation: 0,
      scrolledUnderElevation: 0.5, centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Nunito', fontSize: 18,
          fontWeight: FontWeight.w800, color: ink, letterSpacing: -0.3),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: blue, foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
        textStyle: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: divider)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: divider)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: blue, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: red)),
      labelStyle: const TextStyle(fontFamily: 'Nunito', color: inkLight, fontSize: 14),
      hintStyle: const TextStyle(fontFamily: 'Nunito', color: inkFaint, fontSize: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface, indicatorColor: blueLight,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? const TextStyle(fontFamily: 'Nunito', fontSize: 11, fontWeight: FontWeight.w800, color: blue)
          : const TextStyle(fontFamily: 'Nunito', fontSize: 11, fontWeight: FontWeight.w600, color: inkLight)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: blue, foregroundColor: Colors.white, elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface, surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), elevation: 0,
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  APP ROOT
// ═══════════════════════════════════════════════════════════════════

class EduTrackApp extends StatelessWidget {
  const EduTrackApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'EduTrack', theme: T.theme, debugShowCheckedModeBanner: false,
    home: const AuthGate(),
  );
}

class AuthGate extends StatefulWidget {
  const AuthGate();
  @override State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _loading = true;
  StreamSubscription<User?>? _authSub;

  @override void initState() {
    super.initState();
    suppressAuthEvents = false;
    _authSub = FB.auth.authStateChanges().listen(_onAuthChanged);
  }

  @override void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _onAuthChanged(User? user) async {
    if (user == null) {
      // Suppress repeated sign-out callbacks Firebase fires after signOut()
      if (suppressAuthEvents) return;

      if (sessionNotifier.value != null) {
        suppressAuthEvents = true;
        sessionNotifier.value = null;
        // Reset after a short delay so future sign-outs still work
        Future.delayed(const Duration(seconds: 2), () => suppressAuthEvents = false);
      }
      if (mounted) setState(() => _loading = false);
      return;
    }

    // Reset suppress flag when a user signs in
    suppressAuthEvents = false;

    // Skip re-fetch if same user already in session
    if (sessionNotifier.value?.uid == user.uid) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    Map<String, dynamic>? meta = await FB.userMeta(user.uid);
    if (meta == null) {
      await Future.delayed(const Duration(seconds: 2));
      meta = await FB.userMeta(user.uid);
    }

    if (meta == null) {
      await FB.signOut();
      if (mounted) setState(() => _loading = false);
      return;
    }

    sessionNotifier.value = Session(
      uid:       user.uid,
      role:      meta['role'],
      schoolId:  meta['schoolId'],
      teacherId: meta['teacherId'],
    );
    if (mounted) setState(() => _loading = false);
  }

  @override Widget build(BuildContext context) {
    if (_loading) return const _SplashScreen();
    return ValueListenableBuilder<Session?>(
      valueListenable: sessionNotifier,
      builder: (_, session, __) {
        if (session == null) return const AuthScreen();
        if (session.isAdmin) return const AdminRoot();
        return const TeacherDashboard();
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  SPLASH
// ═══════════════════════════════════════════════════════════════════

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB), Color(0xFF3B82F6)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
      ),
      child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.school_rounded, size: 72, color: Colors.white),
        SizedBox(height: 20),
        Text('EduTrack', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900,
            color: Colors.white, letterSpacing: -1.5)),
        SizedBox(height: 32),
        CircularProgressIndicator(color: Colors.white54, strokeWidth: 2.5),
      ])),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  AUTH SCREEN
// ═══════════════════════════════════════════════════════════════════

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});
  @override Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height - 56),
        child: IntrinsicHeight(child: Column(children: [
          const Spacer(),
          Container(
            width: 88, height: 88,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [T.blueDark, T.blue, T.blueMid],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(26),
              boxShadow: [BoxShadow(color: T.blue.withOpacity(.35), blurRadius: 24, offset: const Offset(0, 10))],
            ),
            child: const Icon(Icons.school_rounded, size: 46, color: Colors.white),
          ),
          const SizedBox(height: 22),
          const Text('EduTrack', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900,
              color: T.ink, letterSpacing: -1.5)),
          const SizedBox(height: 6),
          const Text('Smart School Management', style: TextStyle(color: T.inkLight, fontSize: 15)),
          const Spacer(),
          SurfaceCard(child: Column(children: [
            const SizedBox(height: 6),
            const Text('Welcome 👋', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: T.ink)),
            const SizedBox(height: 4),
            const Text('Login to your school account', style: TextStyle(color: T.inkLight, fontSize: 14)),
            const SizedBox(height: 24),
            PrimaryButton(label: 'Login', icon: Icons.login_rounded,
                onTap: () => Navigator.push(context, slideRoute(const LoginScreen()))),
            const SizedBox(height: 12),
            OutlineButton(label: 'Register New School', icon: Icons.add_business_rounded,
                onTap: () => Navigator.push(context, slideRoute(const RegisterScreen()))),
            const SizedBox(height: 6),
          ])),
          const Spacer(),
        ])),
      ),
    )),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  LOGIN
// ═══════════════════════════════════════════════════════════════════

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass  = TextEditingController();
  bool _loading = false, _obscure = true;

  void _login() async {
    if (_email.text.trim().isEmpty || _pass.text.isEmpty) {
      _err('Please fill in all fields'); return;
    }
    setState(() => _loading = true);

    final err = await FB.login(_email.text, _pass.text);
    if (!mounted) return;
    if (err != null) { setState(() => _loading = false); _err(err); return; }

    final uid = FB.auth.currentUser!.uid;
    Map<String, dynamic>? meta = await FB.userMeta(uid);
    if (meta == null) {
      await Future.delayed(const Duration(seconds: 2));
      meta = await FB.userMeta(uid);
    }
    if (!mounted) return;

    if (meta == null) {
      await FB.signOut();
      setState(() => _loading = false);
      _err('Account not configured. Contact your administrator.');
      return;
    }

    sessionNotifier.value = Session(uid: uid, role: meta['role'],
        schoolId: meta['schoolId'], teacherId: meta['teacherId']);
    setState(() => _loading = false);
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      fadeRoute(meta['role'] == 'admin' ? const AdminRoot() : const TeacherDashboard()),
          (_) => false,
    );
  }

  void _err(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(buildSnack(m, isError: true));

  @override Widget build(BuildContext context) => Scaffold(
    appBar: buildAppBar('Login'),
    body: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 4),
      const Text('Welcome back!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
          color: T.ink, letterSpacing: -.5)),
      const SizedBox(height: 4),
      const Text('Sign in to your school account', style: TextStyle(color: T.inkLight, fontSize: 15)),
      const SizedBox(height: 32),
      SurfaceCard(child: Column(children: [
        LabeledField(ctrl: _email, label: 'Email Address',
            icon: Icons.email_outlined, type: TextInputType.emailAddress),
        const SizedBox(height: 14),
        TextField(
          controller: _pass, obscureText: _obscure,
          style: const TextStyle(fontFamily: 'Nunito', fontSize: 15),
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline_rounded, color: T.inkFaint, size: 20),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  color: T.inkFaint, size: 20),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 24),
        PrimaryButton(label: 'Sign In', onTap: _loading ? null : _login, loading: _loading),
      ])),
    ])),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  REGISTER SCHOOL
// ═══════════════════════════════════════════════════════════════════

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override State<RegisterScreen> createState() => _RegisterState();
}

class _RegisterState extends State<RegisterScreen> {
  final _name  = TextEditingController();
  final _admin = TextEditingController();
  final _email = TextEditingController();
  final _pass  = TextEditingController();
  bool _loading = false;

  void _register() async {
    if ([_name, _admin, _email, _pass].any((c) => c.text.trim().isEmpty)) {
      _err('Please fill in all fields'); return;
    }
    if (_pass.text.length < 6) { _err('Password must be at least 6 characters'); return; }
    setState(() => _loading = true);
    try {
      final cred = await FB.auth.createUserWithEmailAndPassword(
          email: _email.text.trim(), password: _pass.text);
      final uid = cred.user!.uid;
      await FB.users.doc(uid).set({'role': 'admin', 'schoolId': uid});
      await FB.schools.doc(uid).set({
        'name': _name.text.trim(), 'adminName': _admin.text.trim(),
        'email': _email.text.trim(), 'adminUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseAuthException catch (e) {
      if (mounted) _err(e.message ?? 'Registration failed');
    } catch (_) {
      if (mounted) _err('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _err(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(buildSnack(m, isError: true));

  @override Widget build(BuildContext context) => Scaffold(
    appBar: buildAppBar('Register School'),
    body: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Create Your School', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
          color: T.ink, letterSpacing: -.5)),
      const SizedBox(height: 4),
      const Text('Set up your school account in seconds',
          style: TextStyle(color: T.inkLight, fontSize: 15)),
      const SizedBox(height: 32),
      SurfaceCard(child: Column(children: [
        const SectionHeader('School Information'),
        LabeledField(ctrl: _name,  label: 'School Name', icon: Icons.school_outlined),
        const SizedBox(height: 12),
        LabeledField(ctrl: _admin, label: 'Admin Name',  icon: Icons.person_outline_rounded),
        const SizedBox(height: 20),
        const SectionHeader('Login Credentials'),
        LabeledField(ctrl: _email, label: 'Email Address', icon: Icons.email_outlined,
            type: TextInputType.emailAddress),
        const SizedBox(height: 12),
        LabeledField(ctrl: _pass, label: 'Password',
            icon: Icons.lock_outline_rounded, obscure: true),
        const SizedBox(height: 24),
        PrimaryButton(label: 'Create School 🚀', onTap: _loading ? null : _register,
            loading: _loading),
      ])),
    ])),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  SHARED DIALOGS
// ═══════════════════════════════════════════════════════════════════

void showDeleteDialog(BuildContext context, {required String title, required String name,
  required String description, required Future<void> Function() onConfirm}) {
  showDialog(context: context, barrierColor: Colors.black.withOpacity(.5),
      builder: (_) => _DeleteDialog(title: title, name: name,
          description: description, onConfirm: onConfirm));
}

class _DeleteDialog extends StatefulWidget {
  final String title, name, description;
  final Future<void> Function() onConfirm;
  const _DeleteDialog({required this.title, required this.name,
    required this.description, required this.onConfirm});
  @override State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  bool _loading = false;
  Future<void> _confirm() async {
    setState(() => _loading = true);
    await widget.onConfirm();
    setState(() => _loading = false);
    if (mounted) Navigator.pop(context);
  }

  @override Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 28),
    child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 64, height: 64,
          decoration: const BoxDecoration(color: T.redLight, shape: BoxShape.circle),
          child: const Icon(Icons.delete_outline_rounded, color: T.red, size: 30)),
      const SizedBox(height: 18),
      Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: T.ink)),
      const SizedBox(height: 8),
      Text(widget.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.inkMid),
          textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: T.redLight, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: T.amber, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.description,
                style: const TextStyle(fontSize: 13, color: T.inkMid, height: 1.4))),
          ])),
      const SizedBox(height: 22),
      Row(children: [
        Expanded(child: OutlineButton(label: 'Cancel', onTap: () => Navigator.pop(context))),
        const SizedBox(width: 12),
        Expanded(child: DangerButton(label: 'Delete', loading: _loading,
            onTap: _loading ? null : _confirm)),
      ]),
    ])),
  );
}

void showLogoutDialog(BuildContext context) {
  showDialog(context: context, barrierColor: Colors.black.withOpacity(.5),
      builder: (_) => const _LogoutDialog());
}

class _LogoutDialog extends StatelessWidget {
  const _LogoutDialog();
  @override Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 28),
    child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 64, height: 64,
          decoration: const BoxDecoration(color: T.blueLight, shape: BoxShape.circle),
          child: const Icon(Icons.logout_rounded, color: T.blue, size: 28)),
      const SizedBox(height: 18),
      const Text('Logout', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: T.ink)),
      const SizedBox(height: 8),
      const Text('Are you sure you want to log out?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: T.inkLight)),
      const SizedBox(height: 24),
      Row(children: [
        Expanded(child: OutlineButton(label: 'Cancel', onTap: () => Navigator.pop(context))),
        const SizedBox(width: 12),
        Expanded(child: PrimaryButton(label: 'Logout', onTap: () {
          Navigator.pop(context);
          suppressAuthEvents = true;
          sessionNotifier.value = null;
          FB.signOut();
        })),
      ]),
    ])),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  SHARED REUSABLE WIDGETS  (used by both admin.dart and teacher.dart)
// ═══════════════════════════════════════════════════════════════════

class SurfaceCard extends StatelessWidget {
  final Widget child;
  const SurfaceCard({super.key, required this.child});
  @override Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: T.divider),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 16, offset: const Offset(0, 4))]),
    padding: const EdgeInsets.all(20),
    child: child,
  );
}

class LabeledField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final TextInputType type;
  final bool obscure, readOnly;
  const LabeledField({super.key, required this.ctrl, required this.label,
    required this.icon, this.type = TextInputType.text,
    this.obscure = false, this.readOnly = false});
  @override Widget build(BuildContext context) => TextField(
    controller: ctrl, keyboardType: type, obscureText: obscure, readOnly: readOnly,
    style: const TextStyle(fontFamily: 'Nunito', fontSize: 15, color: T.ink),
    decoration: InputDecoration(labelText: label,
        prefixIcon: Icon(icon, color: T.inkFaint, size: 20)),
  );
}

class SectionHeader extends StatelessWidget {
  final String label;
  const SectionHeader(this.label, {super.key});
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
        color: T.inkFaint, letterSpacing: 1.0)),
  );
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool loading;
  final Color? color;
  const PrimaryButton({super.key, required this.label, this.icon, this.onTap,
    this.loading = false, this.color});
  @override Widget build(BuildContext context) {
    final c = color ?? T.blue;
    return SizedBox(width: double.infinity, height: 52,
      child: Material(color: onTap == null ? c.withOpacity(.5) : c,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14),
          splashColor: Colors.white.withOpacity(.2),
          child: Center(child: loading
              ? const SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, color: Colors.white, size: 18), const SizedBox(width: 8)],
            Text(label, style: const TextStyle(fontFamily: 'Nunito',
                fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white)),
          ])),
        ),
      ),
    );
  }
}

class OutlineButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  const OutlineButton({super.key, required this.label, this.icon, this.onTap});
  @override Widget build(BuildContext context) => SizedBox(width: double.infinity, height: 52,
    child: Material(color: Colors.white, borderRadius: BorderRadius.circular(14),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
              border: Border.all(color: T.divider, width: 1.5)),
          child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, color: T.inkMid, size: 18), const SizedBox(width: 8)],
            Text(label, style: const TextStyle(fontFamily: 'Nunito',
                fontWeight: FontWeight.w700, fontSize: 15, color: T.inkMid)),
          ])),
        ),
      ),
    ),
  );
}

class DangerButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  const DangerButton({super.key, required this.label, this.onTap, this.loading = false});
  @override Widget build(BuildContext context) => SizedBox(width: double.infinity, height: 52,
    child: Material(color: onTap == null ? T.red.withOpacity(.5) : T.red,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14),
        child: Center(child: loading
            ? const SizedBox(width: 22, height: 22,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : Text(label, style: const TextStyle(fontFamily: 'Nunito',
            fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white))),
      ),
    ),
  );
}

class CircleInitial extends StatelessWidget {
  final String name;
  final Color fg, bg;
  final double radius;
  const CircleInitial(this.name, this.fg, this.bg, {super.key, required this.radius});
  @override Widget build(BuildContext context) => CircleAvatar(
    radius: radius, backgroundColor: bg,
    child: Text(name[0].toUpperCase(),
        style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: radius * .85)),
  );
}

class InitialBubble extends StatelessWidget {
  final String name;
  const InitialBubble(this.name, {super.key});
  @override Widget build(BuildContext context) => Container(
    width: 46, height: 46,
    decoration: BoxDecoration(color: T.blueLight, shape: BoxShape.circle,
        border: Border.all(color: T.blue.withOpacity(.2), width: 2)),
    child: Center(child: Text(name[0].toUpperCase(),
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: T.blue))),
  );
}

class StatusChip extends StatelessWidget {
  final String label;
  final Color fg, bg;
  const StatusChip(this.label, this.fg, this.bg, {super.key});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800)),
  );
}

class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const InfoRow(this.icon, this.label, {super.key});
  @override Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 12, color: T.inkFaint), const SizedBox(width: 5),
    Flexible(child: Text(label, style: const TextStyle(color: T.inkLight, fontSize: 13),
        overflow: TextOverflow.ellipsis)),
  ]);
}

class StatTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const StatTile({super.key, required this.label, required this.value,
    required this.icon, required this.color});
  @override Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: T.divider),
        boxShadow: [BoxShadow(color: color.withOpacity(.05), blurRadius: 12, offset: const Offset(0, 4))]),
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Container(padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(.1), borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, color: color, size: 18)),
      const SizedBox(height: 12),
      Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
          color: color, letterSpacing: -1.0), maxLines: 1),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 12, color: T.inkLight,
          fontWeight: FontWeight.w600), maxLines: 1),
    ]),
  );
}

class ActionRow extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final Color color;
  final VoidCallback onTap;
  const ActionRow({super.key, required this.icon, required this.label,
    required this.sub, required this.color, required this.onTap});
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(color: Colors.white, borderRadius: BorderRadius.circular(16),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16),
        child: Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16),
              border: Border.all(color: T.divider)),
          child: Row(children: [
            Container(width: 44, height: 44,
                decoration: BoxDecoration(color: color.withOpacity(.1),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 22)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700,
                  fontSize: 15, color: T.ink)),
              Text(sub, style: const TextStyle(fontSize: 12, color: T.inkLight)),
            ])),
            Container(width: 28, height: 28,
                decoration: BoxDecoration(color: color.withOpacity(.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.arrow_forward_rounded, size: 14, color: color)),
          ]),
        ),
      ),
    ),
  );
}

class CardActions extends StatelessWidget {
  final IconData leftIcon, rightIcon;
  final String leftLabel, rightLabel;
  final Color leftColor, rightColor;
  final VoidCallback onLeft, onRight;
  const CardActions({super.key, required this.leftIcon, required this.leftLabel,
    required this.leftColor, required this.onLeft, required this.rightIcon,
    required this.rightLabel, required this.rightColor, required this.onRight});
  @override Widget build(BuildContext context) => IntrinsicHeight(child: Row(children: [
    Expanded(child: TextButton.icon(onPressed: onLeft,
        icon: Icon(leftIcon, size: 15, color: leftColor),
        label: Text(leftLabel, style: TextStyle(color: leftColor,
            fontWeight: FontWeight.w700, fontSize: 13)),
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 11)))),
    VerticalDivider(width: 1, color: T.dividerFaint),
    Expanded(child: TextButton.icon(onPressed: onRight,
        icon: Icon(rightIcon, size: 15, color: rightColor),
        label: Text(rightLabel, style: TextStyle(color: rightColor,
            fontWeight: FontWeight.w700, fontSize: 13)),
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 11)))),
  ]));
}

class AttBadge extends StatelessWidget {
  final String label;
  final Color color, bg;
  const AttBadge(this.label, this.color, this.bg, {super.key});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
    ]),
  );
}

class FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  const FilterPill(this.label, this.selected, this.onTap, this.color, {super.key});
  @override Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200), margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : T.divider),
          boxShadow: selected
              ? [BoxShadow(color: color.withOpacity(.2), blurRadius: 8, offset: const Offset(0, 2))]
              : []),
      child: Text(label, style: TextStyle(color: selected ? Colors.white : T.inkLight,
          fontWeight: FontWeight.w700, fontSize: 13)),
    ),
  );
}

class SearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const SearchField({super.key, required this.hint, required this.onChanged});
  @override Widget build(BuildContext context) => TextField(
    onChanged: onChanged,
    style: const TextStyle(fontFamily: 'Nunito', fontSize: 14),
    decoration: InputDecoration(hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded, color: T.inkFaint, size: 20),
        isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: T.divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: T.divider)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: T.blue, width: 2)),
        filled: true, fillColor: T.bg),
  );
}

class ClassDropdown extends StatelessWidget {
  final List<SchoolClass> classes;
  final String? value;
  final ValueChanged<String?> onChanged;
  const ClassDropdown({super.key, required this.classes, this.value, required this.onChanged});
  @override Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: T.bg, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.divider)),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: DropdownButtonHideUnderline(child: DropdownButton<String?>(
      value: value,
      hint: const Text('Class', style: TextStyle(fontSize: 13, color: T.inkLight, fontFamily: 'Nunito')),
      items: [
        const DropdownMenuItem(value: null,
            child: Text('All', style: TextStyle(fontFamily: 'Nunito', fontSize: 13))),
        ...classes.map((c) => DropdownMenuItem(value: c.id,
            child: Text(c.name, style: const TextStyle(fontFamily: 'Nunito', fontSize: 13)))),
      ],
      onChanged: onChanged,
      icon: const Icon(Icons.expand_more_rounded, size: 18, color: T.inkLight), isDense: true,
    )),
  );
}

class DatePickerField extends StatelessWidget {
  final String date;
  final ValueChanged<String> onChanged;
  const DatePickerField({super.key, required this.date, required this.onChanged});
  @override Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final p = await showDatePicker(context: context, initialDate: DateTime.now(),
          firstDate: DateTime(2020), lastDate: DateTime.now(),
          builder: (ctx, child) => Theme(data: Theme.of(ctx).copyWith(
              colorScheme: const ColorScheme.light(primary: T.blue, onPrimary: Colors.white)),
              child: child!));
      if (p != null) onChanged(DateFormat('yyyy-MM-dd').format(p));
    },
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: T.bg, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: T.divider)),
      child: Row(children: [
        const Icon(Icons.calendar_today_rounded, color: T.inkFaint, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(date, style: const TextStyle(fontFamily: 'Nunito',
            color: T.ink, fontWeight: FontWeight.w600))),
        const Icon(Icons.expand_more_rounded, color: T.inkFaint, size: 18),
      ]),
    ),
  );
}

class IconActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final double? size;
  const IconActionButton(this.icon, this.onTap, {super.key, this.color, this.size});
  @override Widget build(BuildContext context) => Material(color: T.bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10),
          child: Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: T.divider)),
              child: Icon(icon, color: color ?? T.inkMid, size: size ?? 20))));
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  const EmptyState(this.icon, this.title, this.sub, {super.key});
  @override Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(48),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80,
          decoration: BoxDecoration(color: T.bg, borderRadius: BorderRadius.circular(20),
              border: Border.all(color: T.divider)),
          child: Icon(icon, size: 38, color: T.divider)),
      const SizedBox(height: 18),
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: T.ink),
          textAlign: TextAlign.center),
      const SizedBox(height: 6),
      Text(sub, style: const TextStyle(color: T.inkLight, fontSize: 14), textAlign: TextAlign.center),
    ]),
  ));
}

class LogoutButton extends StatelessWidget {
  final VoidCallback onTap;
  const LogoutButton({super.key, required this.onTap});
  @override Widget build(BuildContext context) => Material(color: T.redLight,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap,
      child: Container(padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16),
            border: Border.all(color: T.red.withOpacity(.2))),
        child: const Row(children: [
          Icon(Icons.logout_rounded, color: T.red, size: 22),
          SizedBox(width: 14),
          Text('Logout', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: T.red)),
          Spacer(),
          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: T.red),
        ]),
      ),
    ),
  );
}

class FeeHeroBanner extends StatelessWidget {
  final double collected, total, pct;
  final int paid, unpaid;
  const FeeHeroBanner({super.key, required this.collected, required this.total,
    required this.paid, required this.unpaid, required this.pct});
  @override Widget build(BuildContext context) {
    final c = pct >= .8
        ? [const Color(0xFF047857), T.green]
        : pct >= .5 ? [T.blue, T.blueMid] : [T.red, T.redMid];
    return Container(
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: c, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: c[0].withOpacity(.3), blurRadius: 20, offset: const Offset(0, 8))]),
      padding: const EdgeInsets.all(18),
      child: Column(children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Rs ${fmtNum(collected)} collected',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
            Text('of Rs ${fmtNum(total)} total',
                style: TextStyle(color: Colors.white.withOpacity(.7), fontSize: 12)),
          ])),
          RingProgress(pct),
        ]),
        const SizedBox(height: 14),
        ClipRRect(borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: pct, minHeight: 6,
                backgroundColor: Colors.white.withOpacity(.2), color: Colors.white)),
        const SizedBox(height: 10),
        Row(children: [
          Text('$paid Paid', style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(width: 4),
          Text('·', style: TextStyle(color: Colors.white.withOpacity(.4))),
          const SizedBox(width: 4),
          Text('$unpaid Unpaid', style: TextStyle(color: Colors.white.withOpacity(.7),
              fontWeight: FontWeight.w600, fontSize: 13)),
          const Spacer(),
          Text('Rs ${fmtNum(total - collected)} pending',
              style: TextStyle(color: Colors.white.withOpacity(.65), fontSize: 12)),
        ]),
      ]),
    );
  }
}

class RingProgress extends StatelessWidget {
  final double pct;
  const RingProgress(this.pct, {super.key});
  @override Widget build(BuildContext context) => SizedBox(width: 54, height: 54,
    child: Stack(alignment: Alignment.center, children: [
      CircularProgressIndicator(value: pct, strokeWidth: 5,
          backgroundColor: Colors.white.withOpacity(.2), color: Colors.white),
      Text('${(pct * 100).round()}%',
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
    ]),
  );
}

class SegmentedTabs extends StatelessWidget {
  final List<String> labels;
  final List<int> counts;
  final List<Color> colors;
  final int selected;
  final ValueChanged<int> onTap;
  const SegmentedTabs({super.key, required this.labels, required this.counts,
    required this.colors, required this.selected, required this.onTap});
  @override Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: T.bg, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.divider)),
    padding: const EdgeInsets.all(4),
    child: Row(children: List.generate(labels.length, (i) => Expanded(child: GestureDetector(
      onTap: () => onTap(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected == i ? colors[i] : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: selected == i
              ? [BoxShadow(color: colors[i].withOpacity(.3), blurRadius: 8, offset: const Offset(0, 3))]
              : [],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${counts[i]}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900,
              color: selected == i ? Colors.white : T.ink)),
          Text(labels[i], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: selected == i ? Colors.white.withOpacity(.85) : T.inkLight)),
        ]),
      ),
    )))),
  );
}

class FeeCard extends StatelessWidget {
  final Student student;
  final VoidCallback onToggle;
  const FeeCard({super.key, required this.student, required this.onToggle});
  @override Widget build(BuildContext context) {
    final paid = student.feePaid;
    final ac = paid ? T.green : T.red;
    final bg = paid ? T.greenLight : T.redLight;
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ac.withOpacity(.2), width: 1.5),
          boxShadow: [BoxShadow(color: ac.withOpacity(.06), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 10), child: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            CircleAvatar(radius: 24, backgroundColor: bg,
                child: Text(student.name[0].toUpperCase(),
                    style: TextStyle(fontWeight: FontWeight.w900, color: ac, fontSize: 20))),
            Positioned(bottom: -1, right: -1,
                child: Container(width: 13, height: 13,
                    decoration: BoxDecoration(color: ac, shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2)))),
          ]),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(student.name, style: const TextStyle(fontWeight: FontWeight.w800,
                fontSize: 15, color: T.ink)),
            const SizedBox(height: 2),
            Row(children: [
              Icon(Icons.tag_rounded, size: 11, color: T.inkFaint), const SizedBox(width: 3),
              Text(student.rollNumber, style: const TextStyle(fontSize: 12, color: T.inkLight)),
            ]),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                child: Text('Rs ${fmtNum(student.monthlyFee)}',
                    style: TextStyle(color: ac, fontWeight: FontWeight.w900, fontSize: 14))),
            const SizedBox(height: 3),
            Text('per month', style: TextStyle(color: ac.withOpacity(.55), fontSize: 10)),
          ]),
        ])),
        GestureDetector(onTap: onToggle,
            child: Container(
              decoration: BoxDecoration(color: bg,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16))),
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(paid ? Icons.remove_circle_outline_rounded : Icons.check_circle_outline_rounded,
                    color: ac, size: 18),
                const SizedBox(width: 8),
                Text(paid ? 'Mark as Unpaid' : 'Mark as Paid ✓',
                    style: TextStyle(color: ac, fontWeight: FontWeight.w800, fontSize: 14)),
              ]),
            )),
      ]),
    );
  }
}

class BulkActionSheet extends StatelessWidget {
  final VoidCallback onMarkAllPaid, onMarkAllUnpaid;
  const BulkActionSheet({super.key, required this.onMarkAllPaid, required this.onMarkAllUnpaid});
  @override Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
    child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 14, bottom: 8),
          decoration: BoxDecoration(color: T.divider, borderRadius: BorderRadius.circular(2))),
      Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(children: [
            const Expanded(child: Text('Bulk Actions', style: TextStyle(fontSize: 17,
                fontWeight: FontWeight.w800, color: T.ink))),
            IconActionButton(Icons.close_rounded, () => Navigator.pop(context), color: T.inkLight),
          ])),
      const Divider(height: 1, color: T.divider),
      const SizedBox(height: 8),
      _SheetAction(icon: Icons.check_circle_rounded, label: 'Mark All Visible as Paid',
          color: T.green, onTap: () { Navigator.pop(context); onMarkAllPaid(); }),
      _SheetAction(icon: Icons.cancel_rounded, label: 'Mark All Visible as Unpaid',
          color: T.red, onTap: () { Navigator.pop(context); onMarkAllUnpaid(); }),
      const SizedBox(height: 8),
    ])),
  );
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SheetAction({required this.icon, required this.label,
    required this.color, required this.onTap});
  @override Widget build(BuildContext context) => InkWell(onTap: onTap,
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
        ])),
  );
}

class CredRow extends StatefulWidget {
  final String label, value;
  final bool isPassword;
  const CredRow({super.key, required this.label, required this.value, this.isPassword = false});
  @override State<CredRow> createState() => _CredRowState();
}

class _CredRowState extends State<CredRow> {
  bool _obscure = true;
  @override Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SizedBox(width: 72, child: Text(widget.label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
            color: T.inkFaint, letterSpacing: .4))),
    Expanded(child: Text(widget.isPassword && _obscure ? '•' * widget.value.length : widget.value,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: T.ink))),
    GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: widget.value));
        ScaffoldMessenger.of(context).showSnackBar(buildSnack('${widget.label} copied!'));
      },
      child: const Icon(Icons.copy_rounded, size: 16, color: T.inkFaint),
    ),
    if (widget.isPassword) ...[
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () => setState(() => _obscure = !_obscure),
        child: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
            size: 16, color: T.inkFaint),
      ),
    ],
  ]);
}

// ═══════════════════════════════════════════════════════════════════
//  HELPERS
// ═══════════════════════════════════════════════════════════════════

String fmtNum(double v) => NumberFormat('#,##0').format(v);

AppBar buildAppBar(String title, {String? subtitle, List<Widget>? actions}) => AppBar(
  title: subtitle != null
      ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title),
    Text(subtitle, style: const TextStyle(fontSize: 12, color: T.inkLight, fontWeight: FontWeight.w500)),
  ]) : Text(title),
  actions: actions,
  bottom: PreferredSize(preferredSize: const Size.fromHeight(1),
      child: Container(height: 1, color: T.divider)),
);

SnackBar buildSnack(String msg, {bool isError = false}) => SnackBar(
  content: Row(children: [
    Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
        color: Colors.white, size: 18),
    const SizedBox(width: 10),
    Expanded(child: Text(msg, style: const TextStyle(fontFamily: 'Nunito',
        fontWeight: FontWeight.w700, fontSize: 14))),
  ]),
  backgroundColor: isError ? T.red : T.green,
  behavior: SnackBarBehavior.floating,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  margin: const EdgeInsets.all(16), duration: const Duration(seconds: 3), elevation: 4,
);

PageRoute fadeRoute(Widget page) => PageRouteBuilder(
  pageBuilder: (_, __, ___) => page,
  transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
  transitionDuration: const Duration(milliseconds: 300),
);

PageRoute slideRoute(Widget page) => PageRouteBuilder(
  pageBuilder: (_, __, ___) => page,
  transitionsBuilder: (_, anim, __, child) => SlideTransition(
    position: Tween(begin: const Offset(1, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
    child: child,
  ),
  transitionDuration: const Duration(milliseconds: 320),
);