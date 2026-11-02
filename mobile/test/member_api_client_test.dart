import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:church_digital_platform_mobile/models/member_models.dart';
import 'package:church_digital_platform_mobile/services/member_api_client.dart';

void main() {
  group('Member Models & Enum Serialization', () {
    test('DirectoryVisibility maps from int, string, and null safely', () {
      expect(DirectoryVisibility.fromValue(0), DirectoryVisibility.private);
      expect(DirectoryVisibility.fromValue(1), DirectoryVisibility.publicToMembers);
      expect(DirectoryVisibility.fromValue(2), DirectoryVisibility.leadersOnly);

      expect(DirectoryVisibility.fromValue('private'), DirectoryVisibility.private);
      expect(DirectoryVisibility.fromValue('publictomembers'), DirectoryVisibility.publicToMembers);
      expect(DirectoryVisibility.fromValue('leadersonly'), DirectoryVisibility.leadersOnly);

      expect(DirectoryVisibility.fromValue(null), DirectoryVisibility.private);
      expect(DirectoryVisibility.fromValue(99), DirectoryVisibility.private);
    });

    test('FamilyRole maps from int, string, and null safely', () {
      expect(FamilyRole.fromValue(0), FamilyRole.individual);
      expect(FamilyRole.fromValue(1), FamilyRole.headOfHousehold);
      expect(FamilyRole.fromValue(2), FamilyRole.spouse);
      expect(FamilyRole.fromValue(3), FamilyRole.child);
      expect(FamilyRole.fromValue(4), FamilyRole.other);

      expect(FamilyRole.fromValue('headofhousehold'), FamilyRole.headOfHousehold);
      expect(FamilyRole.fromValue('spouse'), FamilyRole.spouse);
      expect(FamilyRole.fromValue(null), FamilyRole.individual);
    });

    test('MemberProfile deserialization parses all backend DTO fields including avatarUrl and showBirthDayAndMonth', () {
      final json = {
        'id': 'mem-1',
        'tenantId': 'ten-1',
        'firstName': 'John',
        'lastName': 'Doe',
        'email': 'john@church.local',
        'phoneNumber': '+15551234567',
        'avatarUrl': 'https://church.local/avatars/john.png',
        'address': '123 Main St',
        'dateOfBirth': '1990-05-15T00:00:00.000Z',
        'anniversaryDate': '2015-06-20T00:00:00.000Z',
        'directoryVisibility': 1,
        'showEmail': true,
        'showPhoneNumber': false,
        'showAddress': true,
        'showBirthDayAndMonth': true,
        'familyId': 'fam-1',
        'familyName': 'Doe Family',
        'familyRole': 1,
        'createdAt': '2026-11-01T00:00:00.000Z',
        'updatedAt': '2026-11-02T00:00:00.000Z',
      };

      final profile = MemberProfile.fromJson(json);
      expect(profile.id, 'mem-1');
      expect(profile.tenantId, 'ten-1');
      expect(profile.fullName, 'John Doe');
      expect(profile.email, 'john@church.local');
      expect(profile.phoneNumber, '+15551234567');
      expect(profile.avatarUrl, 'https://church.local/avatars/john.png');
      expect(profile.directoryVisibility, DirectoryVisibility.publicToMembers);
      expect(profile.showEmail, true);
      expect(profile.showPhoneNumber, false);
      expect(profile.showBirthday, true);
      expect(profile.familyRole, FamilyRole.headOfHousehold);
      expect(profile.familyName, 'Doe Family');
      expect(profile.dateOfBirth?.year, 1990);
    });

    test('DirectoryMember deserialization parses fullName and handles null contact info for private profiles', () {
      final json = {
        'id': 'mem-2',
        'fullName': 'Jane Smith',
        'avatarUrl': null,
        'email': null,
        'phoneNumber': null,
        'address': null,
        'birthdayNotice': null,
        'directoryVisibility': 0,
        'familyId': null,
        'familyName': null,
        'familyRole': 0,
      };

      final member = DirectoryMember.fromJson(json);
      expect(member.id, 'mem-2');
      expect(member.fullName, 'Jane Smith');
      expect(member.avatarUrl, isNull);
      expect(member.email, isNull);
      expect(member.phoneNumber, isNull);
      expect(member.birthdayNotice, isNull);
      expect(member.directoryVisibility, DirectoryVisibility.private);
    });

    test('UpdateMemberProfileInput serializes correctly to JSON including showBirthDayAndMonth and avatarUrl', () {
      final input = UpdateMemberProfileInput(
        firstName: 'Alice',
        lastName: 'Wonderland',
        phoneNumber: '+15559876543',
        avatarUrl: 'https://church.local/avatars/alice.png',
        address: '456 Elm St',
        directoryVisibility: DirectoryVisibility.publicToMembers,
        showEmail: true,
        showPhoneNumber: true,
        showAddress: false,
        showBirthday: true,
      );

      final json = input.toJson();
      expect(json['firstName'], 'Alice');
      expect(json['lastName'], 'Wonderland');
      expect(json['phoneNumber'], '+15559876543');
      expect(json['avatarUrl'], 'https://church.local/avatars/alice.png');
      expect(json['directoryVisibility'], 1);
      expect(json['showEmail'], true);
      expect(json['showPhoneNumber'], true);
      expect(json['showAddress'], false);
      expect(json['showBirthDayAndMonth'], true);
    });
  });

  group('HttpMemberApiClient Endpoints', () {
    const testBaseUrl = 'https://api.church.local';

    test('getMyProfile calls /api/v1/members/me and returns MemberProfile', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/members/me');

        return http.Response(
          jsonEncode({
            'id': 'mem-10',
            'tenantId': 'ten-10',
            'firstName': 'Paul',
            'lastName': 'Apostle',
            'email': 'paul@church.local',
            'avatarUrl': 'https://church.local/paul.png',
            'directoryVisibility': 1,
            'showEmail': true,
            'showBirthDayAndMonth': true,
            'familyRole': 0,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = HttpMemberApiClient(client: client, baseUrl: testBaseUrl);
      final profile = await apiClient.getMyProfile();

      expect(profile.id, 'mem-10');
      expect(profile.fullName, 'Paul Apostle');
      expect(profile.email, 'paul@church.local');
      expect(profile.avatarUrl, 'https://church.local/paul.png');
      expect(profile.directoryVisibility, DirectoryVisibility.publicToMembers);
      expect(profile.showBirthday, true);
    });

    test('updateMyProfile calls PUT /api/v1/members/me with JSON payload including avatarUrl and showBirthDayAndMonth', () async {
      final client = MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/api/v1/members/me');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['firstName'], 'Peter');
        expect(body['lastName'], 'Fisherman');
        expect(body['avatarUrl'], 'https://church.local/peter.png');
        expect(body['showBirthDayAndMonth'], true);
        expect(body['directoryVisibility'], 0);

        return http.Response(
          jsonEncode({
            'id': 'mem-11',
            'tenantId': 'ten-10',
            'firstName': 'Peter',
            'lastName': 'Fisherman',
            'email': 'peter@church.local',
            'avatarUrl': 'https://church.local/peter.png',
            'directoryVisibility': 0,
            'showEmail': false,
            'showBirthDayAndMonth': true,
            'familyRole': 0,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = HttpMemberApiClient(client: client, baseUrl: testBaseUrl);
      final updated = await apiClient.updateMyProfile(
        const UpdateMemberProfileInput(
          firstName: 'Peter',
          lastName: 'Fisherman',
          avatarUrl: 'https://church.local/peter.png',
          showBirthday: true,
          directoryVisibility: DirectoryVisibility.private,
        ),
      );

      expect(updated.firstName, 'Peter');
      expect(updated.avatarUrl, 'https://church.local/peter.png');
      expect(updated.directoryVisibility, DirectoryVisibility.private);
    });

    test('getDirectory calls GET /api/v1/members with search and pagination parameters', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/members');
        expect(request.url.queryParameters['search'], 'Barnabas');
        expect(request.url.queryParameters['page'], '2');
        expect(request.url.queryParameters['pageSize'], '25');

        return http.Response(
          jsonEncode([
            {
              'id': 'mem-12',
              'fullName': 'Barnabas Encourager',
              'email': 'barnabas@church.local',
              'directoryVisibility': 1,
              'familyRole': 0,
            }
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = HttpMemberApiClient(client: client, baseUrl: testBaseUrl);
      final directory = await apiClient.getDirectory(
        search: 'Barnabas',
        page: 2,
        pageSize: 25,
      );

      expect(directory, hasLength(1));
      expect(directory.first.fullName, 'Barnabas Encourager');
    });

    test('getFamily calls GET /api/v1/members/families/{id}', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/members/families/fam-42');

        return http.Response(
          jsonEncode({
            'id': 'fam-42',
            'tenantId': 'ten-10',
            'familyName': 'The Encouragers',
            'members': [
              {
                'id': 'mem-12',
                'fullName': 'Barnabas Encourager',
                'directoryVisibility': 1,
                'familyRole': 1,
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = HttpMemberApiClient(client: client, baseUrl: testBaseUrl);
      final family = await apiClient.getFamily('fam-42');

      expect(family.id, 'fam-42');
      expect(family.familyName, 'The Encouragers');
      expect(family.members, hasLength(1));
      expect(family.members.first.fullName, 'Barnabas Encourager');
    });

    test('Error handling maps HTTP status codes to MemberApiException', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'Member not found.'}),
          404,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = HttpMemberApiClient(client: client, baseUrl: testBaseUrl);

      expect(
        () => apiClient.getMember('non-existent'),
        throwsA(
          isA<MemberApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', contains('not found')),
        ),
      );
    });
  });
}
