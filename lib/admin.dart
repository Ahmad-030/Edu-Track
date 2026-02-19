import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'main.dart';

// ═══════════════════════════════════════════════════════════════════
//  ADMIN ROOT  (bottom nav shell)
// ═══════════════════════════════════════════════════════════════════

class AdminRoot extends StatefulWidget {
  const AdminRoot({super.key});
  @override State<AdminRoot> createState() => _AdminRootState();
}

class _AdminRootState extends State<AdminRoot> {
  int _tab = 0;
  static const _tabs = [
    AdminDashboard(),
    TeachersScreen(),
    ClassesScreen(),
    StudentsScreen(),
    AdminMoreScreen(),
  ];

  @override Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _tab, children: _tabs),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (i) => setState(() => _tab = i),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
        NavigationDestination(icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded), label: 'Teachers'),
        NavigationDestination(icon: Icon(Icons.class_outlined),
            selectedIcon: Icon(Icons.class_rounded), label: 'Classes'),
        NavigationDestination(icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school_rounded), label: 'Students'),
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
                      return _buildBody(context, school, teachers, classes, students);
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

  Widget _buildBody(BuildContext ctx, School? school, List<Teacher> teachers,
      List<SchoolClass> classes, List<Student> students) {
    final paid      = students.where((s) => s.feePaid).length;
    final unpaid    = students.length - paid;
    final collected = students.where((s) => s.feePaid).fold(0.0, (a, s) => a + s.monthlyFee);
    final total     = students.fold(0.0, (a, s) => a + s.monthlyFee);
    final pct       = students.isEmpty ? 0.0 : (paid / students.length).clamp(0.0, 1.0);

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Hello, ${school?.adminName ?? 'Admin'}! 👋',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                        color: T.ink, letterSpacing: -.3)),
                const SizedBox(height: 3),
                Row(children: [
                  Container(width: 6, height: 6,
                      decoration: const BoxDecoration(color: T.green, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(school?.name ?? '', style: const TextStyle(color: T.inkLight,
                      fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ])),
              InitialBubble(school?.adminName ?? 'A'),
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
                      decoration: BoxDecoration(color: Colors.white.withOpacity(.15),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.account_balance_wallet_rounded,
                          color: Colors.white, size: 16)),
                  const SizedBox(width: 10),
                  Text('Monthly Fee Overview', style: TextStyle(color: Colors.white.withOpacity(.85),
                      fontSize: 13, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(.15),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(DateFormat('MMM yyyy').format(DateTime.now()),
                          style: const TextStyle(color: Colors.white, fontSize: 11,
                              fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 18),
                Text('Rs ${fmtNum(collected)}', style: const TextStyle(fontSize: 36,
                    fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.5)),
                Text('collected of Rs ${fmtNum(total)}',
                    style: TextStyle(color: Colors.white.withOpacity(.65), fontSize: 13)),
                const SizedBox(height: 18),
                Stack(children: [
                  Container(height: 6, decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.2), borderRadius: BorderRadius.circular(3))),
                  FractionallySizedBox(widthFactor: pct,
                      child: Container(height: 6,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3),
                            boxShadow: [BoxShadow(color: Colors.white.withOpacity(.5), blurRadius: 8)]),
                      )),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Text('$paid Paid', style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(width: 4),
                  Text('·', style: TextStyle(color: Colors.white.withOpacity(.4))),
                  const SizedBox(width: 4),
                  Text('$unpaid Unpaid', style: TextStyle(color: Colors.white.withOpacity(.65),
                      fontWeight: FontWeight.w600, fontSize: 13)),
                  const Spacer(),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(.2),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('${(pct * 100).round()}%', style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
                ]),
              ]),
            ),
            const SizedBox(height: 24),
          ]))),
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(children: [
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: StatTile(label: 'Teachers', value: '${teachers.length}',
                icon: Icons.people_rounded, color: T.blue)),
            const SizedBox(width: 12),
            Expanded(child: StatTile(label: 'Students', value: '${students.length}',
                icon: Icons.school_rounded, color: T.purple)),
          ])),
          const SizedBox(height: 12),
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: StatTile(label: 'Classes', value: '${classes.length}',
                icon: Icons.class_rounded, color: T.teal)),
            const SizedBox(width: 12),
            Expanded(child: StatTile(label: 'Unpaid', value: '$unpaid',
                icon: Icons.pending_rounded, color: unpaid > 0 ? T.red : T.green)),
          ])),
        ]),
      )),
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
          child: const Text('Quick Actions', style: TextStyle(fontSize: 16,
              fontWeight: FontWeight.w800, color: T.ink)))),
      SliverPadding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          sliver: SliverList(delegate: SliverChildListDelegate([
            ActionRow(icon: Icons.person_add_rounded, label: 'Add Teacher',
                sub: 'Manage teaching staff', color: T.blue,
                onTap: () => Navigator.push(ctx, slideRoute(const AddTeacherScreen()))),
            ActionRow(icon: Icons.add_box_rounded, label: 'Add Class',
                sub: 'Create a new grade or section', color: T.purple,
                onTap: () => Navigator.push(ctx, slideRoute(const AddClassScreen()))),
            ActionRow(icon: Icons.person_add_alt_1_rounded, label: 'Add Student',
                sub: 'Enroll a new student', color: T.teal,
                onTap: () => Navigator.push(ctx, slideRoute(const AddStudentScreen()))),
            ActionRow(icon: Icons.calendar_today_rounded, label: 'View Attendance',
                sub: 'Check class attendance records', color: T.amber,
                onTap: () => Navigator.push(ctx, slideRoute(const AdminAttendanceScreen()))),
            ActionRow(icon: Icons.account_balance_wallet_rounded, label: 'Fee Tracker',
                sub: 'Monitor & collect fees', color: T.green,
                onTap: () => Navigator.push(ctx, slideRoute(const FeeTrackerScreen()))),
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
      appBar: buildAppBar('Teachers'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, slideRoute(const AddTeacherScreen())),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Teacher', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FB.teachers(sid).orderBy('name').snapshots(),
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final teachers = snap.data!.docs.map(Teacher.fromDoc).toList();
          if (teachers.isEmpty) return const EmptyState(Icons.people_rounded,
              'No teachers yet', 'Tap the button below to add your first teacher');
          // Also stream students once to get counts per class
          return StreamBuilder<QuerySnapshot>(
            stream: FB.students(sid).snapshots(),
            builder: (_, studSnap) {
              final allStudents = studSnap.hasData
                  ? studSnap.data!.docs.map(Student.fromDoc).toList() : <Student>[];
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: teachers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final teacher = teachers[i];
                  final studentCount = teacher.classId == null
                      ? 0
                      : allStudents.where((s) => s.classId == teacher.classId).length;
                  return _TeacherCard(teacher: teacher, sid: sid, studentCount: studentCount);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _TeacherCard extends StatelessWidget {
  final Teacher teacher;
  final String sid;
  final int studentCount;
  const _TeacherCard({required this.teacher, required this.sid, required this.studentCount});

  @override Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: T.divider),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.03), blurRadius: 12, offset: const Offset(0, 4))]),
    child: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: Row(children: [
        CircleInitial(teacher.name, T.blue, T.blueLight, radius: 26),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(teacher.name, style: const TextStyle(fontWeight: FontWeight.w800,
              fontSize: 16, color: T.ink)),
          const SizedBox(height: 4),
          InfoRow(Icons.book_outlined, teacher.subject),
          const SizedBox(height: 2),
          InfoRow(Icons.phone_outlined, teacher.phone),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (teacher.classId != null) ...[
            StreamBuilder<DocumentSnapshot>(
              stream: FB.classes(sid).doc(teacher.classId!).snapshots(),
              builder: (_, s) {
                final name = s.hasData && s.data!.exists
                    ? (s.data!.data() as Map)['name'] as String : '...';
                return StatusChip(name, T.blue, T.blueLight);
              },
            ),
            const SizedBox(height: 6),
            // Student count badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: T.purpleLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.school_rounded, size: 12, color: T.purple),
                const SizedBox(width: 4),
                Text('$studentCount students',
                    style: const TextStyle(color: T.purple, fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ),
          ] else
            const StatusChip('No Class', T.inkFaint, T.dividerFaint),
        ]),
      ])),
      Container(height: 1, color: T.dividerFaint),
      CardActions(
        leftIcon: Icons.edit_rounded, leftLabel: 'Edit', leftColor: T.blue,
        rightIcon: Icons.delete_rounded, rightLabel: 'Delete', rightColor: T.red,
        onLeft:  () => Navigator.push(context, slideRoute(AddTeacherScreen(teacher: teacher))),
        onRight: () => showDeleteDialog(context, title: 'Delete Teacher', name: teacher.name,
            description: 'This teacher will be removed and unassigned from their class.',
            onConfirm: () => _deleteTeacher()),
      ),
    ]),
  );

  Future<void> _deleteTeacher() async {
    final batch = FB.db.batch();
    if (teacher.classId != null) {
      batch.update(FB.classes(sid).doc(teacher.classId!), {'teacherId': FieldValue.delete()});
    }
    batch.delete(FB.teachers(sid).doc(teacher.id));
    await batch.commit();
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ADD / EDIT TEACHER
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
        final teacherUid = await FB.createTeacherAuthAccount(
            _email.text.trim(), _pass.text);

        final batch = FB.db.batch();
        batch.set(FB.teachers(sid).doc(teacherUid), {
          'name': _name.text.trim(), 'subject': _subject.text.trim(),
          'phone': _phone.text.trim(), 'email': _email.text.trim(), 'classId': _classId,
        });
        batch.set(FB.users.doc(teacherUid), {
          'role': 'teacher', 'schoolId': sid, 'teacherId': teacherUid,
        });
        if (_classId != null) {
          batch.update(FB.classes(sid).doc(_classId!), {'teacherId': teacherUid});
        }
        await batch.commit();

        if (mounted) await _showCredentials(_name.text.trim(), _email.text.trim(), _pass.text);
      } else {
        final batch = FB.db.batch();
        final old = widget.teacher!;
        if (old.classId != null && old.classId != _classId) {
          batch.update(FB.classes(sid).doc(old.classId!), {'teacherId': FieldValue.delete()});
        }
        if (_classId != null && _classId != old.classId) {
          batch.update(FB.classes(sid).doc(_classId!), {'teacherId': old.id});
        }
        batch.update(FB.teachers(sid).doc(old.id), {
          'name': _name.text.trim(), 'subject': _subject.text.trim(),
          'phone': _phone.text.trim(), 'classId': _classId,
        });
        await batch.commit();
        if (mounted) Navigator.pop(context);
      }
    } on Exception catch (e) {
      _err(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showCredentials(String name, String email, String password) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 64, height: 64,
                  decoration: const BoxDecoration(color: T.greenLight, shape: BoxShape.circle),
                  child: const Icon(Icons.check_circle_rounded, color: T.green, size: 34)),
              const SizedBox(height: 16),
              const Text('Teacher Account Created!',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: T.ink),
                  textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('Share these credentials with $name.',
                  style: const TextStyle(fontSize: 13, color: T.inkLight, height: 1.5),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              Container(width: double.infinity,
                  decoration: BoxDecoration(color: T.bg, borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: T.divider)),
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    CredRow(label: 'Name', value: name),
                    const Divider(height: 20, color: T.divider),
                    CredRow(label: 'Email', value: email),
                    const Divider(height: 20, color: T.divider),
                    CredRow(label: 'Password', value: password, isPassword: true),
                  ])),
              const SizedBox(height: 12),
              Container(padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: T.amberLight, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: T.amber.withOpacity(.3))),
                  child: const Row(children: [
                    Icon(Icons.warning_amber_rounded, color: T.amber, size: 16),
                    SizedBox(width: 8),
                    Expanded(child: Text('Ask the teacher to change their password after first login.',
                        style: TextStyle(fontSize: 12, color: T.inkMid, height: 1.4))),
                  ])),
              const SizedBox(height: 20),
              PrimaryButton(label: 'Done', icon: Icons.check_rounded,
                  onTap: () => Navigator.pop(context)),
            ])),
        ),
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  void _err(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(buildSnack(m, isError: true));

  @override Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FB.classes(currentSession!.schoolId).snapshots(),
      builder: (_, snap) {
        final classes = snap.hasData
            ? snap.data!.docs.map(SchoolClass.fromDoc).toList() : <SchoolClass>[];
        return Scaffold(
          appBar: buildAppBar(widget.teacher == null ? 'Add Teacher' : 'Edit Teacher'),
          body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
            if (widget.teacher == null)
              Container(margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: T.blueLight, borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: T.blue.withOpacity(.2))),
                  child: const Row(children: [
                    Icon(Icons.info_outline_rounded, color: T.blue, size: 18),
                    SizedBox(width: 10),
                    Expanded(child: Text(
                      'A login account will be created. You will stay logged in as admin.',
                      style: TextStyle(color: T.blue, fontSize: 13, fontWeight: FontWeight.w600),
                    )),
                  ])),
            SurfaceCard(child: Column(children: [
              const SectionHeader('Personal Information'),
              LabeledField(ctrl: _name,    label: 'Full Name',    icon: Icons.person_outline_rounded),
              const SizedBox(height: 12),
              LabeledField(ctrl: _subject, label: 'Subject',      icon: Icons.book_outlined),
              const SizedBox(height: 12),
              LabeledField(ctrl: _phone,   label: 'Phone Number', icon: Icons.phone_outlined,
                  type: TextInputType.phone),
            ])),
            const SizedBox(height: 14),
            SurfaceCard(child: Column(children: [
              const SectionHeader('Login Credentials'),
              LabeledField(ctrl: _email, label: 'Email Address', icon: Icons.email_outlined,
                  type: TextInputType.emailAddress, readOnly: widget.teacher != null),
              if (widget.teacher == null) ...[
                const SizedBox(height: 12),
                LabeledField(ctrl: _pass, label: 'Password',
                    icon: Icons.lock_outline_rounded, obscure: true),
              ],
            ])),
            const SizedBox(height: 14),
            SurfaceCard(child: Column(children: [
              const SectionHeader('Class Assignment'),
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
            PrimaryButton(
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
      appBar: buildAppBar('Classes'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, slideRoute(const AddClassScreen())),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Class', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FB.classes(sid).orderBy('name').snapshots(),
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final classes = snap.data!.docs.map(SchoolClass.fromDoc).toList();
          if (classes.isEmpty) return const EmptyState(Icons.class_rounded,
              'No classes yet', 'Create your first class to get started');
          return StreamBuilder<QuerySnapshot>(
            stream: FB.students(sid).snapshots(),
            builder: (_, studSnap) {
              final allStudents = studSnap.hasData
                  ? studSnap.data!.docs.map(Student.fromDoc).toList() : <Student>[];
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
  final SchoolClass cls;
  final String sid;
  final int studentCount;
  const _ClassCard({required this.cls, required this.sid, required this.studentCount});

  @override Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: T.divider),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.03), blurRadius: 12, offset: const Offset(0, 4))]),
    child: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: Row(children: [
        Container(width: 50, height: 50,
            decoration: BoxDecoration(gradient: const LinearGradient(
                colors: [T.teal, T.tealMid], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.class_rounded, color: Colors.white, size: 24)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(cls.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: T.ink)),
          const SizedBox(height: 4),
          if (cls.teacherId != null)
            StreamBuilder<DocumentSnapshot>(
              stream: FB.teachers(sid).doc(cls.teacherId!).snapshots(),
              builder: (_, s) {
                final name = s.hasData && s.data!.exists
                    ? (s.data!.data() as Map)['name'] as String : '...';
                return InfoRow(Icons.person_outline_rounded, name);
              },
            )
          else
            const InfoRow(Icons.person_outline_rounded, 'No teacher assigned'),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$studentCount', style: const TextStyle(fontSize: 26,
              fontWeight: FontWeight.w900, color: T.teal, letterSpacing: -1)),
          const Text('students', style: TextStyle(fontSize: 11, color: T.inkLight,
              fontWeight: FontWeight.w600)),
        ]),
      ])),
      Container(height: 1, color: T.dividerFaint),
      CardActions(
        leftIcon: Icons.edit_rounded, leftLabel: 'Edit', leftColor: T.blue,
        rightIcon: Icons.delete_rounded, rightLabel: 'Delete', rightColor: T.red,
        onLeft:  () => Navigator.push(context, slideRoute(AddClassScreen(cls: cls))),
        onRight: () => showDeleteDialog(context, title: 'Delete Class', name: cls.name,
            description: 'All student assignments to this class will be affected.',
            onConfirm: () => _deleteClass()),
      ),
    ]),
  );

  Future<void> _deleteClass() async {
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
  String? _tid;
  bool _loading = false;

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
    } catch (_) {
      _err('Error saving class');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _err(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(buildSnack(m, isError: true));

  @override Widget build(BuildContext context) => Scaffold(
    appBar: buildAppBar(widget.cls == null ? 'Add Class' : 'Edit Class'),
    body: StreamBuilder<QuerySnapshot>(
      stream: FB.teachers(currentSession!.schoolId).orderBy('name').snapshots(),
      builder: (_, snap) {
        final teachers = snap.hasData
            ? snap.data!.docs.map(Teacher.fromDoc).toList() : <Teacher>[];
        return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
          SurfaceCard(child: Column(children: [
            const SectionHeader('Class Details'),
            LabeledField(ctrl: _name, label: 'Class Name (e.g. Grade 1 - A)',
                icon: Icons.class_outlined),
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
          PrimaryButton(
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
      appBar: buildAppBar('Students'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, slideRoute(const AddStudentScreen())),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Student', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FB.classes(sid).orderBy('name').snapshots(),
        builder: (_, clsSnap) {
          final classes = clsSnap.hasData
              ? clsSnap.data!.docs.map(SchoolClass.fromDoc).toList() : <SchoolClass>[];
          return StreamBuilder<QuerySnapshot>(
            stream: _filter == null
                ? FB.students(sid).orderBy('name').snapshots()
                : FB.students(sid).where('classId', isEqualTo: _filter).orderBy('name').snapshots(),
            builder: (_, studSnap) {
              final students = studSnap.hasData
                  ? studSnap.data!.docs.map(Student.fromDoc).toList() : <Student>[];
              return Column(children: [
                Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                    FilterPill('All', _filter == null, () => setState(() => _filter = null), T.blue),
                    ...classes.map((c) => FilterPill(c.name, _filter == c.id,
                            () => setState(() => _filter = c.id), T.purple)),
                  ])),
                ),
                Container(height: 1, color: T.divider),
                Expanded(child: students.isEmpty
                    ? const EmptyState(Icons.school_rounded, 'No students found',
                    'Add students or change the filter')
                    : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: students.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) =>
                      _StudentCard(student: students[i], sid: sid, classes: classes),
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
  final Student student;
  final String sid;
  final List<SchoolClass> classes;
  const _StudentCard({required this.student, required this.sid, required this.classes});

  String _className() => classes.where((c) => c.id == student.classId).firstOrNull?.name ?? '-';

  @override Widget build(BuildContext context) {
    final paid = student.feePaid;
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
          border: Border.all(color: T.divider),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.03), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          CircleInitial(student.name, T.purple, T.purpleLight, radius: 23),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(student.name, style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 15, color: T.ink))),
              StatusChip(paid ? 'Paid' : 'Unpaid', paid ? T.green : T.red,
                  paid ? T.greenLight : T.redLight),
            ]),
            const SizedBox(height: 4),
            InfoRow(Icons.tag_rounded, 'Roll #${student.rollNumber}  ·  ${_className()}'),
            const SizedBox(height: 2),
            InfoRow(Icons.phone_outlined,
                '${student.parentPhone}  ·  Rs ${fmtNum(student.monthlyFee)}/mo'),
          ])),
        ])),
        Container(height: 1, color: T.dividerFaint),
        CardActions(
          leftIcon: Icons.edit_rounded, leftLabel: 'Edit', leftColor: T.blue,
          rightIcon: Icons.delete_rounded, rightLabel: 'Delete', rightColor: T.red,
          onLeft:  () => Navigator.push(context, slideRoute(AddStudentScreen(student: student))),
          onRight: () => showDeleteDialog(context, title: 'Delete Student', name: student.name,
              description: "This student's data will be removed.",
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
  String? _cid;
  bool _loading = false;

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
      ScaffoldMessenger.of(context).showSnackBar(
          buildSnack('Please fill all fields and select a class', isError: true));
      return;
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
    appBar: buildAppBar(widget.student == null ? 'Add Student' : 'Edit Student'),
    body: StreamBuilder<QuerySnapshot>(
      stream: FB.classes(currentSession!.schoolId).orderBy('name').snapshots(),
      builder: (_, snap) {
        final classes = snap.hasData
            ? snap.data!.docs.map(SchoolClass.fromDoc).toList() : <SchoolClass>[];
        return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
          SurfaceCard(child: Column(children: [
            const SectionHeader('Student Information'),
            LabeledField(ctrl: _name,  label: 'Full Name',    icon: Icons.person_outline_rounded),
            const SizedBox(height: 12),
            LabeledField(ctrl: _roll,  label: 'Roll Number',  icon: Icons.tag_rounded),
            const SizedBox(height: 12),
            LabeledField(ctrl: _phone, label: 'Parent Phone', icon: Icons.phone_outlined,
                type: TextInputType.phone),
          ])),
          const SizedBox(height: 14),
          SurfaceCard(child: Column(children: [
            const SectionHeader('Class & Fee'),
            DropdownButtonFormField<String?>(
              value: _cid,
              decoration: const InputDecoration(labelText: 'Assign to Class',
                  prefixIcon: Icon(Icons.class_outlined, color: T.inkFaint, size: 20)),
              items: classes.map((c) =>
                  DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
              onChanged: (v) => setState(() => _cid = v),
            ),
            const SizedBox(height: 12),
            LabeledField(ctrl: _fee, label: 'Monthly Fee (Rs)', icon: Icons.payments_outlined,
                type: TextInputType.number),
          ])),
          const SizedBox(height: 28),
          PrimaryButton(
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
//  FEE TRACKER
// ═══════════════════════════════════════════════════════════════════

class FeeTrackerScreen extends StatefulWidget {
  const FeeTrackerScreen({super.key});
  @override State<FeeTrackerScreen> createState() => _FeeTrackerState();
}

class _FeeTrackerState extends State<FeeTrackerScreen> {
  String _filter = 'all';
  String _search = '';
  String? _classFilter;

  @override Widget build(BuildContext context) {
    final sid = currentSession!.schoolId;
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(child: StreamBuilder<QuerySnapshot>(
        stream: FB.students(sid).snapshots(),
        builder: (_, snap) {
          final all = snap.hasData ? snap.data!.docs.map(Student.fromDoc).toList() : <Student>[];
          final paid      = all.where((s) => s.feePaid).length;
          final unpaid    = all.length - paid;
          final collected = all.where((s) => s.feePaid).fold(0.0, (a, s) => a + s.monthlyFee);
          final total     = all.fold(0.0, (a, s) => a + s.monthlyFee);
          final pct       = all.isEmpty ? 0.0 : (paid / all.length).clamp(0.0, 1.0);
          final filtered  = all.where((s) {
            final mF = _filter == 'all' || (_filter == 'paid' ? s.feePaid : !s.feePaid);
            final mS = _search.isEmpty ||
                s.name.toLowerCase().contains(_search.toLowerCase()) ||
                s.rollNumber.contains(_search);
            final mC = _classFilter == null || s.classId == _classFilter;
            return mF && mS && mC;
          }).toList();

          return StreamBuilder<QuerySnapshot>(
            stream: FB.classes(sid).orderBy('name').snapshots(),
            builder: (_, clsSnap) {
              final classes = clsSnap.hasData
                  ? clsSnap.data!.docs.map(SchoolClass.fromDoc).toList() : <SchoolClass>[];
              return Column(children: [
                Container(color: Colors.white, child: Column(children: [
                  Padding(padding: const EdgeInsets.fromLTRB(20, 18, 16, 0), child: Row(children: [
                    const Expanded(child: Text('Fee Tracker', style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900, color: T.ink))),
                    IconActionButton(Icons.tune_rounded,
                            () => _bulkSheet(context, filtered)),
                  ])),
                  Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: FeeHeroBanner(collected: collected, total: total,
                          paid: paid, unpaid: unpaid, pct: pct)),
                  Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: SegmentedTabs(
                        labels: ['All', 'Paid', 'Unpaid'], counts: [all.length, paid, unpaid],
                        colors: [T.blue, T.green, T.red],
                        selected: _filter == 'all' ? 0 : _filter == 'paid' ? 1 : 2,
                        onTap: (i) => setState(() => _filter = ['all', 'paid', 'unpaid'][i]),
                      )),
                  Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Row(children: [
                        Expanded(child: SearchField(hint: 'Search name or roll…',
                            onChanged: (v) => setState(() => _search = v))),
                        const SizedBox(width: 10),
                        ClassDropdown(classes: classes, value: _classFilter,
                            onChanged: (v) => setState(() => _classFilter = v)),
                      ])),
                ])),
                Container(height: 1, color: T.divider),
                Expanded(child: filtered.isEmpty
                    ? EmptyState(Icons.account_balance_wallet_rounded, 'No students here',
                    _filter == 'unpaid' ? 'All students have paid! 🎉' : 'Add students first')
                    : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => FeeCard(student: filtered[i],
                      onToggle: () => FB.students(sid).doc(filtered[i].id)
                          .update({'feePaid': !filtered[i].feePaid})),
                )),
              ]);
            },
          );
        },
      )),
    );
  }

  void _bulkSheet(BuildContext ctx, List<Student> filtered) {
    final sid = currentSession!.schoolId;
    showModalBottomSheet(context: ctx, backgroundColor: Colors.transparent,
        builder: (_) => BulkActionSheet(
          onMarkAllPaid:   () async { for (final s in filtered.where((s) => !s.feePaid)) await FB.students(sid).doc(s.id).update({'feePaid': true}); },
          onMarkAllUnpaid: () async { for (final s in filtered.where((s) => s.feePaid))  await FB.students(sid).doc(s.id).update({'feePaid': false}); },
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
      appBar: buildAppBar('Attendance View'),
      body: Column(children: [
        Container(color: Colors.white, padding: const EdgeInsets.all(16), child: Column(children: [
          StreamBuilder<QuerySnapshot>(
            stream: FB.classes(sid).orderBy('name').snapshots(),
            builder: (_, snap) {
              final classes = snap.hasData
                  ? snap.data!.docs.map(SchoolClass.fromDoc).toList() : <SchoolClass>[];
              return DropdownButtonFormField<String?>(
                value: _cid,
                decoration: const InputDecoration(labelText: 'Select Class',
                    prefixIcon: Icon(Icons.class_outlined, color: T.inkFaint, size: 20)),
                items: classes.map((c) =>
                    DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                onChanged: (v) => setState(() => _cid = v),
              );
            },
          ),
          const SizedBox(height: 10),
          DatePickerField(date: _date, onChanged: (d) => setState(() => _date = d)),
        ])),
        Container(height: 1, color: T.divider),
        Expanded(child: _cid == null
            ? const EmptyState(Icons.class_rounded, 'Select a class',
            'Choose a class and date to view attendance')
            : StreamBuilder<QuerySnapshot>(
          stream: FB.students(sid).where('classId', isEqualTo: _cid).orderBy('name').snapshots(),
          builder: (_, studSnap) {
            final students = studSnap.hasData
                ? studSnap.data!.docs.map(Student.fromDoc).toList() : <Student>[];
            return StreamBuilder<QuerySnapshot>(
              stream: FB.attendance(sid).where('classId', isEqualTo: _cid)
                  .where('date', isEqualTo: _date).snapshots(),
              builder: (_, attSnap) {
                AttendanceRecord? record;
                if (attSnap.hasData && attSnap.data!.docs.isNotEmpty) {
                  record = AttendanceRecord.fromDoc(attSnap.data!.docs.first);
                }
                final presentC = record == null ? 0
                    : record.attendance.values.where((v) => v).length;
                return Column(children: [
                  if (students.isNotEmpty)
                    Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Row(children: [
                          AttBadge('$presentC Present', T.green, T.greenLight),
                          const SizedBox(width: 10),
                          AttBadge('${students.length - presentC} Absent', T.red, T.redLight),
                        ])),
                  Expanded(child: students.isEmpty
                      ? const EmptyState(Icons.people_rounded, 'No students',
                      'This class has no students yet')
                      : ListView.separated(
                    padding: const EdgeInsets.all(16), itemCount: students.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final s = students[i];
                      final present = record?.attendance[s.id] ?? false;
                      return Container(
                        decoration: BoxDecoration(color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: T.divider)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(children: [
                          CircleInitial(s.name, present ? T.green : T.red,
                              present ? T.greenLight : T.redLight, radius: 18),
                          const SizedBox(width: 12),
                          Expanded(child: Text(s.name, style: const TextStyle(
                              fontWeight: FontWeight.w700, color: T.ink))),
                          StatusChip(present ? 'Present' : 'Absent',
                              present ? T.green : T.red,
                              present ? T.greenLight : T.redLight),
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
//  ADMIN MORE / SETTINGS
// ═══════════════════════════════════════════════════════════════════

class AdminMoreScreen extends StatelessWidget {
  const AdminMoreScreen({super.key});
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
            const Text('Settings', style: TextStyle(fontSize: 22,
                fontWeight: FontWeight.w900, color: T.ink)),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF1E3A8A), T.blue],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: T.blue.withOpacity(.3),
                    blurRadius: 24, offset: const Offset(0, 8))],
              ),
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Container(width: 56, height: 56,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(.15),
                        borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.school_rounded, color: Colors.white, size: 28)),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(school?.name ?? '...', style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 17, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(school?.email ?? '', style: TextStyle(
                      color: Colors.white.withOpacity(.7), fontSize: 12)),
                  Text('Admin: ${school?.adminName ?? ''}', style: TextStyle(
                      color: Colors.white.withOpacity(.7), fontSize: 12)),
                ])),
              ]),
            ),
            const SizedBox(height: 20),
            _SettingRow(Icons.info_outline_rounded, 'About EduTrack',
                'Learn more about this app', T.teal,
                    () => Navigator.push(context, slideRoute(const AboutScreen()))),
            const SizedBox(height: 8),
            _SettingRow(Icons.shield_outlined, 'Privacy Policy',
                'How we handle your school\'s data', T.blue,
                    () => Navigator.push(context, slideRoute(const PrivacyPolicyScreen()))),
            const SizedBox(height: 8),
            LogoutButton(onTap: () => showLogoutDialog(context)),
          ]);
        },
      )),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  final Color color;
  final VoidCallback onTap;
  const _SettingRow(this.icon, this.title, this.sub, this.color, this.onTap);
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
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700,
                  fontSize: 15, color: T.ink)),
              Text(sub, style: const TextStyle(fontSize: 12, color: T.inkLight)),
            ])),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: color.withOpacity(.5)),
          ]),
        ),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  ABOUT SCREEN
// ═══════════════════════════════════════════════════════════════════

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      appBar: buildAppBar('About EduTrack'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E3A8A), Color(0xFF2563EB), Color(0xFF3B82F6)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [BoxShadow(color: T.blue.withOpacity(.4),
                  blurRadius: 32, offset: const Offset(0, 12))],
            ),
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
            child: Column(children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.15),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white.withOpacity(.25), width: 1.5),
                ),
                child: const Icon(Icons.school_rounded, size: 44, color: Colors.white),
              ),
              const SizedBox(height: 18),
              const Text('EduTrack', style: TextStyle(
                  fontSize: 34, fontWeight: FontWeight.w900,
                  color: Colors.white, letterSpacing: -1.5)),
              const SizedBox(height: 6),
              Text('Smart School Management',
                  style: TextStyle(color: Colors.white.withOpacity(.75), fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 28),
          SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader('ABOUT THIS APP'),
            const Text(
              'EduTrack is a comprehensive school management platform designed to simplify daily administration for schools of all sizes.',
              style: TextStyle(fontSize: 14, color: T.inkMid, height: 1.6),
            ),
            const SizedBox(height: 12),
            const Text(
              'From managing students and teachers to tracking attendance and collecting fees — everything is in one place, backed by real-time cloud sync.',
              style: TextStyle(fontSize: 14, color: T.inkMid, height: 1.6),
            ),
          ])),
          const SizedBox(height: 16),
          SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader('KEY FEATURES'),
            _FeatureRow(Icons.people_rounded, 'Teacher Management',
                'Add, edit, and assign teachers to classes with secure login credentials.', T.blue),
            const Divider(height: 20, color: T.dividerFaint),
            _FeatureRow(Icons.school_rounded, 'Student Enrollment',
                'Manage student records, roll numbers, and parent contacts.', T.purple),
            const Divider(height: 20, color: T.dividerFaint),
            _FeatureRow(Icons.fact_check_rounded, 'Attendance Tracking',
                'Teachers mark daily attendance; admins get a full overview.', T.teal),
            const Divider(height: 20, color: T.dividerFaint),
            _FeatureRow(Icons.account_balance_wallet_rounded, 'Fee Management',
                'Monitor monthly fee collection with bulk actions and filters.', T.green),
            const Divider(height: 20, color: T.dividerFaint),
            _FeatureRow(Icons.cloud_sync_rounded, 'Real-time Cloud Sync',
                'All data is stored securely in Firebase Firestore, always up to date.', T.amber),
          ])),
          const SizedBox(height: 16),
          SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader('BUILT WITH'),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _TechChip('Flutter', Icons.flutter_dash, T.blue),
              _TechChip('Firebase', Icons.local_fire_department_rounded, T.amber),
              _TechChip('Firestore', Icons.storage_rounded, T.teal),
              _TechChip('Firebase Auth', Icons.lock_rounded, T.purple),
            ]),
          ])),
          const SizedBox(height: 16),
          // Privacy Policy link
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: () => Navigator.push(context, slideRoute(const PrivacyPolicyScreen())),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: T.blue.withOpacity(.2)),
                ),
                child: Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E3A8A), T.blue],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.shield_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Privacy Policy', style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15, color: T.ink)),
                    const SizedBox(height: 2),
                    const Text('How we protect your school\'s data',
                        style: TextStyle(fontSize: 12, color: T.inkLight)),
                  ])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: T.blueLight, borderRadius: BorderRadius.circular(20)),
                    child: const Text('Read', style: TextStyle(color: T.blue,
                        fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: T.blueLight, borderRadius: BorderRadius.circular(18),
                border: Border.all(color: T.blue.withOpacity(.15))),
            child: Column(children: [
              const Icon(Icons.copyright_rounded, color: T.blue, size: 22),
              const SizedBox(height: 8),
              Text(
                '© ${DateTime.now().year} EduTrack. All rights reserved.',
                style: const TextStyle(color: T.blue, fontWeight: FontWeight.w800, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              const Text(
                'This application is intended for authorized school use only.',
                style: TextStyle(color: T.inkLight, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ]),
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title, description;
  final Color color;
  const _FeatureRow(this.icon, this.title, this.description, this.color);

  @override Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(width: 40, height: 40,
        decoration: BoxDecoration(color: color.withOpacity(.1), borderRadius: BorderRadius.circular(11)),
        child: Icon(icon, color: color, size: 20)),
    const SizedBox(width: 14),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: T.ink)),
      const SizedBox(height: 3),
      Text(description, style: const TextStyle(fontSize: 12, color: T.inkLight, height: 1.5)),
    ])),
  ]);
}

class _TechChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _TechChip(this.label, this.icon, this.color);

  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(color: color.withOpacity(.08), borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(.2))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 15),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
    ]),
  );
}
// ═══════════════════════════════════════════════════════════════════
//  PRIVACY POLICY SCREEN
// ═══════════════════════════════════════════════════════════════════
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});
  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          // Prevent the WebView from navigating away from the local HTML
          onNavigationRequest: (request) =>
          request.url.startsWith('data:') || request.url == 'about:blank'
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );
    _loadAsset();
  }

  Future<void> _loadAsset() async {
    // Guard against async gap where widget may have been disposed
    if (!mounted) return;
    final html = await rootBundle.loadString('assets/privacy_policy.html');
    if (!mounted) return;              // ← check again after await
    await _controller.loadHtmlString(html);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: buildAppBar('Privacy Policy'),
    body: Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          const Center(child: CircularProgressIndicator()),
      ],
    ),
  );
}