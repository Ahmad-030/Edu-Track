import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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
//  FIREBASE SERVICE  (single source of truth)
// ═══════════════════════════════════════════════════════════════════

class FB {
  static final auth = FirebaseAuth.instance;
  static final db   = FirebaseFirestore.instance;

  // ── Auth ──────────────────────────────────────────────────────────
  static User? get user => auth.currentUser;
  static Stream<User?> get authState => auth.userChangedEvents();

  static Future<void> signOut() => auth.signOut();

  static Future<String?> login(String email, String pw) async {
    try {
      await auth.signInWithEmailAndPassword(email: email.trim(), password: pw);
      return null; // success
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Login failed';
    }
  }

  // ── Secondary-app teacher account creation ────────────────────────
  // Uses a second FirebaseApp instance so the admin stays signed in
  // on the primary instance while the teacher account is created on
  // the secondary instance. The secondary instance is signed out
  // immediately after — admin never loses their session.
  static Future<String> createTeacherAuthAccount(
      String email, String password) async {
    // Reuse secondary app if already initialised, otherwise create it.
    FirebaseApp secondaryApp;
    try {
      secondaryApp = Firebase.app('secondary');
    } catch (_) {
      secondaryApp = await Firebase.initializeApp(
        name: 'secondary',
        options: Firebase.app().options, // same project, different instance
      );
    }

    final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
    try {
      final cred = await secondaryAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = cred.user!.uid;
      await secondaryAuth.signOut(); // sign out secondary only — admin unaffected
      return uid;
    } on FirebaseAuthException {
      await secondaryAuth.signOut();
      rethrow; // let caller surface the real Firebase error message
    }
  }

  // ── Firestore paths ────────────────────────────────────────────────
  static CollectionReference get schools      => db.collection('schools');
  static DocumentReference school(String id) => schools.doc(id);

  static CollectionReference teachers(String sid)  => school(sid).collection('teachers');
  static CollectionReference classes(String sid)   => school(sid).collection('classes');
  static CollectionReference students(String sid)  => school(sid).collection('students');
  static CollectionReference attendance(String sid) => school(sid).collection('attendance');

  // ── User-role mapping ─────────────────────────────────────────────
  // We store a top-level 'users' collection: uid -> {role, schoolId, [teacherId]}
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
  Map<String, dynamic> toJson() => {'name': name, 'adminName': adminName, 'email': email};
}

class Teacher {
  final String id, name, subject, phone, email;
  final String? classId;
  const Teacher({required this.id, required this.name, required this.subject, required this.phone, required this.email, this.classId});
  factory Teacher.fromDoc(DocumentSnapshot d) {
    final j = d.data() as Map<String, dynamic>;
    return Teacher(id: d.id, name: j['name'], subject: j['subject'], phone: j['phone'], email: j['email'], classId: j['classId']);
  }
  Map<String, dynamic> toJson() => {'name': name, 'subject': subject, 'phone': phone, 'email': email, 'classId': classId};
  Teacher copyWith({String? name, String? subject, String? phone, String? email, String? classId, bool clearClass = false}) =>
      Teacher(id: id, name: name ?? this.name, subject: subject ?? this.subject, phone: phone ?? this.phone,
          email: email ?? this.email, classId: clearClass ? null : (classId ?? this.classId));
}

class SchoolClass {
  final String id, name;
  final String? teacherId;
  const SchoolClass({required this.id, required this.name, this.teacherId});
  factory SchoolClass.fromDoc(DocumentSnapshot d) {
    final j = d.data() as Map<String, dynamic>;
    return SchoolClass(id: d.id, name: j['name'], teacherId: j['teacherId']);
  }
  Map<String, dynamic> toJson() => {'name': name, 'teacherId': teacherId};
  SchoolClass copyWith({String? name, String? teacherId, bool clearTeacher = false}) =>
      SchoolClass(id: id, name: name ?? this.name, teacherId: clearTeacher ? null : (teacherId ?? this.teacherId));
}

class Student {
  final String id, classId, name, rollNumber, parentPhone;
  final double monthlyFee;
  final bool feePaid;
  const Student({required this.id, required this.classId, required this.name, required this.rollNumber,
    required this.parentPhone, required this.monthlyFee, this.feePaid = false});
  factory Student.fromDoc(DocumentSnapshot d) {
    final j = d.data() as Map<String, dynamic>;
    return Student(id: d.id, classId: j['classId'], name: j['name'], rollNumber: j['rollNumber'],
        parentPhone: j['parentPhone'], monthlyFee: (j['monthlyFee'] as num).toDouble(), feePaid: j['feePaid'] ?? false);
  }
  Map<String, dynamic> toJson() => {'classId': classId, 'name': name, 'rollNumber': rollNumber,
    'parentPhone': parentPhone, 'monthlyFee': monthlyFee, 'feePaid': feePaid};
  Student copyWith({String? classId, String? name, String? rollNumber, String? parentPhone, double? monthlyFee, bool? feePaid}) =>
      Student(id: id, classId: classId ?? this.classId, name: name ?? this.name, rollNumber: rollNumber ?? this.rollNumber,
          parentPhone: parentPhone ?? this.parentPhone, monthlyFee: monthlyFee ?? this.monthlyFee, feePaid: feePaid ?? this.feePaid);
}

class AttendanceRecord {
  final String id, classId, date;
  final Map<String, bool> attendance;
  const AttendanceRecord({required this.id, required this.classId, required this.date, required this.attendance});
  factory AttendanceRecord.fromDoc(DocumentSnapshot d) {
    final j = d.data() as Map<String, dynamic>;
    return AttendanceRecord(id: d.id, classId: j['classId'], date: j['date'],
        attendance: Map<String, bool>.from(j['attendance'] ?? {}));
  }
  Map<String, dynamic> toJson() => {'classId': classId, 'date': date, 'attendance': attendance};
}

// ═══════════════════════════════════════════════════════════════════
//  SESSION  (held in memory after login)
// ═══════════════════════════════════════════════════════════════════

class Session {
  final String uid, role, schoolId;
  final String? teacherId; // set when role == 'teacher'
  const Session({required this.uid, required this.role, required this.schoolId, this.teacherId});
  bool get isAdmin => role == 'admin';
}

final _sessionNotifier = ValueNotifier<Session?>(null);
Session? get currentSession => _sessionNotifier.value;

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
      backgroundColor: surface, foregroundColor: ink, elevation: 0, scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Nunito', fontSize: 18, fontWeight: FontWeight.w800, color: ink, letterSpacing: -0.3),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: blue, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0, textStyle: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700, fontSize: 15),
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
//  APP ROOT  (listens to Firebase Auth state)
// ═══════════════════════════════════════════════════════════════════

class EduTrackApp extends StatelessWidget {
  const EduTrackApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'EduTrack', theme: T.theme, debugShowCheckedModeBanner: false,
    home: const _AuthGate(),
  );
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();
  @override State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _loading = true;
  StreamSubscription<User?>? _authSub;

  @override void initState() {
    super.initState();
    _authSub = FB.auth.authStateChanges().listen(_onAuthChanged);
  }

  @override void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _onAuthChanged(User? user) async {
    if (user == null) {
      _sessionNotifier.value = null;
      if (mounted) setState(() => _loading = false);
      return;
    }

    // Fetch user-role mapping. Retry once after a short delay to handle the
    // race where _onAuthChanged fires before the Firestore 'users' doc is
    // written (e.g. during registration or teacher account creation).
    Map<String, dynamic>? meta = await FB.userMeta(user.uid);
    if (meta == null) {
      await Future.delayed(const Duration(seconds: 2));
      meta = await FB.userMeta(user.uid);
    }

    if (meta == null) {
      // Still not found after retry — sign out to avoid a stuck state
      await FB.signOut();
      if (mounted) setState(() => _loading = false);
      return;
    }

    _sessionNotifier.value = Session(
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
      valueListenable: _sessionNotifier,
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
        Text('EduTrack', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.5)),
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
              gradient: const LinearGradient(colors: [T.blueDark, T.blue, T.blueMid], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(26),
              boxShadow: [BoxShadow(color: T.blue.withOpacity(.35), blurRadius: 24, offset: const Offset(0, 10))],
            ),
            child: const Icon(Icons.school_rounded, size: 46, color: Colors.white),
          ),
          const SizedBox(height: 22),
          const Text('EduTrack', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: T.ink, letterSpacing: -1.5)),
          const SizedBox(height: 6),
          const Text('Smart School Management', style: TextStyle(color: T.inkLight, fontSize: 15)),
          const Spacer(),
          _SurfaceCard(child: Column(children: [
            const SizedBox(height: 6),
            const Text('Welcome 👋', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: T.ink)),
            const SizedBox(height: 4),
            const Text('Login to your school account', style: TextStyle(color: T.inkLight, fontSize: 14)),
            const SizedBox(height: 24),
            _PrimaryButton(
              label: 'Login',
              icon: Icons.login_rounded,
              onTap: () => Navigator.push(context, _slideRoute(const LoginScreen())),
            ),
            const SizedBox(height: 12),
            _OutlineButton(
              label: 'Register New School',
              icon: Icons.add_business_rounded,
              onTap: () => Navigator.push(context, _slideRoute(const RegisterScreen())),
            ),
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

    // Step 1: sign in
    final err = await FB.login(_email.text, _pass.text);
    if (!mounted) return;
    if (err != null) {
      setState(() => _loading = false);
      _err(err);
      return;
    }

    // Step 2: fetch role (retry once for race condition)
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

    // Step 3: update session
    _sessionNotifier.value = Session(
      uid:       uid,
      role:      meta['role'],
      schoolId:  meta['schoolId'],
      teacherId: meta['teacherId'],
    );
    setState(() => _loading = false);

    // Step 4: navigate, clearing the full back stack (AuthScreen + LoginScreen)
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      _fadeRoute(meta['role'] == 'admin' ? const AdminRoot() : const TeacherDashboard()),
          (_) => false,
    );
  }

  void _err(String m) => ScaffoldMessenger.of(context).showSnackBar(_buildSnack(m, isError: true));

  @override Widget build(BuildContext context) => Scaffold(
    appBar: _buildAppBar('Login'),
    body: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 4),
      const Text('Welcome back!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: T.ink, letterSpacing: -.5)),
      const SizedBox(height: 4),
      const Text('Sign in to your school account', style: TextStyle(color: T.inkLight, fontSize: 15)),
      const SizedBox(height: 32),
      _SurfaceCard(child: Column(children: [
        _LabeledField(ctrl: _email, label: 'Email Address', icon: Icons.email_outlined, type: TextInputType.emailAddress),
        const SizedBox(height: 14),
        TextField(
          controller: _pass, obscureText: _obscure,
          style: const TextStyle(fontFamily: 'Nunito', fontSize: 15),
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline_rounded, color: T.inkFaint, size: 20),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: T.inkFaint, size: 20),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _PrimaryButton(label: 'Sign In', onTap: _loading ? null : _login, loading: _loading),
      ])),
    ])),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  REGISTER SCHOOL  (creates admin Firebase user + Firestore docs)
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
      // 1. Create Firebase Auth user
      final cred = await FB.auth.createUserWithEmailAndPassword(
          email: _email.text.trim(), password: _pass.text);
      final uid = cred.user!.uid;

      // 2. Write user-role mapping FIRST — _onAuthChanged reads this doc.
      //    If we write school first, the auth listener fires before this doc
      //    exists and incorrectly signs the admin out.
      await FB.users.doc(uid).set({'role': 'admin', 'schoolId': uid});

      // 3. Write school document
      await FB.schools.doc(uid).set({
        'name':      _name.text.trim(),
        'adminName': _admin.text.trim(),
        'email':     _email.text.trim(),
        'adminUid':  uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // _AuthGate listener fires automatically and routes to AdminRoot
    } on FirebaseAuthException catch (e) {
      if (mounted) _err(e.message ?? 'Registration failed');
    } catch (e) {
      if (mounted) _err('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _err(String m) => ScaffoldMessenger.of(context).showSnackBar(_buildSnack(m, isError: true));

  @override Widget build(BuildContext context) => Scaffold(
    appBar: _buildAppBar('Register School'),
    body: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Create Your School', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: T.ink, letterSpacing: -.5)),
      const SizedBox(height: 4),
      const Text('Set up your school account in seconds', style: TextStyle(color: T.inkLight, fontSize: 15)),
      const SizedBox(height: 32),
      _SurfaceCard(child: Column(children: [
        _SectionHeader('School Information'),
        _LabeledField(ctrl: _name,  label: 'School Name', icon: Icons.school_outlined),
        const SizedBox(height: 12),
        _LabeledField(ctrl: _admin, label: 'Admin Name',  icon: Icons.person_outline_rounded),
        const SizedBox(height: 20),
        _SectionHeader('Login Credentials'),
        _LabeledField(ctrl: _email, label: 'Email Address', icon: Icons.email_outlined, type: TextInputType.emailAddress),
        const SizedBox(height: 12),
        _LabeledField(ctrl: _pass,  label: 'Password', icon: Icons.lock_outline_rounded, obscure: true),
        const SizedBox(height: 24),
        _PrimaryButton(label: 'Create School 🚀', onTap: _loading ? null : _register, loading: _loading),
      ])),
    ])),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  ADMIN ROOT
// ═══════════════════════════════════════════════════════════════════

class AdminRoot extends StatefulWidget {
  const AdminRoot({super.key});
  @override State<AdminRoot> createState() => _AdminRootState();
}

class _AdminRootState extends State<AdminRoot> {
  int _tab = 0;
  static const _tabs = [AdminDashboard(), TeachersScreen(), ClassesScreen(), StudentsScreen(), MoreScreen()];

  @override Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _tab, children: _tabs),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (i) => setState(() => _tab = i),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
        NavigationDestination(icon: Icon(Icons.people_outline_rounded), selectedIcon: Icon(Icons.people_rounded), label: 'Teachers'),
        NavigationDestination(icon: Icon(Icons.class_outlined), selectedIcon: Icon(Icons.class_rounded), label: 'Classes'),
        NavigationDestination(icon: Icon(Icons.school_outlined), selectedIcon: Icon(Icons.school_rounded), label: 'Students'),
        NavigationDestination(icon: Icon(Icons.more_horiz_rounded), label: 'More'),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  ADMIN DASHBOARD
// ═══════════════════════════════════════════════════════════════════

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override Widget build(BuildContext context) {
    final sid = currentSession!.schoolId;
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(child: StreamBuilder<DocumentSnapshot>(
        stream: FB.school(sid).snapshots(),
        builder: (_, schoolSnap) {
          final school = schoolSnap.hasData && schoolSnap.data!.exists
              ? School.fromDoc(schoolSnap.data!) : null;
          return StreamBuilder<QuerySnapshot>(
            stream: FB.students(sid).snapshots(),
            builder: (_, studSnap) {
              final students = studSnap.hasData
                  ? studSnap.data!.docs.map(Student.fromDoc).toList() : <Student>[];
              return StreamBuilder<QuerySnapshot>(
                stream: FB.teachers(sid).snapshots(),
                builder: (_, teachSnap) {
                  final teachers = teachSnap.hasData
                      ? teachSnap.data!.docs.map(Teacher.fromDoc).toList() : <Teacher>[];
                  return StreamBuilder<QuerySnapshot>(
                    stream: FB.classes(sid).snapshots(),
                    builder: (_, clsSnap) {
                      final classes = clsSnap.hasData
                          ? clsSnap.data!.docs.map(SchoolClass.fromDoc).toList() : <SchoolClass>[];
                      return _buildDashboard(context, school, teachers, classes, students);
                    },
                  );
                },
              );
            },
          );
        },
      )),
    );
  }

  Widget _buildDashboard(BuildContext ctx, School? school,
      List<Teacher> teachers, List<SchoolClass> classes, List<Student> students) {
    final paid      = students.where((s) => s.feePaid).length;
    final unpaid    = students.length - paid;
    final collected = students.where((s) => s.feePaid).fold(0.0, (a, s) => a + s.monthlyFee);
    final total     = students.fold(0.0, (a, s) => a + s.monthlyFee);
    final pct       = students.isEmpty ? 0.0 : (paid / students.length).clamp(0.0, 1.0);

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 0), child: Column(children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hello, ${school?.adminName ?? 'Admin'}! 👋',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: T.ink, letterSpacing: -.3)),
            const SizedBox(height: 3),
            Row(children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: T.green, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(school?.name ?? '', style: const TextStyle(color: T.inkLight, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ])),
          _InitialBubble(school?.adminName ?? 'A'),
        ]),
        const SizedBox(height: 22),

        // Hero fee card
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E3A8A), Color(0xFF1D4ED8), Color(0xFF2563EB)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: T.blue.withOpacity(.4), blurRadius: 28, offset: const Offset(0, 12))],
          ),
          padding: const EdgeInsets.all(22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(.15), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 16)),
              const SizedBox(width: 10),
              Text('Monthly Fee Overview', style: TextStyle(color: Colors.white.withOpacity(.85), fontSize: 13, fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(.15), borderRadius: BorderRadius.circular(20)),
                  child: Text(DateFormat('MMM yyyy').format(DateTime.now()), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 18),
            Text('Rs ${_fmt(collected)}', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.5)),
            Text('collected of Rs ${_fmt(total)}', style: TextStyle(color: Colors.white.withOpacity(.65), fontSize: 13)),
            const SizedBox(height: 18),
            Stack(children: [
              Container(height: 6, decoration: BoxDecoration(color: Colors.white.withOpacity(.2), borderRadius: BorderRadius.circular(3))),
              FractionallySizedBox(widthFactor: pct,
                  child: Container(height: 6,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3),
                        boxShadow: [BoxShadow(color: Colors.white.withOpacity(.5), blurRadius: 8)]),
                  )),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Text('$paid Paid', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(width: 4),
              Text('·', style: TextStyle(color: Colors.white.withOpacity(.4))),
              const SizedBox(width: 4),
              Text('$unpaid Unpaid', style: TextStyle(color: Colors.white.withOpacity(.65), fontWeight: FontWeight.w600, fontSize: 13)),
              const Spacer(),
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(.2), borderRadius: BorderRadius.circular(20)),
                  child: Text('${(pct * 100).round()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
            ]),
          ]),
        ),
        const SizedBox(height: 24),
      ]))),

      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(children: [
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _StatTile(label: 'Teachers', value: '${teachers.length}', icon: Icons.people_rounded, color: T.blue)),
            const SizedBox(width: 12),
            Expanded(child: _StatTile(label: 'Students', value: '${students.length}', icon: Icons.school_rounded, color: T.purple)),
          ])),
          const SizedBox(height: 12),
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _StatTile(label: 'Classes', value: '${classes.length}', icon: Icons.class_rounded, color: T.teal)),
            const SizedBox(width: 12),
            Expanded(child: _StatTile(label: 'Unpaid', value: '$unpaid', icon: Icons.pending_rounded, color: unpaid > 0 ? T.red : T.green)),
          ])),
        ]),
      )),

      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
          child: const Text('Quick Actions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.ink)))),

      SliverPadding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), sliver: SliverList(delegate: SliverChildListDelegate([
        _ActionRow(icon: Icons.person_add_rounded,             label: 'Add Teacher',     sub: 'Manage teaching staff',        color: T.blue,   onTap: () => Navigator.push(ctx, _slideRoute(const AddTeacherScreen()))),
        _ActionRow(icon: Icons.add_box_rounded,                label: 'Add Class',       sub: 'Create a new grade or section', color: T.purple, onTap: () => Navigator.push(ctx, _slideRoute(const AddClassScreen()))),
        _ActionRow(icon: Icons.person_add_alt_1_rounded,       label: 'Add Student',     sub: 'Enroll a new student',          color: T.teal,   onTap: () => Navigator.push(ctx, _slideRoute(const AddStudentScreen()))),
        _ActionRow(icon: Icons.calendar_today_rounded,         label: 'View Attendance', sub: 'Check class attendance records', color: T.amber,  onTap: () => Navigator.push(ctx, _slideRoute(const AdminAttendanceScreen()))),
        _ActionRow(icon: Icons.account_balance_wallet_rounded, label: 'Fee Tracker',     sub: 'Monitor & collect fees',        color: T.green,  onTap: () => Navigator.push(ctx, _slideRoute(const FeeTrackerScreen()))),
      ]))),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════
//  TEACHERS SCREEN
// ═══════════════════════════════════════════════════════════════════

class TeachersScreen extends StatelessWidget {
  const TeachersScreen({super.key});
  @override Widget build(BuildContext context) {
    final sid = currentSession!.schoolId;
    return Scaffold(
      appBar: _buildAppBar('Teachers'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, _slideRoute(const AddTeacherScreen())),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Teacher', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FB.teachers(sid).orderBy('name').snapshots(),
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final teachers = snap.data!.docs.map(Teacher.fromDoc).toList();
          if (teachers.isEmpty) return const _EmptyState(Icons.people_rounded, 'No teachers yet', 'Tap the button below to add your first teacher');
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: teachers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _TeacherCard(teacher: teachers[i], sid: sid),
          );
        },
      ),
    );
  }
}

class _TeacherCard extends StatelessWidget {
  final Teacher teacher; final String sid;
  const _TeacherCard({required this.teacher, required this.sid});

  @override Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: T.divider),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.03), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          _CircleInitial(teacher.name, T.blue, T.blueLight, radius: 26),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(teacher.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: T.ink)),
            const SizedBox(height: 4),
            _InfoRow(Icons.book_outlined, teacher.subject),
            const SizedBox(height: 2),
            _InfoRow(Icons.phone_outlined, teacher.phone),
          ])),
          if (teacher.classId != null) ...[
            StreamBuilder<DocumentSnapshot>(
              stream: FB.classes(sid).doc(teacher.classId!).snapshots(),
              builder: (_, s) {
                final name = s.hasData && s.data!.exists ? (s.data!.data() as Map)['name'] as String : '...';
                return _StatusChip(name, T.blue, T.blueLight);
              },
            ),
          ],
        ])),
        Container(height: 1, color: T.dividerFaint),
        _CardActions(
          leftIcon: Icons.edit_rounded, leftLabel: 'Edit', leftColor: T.blue,
          rightIcon: Icons.delete_rounded, rightLabel: 'Delete', rightColor: T.red,
          onLeft:  () => Navigator.push(context, _slideRoute(AddTeacherScreen(teacher: teacher))),
          onRight: () => _showDeleteDialog(context, title: 'Delete Teacher', name: teacher.name,
              description: 'This teacher will be removed and unassigned from their class.',
              onConfirm: () => _deleteTeacher(sid, teacher)),
        ),
      ]),
    );
  }

  Future<void> _deleteTeacher(String sid, Teacher teacher) async {
    final batch = FB.db.batch();
    // Clear class assignment
    if (teacher.classId != null) {
      batch.update(FB.classes(sid).doc(teacher.classId!), {'teacherId': FieldValue.delete()});
    }
    batch.delete(FB.teachers(sid).doc(teacher.id));
    // Delete Firebase Auth user would require admin SDK — skip here (optional)
    await batch.commit();
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ADD / EDIT TEACHER
//  Key difference: creates a Firebase Auth account for the teacher
//  Admin stays logged in; we use secondary auth instance approach.
// ═══════════════════════════════════════════════════════════════════

class AddTeacherScreen extends StatefulWidget {
  final Teacher? teacher;
  const AddTeacherScreen({super.key, this.teacher});
  @override State<AddTeacherScreen> createState() => _AddTeacherState();
}

class _AddTeacherState extends State<AddTeacherScreen> {
  final _name    = TextEditingController();
  final _subject = TextEditingController();
  final _phone   = TextEditingController();
  final _email   = TextEditingController();
  final _pass    = TextEditingController();
  String? _classId;
  bool _loading = false;

  @override void initState() {
    super.initState();
    if (widget.teacher != null) {
      final t = widget.teacher!;
      _name.text = t.name; _subject.text = t.subject;
      _phone.text = t.phone; _email.text = t.email;
      _classId = t.classId;
    }
  }

  void _save() async {
    final sid = currentSession!.schoolId;
    if ([_name, _subject, _phone, _email].any((c) => c.text.trim().isEmpty) ||
        (widget.teacher == null && _pass.text.isEmpty)) {
      _err('Please fill in all required fields'); return;
    }
    if (widget.teacher == null && _pass.text.length < 6) {
      _err('Password must be at least 6 characters'); return;
    }
    setState(() => _loading = true);
    try {
      if (widget.teacher == null) {
        // ── ADD NEW TEACHER via secondary Firebase app ─────────────────
        // Admin stays signed in on the primary app instance throughout.

        // Step 1: Create teacher Firebase Auth account on secondary instance
        final teacherUid = await FB.createTeacherAuthAccount(
          _email.text.trim(),
          _pass.text,
        );

        // Step 2: Write all Firestore docs in a single batch
        final batch = FB.db.batch();

        // Teacher profile under the school
        batch.set(FB.teachers(sid).doc(teacherUid), {
          'name':    _name.text.trim(),
          'subject': _subject.text.trim(),
          'phone':   _phone.text.trim(),
          'email':   _email.text.trim(),
          'classId': _classId,
        });

        // User-role mapping (needed by _AuthGate to route correctly)
        batch.set(FB.users.doc(teacherUid), {
          'role':      'teacher',
          'schoolId':  sid,
          'teacherId': teacherUid,
        });

        // If a class was selected, link the teacher to it
        if (_classId != null) {
          batch.update(FB.classes(sid).doc(_classId!), {'teacherId': teacherUid});
        }

        await batch.commit();

        // Step 3: Show credentials dialog — admin copies them for the teacher
        if (mounted) {
          await _showCredentialsDialog(
            name:     _name.text.trim(),
            email:    _email.text.trim(),
            password: _pass.text,
          );
        }
      } else {
        // ── UPDATE EXISTING TEACHER ────────────────────────────────────
        final batch = FB.db.batch();
        final old = widget.teacher!;

        // Unlink from the old class if it changed
        if (old.classId != null && old.classId != _classId) {
          batch.update(
            FB.classes(sid).doc(old.classId!),
            {'teacherId': FieldValue.delete()},
          );
        }
        // Link to the new class if it changed
        if (_classId != null && _classId != old.classId) {
          batch.update(FB.classes(sid).doc(_classId!), {'teacherId': old.id});
        }

        batch.update(FB.teachers(sid).doc(old.id), {
          'name':    _name.text.trim(),
          'subject': _subject.text.trim(),
          'phone':   _phone.text.trim(),
          'classId': _classId,
        });

        await batch.commit();
        if (mounted) Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      _err(e.message ?? 'Error creating teacher account');
    } catch (e) {
      _err('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Shows a modal with the teacher's login credentials so the admin
  /// can share them (e.g. screenshot or copy-paste via WhatsApp).
  Future<void> _showCredentialsDialog({
    required String name,
    required String email,
    required String password,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Success icon
              Container(
                width: 64, height: 64,
                decoration: const BoxDecoration(color: T.greenLight, shape: BoxShape.circle),
                child: const Icon(Icons.check_circle_rounded, color: T.green, size: 34),
              ),
              const SizedBox(height: 16),
              const Text(
                'Teacher Account Created!',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: T.ink),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Share these credentials with $name so they can log in on their device.',
                style: const TextStyle(fontSize: 13, color: T.inkLight, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Credentials card
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: T.bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: T.divider),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _CredRow(label: 'Name',     value: name),
                  const Divider(height: 20, color: T.divider),
                  _CredRow(label: 'Email',    value: email),
                  const Divider(height: 20, color: T.divider),
                  _CredRow(label: 'Password', value: password, isPassword: true),
                ]),
              ),

              const SizedBox(height: 12),
              // Security note
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: T.amberLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: T.amber.withOpacity(.3)),
                ),
                child: const Row(children: [
                  Icon(Icons.warning_amber_rounded, color: T.amber, size: 16),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'Ask the teacher to change their password after first login.',
                    style: TextStyle(fontSize: 12, color: T.inkMid, height: 1.4),
                  )),
                ]),
              ),

              const SizedBox(height: 20),
              _PrimaryButton(
                label: 'Done',
                icon: Icons.check_rounded,
                onTap: () => Navigator.pop(context),
              ),
            ]),
          ),
        ),
      ),
    );
    // Pop the Add Teacher screen after dialog is dismissed
    if (mounted) Navigator.pop(context);
  }

  void _err(String m) => ScaffoldMessenger.of(context).showSnackBar(_buildSnack(m, isError: true));

  @override Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FB.classes(currentSession!.schoolId).snapshots(),
      builder: (_, snap) {
        final classes = snap.hasData ? snap.data!.docs.map(SchoolClass.fromDoc).toList() : <SchoolClass>[];
        return Scaffold(
          appBar: _buildAppBar(widget.teacher == null ? 'Add Teacher' : 'Edit Teacher'),
          body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
            // Info banner about auth — secondary app means admin stays logged in
            if (widget.teacher == null)
              Container(margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: T.blueLight, borderRadius: BorderRadius.circular(14), border: Border.all(color: T.blue.withOpacity(.2))),
                  child: const Row(children: [
                    Icon(Icons.info_outline_rounded, color: T.blue, size: 18),
                    SizedBox(width: 10),
                    Expanded(child: Text(
                      'A login account will be created for this teacher. You will stay logged in as admin — credentials are shown after saving so you can share them.',
                      style: TextStyle(color: T.blue, fontSize: 13, fontWeight: FontWeight.w600),
                    )),
                  ])),
            _SurfaceCard(child: Column(children: [
              _SectionHeader('Personal Information'),
              _LabeledField(ctrl: _name,    label: 'Full Name',    icon: Icons.person_outline_rounded),
              const SizedBox(height: 12),
              _LabeledField(ctrl: _subject, label: 'Subject',      icon: Icons.book_outlined),
              const SizedBox(height: 12),
              _LabeledField(ctrl: _phone,   label: 'Phone Number', icon: Icons.phone_outlined, type: TextInputType.phone),
            ])),
            const SizedBox(height: 14),
            _SurfaceCard(child: Column(children: [
              _SectionHeader('Login Credentials'),
              _LabeledField(ctrl: _email, label: 'Email Address', icon: Icons.email_outlined, type: TextInputType.emailAddress,
                  readOnly: widget.teacher != null),
              if (widget.teacher == null) ...[
                const SizedBox(height: 12),
                _LabeledField(ctrl: _pass, label: 'Password', icon: Icons.lock_outline_rounded, obscure: true),
              ],
            ])),
            const SizedBox(height: 14),
            _SurfaceCard(child: Column(children: [
              _SectionHeader('Class Assignment'),
              DropdownButtonFormField<String?>(
                value: _classId,
                decoration: const InputDecoration(labelText: 'Assign to Class (optional)',
                    prefixIcon: Icon(Icons.class_outlined, color: T.inkFaint, size: 20)),
                items: [
                  const DropdownMenuItem(value: null, child: Text('No class assigned')),
                  ...classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                ],
                onChanged: (v) => setState(() => _classId = v),
              ),
            ])),
            const SizedBox(height: 28),
            _PrimaryButton(
              label: widget.teacher == null ? 'Save Teacher' : 'Update Teacher',
              icon: widget.teacher == null ? Icons.person_add_rounded : Icons.check_rounded,
              onTap: _loading ? null : _save, loading: _loading,
            ),
          ])),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  CLASSES SCREEN
// ═══════════════════════════════════════════════════════════════════

class ClassesScreen extends StatelessWidget {
  const ClassesScreen({super.key});
  @override Widget build(BuildContext context) {
    final sid = currentSession!.schoolId;
    return Scaffold(
      appBar: _buildAppBar('Classes'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, _slideRoute(const AddClassScreen())),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Class', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FB.classes(sid).orderBy('name').snapshots(),
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final classes = snap.data!.docs.map(SchoolClass.fromDoc).toList();
          if (classes.isEmpty) return const _EmptyState(Icons.class_rounded, 'No classes yet', 'Create your first class to get started');
          return StreamBuilder<QuerySnapshot>(
            stream: FB.students(sid).snapshots(),
            builder: (_, studSnap) {
              final allStudents = studSnap.hasData ? studSnap.data!.docs.map(Student.fromDoc).toList() : <Student>[];
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: classes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final c = classes[i];
                  final count = allStudents.where((s) => s.classId == c.id).length;
                  return _ClassCard(cls: c, sid: sid, studentCount: count);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  final SchoolClass cls; final String sid; final int studentCount;
  const _ClassCard({required this.cls, required this.sid, required this.studentCount});

  @override Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: T.divider),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.03), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          Container(width: 50, height: 50,
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [T.teal, T.tealMid], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.class_rounded, color: Colors.white, size: 24)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cls.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: T.ink)),
            const SizedBox(height: 4),
            if (cls.teacherId != null)
              StreamBuilder<DocumentSnapshot>(
                stream: FB.teachers(sid).doc(cls.teacherId!).snapshots(),
                builder: (_, s) {
                  final name = s.hasData && s.data!.exists ? (s.data!.data() as Map)['name'] as String : '...';
                  return _InfoRow(Icons.person_outline_rounded, name);
                },
              )
            else
              const _InfoRow(Icons.person_outline_rounded, 'No teacher assigned'),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$studentCount', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: T.teal, letterSpacing: -1)),
            const Text('students', style: TextStyle(fontSize: 11, color: T.inkLight, fontWeight: FontWeight.w600)),
          ]),
        ])),
        Container(height: 1, color: T.dividerFaint),
        _CardActions(
          leftIcon: Icons.edit_rounded, leftLabel: 'Edit', leftColor: T.blue,
          rightIcon: Icons.delete_rounded, rightLabel: 'Delete', rightColor: T.red,
          onLeft:  () => Navigator.push(context, _slideRoute(AddClassScreen(cls: cls))),
          onRight: () => _showDeleteDialog(context, title: 'Delete Class', name: cls.name,
              description: 'All student assignments to this class will be affected.',
              onConfirm: () => _deleteClass(sid, cls)),
        ),
      ]),
    );
  }

  Future<void> _deleteClass(String sid, SchoolClass cls) async {
    final batch = FB.db.batch();
    if (cls.teacherId != null) {
      batch.update(FB.teachers(sid).doc(cls.teacherId!), {'classId': FieldValue.delete()});
    }
    batch.delete(FB.classes(sid).doc(cls.id));
    await batch.commit();
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ADD / EDIT CLASS
// ═══════════════════════════════════════════════════════════════════

class AddClassScreen extends StatefulWidget {
  final SchoolClass? cls;
  const AddClassScreen({super.key, this.cls});
  @override State<AddClassScreen> createState() => _AddClassState();
}

class _AddClassState extends State<AddClassScreen> {
  final _name = TextEditingController();
  String? _tid; bool _loading = false;

  @override void initState() {
    super.initState();
    if (widget.cls != null) { _name.text = widget.cls!.name; _tid = widget.cls!.teacherId; }
  }

  void _save() async {
    final sid = currentSession!.schoolId;
    if (_name.text.trim().isEmpty) { _err('Please enter a class name'); return; }
    setState(() => _loading = true);
    try {
      final batch = FB.db.batch();
      if (widget.cls == null) {
        final ref = FB.classes(sid).doc();
        batch.set(ref, {'name': _name.text.trim(), 'teacherId': _tid});
        if (_tid != null) batch.update(FB.teachers(sid).doc(_tid!), {'classId': ref.id});
      } else {
        final old = widget.cls!;
        batch.update(FB.classes(sid).doc(old.id), {'name': _name.text.trim(), 'teacherId': _tid});
        if (old.teacherId != null && old.teacherId != _tid) {
          batch.update(FB.teachers(sid).doc(old.teacherId!), {'classId': FieldValue.delete()});
        }
        if (_tid != null && _tid != old.teacherId) {
          batch.update(FB.teachers(sid).doc(_tid!), {'classId': old.id});
        }
      }
      await batch.commit();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _err('Error saving class');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _err(String m) => ScaffoldMessenger.of(context).showSnackBar(_buildSnack(m, isError: true));

  @override Widget build(BuildContext context) => Scaffold(
    appBar: _buildAppBar(widget.cls == null ? 'Add Class' : 'Edit Class'),
    body: StreamBuilder<QuerySnapshot>(
      stream: FB.teachers(currentSession!.schoolId).orderBy('name').snapshots(),
      builder: (_, snap) {
        final teachers = snap.hasData ? snap.data!.docs.map(Teacher.fromDoc).toList() : <Teacher>[];
        return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
          _SurfaceCard(child: Column(children: [
            _SectionHeader('Class Details'),
            _LabeledField(ctrl: _name, label: 'Class Name (e.g. Grade 1 - A)', icon: Icons.class_outlined),
            const SizedBox(height: 14),
            DropdownButtonFormField<String?>(
              value: _tid,
              decoration: const InputDecoration(labelText: 'Assign Teacher (optional)',
                  prefixIcon: Icon(Icons.person_outline_rounded, color: T.inkFaint, size: 20)),
              items: [
                const DropdownMenuItem(value: null, child: Text('No teacher assigned')),
                ...teachers.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))),
              ],
              onChanged: (v) => setState(() => _tid = v),
            ),
          ])),
          const SizedBox(height: 28),
          _PrimaryButton(
            label: widget.cls == null ? 'Save Class' : 'Update Class',
            icon: widget.cls == null ? Icons.add_rounded : Icons.check_rounded,
            onTap: _loading ? null : _save, loading: _loading,
          ),
        ]));
      },
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  STUDENTS SCREEN
// ═══════════════════════════════════════════════════════════════════

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});
  @override State<StudentsScreen> createState() => _StudentsState();
}

class _StudentsState extends State<StudentsScreen> {
  String? _filter;

  @override Widget build(BuildContext context) {
    final sid = currentSession!.schoolId;
    return Scaffold(
      appBar: _buildAppBar('Students'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, _slideRoute(const AddStudentScreen())),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Student', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FB.classes(sid).orderBy('name').snapshots(),
        builder: (_, clsSnap) {
          final classes = clsSnap.hasData ? clsSnap.data!.docs.map(SchoolClass.fromDoc).toList() : <SchoolClass>[];
          return StreamBuilder<QuerySnapshot>(
            stream: _filter == null
                ? FB.students(sid).orderBy('name').snapshots()
                : FB.students(sid).where('classId', isEqualTo: _filter).orderBy('name').snapshots(),
            builder: (_, studSnap) {
              final students = studSnap.hasData ? studSnap.data!.docs.map(Student.fromDoc).toList() : <Student>[];
              return Column(children: [
                Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                    _FilterPill('All', _filter == null, () => setState(() => _filter = null), T.blue),
                    ...classes.map((c) => _FilterPill(c.name, _filter == c.id, () => setState(() => _filter = c.id), T.purple)),
                  ])),
                ),
                Container(height: 1, color: T.divider),
                Expanded(child: students.isEmpty
                    ? const _EmptyState(Icons.school_rounded, 'No students found', 'Add students or change the filter')
                    : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: students.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _StudentCard(student: students[i], sid: sid, classes: classes),
                )),
              ]);
            },
          );
        },
      ),
    );
  }
}

class _StudentCard extends StatelessWidget {
  final Student student; final String sid; final List<SchoolClass> classes;
  const _StudentCard({required this.student, required this.sid, required this.classes});

  String _className() => classes.where((c) => c.id == student.classId).firstOrNull?.name ?? '-';

  @override Widget build(BuildContext context) {
    final paid = student.feePaid;
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: T.divider),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.03), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          _CircleInitial(student.name, T.purple, T.purpleLight, radius: 23),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(student.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: T.ink))),
              _StatusChip(paid ? 'Paid' : 'Unpaid', paid ? T.green : T.red, paid ? T.greenLight : T.redLight),
            ]),
            const SizedBox(height: 4),
            _InfoRow(Icons.tag_rounded, 'Roll #${student.rollNumber}  ·  ${_className()}'),
            const SizedBox(height: 2),
            _InfoRow(Icons.phone_outlined, '${student.parentPhone}  ·  Rs ${_fmt(student.monthlyFee)}/mo'),
          ])),
        ])),
        Container(height: 1, color: T.dividerFaint),
        _CardActions(
          leftIcon: Icons.edit_rounded, leftLabel: 'Edit', leftColor: T.blue,
          rightIcon: Icons.delete_rounded, rightLabel: 'Delete', rightColor: T.red,
          onLeft:  () => Navigator.push(context, _slideRoute(AddStudentScreen(student: student))),
          onRight: () => _showDeleteDialog(context, title: 'Delete Student', name: student.name,
              description: 'This student\'s data will be removed.',
              onConfirm: () => FB.students(sid).doc(student.id).delete()),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ADD / EDIT STUDENT
// ═══════════════════════════════════════════════════════════════════

class AddStudentScreen extends StatefulWidget {
  final Student? student;
  const AddStudentScreen({super.key, this.student});
  @override State<AddStudentScreen> createState() => _AddStudentState();
}

class _AddStudentState extends State<AddStudentScreen> {
  final _name  = TextEditingController();
  final _roll  = TextEditingController();
  final _phone = TextEditingController();
  final _fee   = TextEditingController();
  String? _cid; bool _loading = false;

  @override void initState() {
    super.initState();
    if (widget.student != null) {
      final s = widget.student!;
      _name.text = s.name; _roll.text = s.rollNumber;
      _phone.text = s.parentPhone; _fee.text = s.monthlyFee.toString();
      _cid = s.classId;
    }
  }

  void _save() async {
    final sid = currentSession!.schoolId;
    if ([_name, _roll, _phone, _fee].any((c) => c.text.trim().isEmpty) || _cid == null) {
      ScaffoldMessenger.of(context).showSnackBar(_buildSnack('Please fill all fields and select a class', isError: true)); return;
    }
    setState(() => _loading = true);
    try {
      final data = {
        'classId': _cid, 'name': _name.text.trim(), 'rollNumber': _roll.text.trim(),
        'parentPhone': _phone.text.trim(), 'monthlyFee': double.tryParse(_fee.text) ?? 0,
        'feePaid': widget.student?.feePaid ?? false,
      };
      if (widget.student == null) {
        await FB.students(sid).add(data);
      } else {
        await FB.students(sid).doc(widget.student!.id).update(data);
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: _buildAppBar(widget.student == null ? 'Add Student' : 'Edit Student'),
    body: StreamBuilder<QuerySnapshot>(
      stream: FB.classes(currentSession!.schoolId).orderBy('name').snapshots(),
      builder: (_, snap) {
        final classes = snap.hasData ? snap.data!.docs.map(SchoolClass.fromDoc).toList() : <SchoolClass>[];
        return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
          _SurfaceCard(child: Column(children: [
            _SectionHeader('Student Information'),
            _LabeledField(ctrl: _name,  label: 'Full Name',    icon: Icons.person_outline_rounded),
            const SizedBox(height: 12),
            _LabeledField(ctrl: _roll,  label: 'Roll Number',  icon: Icons.tag_rounded),
            const SizedBox(height: 12),
            _LabeledField(ctrl: _phone, label: 'Parent Phone', icon: Icons.phone_outlined, type: TextInputType.phone),
          ])),
          const SizedBox(height: 14),
          _SurfaceCard(child: Column(children: [
            _SectionHeader('Class & Fee'),
            DropdownButtonFormField<String?>(
              value: _cid,
              decoration: const InputDecoration(labelText: 'Assign to Class',
                  prefixIcon: Icon(Icons.class_outlined, color: T.inkFaint, size: 20)),
              items: classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
              onChanged: (v) => setState(() => _cid = v),
            ),
            const SizedBox(height: 12),
            _LabeledField(ctrl: _fee, label: 'Monthly Fee (Rs)', icon: Icons.payments_outlined, type: TextInputType.number),
          ])),
          const SizedBox(height: 28),
          _PrimaryButton(
            label: widget.student == null ? 'Save Student' : 'Update Student',
            icon: widget.student == null ? Icons.person_add_rounded : Icons.check_rounded,
            onTap: _loading ? null : _save, loading: _loading,
          ),
        ]));
      },
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  FEE TRACKER  (admin)
// ═══════════════════════════════════════════════════════════════════

class FeeTrackerScreen extends StatefulWidget {
  const FeeTrackerScreen({super.key});
  @override State<FeeTrackerScreen> createState() => _FeeTrackerState();
}

class _FeeTrackerState extends State<FeeTrackerScreen> {
  String _filter = 'all'; String _search = ''; String? _classFilter;

  Future<void> _toggle(Student s) async {
    final sid = currentSession!.schoolId;
    await FB.students(sid).doc(s.id).update({'feePaid': !s.feePaid});
  }

  @override Widget build(BuildContext context) {
    final sid = currentSession!.schoolId;
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(child: StreamBuilder<QuerySnapshot>(
        stream: FB.students(sid).snapshots(),
        builder: (_, snap) {
          final all = snap.hasData ? snap.data!.docs.map(Student.fromDoc).toList() : <Student>[];
          final paid = all.where((s) => s.feePaid).length;
          final unpaid = all.length - paid;
          final collected = all.where((s) => s.feePaid).fold(0.0, (a, s) => a + s.monthlyFee);
          final total = all.fold(0.0, (a, s) => a + s.monthlyFee);
          final pct = all.isEmpty ? 0.0 : (paid / all.length).clamp(0.0, 1.0);

          var filtered = all.where((s) {
            final mF = _filter == 'all' || (_filter == 'paid' ? s.feePaid : !s.feePaid);
            final mS = _search.isEmpty || s.name.toLowerCase().contains(_search.toLowerCase()) || s.rollNumber.contains(_search);
            final mC = _classFilter == null || s.classId == _classFilter;
            return mF && mS && mC;
          }).toList();

          return StreamBuilder<QuerySnapshot>(
            stream: FB.classes(sid).orderBy('name').snapshots(),
            builder: (_, clsSnap) {
              final classes = clsSnap.hasData ? clsSnap.data!.docs.map(SchoolClass.fromDoc).toList() : <SchoolClass>[];
              return Column(children: [
                Container(color: Colors.white, child: Column(children: [
                  Padding(padding: const EdgeInsets.fromLTRB(20, 18, 16, 0),
                      child: Row(children: [
                        const Expanded(child: Text('Fee Tracker', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: T.ink))),
                        _IconAction(Icons.tune_rounded, () => _bulkSheet(context, filtered, all)),
                      ])),
                  Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _FeeHeroBanner(collected: collected, total: total, paid: paid, unpaid: unpaid, pct: pct)),
                  Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _SegmentedTabs(
                        labels: ['All', 'Paid', 'Unpaid'], counts: [all.length, paid, unpaid], colors: [T.blue, T.green, T.red],
                        selected: _filter == 'all' ? 0 : _filter == 'paid' ? 1 : 2,
                        onTap: (i) => setState(() => _filter = ['all', 'paid', 'unpaid'][i]),
                      )),
                  Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 12), child: Row(children: [
                    Expanded(child: _SearchField(hint: 'Search name or roll…', onChanged: (v) => setState(() => _search = v))),
                    const SizedBox(width: 10),
                    _ClassDropdown(classes: classes, value: _classFilter, onChanged: (v) => setState(() => _classFilter = v)),
                  ])),
                ])),
                Container(height: 1, color: T.divider),
                Expanded(child: filtered.isEmpty
                    ? _EmptyState(Icons.account_balance_wallet_rounded, 'No students here',
                    _filter == 'unpaid' ? 'All students have paid! 🎉' : 'Add students first')
                    : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _FeeCard(student: filtered[i], onToggle: () => _toggle(filtered[i])),
                )),
              ]);
            },
          );
        },
      )),
    );
  }

  void _bulkSheet(BuildContext ctx, List<Student> filtered, List<Student> all) {
    final sid = currentSession!.schoolId;
    showModalBottomSheet(context: ctx, backgroundColor: Colors.transparent, builder: (_) =>
        _BulkActionSheet(
          onMarkAllPaid: () async { for (final s in filtered.where((s) => !s.feePaid)) await FB.students(sid).doc(s.id).update({'feePaid': true}); },
          onMarkAllUnpaid: () async { for (final s in filtered.where((s) => s.feePaid)) await FB.students(sid).doc(s.id).update({'feePaid': false}); },
        ));
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ADMIN ATTENDANCE VIEW
// ═══════════════════════════════════════════════════════════════════

class AdminAttendanceScreen extends StatefulWidget {
  const AdminAttendanceScreen({super.key});
  @override State<AdminAttendanceScreen> createState() => _AdminAttState();
}

class _AdminAttState extends State<AdminAttendanceScreen> {
  String? _cid;
  String _date = DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override Widget build(BuildContext context) {
    final sid = currentSession!.schoolId;
    return Scaffold(
      appBar: _buildAppBar('Attendance View'),
      body: Column(children: [
        Container(color: Colors.white, padding: const EdgeInsets.all(16), child: Column(children: [
          StreamBuilder<QuerySnapshot>(
            stream: FB.classes(sid).orderBy('name').snapshots(),
            builder: (_, snap) {
              final classes = snap.hasData ? snap.data!.docs.map(SchoolClass.fromDoc).toList() : <SchoolClass>[];
              return DropdownButtonFormField<String?>(
                value: _cid,
                decoration: const InputDecoration(labelText: 'Select Class',
                    prefixIcon: Icon(Icons.class_outlined, color: T.inkFaint, size: 20)),
                items: classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                onChanged: (v) => setState(() => _cid = v),
              );
            },
          ),
          const SizedBox(height: 10),
          _DatePickerField(date: _date, onChanged: (d) => setState(() => _date = d)),
        ])),
        Container(height: 1, color: T.divider),
        Expanded(child: _cid == null
            ? const _EmptyState(Icons.class_rounded, 'Select a class', 'Choose a class and date to view attendance')
            : StreamBuilder<QuerySnapshot>(
          stream: FB.students(sid).where('classId', isEqualTo: _cid).orderBy('name').snapshots(),
          builder: (_, studSnap) {
            final students = studSnap.hasData ? studSnap.data!.docs.map(Student.fromDoc).toList() : <Student>[];
            return StreamBuilder<QuerySnapshot>(
              stream: FB.attendance(sid).where('classId', isEqualTo: _cid).where('date', isEqualTo: _date).snapshots(),
              builder: (_, attSnap) {
                AttendanceRecord? record;
                if (attSnap.hasData && attSnap.data!.docs.isNotEmpty) {
                  record = AttendanceRecord.fromDoc(attSnap.data!.docs.first);
                }
                final presentC = record == null ? 0 : record.attendance.values.where((v) => v).length;
                return Column(children: [
                  if (students.isNotEmpty)
                    Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Row(children: [
                      _AttBadge('$presentC Present', T.green, T.greenLight),
                      const SizedBox(width: 10),
                      _AttBadge('${students.length - presentC} Absent', T.red, T.redLight),
                    ])),
                  Expanded(child: students.isEmpty
                      ? const _EmptyState(Icons.people_rounded, 'No students', 'This class has no students yet')
                      : ListView.separated(
                    padding: const EdgeInsets.all(16), itemCount: students.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final s = students[i]; final present = record?.attendance[s.id] ?? false;
                      return Container(
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: T.divider)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(children: [
                          _CircleInitial(s.name, present ? T.green : T.red, present ? T.greenLight : T.redLight, radius: 18),
                          const SizedBox(width: 12),
                          Expanded(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, color: T.ink))),
                          _StatusChip(present ? 'Present' : 'Absent', present ? T.green : T.red, present ? T.greenLight : T.redLight),
                        ]),
                      );
                    },
                  )),
                ]);
              },
            );
          },
        )),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  MORE / SETTINGS  (admin)
// ═══════════════════════════════════════════════════════════════════

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});
  @override Widget build(BuildContext context) {
    final sid = currentSession!.schoolId;
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(child: StreamBuilder<DocumentSnapshot>(
        stream: FB.school(sid).snapshots(),
        builder: (_, snap) {
          final school = snap.hasData && snap.data!.exists ? School.fromDoc(snap.data!) : null;
          return ListView(padding: const EdgeInsets.all(20), children: [
            const SizedBox(height: 4),
            const Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: T.ink)),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1E3A8A), T.blue], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: T.blue.withOpacity(.3), blurRadius: 24, offset: const Offset(0, 8))],
              ),
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Container(width: 56, height: 56,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(.15), borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.school_rounded, color: Colors.white, size: 28)),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(school?.name ?? '...', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(school?.email ?? '', style: TextStyle(color: Colors.white.withOpacity(.7), fontSize: 12)),
                  Text('Admin: ${school?.adminName ?? ''}', style: TextStyle(color: Colors.white.withOpacity(.7), fontSize: 12)),
                ])),
              ]),
            ),
            const SizedBox(height: 20),
            _SettingRow(Icons.info_outline_rounded, 'About EduTrack', 'Version 2.0 — Firebase Cloud Backend', T.teal, () {}),
            const SizedBox(height: 8),
            _LogoutButton(onTap: () => _showLogoutDialog(context)),
          ]);
        },
      )),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  TEACHER DASHBOARD
// ═══════════════════════════════════════════════════════════════════

class TeacherDashboard extends StatefulWidget {
  const TeacherDashboard({super.key});
  @override State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
  bool _loggingOut = false;

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(.5),
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 64, height: 64,
              decoration: const BoxDecoration(color: T.blueLight, shape: BoxShape.circle),
              child: const Icon(Icons.logout_rounded, color: T.blue, size: 28)),
          const SizedBox(height: 18),
          const Text('Logout', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: T.ink)),
          const SizedBox(height: 8),
          const Text('Are you sure you want to log out?', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: T.inkLight)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: _OutlineButton(label: 'Cancel', onTap: () => Navigator.pop(context, false))),
            const SizedBox(width: 12),
            Expanded(child: _PrimaryButton(label: 'Logout', onTap: () => Navigator.pop(context, true))),
          ]),
        ])),
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _loggingOut = true);
    try {
      // Clear session immediately so UI reacts at once
      _sessionNotifier.value = null;
      await FB.signOut();
    } catch (_) {
      // If sign-out fails, restore session state and show error
      if (mounted) {
        setState(() => _loggingOut = false);
        ScaffoldMessenger.of(context).showSnackBar(_buildSnack('Logout failed. Please try again.', isError: true));
      }
    }
  }

  @override Widget build(BuildContext context) {
    // Guard: session becomes null the moment logout clears _sessionNotifier,
    // but Flutter may rebuild this widget once before _AuthGate replaces it.
    if (_loggingOut || currentSession == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final session = currentSession!;
    final sid = session.schoolId;
    final tid = session.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: FB.teachers(sid).doc(tid).snapshots(),
      builder: (_, tSnap) {
        final teacher = tSnap.hasData && tSnap.data!.exists ? Teacher.fromDoc(tSnap.data!) : null;
        final classId = teacher?.classId;

        return Scaffold(
          backgroundColor: T.bg,
          body: SafeArea(child: classId == null
              ? _noClassView(teacher)
              : StreamBuilder<DocumentSnapshot>(
            stream: FB.classes(sid).doc(classId).snapshots(),
            builder: (_, clsSnap) {
              final myClass = clsSnap.hasData && clsSnap.data!.exists ? SchoolClass.fromDoc(clsSnap.data!) : null;
              return StreamBuilder<QuerySnapshot>(
                stream: FB.students(sid).where('classId', isEqualTo: classId).orderBy('name').snapshots(),
                builder: (_, studSnap) {
                  final students = studSnap.hasData ? studSnap.data!.docs.map(Student.fromDoc).toList() : <Student>[];
                  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
                  return StreamBuilder<QuerySnapshot>(
                    stream: FB.attendance(sid).where('classId', isEqualTo: classId).where('date', isEqualTo: today).snapshots(),
                    builder: (_, attSnap) {
                      final todayRec = attSnap.hasData && attSnap.data!.docs.isNotEmpty
                          ? AttendanceRecord.fromDoc(attSnap.data!.docs.first) : null;
                      final presentToday = todayRec?.attendance.values.where((v) => v).length;
                      final paid = students.where((s) => s.feePaid).length;
                      final unpaid = students.length - paid;

                      return ListView(padding: const EdgeInsets.all(20), children: [
                        Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Hello, ${teacher?.name ?? 'Teacher'}! 👋',
                                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: T.ink, letterSpacing: -.3)),
                            const SizedBox(height: 3),
                            Row(children: [
                              Container(width: 6, height: 6, decoration: const BoxDecoration(color: T.green, shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Text(teacher?.subject ?? '', style: const TextStyle(color: T.inkLight, fontSize: 13, fontWeight: FontWeight.w600)),
                            ]),
                          ])),
                          _InitialBubble(teacher?.name ?? 'T'),
                        ]),
                        const SizedBox(height: 22),

                        // Hero class card
                        Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF4C1D95), T.purple, T.purpleMid], begin: Alignment.topLeft, end: Alignment.bottomRight),
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [BoxShadow(color: T.purple.withOpacity(.4), blurRadius: 24, offset: const Offset(0, 10))],
                          ),
                          padding: const EdgeInsets.all(22),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Container(padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: Colors.white.withOpacity(.15), borderRadius: BorderRadius.circular(10)),
                                  child: const Icon(Icons.class_rounded, color: Colors.white, size: 16)),
                              const SizedBox(width: 10),
                              Text('My Class', style: TextStyle(color: Colors.white.withOpacity(.8), fontSize: 13, fontWeight: FontWeight.w700)),
                            ]),
                            const SizedBox(height: 10),
                            Text(myClass?.name ?? '...', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -.8)),
                            const SizedBox(height: 14),
                            Row(children: [
                              Text('${students.length} Students', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                              const SizedBox(width: 4),
                              Text('·', style: TextStyle(color: Colors.white.withOpacity(.4))),
                              const SizedBox(width: 4),
                              if (presentToday != null)
                                Text('$presentToday Present Today', style: TextStyle(color: Colors.white.withOpacity(.75), fontWeight: FontWeight.w600, fontSize: 13))
                              else
                                Text('Not marked today', style: TextStyle(color: Colors.white.withOpacity(.55), fontSize: 13)),
                            ]),
                            const SizedBox(height: 18),
                            Row(children: [
                              Expanded(child: _TeacherActionBtn('Mark Attendance', Icons.fact_check_rounded,
                                      () => Navigator.push(context, _slideRoute(MarkAttendanceScreen(classId: classId, sid: sid))))),
                              const SizedBox(width: 10),
                              Expanded(child: _TeacherActionBtn('View History', Icons.history_rounded,
                                      () => Navigator.push(context, _slideRoute(AttendanceHistoryScreen(classId: classId, sid: sid))))),
                            ]),
                          ]),
                        ),
                        const SizedBox(height: 20),

                        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Expanded(child: _StatTile(label: 'Students', value: '${students.length}', icon: Icons.people_rounded, color: T.blue)),
                          const SizedBox(width: 12),
                          Expanded(child: _StatTile(label: 'Unpaid', value: '$unpaid', icon: Icons.pending_rounded, color: unpaid > 0 ? T.red : T.green)),
                        ])),
                        const SizedBox(height: 22),

                        const Text('Quick Actions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.ink)),
                        const SizedBox(height: 12),
                        _ActionRow(icon: Icons.person_add_rounded, label: 'Add Student', sub: 'Enroll to ${myClass?.name ?? ''}', color: T.blue,
                            onTap: () => Navigator.push(context, _slideRoute(TeacherAddStudentScreen(classId: classId, className: myClass?.name ?? '', sid: sid)))),
                        _ActionRow(icon: Icons.account_balance_wallet_rounded, label: 'Manage Fees', sub: 'Mark fees for ${myClass?.name ?? ''}', color: T.green,
                            onTap: () => Navigator.push(context, _slideRoute(TeacherFeeScreen(classId: classId, className: myClass?.name ?? '', sid: sid)))),
                        const SizedBox(height: 8),
                        _LogoutButton(onTap: _logout),
                      ]);
                    },
                  );
                },
              );
            },
          )),
        );
      },
    );
  }

  Widget _noClassView(Teacher? teacher) => ListView(padding: const EdgeInsets.all(20), children: [
    Row(children: [
      Expanded(child: Text('Hello, ${teacher?.name ?? 'Teacher'}! 👋',
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: T.ink))),
      _InitialBubble(teacher?.name ?? 'T'),
    ]),
    const SizedBox(height: 32),
    Container(padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF4C1D95), T.purple], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Column(children: [
        Icon(Icons.warning_amber_rounded, color: Colors.white, size: 44),
        SizedBox(height: 14),
        Text('No Class Assigned', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
        SizedBox(height: 8),
        Text('Contact your administrator to get assigned to a class.', style: TextStyle(color: Colors.white70, fontSize: 14), textAlign: TextAlign.center),
      ]),
    ),
    const SizedBox(height: 24),
    _LogoutButton(onTap: _logout),
  ]);
}

class _TeacherActionBtn extends StatelessWidget {
  final String label; final IconData icon; final VoidCallback onTap;
  const _TeacherActionBtn(this.label, this.icon, this.onTap);
  @override Widget build(BuildContext context) => ElevatedButton.icon(
    onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label, style: const TextStyle(fontSize: 13)),
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.white.withOpacity(.2), foregroundColor: Colors.white,
      minimumSize: const Size(0, 44), elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.white.withOpacity(.3))),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  TEACHER ADD STUDENT
// ═══════════════════════════════════════════════════════════════════

class TeacherAddStudentScreen extends StatefulWidget {
  final String classId, className, sid;
  const TeacherAddStudentScreen({super.key, required this.classId, required this.className, required this.sid});
  @override State<TeacherAddStudentScreen> createState() => _TeacherAddStudentState();
}

class _TeacherAddStudentState extends State<TeacherAddStudentScreen> {
  final _name = TextEditingController(), _roll = TextEditingController(),
      _phone = TextEditingController(), _fee = TextEditingController();
  bool _loading = false;

  void _save() async {
    if ([_name, _roll, _phone, _fee].any((c) => c.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(_buildSnack('Please fill all fields', isError: true)); return;
    }
    setState(() => _loading = true);
    await FB.students(widget.sid).add({
      'classId': widget.classId, 'name': _name.text.trim(), 'rollNumber': _roll.text.trim(),
      'parentPhone': _phone.text.trim(), 'monthlyFee': double.tryParse(_fee.text) ?? 0, 'feePaid': false,
    });
    setState(() => _loading = false);
    if (mounted) { ScaffoldMessenger.of(context).showSnackBar(_buildSnack('${_name.text} added!')); Navigator.pop(context); }
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: _buildAppBar('Add Student'),
    body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
      Container(width: double.infinity, padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: T.purpleLight, borderRadius: BorderRadius.circular(16), border: Border.all(color: T.purple.withOpacity(.2))),
        child: Row(children: [
          const Icon(Icons.class_rounded, color: T.purple, size: 22),
          const SizedBox(width: 12),
          Text(widget.className, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: T.purple)),
        ]),
      ),
      const SizedBox(height: 16),
      _SurfaceCard(child: Column(children: [
        _SectionHeader('Student Information'),
        _LabeledField(ctrl: _name, label: 'Full Name', icon: Icons.person_outline_rounded),
        const SizedBox(height: 12),
        _LabeledField(ctrl: _roll, label: 'Roll Number', icon: Icons.tag_rounded),
        const SizedBox(height: 12),
        _LabeledField(ctrl: _phone, label: 'Parent Phone', icon: Icons.phone_outlined, type: TextInputType.phone),
        const SizedBox(height: 12),
        _LabeledField(ctrl: _fee, label: 'Monthly Fee (Rs)', icon: Icons.payments_outlined, type: TextInputType.number),
      ])),
      const SizedBox(height: 28),
      _PrimaryButton(label: 'Add Student', icon: Icons.person_add_rounded, onTap: _loading ? null : _save, loading: _loading),
    ])),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  TEACHER FEE SCREEN
// ═══════════════════════════════════════════════════════════════════

class TeacherFeeScreen extends StatefulWidget {
  final String classId, className, sid;
  const TeacherFeeScreen({super.key, required this.classId, required this.className, required this.sid});
  @override State<TeacherFeeScreen> createState() => _TeacherFeeState();
}

class _TeacherFeeState extends State<TeacherFeeScreen> {
  String _filter = 'all'; String _search = '';

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(child: StreamBuilder<QuerySnapshot>(
        stream: FB.students(widget.sid).where('classId', isEqualTo: widget.classId).orderBy('name').snapshots(),
        builder: (_, snap) {
          final all = snap.hasData ? snap.data!.docs.map(Student.fromDoc).toList() : <Student>[];
          final paid = all.where((s) => s.feePaid).length;
          final unpaid = all.length - paid;
          final collected = all.where((s) => s.feePaid).fold(0.0, (a, s) => a + s.monthlyFee);
          final total = all.fold(0.0, (a, s) => a + s.monthlyFee);
          final pct = all.isEmpty ? 0.0 : (paid / all.length).clamp(0.0, 1.0);
          final filtered = all.where((s) {
            final mF = _filter == 'all' || (_filter == 'paid' ? s.feePaid : !s.feePaid);
            final mS = _search.isEmpty || s.name.toLowerCase().contains(_search.toLowerCase());
            return mF && mS;
          }).toList();

          return Column(children: [
            Container(color: Colors.white, child: Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: Row(children: [
                _IconAction(Icons.arrow_back_ios_rounded, () => Navigator.pop(context), size: 18),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Fee Management', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: T.ink)),
                  Text(widget.className, style: const TextStyle(fontSize: 12, color: T.inkLight)),
                ])),
              ])),
              const SizedBox(height: 14),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _FeeHeroBanner(collected: collected, total: total, paid: paid, unpaid: unpaid, pct: pct)),
              const SizedBox(height: 12),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _SegmentedTabs(
                    labels: ['All', 'Paid', 'Unpaid'], counts: [all.length, paid, unpaid], colors: [T.blue, T.green, T.red],
                    selected: _filter == 'all' ? 0 : _filter == 'paid' ? 1 : 2,
                    onTap: (i) => setState(() => _filter = ['all', 'paid', 'unpaid'][i]),
                  )),
              Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: _SearchField(hint: 'Search by name…', onChanged: (v) => setState(() => _search = v))),
            ])),
            Container(height: 1, color: T.divider),
            Expanded(child: filtered.isEmpty
                ? _EmptyState(Icons.account_balance_wallet_rounded, 'No students', _filter == 'unpaid' ? 'All paid! 🎉' : 'No students found')
                : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _FeeCard(student: filtered[i], onToggle: () async {
                await FB.students(widget.sid).doc(filtered[i].id).update({'feePaid': !filtered[i].feePaid});
              }),
            )),
          ]);
        },
      )),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  MARK ATTENDANCE
// ═══════════════════════════════════════════════════════════════════

class MarkAttendanceScreen extends StatefulWidget {
  final String classId, sid;
  const MarkAttendanceScreen({super.key, required this.classId, required this.sid});
  @override State<MarkAttendanceScreen> createState() => _MarkAttState();
}

class _MarkAttState extends State<MarkAttendanceScreen> {
  final _date = DateFormat('yyyy-MM-dd').format(DateTime.now());
  Map<String, bool> _att = {};
  bool _initialized = false, _saving = false;

  @override Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FB.students(widget.sid).where('classId', isEqualTo: widget.classId).orderBy('name').snapshots(),
      builder: (_, studSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FB.attendance(widget.sid).where('classId', isEqualTo: widget.classId).where('date', isEqualTo: _date).snapshots(),
          builder: (_, attSnap) {
            final students = studSnap.hasData ? studSnap.data!.docs.map(Student.fromDoc).toList() : <Student>[];
            if (!_initialized && students.isNotEmpty) {
              AttendanceRecord? existing;
              if (attSnap.hasData && attSnap.data!.docs.isNotEmpty) existing = AttendanceRecord.fromDoc(attSnap.data!.docs.first);
              for (final s in students) _att[s.id] = existing?.attendance[s.id] ?? true;
              _initialized = true;
            }
            final present = _att.values.where((v) => v).length;
            final absent  = students.length - present;

            return Scaffold(
              appBar: _buildAppBar('Mark Attendance', subtitle: _date),
              body: Column(children: [
                Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(16, 12, 16, 14), child: Row(children: [
                  Expanded(child: _AttBadge('$present Present', T.green, T.greenLight)),
                  const SizedBox(width: 10),
                  Expanded(child: _AttBadge('$absent Absent', T.red, T.redLight)),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => setState(() { for (final k in _att.keys) _att[k] = true; }),
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(color: T.blueLight, borderRadius: BorderRadius.circular(10)),
                        child: const Text('All ✓', style: TextStyle(color: T.blue, fontWeight: FontWeight.w800, fontSize: 13))),
                  ),
                ])),
                Container(height: 1, color: T.divider),
                Expanded(child: students.isEmpty
                    ? const _EmptyState(Icons.people_rounded, 'No students', 'Add students to this class first')
                    : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                  itemCount: students.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final s = students[i]; final p = _att[s.id] ?? true;
                    return GestureDetector(
                      onTap: () => setState(() => _att[s.id] = !(p)),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: p ? T.greenLight : T.redLight,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: (p ? T.green : T.red).withOpacity(.25), width: 1.5),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        child: Row(children: [
                          _CircleInitial(s.name, p ? T.green : T.red, Colors.white, radius: 19),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, color: T.ink, fontSize: 15)),
                            Text('Roll #${s.rollNumber}', style: const TextStyle(fontSize: 12, color: T.inkLight)),
                          ])),
                          AnimatedSwitcher(duration: const Duration(milliseconds: 200),
                              child: Icon(p ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                  key: ValueKey(p), color: p ? T.green : T.red, size: 28)),
                        ]),
                      ),
                    );
                  },
                )),
                Padding(padding: const EdgeInsets.all(16), child: _PrimaryButton(
                  label: _saving ? 'Saving…' : 'Save Attendance',
                  icon: Icons.save_rounded,
                  onTap: _saving ? null : () => _saveAttendance(attSnap),
                  loading: _saving,
                )),
              ]),
            );
          },
        );
      },
    );
  }

  Future<void> _saveAttendance(AsyncSnapshot<QuerySnapshot> attSnap) async {
    setState(() => _saving = true);
    final data = {'classId': widget.classId, 'date': _date, 'attendance': _att};
    if (attSnap.hasData && attSnap.data!.docs.isNotEmpty) {
      await FB.attendance(widget.sid).doc(attSnap.data!.docs.first.id).update(data);
    } else {
      await FB.attendance(widget.sid).add(data);
    }
    setState(() => _saving = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(_buildSnack('Attendance saved!'));
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ATTENDANCE HISTORY
// ═══════════════════════════════════════════════════════════════════

class AttendanceHistoryScreen extends StatelessWidget {
  final String classId, sid;
  const AttendanceHistoryScreen({super.key, required this.classId, required this.sid});

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar('Attendance History'),
      body: StreamBuilder<QuerySnapshot>(
        stream: FB.attendance(sid).where('classId', isEqualTo: classId).orderBy('date', descending: true).snapshots(),
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final records = snap.data!.docs.map(AttendanceRecord.fromDoc).toList();
          if (records.isEmpty) return const _EmptyState(Icons.history_rounded, 'No records yet', 'Mark attendance to see history here');
          return StreamBuilder<QuerySnapshot>(
            stream: FB.students(sid).where('classId', isEqualTo: classId).snapshots(),
            builder: (_, studSnap) {
              final students = studSnap.hasData ? studSnap.data!.docs.map(Student.fromDoc).toList() : <Student>[];
              return ListView.separated(
                padding: const EdgeInsets.all(16), itemCount: records.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final r = records[i];
                  final total = students.length;
                  final present = r.attendance.values.where((v) => v).length;
                  final pct = total == 0 ? 0.0 : present / total;
                  final c  = pct >= .8 ? T.green : pct >= .5 ? T.blue : T.red;
                  final bg = pct >= .8 ? T.greenLight : pct >= .5 ? T.blueLight : T.redLight;
                  return InkWell(
                    onTap: () => Navigator.push(context, _slideRoute(AttendanceDetailScreen(record: r, sid: sid, classId: classId))),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: T.divider)),
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        Container(width: 48, height: 48,
                            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                            child: Icon(Icons.calendar_today_rounded, color: c, size: 22)),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.date, style: const TextStyle(fontWeight: FontWeight.w700, color: T.ink, fontSize: 15)),
                          const SizedBox(height: 6),
                          ClipRRect(borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(value: pct, minHeight: 5, backgroundColor: T.divider, color: c)),
                          const SizedBox(height: 5),
                          Text('$present / $total  ·  ${(pct * 100).round()}%', style: const TextStyle(color: T.inkLight, fontSize: 12)),
                        ])),
                        Icon(Icons.arrow_forward_ios_rounded, size: 14, color: T.inkFaint),
                      ]),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class AttendanceDetailScreen extends StatelessWidget {
  final AttendanceRecord record; final String sid, classId;
  const AttendanceDetailScreen({super.key, required this.record, required this.sid, required this.classId});

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(record.date),
      body: StreamBuilder<QuerySnapshot>(
        stream: FB.students(sid).where('classId', isEqualTo: classId).orderBy('name').snapshots(),
        builder: (_, snap) {
          final students = snap.hasData ? snap.data!.docs.map(Student.fromDoc).toList() : <Student>[];
          final present = record.attendance.values.where((v) => v).length;
          return Column(children: [
            Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(16, 12, 16, 14), child: Row(children: [
              Expanded(child: _AttBadge('$present Present', T.green, T.greenLight)),
              const SizedBox(width: 10),
              Expanded(child: _AttBadge('${students.length - present} Absent', T.red, T.redLight)),
            ])),
            Container(height: 1, color: T.divider),
            Expanded(child: ListView.separated(padding: const EdgeInsets.all(16), itemCount: students.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final s = students[i]; final p = record.attendance[s.id] ?? false;
                return Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: T.divider)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    _CircleInitial(s.name, p ? T.green : T.red, p ? T.greenLight : T.redLight, radius: 17),
                    const SizedBox(width: 12),
                    Expanded(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600, color: T.ink))),
                    _StatusChip(p ? 'Present' : 'Absent', p ? T.green : T.red, p ? T.greenLight : T.redLight),
                  ]),
                );
              },
            )),
          ]);
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  DIALOGS
// ═══════════════════════════════════════════════════════════════════

void _showDeleteDialog(BuildContext context, {required String title, required String name,
  required String description, required Future<void> Function() onConfirm}) {
  showDialog(context: context, barrierColor: Colors.black.withOpacity(.5),
      builder: (_) => _DeleteDialog(title: title, name: name, description: description, onConfirm: onConfirm));
}

class _DeleteDialog extends StatefulWidget {
  final String title, name, description; final Future<void> Function() onConfirm;
  const _DeleteDialog({required this.title, required this.name, required this.description, required this.onConfirm});
  @override State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  bool _loading = false;
  Future<void> _confirm() async {
    setState(() => _loading = true); await widget.onConfirm(); setState(() => _loading = false);
    if (mounted) Navigator.pop(context);
  }
  @override Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 28),
    child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 64, height: 64, decoration: const BoxDecoration(color: T.redLight, shape: BoxShape.circle),
          child: const Icon(Icons.delete_outline_rounded, color: T.red, size: 30)),
      const SizedBox(height: 18),
      Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: T.ink)),
      const SizedBox(height: 8),
      Text(widget.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.inkMid), textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: T.redLight, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: T.amber, size: 16), const SizedBox(width: 8),
            Expanded(child: Text(widget.description, style: const TextStyle(fontSize: 13, color: T.inkMid, height: 1.4))),
          ])),
      const SizedBox(height: 22),
      Row(children: [
        Expanded(child: _OutlineButton(label: 'Cancel', onTap: () => Navigator.pop(context))),
        const SizedBox(width: 12),
        Expanded(child: _DangerButton(label: 'Delete', loading: _loading, onTap: _loading ? null : _confirm)),
      ]),
    ])),
  );
}

void _showLogoutDialog(BuildContext context) {
  showDialog(context: context, barrierColor: Colors.black.withOpacity(.5), builder: (_) => _LogoutDialog());
}

class _LogoutDialog extends StatelessWidget {
  @override Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 28),
    child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 64, height: 64, decoration: const BoxDecoration(color: T.blueLight, shape: BoxShape.circle),
          child: const Icon(Icons.logout_rounded, color: T.blue, size: 28)),
      const SizedBox(height: 18),
      const Text('Logout', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: T.ink)),
      const SizedBox(height: 8),
      const Text('Are you sure you want to log out?', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: T.inkLight)),
      const SizedBox(height: 24),
      Row(children: [
        Expanded(child: _OutlineButton(label: 'Cancel', onTap: () => Navigator.pop(context))),
        const SizedBox(width: 12),
        Expanded(child: _PrimaryButton(label: 'Logout', onTap: () async {
          Navigator.pop(context);
          await FB.signOut();
          // _AuthGate listener fires automatically
        })),
      ]),
    ])),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  REUSABLE UI
// ═══════════════════════════════════════════════════════════════════

class _SurfaceCard extends StatelessWidget {
  final Widget child;
  const _SurfaceCard({required this.child});
  @override Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: T.divider),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 16, offset: const Offset(0, 4))]),
    padding: const EdgeInsets.all(20),
    child: child,
  );
}

class _LabeledField extends StatelessWidget {
  final TextEditingController ctrl; final String label; final IconData icon;
  final TextInputType type; final bool obscure; final bool readOnly;
  const _LabeledField({required this.ctrl, required this.label, required this.icon,
    this.type = TextInputType.text, this.obscure = false, this.readOnly = false});
  @override Widget build(BuildContext context) => TextField(
    controller: ctrl, keyboardType: type, obscureText: obscure, readOnly: readOnly,
    style: const TextStyle(fontFamily: 'Nunito', fontSize: 15, color: T.ink),
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, color: T.inkFaint, size: 20)),
  );
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: T.inkFaint, letterSpacing: 1.0)),
  );
}

class _PrimaryButton extends StatelessWidget {
  final String label; final IconData? icon; final VoidCallback? onTap; final bool loading; final Color? color;
  const _PrimaryButton({required this.label, this.icon, this.onTap, this.loading = false, this.color});
  @override Widget build(BuildContext context) {
    final c = color ?? T.blue;
    return SizedBox(width: double.infinity, height: 52,
      child: Material(color: onTap == null ? c.withOpacity(.5) : c, borderRadius: BorderRadius.circular(14),
        child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14), splashColor: Colors.white.withOpacity(.2),
          child: Center(child: loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, color: Colors.white, size: 18), const SizedBox(width: 8)],
            Text(label, style: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white)),
          ])),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final String label; final IconData? icon; final VoidCallback? onTap;
  const _OutlineButton({required this.label, this.icon, this.onTap});
  @override Widget build(BuildContext context) => SizedBox(width: double.infinity, height: 52,
    child: Material(color: Colors.white, borderRadius: BorderRadius.circular(14),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: T.divider, width: 1.5)),
          child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, color: T.inkMid, size: 18), const SizedBox(width: 8)],
            Text(label, style: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700, fontSize: 15, color: T.inkMid)),
          ])),
        ),
      ),
    ),
  );
}

class _DangerButton extends StatelessWidget {
  final String label; final VoidCallback? onTap; final bool loading;
  const _DangerButton({required this.label, this.onTap, this.loading = false});
  @override Widget build(BuildContext context) => SizedBox(width: double.infinity, height: 52,
    child: Material(color: onTap == null ? T.red.withOpacity(.5) : T.red, borderRadius: BorderRadius.circular(14),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14),
        child: Center(child: loading
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : Text(label, style: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white))),
      ),
    ),
  );
}

class _GhostButton extends StatelessWidget {
  final String label; final VoidCallback? onTap; final Color? color;
  const _GhostButton(this.label, {this.onTap, this.color});
  @override Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(foregroundColor: color ?? T.inkLight,
        textStyle: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700, fontSize: 14)),
    child: Text(label),
  );
}

class _CircleInitial extends StatelessWidget {
  final String name; final Color fg, bg; final double radius;
  const _CircleInitial(this.name, this.fg, this.bg, {required this.radius});
  @override Widget build(BuildContext context) => CircleAvatar(
    radius: radius, backgroundColor: bg,
    child: Text(name[0].toUpperCase(), style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: radius * .85)),
  );
}

class _InitialBubble extends StatelessWidget {
  final String name;
  const _InitialBubble(this.name);
  @override Widget build(BuildContext context) => Container(
    width: 46, height: 46,
    decoration: BoxDecoration(color: T.blueLight, shape: BoxShape.circle, border: Border.all(color: T.blue.withOpacity(.2), width: 2)),
    child: Center(child: Text(name[0].toUpperCase(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: T.blue))),
  );
}

class _StatusChip extends StatelessWidget {
  final String label; final Color fg, bg;
  const _StatusChip(this.label, this.fg, this.bg);
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800)),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon; final String label;
  const _InfoRow(this.icon, this.label);
  @override Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 12, color: T.inkFaint), const SizedBox(width: 5),
    Flexible(child: Text(label, style: const TextStyle(color: T.inkLight, fontSize: 13), overflow: TextOverflow.ellipsis)),
  ]);
}

class _StatTile extends StatelessWidget {
  final String label, value; final IconData icon; final Color color;
  const _StatTile({required this.label, required this.value, required this.icon, required this.color});
  @override Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: T.divider),
      boxShadow: [BoxShadow(color: color.withOpacity(.05), blurRadius: 12, offset: const Offset(0, 4))],
    ),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(.1), borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 12),
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color, letterSpacing: -1.0), maxLines: 1),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: T.inkLight, fontWeight: FontWeight.w600), maxLines: 1),
      ],
    ),
  );
}

class _ActionRow extends StatelessWidget {
  final IconData icon; final String label, sub; final Color color; final VoidCallback onTap;
  const _ActionRow({required this.icon, required this.label, required this.sub, required this.color, required this.onTap});
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(color: Colors.white, borderRadius: BorderRadius.circular(16),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16),
        child: Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: T.divider)),
          child: Row(children: [
            Container(width: 44, height: 44,
                decoration: BoxDecoration(color: color.withOpacity(.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 22)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: T.ink)),
              Text(sub, style: const TextStyle(fontSize: 12, color: T.inkLight)),
            ])),
            Container(width: 28, height: 28,
                decoration: BoxDecoration(color: color.withOpacity(.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.arrow_forward_rounded, size: 14, color: color)),
          ]),
        ),
      ),
    ),
  );
}

class _CardActions extends StatelessWidget {
  final IconData leftIcon, rightIcon; final String leftLabel, rightLabel; final Color leftColor, rightColor;
  final VoidCallback onLeft, onRight;
  const _CardActions({required this.leftIcon, required this.leftLabel, required this.leftColor, required this.onLeft,
    required this.rightIcon, required this.rightLabel, required this.rightColor, required this.onRight});
  @override Widget build(BuildContext context) => IntrinsicHeight(child: Row(children: [
    Expanded(child: TextButton.icon(onPressed: onLeft, icon: Icon(leftIcon, size: 15, color: leftColor),
        label: Text(leftLabel, style: TextStyle(color: leftColor, fontWeight: FontWeight.w700, fontSize: 13)),
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 11)))),
    VerticalDivider(width: 1, color: T.dividerFaint),
    Expanded(child: TextButton.icon(onPressed: onRight, icon: Icon(rightIcon, size: 15, color: rightColor),
        label: Text(rightLabel, style: TextStyle(color: rightColor, fontWeight: FontWeight.w700, fontSize: 13)),
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 11)))),
  ]));
}

class _AttBadge extends StatelessWidget {
  final String label; final Color color, bg;
  const _AttBadge(this.label, this.color, this.bg);
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

class _FilterPill extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap; final Color color;
  const _FilterPill(this.label, this.selected, this.onTap, this.color);
  @override Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200), margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: selected ? color : Colors.white, borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : T.divider),
          boxShadow: selected ? [BoxShadow(color: color.withOpacity(.2), blurRadius: 8, offset: const Offset(0, 2))] : []),
      child: Text(label, style: TextStyle(color: selected ? Colors.white : T.inkLight, fontWeight: FontWeight.w700, fontSize: 13)),
    ),
  );
}

class _SearchField extends StatelessWidget {
  final String hint; final ValueChanged<String> onChanged;
  const _SearchField({required this.hint, required this.onChanged});
  @override Widget build(BuildContext context) => TextField(
    onChanged: onChanged, style: const TextStyle(fontFamily: 'Nunito', fontSize: 14),
    decoration: InputDecoration(hintText: hint, prefixIcon: const Icon(Icons.search_rounded, color: T.inkFaint, size: 20),
        isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: T.divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: T.divider)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: T.blue, width: 2)),
        filled: true, fillColor: T.bg),
  );
}

class _ClassDropdown extends StatelessWidget {
  final List<SchoolClass> classes; final String? value; final ValueChanged<String?> onChanged;
  const _ClassDropdown({required this.classes, this.value, required this.onChanged});
  @override Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: T.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: T.divider)),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: DropdownButtonHideUnderline(child: DropdownButton<String?>(
      value: value,
      hint: const Text('Class', style: TextStyle(fontSize: 13, color: T.inkLight, fontFamily: 'Nunito')),
      items: [
        const DropdownMenuItem(value: null, child: Text('All', style: TextStyle(fontFamily: 'Nunito', fontSize: 13))),
        ...classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, style: const TextStyle(fontFamily: 'Nunito', fontSize: 13)))),
      ],
      onChanged: onChanged, icon: const Icon(Icons.expand_more_rounded, size: 18, color: T.inkLight), isDense: true,
    )),
  );
}

class _DatePickerField extends StatelessWidget {
  final String date; final ValueChanged<String> onChanged;
  const _DatePickerField({required this.date, required this.onChanged});
  @override Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final p = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now(),
          builder: (ctx, child) => Theme(data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: T.blue, onPrimary: Colors.white)), child: child!));
      if (p != null) onChanged(DateFormat('yyyy-MM-dd').format(p));
    },
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: T.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: T.divider)),
      child: Row(children: [
        const Icon(Icons.calendar_today_rounded, color: T.inkFaint, size: 18), const SizedBox(width: 12),
        Expanded(child: Text(date, style: const TextStyle(fontFamily: 'Nunito', color: T.ink, fontWeight: FontWeight.w600))),
        const Icon(Icons.expand_more_rounded, color: T.inkFaint, size: 18),
      ]),
    ),
  );
}

class _IconAction extends StatelessWidget {
  final IconData icon; final VoidCallback? onTap; final Color? color; final double? size;
  const _IconAction(this.icon, this.onTap, {this.color, this.size});
  @override Widget build(BuildContext context) => Material(color: T.bg, borderRadius: BorderRadius.circular(10),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10),
          child: Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: T.divider)),
              child: Icon(icon, color: color ?? T.inkMid, size: size ?? 20))));
}

class _EmptyState extends StatelessWidget {
  final IconData icon; final String title, sub;
  const _EmptyState(this.icon, this.title, this.sub);
  @override Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(48),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80,
          decoration: BoxDecoration(color: T.bg, borderRadius: BorderRadius.circular(20), border: Border.all(color: T.divider)),
          child: Icon(icon, size: 38, color: T.divider)),
      const SizedBox(height: 18),
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: T.ink), textAlign: TextAlign.center),
      const SizedBox(height: 6),
      Text(sub, style: const TextStyle(color: T.inkLight, fontSize: 14), textAlign: TextAlign.center),
    ]),
  ));
}

class _SettingRow extends StatelessWidget {
  final IconData icon; final String title, sub; final Color color; final VoidCallback onTap;
  const _SettingRow(this.icon, this.title, this.sub, this.color, this.onTap);
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(color: Colors.white, borderRadius: BorderRadius.circular(16),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16),
        child: Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: T.divider)),
          child: Row(children: [
            Container(width: 44, height: 44,
                decoration: BoxDecoration(color: color.withOpacity(.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 22)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: T.ink)),
              Text(sub, style: const TextStyle(fontSize: 12, color: T.inkLight)),
            ])),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: color.withOpacity(.5)),
          ]),
        ),
      ),
    ),
  );
}

class _LogoutButton extends StatelessWidget {
  final VoidCallback onTap;
  const _LogoutButton({required this.onTap});
  @override Widget build(BuildContext context) => Material(color: T.redLight, borderRadius: BorderRadius.circular(16),
    child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap,
      child: Container(padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: T.red.withOpacity(.2))),
        child: const Row(children: [
          Icon(Icons.logout_rounded, color: T.red, size: 22), SizedBox(width: 14),
          Text('Logout', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: T.red)),
          Spacer(),
          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: T.red),
        ]),
      ),
    ),
  );
}

class _FeeHeroBanner extends StatelessWidget {
  final double collected, total, pct; final int paid, unpaid;
  const _FeeHeroBanner({required this.collected, required this.total, required this.paid, required this.unpaid, required this.pct});
  @override Widget build(BuildContext context) {
    final c = pct >= .8 ? [const Color(0xFF047857), T.green] : pct >= .5 ? [T.blue, T.blueMid] : [T.red, T.redMid];
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: c, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: c[0].withOpacity(.3), blurRadius: 20, offset: const Offset(0, 8))]),
      padding: const EdgeInsets.all(18),
      child: Column(children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Rs ${_fmt(collected)} collected', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
            Text('of Rs ${_fmt(total)} total', style: TextStyle(color: Colors.white.withOpacity(.7), fontSize: 12)),
          ])),
          _RingProgress(pct),
        ]),
        const SizedBox(height: 14),
        ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(
            value: pct, minHeight: 6, backgroundColor: Colors.white.withOpacity(.2), color: Colors.white)),
        const SizedBox(height: 10),
        Row(children: [
          Text('$paid Paid', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(width: 4), Text('·', style: TextStyle(color: Colors.white.withOpacity(.4))), const SizedBox(width: 4),
          Text('$unpaid Unpaid', style: TextStyle(color: Colors.white.withOpacity(.7), fontWeight: FontWeight.w600, fontSize: 13)),
          const Spacer(),
          Text('Rs ${_fmt(total - collected)} pending', style: TextStyle(color: Colors.white.withOpacity(.65), fontSize: 12)),
        ]),
      ]),
    );
  }
}

class _RingProgress extends StatelessWidget {
  final double pct;
  const _RingProgress(this.pct);
  @override Widget build(BuildContext context) => SizedBox(width: 54, height: 54, child: Stack(alignment: Alignment.center, children: [
    CircularProgressIndicator(value: pct, strokeWidth: 5, backgroundColor: Colors.white.withOpacity(.2), color: Colors.white),
    Text('${(pct * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
  ]));
}

class _SegmentedTabs extends StatelessWidget {
  final List<String> labels; final List<int> counts; final List<Color> colors; final int selected; final ValueChanged<int> onTap;
  const _SegmentedTabs({required this.labels, required this.counts, required this.colors, required this.selected, required this.onTap});
  @override Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: T.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: T.divider)),
    padding: const EdgeInsets.all(4),
    child: Row(children: List.generate(labels.length, (i) => Expanded(child: GestureDetector(
      onTap: () => onTap(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected == i ? colors[i] : Colors.transparent, borderRadius: BorderRadius.circular(9),
          boxShadow: selected == i ? [BoxShadow(color: colors[i].withOpacity(.3), blurRadius: 8, offset: const Offset(0, 3))] : [],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${counts[i]}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: selected == i ? Colors.white : T.ink)),
          Text(labels[i], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selected == i ? Colors.white.withOpacity(.85) : T.inkLight)),
        ]),
      ),
    )))),
  );
}

class _FeeCard extends StatelessWidget {
  final Student student; final VoidCallback onToggle;
  const _FeeCard({required this.student, required this.onToggle});
  @override Widget build(BuildContext context) {
    final paid = student.feePaid; final ac = paid ? T.green : T.red; final bg = paid ? T.greenLight : T.redLight;
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ac.withOpacity(.2), width: 1.5),
          boxShadow: [BoxShadow(color: ac.withOpacity(.06), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 10), child: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            CircleAvatar(radius: 24, backgroundColor: bg,
                child: Text(student.name[0].toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, color: ac, fontSize: 20))),
            Positioned(bottom: -1, right: -1,
                child: Container(width: 13, height: 13,
                    decoration: BoxDecoration(color: ac, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
          ]),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(student.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: T.ink)),
            const SizedBox(height: 2),
            Row(children: [
              Icon(Icons.tag_rounded, size: 11, color: T.inkFaint), const SizedBox(width: 3),
              Text(student.rollNumber, style: const TextStyle(fontSize: 12, color: T.inkLight)),
            ]),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                child: Text('Rs ${_fmt(student.monthlyFee)}', style: TextStyle(color: ac, fontWeight: FontWeight.w900, fontSize: 14))),
            const SizedBox(height: 3),
            Text('per month', style: TextStyle(color: ac.withOpacity(.55), fontSize: 10)),
          ]),
        ])),
        GestureDetector(onTap: onToggle,
            child: Container(
              decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16))),
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(paid ? Icons.remove_circle_outline_rounded : Icons.check_circle_outline_rounded, color: ac, size: 18),
                const SizedBox(width: 8),
                Text(paid ? 'Mark as Unpaid' : 'Mark as Paid ✓', style: TextStyle(color: ac, fontWeight: FontWeight.w800, fontSize: 14)),
              ]),
            )),
      ]),
    );
  }
}

class _BulkActionSheet extends StatelessWidget {
  final VoidCallback onMarkAllPaid, onMarkAllUnpaid;
  const _BulkActionSheet({required this.onMarkAllPaid, required this.onMarkAllUnpaid});
  @override Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
    child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 14, bottom: 8), decoration: BoxDecoration(color: T.divider, borderRadius: BorderRadius.circular(2))),
      Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(children: [const Expanded(child: Text('Bulk Actions', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.ink))),
            _IconAction(Icons.close_rounded, () => Navigator.pop(context), color: T.inkLight)])),
      const Divider(height: 1, color: T.divider),
      const SizedBox(height: 8),
      _SheetAction(icon: Icons.check_circle_rounded, label: 'Mark All Visible as Paid', color: T.green, onTap: () { Navigator.pop(context); onMarkAllPaid(); }),
      _SheetAction(icon: Icons.cancel_rounded, label: 'Mark All Visible as Unpaid', color: T.red, onTap: () { Navigator.pop(context); onMarkAllUnpaid(); }),
      const SizedBox(height: 8),
    ])),
  );
}

class _SheetAction extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _SheetAction({required this.icon, required this.label, required this.color, required this.onTap});
  @override Widget build(BuildContext context) => InkWell(onTap: onTap,
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), child: Row(children: [
      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20)),
      const SizedBox(width: 14),
      Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
    ])),
  );
}

// Credential row used inside the teacher-credentials dialog
class _CredRow extends StatefulWidget {
  final String label, value;
  final bool isPassword;
  const _CredRow({required this.label, required this.value, this.isPassword = false});
  @override State<_CredRow> createState() => _CredRowState();
}

class _CredRowState extends State<_CredRow> {
  bool _obscure = true;

  @override Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 72,
        child: Text(widget.label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: T.inkFaint, letterSpacing: .4)),
      ),
      Expanded(child: Text(
        widget.isPassword && _obscure ? '•' * widget.value.length : widget.value,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: T.ink),
      )),
      // Copy button
      GestureDetector(
        onTap: () {
          Clipboard.setData(ClipboardData(text: widget.value));
          ScaffoldMessenger.of(context).showSnackBar(
            _buildSnack('${widget.label} copied!'),
          );
        },
        child: const Icon(Icons.copy_rounded, size: 16, color: T.inkFaint),
      ),
      if (widget.isPassword) ...[
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => setState(() => _obscure = !_obscure),
          child: Icon(
            _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
            size: 16, color: T.inkFaint,
          ),
        ),
      ],
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════
//  HELPERS
// ═══════════════════════════════════════════════════════════════════

String _fmt(double v) => NumberFormat('#,##0').format(v);

AppBar _buildAppBar(String title, {String? subtitle, List<Widget>? actions}) => AppBar(
  title: subtitle != null
      ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title),
    Text(subtitle, style: const TextStyle(fontSize: 12, color: T.inkLight, fontWeight: FontWeight.w500)),
  ]) : Text(title),
  actions: actions,
  bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: T.divider)),
);

SnackBar _buildSnack(String msg, {bool isError = false}) => SnackBar(
  content: Row(children: [
    Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: Colors.white, size: 18),
    const SizedBox(width: 10),
    Expanded(child: Text(msg, style: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700, fontSize: 14))),
  ]),
  backgroundColor: isError ? T.red : T.green,
  behavior: SnackBarBehavior.floating,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  margin: const EdgeInsets.all(16), duration: const Duration(seconds: 3), elevation: 4,
);

PageRoute _fadeRoute(Widget page) => PageRouteBuilder(
  pageBuilder: (_, __, ___) => page,
  transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
  transitionDuration: const Duration(milliseconds: 300),
);

PageRoute _slideRoute(Widget page) => PageRouteBuilder(
  pageBuilder: (_, __, ___) => page,
  transitionsBuilder: (_, anim, __, child) => SlideTransition(
    position: Tween(begin: const Offset(1, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
    child: child,
  ),
  transitionDuration: const Duration(milliseconds: 320),
);

// Extension for auth state stream
extension on FirebaseAuth {
  Stream<User?> userChangedEvents() => authStateChanges();
}