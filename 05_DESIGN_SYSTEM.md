# 05 - Design System

**OPS Software Bible - Chapter 5**
**Last Updated**: February 28, 2026
**iOS App Version**: 437 Swift files (76 component files in Views/Components/)
**Purpose**: Complete design system reference for iOS and Android implementations

---

## Table of Contents

1. [Design Philosophy](#1-design-philosophy)
2. [Color Palette](#2-color-palette)
3. [Typography System](#3-typography-system)
4. [Layout & Spacing](#4-layout--spacing)
5. [Component Library](#5-component-library)
6. [Icons & Imagery](#6-icons--imagery)
7. [Status Colors & Badges](#7-status-colors--badges)
8. [Form Patterns](#8-form-patterns)
9. [Card Styling](#9-card-styling)
10. [Button Hierarchy](#10-button-hierarchy)
11. [Field-First Design Principles](#11-field-first-design-principles)
12. [Accessibility Standards](#12-accessibility-standards)
13. [Animation & Motion](#13-animation--motion)
14. [Anti-Patterns](#14-anti-patterns)

---

## 1. Design Philosophy

### Brand Essence: Dependable Field Partner

OPS exists to make trade workers' lives easier through technology that "just works" in any environment—dirt, gloves, sunlight, poor connectivity. Every design decision flows from this core purpose.

### Core Brand Values

#### 1. Built By Trades, For Trades
- Created by actual trade workers who understand real field challenges
- Not designed by "tech people who've never swung a hammer"
- Every feature serves a clear, practical purpose

#### 2. No Unnecessary Complexity
- No features users will never use
- No processes that waste time
- Simple, direct solutions to real problems

#### 3. Reliability Above All
- Works when other technologies fail
- Maintains dependability in harsh conditions
- Offline-first architecture ensures no data loss

#### 4. Field-First Design
- Designed for job sites, not offices
- High contrast for sunlight readability
- Large touch targets for gloved hands
- Minimal text entry requirements

#### 5. Time Is Money
- Every minute managing software is a minute not billing
- Quick actions, minimal taps
- Respect user's time above all else

### Steve Jobs Design Principles (Applied)

#### Simplicity as Ultimate Sophistication
> "Simple can be harder than complex: You have to work hard to get your thinking clean to make it simple."

- Deeply understand user needs to eliminate unnecessary elements
- Every screen should have one primary purpose
- Progressive disclosure reveals complexity only when needed

#### Human-Centered, Not Technology-Driven
> "Start with the customer experience and work backwards to the technology."

- Interface adapts to natural human behavior in field
- Technology serves the user, not the other way around
- Always consider the context: gloves, sunlight, urgency

#### Obsessive Attention to Detail
- Perfect every aspect, no matter how small
- Anticipate edge cases and friction points
- Consistency is paramount—similar things look identical everywhere

---

## 2. Color Palette

### Production Color Values (Assets.xcassets)

**CRITICAL**: These are the ACTUAL production values from `Assets.xcassets`. OPSStyle.swift comments are incorrect in some cases (e.g., AccentPrimary is NOT orange).

#### Primary Colors

```swift
// Primary Accent (Steel Blue) - #597794
// RGB: 89, 119, 148
// Used for: Interactive elements, primary buttons, clickable icons
static let primaryAccent = Color("AccentPrimary")
```

```swift
// Secondary Accent - DEPRECATED (now matches primaryAccent #597794)
// RGB: 89, 119, 148
// Previously was Amber/Gold (#C4A868), now identical to primaryAccent.
// Will be removed after active-state migration.
static let secondaryAccent = Color("AccentSecondary")
```

#### Background Colors

```swift
// Background (Near Black) - #0A0A0A
// RGB: 10, 10, 10
// Used for: Main app background
// Benefits: Reduces glare, conserves battery, high contrast
static let background = Color("Background")
```

```swift
// Card Background (Dark Gray) - #141414
// RGB: 20, 20, 20
// Used for: Card surfaces, content containers
static let cardBackground = Color("CardBackground")
```

```swift
// Card Background Dark - #0D0D0D (computed)
// Used for: Darker card variants, elevated surfaces
// Note: Often used with .opacity(0.8) in iOS
static let cardBackgroundDark = Color("CardBackgroundDark")
```

#### Text Colors

```swift
// Primary Text (Off-White) - #E5E5E5
// RGB: 229, 229, 229
// Used for: Main content, headers, primary information
// NOT pure white (#FFFFFF) for reduced eye strain
static let primaryText = Color("TextPrimary")
```

```swift
// Secondary Text (Medium Gray) - #999999
// RGB: 153, 153, 153
// Used for: Supporting text, labels, captions
static let secondaryText = Color("TextSecondary")
```

```swift
// Tertiary Text (Dark Gray) - #666666
// RGB: 102, 102, 102
// Used for: Hints, disabled text, less important info
static let tertiaryText = Color("TextTertiary")
```

#### Status Colors

```swift
// Success (Muted Olive-Green) - #A5B368
// RGB: 165, 179, 104
// Used for: Completed status, success messages
static let successStatus = Color("StatusSuccess")
```

```swift
// Warning (Amber Gold) - #C4A868
// RGB: 196, 168, 104
// Used for: Warning messages, attention needed
static let warningStatus = Color("StatusWarning")
```

```swift
// Error (Deep Brick Red) - #93321A
// RGB: 147, 50, 26
// Used for: Errors, destructive actions, critical warnings
static let errorStatus = Color("StatusError")
```

#### Project Status Colors

```swift
// RFQ (Gray) - Exact value TBD
static let rfqStatus = Color("StatusRFQ")

// Estimated (Orange/Amber) - Exact value TBD
static let estimatedStatus = Color("StatusEstimated")

// Accepted (Teal/Blue) - #9DB582
// RGB: 157, 181, 130
static let acceptedStatus = Color("StatusAccepted")

// In Progress (Purple/Mauve) - #8195B5
// RGB: 129, 149, 181
static let inProgressStatus = Color("StatusInProgress")

// Completed (Purple/Lavender) - #B58289
// RGB: 181, 130, 137
static let completedStatus = Color("StatusCompleted")

// Closed (Gray) - Exact value TBD
static let closedStatus = Color("StatusClosed")

// Archived (Dark Gray) - Exact value TBD
static let archivedStatus = Color("StatusArchived")
```

#### Border & Overlay Colors

```swift
// Card Border (White 10% opacity)
// Standard border for most cards
static let cardBorder = Color.white.opacity(0.10)

// Card Border Subtle (White 8% opacity)
// For less prominent cards and subtle divisions
static let cardBorderSubtle = Color.white.opacity(0.08)

// Input Field Border (White 10% opacity)
// For text fields, form controls, avatar circles
static let inputFieldBorder = Color.white.opacity(0.10)

// Button Border (White 15% opacity)
// For secondary action buttons
static let buttonBorder = Color.white.opacity(0.15)

// Dark Border (Black 50% opacity)
// Used by GracePeriodBanner
static let darkBorder = Color.black.opacity(0.5)

// Separator (White 10% opacity)
// For divider lines
static let separator = Color.white.opacity(0.10)
```

### Color Usage Rules

#### Primary Accent Usage
- **Must be < 10% of visible UI colors**
- Use for:
  - Primary buttons and call-to-action elements
  - Clickable icons and interactive indicators
  - Main navigation elements
  - Tab bar active state
- Never use for:
  - Large backgrounds
  - Non-interactive decorations
  - Text (except links/buttons)

#### Secondary Accent Usage
- **DEPRECATED**: `secondaryAccent` now matches `primaryAccent` (#597794). It will be removed after the active-state migration.
- Previously was ONLY used for active projects/active state indicators.
- New code should use `primaryAccent` directly instead of `secondaryAccent`.

#### Background Usage
- **CRITICAL**: Never use `.opacity()` modifiers on background colors
- Use solid colors from the palette
- Exception: `cardBackgroundDark.opacity(0.8)` is pre-defined pattern

```swift
// ✅ CORRECT
.background(OPSStyle.Colors.background)
.background(OPSStyle.Colors.cardBackground)

// ❌ WRONG
.background(OPSStyle.Colors.background.opacity(0.5))
```

#### Text Color Hierarchy

```swift
// Primary: Main content
Text("Project Name")
    .foregroundColor(OPSStyle.Colors.primaryText)

// Secondary: Labels, supporting info
Text("Created by:")
    .foregroundColor(OPSStyle.Colors.secondaryText)

// Tertiary: Hints, disabled
Text("No projects found")
    .foregroundColor(OPSStyle.Colors.tertiaryText)
```

---

## 3. Typography System

### Font Families

#### Primary: Mohave
- **Weights**: Light, Regular, Medium, SemiBold, Bold
- **Use for**: Titles, body text, headings, status badges, most UI elements
- **Characteristics**: Modern, clean, highly legible at all sizes
- **Field-optimized**: Excellent readability in bright sunlight

#### Supporting: Kosugi
- **Weight**: Regular (with optional .weight() modifier)
- **Use for**: Subtitles, captions, labels, buttons, section labels, supporting text
- **Characteristics**: Excellent small-size legibility, provides visual contrast
- **Purpose**: Creates clear hierarchy when paired with Mohave

#### Display: Bebas Neue
- **Weight**: Regular
- **Use for**: Special branding moments ONLY (not regular UI)
- **Characteristics**: Condensed display font
- **Usage**: Very rare—reserved for marketing materials

### Typography Scale

#### Headers and Titles

```swift
// Large Title - Mohave Bold, 32pt
static let largeTitle = Font.custom("Mohave-Bold", size: 32)
// Use for: Main screen titles, hero text

// Title - Mohave SemiBold, 28pt
static let title = Font.custom("Mohave-SemiBold", size: 28)
// Use for: Section titles, dialog headers

// Subtitle - Kosugi Regular, 22pt
static let subtitle = Font.custom("Kosugi-Regular", size: 22)
// Use for: Section subtitles, supporting headers
```

#### Body Text

```swift
// Body - Mohave Regular, 16pt
static let body = Font.custom("Mohave-Regular", size: 16)
// Use for: Main content text, descriptions, paragraphs

// Body Bold - Mohave Medium, 16pt
static let bodyBold = Font.custom("Mohave-Medium", size: 16)
// Use for: Emphasized content, important labels

// Body Emphasis - Mohave SemiBold, 16pt
static let bodyEmphasis = Font.custom("Mohave-SemiBold", size: 16)
// Use for: Strong emphasis, key information

// Small Body - Mohave Light, 14pt
static let smallBody = Font.custom("Mohave-Light", size: 14)
// Use for: Secondary content, metadata
```

#### Supporting Text

```swift
// Caption - Kosugi Regular, 14pt
static let caption = Font.custom("Kosugi-Regular", size: 14)
// Use for: Labels, supporting text, metadata

// Caption Bold - Kosugi Regular, 14pt with .weight(.semibold)
static let captionBold = Font.custom("Kosugi-Regular", size: 14)
// Note: Apply .weight(.semibold) modifier in usage
// Use for: Section headers (ALL CAPS), emphasized labels

// Small Caption - Kosugi Regular, 12pt
static let smallCaption = Font.custom("Kosugi-Regular", size: 12)
// Use for: Timestamps, fine print, tertiary information
```

#### Card Typography

```swift
// Card Title - Mohave Medium, 18pt
static let cardTitle = Font.custom("Mohave-Medium", size: 18)
// Use for: Card headers, primary card content

// Card Subtitle - Kosugi Regular, 15pt
static let cardSubtitle = Font.custom("Kosugi-Regular", size: 15)
// Use for: Card supporting text, secondary card content

// Card Body - Mohave Regular, 14pt
static let cardBody = Font.custom("Mohave-Regular", size: 14)
// Use for: Card description text, card details
```

#### Headings

```swift
// Heading - Mohave Medium, 20pt
static let heading = Font.custom("Mohave-Medium", size: 20)
// Use for: Section headings, medium-prominence titles

// Heading Large - Mohave SemiBold, 24pt
static let headingLarge = Font.custom("Mohave-SemiBold", size: 24)
// Use for: Prominent section headings
```

#### Display

```swift
// Display Large - Mohave Bold, 48pt
static let displayLarge = Font.custom("Mohave-Bold", size: 48)
// Use for: Hero numbers, large data displays

// Display XL - Mohave Bold, 60pt
static let displayXL = Font.custom("Mohave-Bold", size: 60)
// Use for: Splash/loading screen numbers, maximum visual impact
```

#### UI Elements

```swift
// Button - Kosugi Regular, 14pt — ALL CAPS via .textCase(.uppercase)
static let button = Font.custom("Kosugi-Regular", size: 14)
// Use for: Button labels, primary actions

// Small Button - Kosugi Regular, 12pt — ALL CAPS via .textCase(.uppercase)
static let smallButton = Font.custom("Kosugi-Regular", size: 12)
// Use for: Compact buttons, secondary actions

// Section Label - Kosugi Regular, 12pt — ALL CAPS, tracked
static let sectionLabel = Font.custom("Kosugi-Regular", size: 12)
// Use for: Section labels, grouped content headers

// Status - Mohave Medium, 12pt
static let status = Font.custom("Mohave-Medium", size: 12)
// Use for: Status badges, tags, pills
```

### Typography Rules

#### Mandatory Standards

```swift
// ✅ CORRECT
Text("Project Title").font(OPSStyle.Typography.title)
Text("Description").font(OPSStyle.Typography.body)
Text("Status").font(OPSStyle.Typography.status)

// ❌ WRONG - Will be rejected
Text("Project Title").font(.title)                    // System font
Text("Description").font(.body)                       // System font
Text("Status").font(.system(size: 12))               // Hardcoded
```

#### Best Practices

1. **Consistency**: Same components must use same typography everywhere
2. **Line Spacing**: Maintain sufficient line spacing for field readability
3. **Dynamic Type**: Test all text at maximum accessibility sizes
4. **Case Conventions**:
   - Sentence case for most text (not ALL CAPS)
   - Section headers use `.textCase(.uppercase)` programmatically
   - Button text typically sentence case or Title Case

#### Field-Optimized Sizing

- **Minimum readable size**: 14pt
- **Preferred body size**: 16pt
- **Important information**: 18-20pt
- **Touch target labels**: 16pt minimum

---

## 4. Layout & Spacing

### 8-Point Grid System

**CRITICAL**: All spacing MUST be multiples of 8pt for consistency.

```swift
// Standard spacing units
static let spacing1 = 4.0     // Half unit (use sparingly)
static let spacing2 = 8.0     // Base unit
static let spacing2_5 = 12.0  // Between spacing2 and spacing3
static let spacing3 = 16.0    // Standard spacing
static let spacing3_5 = 20.0  // Between spacing3 and spacing4
static let spacing4 = 24.0    // Section spacing
static let spacing5 = 32.0    // Large spacing
```

```swift
// ✅ CORRECT: 8pt multiples
.padding(8)
.padding(16)
.padding(24)
.spacing(16)

// ❌ WRONG: Non-8pt values
.padding(15)
.spacing(10)
.padding(18)
```

### Touch Targets

#### Size Standards

```swift
// Touch target minimums
static let touchTargetMin = 44.0        // Apple HIG minimum
static let touchTargetStandard = 56.0   // OPS standard
static let touchTargetLarge = 64.0      // Primary actions
```

#### Field-Optimized Targets

- **Minimum**: 44×44pt (accessibility requirement)
- **Standard**: 56×56pt (OPS default for all interactive elements)
- **Large**: 64×64pt (primary actions, critical buttons)
- **Glove Test**: All targets must work with work gloves (reduced precision)

```swift
// ✅ CORRECT: Field-friendly sizing
Button("Create Project") { }
    .frame(width: 56, height: 56)

// ❌ WRONG: Too small for gloves
Button("Delete") { }
    .frame(width: 30, height: 30)  // Too small!
```

### Corner Radius

```swift
// Corner radius variants
static let cornerRadius = 3.0         // Standard UI elements
static let buttonRadius = 3.0         // Buttons
static let smallCornerRadius = 2.0    // Badges, small elements
static let cardCornerRadius = 4.0     // Cards, larger containers
static let largeCornerRadius = 4.0    // Modals, sheets
```

### Padding & Margins

```swift
// Content padding preset
static let contentPadding = EdgeInsets(
    top: 16,
    leading: 16,
    bottom: 16,
    trailing: 16
)

// Screen margins
static let screenMargin: CGFloat = 20      // Screen edge margins
static let cardPadding: CGFloat = 16       // Inside card padding
static let cardSpacing: CGFloat = 16       // Between cards
static let sectionSpacing: CGFloat = 24    // Between sections
```

### Screen Organization

#### Vertical Hierarchy

```swift
VStack {
    // 1. Header at top
    AppHeader(title: "Projects")

    // 2. Content in middle (scrollable)
    ScrollView {
        // Content
    }

    // 3. Primary actions at bottom (thumb-accessible)
    Spacer()
    PrimaryButton(title: "Create Project") { }
        .padding(.bottom, 20)
}
```

**Rationale**: Critical actions at bottom are easier to reach with thumb while holding phone.

### Shadows

```swift
// Shadow presets
enum Shadow {
    // Card shadow - subtle depth
    static let card = (
        color: Color.black.opacity(0.1),
        radius: 4.0,
        x: 0.0,
        y: 2.0
    )

    // Elevated shadow - medium depth
    static let elevated = (
        color: Color.black.opacity(0.2),
        radius: 8.0,
        x: 0.0,
        y: 4.0
    )

    // Floating shadow - high depth
    static let floating = (
        color: Color.black.opacity(0.3),
        radius: 12.0,
        x: 0.0,
        y: 6.0
    )
}
```

### Opacity Presets

```swift
enum Opacity {
    static let subtle = 0.1    // Disabled, very light overlays
    static let light = 0.3     // Light overlays
    static let medium = 0.5    // Medium overlays
    static let strong = 0.7    // Strong overlays
    static let heavy = 0.9     // Almost opaque
}
```

---

## 5. Component Library

### Component Philosophy

#### Key Principles

1. **Reuse Over Recreation**: Always use existing components
2. **OPSStyle Compliance**: All components use OPSStyle constants
3. **Single Responsibility**: Each component does one thing well
4. **Field-Optimized**: Large targets, high contrast, glove-friendly

### Button Components

#### Primary Button

```swift
// Usage
PrimaryButton(title: "Save Project", action: saveProject)

// Properties
- Background: OPSStyle.Colors.primaryAccent
- Text: White
- Height: 56pt (touchTargetStandard)
- Font: OPSStyle.Typography.button
- Full width by default
```

#### Secondary Button

```swift
// Usage
SecondaryButton(title: "Cancel", action: dismiss)

// Properties
- Background: OPSStyle.Colors.cardBackground
- Text: OPSStyle.Colors.primaryAccent
- Border: 2pt, primaryAccent
- Height: 56pt
- Font: OPSStyle.Typography.button
```

#### Destructive Button

```swift
// Usage
DestructiveButton(title: "Delete Project", action: deleteProject)

// Properties
- Background: OPSStyle.Colors.errorStatus
- Text: White
- Height: 56pt
- Font: OPSStyle.Typography.button
```

#### Icon Button

```swift
// Usage
IconButton(icon: OPSStyle.Icons.plusCircle, action: addTask, size: 60)

// Properties
- Circular background
- Size: 44pt minimum (customizable)
- Default tint: primaryAccent
- Icon size: 40% of button size
```

#### Text Button

```swift
// Usage
Button("Skip") { /* action */ }
    .font(OPSStyle.Typography.button)
    .foregroundColor(OPSStyle.Colors.primaryAccent)

// Properties
- No background
- Text color: primaryAccent
- Font: button
- Used for tertiary actions
```

### Card Components

#### Standard Card

```swift
// Usage
StandardCard {
    VStack {
        Text("Card Title")
        Text("Card content")
    }
}

// Properties
- Background: cardBackground
- Border: cardBorder, 1pt
- Padding: 16pt all sides
- Corner radius: 4pt (cardCornerRadius)
```

#### Elevated Card

```swift
// Usage
ElevatedCard {
    // Content
}

// Properties
- Background: cardBackgroundDark
- Shadow: card shadow preset
- Padding: 16pt
- Corner radius: 4pt (cardCornerRadius)
```

#### Interactive Card

```swift
// Usage
InteractiveCard(action: openDetails) {
    // Card content
}

// Properties
- Tappable with subtle press animation
- Scale effect: 0.98 when pressed
- Same styling as StandardCard
- Includes ScaleButtonStyle for animation
```

#### Accent Card

```swift
// Usage
AccentCard(accentColor: OPSStyle.Colors.primaryAccent) {
    Text("Important message")
}

// Properties
- Colored left border (4pt width)
- Background: cardBackground
- Padding: 16pt
- Corner radius: 4pt (cardCornerRadius)
```

### Form Components

#### Form Text Field

```swift
// Usage
FormTextField(title: "Project Name", text: $projectName)

// Properties
- Section label (uppercase)
- Input field with cardBackground
- Font: body
- Keyboard type configurable
- 8pt spacing between label and field
```

#### Form Text Editor

```swift
// Usage
FormTextEditor(title: "Notes", text: $notes, height: 150)

// Properties
- Multi-line text input
- Section label (uppercase)
- Customizable height
- Font: body
- Background: cardBackground
```

#### Form Toggle

```swift
// Usage
FormToggle(
    title: "Enable Notifications",
    subtitle: "Receive project updates",
    isOn: $notificationsEnabled
)

// Properties
- Title and optional subtitle
- Tint: primaryAccent
- Vertical padding: 12pt
```

#### Form Radio Options

```swift
// Usage
FormRadioOptions(
    title: "Project Status",
    options: Status.allCases,
    selection: $selectedStatus,
    label: { $0.displayName }
)

// Properties
- Generic for any Hashable type
- Radio circle indicators
- Custom label formatter
- Color: primaryAccent
```

### List & Display Components

#### Info Row

```swift
// Usage
InfoRow(
    icon: OPSStyle.Icons.envelope,
    title: "Email",
    value: client.emailAddress,
    action: { /* open email */ }
)

// Properties
- Icon (24pt width)
- Title and value stacked vertically
- Optional chevron for tappable rows
- Font: caption (title), body (value)
```

#### Status Badge

```swift
// Usage
StatusBadge(status: project.status)

// Properties
- Uppercase text
- Font: status (12pt)
- White text
- Colored background (status-specific)
- Padding: 12pt horizontal, 6pt vertical
- Corner radius: 6pt
```

#### Icon Badge

```swift
// Usage
IconBadge(
    icon: OPSStyle.Icons.checkmark,
    color: OPSStyle.Colors.successStatus
)

// Properties
- Circular badge
- Size: 24pt (customizable)
- Icon: 50% of badge size
- White icon on colored background
```

#### User Avatar

```swift
// Usage
UserAvatar(user: currentUser, size: 40)

// Properties
- Async image loading
- Fallback to initials
- Circular clipping
- Color from user.userColor or default
- Size: customizable (default 40pt)
```

#### Empty State View

```swift
// Usage
EmptyStateView(
    icon: "folder.badge.plus",
    title: "No Projects",
    message: "Create your first project to get started",
    actionTitle: "Create Project",
    action: createProject
)

// Properties
- Large icon (48pt)
- Title (bodyBold)
- Message (caption, multiline)
- Optional action button
- Padding: 40pt
```

### Specialized Components

#### Search Bar

```swift
// Usage
SearchBar(text: $searchText, placeholder: "Search projects...")

// Properties
- Magnifying glass icon
- Clear button when text present
- Background: cardBackground
- Font: body
- Corner radius: standard
```

#### Collapsible Section

```swift
// Usage
CollapsibleSection(
    title: "Closed",
    count: closedProjects.count,
    isExpanded: $showClosed
) {
    // Content only visible when expanded
}

// Properties
- Pattern: [ CLOSED ] ------------ [ 5 ]
- Chevron indicator (up/down)
- Spring animation (0.3s, 0.7 damping)
- Font: captionBold
```

#### Loading Overlay

```swift
// Usage
if isLoading {
    LoadingView(message: "Loading projects...")
}

// Properties
- Full screen overlay
- Circular progress indicator (1.2x scale)
- Message below spinner
- Background: 90% opacity black
- Z-index: 999
```

### Navigation Components

#### Segmented Control

```swift
// Usage
SegmentedControl(
    options: [CalendarViewType.month, CalendarViewType.week],
    selection: $viewType,
    label: { $0.displayName }
)

// Properties
- Generic for any Hashable type
- Active: white text, primaryAccent background
- Inactive: secondaryText, clear background
- Font: bodyBold
```

---

## 6. Icons & Imagery

### Icon System

OPS uses SF Symbols exclusively, accessed through `OPSStyle.Icons` constants.

**CRITICAL**: Never hardcode SF Symbol strings. Always use OPSStyle.Icons constants.

```swift
// ✅ CORRECT
Image(systemName: OPSStyle.Icons.calendar)
Image(systemName: OPSStyle.Icons.personFill)

// ❌ WRONG
Image(systemName: "calendar")           // Hardcoded
Image(systemName: "person.fill")        // Hardcoded
```

### Semantic Icons (OPS Domain)

These are the standardized icons for core OPS concepts. Always use these for their designated purpose.

#### Core Entities

```swift
static let project = "folder.fill"                  // Projects
static let task = "checklist"                       // Tasks
static let taskType = "tag.fill"                    // Task Types
static let client = "person.circle.fill"            // Clients
static let subClient = "person.2.fill"              // Sub-clients
static let teamMember = "person.fill"               // Team Members
static let crew = "person.3.fill"                   // Crews/Teams
```

#### Scheduling & Time

```swift
static let schedule = "calendar.badge.clock"        // Scheduling
static let deadline = "calendar.badge.exclamationmark" // Deadlines
static let duration = "clock.fill"                  // Duration/Time
```

#### Location & Site

```swift
static let jobSite = "location.fill"                // Job Sites
static let address = "mappin.and.ellipse"           // Addresses
```

#### Content & Media

```swift
static let notes = "note.text"                      // Notes
static let description = "text.alignleft"           // Description
static let photos = "photo.on.rectangle"            // Photos
static let documents = "doc.text.fill"              // Documents
```

#### Actions

```swift
static let add = "plus.circle.fill"                 // Add/Create
static let edit = "pencil.circle.fill"              // Edit
static let delete = "trash.fill"                    // Delete
static let sync = "arrow.triangle.2.circlepath"     // Sync
static let share = "square.and.arrow.up"            // Share
static let filter = "line.horizontal.3.decrease.circle" // Filter
static let sort = "arrow.up.arrow.down.circle"      // Sort
static let addContact = "person.crop.circle.badge.plus" // Add from Contacts
static let addProject = "folder.badge.plus"         // Create Project
```

#### Status & State

```swift
static let complete = "checkmark.circle.fill"       // Complete
static let incomplete = "circle"                    // Incomplete
static let inProgress = "clock.arrow.circlepath"    // In Progress
static let alert = "exclamationmark.triangle.fill"  // Alerts/Warnings
static let error = "xmark.octagon.fill"             // Errors
static let info = "info.circle.fill"                // Information
```

#### System

```swift
static let settings = "gearshape.fill"              // Settings
static let search = "magnifyingglass"               // Search
static let menu = "line.3.horizontal"               // Menu
static let close = "xmark"                          // Close/Dismiss
static let back = "chevron.left"                    // Back navigation
static let forward = "chevron.right"                // Forward navigation
```

### Icon Color Rules

```swift
// Clickable/Interactive icons
Image(systemName: OPSStyle.Icons.plusCircle)
    .foregroundColor(OPSStyle.Colors.primaryAccent)

// Non-clickable/Informational icons
Image(systemName: OPSStyle.Icons.calendar)
    .foregroundColor(OPSStyle.Colors.primaryText)

// Status icons
Image(systemName: OPSStyle.Icons.checkmarkCircle)
    .foregroundColor(OPSStyle.Colors.successStatus)
```

### Icon Sizing

```swift
// Standard icon sizes (OPSStyle.Layout.IconSize)
- XS: 12pt (tiny indicators)
- SM: 16pt (inline icons, captions)
- MD: 20pt (standard icons)
- LG: 24pt (section header icons)
- XL: 32pt (action icons, prominent UI)
- XXL: 48pt (large decorative icons, empty states)

// Tab bar icon size
- tabBarIconSize: 28pt
```

---

## 7. Status Colors & Badges

### Project Status System

Each project status has a specific color that conveys meaning at a glance.

```swift
// RFQ (Request for Quote) - Gray
static let rfqStatus = Color("StatusRFQ")
// Meaning: Initial inquiry, not yet estimated

// Estimated - Orange/Amber
static let estimatedStatus = Color("StatusEstimated")
// Meaning: Quote provided, awaiting client decision

// Accepted - Teal/Blue (#9DB582)
static let acceptedStatus = Color("StatusAccepted")
// Meaning: Client accepted, ready to schedule

// In Progress - Purple/Mauve (#8195B5)
static let inProgressStatus = Color("StatusInProgress")
// Meaning: Work underway, actively being completed

// Completed - Purple/Lavender (#B58289)
static let completedStatus = Color("StatusCompleted")
// Meaning: Work finished, ready for final invoicing

// Closed - Gray
static let closedStatus = Color("StatusClosed")
// Meaning: Fully invoiced and paid

// Archived - Dark Gray
static let archivedStatus = Color("StatusArchived")
// Meaning: No longer active, archived for records
```

### Task Status Colors

```swift
// Unscheduled - Default text color
// Meaning: Task exists but not yet scheduled

// Scheduled/Booked - Calendar color
// Meaning: Task has assigned date/time

// In Progress - Same as project in progress
// Meaning: Work actively underway

// Completed - Same as project completed
// Meaning: Task finished

// Cancelled - Red/Error color
// Meaning: Task will not be completed
```

### General Status Colors

```swift
// Success - Muted Green
static let successStatus = Color("StatusSuccess")
// Use for: Confirmations, completed actions, positive states

// Warning - Amber (#C4A868)
static let warningStatus = Color("StatusWarning")
// Use for: Attention needed, non-critical issues, cautions

// Error - Deep Brick Red (#93321A)
static let errorStatus = Color("StatusError")
// Use for: Errors, failures, critical issues, destructive actions
```

### Status Badge Component

```swift
// Standard usage
StatusBadge(status: project.status)

// Rendered as:
[ RFQ ]      // Gray background, white text
[ ESTIMATED ] // Orange background, white text
[ ACCEPTED ]  // Teal background, white text
etc.

// Properties
- Text: ALL CAPS status name
- Font: Mohave Medium 12pt
- Padding: 12pt horizontal, 6pt vertical
- Corner radius: 6pt
- White text on colored background
```

### Status Badge Patterns

#### In Cards

```swift
HStack {
    StatusBadge(status: project.status)

    Spacer()

    Text(project.name)
        .font(OPSStyle.Typography.cardTitle)
}
```

#### In Headers

```swift
VStack(alignment: .leading) {
    StatusBadge(status: project.status)

    Text(project.name)
        .font(OPSStyle.Typography.title)
}
```

#### Client Project Badges

Visual summary showing count of projects in each status:

```swift
// Renders as: [3] [2] [5]
// Where each badge is colored by status
ClientProjectBadges(client: client)

// Properties
- Shows only non-closed, non-archived projects
- Count in square brackets
- Small font (12pt)
- Colored by status
- 6pt spacing between badges
```

---

## 8. Form Patterns

### Form Sheet Architecture

OPS uses full-screen form sheets with consistent patterns across all entity types (Project, Task, Client, etc.).

#### Standard Form Sheet Structure

```swift
VStack {
    // 1. Header (fixed at top)
    HStack {
        Button("Cancel") { dismiss() }
        Spacer()
        Text("New Project")
            .font(OPSStyle.Typography.title)
        Spacer()
        Button("Save") { save() }
    }
    .padding()

    // 2. Scrollable content
    ScrollView {
        VStack(spacing: 24) {
            // Form sections
        }
        .padding()
    }

    // 3. Bottom actions (if needed)
    // Save/Cancel buttons, secondary actions
}
.background(OPSStyle.Colors.background)
```

### Progressive Disclosure Pattern

Complex forms use optional section pills to reveal additional fields only when needed.

#### Optional Section Pills

```swift
// Collapsed state
OptionalSectionPill(
    title: "Add Notes",
    icon: OPSStyle.Icons.notes,
    isExpanded: $showNotes
)

// When tapped:
// 1. Pill disappears
// 2. Full section expands below
// 3. Auto-scroll positions section at top
// 4. Section has "Remove" button to collapse back

// Properties
- Border: secondaryText opacity 1.0
- Font: captionBold
- Padding: 12pt
- Corner radius: 4pt (cardCornerRadius)
- Icon + text + chevron
```

#### Dynamic Section Reordering

When a pill is tapped to open its section:
1. Section automatically moves to top of form
2. Smooth scroll animation with delay
3. Section expands with spring animation
4. User can edit content
5. "Remove" button collapses section back to pill

### Form Input Patterns

#### Standard Text Input

```swift
VStack(alignment: .leading, spacing: 8) {
    Text("PROJECT NAME")
        .font(OPSStyle.Typography.captionBold)
        .foregroundColor(OPSStyle.Colors.secondaryText)
        .textCase(.uppercase)

    TextField("Enter project name", text: $projectName)
        .font(OPSStyle.Typography.body)
        .foregroundColor(OPSStyle.Colors.primaryText)
        .padding(12)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isFocused ? OPSStyle.Colors.primaryAccent : Color.white.opacity(0.1),
                    lineWidth: 1
                )
        )
}
```

#### Multi-line Text Input

```swift
VStack(alignment: .leading, spacing: 8) {
    Text("NOTES")
        .font(OPSStyle.Typography.captionBold)
        .foregroundColor(OPSStyle.Colors.secondaryText)

    TextEditor(text: $notes)
        .font(OPSStyle.Typography.body)
        .foregroundColor(OPSStyle.Colors.primaryText)
        .frame(height: 120)
        .padding(8)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
}
```

#### Border Visual Hierarchy

**Structural Elements** (Pills, Section Containers):
- Border: `Color.white.opacity(0.10)` or `secondaryText`
- Purpose: Group content, show boundaries
- More visible to indicate structure

**Input Elements** (TextFields, TextEditors):
- Border: `Color.white.opacity(0.1)` (unfocused)
- Border: `primaryAccent` (focused)
- Purpose: Subtle until interaction
- Darker to keep focus on content

### Form Card Grouping

All related inputs are grouped into single card sections:

```swift
VStack(alignment: .leading, spacing: 16) {
    // Card section header
    Text("BASIC INFORMATION")
        .font(OPSStyle.Typography.captionBold)
        .foregroundColor(OPSStyle.Colors.secondaryText)

    // Card with multiple inputs
    VStack(alignment: .leading, spacing: 16) {
        FormTextField(title: "Name", text: $name)
        FormTextField(title: "Email", text: $email)
        FormTextField(title: "Phone", text: $phone)
    }
    .padding(16)
    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
    .cornerRadius(8)
    .overlay(
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.white.opacity(0.1), lineWidth: 1)
    )
}
```

### Button Placement

#### Bottom-Anchored Actions

```swift
VStack {
    // Form content (scrollable)

    Spacer()

    // Primary actions at bottom
    HStack(spacing: 16) {
        SecondaryButton(title: "Cancel", action: dismiss)
        PrimaryButton(title: "Save", action: save)
    }
    .padding()
}
```

#### Secondary Actions

```swift
// Placed below primary actions
VStack {
    // Primary Save/Cancel

    // Secondary actions
    Button("Copy from Project") { }
        .font(OPSStyle.Typography.caption)
        .foregroundColor(OPSStyle.Colors.primaryAccent)

    Button("Import from Contacts") { }
        .font(OPSStyle.Typography.caption)
        .foregroundColor(OPSStyle.Colors.primaryAccent)
}
```

---

## 9. Card Styling

### Standard Card Pattern

The canonical card styling used throughout OPS:

```swift
VStack {
    // Card content
}
.padding(16)
.background(
    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
        .fill(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
)
```

### Card Styling Rules

#### Critical Requirements

1. **Section Headers OUTSIDE Cards**: Never put section headers inside card backgrounds

```swift
// ✅ CORRECT
VStack(alignment: .leading, spacing: 8) {
    Text("TEAM MEMBERS")
        .font(OPSStyle.Typography.captionBold)
        .foregroundColor(OPSStyle.Colors.secondaryText)

    VStack {
        // Card content
    }
    .padding(16)
    .cardStyle()
}

// ❌ WRONG
VStack {
    Text("TEAM MEMBERS")  // Don't put header inside card
    // Content
}
.cardStyle()
```

2. **Never Nest Cards**: No double backgrounds

```swift
// ❌ WRONG
VStack {
    VStack {
        // Inner card
    }
    .cardStyle()
}
.cardStyle()  // Don't nest cards!
```

3. **Consistent Padding**: 16pt for card content, 14pt vertical / 16pt horizontal for compact cards

```swift
// Standard card padding
.padding(16)

// Compact card padding
.padding(.vertical, 14)
.padding(.horizontal, 16)
```

### Card Background Variants

```swift
// Standard card background (most common)
.background(OPSStyle.Colors.cardBackground)

// Dark card background (elevated cards)
.background(OPSStyle.Colors.cardBackgroundDark)

// Dark card with opacity (common pattern)
.background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
```

### Card Border Variants

```swift
// Standard border (most common)
.stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
// = Color.white.opacity(0.10)

// Subtle border (less prominent cards)
.stroke(OPSStyle.Colors.cardBorderSubtle, lineWidth: 1)
// = Color.white.opacity(0.08)

// No border (rare, only when card already has strong visual boundary)
```

### Specialized Card Patterns

#### Info Card with Icon

```swift
HStack(spacing: 12) {
    Image(systemName: OPSStyle.Icons.info)
        .font(.system(size: 20))
        .foregroundColor(OPSStyle.Colors.primaryAccent)

    VStack(alignment: .leading, spacing: 4) {
        Text("Information")
            .font(OPSStyle.Typography.bodyBold)
        Text("Supporting details go here")
            .font(OPSStyle.Typography.caption)
            .foregroundColor(OPSStyle.Colors.secondaryText)
    }
}
.padding(16)
.cardStyle()
```

#### Accent Border Card

```swift
HStack(spacing: 0) {
    Rectangle()
        .fill(OPSStyle.Colors.primaryAccent)
        .frame(width: 4)

    VStack {
        // Content
    }
    .padding(16)
}
.background(OPSStyle.Colors.cardBackground)
.cornerRadius(8)
```

#### Interactive Card with Press Effect

```swift
Button(action: openDetails) {
    // Card content
}
.buttonStyle(ScaleButtonStyle())

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
```

---

## 10. Button Hierarchy

### Button Types & Usage

#### 1. Primary Button
**Purpose**: Main call-to-action on a screen

```swift
PrimaryButton(title: "Save Project", action: saveProject)

// Visual Properties
- Background: primaryAccent (#597794)
- Text: White
- Font: button (Kosugi Regular 14pt, ALL CAPS)
- Height: 56pt
- Full width
- Corner radius: 3pt

// Usage
- One per screen maximum (occasionally two if equal weight)
- Used for: Save, Create, Submit, Confirm
- Position: Bottom of screen for thumb access
```

#### 2. Accent Button (Variant)
**Purpose**: Secondary primary action with different color

```swift
// Not a standard component, but used in some contexts
Button(action: {}) {
    Text("Schedule")
}
.background(OPSStyle.Colors.secondaryAccent)
.foregroundColor(.white)

// Usage
- Rare—only when two equal-weight primary actions needed
- Example: "Save" vs "Save & Schedule"
```

#### 3. Secondary Button
**Purpose**: Alternative or cancel action

```swift
SecondaryButton(title: "Cancel", action: dismiss)

// Visual Properties
- Background: cardBackground
- Text: primaryAccent
- Border: 2pt, primaryAccent
- Font: button
- Height: 56pt
- Full width
- Corner radius: 3pt

// Usage
- Paired with primary buttons
- Used for: Cancel, Back, Skip
- Less visually prominent than primary
```

#### 4. Destructive Button
**Purpose**: Dangerous actions that require extra caution

```swift
DestructiveButton(title: "Delete Project", action: deleteProject)

// Visual Properties
- Background: errorStatus (#93321A)
- Text: White
- Font: button
- Height: 56pt
- Full width
- Corner radius: 3pt

// Usage
- Delete, Remove, Archive (if destructive)
- Often requires confirmation dialog first
- Use sparingly—user should pause before tapping
```

#### 5. Text Button
**Purpose**: Tertiary actions, low-emphasis options

```swift
Button("Skip") {
    // action
}
.font(OPSStyle.Typography.button)
.foregroundColor(OPSStyle.Colors.primaryAccent)

// Visual Properties
- No background
- No border
- Text: primaryAccent
- Font: button or caption

// Usage
- Skip, Remind Me Later, Learn More
- Least prominent action on screen
- Often at bottom of screen or in headers
```

#### 6. Icon Button
**Purpose**: Compact actions in toolbars, cards

```swift
IconButton(
    icon: OPSStyle.Icons.plusCircle,
    action: addItem,
    size: 56
)

// Visual Properties
- Circular background
- Size: 56pt (standard), 44pt (minimum), 64pt (large)
- Icon: 40% of button size
- Default tint: primaryAccent
- Background: cardBackground with border

// Usage
- Add, Edit, Delete (in card corners)
- Floating action button
- Toolbar actions
```

### Button Placement Patterns

#### Bottom-Anchored Pattern (Preferred)

```swift
VStack {
    // Screen content (scrollable)

    Spacer()

    // Buttons at bottom for thumb access
    HStack(spacing: 16) {
        SecondaryButton(title: "Cancel", action: dismiss)
        PrimaryButton(title: "Save", action: save)
    }
    .padding()
}
```

#### Floating Action Button

```swift
ZStack {
    // Main content

    VStack {
        Spacer()
        HStack {
            Spacer()
            IconButton(
                icon: OPSStyle.Icons.plus,
                action: createNew,
                size: 64
            )
            .padding()
        }
    }
}
```

#### Inline Actions

```swift
// In cards, headers
HStack {
    Text("Section Title")
    Spacer()
    Button("Edit") { }
        .font(OPSStyle.Typography.caption)
        .foregroundColor(OPSStyle.Colors.primaryAccent)
}
```

### Button States

#### Disabled State

```swift
PrimaryButton(title: "Save", action: save)
    .opacity(isSaveEnabled ? 1.0 : 0.7)
    .disabled(!isSaveEnabled)

// Alternative for explicit disabled styling
.background(isSaveEnabled ? OPSStyle.Colors.primaryAccent : Color.gray)
```

#### Loading State

```swift
Button(action: save) {
    if isSaving {
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .white))
    } else {
        Text("Save")
    }
}
.disabled(isSaving)
```

---

## 11. Field-First Design Principles

### The Three Constraints

Every design decision must consider:

1. **Gloves**: Reduced precision, large touch targets required
2. **Sunlight**: High contrast essential, no subtle color differences
3. **Battery**: Dark theme, efficient animations, optimized performance

### Touch Target Requirements

#### Size Standards

- **Minimum**: 44×44pt (Apple accessibility requirement)
- **OPS Standard**: 56×56pt (all interactive elements)
- **Primary Actions**: 64×64pt (critical buttons)

#### Spacing Standards

- **Between targets**: Minimum 8pt (prevents accidental taps)
- **Preferred spacing**: 16pt between interactive elements

#### Glove Test Checklist

- [ ] All buttons work with work gloves (tested)
- [ ] No adjacent targets closer than 8pt
- [ ] Swipe gestures have sufficient drag distance (minimum 20pt before triggering)
- [ ] No reliance on precise taps (e.g., tiny icons)

### Sunlight Readability

#### Contrast Requirements

- **Normal text**: Minimum 7:1 contrast ratio
- **Large text (18pt+)**: Minimum 4.5:1 contrast ratio
- **Interactive elements**: Must stand out against background

#### OPS Color Compliance

```swift
// ✅ High contrast pairs (field-tested)
primaryText on background        // #E5E5E5 on #0A0A0A
primaryAccent on background      // #597794 on #0A0A0A
white on primaryAccent           // White on #597794
white on errorStatus             // White on #93321A

// ⚠️ Avoid in critical text
tertiaryText on background       // Acceptable for hints only
secondaryText on cardBackground  // Acceptable for labels only
```

#### Testing Process

1. Test all screens outdoors in bright sunlight
2. Verify all critical text readable at arm's length
3. Ensure status colors distinguishable (not just by hue)
4. No reliance on subtle opacity differences for important info

### Minimal Text Entry

#### Design Principle

Every keystroke is a burden in the field. Minimize text entry through:

1. **Smart Defaults**: Pre-fill fields from context (location, date, current project)
2. **Pickers Over Typing**: Use pickers for common values (status, team members)
3. **Copy Functions**: "Copy from Project" to reuse data
4. **Contact Integration**: Import from device contacts instead of manual entry
5. **Voice Input**: Support dictation for notes and descriptions

#### Text Entry Patterns

```swift
// ✅ GOOD: Picker for known values
Picker("Status", selection: $status) {
    ForEach(Status.allCases) { status in
        Text(status.displayName).tag(status)
    }
}

// ❌ AVOID: Manual text entry for known values
TextField("Enter status (RFQ, Estimated, etc.)", text: $statusText)
```

### Offline-First Architecture

#### Data Persistence

- All critical data cached locally (SwiftData/Room)
- Changes saved locally with `needsSync` flag
- Sync when connection available (opportunistic)
- No data loss, even if offline for days

#### Sync Strategy

1. **Immediate**: Save to local database instantly
2. **Event-Driven**: Sync when specific actions occur (project saved, task completed)
3. **Periodic**: Background sync every 5 minutes (if changes exist)

#### UI Feedback

```swift
// Sync status indicator
if needsSync {
    HStack {
        Image(systemName: "arrow.triangle.2.circlepath")
        Text("Syncing...")
    }
    .font(OPSStyle.Typography.caption)
    .foregroundColor(OPSStyle.Colors.secondaryText)
}
```

### Performance Requirements

#### Device Support

- Support 3-year-old devices minimum
- iPhone 12 and newer (as of 2026)
- Smooth 60fps scrolling on minimum supported device
- Fast launch time (<2 seconds)

#### Battery Efficiency

- Dark theme reduces OLED power consumption
- Lazy loading for lists and images
- Debounced network requests (500ms minimum)
- No polling—use event-driven updates

#### Memory Management

- Image caching with size limits
- Pagination for large lists (50 items per page)
- Release unused resources promptly
- No memory leaks in navigation

---

## 12. Accessibility Standards

### Reduce Motion Support

OPS fully supports the iOS **Reduce Motion** accessibility setting via the `Animation+Accessible.swift` extension.

```swift
// Check state directly if needed
if UIAccessibility.isReduceMotionEnabled {
    // Skip animation entirely
} else {
    // Run animation
}

// Preferred: use the extension — it handles the check automatically
withAnimation(.accessibleEaseInOut()) {
    state.toggle()
}
```

When Reduce Motion is enabled:
- `Animation.accessibleEaseInOut()` returns `nil` → SwiftUI applies state changes instantly, no motion
- All view transitions that use this extension are automatically instant
- Cards, section expands, filter chips, kanban bars, search sheets — all respect the setting

**Do not use `.spring()` anywhere in OPS.** Spring animations cannot return `nil` and will always animate regardless of the accessibility setting.

### VoiceOver Support

#### Accessibility Labels

```swift
// Card accessibility
projectCard
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Project: \(project.name)")
    .accessibilityHint("Tap to view details")
    .accessibilityAddTraits(.isButton)

// Button accessibility
Button(action: delete) {
    Image(systemName: OPSStyle.Icons.trash)
}
.accessibilityLabel("Delete project")
.accessibilityHint("Permanently removes this project")
```

#### Accessibility Traits

```swift
// Interactive elements
.accessibilityAddTraits(.isButton)
.accessibilityAddTraits(.isLink)

// Status indicators
.accessibilityAddTraits(.isStaticText)

// Headers
.accessibilityAddTraits(.isHeader)
```

### Dynamic Type Support

#### Text Scaling

- All text uses OPSStyle.Typography (respects Dynamic Type)
- Maintain minimum touch targets at all text sizes
- Adjust layout for larger text (test at 400% scale)
- Truncate or wrap text gracefully

#### Layout Adjustments

```swift
@Environment(\.sizeCategory) var sizeCategory

var body: some View {
    if sizeCategory > .extraLarge {
        // Vertical layout for large text
        VStack { }
    } else {
        // Horizontal layout for normal text
        HStack { }
    }
}
```

### Color Contrast

All OPSStyle colors are pre-verified for contrast compliance:

- **Primary text on background**: 7:1+ ratio
- **Secondary text on background**: 4.5:1+ ratio
- **Interactive elements**: Sufficient contrast in all states
- **Status colors**: Distinguishable by luminance, not just hue

### Keyboard Navigation

- All interactive elements reachable via keyboard (iOS external keyboard)
- Logical tab order
- Visible focus indicators
- No keyboard traps

---

## 13. Animation & Motion

### Accessibility-Aware Animations (REQUIRED)

**All animations in OPS must use `Animation.accessibleEaseInOut()`. Never use `.spring()` or raw `.easeInOut()` in view code.**

```swift
// File: Extensions/Animation+Accessible.swift
extension Animation {
    static func accessibleEaseInOut(duration: Double = 0.25) -> Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: duration)
    }
}
```

This extension:
- Returns `nil` when iOS **Reduce Motion** is enabled — SwiftUI treats `nil` as instant (no animation)
- Defaults to 0.25s easeInOut when motion is allowed
- Is used via `withAnimation(.accessibleEaseInOut())` or `.animation(.accessibleEaseInOut(), value: …)`

**Rationale:** `.spring()` ignores the Reduce Motion accessibility setting and can cause motion sickness for sensitive users. `accessibleEaseInOut()` is a global enforcer of the iOS Reduce Motion preference across the entire app.

### Animation Standards

```swift
// Standard state change (0.25s default)
withAnimation(.accessibleEaseInOut()) {
    isExpanded.toggle()
}

// Quick UI feedback (filter chip tap, toggle)
withAnimation(.accessibleEaseInOut(duration: 0.2)) {
    activeFilter = .today
}

// Slow/deliberate (calendar expand, section transitions)
withAnimation(.accessibleEaseInOut(duration: 0.35)) {
    isMonthExpanded.toggle()
}
```

### Common Animation Patterns

#### Sheet Presentation

```swift
// Automatic—SwiftUI handles
.sheet(isPresented: $showSheet) {
    // Sheet content
}
```

#### Card Swipe Gesture

```swift
.offset(x: swipeOffset)
.gesture(
    DragGesture()
        .onChanged { value in
            swipeOffset = value.translation.width
        }
        .onEnded { value in
            withAnimation(.accessibleEaseInOut(duration: 0.2)) {
                swipeOffset = 0
            }
        }
)
```

#### Section Expand/Collapse

```swift
if isExpanded {
    content()
        .transition(.opacity.combined(with: .move(edge: .top)))
}

// Toggle with animation
Button("Expand") {
    withAnimation(.accessibleEaseInOut(duration: 0.2)) {
        isExpanded.toggle()
    }
}
```

#### Button Press Effect

```swift
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.accessibleEaseInOut(duration: 0.1), value: configuration.isPressed)
    }
}
```

### Haptic Feedback

#### Feedback Patterns

```swift
// Light tap (UI feedback)
UIImpactFeedbackGenerator(style: .light).impactOccurred()

// Medium impact (swipe threshold reached)
UIImpactFeedbackGenerator(style: .medium).impactOccurred()

// Success notification
UINotificationFeedbackGenerator().notificationOccurred(.success)

// Error notification
UINotificationFeedbackGenerator().notificationOccurred(.error)
```

#### Usage Guidelines

- Use sparingly (not on every tap)
- Match intensity to action importance
- Provide feedback at thresholds (e.g., 40% swipe)
- Never for passive events (scrolling, loading)

### Performance Considerations

- Prefer opacity changes over position changes
- Avoid blur effects during animation
- Use `drawingGroup()` for complex animations
- Test on minimum supported device

---

## 14. Anti-Patterns

### What to Avoid

#### 1. Opacity Modifiers on Backgrounds

```swift
// ❌ WRONG
.background(OPSStyle.Colors.background.opacity(0.5))

// ✅ CORRECT
.background(OPSStyle.Colors.cardBackground)
```

**Exception**: `cardBackgroundDark.opacity(0.8)` is a defined pattern.

#### 2. Misuse of Secondary Accent

```swift
// ❌ WRONG: Decoration
.foregroundColor(OPSStyle.Colors.secondaryAccent)  // For non-active items

// ✅ CORRECT: Active state only
if project.isActive {
    .foregroundColor(OPSStyle.Colors.secondaryAccent)
}
```

#### 3. Hardcoded Values

```swift
// ❌ WRONG
.padding(15)
.font(.system(size: 16))
.foregroundColor(Color(red: 0.25, green: 0.45, blue: 0.58))
Image(systemName: "calendar")

// ✅ CORRECT
.padding(OPSStyle.Layout.spacing3)
.font(OPSStyle.Typography.body)
.foregroundColor(OPSStyle.Colors.primaryAccent)
Image(systemName: OPSStyle.Icons.calendar)
```

#### 4. System Fonts

```swift
// ❌ WRONG
Text("Title").font(.title)
Text("Body").font(.body)
Text("Caption").font(.caption)

// ✅ CORRECT
Text("Title").font(OPSStyle.Typography.title)
Text("Body").font(OPSStyle.Typography.body)
Text("Caption").font(OPSStyle.Typography.caption)
```

#### 5. Nested Cards

```swift
// ❌ WRONG
VStack {
    VStack {
        // Inner content
    }
    .cardStyle()
}
.cardStyle()

// ✅ CORRECT
VStack {
    // Content
}
.cardStyle()
```

#### 6. Section Headers Inside Cards

```swift
// ❌ WRONG
VStack {
    Text("SECTION HEADER")
    // Content
}
.cardStyle()

// ✅ CORRECT
VStack {
    Text("SECTION HEADER")
        .font(OPSStyle.Typography.captionBold)

    VStack {
        // Content
    }
    .cardStyle()
}
```

#### 7. Low Contrast

```swift
// ❌ WRONG: Unreadable in sunlight
Text("Important").foregroundColor(Color.gray.opacity(0.5))

// ✅ CORRECT
Text("Important").foregroundColor(OPSStyle.Colors.primaryText)
```

#### 8. Tiny Touch Targets

```swift
// ❌ WRONG
Button("Delete") { }
    .frame(width: 30, height: 30)

// ✅ CORRECT
Button("Delete") { }
    .frame(width: 56, height: 56)
```

#### 9. Complex Gestures

```swift
// ❌ AVOID: Multi-finger gestures for critical functions
.gesture(MagnificationGesture())
.gesture(RotationGesture())

// ✅ CORRECT: Simple taps and swipes
.onTapGesture { }
.gesture(DragGesture())
```

#### 10. Gradients & Effects

```swift
// ❌ AVOID: Hurts performance on older devices
.background(
    LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom)
)
.blur(radius: 10)

// ✅ CORRECT: Solid colors
.background(OPSStyle.Colors.cardBackground)
```

#### 11. Decorative Elements

```swift
// ❌ WRONG: No functional purpose
Circle()
    .fill(Color.blue.opacity(0.3))
    .frame(width: 200, height: 200)
    .blur(radius: 50)

// ✅ CORRECT: Every element serves a purpose
StatusBadge(status: project.status)
```

#### 12. Centered Large Blocks of Text

```swift
// ❌ WRONG: Hard to read
Text(longDescription)
    .multilineTextAlignment(.center)

// ✅ CORRECT
Text(longDescription)
    .multilineTextAlignment(.leading)
```

### Quick Decision Matrix

When in doubt:

1. Choose **reliability** over features
2. Choose **simplicity** over flexibility
3. Choose **clarity** over cleverness
4. Choose **field needs** over office preferences
5. Choose **proven patterns** over innovation

---

## Appendix A: SwiftUI to Kotlin/Compose Mapping

For Android conversion, here are the equivalent concepts:

### Color

```swift
// iOS (SwiftUI)
Color("AccentPrimary")
Color.white.opacity(0.10)

// Android (Compose)
colorResource(R.color.accent_primary)
Color.White.copy(alpha = 0.1f)
```

### Typography

```swift
// iOS (SwiftUI)
Font.custom("Mohave-Bold", size: 32)

// Android (Compose)
FontFamily(Font(R.font.mohave_bold))
fontSize = 32.sp
```

### Layout

```swift
// iOS (SwiftUI)
VStack(spacing: 16) { }
HStack(spacing: 8) { }
.padding(16)

// Android (Compose)
Column(verticalArrangement = Arrangement.spacedBy(16.dp)) { }
Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { }
Modifier.padding(16.dp)
```

### Buttons

```swift
// iOS (SwiftUI)
Button("Save") { action() }
    .buttonStyle(PrimaryButtonStyle())

// Android (Compose)
OpsButton(
    text = "Save",
    onClick = { action() },
    style = ButtonStyle.Primary
)
```

---

## Appendix B: Component File Locations (iOS)

```
OPS/OPS/Views/Components/ (76 files)
├── Cards/
│   ├── ClientInfoCard.swift
│   ├── CompanyContactCard.swift
│   ├── LocationCard.swift
│   ├── NotesCard.swift
│   └── TeamMembersCard.swift
├── Client/
│   ├── SubClientEditSheet.swift
│   └── SubClientListView.swift
├── Common/
│   ├── AddressAutocompleteField.swift
│   ├── AddressSearchField.swift
│   ├── AppHeader.swift
│   ├── AppMessageView.swift
│   ├── CompanyTeamListView.swift
│   ├── ContactDetailSheet.swift
│   ├── CustomAlert.swift
│   ├── CustomTabBar.swift
│   ├── DeleteConfirmation.swift
│   ├── DeletionSheet.swift
│   ├── ExpandableNotesView.swift
│   ├── FilterSheet.swift
│   ├── ImageSyncProgressView.swift
│   ├── LoadingOverlay.swift
│   ├── LocationPermissionView.swift
│   ├── NavigationBanner.swift
│   ├── NavigationControlsView.swift
│   ├── NotificationBanner.swift
│   ├── PushInMessage.swift
│   ├── ReassignmentRows.swift
│   ├── RefreshIndicator.swift
│   ├── SearchField.swift
│   ├── StorageOptionSlider.swift
│   ├── TabBarBackground.swift
│   ├── TacticalLoadingBar.swift
│   └── UnassignedRolesOverlay.swift
├── Contact/
│   ├── ContactCreatorView.swift
│   ├── ContactPicker.swift
│   └── ContactUpdater.swift
├── Event/
│   └── EventCarousel.swift
├── Images/
│   ├── ImagePicker.swift
│   ├── ImagePickerView.swift
│   ├── PhotoAnnotationView.swift
│   ├── ProjectImagesSection.swift
│   ├── ProjectImagesSimple.swift
│   ├── ProjectImageView.swift
│   └── ProjectPhotosGrid.swift
├── Map/
│   ├── MiniMapView.swift
│   ├── ProjectMapAnnotation.swift
│   ├── ProjectMapView.swift
│   └── RouteDirectionsView.swift
├── Project/
│   ├── ProjectActionBar.swift
│   ├── ProjectCard.swift
│   ├── ProjectCarousel.swift
│   ├── ProjectDetailsView.swift
│   ├── ProjectHeader.swift
│   ├── ProjectNotesView.swift
│   ├── ProjectSheetContainer.swift
│   ├── ProjectSummaryCard.swift
│   ├── TaskCompletionChecklistSheet.swift
│   └── TaskDetailsView.swift
├── Scheduling/
│   └── CalendarSchedulerSheet.swift
├── Sync/
│   └── SyncStatusIndicator.swift
├── Task/
│   └── TaskSelectorBar.swift
├── Tasks/
│   └── TaskListView.swift
├── Team/
│   ├── TeamRoleAssignmentSheet.swift
│   └── TeamRoleManagementView.swift
├── User/
│   ├── CompanyTeamMembersListView.swift
│   ├── ContactDetailView.swift
│   ├── OrganizationTeamView.swift
│   ├── ProjectTeamView.swift
│   ├── TaskTeamView.swift
│   ├── TeamMemberListView.swift
│   └── UserProfileCard.swift
├── CompanyAvatar.swift
├── FloatingActionMenu.swift
├── OptionalSectionPill.swift
├── ProfileImageUploader.swift
└── UserAvatar.swift
```

---

**End of Design System Documentation**

This document serves as the complete design system reference for OPS iOS and Android implementations. All code must conform to these standards to maintain brand consistency and field-first usability.
