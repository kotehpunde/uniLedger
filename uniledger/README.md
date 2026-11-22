# UniLedger

A Flutter app for university students to track personal spending and split shared hostel bills with roommates.
Built for 6002CEM Mobile App Development, Coursework 2.

## Features

- Account activation with a university student ID (checked against mock student records) and a hashed password
- Dashboard with monthly budget progress, spending insights (safe to spend today, top category, month comparison) and a category chart
- Personal expenses: add, edit, swipe to delete with undo, category filter, budget alerts at 80% and 100%
- Keyword auto-category and foreign-currency expenses converted to MYR with live rates
- Household: roommates, shared bills split between selected members, who owes whom
- Mock settlement via Touch 'n Go eWallet, DuitNow QR or cash
- Household statement with per-person totals, CSV download to the phone, and a shareable text summary

## Tech

| Part | Package / service |
|---|---|
| Local database | sqflite (SQLite) |
| Session | shared_preferences |
| Password hashing | crypto (SHA-256) |
| HTTP | http |
| Exchange rates | ExchangeRate-API (open.er-api.com) |
| Tip of the day | Advice Slip API |
| File export | path_provider, dart:io |
| Sharing | share_plus |

## Run it

1. Install Flutter and an Android emulator.
2. `flutter pub get`
3. `flutter run` (choose the Android emulator; sqflite does not run on Windows desktop).

Demo student IDs: `P22014397` to `P22014406`.

## Project structure

```
lib/
  main.dart                 app start, chooses Login or Home
  database_helper.dart      SQLite tables and all queries
  session.dart              remembers the logged-in user
  categories.dart           categories, keywords, tips, formatting
  currency_service.dart     exchange-rate API
  export_service.dart       CSV download and text sharing
  screens/
    login_screen.dart
    register_screen.dart
    home_screen.dart
    dashboard_screen.dart
    expenses_screen.dart
    expense_form_screen.dart
    household_screen.dart
    statement_screen.dart
    profile_screen.dart
```

## Limitations

Data is stored locally on one device, student records are mock data, and payments are simulated.
Planned next step: move storage to Supabase so every roommate sees live updates on their own phone.
