import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/rn_api.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../widgets/rn_kit.dart';
import '../widgets/use_api.dart';

/// Port of `frontend/app/student-details.tsx` (Expo v2.11.1).
class StudentDetailsScreen extends StatefulWidget {
  const StudentDetailsScreen({super.key});
  @override
  State<StudentDetailsScreen> createState() => _StudentDetailsScreenState();
}

class _StudentDetailsScreenState extends State<StudentDetailsScreen> with UseApi<StudentDetailsScreen> {
  late final _info = useApi(RnApi.myInfo, initial: UserSession.instance.myInfo);
  late final _addtnl = useApi(RnApi.studentAddtnlInfo, initial: UserSession.instance.studentAddtnlInfo);

  @override
  void initState() {
    super.initState();
    _info;
    _addtnl;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final session = context.watch<UserSession>();
    final hasSelectedStudent = session.activeStudentName?.trim().isNotEmpty ?? false;
    final user = hasSelectedStudent ? const <String, dynamic>{}
        : session.authData ?? const <String, dynamic>{};
    final info = (hasSelectedStudent ? session.activeStudentInfo : _info.data) ?? const <String, dynamic>{};
    final extra = hasSelectedStudent ? const <String, dynamic>{}
        : _addtnl.data ?? const <String, dynamic>{};
    final loading = hasSelectedStudent ? session.activeStudentInfoLoading : _info.loading || _addtnl.loading;
    String v(dynamic x) => '${x ?? ''}'.trim();
    String or(List<dynamic> xs) => xs.map(v).firstWhere((s) => s.isNotEmpty, orElse: () => '—');

    final fields = [
      (icon: Ion.personOutline, label: 'Name', value: or([info['name'], user['name']])),
      (icon: Ion.cardOutline, label: 'Registration No', value: or([info['registrationNo'], user['code']])),
      (icon: Ion.fingerPrintOutline, label: 'IC No', value: or([user['icNo']])),
      (icon: Ion.ribbonOutline, label: 'Current Grade', value: or([info['currentGrade'], user['currentGrade']])),
      (icon: Ion.locationOutline, label: 'Training Center', value: or([info['tCenterName']])),
      (icon: Ion.businessOutline, label: 'Exam Center', value: or([info['eCenterName']])),
      (icon: Ion.personCircleOutline, label: 'Instructor', value: or([info['instructorName']])),
      (icon: Ion.callOutline, label: 'Phone', value: or([user['handPhone'], extra['mobileNo']])),
      (icon: Ion.schoolOutline, label: 'School', value: or([extra['schoolname']])),
      (icon: Ion.calendarOutline, label: 'Date of Birth', value: fmtDateGB(extra['dob'], empty: '—')),
      (icon: Ion.waterOutline, label: 'Blood Type', value: or([extra['bloodtype']])),
      (icon: Ion.fitnessOutline, label: 'Health Status', value: or([extra['healthstatus']])),
    ];

    return Scaffold(
      backgroundColor: c.background,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const RnHeader(title: 'Student Details', horizontal: Gaps.lg),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.xl, Gaps.xl, 60),
            children: [
              if (loading) const RnSpinner(vertical: 30),
              // Nothing cached and the fetch failed: say so rather than a card of dashes.
              if (!loading && ((hasSelectedStudent && session.activeStudentInfo == null) ||
                  (!hasSelectedStudent && _info.data == null && _info.error != null)))
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ErrorState(
                      message: 'Could not load your details. ${hasSelectedStudent ? session.activeStudentInfoError ?? '' : _info.error}',
                      onRetry: () {
                        if (hasSelectedStudent) {
                          session.switchStudent(session.activeStudentId ?? 0,
                              studentName: session.activeStudentName);
                        } else {
                          _info.reload();
                          _addtnl.reload();
                        }
                      }),
                ),
              if (!loading)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: rnCard(c, radius: Radii.xl),
                  child: Column(children: [
                    for (var i = 0; i < fields.length; i++) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        child: Row(children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
                            child: Icon(fields[i].icon, size: 18, color: c.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(fields[i].label,
                                  maxLines: 1,
                                  style: TextStyle(fontSize: 12, color: c.textSecondary, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(fields[i].value,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 15, color: c.textPrimary, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ]),
                      ),
                      if (i < fields.length - 1) Container(height: 1, color: c.border),
                    ],
                  ]),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}
