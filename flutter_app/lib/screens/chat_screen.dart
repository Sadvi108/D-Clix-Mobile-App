import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/chat_store.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../widgets/rn_kit.dart';

/// RN `fmtWhen`: now / 5m / 3h / "02 Sep".
String chatWhen(DateTime? d) {
  if (d == null) return '';
  final mins = (DateTime.now().difference(d).inSeconds / 60).round();
  if (mins < 1) return 'now';
  if (mins < 60) return '${mins}m';
  if (mins < 1440) return '${mins ~/ 60}h';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day.toString().padLeft(2, '0')} ${m[d.month - 1]}';
}

/// Port of `frontend/app/chat.tsx` (Expo v2.11.1).
///
/// Conversations = notification groups (server truth) merged with locally-sent messages.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  Map<String, List<SentMessage>> _sent = const {};
  int _revision = -1;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await UserSession.instance.refreshNotifications();
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _loadSent(UserSession session) async {
    final userId = session.authenticatedUserId ?? 0;
    _revision = session.notificationsRevision;
    final sent = await ChatStore.threads(userId);
    if (mounted && userId == (session.authenticatedUserId ?? 0)) setState(() => _sent = sent);
  }

  Future<void> _open(String key, String title, bool replyable) async {
    await context.push(
        '/notification/${Uri.encodeComponent(key)}?t=${Uri.encodeQueryComponent(title)}${replyable ? '' : '&ro=1'}');
    // MyNotifications cannot contain messages sent by the student. Reload the
    // local echo when the thread closes so the Chat Academy list immediately
    // reflects the new preview even when the server inbox did not change.
    if (mounted) await _loadSent(UserSession.instance);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: UserSession.instance, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final c = context.appColors;
    final session = UserSession.instance;
    if (_revision != session.notificationsRevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSent(session));
    }
    final items = session.notifications;
    final loading = items == null || _refreshing;
    final threads = buildThreadList(myNotifications: items ?? const [], sentByThread: _sent);
    final helpdeskLast = (_sent[ChatStore.helpdeskThread] ?? const []).lastOrNull;
    final clubName = '${session.authData?['clubName'] ?? ''}'.trim();

    Widget row({
      required Widget avatar,
      required String title,
      required String preview,
      required String when,
      int unread = 0,
      Widget? trailing,
      bool pinned = false,
      required VoidCallback onTap,
    }) =>
        Touchable(
          activeOpacity: 0.85,
          onPress: onTap,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: pinned
                ? BoxDecoration(
                    color: c.isDark ? c.surfaceAlt : const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(Radii.lg),
                    boxShadow: Shadows.soft(c),
                    border: Border.all(color: c.primary.hexA('44')),
                  )
                : rnCard(c),
            child: Row(children: [
              avatar,
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w700,
                              color: c.textPrimary)),
                    ),
                    const SizedBox(width: 8),
                    Text(when, style: TextStyle(fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 3),
                  Text(preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: unread > 0 ? c.textPrimary : c.textSecondary,
                          fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400)),
                ]),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing],
            ]),
          ),
        );

    return Scaffold(
      backgroundColor: c.background,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const RnHeader(title: 'Chat Academy', horizontal: Gaps.lg),
        Expanded(
          child: RefreshIndicator(
            color: c.primary,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.xl, Gaps.xl, 60),
              children: [
                // Pinned: talk to the club (starts a new helpdesk conversation)
                row(
                  pinned: true,
                  avatar: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                    child: const Icon(Ion.headset, size: 20, color: Colors.white),
                  ),
                  title: '${clubName.isEmpty ? 'Club' : clubName} · Help Desk',
                  preview: helpdeskLast != null ? 'You: ${helpdeskLast.text}' : 'Message your club admin / instructor',
                  when: helpdeskLast == null ? '' : chatWhen(helpdeskLast.at),
                  trailing: Icon(Ion.chevronForward, size: 16, color: c.textMuted),
                  onTap: () => _open(ChatStore.helpdeskThread, 'Club Help Desk', true),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 18, bottom: 10),
                  child: Text('CONVERSATIONS',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: c.textMuted)),
                ),
                if (loading && (items ?? const []).isEmpty)
                  const SkeletonList(rows: 5, lines: 2, padding: EdgeInsets.only(top: 4)),
                if (session.notificationsError != null && (items ?? const []).isEmpty)
                  ErrorState(message: session.notificationsError, onRetry: _refresh),
                if (!loading && threads.isEmpty && session.notificationsError == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 50),
                    child: Column(children: [
                      Icon(Ion.chatbubblesOutline, size: 44, color: c.textMuted),
                      const SizedBox(height: 14),
                      Text('No conversations yet',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
                      const SizedBox(height: 6),
                      Text('Messages from your club appear here.',
                          style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
                    ]),
                  ),
                for (final t in threads)
                  row(
                    avatar: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
                      child: Icon(Ion.chatbubbleEllipsesOutline, size: 19, color: c.primary),
                    ),
                    title: t.title,
                    preview: t.preview.isEmpty ? '…' : t.preview,
                    when: chatWhen(t.at),
                    unread: t.unread,
                    trailing: t.unread > 0
                        ? Container(
                            constraints: const BoxConstraints(minWidth: 20),
                            height: 20,
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(10)),
                            child: Text('${t.unread}',
                                style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                          )
                        : null,
                    onTap: () => _open(t.key, t.title, t.replyable),
                  ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
