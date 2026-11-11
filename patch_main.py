import re

with open('mobile/lib/main.dart', 'r') as f:
    content = f.read()

# Add import
content = content.replace(
    '''import 'services/offering_api_client.dart';''',
    '''import 'services/offering_api_client.dart';
import 'services/announcement_api_client.dart';'''
)

# Add cached client declaration
content = content.replace(
    '''  HttpOfferingApiClient? _cachedOfferingClient;''',
    '''  HttpOfferingApiClient? _cachedOfferingClient;
  DefaultAnnouncementApiClient? _cachedAnnouncementClient;'''
)

# Update _updateClients to instantiate announcement client
content = content.replace(
    '''        _cachedOfferingClient = HttpOfferingApiClient(
          client: authClient,
          baseUrl: effectiveBase,
        );
      } else {''',
    '''        _cachedOfferingClient = HttpOfferingApiClient(
          client: authClient,
          baseUrl: effectiveBase,
        );
        _cachedAnnouncementClient = DefaultAnnouncementApiClient(
          client: authClient,
          baseUrl: effectiveBase,
        );
      } else {'''
)

# Clear cached client
content = content.replace(
    '''        _cachedOfferingClient = null;
      }
    }
  }''',
    '''        _cachedOfferingClient = null;
        _cachedAnnouncementClient = null;
      }
    }
  }'''
)

# Add isAdmin helper
content = content.replace(
    '''  bool get _canManageOfferings {
    final session = _currentSession;
    if (session == null) return false;
    return session.roles.any((r) => r.toLowerCase() == 'pastor' || r.toLowerCase() == 'admin');
  }''',
    '''  bool get _isAdmin {
    final session = _currentSession;
    if (session == null) return false;
    return session.roles.any((r) => r.toLowerCase() == 'admin');
  }

  bool get _canManageOfferings {
    final session = _currentSession;
    if (session == null) return false;
    return session.roles.any((r) => r.toLowerCase() == 'pastor' || r.toLowerCase() == 'admin');
  }'''
)

# Update HomeScreen instantiation
content = content.replace(
    '''    HomeScreen(
      celebrationClient: _cachedCelebrationClient,
      offeringClient: _cachedOfferingClient,
      isPastor: _isPastor,
      canManageOfferings: _canManageOfferings,
    ),''',
    '''    HomeScreen(
      announcementClient: _cachedAnnouncementClient,
      celebrationClient: _cachedCelebrationClient,
      offeringClient: _cachedOfferingClient,
      isPastor: _isPastor,
      isAdmin: _isAdmin,
      canManageOfferings: _canManageOfferings,
    ),'''
)

with open('mobile/lib/main.dart', 'w') as f:
    f.write(content)
