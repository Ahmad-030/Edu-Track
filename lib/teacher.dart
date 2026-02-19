import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'main.dart';

// ═══════════════════════════════════════════════════════════════════
//  TEACHER DASHBOARD
// ═══════════════════════════════════════════════════════════════════

class TeacherDashboard extends StatefulWidget {
  const TeacherDashboard({super.key});
  @override State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {

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
            Expanded(child: OutlineButton(label: 'Cancel', onTap: () => Navigator.pop(context, false))),
            const SizedBox(width: 12),
            Expanded(child: PrimaryButton(label: 'Logout', onTap: () => Navigator.pop(context, true))),
          ]),
        ])),
      ),
    );

    if (confirmed != true) return;

    // Clear session first → UI reacts instantly via _AuthGate
    suppressAuthEvents = true;
    sessionNotifier.value = null;
    FB.signOut(); // fire-and-forget
  }

  @override Widget build(BuildContext context) {
    if (currentSession == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final session = currentSession!;
    final sid = session.schoolId;
    final tid = session.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: FB.teachers(sid).doc(tid).snapshots(),
      builder: (_, tSnap) {
        final teacher = tSnap.hasData && tSnap.data!.exists
            ? Teacher.fromDoc(tSnap.data!) : null;
        final classId = teacher?.classId;

        return Scaffold(
          backgroundColor: T.bg,
          body: SafeArea(child: classId == null
              ? _noClassView(teacher)
              : StreamBuilder<DocumentSnapshot>(
            stream: FB.classes(sid).doc(classId).snapshots(),
            builder: (_, clsSnap) {
              final myClass = clsSnap.hasData && clsSnap.data!.exists
                  ? SchoolClass.fromDoc(clsSnap.data!) : null;
              return StreamBuilder<QuerySnapshot>(
                stream: FB.students(sid).where('classId', isEqualTo: classId)
                    .orderBy('name').snapshots(),
                builder: (_, studSnap) {
                  final students = studSnap.hasData
                      ? studSnap.data!.docs.map(Student.fromDoc).toList() : <Student>[];
                  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
                  return StreamBuilder<QuerySnapshot>(
                    stream: FB.attendance(sid).where('classId', isEqualTo: classId)
                        .where('date', isEqualTo: today).snapshots(),
                    builder: (_, attSnap) {
                      final todayRec = attSnap.hasData && attSnap.data!.docs.isNotEmpty
                          ? AttendanceRecord.fromDoc(attSnap.data!.docs.first) : null;
                      final presentToday = todayRec?.attendance.values.where((v) => v).length;
                      final paid   = students.where((s) => s.feePaid).length;
                      final unpaid = students.length - paid;

                      return ListView(padding: const EdgeInsets.all(20), children: [
                        // ── Header ──────────────────────────────────
                        Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Hello, ${teacher?.name ?? 'Teacher'}! 👋',
                                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900,
                                    color: T.ink, letterSpacing: -.3)),
                            const SizedBox(height: 3),
                            Row(children: [
                              Container(width: 6, height: 6,
                                  decoration: const BoxDecoration(color: T.green, shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Text(teacher?.subject ?? '', style: const TextStyle(
                                  color: T.inkLight, fontSize: 13, fontWeight: FontWeight.w600)),
                            ]),
                          ])),
                          InitialBubble(teacher?.name ?? 'T'),
                        ]),
                        const SizedBox(height: 22),

                        // ── Hero class card ──────────────────────────
                        Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF4C1D95), T.purple, T.purpleMid],
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [BoxShadow(color: T.purple.withOpacity(.4),
                                blurRadius: 24, offset: const Offset(0, 10))],
                          ),
                          padding: const EdgeInsets.all(22),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Container(padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: Colors.white.withOpacity(.15),
                                      borderRadius: BorderRadius.circular(10)),
                                  child: const Icon(Icons.class_rounded, color: Colors.white, size: 16)),
                              const SizedBox(width: 10),
                              Text('My Class', style: TextStyle(
                                  color: Colors.white.withOpacity(.8), fontSize: 13, fontWeight: FontWeight.w700)),
                            ]),
                            const SizedBox(height: 10),
                            Text(myClass?.name ?? '...', style: const TextStyle(
                                fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -.8)),
                            const SizedBox(height: 14),
                            Row(children: [
                              Text('${students.length} Students', style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                              const SizedBox(width: 4),
                              Text('·', style: TextStyle(color: Colors.white.withOpacity(.4))),
                              const SizedBox(width: 4),
                              if (presentToday != null)
                                Text('$presentToday Present Today', style: TextStyle(
                                    color: Colors.white.withOpacity(.75), fontWeight: FontWeight.w600, fontSize: 13))
                              else
                                Text('Not marked today', style: TextStyle(
                                    color: Colors.white.withOpacity(.55), fontSize: 13)),
                            ]),
                            const SizedBox(height: 18),
                            Row(children: [
                              Expanded(child: _TeacherActionBtn('Mark Attendance', Icons.fact_check_rounded,
                                      () => Navigator.push(context, slideRoute(
                                      MarkAttendanceScreen(classId: classId, sid: sid))))),
                              const SizedBox(width: 10),
                              Expanded(child: _TeacherActionBtn('View History', Icons.history_rounded,
                                      () => Navigator.push(context, slideRoute(
                                      AttendanceHistoryScreen(classId: classId, sid: sid))))),
                            ]),
                          ]),
                        ),
                        const SizedBox(height: 20),

                        // ── Stats ────────────────────────────────────
                        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Expanded(child: StatTile(label: 'Students', value: '${students.length}',
                              icon: Icons.people_rounded, color: T.blue)),
                          const SizedBox(width: 12),
                          Expanded(child: StatTile(label: 'Unpaid', value: '$unpaid',
                              icon: Icons.pending_rounded, color: unpaid > 0 ? T.red : T.green)),
                        ])),
                        const SizedBox(height: 22),

                        // ── Quick Actions ────────────────────────────
                        const Text('Quick Actions', style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800, color: T.ink)),
                        const SizedBox(height: 12),
                        ActionRow(
                          icon: Icons.person_add_rounded, label: 'Add Student',
                          sub: 'Enroll to ${myClass?.name ?? ''}', color: T.blue,
                          onTap: () => Navigator.push(context, slideRoute(TeacherAddStudentScreen(
                              classId: classId, className: myClass?.name ?? '', sid: sid))),
                        ),
                        ActionRow(
                          icon: Icons.account_balance_wallet_rounded, label: 'Manage Fees',
                          sub: 'Mark fees for ${myClass?.name ?? ''}', color: T.green,
                          onTap: () => Navigator.push(context, slideRoute(TeacherFeeScreen(
                              classId: classId, className: myClass?.name ?? '', sid: sid))),
                        ),
                        const SizedBox(height: 8),
                        LogoutButton(onTap: _logout),
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
      InitialBubble(teacher?.name ?? 'T'),
    ]),
    const SizedBox(height: 32),
    Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF4C1D95), T.purple], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Column(children: [
        Icon(Icons.warning_amber_rounded, color: Colors.white, size: 44),
        SizedBox(height: 14),
        Text('No Class Assigned', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
        SizedBox(height: 8),
        Text('Contact your administrator to get assigned to a class.',
            style: TextStyle(color: Colors.white70, fontSize: 14), textAlign: TextAlign.center),
      ]),
    ),
    const SizedBox(height: 24),
    LogoutButton(onTap: _logout),
  ]);
}

class _TeacherActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _TeacherActionBtn(this.label, this.icon, this.onTap);
  @override Widget build(BuildContext context) => ElevatedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 16),
    label: Text(label, style: const TextStyle(fontSize: 13)),
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.white.withOpacity(.2), foregroundColor: Colors.white,
      minimumSize: const Size(0, 44), elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withOpacity(.3))),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  TEACHER ADD STUDENT
// ═══════════════════════════════════════════════════════════════════

class TeacherAddStudentScreen extends StatefulWidget {
  final String classId, className, sid;
  const TeacherAddStudentScreen({super.key,
    required this.classId, required this.className, required this.sid});
  @override State<TeacherAddStudentScreen> createState() => _TeacherAddStudentState();
}

class _TeacherAddStudentState extends State<TeacherAddStudentScreen> {
  final _name  = TextEditingController();
  final _roll  = TextEditingController();
  final _phone = TextEditingController();
  final _fee   = TextEditingController();
  bool _loading = false;

  void _save() async {
    if ([_name, _roll, _phone, _fee].any((c) => c.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(buildSnack('Please fill all fields', isError: true));
      return;
    }
    setState(() => _loading = true);
    await FB.students(widget.sid).add({
      'classId': widget.classId, 'name': _name.text.trim(),
      'rollNumber': _roll.text.trim(), 'parentPhone': _phone.text.trim(),
      'monthlyFee': double.tryParse(_fee.text) ?? 0, 'feePaid': false,
    });
    setState(() => _loading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(buildSnack('${_name.text} added!'));
      Navigator.pop(context);
    }
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: buildAppBar('Add Student'),
    body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
      Container(
        width: double.infinity, padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: T.purpleLight, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: T.purple.withOpacity(.2))),
        child: Row(children: [
          const Icon(Icons.class_rounded, color: T.purple, size: 22),
          const SizedBox(width: 12),
          Text(widget.className, style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w900, color: T.purple)),
        ]),
      ),
      const SizedBox(height: 16),
      SurfaceCard(child: Column(children: [
        const SectionHeader('Student Information'),
        LabeledField(ctrl: _name,  label: 'Full Name',    icon: Icons.person_outline_rounded),
        const SizedBox(height: 12),
        LabeledField(ctrl: _roll,  label: 'Roll Number',  icon: Icons.tag_rounded),
        const SizedBox(height: 12),
        LabeledField(ctrl: _phone, label: 'Parent Phone', icon: Icons.phone_outlined,
            type: TextInputType.phone),
        const SizedBox(height: 12),
        LabeledField(ctrl: _fee,   label: 'Monthly Fee (Rs)', icon: Icons.payments_outlined,
            type: TextInputType.number),
      ])),
      const SizedBox(height: 28),
      PrimaryButton(
        label: 'Add Student', icon: Icons.person_add_rounded,
        onTap: _loading ? null : _save, loading: _loading,
      ),
    ])),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  TEACHER FEE SCREEN
// ═══════════════════════════════════════════════════════════════════

class TeacherFeeScreen extends StatefulWidget {
  final String classId, className, sid;
  const TeacherFeeScreen({super.key,
    required this.classId, required this.className, required this.sid});
  @override State<TeacherFeeScreen> createState() => _TeacherFeeState();
}

class _TeacherFeeState extends State<TeacherFeeScreen> {
  String _filter = 'all';
  String _search = '';

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(child: StreamBuilder<QuerySnapshot>(
        stream: FB.students(widget.sid)
            .where('classId', isEqualTo: widget.classId)
            .orderBy('name').snapshots(),
        builder: (_, snap) {
          final all = snap.hasData
              ? snap.data!.docs.map(Student.fromDoc).toList() : <Student>[];
          final paid      = all.where((s) => s.feePaid).length;
          final unpaid    = all.length - paid;
          final collected = all.where((s) => s.feePaid).fold(0.0, (a, s) => a + s.monthlyFee);
          final total     = all.fold(0.0, (a, s) => a + s.monthlyFee);
          final pct       = all.isEmpty ? 0.0 : (paid / all.length).clamp(0.0, 1.0);
          final filtered  = all.where((s) {
            final mF = _filter == 'all' || (_filter == 'paid' ? s.feePaid : !s.feePaid);
            final mS = _search.isEmpty ||
                s.name.toLowerCase().contains(_search.toLowerCase());
            return mF && mS;
          }).toList();

          return Column(children: [
            Container(color: Colors.white, child: Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: Row(children: [
                IconActionButton(Icons.arrow_back_ios_rounded,
                        () => Navigator.pop(context), size: 18),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Fee Management', style: TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w900, color: T.ink)),
                  Text(widget.className, style: const TextStyle(fontSize: 12, color: T.inkLight)),
                ])),
              ])),
              const SizedBox(height: 14),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FeeHeroBanner(collected: collected, total: total,
                      paid: paid, unpaid: unpaid, pct: pct)),
              const SizedBox(height: 12),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedTabs(
                    labels: ['All', 'Paid', 'Unpaid'], counts: [all.length, paid, unpaid],
                    colors: [T.blue, T.green, T.red],
                    selected: _filter == 'all' ? 0 : _filter == 'paid' ? 1 : 2,
                    onTap: (i) => setState(() => _filter = ['all', 'paid', 'unpaid'][i]),
                  )),
              Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: SearchField(hint: 'Search by name…',
                      onChanged: (v) => setState(() => _search = v))),
            ])),
            Container(height: 1, color: T.divider),
            Expanded(child: filtered.isEmpty
                ? EmptyState(Icons.account_balance_wallet_rounded, 'No students',
                _filter == 'unpaid' ? 'All paid! 🎉' : 'No students found')
                : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => FeeCard(
                student: filtered[i],
                onToggle: () => FB.students(widget.sid).doc(filtered[i].id)
                    .update({'feePaid': !filtered[i].feePaid}),
              ),
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
      stream: FB.students(widget.sid)
          .where('classId', isEqualTo: widget.classId)
          .orderBy('name').snapshots(),
      builder: (_, studSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FB.attendance(widget.sid)
              .where('classId', isEqualTo: widget.classId)
              .where('date', isEqualTo: _date).snapshots(),
          builder: (_, attSnap) {
            final students = studSnap.hasData
                ? studSnap.data!.docs.map(Student.fromDoc).toList() : <Student>[];

            if (!_initialized && students.isNotEmpty) {
              AttendanceRecord? existing;
              if (attSnap.hasData && attSnap.data!.docs.isNotEmpty) {
                existing = AttendanceRecord.fromDoc(attSnap.data!.docs.first);
              }
              for (final s in students) _att[s.id] = existing?.attendance[s.id] ?? true;
              _initialized = true;
            }

            final present = _att.values.where((v) => v).length;
            final absent  = students.length - present;

            return Scaffold(
              appBar: buildAppBar('Mark Attendance', subtitle: _date),
              body: Column(children: [
                Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Row(children: [
                      Expanded(child: AttBadge('$present Present', T.green, T.greenLight)),
                      const SizedBox(width: 10),
                      Expanded(child: AttBadge('$absent Absent', T.red, T.redLight)),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => setState(() { for (final k in _att.keys) _att[k] = true; }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(color: T.blueLight, borderRadius: BorderRadius.circular(10)),
                          child: const Text('All ✓', style: TextStyle(
                              color: T.blue, fontWeight: FontWeight.w800, fontSize: 13)),
                        ),
                      ),
                    ])),
                Container(height: 1, color: T.divider),
                Expanded(child: students.isEmpty
                    ? const EmptyState(Icons.people_rounded, 'No students',
                    'Add students to this class first')
                    : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                  itemCount: students.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final s = students[i];
                    final p = _att[s.id] ?? true;
                    return GestureDetector(
                      onTap: () => setState(() => _att[s.id] = !p),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: p ? T.greenLight : T.redLight,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: (p ? T.green : T.red).withOpacity(.25), width: 1.5),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        child: Row(children: [
                          CircleInitial(s.name, p ? T.green : T.red, Colors.white, radius: 19),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.name, style: const TextStyle(
                                fontWeight: FontWeight.w700, color: T.ink, fontSize: 15)),
                            Text('Roll #${s.rollNumber}',
                                style: const TextStyle(fontSize: 12, color: T.inkLight)),
                          ])),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              p ? Icons.check_circle_rounded : Icons.cancel_rounded,
                              key: ValueKey(p), color: p ? T.green : T.red, size: 28,
                            ),
                          ),
                        ]),
                      ),
                    );
                  },
                )),
                Padding(padding: const EdgeInsets.all(16), child: PrimaryButton(
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(buildSnack('Attendance saved!'));
    }
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
      appBar: buildAppBar('Attendance History'),
      body: StreamBuilder<QuerySnapshot>(
        stream: FB.attendance(sid).where('classId', isEqualTo: classId)
            .orderBy('date', descending: true).snapshots(),
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final records = snap.data!.docs.map(AttendanceRecord.fromDoc).toList();
          if (records.isEmpty) return const EmptyState(Icons.history_rounded,
              'No records yet', 'Mark attendance to see history here');
          return StreamBuilder<QuerySnapshot>(
            stream: FB.students(sid).where('classId', isEqualTo: classId).snapshots(),
            builder: (_, studSnap) {
              final students = studSnap.hasData
                  ? studSnap.data!.docs.map(Student.fromDoc).toList() : <Student>[];
              return ListView.separated(
                padding: const EdgeInsets.all(16), itemCount: records.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final r       = records[i];
                  final total   = students.length;
                  final present = r.attendance.values.where((v) => v).length;
                  final pct     = total == 0 ? 0.0 : present / total;
                  final c  = pct >= .8 ? T.green : pct >= .5 ? T.blue : T.red;
                  final bg = pct >= .8 ? T.greenLight : pct >= .5 ? T.blueLight : T.redLight;

                  return InkWell(
                    onTap: () => Navigator.push(context, slideRoute(
                        AttendanceDetailScreen(record: r, sid: sid, classId: classId))),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: T.divider)),
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        Container(width: 48, height: 48,
                            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                            child: Icon(Icons.calendar_today_rounded, color: c, size: 22)),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.date, style: const TextStyle(
                              fontWeight: FontWeight.w700, color: T.ink, fontSize: 15)),
                          const SizedBox(height: 6),
                          ClipRRect(borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(value: pct, minHeight: 5,
                                  backgroundColor: T.divider, color: c)),
                          const SizedBox(height: 5),
                          Text('$present / $total  ·  ${(pct * 100).round()}%',
                              style: const TextStyle(color: T.inkLight, fontSize: 12)),
                        ])),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: T.inkFaint),
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

// ═══════════════════════════════════════════════════════════════════
//  ATTENDANCE DETAIL
// ═══════════════════════════════════════════════════════════════════

class AttendanceDetailScreen extends StatelessWidget {
  final AttendanceRecord record;
  final String sid, classId;
  const AttendanceDetailScreen({super.key,
    required this.record, required this.sid, required this.classId});

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppBar(record.date),
      body: StreamBuilder<QuerySnapshot>(
        stream: FB.students(sid).where('classId', isEqualTo: classId)
            .orderBy('name').snapshots(),
        builder: (_, snap) {
          final students = snap.hasData
              ? snap.data!.docs.map(Student.fromDoc).toList() : <Student>[];
          final present = record.attendance.values.where((v) => v).length;
          return Column(children: [
            Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Row(children: [
                  Expanded(child: AttBadge('$present Present', T.green, T.greenLight)),
                  const SizedBox(width: 10),
                  Expanded(child: AttBadge('${students.length - present} Absent', T.red, T.redLight)),
                ])),
            Container(height: 1, color: T.divider),
            Expanded(child: ListView.separated(
              padding: const EdgeInsets.all(16), itemCount: students.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final s = students[i];
                final p = record.attendance[s.id] ?? false;
                return Container(
                  decoration: BoxDecoration(color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: T.divider)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    CircleInitial(s.name, p ? T.green : T.red,
                        p ? T.greenLight : T.redLight, radius: 17),
                    const SizedBox(width: 12),
                    Expanded(child: Text(s.name, style: const TextStyle(
                        fontWeight: FontWeight.w600, color: T.ink))),
                    StatusChip(p ? 'Present' : 'Absent',
                        p ? T.green : T.red, p ? T.greenLight : T.redLight),
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