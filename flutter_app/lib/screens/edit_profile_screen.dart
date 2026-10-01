import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/response_utils.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../widgets/rn_kit.dart';

int _intOf(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

/// Accept international phone numbers with common display separators.
String? validateProfilePhone(String raw) {
  final value = raw.trim();
  // Some legacy records have no phone. Keep that optional, but reject a
  // malformed value once one is entered.
  if (value.isEmpty) return null;
  if (!RegExp(r'^\+?[0-9 ()-]+$').hasMatch(value) || value.substring(1).contains('+')) {
    return 'Use digits with an optional +, spaces, dashes or parentheses.';
  }
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 7 || digits.length > 15) {
    return 'Enter a valid mobile number with 7 to 15 digits.';
  }
  return null;
}

String normalizeProfilePhone(String raw) {
  final value = raw.trim();
  final digits = value.replaceAll(RegExp(r'\D'), '');
  return value.startsWith('+') ? '+$digits' : digits;
}

/// Port of `frontend/app/edit-profile.tsx` (Expo v2.11.1).
///
/// Writes through `/Profile/UpdateProfile` (multipart), which expects the identity fields
/// (Id, UserId, IcNo, BranchId, ClubId) echoed back alongside the edits.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _ic = TextEditingController();
  final _address = TextEditingController();
  final _postal = TextEditingController();
  // The rest of the old app's profile form (`ProfileDataAccess.cs:80-110`).
  // These were previously not sent at all, so every save risked blanking them
  // server-side, and there was no way to change a password in the app at all.
  // Parity review F11.
  final _school = TextEditingController();
  final _className = TextEditingController();
  final _tshirt = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _blood = TextEditingController();
  final _food = TextEditingController();
  final _health = TextEditingController();
  final _newPwd = TextEditingController();
  final _confirmPwd = TextEditingController();
  DateTime? _dob;
  String _gender = '';
  /// `/Profile/StudentAddtnlInfo` — the old form loaded this before letting
  /// anyone edit, because UpdateProfile takes the whole profile.
  ///
  /// Three outcomes, and they are NOT the same thing:
  ///  * loaded — the extras are known, so they are all sent, including ones the
  ///    member deliberately cleared (the server has no other way to clear them);
  ///  * failed / not a usable reply — the extras are unknown, so every one of
  ///    them is left out of the multipart rather than sent blank;
  ///  * instructor — the endpoint is student-only, so there are no extras to
  ///    send at all (same scoping as the session refresh).
  /// Parity review F11.
  bool _extrasLoading = true;
  bool _extrasLoaded = false;
  String? _extrasError;

  /// Who this form was opened for, and the session it belongs to.
  ///
  /// `authData` is live: a form left open while the account switches would post
  /// the old form's edits — with an explicit `Id` — into whoever is signed in
  /// now. Every save and every late reply is checked against this first.
  /// Parity review F11.
  /// Both captured in `initState`, NOT lazily: a `late final` read for the
  /// first time after the account already changed would snapshot the new
  /// account and wave the stale form straight through.
  late final int _openedForId;
  late final int _openedEpoch;
  bool get _sameAccount =>
      UserSession.instance.sessionEpoch == _openedEpoch &&
      _intOf(UserSession.instance.authData?['id']) == _openedForId;
  /// StandardMaster (`/Listing/DropdownListByType/5`), the old
  /// `StandardSelection` picker.
  List<Map<String, dynamic>> _standards = const [];
  int? _standardId;
  XFile? _picked;
  Uint8List? _pickedBytes;
  bool _saving = false;
  String? _phoneError;

  Map<String, dynamic> get _user => UserSession.instance.authData ?? const <String, dynamic>{};
  String _u(String k) => '${_user[k] ?? ''}'.trim();

  @override
  void initState() {
    super.initState();
    _openedForId = _intOf(UserSession.instance.authData?['id']);
    _openedEpoch = UserSession.instance.sessionEpoch;
    _name.text = _u('name');
    _email.text = _u('emailAddress');
    _phone.text = _u('handPhone');
    _ic.text = _u('icNo');
    _gender = _u('gender');
    _address.text = _u('address1');
    _postal.text = _u('postalCode');
    _school.text = _u('schoolname');
    _className.text = _u('className');
    _tshirt.text = _u('tshirtSize');
    _height.text = _u('height');
    _weight.text = _u('weight');
    _blood.text = _u('bloodtype');
    _food.text = _u('foodtype');
    _health.text = _u('healthstatus');
    _dob = DateTime.tryParse(_u('dob'));
    _name.addListener(() => setState(() {}));
    _loadExtras();
  }

  /// Seed the extended fields from the server's own copy, falling back to
  /// whatever the session already holds.
  Future<void> _loadExtras() async {
    // Student-only endpoint, exactly as the session refresh scopes it.
    if (UserSession.instance.isInstructor) {
      setState(() {
        _extrasLoading = false;
        _extrasLoaded = false;
        _extrasError = null;
      });
      return;
    }
    setState(() {
      _extrasLoading = true;
      _extrasLoaded = false;
      _extrasError = null;
    });
    void fail(String why) {
      if (mounted && _sameAccount) {
        setState(() {
          _extrasError = why;
          _extrasLoaded = false;
          _extrasLoading = false;
        });
      }
    }

    try {
      final res = await Api.profileStudentAddtnlInfo();
      // A late reply belongs to the account it was asked for, not to whoever is
      // signed in by the time it lands.
      if (!mounted || !_sameAccount) return;
      final data = unwrapData(res);
      if (data is! Map) {
        // Not a usable reply. "No extras came back" is not "this member has
        // none": sending blanks on that basis is what wipes real values.
        fail("Your school, class, size and health details didn't come back from your academy.");
        return;
      }
      final extra = <String, dynamic>{
        ...?UserSession.instance.studentAddtnlInfo,
        ...Map<String, dynamic>.from(data),
      };
      UserSession.instance.studentAddtnlInfo = extra;
      String pick(String key) => '${extra[key] ?? _user[key] ?? ''}'.trim();
      setState(() {
        _school.text = pick('schoolname');
        _className.text = pick('className');
        _tshirt.text = pick('tshirtSize');
        _height.text = pick('height');
        _weight.text = pick('weight');
        _blood.text = pick('bloodtype');
        _food.text = pick('foodtype');
        _health.text = pick('healthstatus');
        _standardId = int.tryParse(pick('standardId'));
        final dob = DateTime.tryParse(pick('dob'));
        if (dob != null) _dob = dob;
        _extrasLoaded = true;
        _extrasLoading = false;
      });
    } catch (e) {
      fail(friendlyError(e));
      return;
    }
    // The standards list is a convenience, not a gate: without it the member's
    // current standard is still echoed back untouched.
    try {
      final rows = unwrapData(await Api.listingDropdownListByType(5));
      if (rows is List && mounted && _sameAccount) {
        setState(() => _standards =
            rows.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList());
      }
    } catch (_) {
      /* keep the plain echo */
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name, _email, _phone, _ic, _address, _postal,
      _school, _className, _tshirt, _height, _weight, _blood, _food, _health,
      _newPwd, _confirmPwd,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _openPicker() async {
    final c = context.appColors;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: c.overlay,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(Gaps.xl, 12, Gaps.xl, 24 + MediaQuery.paddingOf(ctx).bottom),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xxl)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 44,
            height: 5,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(3)),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            for (final o in const [
              (label: 'Gallery', icon: Ion.images, color: Color(0xFFFB7185), source: ImageSource.gallery),
              (label: 'Camera', icon: Ion.camera, color: Color(0xFF34D399), source: ImageSource.camera),
            ])
              Touchable(
                onPress: () => Navigator.pop(ctx, o.source),
                child: Column(children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(color: o.color, borderRadius: BorderRadius.circular(20)),
                    child: Icon(o.icon, size: 26, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  Text(o.label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.textPrimary)),
                ]),
              ),
          ]),
        ]),
      ),
    );
    if (source == null) return;
    try {
      final img = await ImagePicker().pickImage(source: source, imageQuality: 60, maxWidth: 1024, maxHeight: 1024);
      if (img == null) return;
      final bytes = await img.readAsBytes();
      if (mounted) {
        setState(() {
          _picked = img;
          _pickedBytes = bytes;
        });
      }
    } catch (e) {
      if (mounted) notify(context, 'Could not pick image', friendlyError(e));
    }
  }

  /// `yyyy-MM-dd`, the format the old form posted (`ProfileDataAccess.cs:97`).
  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Old `UserDetailsModel.calcBmi()`: weight / (height in m)², 2 decimals.
  String get _bmi {
    final h = double.tryParse(_height.text.trim()) ?? 0;
    final w = double.tryParse(_weight.text.trim()) ?? 0;
    if (h <= 0 || w <= 0) return '';
    final metres = h / 100;
    return '${((w / (metres * metres)) * 100).round() / 100}';
  }

  Future<void> _save() async {
    if (_user.isEmpty || _extrasLoading) return;
    // The form belongs to the account it was opened for. If that changed under
    // it, there is nothing safe to save: these edits describe someone else.
    if (!_sameAccount) {
      await notify(context, 'Signed in as someone else',
          'This form was opened for a different account. Close it and open Edit Profile again.');
      return;
    }
    final name = _name.text.trim();
    if (name.isEmpty) {
      await notify(context, 'Name required', 'Please enter your name.');
      return;
    }
    final phoneError = validateProfilePhone(_phone.text);
    if (phoneError != null) {
      setState(() => _phoneError = phoneError);
      return;
    }
    final phone = normalizeProfilePhone(_phone.text);
    final newPwd = _newPwd.text;
    if (newPwd.isNotEmpty && newPwd != _confirmPwd.text) {
      await notify(context, 'Passwords do not match', 'Type the same new password in both boxes.');
      return;
    }
    setState(() => _saving = true);
    final s = UserSession.instance;
    final fields = <String, String>{
      'Id': _u('id'),
      'UserId': _u('userId'),
      // UpdateProfile owns this field for both member and instructor records.
      'IcNo': _ic.text.trim(),
      'Name': name,
      'EmailAddress': _email.text.trim(),
      'HandPhone': phone,
      'Gender': _gender,
      'Address1': _address.text,
      'Address2': _u('address2'),
      'Address3': _u('address3'),
      'Address4': _u('address4'),
      'PostalCode': _postal.text,
      'BranchId': _u('branchId'),
      'ClubId': _u('clubId'),
    };
    // The rest of the old form, and only when the server's own copy actually
    // loaded — posting a blank for a field this screen never learnt would wipe
    // it. Once loaded, the text fields go out even when empty: that is how the
    // old form let a member clear their school or health note
    // (`ProfileDataAccess.cs:80-90`, which sends "" for these). Only the
    // numeric and date parts are conditional, as they were there (`:91-98`).
    if (_extrasLoaded) {
      fields.addAll({
        'Schoolname': _school.text.trim(),
        'ClassName': _className.text.trim(),
        'TshirtSize': _tshirt.text.trim(),
        'Bloodtype': _blood.text.trim(),
        'Foodtype': _food.text.trim(),
        'Healthstatus': _health.text.trim(),
      });
      for (final e in {
        'Dob': _dob == null ? '' : _ymd(_dob!),
        'Height': _height.text.trim(),
        'Weight': _weight.text.trim(),
        'Bmi': _bmi,
        'StandardId': _standardId?.toString() ?? '',
      }.entries) {
        if (e.value.isNotEmpty) fields[e.key] = e.value;
      }
    }
    // Only sent when the member actually typed one; the server treats an absent
    // NewPassword as "unchanged" (`ProfileDataAccess.cs:108`).
    if (newPwd.isNotEmpty) fields['NewPassword'] = newPwd;
    // Web has no file path for a multipart part, so the photo also rides as base64
    // `ProfilePic`; the server ignores whichever field it does not bind.
    final photoB64 = _pickedBytes == null ? null : base64Encode(_pickedBytes!);
    if (photoB64 != null) fields['ProfilePic'] = photoB64;
    try {
      final res = await Api.profileUpdateProfile(fields,
          photoPath: !kIsWeb && _picked != null ? _picked!.path : null);
      // The save landed, but the session may have moved on while it was in
      // flight. Never write this form's values into a different account.
      if (!_sameAccount) return;
      final dpUrl = unwrapData(res);
      await s.updateUser({
        'name': name,
        'emailAddress': _email.text.trim(),
        'handPhone': phone,
        'icNo': _ic.text.trim(),
        'gender': _gender,
        'address1': _address.text,
        'postalCode': _postal.text,
        // NOTE: the new password is deliberately absent here — it is sent to
        // the server and then forgotten, never written to the session or to
        // preferences.
        if (_extrasLoaded) ...{
          'schoolname': _school.text.trim(),
          'className': _className.text.trim(),
          'tshirtSize': _tshirt.text.trim(),
          'bloodtype': _blood.text.trim(),
          'foodtype': _food.text.trim(),
          'healthstatus': _health.text.trim(),
          if (_dob != null) 'dob': _ymd(_dob!),
          if (_height.text.trim().isNotEmpty) 'height': _height.text.trim(),
          if (_weight.text.trim().isNotEmpty) 'weight': _weight.text.trim(),
          if (_bmi.isNotEmpty) 'bmi': _bmi,
          if (_standardId != null) 'standardId': _standardId,
        },
        if (dpUrl is String && dpUrl.trim().isNotEmpty) 'profilePic': dpUrl.trim(),
      });
      if (photoB64 != null && _sameAccount) await s.setLocalPhoto(photoB64);
      if (!mounted) return;
      // A password is never kept in the form after it has been accepted.
      _newPwd.clear();
      _confirmPwd.clear();
      setState(() => _saving = false);
      await notify(context, 'Saved',
          newPwd.isEmpty ? 'Your profile has been updated.' : 'Your profile and password have been updated.');
      if (mounted) safeBack(context);
    } catch (e) {
      // Keep the picked photo on this device even when the save failed — but
      // only while it is still this member's device session.
      if (photoB64 != null && _sameAccount) await s.setLocalPhoto(photoB64);
      if (!mounted) return;
      setState(() => _saving = false);
      notify(context, 'Update failed', friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final session = context.watch<UserSession>();
    final avatarUrl = session.studentPhoto;

    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.textSecondary)),
        );

    Widget field(String l, TextEditingController ctrl, IconData icon,
        {TextInputType? keyboard, bool multiline = false, bool obscure = false,
        String? error, ValueChanged<String>? onChanged}) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        label(l),
        Container(
          margin: EdgeInsets.only(bottom: error == null ? 14 : 5),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: error == null ? c.border : c.danger),
          ),
          child: Row(crossAxisAlignment: multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: [
            Padding(
              padding: EdgeInsets.only(top: multiline ? 12 : 0),
              child: Icon(icon, size: 18, color: c.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: multiline ? 70 : null,
                child: TextField(
                  controller: ctrl,
                  onChanged: onChanged,
                  obscureText: obscure,
                  autocorrect: !obscure,
                  enableSuggestions: !obscure,
                  keyboardType: multiline ? TextInputType.multiline : keyboard,
                  maxLines: multiline ? null : 1,
                  expands: multiline,
                  textAlignVertical: multiline ? TextAlignVertical.top : null,
                  textCapitalization: keyboard == TextInputType.emailAddress || obscure
                      ? TextCapitalization.none
                      : TextCapitalization.sentences,
                  cursorColor: c.primary,
                  style: TextStyle(color: c.textPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    hintText: l,
                    hintStyle: TextStyle(color: c.textMuted, fontSize: 15),
                  ),
                ),
              ),
            ),
          ]),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 14),
            child: Text(error, style: TextStyle(fontSize: 12, color: c.danger, fontWeight: FontWeight.w600)),
          ),
      ]);
    }

    Widget readRow(String l, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Text(l, maxLines: 1, style: TextStyle(fontSize: 13, color: c.textSecondary)),
            const SizedBox(width: Gaps.md),
            Expanded(
              child: Text(v.isEmpty ? '—' : v,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13, color: c.textPrimary, fontWeight: FontWeight.w600)),
            ),
          ]),
        );

    Widget avatar;
    if (_pickedBytes != null) {
      avatar = Image.memory(_pickedBytes!, width: 110, height: 110, fit: BoxFit.cover);
    } else if (avatarUrl.isNotEmpty || session.localPhotoB64.isNotEmpty) {
      Widget initials() => Center(
            child: Text(initialsOf(_name.text),
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: c.primary)),
          );
      avatar = session.localPhotoB64.isNotEmpty
          ? Image.memory(base64Decode(session.localPhotoB64),
              width: 110, height: 110, fit: BoxFit.cover, errorBuilder: (_, __, ___) => initials())
          : CachedNetworkImage(
              imageUrl: avatarUrl, width: 110, height: 110, fit: BoxFit.cover, errorWidget: (_, __, ___) => initials());
    } else {
      avatar = Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.border, width: 2)),
        alignment: Alignment.center,
        child: Text(initialsOf(_name.text),
            style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: c.primary)),
      );
    }

    return Scaffold(
      backgroundColor: c.background,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const RnHeader(title: 'Edit Profile'),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.xl, Gaps.xl, 60),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(children: [
                  Touchable(
                    onPress: _openPicker,
                    activeOpacity: 0.85,
                    child: SizedBox(
                      width: 110,
                      height: 110,
                      child: Stack(children: [
                        Container(
                          width: 110,
                          height: 110,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
                          child: avatar,
                        ),
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: c.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: c.background, width: 3),
                            ),
                            child: const Icon(Ion.camera, size: 16, color: Colors.white),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('Tap to change photo',
                      style: TextStyle(fontSize: 12, color: c.textSecondary, fontWeight: FontWeight.w600)),
                ]),
              ),
              field('Name', _name, Ion.personOutline),
              field('Email', _email, Ion.mailOutline, keyboard: TextInputType.emailAddress),
              field('Mobile No', _phone, Ion.callOutline,
                  keyboard: TextInputType.phone,
                  error: _phoneError,
                  onChanged: (_) {
                    if (_phoneError != null) setState(() => _phoneError = validateProfilePhone(_phone.text));
                  }),
              field('IC No', _ic, Ion.idCardOutline),
              label('Gender'),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(children: [
                  for (final g in const ['Male', 'Female']) ...[
                    if (g == 'Female') const SizedBox(width: 12),
                    Expanded(
                      child: Touchable(
                        onPress: () => setState(() => _gender = g),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _gender == g ? c.primary : c.surface,
                            borderRadius: BorderRadius.circular(Radii.md),
                            border: Border.all(color: _gender == g ? c.primary : c.border),
                          ),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(g == 'Male' ? Ion.male : Ion.female,
                                size: 16, color: _gender == g ? Colors.white : c.primary),
                            const SizedBox(width: 8),
                            Text(g,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: _gender == g ? Colors.white : c.textPrimary)),
                          ]),
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
              field('Address', _address, Ion.locationOutline, multiline: true),
              field('Postal Code', _postal, Ion.mapOutline, keyboard: TextInputType.number),
              // The rest of the old app's profile form. Parity review F11.
              label('Date of Birth'),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Touchable(
                  onPress: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _dob ?? DateTime(now.year - 12, now.month, now.day),
                      firstDate: DateTime(now.year - 100),
                      lastDate: now,
                    );
                    if (picked != null) setState(() => _dob = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(children: [
                      Icon(Ion.calendarOutline, size: 18, color: c.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_dob == null ? 'Not set' : fmtDateGB(_ymd(_dob!)),
                            style: TextStyle(
                                fontSize: 15, color: _dob == null ? c.textMuted : c.textPrimary)),
                      ),
                      Icon(Ion.chevronForward, size: 16, color: c.textMuted),
                    ]),
                  ),
                ),
              ),
              if (_extrasLoading)
                const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: RnSpinner())
              else if (_extrasError != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.danger.hexA('14'),
                    borderRadius: BorderRadius.circular(Radii.md),
                    border: Border.all(color: c.danger.hexA('55')),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("Your school, class, size and health details couldn't be loaded, so they are left untouched by this save.",
                        style: TextStyle(fontSize: 13, color: c.textPrimary, height: 18 / 13)),
                    const SizedBox(height: 10),
                    Touchable(
                      onPress: _loadExtras,
                      child: Text('Try again',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c.primary)),
                    ),
                  ]),
                ),
              if (_extrasLoaded) ...[
              field('School', _school, Ion.schoolOutline),
              field('Class', _className, Ion.bookOutline),
              field('T-shirt Size', _tshirt, Ion.shirtOutline),
              Row(children: [
                Expanded(child: field('Height (cm)', _height, Ion.resizeOutline, keyboard: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: field('Weight (kg)', _weight, Ion.fitnessOutline, keyboard: TextInputType.number)),
              ]),
              field('Blood Type', _blood, Ion.waterOutline),
              field('Food Type', _food, Ion.restaurantOutline),
              field('Health Status', _health, Ion.heartOutline, multiline: true),
              if (_standards.isNotEmpty) ...[
                label('Standard'),
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(color: c.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _standards.any((r) => _intOf(r['id']) == _standardId) ? _standardId : null,
                        isExpanded: true,
                        hint: Text('Select', style: TextStyle(fontSize: 15, color: c.textMuted)),
                        dropdownColor: c.surface,
                        style: TextStyle(fontSize: 15, color: c.textPrimary),
                        items: [
                          for (final r in _standards)
                            DropdownMenuItem(
                                value: _intOf(r['id']), child: Text('${r['text'] ?? r['value'] ?? ''}')),
                        ],
                        onChanged: (v) => setState(() => _standardId = v),
                      ),
                    ),
                  ),
                ),
              ],
              ],
              label('Change Password'),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('Leave both boxes empty to keep your current password.',
                    style: TextStyle(fontSize: 12, color: c.textSecondary)),
              ),
              field('New Password', _newPwd, Ion.lockClosedOutline, obscure: true),
              field('Confirm New Password', _confirmPwd, Ion.lockClosedOutline, obscure: true),
              Container(
                margin: const EdgeInsets.only(top: 6, bottom: 20),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.md)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('Read-only',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c.textMuted, letterSpacing: 1)),
                  ),
                  readRow('Registration No', _u('code')),
                  readRow('Grade', _u('currentGrade')),
                ]),
              ),
              Touchable(
                onPress: _saving || _extrasLoading ? null : _save,
                activeOpacity: 0.9,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 54),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: c.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(Radii.md),
                    boxShadow: Shadows.strong(c),
                  ),
                  child: _saving
                      ? const Center(
                          child: SizedBox(
                              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)))
                      : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Ion.checkmark, size: 18, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Save Changes',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                        ]),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}
