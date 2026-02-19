import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  static Future<String> createTeacherAuthAccount(String email, String password) async {
    FirebaseApp? secondaryApp;
    try {
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
      await secondaryApp.delete();
      return uid;
    } on FirebaseAuthException {
      try { await secondaryApp?.delete(); } catch (_) {}
      rethrow;
    } catch (e) {
      try { await secondaryApp?.delete(); } catch (_) {}
      rethrow;
    }
  }

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

Future<void> performLogout(BuildContext context) async {
  await FB.signOut();
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
  );
}

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
//  ONBOARDING COLORS
// ═══════════════════════════════════════════════════════════════════

class OC {
  static const Color navy       = Color(0xFF0A1628);
  static const Color navyMid    = Color(0xFF0F2040);
  static const Color blue       = Color(0xFF2563EB);
  static const Color blueBright = Color(0xFF3B82F6);
  static const Color cyan       = Color(0xFF06B6D4);
  static const Color indigo     = Color(0xFF4F46E5);
  static const Color violet     = Color(0xFF7C3AED);
  static const Color amber      = Color(0xFFF59E0B);
  static const Color emerald    = Color(0xFF10B981);
  static const Color white      = Colors.white;
  static const Color white20    = Color(0x33FFFFFF);
  static const Color white10    = Color(0x1AFFFFFF);
}

// ═══════════════════════════════════════════════════════════════════
//  APP ROOT  →  Splash → Onboarding (first run) → Auth
// ═══════════════════════════════════════════════════════════════════

class EduTrackApp extends StatelessWidget {
  const EduTrackApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'EduTrack', theme: T.theme, debugShowCheckedModeBanner: false,
    home: const AppEntryPoint(),
  );
}

enum _Phase { splash, onboarding, auth }

class AppEntryPoint extends StatefulWidget {
  const AppEntryPoint({super.key});
  @override State<AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends State<AppEntryPoint> {
  _Phase _phase = _Phase.splash;

  @override Widget build(BuildContext context) {
    return switch (_phase) {
      _Phase.splash     => SplashScreen(onComplete: _afterSplash),
      _Phase.onboarding => OnboardingScreen(onDone: _afterOnboarding),
      _Phase.auth       => const AuthGate(),
    };
  }

  Future<void> _afterSplash() async {
    final prefs = await SharedPreferences.getInstance();
    final seen  = prefs.getBool('onboarding_done') ?? false;
    if (mounted) setState(() => _phase = seen ? _Phase.auth : _Phase.onboarding);
  }

  Future<void> _afterOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (mounted) setState(() => _phase = _Phase.auth);
  }
}

// ═══════════════════════════════════════════════════════════════════
//  AUTH GATE
// ═══════════════════════════════════════════════════════════════════

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
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
      sessionNotifier.value = null;
      if (mounted) setState(() => _loading = false);
      return;
    }
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
      uid: user.uid, role: meta['role'],
      schoolId: meta['schoolId'], teacherId: meta['teacherId'],
    );
    if (mounted) setState(() => _loading = false);
  }

  @override Widget build(BuildContext context) {
    if (_loading) return const _LoadingScreen();
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
//  LOADING SCREEN  (shown while Firebase checks auth state)
// ═══════════════════════════════════════════════════════════════════

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override Widget build(BuildContext context) => const Scaffold(
    backgroundColor: T.bg,
    body: Center(child: CircularProgressIndicator(color: T.blue, strokeWidth: 2.5)),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  ANIMATED SPLASH SCREEN
// ═══════════════════════════════════════════════════════════════════

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const SplashScreen({super.key, required this.onComplete});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _bgCtrl;
  late AnimationController _logoCtrl;
  late AnimationController _textCtrl;
  late AnimationController _particleCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _exitCtrl;

  late Animation<double> _bgAnim;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _logoRotate;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;
  late Animation<double> _particleAnim;
  late Animation<double> _pulseAnim;
  late Animation<double> _exitScale;
  late Animation<double> _exitOpacity;

  @override void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _bgCtrl       = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _logoCtrl     = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _textCtrl     = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _particleCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _pulseCtrl    = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
    _exitCtrl     = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

    _bgAnim      = CurvedAnimation(parent: _bgCtrl, curve: Curves.easeOut);
    _logoScale   = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut));
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _logoCtrl, curve: const Interval(0.0, 0.5, curve: Curves.easeOut)));
    _logoRotate  = Tween<double>(begin: -0.3, end: 0.0).animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack));
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut));
    _textSlide   = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(CurvedAnimation(parent: _textCtrl, curve: Curves.easeOutCubic));
    _particleAnim = CurvedAnimation(parent: _particleCtrl, curve: Curves.linear);
    _pulseAnim   = Tween<double>(begin: 0.95, end: 1.05).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _exitScale   = Tween<double>(begin: 1.0, end: 8.0).animate(CurvedAnimation(parent: _exitCtrl, curve: Curves.easeInCubic));
    _exitOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(CurvedAnimation(parent: _exitCtrl, curve: const Interval(0.5, 1.0)));

    _runSequence();
  }

  Future<void> _runSequence() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _bgCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    _logoCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 600));
    _textCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 2200));
    _particleCtrl.stop();
    _pulseCtrl.stop();
    await _exitCtrl.forward();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) widget.onComplete();
  }

  @override void dispose() {
    _bgCtrl.dispose(); _logoCtrl.dispose(); _textCtrl.dispose();
    _particleCtrl.dispose(); _pulseCtrl.dispose(); _exitCtrl.dispose();
    super.dispose();
  }

  @override Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_bgCtrl, _logoCtrl, _textCtrl, _particleCtrl, _pulseCtrl, _exitCtrl]),
      builder: (_, __) => Scaffold(
        backgroundColor: OC.navy,
        body: Stack(children: [
          // Gradient bg
          Positioned.fill(child: _SplashGradient(progress: _bgAnim.value)),
          // Particles
          Positioned.fill(child: CustomPaint(painter: _ParticlePainter(_particleAnim.value))),
          // Orbital rings
          Center(child: _OrbitalRings(pulse: _pulseAnim.value, opacity: _logoOpacity.value)),
          // Logo + text
          Center(child: Transform.scale(
            scale: _exitScale.value,
            child: Opacity(
              opacity: _exitOpacity.value,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Transform.rotate(
                  angle: _logoRotate.value,
                  child: Transform.scale(
                    scale: _logoScale.value,
                    child: Opacity(opacity: _logoOpacity.value, child: const _SplashLogo()),
                  ),
                ),
                const SizedBox(height: 32),
                SlideTransition(
                  position: _textSlide,
                  child: FadeTransition(
                    opacity: _textOpacity,
                    child: Column(children: [
                      ShaderMask(
                        shaderCallback: (b) => const LinearGradient(
                          colors: [OC.white, OC.cyan, OC.blueBright],
                        ).createShader(b),
                        child: const Text('EduTrack', style: TextStyle(
                          fontSize: 48, fontWeight: FontWeight.w900,
                          color: OC.white, letterSpacing: -2, fontFamily: 'Nunito',
                        )),
                      ),
                      const SizedBox(height: 8),
                      Text('Smart School Management', style: TextStyle(
                        fontSize: 15, color: OC.white.withOpacity(0.55),
                        fontWeight: FontWeight.w600, letterSpacing: 2.5, fontFamily: 'Nunito',
                      )),
                    ]),
                  ),
                ),
              ]),
            ),
          )),
          // Bottom dots
          Positioned(bottom: 60, left: 0, right: 0,
            child: FadeTransition(opacity: _textOpacity, child: Column(children: [
              const _PulsingDots(),
              const SizedBox(height: 16),
            ])),
          ),
        ]),
      ),
    );
  }
}

class _SplashGradient extends StatelessWidget {
  final double progress;
  const _SplashGradient({required this.progress});
  @override Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: const Alignment(-0.3, -0.5),
        radius: 1.5,
        colors: [
          Color.lerp(OC.navy, OC.indigo.withOpacity(0.6), progress)!,
          Color.lerp(OC.navy, OC.navyMid, progress)!,
          OC.navy,
        ],
        stops: const [0.0, 0.5, 1.0],
      ),
    ),
  );
}

class _ParticlePainter extends CustomPainter {
  final double t;
  _ParticlePainter(this.t);
  @override void paint(Canvas canvas, Size size) {
    final rng = math.Random(42);
    final paint = Paint()..style = PaintingStyle.fill;
    const colors = [OC.cyan, OC.blueBright, OC.violet, OC.amber];
    for (int i = 0; i < 40; i++) {
      final x     = rng.nextDouble() * size.width;
      final y     = rng.nextDouble() * size.height;
      final speed = 0.3 + rng.nextDouble() * 0.7;
      final radius = 1.0 + rng.nextDouble() * 2.5;
      final phase = rng.nextDouble();
      final opacity = (math.sin((t + phase) * math.pi * 2) + 1) / 2 * 0.4 + 0.05;
      final cx = x + math.sin((t + phase) * math.pi * 2) * 20;
      final cy = (y - (t * speed * 80)) % size.height;
      paint.color = colors[i % colors.length].withOpacity(opacity);
      canvas.drawCircle(Offset(cx, (cy + size.height) % size.height), radius, paint);
    }
  }
  @override bool shouldRepaint(_ParticlePainter old) => old.t != t;
}

class _OrbitalRings extends StatelessWidget {
  final double pulse, opacity;
  const _OrbitalRings({required this.pulse, required this.opacity});
  @override Widget build(BuildContext context) => Opacity(
    opacity: opacity.clamp(0.0, 1.0),
    child: Transform.scale(scale: pulse,
      child: SizedBox(width: 300, height: 300,
        child: Stack(alignment: Alignment.center, children: [
          _Ring(size: 280, color: OC.blue.withOpacity(0.08), width: 1),
          _Ring(size: 220, color: OC.cyan.withOpacity(0.12), width: 1.5),
          _Ring(size: 160, color: OC.indigo.withOpacity(0.15), width: 2),
        ]),
      ),
    ),
  );
}

class _Ring extends StatelessWidget {
  final double size; final Color color; final double width;
  const _Ring({required this.size, required this.color, required this.width});
  @override Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: width)),
  );
}

class _SplashLogo extends StatelessWidget {
  const _SplashLogo();
  @override Widget build(BuildContext context) => Container(
    width: 110, height: 110,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF1E3A8A), OC.blue, OC.cyan],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(32),
      boxShadow: [
        BoxShadow(color: OC.blue.withOpacity(0.6), blurRadius: 40, spreadRadius: 5),
        BoxShadow(color: OC.cyan.withOpacity(0.3), blurRadius: 80, spreadRadius: 10),
      ],
    ),
    child: Stack(alignment: Alignment.center, children: [
      Positioned(top: 0, left: 0, right: 0, height: 55,
        child: Container(decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          gradient: LinearGradient(colors: [OC.white.withOpacity(0.2), Colors.transparent],
              begin: Alignment.topCenter, end: Alignment.bottomCenter),
        )),
      ),
      const Icon(Icons.school_rounded, color: OC.white, size: 54),
    ]),
  );
}

class _PulsingDots extends StatefulWidget {
  const _PulsingDots();
  @override State<_PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<_PulsingDots> with TickerProviderStateMixin {
  late List<AnimationController> _ctrls;
  late List<Animation<double>> _anims;
  @override void initState() {
    super.initState();
    _ctrls = List.generate(3, (_) => AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true));
    _anims = List.generate(3, (i) => Tween<double>(begin: 0.3, end: 1.0).animate(_ctrls[i]));
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 150), () { if (mounted) _ctrls[i].forward(); });
    }
  }
  @override void dispose() { for (final c in _ctrls) c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(3, (i) => AnimatedBuilder(
      animation: _anims[i],
      builder: (_, __) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 6, height: 6,
        decoration: BoxDecoration(
          color: OC.cyan.withOpacity(_anims[i].value), shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: OC.cyan.withOpacity(_anims[i].value * 0.5), blurRadius: 8)],
        ),
      ),
    )),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  ONBOARDING SCREEN
// ═══════════════════════════════════════════════════════════════════

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});
  @override State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with TickerProviderStateMixin {
  final _pageCtrl = PageController();
  int _page = 0;
  late AnimationController _contentCtrl;

  static const _pages = [
    _OBData(
      icon: Icons.dashboard_rounded,
      gradient: [Color(0xFF1E3A8A), Color(0xFF2563EB), Color(0xFF3B82F6)],
      glowColor: Color(0xFF2563EB),
      title: 'Manage Your\nSchool Smartly',
      subtitle: 'Everything your school needs in one powerful, beautiful platform — built for admins and teachers.',
      badge: 'ADMIN & TEACHER ROLES',
      features: ['👨‍🏫  Teacher management & login', '🏫  Class organization', '📊  Real-time dashboard'],
      accentColor: Color(0xFF06B6D4),
    ),
    _OBData(
      icon: Icons.fact_check_rounded,
      gradient: [Color(0xFF312E81), Color(0xFF4F46E5), Color(0xFF7C3AED)],
      glowColor: Color(0xFF7C3AED),
      title: 'Track Attendance\nEffortlessly',
      subtitle: 'Mark attendance in seconds. View full history anytime, and get instant present/absent stats.',
      badge: 'DAILY TRACKING',
      features: ['✅  One-tap attendance marking', '📅  Complete date history', '📈  Present vs absent stats'],
      accentColor: Color(0xFF818CF8),
    ),
    _OBData(
      icon: Icons.account_balance_wallet_rounded,
      gradient: [Color(0xFF064E3B), Color(0xFF059669), Color(0xFF10B981)],
      glowColor: Color(0xFF10B981),
      title: 'Fee Collection\nMade Simple',
      subtitle: 'Monitor monthly payments, mark fees paid or unpaid, and stay on top of school finances.',
      badge: 'FEE MANAGEMENT',
      features: ['💳  Track paid & unpaid fees', '🔍  Filter, search & export', '⚡  Bulk mark actions'],
      accentColor: Color(0xFF34D399),
    ),
    _OBData(
      icon: Icons.people_rounded,
      gradient: [Color(0xFF78350F), Color(0xFFD97706), Color(0xFFF59E0B)],
      glowColor: Color(0xFFF59E0B),
      title: 'Student Profiles\nAt Your Fingertips',
      subtitle: 'Full student records with parent contacts, roll numbers, class info and real-time cloud sync.',
      badge: 'STUDENT MANAGEMENT',
      features: ['👤  Complete student profiles', '📱  Parent contact details', '🔄  Real-time Firebase sync'],
      accentColor: Color(0xFFFBBF24),
    ),
  ];

  @override void initState() {
    super.initState();
    _contentCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..forward();
  }

  @override void dispose() { _contentCtrl.dispose(); _pageCtrl.dispose(); super.dispose(); }

  void _next() {
    if (_page < _pages.length - 1) {
      _contentCtrl.reverse().then((_) {
        _pageCtrl.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.easeInOutCubic);
        setState(() => _page++);
        _contentCtrl.forward();
      });
    } else {
      widget.onDone();
    }
  }

  @override Widget build(BuildContext context) {
    final data = _pages[_page];
    return Scaffold(
      backgroundColor: OC.navy,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [data.gradient[0], data.gradient[1], OC.navy],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(child: Stack(children: [
          // Grid overlay
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          // Corner glow
          Positioned(top: -80, right: -80, child: Container(
            width: 250, height: 250,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [data.glowColor.withOpacity(0.25), Colors.transparent]),
            ),
          )),
          Column(children: [
            // Top bar
            Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), child: Row(children: [
              // Page indicator text
              Text('${_page + 1} / ${_pages.length}', style: TextStyle(
                color: OC.white.withOpacity(0.4), fontFamily: 'Nunito',
                fontWeight: FontWeight.w700, fontSize: 13,
              )),
              const Spacer(),
              if (_page < _pages.length - 1)
                GestureDetector(
                  onTap: widget.onDone,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: OC.white10, borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: OC.white20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('Skip', style: TextStyle(color: OC.white.withOpacity(0.7),
                          fontWeight: FontWeight.w700, fontSize: 13, fontFamily: 'Nunito')),
                      const SizedBox(width: 4),
                      Icon(Icons.keyboard_double_arrow_right_rounded,
                          color: OC.white.withOpacity(0.5), size: 16),
                    ]),
                  ),
                ),
            ])),

            // Hero area
            Expanded(flex: 4, child: PageView.builder(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _pages.length,
              itemBuilder: (_, i) => _HeroWidget(data: _pages[i]),
            )),

            // Content card
            Expanded(flex: 6, child: _OBCard(
              data: data, page: _page, total: _pages.length,
              onNext: _next, ctrl: _contentCtrl,
            )),
          ]),
        ])),
      ),
    );
  }
}

class _OBData {
  final IconData icon;
  final List<Color> gradient;
  final Color glowColor, accentColor;
  final String title, subtitle, badge;
  final List<String> features;
  const _OBData({required this.icon, required this.gradient, required this.glowColor,
    required this.title, required this.subtitle, required this.badge,
    required this.features, required this.accentColor});
}

class _GridPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withOpacity(0.03)..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 40) canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    for (double y = 0; y < size.height; y += 40) canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
  }
  @override bool shouldRepaint(_) => false;
}

class _HeroWidget extends StatefulWidget {
  final _OBData data;
  const _HeroWidget({super.key, required this.data});
  @override State<_HeroWidget> createState() => _HeroWidgetState();
}

class _HeroWidgetState extends State<_HeroWidget> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _float;
  @override void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500))..repeat(reverse: true);
    _float = Tween<double>(begin: -8, end: 8).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(
    animation: _float,
    builder: (_, __) => Center(child: Transform.translate(
      offset: Offset(0, _float.value),
      child: SizedBox(width: 240, height: 200, child: Stack(alignment: Alignment.center, children: [
        Container(width: 200, height: 200, decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [widget.data.glowColor.withOpacity(0.2), Colors.transparent]),
        )),
        Container(width: 140, height: 140, decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [widget.data.glowColor.withOpacity(0.15), Colors.transparent]),
        )),
        // Main icon
        Container(
          width: 120, height: 120,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: widget.data.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(36),
            boxShadow: [
              BoxShadow(color: widget.data.glowColor.withOpacity(0.5), blurRadius: 30, spreadRadius: 5),
              BoxShadow(color: widget.data.glowColor.withOpacity(0.2), blurRadius: 60, spreadRadius: 15),
            ],
          ),
          child: Stack(alignment: Alignment.center, children: [
            Positioned(top: 0, left: 0, right: 0, height: 60,
              child: Container(decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
                gradient: LinearGradient(
                  colors: [OC.white.withOpacity(0.25), Colors.transparent],
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                ),
              )),
            ),
            Icon(widget.data.icon, color: OC.white, size: 58),
          ]),
        ),
        // Floating badges
        Positioned(top: 0, right: 0, child: _Badge(Icons.star_rounded, widget.data.accentColor)),
        Positioned(bottom: 10, left: 0, child: _Badge(Icons.check_circle_rounded, const Color(0xFF10B981))),
        Positioned(top: 20, left: 0, child: _Badge(Icons.notifications_rounded, widget.data.glowColor, small: true)),
      ])),
    )),
  );
}

class _Badge extends StatelessWidget {
  final IconData icon; final Color color; final bool small;
  const _Badge(this.icon, this.color, {this.small = false});
  @override Widget build(BuildContext context) {
    final s = small ? 32.0 : 40.0;
    return Container(
      width: s, height: s,
      decoration: BoxDecoration(
        color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(small ? 10 : 12),
        border: Border.all(color: color.withOpacity(0.4)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 10)],
      ),
      child: Icon(icon, color: color, size: small ? 16 : 20),
    );
  }
}

class _OBCard extends StatelessWidget {
  final _OBData data;
  final int page, total;
  final VoidCallback onNext;
  final AnimationController ctrl;
  const _OBCard({required this.data, required this.page, required this.total, required this.onNext, required this.ctrl});

  @override Widget build(BuildContext context) => FadeTransition(
    opacity: ctrl,
    child: SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
          .animate(CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic)),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          color: OC.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: OC.white.withOpacity(0.1)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(26),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Badge chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: data.accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: data.accentColor.withOpacity(0.3)),
                ),
                child: Text(data.badge, style: TextStyle(color: data.accentColor,
                    fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5, fontFamily: 'Nunito')),
              ),
              const SizedBox(height: 14),
              // Title
              Text(data.title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900,
                  color: OC.white, letterSpacing: -0.8, height: 1.2, fontFamily: 'Nunito')),
              const SizedBox(height: 10),
              // Subtitle
              Text(data.subtitle, style: TextStyle(fontSize: 13, color: OC.white.withOpacity(0.6),
                  height: 1.6, fontFamily: 'Nunito')),
              const SizedBox(height: 16),
              // Features
              ...data.features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Container(width: 4, height: 4, margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(color: data.accentColor, shape: BoxShape.circle)),
                  Text(f, style: TextStyle(color: OC.white.withOpacity(0.75),
                      fontSize: 13, fontFamily: 'Nunito', fontWeight: FontWeight.w600)),
                ]),
              )),
              const SizedBox(height: 22),
              // Dots + next button
              Row(children: [
                Row(children: List.generate(total, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.only(right: 6),
                  width: i == page ? 24 : 8, height: 8,
                  decoration: BoxDecoration(
                    color: i == page ? data.accentColor : OC.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: i == page ? [BoxShadow(color: data.accentColor.withOpacity(0.5), blurRadius: 8)] : [],
                  ),
                ))),
                const Spacer(),
                GestureDetector(
                  onTap: onNext,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: EdgeInsets.symmetric(horizontal: page == total - 1 ? 22 : 18, vertical: 13),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [data.gradient[0], data.gradient[1]]),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: data.glowColor.withOpacity(0.5), blurRadius: 16, offset: const Offset(0, 4))],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(page == total - 1 ? 'Get Started' : 'Next',
                          style: const TextStyle(color: OC.white, fontWeight: FontWeight.w800,
                              fontSize: 15, fontFamily: 'Nunito')),
                      const SizedBox(width: 6),
                      Icon(page == total - 1 ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
                          color: OC.white, size: 18),
                    ]),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
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
          const Text('EduTrack', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: T.ink, letterSpacing: -1.5)),
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
    Navigator.pushAndRemoveUntil(context,
        fadeRoute(meta['role'] == 'admin' ? const AdminRoot() : const TeacherDashboard()),
            (_) => false);
  }

  void _err(String m) => ScaffoldMessenger.of(context).showSnackBar(buildSnack(m, isError: true));

  @override Widget build(BuildContext context) => Scaffold(
    appBar: buildAppBar('Login'),
    body: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 4),
      const Text('Welcome back!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: T.ink, letterSpacing: -.5)),
      const SizedBox(height: 4),
      const Text('Sign in to your school account', style: TextStyle(color: T.inkLight, fontSize: 15)),
      const SizedBox(height: 32),
      SurfaceCard(child: Column(children: [
        LabeledField(ctrl: _email, label: 'Email Address', icon: Icons.email_outlined, type: TextInputType.emailAddress),
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

  void _err(String m) => ScaffoldMessenger.of(context).showSnackBar(buildSnack(m, isError: true));

  @override Widget build(BuildContext context) => Scaffold(
    appBar: buildAppBar('Register School'),
    body: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Create Your School', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: T.ink, letterSpacing: -.5)),
      const SizedBox(height: 4),
      const Text('Set up your school account in seconds', style: TextStyle(color: T.inkLight, fontSize: 15)),
      const SizedBox(height: 32),
      SurfaceCard(child: Column(children: [
        const SectionHeader('School Information'),
        LabeledField(ctrl: _name,  label: 'School Name', icon: Icons.school_outlined),
        const SizedBox(height: 12),
        LabeledField(ctrl: _admin, label: 'Admin Name',  icon: Icons.person_outline_rounded),
        const SizedBox(height: 20),
        const SectionHeader('Login Credentials'),
        LabeledField(ctrl: _email, label: 'Email Address', icon: Icons.email_outlined, type: TextInputType.emailAddress),
        const SizedBox(height: 12),
        LabeledField(ctrl: _pass, label: 'Password', icon: Icons.lock_outline_rounded, obscure: true),
        const SizedBox(height: 24),
        PrimaryButton(label: 'Create School 🚀', onTap: _loading ? null : _register, loading: _loading),
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
      builder: (_) => _DeleteDialog(title: title, name: name, description: description, onConfirm: onConfirm));
}

class _DeleteDialog extends StatefulWidget {
  final String title, name, description;
  final Future<void> Function() onConfirm;
  const _DeleteDialog({required this.title, required this.name, required this.description, required this.onConfirm});
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
      Container(width: 64, height: 64, decoration: const BoxDecoration(color: T.redLight, shape: BoxShape.circle),
          child: const Icon(Icons.delete_outline_rounded, color: T.red, size: 30)),
      const SizedBox(height: 18),
      Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: T.ink)),
      const SizedBox(height: 8),
      Text(widget.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.inkMid), textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: T.redLight, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: T.amber, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.description, style: const TextStyle(fontSize: 13, color: T.inkMid, height: 1.4))),
          ])),
      const SizedBox(height: 22),
      Row(children: [
        Expanded(child: OutlineButton(label: 'Cancel', onTap: () => Navigator.pop(context))),
        const SizedBox(width: 12),
        Expanded(child: DangerButton(label: 'Delete', loading: _loading, onTap: _loading ? null : _confirm)),
      ]),
    ])),
  );
}

void showLogoutDialog(BuildContext context) {
  showDialog(
    context: context, barrierColor: Colors.black.withOpacity(.5),
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 64, height: 64, decoration: const BoxDecoration(color: T.blueLight, shape: BoxShape.circle),
            child: const Icon(Icons.logout_rounded, color: T.blue, size: 28)),
        const SizedBox(height: 18),
        const Text('Logout', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: T.ink)),
        const SizedBox(height: 8),
        const Text('Are you sure you want to log out?', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: T.inkLight)),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: OutlineButton(label: 'Cancel', onTap: () => Navigator.pop(context))),
          const SizedBox(width: 12),
          Expanded(child: PrimaryButton(label: 'Logout',
              onTap: () { Navigator.pop(context); performLogout(context); })),
        ]),
      ])),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  SHARED REUSABLE WIDGETS
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
    required this.icon, this.type = TextInputType.text, this.obscure = false, this.readOnly = false});
  @override Widget build(BuildContext context) => TextField(
    controller: ctrl, keyboardType: type, obscureText: obscure, readOnly: readOnly,
    style: const TextStyle(fontFamily: 'Nunito', fontSize: 15, color: T.ink),
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, color: T.inkFaint, size: 20)),
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
  const PrimaryButton({super.key, required this.label, this.icon, this.onTap, this.loading = false, this.color});
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

class OutlineButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  const OutlineButton({super.key, required this.label, this.icon, this.onTap});
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

class DangerButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  const DangerButton({super.key, required this.label, this.onTap, this.loading = false});
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

class CircleInitial extends StatelessWidget {
  final String name; final Color fg, bg; final double radius;
  const CircleInitial(this.name, this.fg, this.bg, {super.key, required this.radius});
  @override Widget build(BuildContext context) => CircleAvatar(
    radius: radius, backgroundColor: bg,
    child: Text(name[0].toUpperCase(), style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: radius * .85)),
  );
}

class InitialBubble extends StatelessWidget {
  final String name;
  const InitialBubble(this.name, {super.key});
  @override Widget build(BuildContext context) => Container(
    width: 46, height: 46,
    decoration: BoxDecoration(color: T.blueLight, shape: BoxShape.circle, border: Border.all(color: T.blue.withOpacity(.2), width: 2)),
    child: Center(child: Text(name[0].toUpperCase(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: T.blue))),
  );
}

class StatusChip extends StatelessWidget {
  final String label; final Color fg, bg;
  const StatusChip(this.label, this.fg, this.bg, {super.key});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800)),
  );
}

class InfoRow extends StatelessWidget {
  final IconData icon; final String label;
  const InfoRow(this.icon, this.label, {super.key});
  @override Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 12, color: T.inkFaint), const SizedBox(width: 5),
    Flexible(child: Text(label, style: const TextStyle(color: T.inkLight, fontSize: 13), overflow: TextOverflow.ellipsis)),
  ]);
}

class StatTile extends StatelessWidget {
  final String label, value; final IconData icon; final Color color;
  const StatTile({super.key, required this.label, required this.value, required this.icon, required this.color});
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
      Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color, letterSpacing: -1.0), maxLines: 1),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 12, color: T.inkLight, fontWeight: FontWeight.w600), maxLines: 1),
    ]),
  );
}

class ActionRow extends StatelessWidget {
  final IconData icon; final String label, sub; final Color color; final VoidCallback onTap;
  const ActionRow({super.key, required this.icon, required this.label, required this.sub, required this.color, required this.onTap});
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
        label: Text(leftLabel, style: TextStyle(color: leftColor, fontWeight: FontWeight.w700, fontSize: 13)),
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 11)))),
    VerticalDivider(width: 1, color: T.dividerFaint),
    Expanded(child: TextButton.icon(onPressed: onRight,
        icon: Icon(rightIcon, size: 15, color: rightColor),
        label: Text(rightLabel, style: TextStyle(color: rightColor, fontWeight: FontWeight.w700, fontSize: 13)),
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 11)))),
  ]));
}

class AttBadge extends StatelessWidget {
  final String label; final Color color, bg;
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
  final String label; final bool selected; final VoidCallback onTap; final Color color;
  const FilterPill(this.label, this.selected, this.onTap, this.color, {super.key});
  @override Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200), margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20), border: Border.all(color: selected ? color : T.divider),
          boxShadow: selected ? [BoxShadow(color: color.withOpacity(.2), blurRadius: 8, offset: const Offset(0, 2))] : []),
      child: Text(label, style: TextStyle(color: selected ? Colors.white : T.inkLight, fontWeight: FontWeight.w700, fontSize: 13)),
    ),
  );
}

class SearchField extends StatelessWidget {
  final String hint; final ValueChanged<String> onChanged;
  const SearchField({super.key, required this.hint, required this.onChanged});
  @override Widget build(BuildContext context) => TextField(
    onChanged: onChanged,
    style: const TextStyle(fontFamily: 'Nunito', fontSize: 14),
    decoration: InputDecoration(hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded, color: T.inkFaint, size: 20),
        isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: T.divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: T.divider)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: T.blue, width: 2)),
        filled: true, fillColor: T.bg),
  );
}

class ClassDropdown extends StatelessWidget {
  final List<SchoolClass> classes; final String? value; final ValueChanged<String?> onChanged;
  const ClassDropdown({super.key, required this.classes, this.value, required this.onChanged});
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
      onChanged: onChanged,
      icon: const Icon(Icons.expand_more_rounded, size: 18, color: T.inkLight), isDense: true,
    )),
  );
}

class DatePickerField extends StatelessWidget {
  final String date; final ValueChanged<String> onChanged;
  const DatePickerField({super.key, required this.date, required this.onChanged});
  @override Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final p = await showDatePicker(context: context, initialDate: DateTime.now(),
          firstDate: DateTime(2020), lastDate: DateTime.now(),
          builder: (ctx, child) => Theme(
              data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: T.blue, onPrimary: Colors.white)),
              child: child!));
      if (p != null) onChanged(DateFormat('yyyy-MM-dd').format(p));
    },
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: T.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: T.divider)),
      child: Row(children: [
        const Icon(Icons.calendar_today_rounded, color: T.inkFaint, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(date, style: const TextStyle(fontFamily: 'Nunito', color: T.ink, fontWeight: FontWeight.w600))),
        const Icon(Icons.expand_more_rounded, color: T.inkFaint, size: 18),
      ]),
    ),
  );
}

class IconActionButton extends StatelessWidget {
  final IconData icon; final VoidCallback? onTap; final Color? color; final double? size;
  const IconActionButton(this.icon, this.onTap, {super.key, this.color, this.size});
  @override Widget build(BuildContext context) => Material(color: T.bg, borderRadius: BorderRadius.circular(10),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10),
          child: Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: T.divider)),
              child: Icon(icon, color: color ?? T.inkMid, size: size ?? 20))));
}

class EmptyState extends StatelessWidget {
  final IconData icon; final String title, sub;
  const EmptyState(this.icon, this.title, this.sub, {super.key});
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

class LogoutButton extends StatelessWidget {
  final VoidCallback onTap;
  const LogoutButton({super.key, required this.onTap});
  @override Widget build(BuildContext context) => Material(color: T.redLight, borderRadius: BorderRadius.circular(16),
    child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap,
      child: Container(padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: T.red.withOpacity(.2))),
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
  final double collected, total, pct; final int paid, unpaid;
  const FeeHeroBanner({super.key, required this.collected, required this.total,
    required this.paid, required this.unpaid, required this.pct});
  @override Widget build(BuildContext context) {
    final c = pct >= .8 ? [const Color(0xFF047857), T.green] : pct >= .5 ? [T.blue, T.blueMid] : [T.red, T.redMid];
    return Container(
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: c, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: c[0].withOpacity(.3), blurRadius: 20, offset: const Offset(0, 8))]),
      padding: const EdgeInsets.all(18),
      child: Column(children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Rs ${fmtNum(collected)} collected', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
            Text('of Rs ${fmtNum(total)} total', style: TextStyle(color: Colors.white.withOpacity(.7), fontSize: 12)),
          ])),
          RingProgress(pct),
        ]),
        const SizedBox(height: 14),
        ClipRRect(borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: pct, minHeight: 6,
                backgroundColor: Colors.white.withOpacity(.2), color: Colors.white)),
        const SizedBox(height: 10),
        Row(children: [
          Text('$paid Paid', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(width: 4),
          Text('·', style: TextStyle(color: Colors.white.withOpacity(.4))),
          const SizedBox(width: 4),
          Text('$unpaid Unpaid', style: TextStyle(color: Colors.white.withOpacity(.7), fontWeight: FontWeight.w600, fontSize: 13)),
          const Spacer(),
          Text('Rs ${fmtNum(total - collected)} pending', style: TextStyle(color: Colors.white.withOpacity(.65), fontSize: 12)),
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
      Text('${(pct * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
    ]),
  );
}

class SegmentedTabs extends StatelessWidget {
  final List<String> labels; final List<int> counts; final List<Color> colors;
  final int selected; final ValueChanged<int> onTap;
  const SegmentedTabs({super.key, required this.labels, required this.counts,
    required this.colors, required this.selected, required this.onTap});
  @override Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: T.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: T.divider)),
    padding: const EdgeInsets.all(4),
    child: Row(children: List.generate(labels.length, (i) => Expanded(child: GestureDetector(
      onTap: () => onTap(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected == i ? colors[i] : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
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

class FeeCard extends StatelessWidget {
  final Student student; final VoidCallback onToggle;
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
                child: Text(student.name[0].toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, color: ac, fontSize: 20))),
            Positioned(bottom: -1, right: -1, child: Container(width: 13, height: 13,
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
                child: Text('Rs ${fmtNum(student.monthlyFee)}', style: TextStyle(color: ac, fontWeight: FontWeight.w900, fontSize: 14))),
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
            const Expanded(child: Text('Bulk Actions', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.ink))),
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
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _SheetAction({required this.icon, required this.label, required this.color, required this.onTap});
  @override Widget build(BuildContext context) => InkWell(onTap: onTap,
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
        ])),
  );
}

class CredRow extends StatefulWidget {
  final String label, value; final bool isPassword;
  const CredRow({super.key, required this.label, required this.value, this.isPassword = false});
  @override State<CredRow> createState() => _CredRowState();
}

class _CredRowState extends State<CredRow> {
  bool _obscure = true;
  @override Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SizedBox(width: 72, child: Text(widget.label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: T.inkFaint, letterSpacing: .4))),
    Expanded(child: Text(widget.isPassword && _obscure ? '•' * widget.value.length : widget.value,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: T.ink))),
    GestureDetector(
      onTap: () { Clipboard.setData(ClipboardData(text: widget.value)); ScaffoldMessenger.of(context).showSnackBar(buildSnack('${widget.label} copied!')); },
      child: const Icon(Icons.copy_rounded, size: 16, color: T.inkFaint),
    ),
    if (widget.isPassword) ...[
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () => setState(() => _obscure = !_obscure),
        child: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 16, color: T.inkFaint),
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
  bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: T.divider)),
);

SnackBar buildSnack(String msg, {bool isError = false}) => SnackBar(
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