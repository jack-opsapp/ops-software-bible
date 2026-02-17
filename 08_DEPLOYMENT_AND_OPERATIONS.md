# 08 - Deployment and Operations

**Document Version:** 1.0
**Last Updated:** February 15, 2026
**Status:** Production Reference

---

## Table of Contents

1. [Overview](#overview)
2. [Build Configuration](#build-configuration)
3. [Environment Variables and Secrets](#environment-variables-and-secrets)
4. [Subscription System](#subscription-system)
5. [Analytics and Tracking](#analytics-and-tracking)
6. [Error Logging and Monitoring](#error-logging-and-monitoring)
7. [Testing Requirements](#testing-requirements)
8. [App Store Deployment](#app-store-deployment)
9. [Data Migrations](#data-migrations)
10. [Bubble.io Backend Configuration](#bubbleio-backend-configuration)
11. [Production Checklist](#production-checklist)

---

## Overview

This document covers all operational aspects of deploying and maintaining the OPS iOS application in production. OPS is a field-first application designed for trade workers, requiring special consideration for offline functionality, device compatibility, and real-world job site conditions.

### Core Deployment Principles

1. **Field-First Reliability** - Every deployment must maintain offline functionality
2. **Zero Downtime** - Updates should never interrupt active field work
3. **Backward Compatibility** - Data migrations must support users on older app versions
4. **Performance First** - Must work smoothly on 3+ year old devices
5. **Security by Design** - All secrets managed through secure channels

---

## Build Configuration

### Xcode Project Settings

#### Minimum Requirements
```
- Xcode: 15.0+
- iOS Deployment Target: 17.0
- Swift Version: 5.9+
- Bundle Identifier: co.opsapp.ops.OPS
- Version: 1.0.0
- Build: Incremented with each release
```

#### Build Targets

**Debug Configuration:**
- Optimizations: None (-Onone)
- Debug Information: Full
- Preprocessor Macros: DEBUG=1
- Other Swift Flags: -D DEBUG
- Code Signing: Development
- Provisioning Profile: Development

**Release Configuration:**
- Optimizations: Whole Module (-O)
- Debug Information: None
- Strip Symbols: Yes
- Enable Bitcode: No (deprecated)
- Code Signing: Distribution
- Provisioning Profile: App Store

#### Capabilities Required

**Essential Capabilities:**
1. **Push Notifications**
   - APNs environment: Production
   - OneSignal integration enabled

2. **Background Modes**
   - Remote notifications
   - Background fetch
   - Location updates (when in use)

3. **Keychain Sharing**
   - Group: $(AppIdentifierPrefix)co.opsapp.ops.OPS

4. **Associated Domains**
   - applinks:opsapp.co
   - webcredentials:opsapp.co

5. **Sign in with Apple**
   - Required for OAuth authentication

#### Swift Package Dependencies

```swift
// Package.swift equivalent
dependencies: [
    .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "12.6.0"),
    .package(url: "https://github.com/stripe/stripe-ios", from: "23.0.0"),
    .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "7.0.0"),
    .package(url: "https://github.com/OneSignal/OneSignal-iOS-SDK", from: "5.0.0"),
    .package(url: "https://github.com/aws-amplify/aws-sdk-ios-spm", from: "2.36.0")
]
```

**Firebase Products:**
- FirebaseCore
- FirebaseAnalytics
- FirebaseAuth (if used)
- FirebaseCrashlytics (future)

**AWS Products:**
- AWSS3
- AWSCore

#### Font Resources

Custom fonts must be included and registered in Info.plist:
- BebasNeue-Regular.ttf
- Kosugi-Regular.ttf
- Mohave-Bold.ttf
- Mohave-Italic.ttf
- Mohave-Light.ttf
- Mohave-Medium.ttf
- Mohave-MediumItalic.ttf
- Mohave-Regular.ttf
- Mohave-SemiBold.ttf
- Mohave-SemiBoldItalic.ttf

---

## Environment Variables and Secrets

### Critical Security Note

**NEVER commit secrets to version control.** All sensitive credentials must be:
1. Stored in Xcode build settings (not checked into Git)
2. Injected via CI/CD environment variables
3. Managed through secure credential storage (1Password, AWS Secrets Manager)

### Required Secrets

#### 1. Bubble.io API Configuration

**Production API:**
```
Base URL: https://opsapp.co/version-test/api/1.1/
API Token: f81e9da85b7a12e996ac53e970a52299
```

**Stored in:** `APIService.swift` (hardcoded - consider moving to build config)

**Security Note:** API token is currently embedded in source. For production, this should be:
- Stored in Xcode configuration settings
- Different tokens for Debug/Release builds
- Rotated periodically

#### 2. AWS S3 Credentials

**Purpose:** Image upload and storage for project/client photos

**Required Keys (stored in Info.plist):**
```xml
<key>AWS_ACCESS_KEY_ID</key>
<string>$(AWS_ACCESS_KEY_ID)</string>

<key>AWS_SECRET_ACCESS_KEY</key>
<string>$(AWS_SECRET_ACCESS_KEY)</string>

<key>AWS_S3_BUCKET</key>
<string>$(AWS_S3_BUCKET)</string>

<key>AWS_REGION</key>
<string>$(AWS_REGION)</string>
```

**Values (injected at build time):**
- AWS_ACCESS_KEY_ID: IAM access key with S3 permissions
- AWS_SECRET_ACCESS_KEY: IAM secret key
- AWS_S3_BUCKET: ops-app-images (or your bucket name)
- AWS_REGION: us-east-2 (or your region)

**IAM Permissions Required:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::ops-app-images/*"
    }
  ]
}
```

#### 3. Firebase Configuration

**File:** `GoogleService-Info.plist`

**Critical Fields:**
```xml
<key>API_KEY</key>
<string>AIzaSyCfsqPrZoiFP22F0C7vndq4ehVgaQL1R_8</string>

<key>GCM_SENDER_ID</key>
<string>992104001932</string>

<key>PROJECT_ID</key>
<string>ops-ios-app</string>

<key>BUNDLE_ID</key>
<string>co.opsapp.ops.OPS</string>

<key>STORAGE_BUCKET</key>
<string>ops-ios-app.firebasestorage.app</string>

<key>GOOGLE_APP_ID</key>
<string>1:992104001932:ios:146016e94829f447f366a9</string>

<key>IS_ADS_ENABLED</key>
<true/>

<key>IS_ANALYTICS_ENABLED</key>
<true/>
```

**Security Note:** This file is safe to commit as it contains public configuration, not secrets.

#### 4. Google Sign-In Configuration

**Stored in Info.plist:**
```xml
<key>GIDClientID</key>
<string>748032911358-3a66h9ie5o4l7g41ec42d6fq4k4erqgb.apps.googleusercontent.com</string>

<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.748032911358-3a66h9ie5o4l7g41ec42d6fq4k4erqgb</string>
    </array>
  </dict>
</array>
```

#### 5. OneSignal Push Notifications

**App ID:** `0fc0a8e0-9727-49b6-9e37-5d6d919d741f`

**Initialized in:** `AppDelegate.swift`
```swift
OneSignal.initialize("0fc0a8e0-9727-49b6-9e37-5d6d919d741f", withLaunchOptions: nil)
```

**APNs Certificate:** Must be uploaded to OneSignal dashboard
- Development: Development Push Certificate (.p12)
- Production: Production Push Certificate (.p12)

#### 6. Stripe Configuration

**Environment:** Live Mode (matches Bubble production)

**Price IDs (Live):**
```swift
// Starter Plan
Monthly: price_1S6Jz1EooJoYGoIwDwx7dQHJ
Annual:  price_1S6Jz1EooJoYGoIwiGXZJ2a7

// Team Plan
Monthly: price_1S6Jz6EooJoYGoIwRoQIstPk
Annual:  price_1S6Jz6EooJoYGoIwQSRdxhRs

// Business Plan
Monthly: price_1S6Jz8EooJoYGoIw9u8cb3lx
Annual:  price_1S6Jz8EooJoYGoIwB2IUeC6z
```

**Price IDs (Test - only use when Bubble is in test mode):**
```swift
// Starter Plan
Monthly: price_1S4UVEEooJoYGoIwIGvWfSd5
Annual:  price_1S4UVJEooJoYGoIwm11ItaKw

// Team Plan
Monthly: price_1S4UVyEooJoYGoIwydDGa3jG
Annual:  price_1S4UVyEooJoYGoIw3aKrVfjQ

// Business Plan
Monthly: price_1S4UW4EooJoYGoIwkgk4d8ph
Annual:  price_1S4UW4EooJoYGoIwaCxXWwUD
```

**Configuration:** `StripeConfiguration.swift`
```swift
// Stripe publishable key set in StripeConfiguration.shared.configure()
```

### Environment-Specific Configuration

#### Development Build
- Uses test Stripe keys (if Bubble in test mode)
- Debug logging enabled
- OneSignal log level: LL_WARN
- Firebase debug mode enabled

#### Production Build
- Uses live Stripe keys
- Debug logging disabled
- OneSignal log level: LL_NONE
- Firebase production mode
- Crash reporting enabled

---

## Subscription System

### Overview

OPS uses a tiered subscription model with trial period, active subscriptions, and grace periods. All subscription logic is managed through `SubscriptionManager.swift` with Stripe payment processing via Bubble.io backend.

### Subscription Tiers

#### Trial Period
```
Duration: 30 days
Max Seats: 10
Price: $0
Features: Full app access, all features
Start: Automatic on company creation
```

**Trial Enforcement:**
- Trial start date set on company creation
- Trial end date = start date + 30 days
- Daily checks via `SubscriptionManager.checkSubscriptionStatus()`
- Notifications scheduled at 7, 3, and 1 day before expiry

#### Starter Plan
```
Price: $90/month or $864/year (20% discount)
Max Seats: 3
Features:
  - 3 team members
  - Unlimited projects
  - Full app functionality
  - Email support
```

**Stripe Price IDs:**
- Monthly: `price_1S6Jz1EooJoYGoIwDwx7dQHJ`
- Annual: `price_1S6Jz1EooJoYGoIwiGXZJ2a7`

#### Team Plan
```
Price: $140/month or $1,344/year (20% discount)
Max Seats: 5
Features:
  - 5 team members
  - Unlimited projects
  - Full app functionality
  - Priority email support
```

**Stripe Price IDs:**
- Monthly: `price_1S6Jz6EooJoYGoIwRoQIstPk`
- Annual: `price_1S6Jz6EooJoYGoIwQSRdxhRs`

#### Business Plan
```
Price: $190/month or $1,824/year (20% discount)
Max Seats: 10
Features:
  - 10 team members
  - Unlimited projects
  - Full app functionality
  - Priority support
```

**Stripe Price IDs:**
- Monthly: `price_1S6Jz8EooJoYGoIw9u8cb3lx`
- Annual: `price_1S6Jz8EooJoYGoIwB2IUeC6z`

### Subscription Status States

```swift
enum SubscriptionStatus: String {
    case trial      // Active trial period
    case active     // Paid subscription active
    case grace      // 7-day grace period after payment failure
    case expired    // Trial or subscription ended
    case cancelled  // User cancelled subscription
}
```

### Access Control Logic

**5-Layer Validation System** (implemented in `SubscriptionManager.shouldLockoutUser()`):

**Layer 1: Company Data Validation**
- Check company exists
- Deny access if nil

**Layer 2: Subscription Status Validation**
- Check subscriptionStatus is not nil
- Deny access if nil

**Layer 3: Seat Capacity Validation**
- Check maxSeats > 0
- Deny access if invalid

**Layer 4: Seat Count Validation**
- Check seatedEmployees count ≤ maxSeats
- Deny access if exceeded

**Layer 5: Status-Specific Validation**

For `trial` status:
- Check trial end date exists
- Check trial not expired (trialEndDate > now)
- **Defensive check:** If Bubble status is "trial" but date expired, deny access and update Bubble to "expired"

For `active` or `grace` status:
- Check user has a seat (userId in seatedEmployeeIds array)
- Deny access if no seat

For `expired` or `cancelled` status:
- Always deny access

### Seat Management

**Seated Employees:**
- Stored in Company.seatedEmployeeIds (array of user IDs)
- Synced to Bubble field: `seated_employees` (list of User references)
- Managed through `SubscriptionManager.addSeat()` and `removeSeat()`

**Seat Assignment Rules:**
1. Admin users can add/remove seats
2. Admins cannot remove their own seat
3. Adding seat requires available capacity (seatedCount < maxSeats)
4. Changes sync immediately to Bubble via API

**Auto-Removal:**
- When downgrading plans, newest non-admin users auto-removed
- Implemented via `getNewestSeatedEmployee()`

### Subscription Notifications

**Trial Expiry Notifications:**
- Scheduled at 7, 3, and 1 day before trial end
- Title: "Trial Ending Soon"
- Time: 9:00 AM each day
- Category: TRIAL_NOTIFICATION

**Grace Period Notifications:**
- Scheduled daily during 7-day grace period
- Title: "Action Required"
- Message: Payment update needed
- Time: 9:00 AM each day
- Category: GRACE_PERIOD_NOTIFICATION

### Payment Flow

**Setup Intent Flow (primary):**

1. User selects plan in `PlanSelectionView`
2. Call `BubbleSubscriptionService.createSetupIntent()`
3. Bubble creates Stripe customer + setup intent
4. iOS presents Stripe payment sheet
5. User enters payment method
6. Stripe confirms setup intent
7. Call `BubbleSubscriptionService.completeSubscription()`
8. Bubble creates subscription, updates company status
9. iOS syncs company data, updates UI

**Promo Code Support:**
- Optional promo code field in payment flow
- Validated by Bubble/Stripe
- 100% discount codes skip payment collection
- Discount applied immediately to subscription

### Subscription Manager Integration

**App Launch:**
```swift
// OPSApp.swift - onAppear
subscriptionManager.setDataController(dataController)
await subscriptionManager.checkSubscriptionStatus()
```

**App Becoming Active:**
```swift
// OPSApp.swift - didBecomeActiveNotification
await subscriptionManager.checkSubscriptionStatus()
```

**After Sync:**
```swift
// Listen for .companySynced notification
await subscriptionManager.checkSubscriptionStatus()
```

**After Payment:**
```swift
// Listen for .paymentSuccessful notification
subscriptionManager.trackSubscriptionPurchase()
```

### Lockout Screen

When `shouldShowLockout == true`:
- Display `SubscriptionLockoutView` (full-screen modal)
- Block all app functionality
- Show subscription status and next steps
- Allow admins to navigate to payment

---

## Analytics and Tracking

### Firebase Analytics

**Project:** ops-ios-app
**SDK Version:** 12.6.0+
**Initialization:** `AppDelegate.didFinishLaunchingWithOptions`

```swift
// AppDelegate.swift
FirebaseApp.configure()
```

**Centralized Manager:** `AnalyticsManager.swift` (singleton)

### Event Categories

#### 1. Authentication Events

**sign_up**
- Triggers: New account creation
- Parameters: method (email/apple/google), user_type (company/employee)
- Location: OnboardingViewModel, DataController
- Google Ads: Primary acquisition conversion

**login**
- Triggers: Returning user login
- Parameters: method, user_type
- Location: DataController

#### 2. Onboarding Events

**complete_onboarding**
- Triggers: User completes onboarding flow
- Parameters: user_type, has_company (bool)
- Location: OnboardingViewModel
- Google Ads: Onboarding completion signal

**begin_trial**
- Triggers: Company owner starts trial
- Parameters: user_type, trial_days (default 30)
- Location: OnboardingViewModel

#### 3. Subscription Events

**purchase** (Firebase standard event)
- Triggers: Subscription purchase
- Parameters: item_name (plan), price, currency (USD), user_type
- Location: SubscriptionManager
- Google Ads: Revenue conversion

**subscribe** (custom event)
- Triggers: Same as purchase (duplicate for backup)
- Parameters: Same as purchase
- Location: SubscriptionManager

#### 4. Screen View Events

**screen_view**
- Triggers: Every screen/view appears
- Parameters: screen_name, screen_class
- Location: All main views via .onAppear

**Tracked Screens:**
- Main tabs: home, job_board, schedule, settings
- Job Board: job_board_dashboard, job_board_projects, job_board_tasks, job_board_clients
- Details: project_details, task_details, client_details
- Forms: project_form, task_form, client_form
- Settings: profile_settings, organization_settings, notification_settings, app_settings, manage_team, manage_subscription
- Subscription: plan_selection, subscription_lockout
- Auth: login, forgot_password

#### 5. CRUD Events

**create_project**
- Parameters: project_count, user_type
- Location: ContentView

**create_first_project** (auto-triggered)
- High-intent conversion signal
- Google Ads: Engagement conversion

**task_created**
- Parameters: task_type, has_schedule (bool), team_size
- Location: TaskFormSheet

**task_completed**
- Parameters: task_type
- Location: DataController
- Google Ads: Productivity signal

**client_created**
- Parameters: has_email, has_phone, has_address, import_method
- Location: ClientSheet

#### 6. Engagement Events

**navigation_started**
- Triggers: User starts navigation to project
- Parameters: project_id
- Location: HomeView

**search_performed**
- Parameters: section, results_count
- Location: Search components

**filter_applied**
- Parameters: section, filter_type
- Location: Filter sheets

**image_uploaded**
- Parameters: image_count, context
- Location: ProjectFormSheet, ClientSheet

**form_abandoned**
- Triggers: Form closed without saving
- Parameters: form_type, fields_filled
- Location: Form sheets

### User Properties

**user_type**
- Values: "company", "employee"
- Set on authentication

**subscription_status**
- Values: "subscribed", "free"
- Set via `AnalyticsManager.setSubscriptionStatus()`

**User ID**
- Set via `Analytics.setUserID()` on login
- Cleared on logout

### Google Ads Conversion Events

Automatically sent via Firebase-Google Ads integration:

1. **sign_up** - Primary acquisition
2. **purchase** - Revenue conversion
3. **create_first_project** - High-intent engagement
4. **complete_onboarding** - Onboarding success
5. **task_completed** - Productivity signal

### Implementation Pattern

```swift
// Screen view tracking
.onAppear {
    AnalyticsManager.shared.trackScreenView(
        screenName: .projectDetails,
        screenClass: "ProjectDetailsView"
    )
}

// Event tracking
AnalyticsManager.shared.trackProjectCreated(
    projectCount: projects.count,
    userType: currentUser?.userType
)
```

### Console Logging

All events log with `[ANALYTICS]` prefix:
```
[ANALYTICS] Tracked screen_view - screen: home
[ANALYTICS] Tracked task_created - type: Installation, hasSchedule: true, teamSize: 2
[ANALYTICS] Tracked subscribe - plan: Team, price: 140.0, currency: USD
```

### Privacy Compliance

**Never Log PII:**
- No names, emails, phone numbers, addresses
- Use IDs only (user_id, project_id, etc.)
- Aggregate metrics only

**User Consent:**
- Analytics enabled by default
- Firebase Analytics automatically respects iOS tracking preferences
- Users can opt out via iOS Settings > Privacy > Analytics

---

## Error Logging and Monitoring

### Current Implementation

**Console Logging:**
- All critical operations log with prefixes:
  - `[AUTH]` - Authentication operations
  - `[SUBSCRIPTION]` - Subscription checks
  - `[SYNC]` - Data synchronization
  - `[ANALYTICS]` - Event tracking
  - `[PUSH]` - Push notifications
  - `[ONESIGNAL]` - OneSignal events
  - `[MIGRATION]` - Data migrations
  - `[APP_LAUNCH]` - Launch health checks

**Example:**
```swift
print("[SUBSCRIPTION] ✅ Access granted - active subscription with seat")
print("[SYNC] ❌ Failed to sync projects: \(error.localizedDescription)")
```

### Recommended Production Monitoring

#### 1. Firebase Crashlytics (Not Yet Implemented)

**Setup:**
```swift
// Add to Package.swift
.package(url: "https://github.com/firebase/firebase-ios-sdk", from: "12.6.0")

// Add to target
dependencies: ["FirebaseCrashlytics"]

// Initialize in AppDelegate
import FirebaseCrashlytics
Crashlytics.crashlytics()
```

**Usage:**
```swift
// Log non-fatal errors
Crashlytics.crashlytics().record(error: error)

// Set user context
Crashlytics.crashlytics().setUserID(userId)
Crashlytics.crashlytics().setCustomValue(companyId, forKey: "company_id")

// Log events
Crashlytics.crashlytics().log("Sync failed for user \(userId)")
```

#### 2. Custom Error Tracking

**Critical Errors to Monitor:**

**Authentication Failures:**
- Login failures (invalid credentials vs. network)
- Token expiration without refresh
- Keychain access failures

**Subscription Errors:**
- Payment failures
- Seat management conflicts
- Trial expiration not updating in Bubble

**Sync Failures:**
- Network timeouts (>30 seconds)
- Bubble API errors (4xx, 5xx)
- Data corruption (nil IDs, invalid relationships)
- Image upload failures to S3

**Data Health Issues:**
- Missing currentUser or company after authentication
- SwiftData fetch failures
- Orphaned records (tasks without projects)

**Implementation Pattern:**
```swift
// ErrorLogger.swift
class ErrorLogger {
    static func logCritical(_ error: Error, context: String) {
        // Log to Crashlytics
        Crashlytics.crashlytics().record(error: error)

        // Log to console
        print("❌ CRITICAL [\(context)]: \(error.localizedDescription)")

        // Optionally send to backend
        // sendErrorToBackend(error, context)
    }
}
```

#### 3. Health Check Monitoring

**DataHealthManager Integration:**

Monitor these states (from `DataHealthManager.swift`):
- `.healthy` - All systems operational
- `.missingUser` - User not found after authentication
- `.missingCompany` - Company not found for user
- `.syncManagerNotInitialized` - Critical service failure

**Alert Thresholds:**
- 3+ failed syncs in 24 hours → Alert
- 10+ users hit lockout screen → Alert
- Image upload failure rate >5% → Alert
- Subscription check failures >1% → Alert

#### 4. Performance Monitoring

**Key Metrics:**
- App launch time (target: <2 seconds)
- Sync duration (target: <5 seconds for typical data)
- UI responsiveness (60 FPS minimum)
- Network request latency
- SwiftData query performance

**Tools:**
- Xcode Instruments (Time Profiler, Allocations)
- Firebase Performance Monitoring
- MetricKit (Apple's performance framework)

### Notification Strategy

**Critical Alerts (PagerDuty/Slack):**
- API down (>5 minutes)
- Payment processing failures (>10% of attempts)
- Mass lockouts (>50 users)
- Data loss detected

**Warning Alerts (Email/Slack):**
- Elevated error rates (>2x baseline)
- Slow API responses (>10 seconds)
- Image upload failures
- Subscription sync delays

---

## Testing Requirements

### Field-First Testing Checklist

OPS is designed for harsh job site conditions. Every release must pass these field-specific tests:

#### 1. Offline Functionality Testing

**Required Tests:**
- [ ] Create project offline → Syncs when online
- [ ] Update task status offline → Syncs correctly
- [ ] Add client offline → Images queue for upload
- [ ] View all data offline (cached from previous sync)
- [ ] Handle 10+ queued changes when reconnecting
- [ ] Resolve sync conflicts (last-write-wins strategy)

**Test Scenarios:**
- Airplane mode enabled
- Cellular data disabled
- Wi-Fi with no internet
- Intermittent connectivity (toggle every 30 seconds)

#### 2. Glove Testing

**Required Tests:**
- [ ] All buttons tappable with thick work gloves
- [ ] Swipe gestures work with gloves
- [ ] Text input possible with gloves (use voice dictation)
- [ ] Status changes via tap (not swipe, if gloves interfere)
- [ ] Navigation between screens

**Test Gloves:**
- Leather work gloves
- Rubber-coated grip gloves
- Winter gloves (extreme case)

**Touch Target Validation:**
- Minimum 44×44pt (iOS standard)
- Prefer 56×56pt for primary actions
- Critical actions: 60×60pt

#### 3. Sunlight Readability Testing

**Required Tests:**
- [ ] Text readable in direct sunlight
- [ ] Status colors distinguishable outdoors
- [ ] Image thumbnails visible
- [ ] Contrast sufficient for all UI elements

**Test Conditions:**
- Direct sunlight (midday, summer)
- Shade (verify not over-contrasted)
- Dusk/dawn lighting

**Contrast Requirements:**
- Normal text: 7:1 minimum
- Large text (18pt+): 4.5:1 minimum
- Status indicators: Color + icon (not color alone)

#### 4. Old Device Testing

**Required Devices:**
- iPhone XR (2018) - 3GB RAM
- iPhone 11 (2019) - 4GB RAM
- iPhone SE 2nd gen (2020) - 3GB RAM

**Performance Targets:**
- App launch: <3 seconds
- View transitions: <0.3 seconds
- Sync 100 projects: <10 seconds
- Image load: <2 seconds per image

**Memory Management:**
- No crashes under memory pressure
- Images released after view dismissal
- Graceful handling of low storage warnings

#### 5. Battery Impact Testing

**Required Tests:**
- [ ] Background sync doesn't drain battery (target: <5% per 8 hours)
- [ ] Location services minimal when not navigating
- [ ] Push notifications don't wake app unnecessarily
- [ ] Dark mode reduces power consumption

**Test Method:**
- Full charge → Use app 4 hours → Measure drain
- Background 8 hours → Measure drain
- Compare to baseline (similar apps)

**Target:** <10% battery drain per hour of active use

#### 6. Real-World Scenario Testing

**Scenario 1: Morning Crew Assignment**
- [ ] Company owner logs in at 6 AM
- [ ] Creates 5 tasks for the day
- [ ] Assigns to 3 field crew members
- [ ] Field crew receives push notifications
- [ ] Field crew views tasks on Job Board
- **Time limit:** <2 minutes total

**Scenario 2: On-Site Status Updates**
- [ ] Field crew arrives at job site
- [ ] Marks task "In Progress"
- [ ] Uploads 3 photos
- [ ] Adds notes to task
- [ ] Marks task "Complete"
- **Constraint:** Works offline, syncs when back online

**Scenario 3: Client Communication**
- [ ] Office crew adds new client
- [ ] Imports contact info from phone
- [ ] Creates project for client
- [ ] Schedules 2 tasks
- [ ] Client receives notification (if configured)
- **Time limit:** <3 minutes total

**Scenario 4: Subscription Management**
- [ ] Trial ends for company
- [ ] Admin sees lockout screen
- [ ] Selects plan, enters payment
- [ ] Team immediately regains access
- [ ] Seated employees see active status
- **Critical:** No data loss during lockout period

#### 7. Edge Case Testing

**Data Edge Cases:**
- [ ] 500+ projects (performance)
- [ ] 100+ employees (seat management)
- [ ] 50+ images in one project
- [ ] Emoji in all text fields
- [ ] Very long project names (50+ characters)
- [ ] Special characters in addresses

**Network Edge Cases:**
- [ ] API returns 500 error → Graceful retry
- [ ] API timeout (30+ seconds) → User feedback
- [ ] Partial sync failure → Resume correctly
- [ ] Image upload fails → Retry logic

**Authentication Edge Cases:**
- [ ] Token expires mid-session → Silent refresh
- [ ] User deleted in Bubble → Force logout
- [ ] PIN entered wrong 3x → Lock screen
- [ ] Apple Sign-In cancelled → Return to login

#### 8. Accessibility Testing

**VoiceOver:**
- [ ] All buttons have labels
- [ ] Images have alt text
- [ ] Form fields have hints
- [ ] Navigation logical

**Dynamic Type:**
- [ ] Layout adapts to larger text sizes
- [ ] No text truncation at 200% size
- [ ] Touch targets scale appropriately

**Color Blindness:**
- [ ] Status not color-only (use icons too)
- [ ] Protanopia test (red-blind)
- [ ] Deuteranopia test (green-blind)

---

## App Store Deployment

### Pre-Release Checklist

#### 1. Version and Build Numbers

**Update in Xcode:**
```
Info.plist:
  CFBundleShortVersionString: X.Y.Z (e.g., 1.0.0)
  CFBundleVersion: Build number (increment each upload)
```

**Versioning Strategy:**
- Major (X): Breaking changes, major features
- Minor (Y): New features, non-breaking
- Patch (Z): Bug fixes only

#### 2. Code Signing and Provisioning

**Distribution Certificate:**
- Valid for 1 year
- Renewed annually in Apple Developer Portal
- Installed in Xcode > Preferences > Accounts

**Provisioning Profile:**
- Type: App Store Distribution
- App ID: co.opsapp.ops.OPS
- Capabilities: Push Notifications, Sign in with Apple, Keychain Sharing
- Devices: Not applicable (App Store = all devices)

**Archive Settings:**
- Product > Archive
- Select scheme: OPS (Release)
- Verify build configuration: Release
- Check code signing: Automatic signing recommended

#### 3. App Store Connect Metadata

**Required Information:**

**App Information:**
- Name: OPS
- Subtitle: Job Management for Trade Workers (max 30 characters)
- Category: Productivity (Primary), Business (Secondary)
- Content Rights: Use licensed fonts confirmed

**Version Information:**
- What's New: <4000 characters, bullet points
- Keywords: job management, field crew, trade workers, project tracking
- Support URL: https://opsapp.co/support
- Marketing URL: https://opsapp.co

**Screenshots (Required Sizes):**
- 6.7" Display (iPhone 15 Pro Max): 1290 × 2796
- 6.5" Display (iPhone 11 Pro Max): 1242 × 2688
- 5.5" Display (iPhone 8 Plus): 1242 × 2208

**Required Screenshots:**
1. Home screen with active projects
2. Job Board view
3. Project details with tasks
4. Schedule/Calendar view
5. Task details with photos

**App Preview Video (Optional but Recommended):**
- 30 seconds max
- Shows core workflow: Create project → Assign task → Update status
- Portrait orientation
- No music (use on-screen text)

**App Icon:**
- 1024 × 1024 PNG (no transparency)
- Consistent with in-app icon

#### 4. App Privacy and Compliance

**Privacy Nutrition Label:**

**Data Collected:**
- Contact Info: Name, Email, Phone (for user account)
- Location: Approximate location (for address suggestions)
- User Content: Photos, Projects, Tasks (for job tracking)
- Identifiers: User ID (for analytics)

**Data Linked to User:**
- All of the above

**Data Used to Track You:**
- None (OPS doesn't sell data or track across apps)

**Third-Party SDKs Privacy:**
- Firebase Analytics: Crash/performance data
- Stripe: Payment information (PCI compliant)
- OneSignal: Push tokens
- Google Sign-In: OAuth tokens
- AWS S3: Image storage

**Age Rating:**
- 4+ (no objectionable content)

**Export Compliance:**
- Uses encryption: Yes (HTTPS, Keychain)
- Qualifies for exemption: Yes (standard encryption only)
- CCATS: Not required for App Store distribution

#### 5. TestFlight Beta Testing

**Internal Testing:**
- Team members (up to 100)
- No review required
- Immediate availability after upload

**External Testing:**
- Public link or email invites (up to 10,000)
- Requires App Store review
- Useful for field testing with real users

**Beta Feedback:**
- Enable in-app feedback
- Monitor crash reports
- Collect performance data

#### 6. App Review Preparation

**Review Notes for Apple:**
```
OPS is a job management app for trade workers (construction, electrical, plumbing, etc.).

Test Account:
Email: demo@opsapp.co
Password: [Provide test account password]
PIN: 1234

The app requires:
1. Account creation (or use test account above)
2. Company association (test account is in demo company)
3. Internet for initial setup (offline mode available after)

Key Features to Test:
- Create project (tap + button on home screen)
- Add tasks to project
- Update task status (tap status badge)
- View calendar schedule
- Manage team members (Settings > Organization > Manage Team)

Subscription Testing:
- Test account has active Business plan
- Payment flows use Stripe SDK (PCI compliant)
- Trial lasts 30 days (test account past trial)

Note: App is designed for use with work gloves on job sites, hence larger touch targets.
```

**Common Rejection Reasons to Avoid:**

1. **Incomplete Demo Account**
   - Ensure test account has sample data
   - All features accessible without payment

2. **Broken Features**
   - Test all primary workflows before submission
   - Verify offline mode works

3. **Misleading Screenshots**
   - Screenshots must match current app version
   - No mockups or concept art

4. **Privacy Policy Issues**
   - Must link to privacy policy on website
   - Policy must explain all data collection

5. **Subscription IAP Issues**
   - Must use Apple's IAP for digital subscriptions
   - Currently OPS uses Stripe (allowed for B2B SaaS)
   - Ensure B2B exemption clearly communicated

#### 7. Submission Process

**Step-by-Step:**

1. **Archive Build**
   ```
   Xcode > Product > Archive
   Wait for archive to complete (~2-5 minutes)
   ```

2. **Validate Archive**
   ```
   Window > Organizer > Archives
   Select archive > Validate App
   Choose distribution method: App Store Connect
   Wait for validation (~2 minutes)
   Fix any errors (code signing, missing symbols, etc.)
   ```

3. **Upload to App Store Connect**
   ```
   Distribute App > App Store Connect > Upload
   Select provisioning profile
   Upload archive (~5-10 minutes depending on build size)
   ```

4. **Processing Time**
   ```
   Apple processes build (~15-60 minutes)
   Receive email when ready for submission
   ```

5. **Submit for Review**
   ```
   App Store Connect > My Apps > OPS
   Select version > Submit for Review
   Answer review questions
   Submit
   ```

6. **Review Timeline**
   ```
   Typical: 1-2 days
   Holiday seasons: 3-5 days
   Check status: App Store Connect
   ```

7. **Release Options**
   ```
   Automatic: Release immediately after approval
   Manual: Release when you choose (recommended for major updates)
   Scheduled: Release on specific date/time
   ```

#### 8. Post-Approval Monitoring

**First 24 Hours:**
- Monitor crash reports in Xcode Organizer
- Check reviews/ratings in App Store Connect
- Verify analytics events flowing to Firebase
- Test subscription purchases with real money (small amount)

**First Week:**
- Daily crash report reviews
- Monitor support emails for issues
- Check server logs for API errors
- Review performance metrics

**Ongoing:**
- Weekly analytics review
- Monthly crash report analysis
- Quarterly update cycle (bug fixes + features)

---

## Data Migrations

### Migration Strategy

OPS uses UserDefaults flags to track one-time data migrations. Each migration runs once per app installation, ensuring data integrity across app versions.

### Migration Pattern

```swift
// OPSApp.swift - onAppear
if !UserDefaults.standard.bool(forKey: "migration_name_v1") {
    await performMigration()
    UserDefaults.standard.set(true, forKey: "migration_name_v1")
}
```

### Implemented Migrations

#### 1. Sample Projects Cleanup (v1.0)

**Flag:** `sample_projects_cleaned`

**Purpose:** Remove demo/sample projects created during onboarding

**Implementation:**
```swift
if !UserDefaults.standard.bool(forKey: "sample_projects_cleaned") {
    await dataController.removeSampleProjects()
    UserDefaults.standard.set(true, forKey: "sample_projects_cleaned")
}
```

**Method:** `DataController.removeSampleProjects()`
- Fetches projects with isSample == true
- Deletes from SwiftData
- Saves context

#### 2. Remote Image Cache Clear (v2)

**Flag:** `remote_cache_cleared_v2`

**Purpose:** Fix duplicate image issue by clearing old cached remote URLs

**Implementation:**
```swift
if !UserDefaults.standard.bool(forKey: "remote_cache_cleared_v2") {
    ImageFileManager.shared.clearRemoteImageCache()
    ImageCache.shared.clear()
    UserDefaults.standard.set(true, forKey: "remote_cache_cleared_v2")
}
```

**Side Effects:**
- Images re-downloaded on next access
- Temporary increase in network usage

#### 3. Project-Level Calendar Events Cleanup (v1)

**Flag:** `project_events_cleaned_v1`

**Purpose:** Delete old project-level CalendarEvents (task-only scheduling migration)

**Implementation:**
```swift
if !UserDefaults.standard.bool(forKey: "project_events_cleaned_v1") {
    await deleteProjectLevelCalendarEvents()
    UserDefaults.standard.set(true, forKey: "project_events_cleaned_v1")
}
```

**Method:** `OPSApp.deleteProjectLevelCalendarEvents()`
```swift
private func deleteProjectLevelCalendarEvents() async {
    let descriptor = FetchDescriptor<CalendarEvent>(
        predicate: #Predicate<CalendarEvent> { event in
            event.taskId == nil  // Project-level events
        }
    )

    let events = try modelContext.fetch(descriptor)
    for event in events {
        modelContext.delete(event)
    }
    try modelContext.save()
}
```

**Impact:**
- Projects now use computed dates from task events
- Simplified scheduling architecture

#### 4. Image Migration (UserDefaults → File System)

**Flag:** Runs always (background migration)

**Purpose:** Move images from UserDefaults (limited size) to file system

**Implementation:**
```swift
Task {
    ImageFileManager.shared.migrateAllImages()
}
```

**Method:** `ImageFileManager.migrateAllImages()`
- Fetches all entities with image data
- Saves to file system
- Updates entity with file path
- Removes from UserDefaults

**Entities Affected:**
- Projects (project photos)
- Clients (profile photos)
- Users (profile photos)

### Migration Safety Checklist

**Before Deploying Migration:**
- [ ] Test on clean install (new user)
- [ ] Test on upgrade (existing user with data)
- [ ] Test with large datasets (500+ records)
- [ ] Verify migration flag persists across app restarts
- [ ] Ensure migration is idempotent (safe to run multiple times)
- [ ] Log migration start/completion
- [ ] Handle errors gracefully (don't crash app)

**Migration Error Handling:**
```swift
do {
    // Perform migration
    try await performMigration()
    UserDefaults.standard.set(true, forKey: "migration_flag")
} catch {
    print("[MIGRATION] ❌ Failed: \(error)")
    // Don't set flag - retry next launch
}
```

### Future Migration Needs

**Potential Migrations:**

1. **SwiftData Schema Changes**
   - Adding new required properties
   - Changing property types
   - Adding/removing relationships

2. **Bubble Field Renames**
   - Update BubbleFields constants
   - Migrate data from old field to new

3. **Status Changes**
   - "Scheduled" → "Booked" (already completed)
   - Future status updates

4. **Subscription Model Changes**
   - Plan tier adjustments
   - Seat count changes
   - Trial duration changes

**Migration Template:**
```swift
// Version X.Y Migration: [Description]
if !UserDefaults.standard.bool(forKey: "migration_name_vX") {
    print("[MIGRATION] Starting: migration_name")

    do {
        // Migration logic here

        print("[MIGRATION] ✅ Complete: migration_name")
        UserDefaults.standard.set(true, forKey: "migration_name_vX")
    } catch {
        print("[MIGRATION] ❌ Failed: \(error)")
        // Consider alerting user or retrying
    }
}
```

---

## Bubble.io Backend Configuration

### Overview

OPS iOS relies on a Bubble.io backend for:
- User authentication and management
- Data synchronization (projects, tasks, clients, etc.)
- Subscription management via Stripe
- Push notification triggers
- Image metadata storage (images stored in S3)

### Base Configuration

**Production URL:** `https://opsapp.co/version-test/api/1.1/`
**API Token:** `f81e9da85b7a12e996ac53e970a52299`

**Environment:**
- Mode: Live (not Development)
- Stripe: Live mode keys
- Domain: opsapp.co (custom domain)

### Required Bubble Plugins

1. **Stripe** (for subscription payments)
   - Version: Latest
   - API Mode: Live
   - Publishable Key: [Set in Bubble plugins]
   - Secret Key: [Set in Bubble plugins]

2. **AWS S3** (for image upload - optional in Bubble if iOS handles directly)
   - Bucket: ops-app-images
   - Region: us-east-2
   - Access Key: [Set in Bubble plugins]

3. **API Connector** (for custom API workflows)
   - Used for: Subscription webhooks, analytics
   - Endpoints: As defined in workflows

### Data Types (Bubble Schema)

Must match iOS SwiftData models exactly:

#### User
```
Fields:
- email (text)
- firstName (text)
- lastName (text)
- phoneNumber (text)
- userType (option set: company, employee)
- company (Company)
- isPlanHolder (yes/no)
- profileImageUrl (text)
- createdDate (date)
- modifiedDate (date)
```

#### Company
```
Fields:
- name (text)
- code (text, unique)
- adminIds (list of texts)
- subscriptionStatus (option set: trial, active, grace, expired, cancelled)
- subscriptionPlan (option set: trial, starter, team, business)
- trialStartDate (date)
- trialEndDate (date)
- subscriptionEnd (date)
- seatGraceStartDate (date)
- maxSeats (number)
- seatedEmployees (list of Users)
- hasPrioritySupport (yes/no)
- stripeCustomerId (text)
- createdDate (date)
- modifiedDate (date)
```

#### Project
```
Fields:
- name (text)
- client (Client)
- company (Company)
- status (option set: accepted, inProgress, completed, cancelled, potential)
- address (text)
- city (text)
- state (text)
- zipCode (text)
- notes (text)
- teamMembers (list of Users)
- imageUrls (list of texts)
- createdDate (date)
- modifiedDate (date)
```

#### ProjectTask
```
Fields:
- title (text)
- project (Project)
- company (Company)
- taskType (TaskType)
- status (option set: booked, inProgress, completed, cancelled, unscheduled)
- notes (text)
- teamMembers (list of Users)
- imageUrls (list of texts)
- createdDate (date)
- modifiedDate (date)
```

#### Client
```
Fields:
- name (text)
- company (Company)
- email (text)
- phoneNumber (text)
- address (text)
- profileImageUrl (text)
- subClients (list of SubClients)
- createdDate (date)
- modifiedDate (date)
```

#### CalendarEvent
```
Fields:
- title (text)
- startDate (date)
- endDate (date)
- taskId (text) - REQUIRED as of Nov 2025
- projectId (text)
- company (Company)
- createdDate (date)
- modifiedDate (date)
```

**Critical:** All CalendarEvents must have taskId set (task-only scheduling migration)

### Option Sets

**Must be byte-identical to iOS enums:**

**subscriptionStatus:**
- trial
- active
- grace
- expired
- cancelled

**subscriptionPlan:**
- trial
- starter
- team
- business
- (priority - not a company plan)
- (setup - not a company plan)

**userType:**
- company
- employee

**projectStatus:**
- accepted
- inProgress
- completed
- cancelled
- potential

**taskStatus:**
- booked (NOT "scheduled" - migration completed Nov 2025)
- inProgress
- completed
- cancelled
- unscheduled

### API Workflows

#### 1. Authentication Workflows

**Endpoint:** `/login`
**Method:** POST
**Parameters:** email, password
**Returns:** User object, token

**Endpoint:** `/signup`
**Method:** POST
**Parameters:** email, password, firstName, lastName, userType
**Returns:** User object, token

**Endpoint:** `/apple_signin`
**Method:** POST
**Parameters:** identityToken, authorizationCode, firstName, lastName
**Returns:** User object, token

**Endpoint:** `/google_signin`
**Method:** POST
**Parameters:** idToken, firstName, lastName
**Returns:** User object, token

#### 2. Subscription Workflows

**Endpoint:** `/create_setup_intent`
**Method:** POST
**Parameters:** company_id, price_id
**Returns:** client_secret, customer_id, ephemeral_key

**Workflow Logic:**
1. Get/create Stripe customer
2. Create setup intent
3. Return client_secret for iOS payment sheet

**Endpoint:** `/complete_subscription`
**Method:** POST
**Parameters:** company_id, price_id, setup_intent_id, promo_code (optional)
**Returns:** subscription_id, subscription_active

**Workflow Logic:**
1. Attach payment method from setup intent to customer
2. Create Stripe subscription with price_id
3. Apply promo code if provided
4. Update company subscriptionStatus = "active"
5. Update company subscriptionPlan
6. Set subscriptionEnd date
7. Return subscription details

**Endpoint:** `/cancel_subscription`
**Method:** POST
**Parameters:** user, company_id, reason, cancelPriority, plan
**Returns:** status

**Workflow Logic:**
1. Cancel Stripe subscription
2. Update company subscriptionStatus = "cancelled"
3. Log cancellation reason

#### 3. Data Sync Workflows

**Endpoint:** `/obj/[data_type]`
**Method:** GET
**Returns:** List of objects modified after constraints:modified_date

**Endpoint:** `/obj/[data_type]/[id]`
**Method:** GET
**Returns:** Single object

**Endpoint:** `/obj/[data_type]`
**Method:** POST
**Parameters:** Object fields
**Returns:** Created object with Bubble ID

**Endpoint:** `/obj/[data_type]/[id]`
**Method:** PATCH
**Parameters:** Fields to update
**Returns:** Updated object

**Endpoint:** `/obj/[data_type]/[id]`
**Method:** DELETE
**Returns:** Success status

### Bubble Workflows for Trial Management

**Critical Workflow:** Trial Expiration Check (runs daily)

**Schedule:** Every day at 12:00 AM UTC

**Logic:**
1. Search for Companies where:
   - subscriptionStatus = "trial"
   - trialEndDate < Current date/time
2. For each company:
   - Set subscriptionStatus = "expired"
   - Send notification to company admins
   - Log expiration event

**Note:** iOS has defensive check in SubscriptionManager that also handles this, but Bubble should be primary source of truth.

### Bubble Workflows for Seat Management

**Workflow:** Update Seated Employees

**Triggered:** When company.seatedEmployees list changes

**Logic:**
1. Count seatedEmployees list
2. If count > maxSeats:
   - Send alert to admins
   - Optionally auto-remove newest non-admin
3. Update modifiedDate

### Stripe Webhook Configuration

**Required Webhooks:**

**customer.subscription.updated**
- Updates company subscriptionStatus if Stripe status changes
- Handles payment failures (set status to "grace")

**customer.subscription.deleted**
- Sets company subscriptionStatus to "cancelled"
- Triggers grace period or lockout

**invoice.payment_failed**
- First failure: Set status to "grace", start 7-day countdown
- Set seatGraceStartDate
- Send notification to admins

**invoice.payment_succeeded**
- Clear grace period
- Set status back to "active"
- Update subscriptionEnd date

**Webhook Endpoint:** `https://opsapp.co/api/1.1/wf/stripe_webhook`

### Field Naming Conventions

**Critical:** BubbleFields constants in iOS must match exactly

**Bubble API returns fields as:**
- `first_name` (snake_case)

**iOS BubbleFields:**
```swift
static let firstName = "first_name"
```

**Common Gotchas:**
- Bubble lists return as arrays of objects with `_id` field
- Dates can be UNIX timestamp OR ISO8601 string
- Empty strings vs. nil (Bubble returns empty string, iOS expects nil)

### Rate Limiting

**Bubble Tier:** Professional (adjust based on actual plan)

**Limits:**
- API calls: 1,000,000/month (adjust based on plan)
- Concurrent connections: 50
- File upload size: 50MB

**iOS RateLimitInterceptor:**
- Delays requests if too frequent
- Implements exponential backoff on 429 errors
- Queues requests during rate limit

### Data Constraints

**Company.code:**
- Must be unique across all companies
- 4-6 characters
- Generated on company creation

**User.email:**
- Must be unique
- Validated as email format

**Subscription Dates:**
- trialEndDate = trialStartDate + 30 days
- subscriptionEnd = updated on each successful payment
- seatGraceStartDate = set on first payment failure

---

## Production Checklist

### Pre-Launch Checklist

#### Infrastructure
- [ ] Firebase project configured (ops-ios-app)
- [ ] Firebase Analytics enabled
- [ ] Google Ads conversion tracking verified
- [ ] OneSignal app created and configured
- [ ] APNs certificates uploaded to OneSignal (Production)
- [ ] Stripe live mode enabled in Bubble
- [ ] AWS S3 bucket created (ops-app-images)
- [ ] AWS IAM user created with S3 permissions
- [ ] Bubble.io production environment live
- [ ] Custom domain configured (opsapp.co)
- [ ] SSL certificate valid

#### Secrets Management
- [ ] AWS credentials added to Xcode build settings (not in code)
- [ ] Bubble API token secured
- [ ] Stripe price IDs verified (live mode)
- [ ] Firebase config file (GoogleService-Info.plist) included
- [ ] Google Sign-In client ID configured
- [ ] OneSignal app ID configured

#### Code Quality
- [ ] All console logs reviewed (remove sensitive data)
- [ ] Error handling in place for all network calls
- [ ] Offline mode tested and working
- [ ] SwiftData migrations tested
- [ ] No force unwraps in production code
- [ ] Memory leaks checked with Instruments
- [ ] Crash reports reviewed (zero critical crashes)

#### Testing
- [ ] Field testing completed (gloves, sunlight, old devices)
- [ ] Offline functionality verified
- [ ] Battery impact measured (<10% per hour active use)
- [ ] All subscription flows tested end-to-end
- [ ] Trial expiration tested
- [ ] Payment success/failure scenarios tested
- [ ] Seat management tested
- [ ] Image upload/download verified
- [ ] Push notifications working (foreground and background)

#### App Store
- [ ] Version and build numbers updated
- [ ] Screenshots created (all required sizes)
- [ ] App icon finalized (1024×1024)
- [ ] App Store description written
- [ ] Keywords optimized
- [ ] Privacy policy published (opsapp.co/privacy)
- [ ] Support URL active (opsapp.co/support)
- [ ] Demo account created for App Review
- [ ] App Review notes prepared
- [ ] Age rating confirmed (4+)
- [ ] Export compliance confirmed

#### Analytics
- [ ] All key events tracking correctly
- [ ] User properties set on authentication
- [ ] Google Ads conversions firing
- [ ] Screen view tracking on all views
- [ ] Subscription purchase events tracking
- [ ] No PII in analytics events

#### Monitoring
- [ ] Error logging strategy implemented
- [ ] Critical alert thresholds defined
- [ ] Support email monitored (support@opsapp.co)
- [ ] Analytics dashboard bookmarked
- [ ] Crash reporting enabled (Xcode Organizer)

### Post-Launch Checklist (First 24 Hours)

- [ ] Monitor crash reports every 4 hours
- [ ] Check App Store reviews/ratings
- [ ] Verify analytics events flowing
- [ ] Test subscription purchase with real payment
- [ ] Monitor support email for issues
- [ ] Check server logs for API errors
- [ ] Verify push notifications delivering
- [ ] Test sync performance with real user data

### Post-Launch Checklist (First Week)

- [ ] Daily crash report review
- [ ] Daily analytics review
- [ ] Daily support email review
- [ ] Monitor subscription conversion rate
- [ ] Check trial-to-paid conversion
- [ ] Verify Stripe webhooks firing correctly
- [ ] Test edge cases reported by users
- [ ] Performance metrics review

### Ongoing Maintenance

**Weekly:**
- [ ] Review analytics trends
- [ ] Check crash reports
- [ ] Monitor support tickets
- [ ] Review App Store reviews

**Monthly:**
- [ ] Performance audit (app launch time, sync speed)
- [ ] Security review (update dependencies)
- [ ] Subscription metrics review
- [ ] User feedback analysis
- [ ] Plan next release features

**Quarterly:**
- [ ] Major app update release
- [ ] iOS version compatibility check
- [ ] Third-party SDK updates
- [ ] Security audit
- [ ] Bubble.io plan review (usage vs. limits)

---

## Appendix

### Quick Reference URLs

**Production:**
- App Store: https://apps.apple.com/app/ops/[APP_ID]
- Website: https://opsapp.co
- Support: https://opsapp.co/support
- Privacy Policy: https://opsapp.co/privacy
- Bubble API: https://opsapp.co/version-test/api/1.1/

**Developer Portals:**
- Apple Developer: https://developer.apple.com
- App Store Connect: https://appstoreconnect.apple.com
- Firebase Console: https://console.firebase.google.com
- Stripe Dashboard: https://dashboard.stripe.com
- OneSignal Dashboard: https://onesignal.com
- AWS Console: https://console.aws.amazon.com
- Bubble Editor: https://bubble.io/[APP_NAME]

### Support Contacts

**Apple Developer Support:**
- Phone: 1-800-633-2152
- Email: developer.apple.com/contact

**Stripe Support:**
- Dashboard: https://dashboard.stripe.com/support
- Email: support@stripe.com

**Firebase Support:**
- Console support chat
- Community: firebase.google.com/support

**Bubble.io Support:**
- Forum: forum.bubble.io
- Email: support@bubble.io

### Critical Metrics Targets

**Performance:**
- App launch: <2 seconds
- Sync time: <5 seconds (100 projects)
- API response: <1 second (95th percentile)
- Image upload: <3 seconds per image

**Reliability:**
- Crash-free rate: >99.5%
- Offline mode success: 100%
- Sync success rate: >99%

**Business:**
- Trial-to-paid conversion: Target 15-25%
- User retention (30 days): Target >60%
- Daily active users: Track weekly
- Monthly recurring revenue (MRR): Track monthly

---

**End of Document**

This deployment and operations guide should be reviewed quarterly and updated with:
- New feature deployment procedures
- Lessons learned from production incidents
- Updated third-party service configurations
- New monitoring and alerting strategies
