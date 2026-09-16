import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/response_utils.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../theme/theme_provider.dart';
import '../widgets/rn_kit.dart';

/// Port of `frontend/app/login.tsx` (Expo v2.11.1).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _Focus { id, pwd, club }

class _LoginScreenState extends State<LoginScreen> {
  final _idCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _clubCtrl = TextEditingController();
  final _idNode = FocusNode();
  final _pwdNode = FocusNode();
  final _clubNode = FocusNode();

  bool _showPwd = false;
  bool _instructor = false;
  _Focus? _focus;

  // Instructor-only
  Map<String, dynamic>? _branch;
  final _branchState = ValueNotifier<_BranchLoad>((loading: false, branches: const []));
  int _branchRequest = 0;

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    void track(FocusNode n, _Focus f) => n.addListener(() {
          if (!mounted) return;
          setState(() => _focus = n.hasFocus ? f : (_focus == f ? null : _focus));
        });
    track(_idNode, _Focus.id);
    track(_pwdNode, _Focus.pwd);
    track(_clubNode, _Focus.club);
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _pwdCtrl.dispose();
    _clubCtrl.dispose();
    _idNode.dispose();
    _pwdNode.dispose();
    _clubNode.dispose();
    _branchState.dispose();
    super.dispose();
  }

  void _switchMode(bool instructor) => setState(() {
        _instructor = instructor;
        _error = null;
      });

  Future<void> _openBranchPicker() async {
    final code = _clubCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter your club code first.');
      return;
    }
    FocusScope.of(context).unfocus();
    final request = ++_branchRequest;
    setState(() => _error = null);
    _branchState.value = (loading: true, branches: const []);
    final sheet = _showBranchSheet();
    try {
      final response = await Api.accountGetBranchesByClubCode(code);
      final error = apiEnvelopeError(response);
      if (error != null) throw Exception(error);
      if (!mounted || request != _branchRequest) return;
      _branchState.value = (
        loading: false,
        branches: findRecordList(response)
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList(),
      );
    } catch (e) {
      if (!mounted || request != _branchRequest) return;
      setState(() => _error = friendlyError(e).isEmpty
          ? 'Could not load branches.'
          : friendlyError(e));
      Navigator.of(context).maybePop();
    } finally {
      if (mounted && request == _branchRequest && _branchState.value.loading) {
        _branchState.value = (loading: false, branches: _branchState.value.branches);
      }
    }
    await sheet;
  }

  Future<void> _onLogin() async {
    if (_busy) return;
    setState(() => _error = null);
    FocusScope.of(context).unfocus();
    final id = _idCtrl.text.trim();
    final pwd = _pwdCtrl.text;
    if (id.isEmpty || pwd.isEmpty) {
      setState(() => _error = 'Please enter your ID and password.');
      return;
    }
    if (_instructor && (_clubCtrl.text.trim().isEmpty || _branch == null)) {
      setState(() => _error = 'Club code and branch are required for instructors.');
      return;
    }
    setState(() => _busy = true);
    final ok = await UserSession.instance.login(
      username: id,
      password: pwd,
      userType: _instructor ? 0 : 3,
      clubCode: _instructor ? _clubCtrl.text.trim() : null,
      branchId: _instructor ? (_branch!['id'] as num?)?.toInt() : null,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      context.go(UserSession.instance.isInstructor ? '/instructor/home' : '/home');
    } else {
      // UserSession.error is already user-facing text (see friendlyError).
      final msg = UserSession.instance.error ?? '';
      setState(() => _error = msg.isEmpty ? 'Login failed. Check your credentials.' : msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final theme = context.watch<ThemeProvider>();
    final insets = MediaQuery.paddingOf(context);

    Widget chip(String label, IconData icon, bool active, VoidCallback onTap) => Expanded(
          child: Touchable(
            onPress: onTap,
            activeOpacity: 0.85,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                gradient: active ? LinearGradient(colors: c.gradient) : null,
                color: active ? null : c.surfaceAlt,
                borderRadius: BorderRadius.circular(Radii.md),
                border: active ? null : Border.all(color: c.border),
                boxShadow: active ? Shadows.strong(c) : null,
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 15, color: active ? Colors.white : c.textSecondary),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        color: active ? Colors.white : c.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ]),
            ),
          ),
        );

    return Scaffold(
      backgroundColor: c.background,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(fit: StackFit.expand, children: [
          Positioned(
            top: -130,
            right: -80,
            child: _blob(280, c.primary.withValues(alpha: c.isDark ? .22 : .18)),
          ),
          Positioned(
            bottom: -80,
            left: -60,
            child: _blob(220, c.primaryLight.withValues(alpha: c.isDark ? .18 : .16)),
          ),
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(Gaps.xl, Gaps.xl, Gaps.xl, 24 + insets.bottom),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Top row: logo + theme toggle
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(kLogoAssetPath, width: 38, height: 38),
                    ),
                    const SizedBox(width: 10),
                    Text('D-CLIX',
                        style: TextStyle(
                            color: c.textPrimary,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3,
                            fontSize: 14)),
                    const Spacer(),
                    Touchable(
                      onPress: theme.toggle,
                      child: Container(
                        width: 32,
                        height: 32,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                            color: c.surfaceAlt, borderRadius: BorderRadius.circular(10)),
                        child: Icon(theme.isDark ? Ion.sunny : Ion.moon,
                            size: 16, color: c.primary),
                      ),
                    ),
                    Touchable(
                      onPress: () => context.push('/user-guide'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: c.surfaceAlt, borderRadius: BorderRadius.circular(14)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Ion.helpCircleOutline, size: 14, color: c.textSecondary),
                          const SizedBox(width: 4),
                          Text('Help',
                              style: TextStyle(
                                  color: c.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ]),
                ),

                const SizedBox(height: 28),
                Text('WELCOME BACK',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: c.primary,
                        letterSpacing: 2.5)),
                const SizedBox(height: 10),
                Text("Let's get you\nback on the mat.",
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                        letterSpacing: -0.8,
                        height: 38 / 32)),
                const SizedBox(height: 10),
                Text('Sign in to continue your training journey',
                    style: TextStyle(
                        color: c.textSecondary, fontSize: 14, fontWeight: FontWeight.w500)),

                const SizedBox(height: 28),
                Row(children: [
                  chip('Student', Ion.school, !_instructor, () => _switchMode(false)),
                  const SizedBox(width: 10),
                  chip('Instructor', Ion.ribbon, _instructor, () => _switchMode(true)),
                ]),

                // Instructor: club code + branch
                if (_instructor) ...[
                  _fieldGroup(
                    c,
                    label: 'Club code',
                    child: _inputLine(
                      c,
                      focused: _focus == _Focus.club,
                      icon: Ion.business,
                      field: _textInput(
                        c,
                        controller: _clubCtrl,
                        node: _clubNode,
                        hint: 'e.g. RTT',
                        caps: TextCapitalization.characters,
                        onChanged: (_) => setState(() {
                          _branch = null;
                          _branchRequest++;
                        }),
                      ),
                    ),
                  ),
                  _fieldGroup(
                    c,
                    label: 'Branch',
                    child: Touchable(
                      onPress: _openBranchPicker,
                      activeOpacity: 0.7,
                      child: _inputLine(
                        c,
                        focused: false,
                        icon: Ion.gitBranch,
                        iconColor: _branch != null ? c.primary : c.textMuted,
                        field: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            _branch != null ? '${_branch!['text'] ?? ''}' : 'Select branch',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: _branch != null ? c.textPrimary : c.textMuted),
                          ),
                        ),
                        trailing: Icon(Ion.chevronDown, size: 18, color: c.textSecondary),
                      ),
                    ),
                  ),
                ],

                _fieldGroup(
                  c,
                  label: _instructor ? 'Instructor ID' : 'Student ID, phone or email',
                  child: _inputLine(
                    c,
                    focused: _focus == _Focus.id,
                    icon: Ion.at,
                    field: _textInput(
                      c,
                      controller: _idCtrl,
                      node: _idNode,
                      hint: _instructor ? 'Instructor ID' : 'Student ID, phone or email',
                      action: TextInputAction.next,
                      onSubmitted: (_) => _pwdNode.requestFocus(),
                    ),
                  ),
                ),

                _fieldGroup(
                  c,
                  label: 'Password',
                  labelTrailing: Touchable(
                    onPress: () => notify(context, 'Forgot password',
                        "Password resets are handled by your academy — please contact them and they'll reset it for you."),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('Forgot?',
                          style: TextStyle(
                              color: c.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  child: _inputLine(
                    c,
                    focused: _focus == _Focus.pwd,
                    icon: Ion.lockClosed,
                    field: _textInput(
                      c,
                      controller: _pwdCtrl,
                      node: _pwdNode,
                      hint: 'Enter password',
                      obscure: !_showPwd,
                      action: TextInputAction.go,
                      onSubmitted: (_) => _onLogin(),
                    ),
                    trailing: Touchable(
                      onPress: () => setState(() => _showPwd = !_showPwd),
                      child: Semantics(
                        button: true,
                        label: _showPwd ? 'Hide password' : 'Show password',
                        child: Icon(_showPwd ? Ion.eyeOffOutline : Ion.eyeOutline,
                            size: 18, color: c.textSecondary),
                      ),
                    ),
                  ),
                ),

                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(top: 18),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                        color: c.danger.hexA('1A'),
                        borderRadius: BorderRadius.circular(Radii.md)),
                    child: Row(children: [
                      Icon(Ion.alertCircle, size: 16, color: c.danger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: TextStyle(
                                color: c.danger, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),

                // The session is always persisted, so this is stated as fact, not a checkbox.
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Row(children: [
                    Icon(Ion.informationCircleOutline, size: 14, color: c.textSecondary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text("You'll stay signed in on this device",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),

                const SizedBox(height: 24),
                Touchable(
                  onPress: _busy ? null : _onLogin,
                  activeOpacity: 0.92,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 56),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: c.gradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(Radii.lg),
                      boxShadow: Shadows.strong(c),
                    ),
                    child: _busy
                        ? const Center(
                            child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4, color: Colors.white)))
                        : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Text('Sign In',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    letterSpacing: 0.5)),
                            const SizedBox(width: 10),
                            Container(
                              width: 26,
                              height: 26,
                              decoration: const BoxDecoration(
                                  color: Colors.white, shape: BoxShape.circle),
                              child: Icon(Ion.arrowForward, size: 14, color: c.primary),
                            ),
                          ]),
                  ),
                ),

                // Step-by-step app walkthrough — reachable before signing in
                const SizedBox(height: 24),
                Touchable(
                  onPress: () => context.push('/user-guide'),
                  activeOpacity: 0.8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(color: c.primary.hexA('55'), width: 1.5),
                      color: c.primary.hexA('12'),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Ion.bookOutline, size: 18, color: c.primary),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text('User Guide — how the app works',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: c.primary, fontWeight: FontWeight.w800, fontSize: 13.5)),
                      ),
                      const SizedBox(width: 8),
                      Icon(Ion.chevronForward, size: 16, color: c.primary),
                    ]),
                  ),
                ),

                const SizedBox(height: 20),
                Text.rich(
                  TextSpan(
                    text: 'New to D-Clix? ',
                    style: TextStyle(color: c.textSecondary, fontSize: 13),
                    children: [
                      TextSpan(
                          text: 'Contact your academy',
                          style: TextStyle(color: c.primary, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _blob(double size, Color color) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      );

  Widget _fieldGroup(AppColors c,
      {required String label, Widget? labelTrailing, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: c.textSecondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3)),
            ),
          ),
          if (labelTrailing != null) labelTrailing,
        ]),
        child,
      ]),
    );
  }

  Widget _inputLine(AppColors c,
      {required bool focused,
      required IconData icon,
      Color? iconColor,
      required Widget field,
      Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: focused ? c.primary : c.border, width: 1.5)),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: iconColor ?? (focused ? c.primary : c.textMuted)),
        const SizedBox(width: 12),
        Expanded(child: field),
        if (trailing != null) ...[const SizedBox(width: 12), trailing],
      ]),
    );
  }

  Widget _textInput(AppColors c,
      {required TextEditingController controller,
      required FocusNode node,
      required String hint,
      bool obscure = false,
      TextCapitalization caps = TextCapitalization.none,
      TextInputAction? action,
      ValueChanged<String>? onChanged,
      ValueChanged<String>? onSubmitted}) {
    return TextField(
      controller: controller,
      focusNode: node,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: !obscure,
      textCapitalization: caps,
      textInputAction: action,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      cursorColor: c.primary,
      style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        isDense: true,
        filled: false,
        contentPadding: const EdgeInsets.symmetric(vertical: 4),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        hintText: hint,
        hintStyle: TextStyle(color: c.textMuted, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<void> _showBranchSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: context.appColors.overlay,
      builder: (ctx) => _BranchSheet(
        state: _branchState,
        selectedId: (_branch?['id'] as num?)?.toInt(),
        onPick: (b) {
          setState(() => _branch = b);
          Navigator.pop(ctx);
        },
      ),
    );
  }
}

/// What the branch sheet renders: still loading, or the branches for the club code.
typedef _BranchLoad = ({bool loading, List<Map<String, dynamic>> branches});

class _BranchSheet extends StatelessWidget {
  final ValueListenable<_BranchLoad> state;
  final int? selectedId;
  final ValueChanged<Map<String, dynamic>> onPick;
  const _BranchSheet({required this.state, required this.selectedId, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final insets = MediaQuery.paddingOf(context);
    return ValueListenableBuilder<_BranchLoad>(
      valueListenable: state,
      builder: (context, load, _) {
        final branches = load.branches;
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
          padding: EdgeInsets.fromLTRB(Gaps.xl, 12, Gaps.xl, 16 + insets.bottom),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xxl)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                      color: c.border, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Select branch',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800, color: c.textPrimary)),
              ),
              if (load.loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                      child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: c.primary))),
                )
              else if (branches.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text('No branches found for this club code.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textSecondary, fontSize: 14)),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: branches.length,
                    itemBuilder: (_, i) {
                      final b = branches[i];
                      final selected = (b['id'] as num?)?.toInt() == selectedId;
                      return Touchable(
                        onPress: () => onPick(b),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: c.border))),
                          child: Row(children: [
                            Icon(selected ? Ion.radioButtonOn : Ion.radioButtonOff,
                                size: 20, color: selected ? c.primary : c.textMuted),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text('${b['text'] ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: c.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
