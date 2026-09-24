import '../../theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../services/api_service.dart';

/// In-app WebView that drives the BCPG payment flow.
///
/// Loads the backend-issued checkout URL and returns control to the caller
/// after a merchant redirect or dismissal. The caller verifies the payment;
/// a redirect or closing the browser is never proof of its outcome.
class BcpgWebViewScreen extends StatefulWidget {
  /// The `paymentUrl` returned by BCPG `/v1/payments/init`.
  final String paymentUrl;

  /// The merchant `referenceId` that was sent to BCPG.
  final String referenceId;

  /// Substring used to detect that the browser navigated back to our
  /// returnUrl. Typically the path component (e.g. `bcpg_redirect`) or
  /// a custom scheme prefix (`dclix://bcpg-return`).
  final String returnUrlNeedle;

  const BcpgWebViewScreen({
    super.key,
    required this.paymentUrl,
    required this.referenceId,
    this.returnUrlNeedle = 'bcpg_redirect',
  });

  static bool isMerchantReturn(String? url,
      {String legacyPath = 'bcpg_redirect'}) {
    final uri = Uri.tryParse(url ?? '');
    if (uri == null) return false;
    if (uri.scheme == 'dclix' && uri.host == 'bcpg-return') return true;
    final allowedHosts = [
      Uri.parse(ApiService.baseUrl).host,
      Uri.parse(ApiService.boostBaseUrl).host
    ];
    if (!['http', 'https'].contains(uri.scheme) ||
        !allowedHosts.contains(uri.host)) return false;
    final path = uri.path.toLowerCase().replaceFirst(RegExp(r'/+$'), '');
    // `/Payment/Completed/{status}` and `/Payment/Finalizing` are where the invoice gateway
    // lands the browser; `/Bcpg/Redirect` is the purchase route's equivalent. Without the
    // Payment pages the WebView would sit on the finished page and never verify the payment.
    return path == '/bcpg/redirect' ||
        path == '/payment/finalizing' ||
        path == '/payment/completed' ||
        path.startsWith('/payment/completed/') ||
        path == '/${legacyPath.toLowerCase()}';
  }

  @override
  State<BcpgWebViewScreen> createState() => _BcpgWebViewScreenState();
}

class _BcpgWebViewScreenState extends State<BcpgWebViewScreen> {
  bool _verifying = false;
  bool _returned = false;
  double _progress = 0;

  /// Detect that the browser landed back on our return target. We don't
  /// trust the BCPG status param — always re-verify via the API.
  bool _isReturnUrl(String? url) {
    return BcpgWebViewScreen.isMerchantReturn(url,
        legacyPath: widget.returnUrlNeedle);
  }

  /// The gateway sent the browser back. Hand control to the caller.
  ///
  /// This screen deliberately does NOT decide the outcome. The gateway's redirect carries
  /// the BROWSER back, not a trustworthy result, and the app previously asked Boost
  /// directly using a merchant secret compiled into the APK. The caller now confirms
  /// through the backend (BoostPayment.confirm), which verifies and reconciles.
  Future<void> _handleReturn() async {
    if (_returned) return;
    _returned = true;
    if (!mounted) return;
    setState(() => _verifying = true);
    Navigator.of(context)
        .pop({'returned': true, 'referenceId': widget.referenceId});
  }

  Future<bool> _confirmAbort() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close payment?'),
        content: const Text(
            'The bank may already be processing your payment. After closing, we will check its status. Check Payment History before paying again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Close and check')),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_verifying) return; // mid-verify: ignore back press
        final abort = await _confirmAbort();
        if (abort && mounted) {
          Navigator.of(context).pop({
            'status': 'cancelled',
            'verification': null,
            'referenceId': widget.referenceId,
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Secure Payment'),
          leading: IconButton(
            icon: const Icon(AppIcons.close),
            onPressed: () async {
              if (_verifying) return;
              final abort = await _confirmAbort();
              if (abort && mounted) {
                Navigator.of(context).pop({
                  'status': 'cancelled',
                  'verification': null,
                  'referenceId': widget.referenceId,
                });
              }
            },
          ),
        ),
        body: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.paymentUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                javaScriptCanOpenWindowsAutomatically: true,
                useShouldOverrideUrlLoading: true,
                supportMultipleWindows: false,
                // FPX bank pages often use third-party cookies + storage.
                thirdPartyCookiesEnabled: true,
                domStorageEnabled: true,
                clearCache: false,
              ),
              onProgressChanged: (_, p) =>
                  setState(() => _progress = p / 100.0),
              shouldOverrideUrlLoading: (controller, action) async {
                final url = action.request.url?.toString();
                if (_isReturnUrl(url)) {
                  // Don't actually navigate to the return URL — bounce
                  // back into the app and verify.
                  await _handleReturn();
                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              },
              onLoadStop: (controller, url) async {
                if (_isReturnUrl(url?.toString())) {
                  await _handleReturn();
                }
              },
            ),
            if (_progress > 0 && _progress < 1)
              LinearProgressIndicator(value: _progress),
            if (_verifying)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 12),
                      Text('Verifying payment…',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
