# Boost gateway for Due Payment and Monthly Payment — design

Date: 2026-09-17
Status: approved approach (Option A), pending live confirmation of the backend bug

## Goal

Pressing **Pay** in Due Payment (invoices) and Monthly Payment (advance months) opens the Boost
checkout page, the same way Purchase Request already does. Live backend, live Boost staging
merchant, real invoices. No mock data, no canned responses, no fallback that fakes a link.

## What is true today

| Section | App request to `POST https://apimacuat.zyncbook.com/Bcpg/PayInvoices` | Backend reply |
|---|---|---|
| Purchase Request | `{"invoiceIds":[],"purchaseItems":[…price…]}` | `200` + `https://stage-pay.boostconnect.biz?t=…` (confirmed live 2026-09-17, screenshot RM 200.00) |
| Due Payment | `{"invoiceIds":[…],"payTermPayments":null,"purchaseItems":null}` | `400 "The JSON value could not be converted to System.String. Path: $.status"` (last probed 2026-07-28) |
| Monthly Payment | `{"invoiceIds":[…],"payTermPayments":{studentIds,year,months},"purchaseItems":null}` | same `400` (last probed 2026-07-28) |

- The request bodies match the UAT Swagger `RequestBcpgPayViewModel` field for field. The app does
  not need a different request.
- All four pay entry points (`payments_screen.dart`, `outstanding_invoices_screen.dart`,
  `payment/term_payment_screen.dart`, `purchase_request_screen.dart`) already call
  `BoostPayment.start` and push `BcpgWebViewScreen` with the returned URL. Due and Monthly redirect
  exactly like Purchase the moment the backend returns a link.
- The invoice/term failure happens before invoice validation (a nonexistent id fails the same
  way): the backend deserialises an amount-lookup reply whose `status` is a number into a `string`.
  Purchases carry their price in the request and skip that lookup, which is why only they work.

## Problems and owners

### 1. Phones cannot reach the UAT host (app, fixed)

`apimacuat.zyncbook.com` serves a self-signed Plesk certificate. Android's
`network_security_config.xml` trusts it, but Dart's `HttpClient` (used by `package:http`) never
reads that file, so on every phone every `/Bcpg` call failed in the TLS handshake — including
purchases. Reproduced: `HandshakeException … CERTIFICATE_VERIFY_FAILED` before, HTTP 401
(reached the server, unauthenticated probe) after.

Fix, in `lib/services/api_service.dart`:
- `ApiService.client` is an `IOClient` whose `badCertificateCallback` accepts a certificate only
  when the host is exactly the Boost host **and** the certificate is byte-identical to the pinned
  `boostCertPem` (same bytes as `android/app/src/main/res/raw/uat_apimacuat.pem`, SHA-256
  `DD:1E:D0:6B:44:C2:95:A0:3D:79:D1:FA:BC:8A:B5:5C:DA:F3:37:BC:36:FA:37:15:28:E9:E5:39:45:D5:A8:AA`,
  expires 2027-04-17). Every other host and certificate keeps normal
  verification. Web keeps `http.Client()`.
- Test: `test/boost_cert_pin_test.dart` (accepts pinned cert on Boost host; rejects it on other
  hosts; rejects other certs on the Boost host; tolerant of line endings).

### 2. Invoice and term paths crash in `/Bcpg/PayInvoices` (backend)

Backend fixes the type of `status` in the model that reads the amount-lookup reply (or reads it as
a number), so a request with `invoiceIds` or `payTermPayments` returns a Boost link the way
purchases do. No app change follows from this fix.

## Explicitly rejected

- **Sending invoices or months as `purchaseItems`.** It would open Boost today, but the backend
  would settle a purchase request, not the invoices. Parents would pay and still owe.
- **Legacy `/Outstanding/PayInvoices` `PaymentMethod=2`.** Failed with the same error on UAT, has no
  advance-month support, and may not be Boost.
- **Any mock, stub, sample link or demo mode.**

## Live verification (no mocks)

1. **Backend state probe** (`boost_probe.sh`, run by a person, password typed by them): prod login →
   UAT accepts the prod token (`GET /Profile/MyInfo` 200) → `POST /Bcpg/PayInvoices` with fake
   invoice `999999999`. Still `Path: $.status` → wait for backend. A validation-style error → fixed.
2. **App, after the backend fix**, on the simulator and on an Android phone with the new build,
   logged in as a real student with a pending invoice:
   - Due Payment → select one invoice → Pay → Boost page opens, amount equals the invoice's due.
   - Monthly Payment → select one month → Pay → Boost page opens, amount equals the month's fee.
   - Purchase Request → still opens Boost (regression check).
3. **Stop at the bank list.** UAT writes to the live database and `stage-pay` is a sandbox:
   finishing a sandbox payment can mark a real invoice paid with no money received. Complete a
   payment only on an invoice an admin has agreed to reverse.

## Out of scope (tracked, not done here)

- Real certificate on `apimacuat.zyncbook.com` → then delete `boostCertPem` and the Android pin.
- `/Bcpg` deployed to production and a production Boost merchant → then delete `boostBaseUrl`.
- `GET /Bcpg/Redirect` 500 without a token (browser return leg). The app intercepts the return URL
  before it loads, so the app flow is unaffected.
