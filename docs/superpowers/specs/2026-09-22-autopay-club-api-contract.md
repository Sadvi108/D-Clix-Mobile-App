# Auto Pay (saved card) — Club.Api contract

Date: 2026-09-22
Status: app side built and tested (`flutter_app/lib/services/autopay.dart`); waiting on these three routes

## Why the app can't do this on its own

Step 3 (`POST /v1/payments/init`) is signed with the merchant secret. Probed 2026-09-22: the test
page `maclubsystem.com/bcpgauto/tokenize.php` returns **401** from Boost unless the caller sends
`merchant_id` and `merchant_secret`. So the app would have to ship the secret, and anyone who unpacks
the APK could then create customers and charge saved cards. The secret stays in Club.Api. The app
sends only its bearer token.

## Routes

All three go under `/Bcpg` so the app sends them to the same host as `/Bcpg/PayInvoices`
(`ApiService.boostBaseUrl`, UAT today). Each one needs `Authorization: Bearer <app token>`. The member
is whoever the token belongs to. The app never sends a student id.

### `POST /Bcpg/AutoPay/Enable`

Body: `{}`

Server:
1. Find the member's BCPG customer id, or create one (test flow Steps 1–2):
   `POST /gateway/recurring/api/v1/customers?idempotentFlag=true` with
   `{id, fullName, email, phone}` from the member's profile. Store the customer id on the student.
2. Step 3: `POST /gateway/v1/payments/init` with
   `paymentMethod: "card"`, `tokenize: "validate_only"`, `amount: 1.00`, `currency: "MYR"`,
   the member as `customer`, a fresh `referenceId`, and:
   - `returnUrl`: `https://<this API host>/Bcpg/Redirect` (**required**: the app closes Boost's page
     when it sees this URL; any other return address leaves the member stuck on Boost)
   - `callbackUrl`: Club.Api's webhook (see below)
3. Store `referenceId` against the student with status `pending`.

Reply `200`:
```json
{ "paymentUrl": "https://stage-pay.boostconnect.biz?t=…", "referenceId": "TOKENIZE_…" }
```
(Wrapping it as `{ "data": { … } }` also works.) The same call replaces an existing card.

### Webhook (server only)

When Boost's callback for that `referenceId` carries `card.token`: store the token, brand, last 4
digits and expiry on the student and set status `active`. A declined or failed tokenization sets
`failed` with a short message. Check the callback's `Authorization` header before trusting it.

### `GET /Bcpg/AutoPay`

Reply `200`:
```json
{
  "status": "off | pending | active | failed",
  "cardBrand": "Visa",
  "cardLast4": "4242",
  "cardExpiry": "08/28",
  "nextChargeDate": "2026-10-01T00:00:00",
  "message": "Your bank declined the September payment."
}
```
Every field except `status` is optional. The app reads any unknown status as `off`, never as `active`.
After Boost returns, the app polls this route 3 times, 2 s apart, while the status is `pending`.

### `POST /Bcpg/AutoPay/Disable`

Body: `{}`. Clear the stored token and set status `off`, so the Step 4 job skips this member.
Reply `200`.

## Step 4 (server job, not the app)

For each student with status `active`: take the pending invoices and charge them with
`POST /gateway/recurring/api/v1/customers/{customerId}/payments` using the stored token. Mark them paid
from the confirmed result, not from the request. If a payment fails, set `failed` plus `message`, so
the member sees "Action needed" and a button to update the card.

## How the app treats 404

A 404 on any of these routes means "not deployed yet". The status route then shows Off, and Enable /
Disable show "Auto Pay is not open yet". So the app is safe to ship before the routes exist, and
starts working as soon as they do.

## Security follow-ups

- `maclubsystem.com/bcpgauto` is public: the Step 3 form pre-fills the UAT merchant secret, and View
  Logs shows the HMAC passwords and webhook auth headers. Put it behind a login or remove it, and
  rotate the UAT secret.
- Never reuse the UAT secret in production.
