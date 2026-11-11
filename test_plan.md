1. **Create `AnnouncementApiClient`**:
   - Implement `mobile/lib/services/announcement_api_client.dart`.
   - Methods: `Future<List<Announcement>> getAnnouncements()` and `Future<Announcement> publishAnnouncement(CreateAnnouncementInput input)`.
   - Use `AuthenticatedHttpClient` (`http.Client`).
   - Connect to `/api/v1/announcements` using `EnvironmentConfig.apiUrl`.

2. **Update `HomeScreen`**:
   - Modify `mobile/lib/screens/home_screen.dart` to accept an `AnnouncementApiClient`.
   - Add state management to load announcements on init, show a loading indicator, and handle errors (retry).
   - Display a list of `Announcement` cards.
   - If `isPastor` or `isAdmin` (we can pass an `canPublishAnnouncements` bool, or check `isPastor`), show a FAB or button to open `AnnouncementComposerScreen`.
   - After publishing, refresh the announcement feed.
   - Include pull-to-refresh functionality (`RefreshIndicator`).
   - Make sure to keep the Celebrations and Offerings cards.

3. **Update tests**:
   - Add unit tests for `AnnouncementApiClient` in `mobile/test/services/announcement_api_client_test.dart` (or similar).
   - Update `mobile/test/home_screen_test.dart` to mock `AnnouncementApiClient` and cover loading, empty state, feed display, publish button visibility, and refresh after publish.

4. **Pre-commit and Analyze**:
   - Run `flutter analyze --fatal-infos`.
   - Run `flutter test mobile/test/home_screen_test.dart` and `mobile/test/announcement_api_client_test.dart`.
   - Run `pre_commit_instructions` and satisfy requirements.

5. **Submit PR**:
   - Submit changes mentioning `#66` in branch and PR.
