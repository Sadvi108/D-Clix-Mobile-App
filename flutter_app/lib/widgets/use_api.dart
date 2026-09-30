import 'package:flutter/widgets.dart';

import '../services/api_service.dart';

import '../services/response_utils.dart';

/// Port of RN `useApi` (`frontend/src/api/useApi.ts`).
///
/// Same two deliberate behaviours:
///  1. A failed fetch keeps whatever data was already on screen — a stale value plus a
///     visible error beats a confident fake zero.
///  2. [reload] supersedes the in-flight request, so a late, older response can never
///     overwrite newer state.
class ApiResource<T> extends ChangeNotifier {
  Future<T> Function() _fn;
  T? data;
  bool loading = true;
  String? error;
  int _runId = 0;
  bool _disposed = false;

  /// [initial] seeds [data] (e.g. from the session cache) so the screen paints at once;
  /// the fetch then runs silently behind it, as a refresh rather than a cold load.
  ApiResource(this._fn, {bool autoRun = true, T? initial}) {
    // A manually-triggered resource has not started a request yet. Treating it
    // as loading disables the very button that is meant to start that request.
    loading = autoRun;
    if (initial != null) {
      data = initial;
      loading = false;
    }
    if (autoRun) reload(silent: initial != null);
  }

  /// Replace the fetcher (RN deps change) and run it.
  void update(Future<T> Function() fn) {
    _fn = fn;
    reload();
  }

  /// [silent] refreshes behind existing data without flipping [loading] — for background
  /// live refresh, so a screen that already shows data doesn't flash its skeleton.
  Future<void> reload({bool silent = false}) async {
    final runId = ++_runId;
    if (!(silent && data != null)) {
      loading = true;
      error = null;
      _notify();
    }
    try {
      final result = await _fn();
      if (_disposed || runId != _runId) return;
      data = result;
      loading = false;
      error = null;
    } catch (e) {
      if (_disposed || runId != _runId) return;
      loading = false;
      error = friendlyError(e);
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// `useApi` for a State: `late final stats = useApi(() => RnApi.homePageStats());`
/// The State rebuilds whenever any resource changes; resources are disposed with it.
///
/// A token change (guardian switching student, branch switch) bumps
/// [ApiService.sessionEpoch]; the next build notices and refetches everything, as RN's
/// `[token]` deps do.
mixin UseApi<W extends StatefulWidget> on State<W> {
  final List<ApiResource<dynamic>> _resources = [];
  int _epoch = ApiService.sessionEpoch;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkEpoch();
  }

  @override
  void didUpdateWidget(covariant W oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkEpoch();
  }

  void _checkEpoch() {
    if (_epoch == ApiService.sessionEpoch) return;
    _epoch = ApiService.sessionEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) reloadAll();
    });
  }

  ApiResource<T> useApi<T>(Future<T> Function() fn, {bool autoRun = true, T? initial}) {
    final r = ApiResource<T>(fn, autoRun: autoRun, initial: initial);
    r.addListener(_onResource);
    _resources.add(r);
    return r;
  }

  void _onResource() {
    if (mounted) setState(() {});
  }

  /// Reload every resource (pull-to-refresh / live refresh).
  Future<void> reloadAll({bool silent = false}) =>
      Future.wait(_resources.map((r) => r.reload(silent: silent)));

  @override
  void dispose() {
    for (final r in _resources) {
      r.removeListener(_onResource);
      r.dispose();
    }
    super.dispose();
  }
}
