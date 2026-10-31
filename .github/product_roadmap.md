# Church Digital Platform - Master Product Roadmap

## Module 1: Core Foundation & Tenant
- Church profile, tenant isolation key, database migrations (Currently in progress)

## Module 2: Church Announcements & Notices
- Reverse-chronological feed, Admin/Pastor role check, priority alerts

## Module 3: Confidential Pastoral Prayer
- Private prayer requests to Pastor only, status updates (Praying, Answered)

## Module 4: Worship & Choir Playlist Engine
- Song library with lyrics and chords, plus Sunday service setlists

## Module 5: Automated Birthday & Anniversary Blessings
- Cron-driven daily check for birthdays/anniversaries with WhatsApp deep-link notifications

## Module 6: Fellowship Ministry Spaces
- Group spaces for Men's Fellowship, Sunday School, and House Prayer groups

## Module 7: Member Profile & Family Directory
- Member personal details, family unit linkage, and privacy visibility controls

## Module 8: Digital Offerings & UPI Contribution Ledger
- Digital giving through UPI with contribution records, payment references, acknowledgements, and an auditable church contribution ledger

## Module 9: Identity, Sign-In & Tenant Context (Cross-Cutting Foundation)
- Production-ready member sign-in and sign-out, verified identity, and secure session lifecycle; select an identity provider if none is already established
- Link authenticated identities to member records and a church tenant; derive tenant context from server-validated identity and enforce tenant isolation across all modules
- Provide the Flutter app with an authenticated API client that attaches the bearer token and trusted tenant context, and stores credentials securely
- Enforce server-side least-privilege roles and policies for Member, Pastor, Admin, and WorshipLeader; never trust roles or tenant IDs supplied only by the client
- Keep test authentication isolated from production authentication; remove or disable header-based test authentication in production
- Treat this module as a prerequisite for member-specific and role-protected features in Modules 3–8; coordinate API and identity contracts with those module issues
