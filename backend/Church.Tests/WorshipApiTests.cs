using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http.Json;
using System.Threading.Tasks;
using Church.API.Models;
using Church.Core;
using Church.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Church.Tests
{
    public class WorshipApiTests : IClassFixture<CustomWebApplicationFactory>
    {
        private readonly CustomWebApplicationFactory _factory;

        public WorshipApiTests(CustomWebApplicationFactory factory)
        {
            _factory = factory;
        }

        private void SeedSongs(Guid churchId, List<Song> songs)
        {
            using var scope = _factory.Services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            foreach (var song in songs)
            {
                song.ChurchId = churchId;
                db.Songs.Add(song);
            }
            db.SaveChanges();
        }

        [Fact]
        public async Task Member_CanReadSongsAndSetlists()
        {
            var churchId = Guid.NewGuid();
            var song = new Song
            {
                Id = Guid.NewGuid(),
                ChurchId = churchId,
                Title = "Amazing Grace",
                Artist = "John Newton",
                DefaultKey = "G",
                TempoBpm = 72,
                Lyrics = "Amazing grace how sweet the sound",
                Chords = "[G] Amazing [C] grace how [G] sweet the [D] sound",
                CreatedAt = DateTime.UtcNow
            };
            SeedSongs(churchId, new List<Song> { song });

            var client = _factory.CreateClient();
            client.DefaultRequestHeaders.Add("X-User-Role", "Member");
            client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            // GET /api/v1/worship/songs
            var listResponse = await client.GetAsync("/api/v1/worship/songs");
            Assert.Equal(HttpStatusCode.OK, listResponse.StatusCode);
            var songs = await listResponse.Content.ReadFromJsonAsync<List<SongResponse>>();
            Assert.NotNull(songs);
            var found = songs.FirstOrDefault(s => s.Id == song.Id);
            Assert.NotNull(found);
            Assert.Equal("Amazing Grace", found.Title);
            Assert.Equal("[G] Amazing [C] grace how [G] sweet the [D] sound", found.Chords);

            // GET /api/v1/worship/songs/{id}
            var singleResponse = await client.GetAsync($"/api/v1/worship/songs/{song.Id}");
            Assert.Equal(HttpStatusCode.OK, singleResponse.StatusCode);
            var singleSong = await singleResponse.Content.ReadFromJsonAsync<SongResponse>();
            Assert.NotNull(singleSong);
            Assert.Equal(song.Id, singleSong.Id);
            Assert.Equal("Amazing Grace", singleSong.Title);
        }

        [Fact]
        public async Task Member_CannotCreateSong_Returns403()
        {
            var churchId = Guid.NewGuid();
            var client = _factory.CreateClient();
            client.DefaultRequestHeaders.Add("X-User-Role", "Member");
            client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            var payload = new CreateSongRequest(
                Title: "Unauthorized Song",
                Artist: "Unknown",
                DefaultKey: "C",
                TempoBpm: 120,
                Lyrics: "Lyrics here",
                Chords: "C F G"
            );

            var response = await client.PostAsJsonAsync("/api/v1/worship/songs", payload);
            Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        }

        [Fact]
        public async Task Member_CannotCreateSetlist_Returns403()
        {
            var churchId = Guid.NewGuid();
            var client = _factory.CreateClient();
            client.DefaultRequestHeaders.Add("X-User-Role", "Member");
            client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            var payload = new CreateSetlistRequest(
                Title: "Sunday Service Setlist",
                ServiceDate: DateTime.UtcNow.AddDays(2),
                Notes: "Weekly setlist",
                Items: new List<CreateSetlistItemRequest>()
            );

            var response = await client.PostAsJsonAsync("/api/v1/worship/setlists", payload);
            Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        }

        [Fact]
        public async Task WorshipLeader_CanCreateUpdateAndDeleteSong()
        {
            var churchId = Guid.NewGuid();
            var client = _factory.CreateClient();
            client.DefaultRequestHeaders.Add("X-User-Role", "WorshipLeader");
            client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            // 1. Create Song
            var createPayload = new CreateSongRequest(
                Title: "Way Maker",
                Artist: "Sinach",
                DefaultKey: "E",
                TempoBpm: 68,
                Lyrics: "You are here moving in our midst",
                Chords: "[E] You are here [B] moving in our [C#m] midst"
            );

            var createResponse = await client.PostAsJsonAsync("/api/v1/worship/songs", createPayload);
            Assert.Equal(HttpStatusCode.Created, createResponse.StatusCode);
            var createdSong = await createResponse.Content.ReadFromJsonAsync<SongResponse>();
            Assert.NotNull(createdSong);
            Assert.Equal("Way Maker", createdSong.Title);
            Assert.Equal(churchId, createdSong.ChurchId);

            // 2. Update Song
            var updatePayload = new UpdateSongRequest(
                Title: "Way Maker (Live)",
                Artist: "Sinach / Leeland",
                DefaultKey: "D",
                TempoBpm: 66,
                Lyrics: "You are here moving in our midst...",
                Chords: "[D] You are here [A] moving..."
            );

            var updateResponse = await client.PutAsJsonAsync($"/api/v1/worship/songs/{createdSong.Id}", updatePayload);
            Assert.Equal(HttpStatusCode.OK, updateResponse.StatusCode);
            var updatedSong = await updateResponse.Content.ReadFromJsonAsync<SongResponse>();
            Assert.NotNull(updatedSong);
            Assert.Equal("Way Maker (Live)", updatedSong.Title);
            Assert.Equal("D", updatedSong.DefaultKey);

            // 3. Delete Song
            var deleteResponse = await client.DeleteAsync($"/api/v1/worship/songs/{createdSong.Id}");
            Assert.Equal(HttpStatusCode.NoContent, deleteResponse.StatusCode);

            // 4. Verify Not Found
            var getResponse = await client.GetAsync($"/api/v1/worship/songs/{createdSong.Id}");
            Assert.Equal(HttpStatusCode.NotFound, getResponse.StatusCode);
        }

        [Fact]
        public async Task PastorOrAdmin_CanCreateSetlistWithOrderedSongs()
        {
            var churchId = Guid.NewGuid();

            // Create 2 songs via Admin client
            var adminClient = _factory.CreateClient();
            adminClient.DefaultRequestHeaders.Add("X-User-Role", "Admin");
            adminClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            var song1Res = await adminClient.PostAsJsonAsync("/api/v1/worship/songs", new CreateSongRequest(
                Title: "Opening Hymn - Holy Holy Holy",
                Artist: "Reginald Heber",
                DefaultKey: "D",
                TempoBpm: 80,
                Lyrics: "Holy Holy Holy Lord God Almighty",
                Chords: "[D] Holy [G] Holy [D] Holy"
            ));
            var song1 = await song1Res.Content.ReadFromJsonAsync<SongResponse>();

            var song2Res = await adminClient.PostAsJsonAsync("/api/v1/worship/songs", new CreateSongRequest(
                Title: "Praise Song - Goodness of God",
                Artist: "Bethel",
                DefaultKey: "G",
                TempoBpm: 70,
                Lyrics: "I love You Lord, For Your mercy never fails me",
                Chords: "[G] I love You [C] Lord..."
            ));
            var song2 = await song2Res.Content.ReadFromJsonAsync<SongResponse>();

            // Create Setlist with items
            var serviceDate = DateTime.UtcNow.Date.AddDays(3);
            var setlistPayload = new CreateSetlistRequest(
                Title: "Sunday Morning Service",
                ServiceDate: serviceDate,
                Notes: "Communion Sunday",
                Items: new List<CreateSetlistItemRequest>
                {
                    new CreateSetlistItemRequest(song1!.Id, 1, "E", "Key shifted to E for choir"),
                    new CreateSetlistItemRequest(song2!.Id, 2, null, "Extended bridge outro")
                }
            );

            var setlistRes = await adminClient.PostAsJsonAsync("/api/v1/worship/setlists", setlistPayload);
            Assert.Equal(HttpStatusCode.Created, setlistRes.StatusCode);
            var setlistDetail = await setlistRes.Content.ReadFromJsonAsync<SetlistDetailResponse>();
            Assert.NotNull(setlistDetail);
            Assert.Equal("Sunday Morning Service", setlistDetail.Title);
            Assert.Equal(2, setlistDetail.Items.Count);

            Assert.Equal(1, setlistDetail.Items[0].Order);
            Assert.Equal("Opening Hymn - Holy Holy Holy", setlistDetail.Items[0].SongTitle);
            Assert.Equal("E", setlistDetail.Items[0].KeyOverride);

            Assert.Equal(2, setlistDetail.Items[1].Order);
            Assert.Equal("Praise Song - Goodness of God", setlistDetail.Items[1].SongTitle);

            // Member can read setlist list and detail
            var memberClient = _factory.CreateClient();
            memberClient.DefaultRequestHeaders.Add("X-User-Role", "Member");
            memberClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            var listRes = await memberClient.GetAsync("/api/v1/worship/setlists");
            Assert.Equal(HttpStatusCode.OK, listRes.StatusCode);
            var setlists = await listRes.Content.ReadFromJsonAsync<List<SetlistResponse>>();
            Assert.NotNull(setlists);
            var foundSummary = setlists.FirstOrDefault(s => s.Id == setlistDetail.Id);
            Assert.NotNull(foundSummary);
            Assert.Equal(2, foundSummary.ItemCount);

            var memberDetailRes = await memberClient.GetAsync($"/api/v1/worship/setlists/{setlistDetail.Id}");
            Assert.Equal(HttpStatusCode.OK, memberDetailRes.StatusCode);
            var memberDetail = await memberDetailRes.Content.ReadFromJsonAsync<SetlistDetailResponse>();
            Assert.NotNull(memberDetail);
            Assert.Equal(2, memberDetail.Items.Count);
        }

        [Fact]
        public async Task TenantIsolation_SongsAndSetlistsNeverExposedAcrossTenants()
        {
            var churchA = Guid.NewGuid();
            var churchB = Guid.NewGuid();

            var clientA = _factory.CreateClient();
            clientA.DefaultRequestHeaders.Add("X-User-Role", "Admin");
            clientA.DefaultRequestHeaders.Add("X-Tenant-Id", churchA.ToString());

            var clientB = _factory.CreateClient();
            clientB.DefaultRequestHeaders.Add("X-User-Role", "Admin");
            clientB.DefaultRequestHeaders.Add("X-Tenant-Id", churchB.ToString());

            // Church A creates a song and setlist
            var songARes = await clientA.PostAsJsonAsync("/api/v1/worship/songs", new CreateSongRequest(
                Title: "Church A Private Anthem",
                Artist: "Church A Choir",
                DefaultKey: "C",
                TempoBpm: 90,
                Lyrics: "Church A specific lyrics",
                Chords: "C G Am F"
            ));
            var songA = await songARes.Content.ReadFromJsonAsync<SongResponse>();
            Assert.NotNull(songA);

            var setlistARes = await clientA.PostAsJsonAsync("/api/v1/worship/setlists", new CreateSetlistRequest(
                Title: "Church A Special Service",
                ServiceDate: DateTime.UtcNow.Date,
                Notes: "Confidential setlist",
                Items: new List<CreateSetlistItemRequest>
                {
                    new CreateSetlistItemRequest(songA.Id, 1, null, null)
                }
            ));
            var setlistA = await setlistARes.Content.ReadFromJsonAsync<SetlistDetailResponse>();
            Assert.NotNull(setlistA);

            // Church B queries songs
            var churchBSongs = await clientB.GetFromJsonAsync<List<SongResponse>>("/api/v1/worship/songs");
            Assert.NotNull(churchBSongs);
            Assert.DoesNotContain(churchBSongs, s => s.Id == songA.Id);

            // Church B tries to GET song A by ID -> 404 Not Found
            var getSongRes = await clientB.GetAsync($"/api/v1/worship/songs/{songA.Id}");
            Assert.Equal(HttpStatusCode.NotFound, getSongRes.StatusCode);

            // Church B queries setlists
            var churchBSetlists = await clientB.GetFromJsonAsync<List<SetlistResponse>>("/api/v1/worship/setlists");
            Assert.NotNull(churchBSetlists);
            Assert.DoesNotContain(churchBSetlists, s => s.Id == setlistA.Id);

            // Church B tries to GET setlist A by ID -> 404 Not Found
            var getSetlistRes = await clientB.GetAsync($"/api/v1/worship/setlists/{setlistA.Id}");
            Assert.Equal(HttpStatusCode.NotFound, getSetlistRes.StatusCode);

            // Church B tries to create a setlist containing Church A's song -> 400 Bad Request
            var badSetlistRes = await clientB.PostAsJsonAsync("/api/v1/worship/setlists", new CreateSetlistRequest(
                Title: "Church B Illicit Setlist",
                ServiceDate: DateTime.UtcNow.Date,
                Notes: "Should fail",
                Items: new List<CreateSetlistItemRequest>
                {
                    new CreateSetlistItemRequest(songA.Id, 1, null, null)
                }
            ));
            Assert.Equal(HttpStatusCode.BadRequest, badSetlistRes.StatusCode);
        }
    }
}
