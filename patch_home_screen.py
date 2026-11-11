import re

with open('mobile/lib/screens/home_screen.dart', 'r') as f:
    content = f.read()

content = content.replace(
    '''  Future<void> _handlePublish(CreateAnnouncementInput input) async {
    if (widget.announcementClient == null) return;
    await widget.announcementClient!.publishAnnouncement(input);
  }''',
    '''  Future<void> _handlePublish(CreateAnnouncementInput input) async {
    if (widget.announcementClient == null) {
      throw StateError('Announcement client is not initialized.');
    }
    await widget.announcementClient!.publishAnnouncement(input);
  }'''
)

with open('mobile/lib/screens/home_screen.dart', 'w') as f:
    f.write(content)
