import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/splash_screen.dart';
import '../screens/new_student_screen.dart';
import '../screens/login_screen.dart';
import '../screens/tabs_shell.dart';
import '../screens/home_screen.dart';
import '../screens/training_screen.dart';
import '../screens/schedule_screen.dart';
import '../screens/payments_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/attendance_screen.dart';
import '../screens/book_class_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/chat_thread_screen.dart';
import '../screens/more_screen.dart';
import '../screens/autopay_screen.dart';
import '../screens/belt_rank_screen.dart';
import '../screens/tournament_screen.dart';
import '../screens/edit_profile_screen.dart';
import '../screens/helpdesk_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/offer_detail_screen.dart';
import '../screens/offers_screen.dart';
import '../screens/user_guide_screen.dart';
import '../screens/student_details_screen.dart';
import '../screens/purchases_screen.dart';
import '../screens/purchase_request_screen.dart';
import '../screens/notification_settings_screen.dart';
import '../screens/progress_screen.dart';
import '../screens/events_screen.dart';
import '../screens/qr_scan_screen.dart';
import '../screens/debug_screen.dart';
import '../screens/outstanding_invoices_screen.dart';
import '../screens/instructor_tabs_shell.dart';
import '../screens/instructor_attendance_screen.dart';
import '../screens/instructor_home_screen.dart';
import '../screens/instructor_collections_screen.dart';
import '../screens/instructor_reports_screen.dart';
import '../screens/instructor_report_list_screen.dart';
import '../screens/instructor_reports/report_spec.dart';
import '../screens/instructor_reports/student_detail_screen.dart';
import '../screens/instructor_reports/rn_reports.dart';
import '../screens/profile_screen.dart' show ProfileScreen;
import '../services/api.dart';
import '../services/live_refresh.dart';
import '../services/user_session.dart';

/// Bare report fetcher: a no-argument call returning the raw response.
typedef ReportFetcher = Future<dynamic> Function();

/// Fade-through page: the outgoing screen fades out as the incoming one
/// fades in and lifts slightly. Calmer than the default platform slide,
/// and consistent across Android / iOS / web.
CustomTransitionPage<void> _fadeThrough(LocalKey key, Widget child) {
  return CustomTransitionPage<void>(
    key: key,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    child: child,
    transitionsBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutQuart,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.035),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Quick cross-fade for bottom-nav tab switches. No slide: lateral motion
/// reads wrong when the tab bar itself doesn't move.
CustomTransitionPage<void> _tabFade(LocalKey key, Widget child) {
  return CustomTransitionPage<void>(
    key: key,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    child: child,
    transitionsBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  );
}

GoRoute _reportRoute(String path, String title, ReportFetcher fetcher) {
  final slug = path.split('/').last;
  final spec =
      kReportSpecs[slug] ?? ReportSpec(title: title, fetch: (_) => fetcher());
  return GoRoute(
    path: path,
    pageBuilder: (_, state) => _fadeThrough(
      state.pageKey,
      InstructorReportListScreen(spec: spec),
    ),
  );
}

/// Developer screens, registered in debug builds only. The /debug dump shows the whole
/// session, bearer token included, so a release build must not carry it.
@visibleForTesting
List<RouteBase> developerRoutes({bool enabled = kDebugMode}) => [
      if (enabled) GoRoute(path: '/debug', builder: (_, __) => const DebugScreen()),
    ];

/// Locations that open without signing in.
@visibleForTesting
Set<String> publicPaths({bool developerTools = kDebugMode}) => {
      '/',
      '/login',
      '/user-guide',
      if (developerTools) '/debug',
    };

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  observers: [LiveRefreshNavigatorObserver()],
  redirect: (context, state) {
    final loc = state.matchedLocation;
    if (publicPaths().contains(loc)) return null;
    if (!UserSession.instance.isLoggedIn) return '/login';
    if (loc.startsWith('/instructor') && !UserSession.instance.isInstructor)
      return '/home';
    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
    // Plain fade, no slide: the splash glides its logo and word onto this page's header,
    // so the header must appear exactly where they land.
    GoRoute(path: '/login', pageBuilder: (_, s) => _tabFade(s.pageKey, const LoginScreen())),
    ShellRoute(
      observers: [LiveRefreshNavigatorObserver()],
      builder: (context, state, child) =>
          TabsShell(child: child, location: state.matchedLocation),
      routes: [
        GoRoute(
            path: '/home',
            pageBuilder: (_, s) => _tabFade(s.pageKey, const HomeScreen())),
        GoRoute(
            path: '/schedule',
            pageBuilder: (_, s) => _tabFade(s.pageKey, const ScheduleScreen())),
        GoRoute(
            path: '/progress',
            pageBuilder: (_, s) => _tabFade(s.pageKey, const ProgressScreen())),
        GoRoute(
            path: '/profile',
            pageBuilder: (_, s) => _tabFade(s.pageKey, const ProfileScreen())),
        // Reachable from quick-access tiles + home Pay Now / Today's Class.
        GoRoute(
            path: '/training',
            pageBuilder: (_, s) => _tabFade(s.pageKey, const TrainingScreen())),
        GoRoute(
            path: '/payments',
            pageBuilder: (_, s) => _tabFade(
                s.pageKey,
                PaymentsScreen(
                    initialTab: s.uri.queryParameters['tab'] ?? 'pay'))),
      ],
    ),
    ShellRoute(
      observers: [LiveRefreshNavigatorObserver()],
      builder: (context, state, child) => InstructorTabsShell(
        child: child,
        location: state.matchedLocation,
      ),
      routes: [
        GoRoute(
            path: '/instructor/home',
            pageBuilder: (_, s) =>
                _tabFade(s.pageKey, const InstructorHomeScreen())),
        GoRoute(
            path: '/instructor/collections',
            pageBuilder: (_, s) =>
                _tabFade(s.pageKey, const InstructorCollectionsScreen())),
        GoRoute(
            path: '/instructor/reports',
            pageBuilder: (_, s) =>
                _tabFade(s.pageKey, const InstructorReportsScreen())),
        // The instructor Settings tab is the role-aware Profile screen, as in Expo v2.11.1.
        GoRoute(
            path: '/instructor/settings',
            pageBuilder: (_, s) => _tabFade(s.pageKey, const ProfileScreen())),
      ],
    ),
    // Drill-down report routes (outside the shell so they appear full-screen
    // with their own back button).
    GoRoute(path: '/instructor/reports/student-centers', pageBuilder: (_, s) => _fadeThrough(s.pageKey, const RStudentCentersScreen())),
    GoRoute(path: '/instructor/reports/training-centers', pageBuilder: (_, s) => _fadeThrough(s.pageKey, const RTrainingCentersScreen())),
    GoRoute(path: '/instructor/reports/exam-centers', pageBuilder: (_, s) => _fadeThrough(s.pageKey, const RExamCentersScreen())),
    GoRoute(path: '/instructor/reports/student-list', pageBuilder: (_, s) => _fadeThrough(s.pageKey, const RStudentListScreen())),
    GoRoute(path: '/instructor/reports/training-time', pageBuilder: (_, s) => _fadeThrough(s.pageKey, const RTrainingScheduleScreen())),
    GoRoute(path: '/instructor/reports/grading-schedule', pageBuilder: (_, s) => _fadeThrough(s.pageKey, const RGradingScreen())),
    GoRoute(path: '/instructor/reports/grading-past', pageBuilder: (_, s) => _fadeThrough(s.pageKey, const RGradingScreen(title: 'Grade Completed'))),
    GoRoute(path: '/instructor/reports/outstanding', pageBuilder: (_, s) => _fadeThrough(s.pageKey, const ROutstandingScreen())),
    GoRoute(path: '/instructor/reports/attendance', pageBuilder: (_, s) => _fadeThrough(s.pageKey, const RAttendanceScreen())),
    GoRoute(path: '/instructor/reports/receipt', pageBuilder: (_, s) => _fadeThrough(s.pageKey, const RReceiptsScreen())),
    GoRoute(path: '/instructor/reports/purchase-request', pageBuilder: (_, s) => _fadeThrough(s.pageKey, const RPurchaseRequestsScreen())),
    GoRoute(path: '/instructor/reports/payment-slip', pageBuilder: (_, s) => _fadeThrough(s.pageKey, const RPaymentSlipsScreen())),
    GoRoute(path: '/instructor/reports/tournament-summary', pageBuilder: (_, s) => _fadeThrough(s.pageKey, const RTournamentScreen())),
    // Old Past / Upcoming entries showed the same date-less summary; keep their links working.
    GoRoute(path: '/instructor/reports/tournament-past', redirect: (_, __) => '/instructor/reports/tournament-summary'),
    GoRoute(path: '/instructor/reports/tournament-upcoming', redirect: (_, __) => '/instructor/reports/tournament-summary'),
    GoRoute(path: '/instructor/reports/tournament', redirect: (_, __) => '/instructor/reports/tournament-summary'),
    GoRoute(path: '/instructor/reports/contribution', pageBuilder: (_, s) => _fadeThrough(s.pageKey, const RContributionScreen())),
    GoRoute(path: '/instructor/reports/reimbursement', pageBuilder: (_, s) => _fadeThrough(s.pageKey, const RReimbursementScreen())),
    // Reports this app has that Expo listed as "coming soon" — generic list screens.
    _reportRoute('/instructor/reports/activity', 'Activities', Api.reportsActivity),
    _reportRoute('/instructor/reports/missing-invoice', 'Missing Invoice', Api.outstandingFetch),
    _reportRoute('/instructor/reports/fee-master', 'Invoice Types', Api.listingInvoceTypes),
    GoRoute(
      path: '/instructor/collections/:typeId',
      pageBuilder: (_, state) => _fadeThrough(
        state.pageKey,
        CollectionListScreen(
          typeId: int.tryParse(state.pathParameters['typeId'] ?? '') ?? 1,
          label: state.uri.queryParameters['label'] ?? 'Collections',
        ),
      ),
    ),
    GoRoute(
        path: '/instructor/reports/new-student',
        builder: (_, __) => const NewStudentScreen()),
    GoRoute(
        path: '/instructor/student-particulars/:id',
        builder: (_, state) => StudentParticularsScreen(
            id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
            name: state.uri.queryParameters['name'] ?? '')),
    GoRoute(
      path: '/instructor/student-detail',
      pageBuilder: (_, state) {
        final extra = state.extra;
        final student = extra is Map
            ? Map<String, dynamic>.from(extra)
            : <String, dynamic>{};
        return MaterialPage(
          key: state.pageKey,
          child: InstructorStudentDetailScreen(student: student),
        );
      },
    ),
    GoRoute(
        path: '/instructor/attendance',
        pageBuilder: (_, s) =>
            _fadeThrough(s.pageKey, const InstructorAttendanceScreen())),
    GoRoute(
      path: '/instructor/qr-scan',
      pageBuilder: (_, state) => MaterialPage(
        key: state.pageKey,
        fullscreenDialog: true,
        child: const QRScanScreen(),
      ),
    ),
    GoRoute(
        path: '/invoices',
        pageBuilder: (_, s) =>
            _fadeThrough(s.pageKey, const OutstandingInvoicesScreen())),
    GoRoute(
        path: '/book-class',
        pageBuilder: (_, s) =>
            _fadeThrough(s.pageKey, const BookClassScreen())),
    GoRoute(
        path: '/chat',
        pageBuilder: (_, s) => _fadeThrough(s.pageKey, const ChatScreen())),
    GoRoute(
        path: '/more',
        pageBuilder: (_, s) => _fadeThrough(s.pageKey, const MoreScreen())),
    GoRoute(
        path: '/purchases',
        pageBuilder: (_, s) =>
            _fadeThrough(s.pageKey, const PurchasesScreen())),
    GoRoute(
        path: '/autopay',
        pageBuilder: (_, s) => _fadeThrough(s.pageKey, const AutoPayScreen())),
    GoRoute(
        path: '/purchase-request',
        pageBuilder: (_, s) =>
            _fadeThrough(s.pageKey, const PurchaseRequestScreen())),
    GoRoute(
        path: '/edit-profile',
        pageBuilder: (_, s) =>
            _fadeThrough(s.pageKey, const EditProfileScreen())),
    GoRoute(
        path: '/student-details',
        pageBuilder: (_, s) =>
            _fadeThrough(s.pageKey, const StudentDetailsScreen())),
    GoRoute(
        path: '/helpdesk',
        pageBuilder: (_, s) => _fadeThrough(s.pageKey, const HelpDeskScreen())),
    // Linked from the sign-in screen, so it must open for someone with no account. The
    // redirect above only guards /instructor, so nothing here needs to change — but keep
    // it that way if a general auth guard is ever added.
    GoRoute(
        path: '/user-guide',
        pageBuilder: (_, s) =>
            _fadeThrough(s.pageKey, const UserGuideScreen())),
    GoRoute(
        path: '/belt-rank',
        pageBuilder: (_, s) =>
            _fadeThrough(s.pageKey, const BeltRankScreen())),
    GoRoute(
        path: '/tournament',
        pageBuilder: (_, s) =>
            _fadeThrough(s.pageKey, const TournamentScreen())),
    // Renamed from Competition; older links and guide entries still land here.
    GoRoute(path: '/competition', redirect: (_, __) => '/tournament'),
    GoRoute(
        path: '/notifications',
        pageBuilder: (_, s) =>
            _fadeThrough(s.pageKey, const NotificationsScreen())),
    GoRoute(
        path: '/offers',
        pageBuilder: (_, s) => _fadeThrough(s.pageKey, const OffersScreen())),
    // Keyed by offer code: every myoffers row has id 0, so the code is the only identity.
    GoRoute(
      path: '/offer/:code',
      pageBuilder: (_, state) => _fadeThrough(
        state.pageKey,
        OfferDetailScreen(code: state.pathParameters['code'] ?? ''),
      ),
    ),
    GoRoute(
        path: '/notification-settings',
        pageBuilder: (_, s) =>
            _fadeThrough(s.pageKey, const NotificationSettingsScreen())),
    ...developerRoutes(),
    GoRoute(
        path: '/attendance',
        pageBuilder: (_, s) =>
            _fadeThrough(s.pageKey, const AttendanceScreen())),
    GoRoute(
        path: '/events',
        pageBuilder: (_, s) => _fadeThrough(
            s.pageKey,
            EventsScreen(
                initialTab: s.uri.queryParameters['tab'] ?? 'events'))),
    // Was NotificationDetailScreen, which rendered GET /Profile/NotificationDetails —
    // a route that is NOT scoped to the caller and returned other members' rows. The
    // conversation is now built from the member's own MyNotifications rows.
    GoRoute(
      path: '/notification/:groupId',
      pageBuilder: (_, state) => _fadeThrough(
        state.pageKey,
        ChatThreadScreen(
          threadKey: state.pathParameters['groupId'] ?? '',
          title: state.uri.queryParameters['t'] ?? 'Conversation',
          replyable: state.uri.queryParameters['ro'] != '1',
        ),
      ),
    ),
    GoRoute(
      path: '/qr-scan',
      pageBuilder: (_, state) => MaterialPage(
        key: state.pageKey,
        fullscreenDialog: true,
        child: const QRScanScreen(),
      ),
    ),
  ],
);
