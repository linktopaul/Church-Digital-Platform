import 'package:flutter/material.dart';
import '../models/worship_models.dart';

class WorshipScreen extends StatefulWidget {
  final List<SongItem>? initialSongs;
  final List<SetlistItemData>? initialSetlists;

  const WorshipScreen({
    super.key,
    this.initialSongs,
    this.initialSetlists,
  });

  @override
  State<WorshipScreen> createState() => _WorshipScreenState();
}

class _WorshipScreenState extends State<WorshipScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<SongItem> _songs;
  late List<SetlistItemData> _setlists;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _songs = widget.initialSongs ??
        [
          const SongItem(
            id: '1',
            title: 'Amazing Grace',
            artist: 'John Newton',
            defaultKey: 'G',
            tempoBpm: 72,
            lyrics:
                'Amazing grace how sweet the sound\nThat saved a wretch like me\nI once was lost, but now I\'m found\nWas blind, but now I see',
            chords:
                '[G] Amazing grace how [C] sweet the [G] sound\nThat [G] saved a wretch like [D] me\nI [G] once was lost, but [C] now I\'m [G] found\nWas [Em] blind, but [D] now I [G] see',
          ),
          const SongItem(
            id: '2',
            title: 'Way Maker',
            artist: 'Sinach',
            defaultKey: 'E',
            tempoBpm: 68,
            lyrics:
                'You are here, moving in our midst\nI worship You, I worship You\nYou are here, working in this place\nI worship You, I worship You',
            chords:
                '[E] You are here, moving [B] in our midst\nI worship [C#m] You, I worship [A] You\n[E] You are here, working [B] in this place\nI worship [C#m] You, I worship [A] You',
          ),
          const SongItem(
            id: '3',
            title: 'Goodness of God',
            artist: 'Bethel Music',
            defaultKey: 'G',
            tempoBpm: 70,
            lyrics:
                'I love You, Lord\nFor Your mercy never fails me\nAll my days, I\'ve been held in Your hands\nFrom the moment that I wake up\nUntil I lay my head\nOh, I will sing of the goodness of God',
            chords:
                '[G] I love You, Lord\nFor Your [C] mercy never fails [G] me\nAll my [Em] days, I\'ve been [C] held in Your [D] hands\nFrom the [Em] moment that I [C] wake up\nUntil I [G] lay my [D/F#] head [Em]\nOh, I will [C] sing of the [D] goodness of [G] God',
          ),
        ];

    _setlists = widget.initialSetlists ??
        [
          SetlistItemData(
            id: 's1',
            title: 'Sunday Morning Worship',
            serviceDate: DateTime.now().add(const Duration(days: 2)),
            notes: 'Communion service - gentle transitions between songs.',
            items: [
              const SetlistSongItem(
                songId: '1',
                title: 'Amazing Grace',
                artist: 'John Newton',
                defaultKey: 'G',
                keyOverride: 'Ab',
                tempoBpm: 72,
                lyrics:
                    'Amazing grace how sweet the sound\nThat saved a wretch like me',
                chords:
                    '[Ab] Amazing grace how [Db] sweet the [Ab] sound\nThat [Ab] saved a wretch like [Eb] me',
                order: 1,
                notes: 'Acoustic intro only for verse 1',
              ),
              const SetlistSongItem(
                songId: '2',
                title: 'Way Maker',
                artist: 'Sinach',
                defaultKey: 'E',
                tempoBpm: 68,
                lyrics:
                    'You are here, moving in our midst\nI worship You, I worship You',
                chords:
                    '[E] You are here, moving [B] in our midst\nI worship [C#m] You, I worship [A] You',
                order: 2,
                notes: 'Full band enters on chorus',
              ),
            ],
          ),
          SetlistItemData(
            id: 's2',
            title: 'Youth Revival Night',
            serviceDate: DateTime.now().add(const Duration(days: 5)),
            notes: 'High energy praise service.',
            items: [
              const SetlistSongItem(
                songId: '3',
                title: 'Goodness of God',
                artist: 'Bethel Music',
                defaultKey: 'G',
                tempoBpm: 70,
                lyrics:
                    'I love You, Lord\nFor Your mercy never fails me',
                chords:
                    '[G] I love You, Lord\nFor Your [C] mercy never fails [G] me',
                order: 1,
                notes: 'Extended bridge and prayer time',
              ),
            ],
          ),
        ];
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openSongDetail(SongItem song) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _SongDetailSheet(song: song),
    );
  }

  void _openSetlistDetail(SetlistItemData setlist) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _SetlistDetailScreen(
          setlist: setlist,
          onSongTap: (songItem) => _openSongDetail(songItem),
        ),
      ),
    );
  }

  void _openAddSongDialog() {
    final titleController = TextEditingController();
    final artistController = TextEditingController();
    final keyController = TextEditingController(text: 'G');
    final tempoController = TextEditingController(text: '72');
    final lyricsController = TextEditingController();
    final chordsController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Song to Library'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('addSongTitleField'),
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title *'),
              ),
              TextField(
                key: const Key('addSongArtistField'),
                controller: artistController,
                decoration: const InputDecoration(labelText: 'Artist / Author'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('addSongKeyField'),
                      controller: keyController,
                      decoration: const InputDecoration(labelText: 'Key'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: const Key('addSongTempoField'),
                      controller: tempoController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'BPM'),
                    ),
                  ),
                ],
              ),
              TextField(
                key: const Key('addSongLyricsField'),
                controller: lyricsController,
                decoration: const InputDecoration(labelText: 'Lyrics'),
                maxLines: 3,
              ),
              TextField(
                key: const Key('addSongChordsField'),
                controller: chordsController,
                decoration: const InputDecoration(labelText: 'Chords'),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('saveSongButton'),
            onPressed: () {
              if (titleController.text.trim().isEmpty) return;
              setState(() {
                _songs.add(
                  SongItem(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    title: titleController.text.trim(),
                    artist: artistController.text.trim().isEmpty
                        ? null
                        : artistController.text.trim(),
                    defaultKey: keyController.text.trim().isEmpty
                        ? 'C'
                        : keyController.text.trim(),
                    tempoBpm: int.tryParse(tempoController.text.trim()),
                    lyrics: lyricsController.text.trim(),
                    chords: chordsController.text.trim(),
                  ),
                );
              });
              Navigator.of(context).pop();
            },
            child: const Text('Save Song'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredSongs = _songs.where((song) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return song.title.toLowerCase().contains(q) ||
          (song.artist?.toLowerCase().contains(q) ?? false);
    }).toList();

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Colors.grey,
            tabs: const [
              Tab(
                iconMargin: EdgeInsets.zero,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.library_music),
                    SizedBox(width: 8),
                    Text('Song Library'),
                  ],
                ),
              ),
              Tab(
                iconMargin: EdgeInsets.zero,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.playlist_play),
                    SizedBox(width: 8),
                    Text('Sunday Setlists'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Song Library
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  key: const Key('songSearchField'),
                  decoration: InputDecoration(
                    hintText: 'Search songs by title or artist...',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) {
                    setState(() => _searchQuery = val);
                  },
                ),
              ),
              Expanded(
                child: filteredSongs.isEmpty
                    ? const Center(
                        child: Text(
                          'No songs found.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        key: const Key('songsListView'),
                        itemCount: filteredSongs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final song = filteredSongs[index];
                          return ListTile(
                            key: Key('songItem_${song.id}'),
                            title: Text(
                              song.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              song.artist ?? 'Traditional',
                              style: const TextStyle(fontSize: 13),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (song.defaultKey != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Key ${song.defaultKey}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue.shade800,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                if (song.tempoBpm != null) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    '${song.tempoBpm} BPM',
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                                const SizedBox(width: 8),
                                const Icon(Icons.chevron_right,
                                    color: Colors.grey),
                              ],
                            ),
                            onTap: () => _openSongDetail(song),
                          );
                        },
                      ),
              ),
            ],
          ),

          // Tab 2: Sunday Setlists
          _setlists.isEmpty
              ? const Center(
                  child: Text(
                    'No setlists available yet.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  key: const Key('setlistsListView'),
                  itemCount: _setlists.length,
                  itemBuilder: (context, index) {
                    final setlist = _setlists[index];
                    final formattedDate =
                        '${setlist.serviceDate.year}-${setlist.serviceDate.month.toString().padLeft(2, '0')}-${setlist.serviceDate.day.toString().padLeft(2, '0')}';
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: ListTile(
                        key: Key('setlistItem_${setlist.id}'),
                        leading: CircleAvatar(
                          backgroundColor:
                              Theme.of(context).colorScheme.primaryContainer,
                          child: Icon(
                            Icons.calendar_month,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                        title: Text(
                          setlist.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text('Service Date: $formattedDate'),
                            if (setlist.notes != null)
                              Text(
                                setlist.notes!,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black54),
                              ),
                          ],
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${setlist.items.length} songs',
                            style: TextStyle(
                              color: Colors.green.shade800,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        onTap: () => _openSetlistDetail(setlist),
                      ),
                    );
                  },
                ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('addSongFab'),
        onPressed: _openAddSongDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Song'),
      ),
    );
  }
}

class _SongDetailSheet extends StatefulWidget {
  final SongItem song;

  const _SongDetailSheet({required this.song});

  @override
  State<_SongDetailSheet> createState() => _SongDetailSheetState();
}

class _SongDetailSheetState extends State<_SongDetailSheet> {
  bool _showChords = true;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.song.title,
                          key: const Key('songDetailTitle'),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (widget.song.artist != null)
                          Text(
                            widget.song.artist!,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (widget.song.defaultKey != null)
                    Chip(
                      label: Text('Key: ${widget.song.defaultKey}'),
                      backgroundColor: Colors.blue.shade50,
                    ),
                  const SizedBox(width: 8),
                  if (widget.song.tempoBpm != null)
                    Chip(
                      label: Text('${widget.song.tempoBpm} BPM'),
                      backgroundColor: Colors.orange.shade50,
                    ),
                  const Spacer(),
                  // Toggle between Chords & Lyrics view
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Chords')),
                      ButtonSegment(value: false, label: Text('Lyrics')),
                    ],
                    selected: {_showChords},
                    onSelectionChanged: (val) {
                      setState(() => _showChords = val.first);
                    },
                  ),
                ],
              ),
              const Divider(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: SelectableText(
                      _showChords
                          ? (widget.song.chords.isNotEmpty
                              ? widget.song.chords
                              : widget.song.lyrics)
                          : widget.song.lyrics,
                      key: const Key('songContentText'),
                      style: TextStyle(
                        fontFamily: _showChords ? 'Courier' : null,
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SetlistDetailScreen extends StatelessWidget {
  final SetlistItemData setlist;
  final ValueChanged<SongItem> onSongTap;

  const _SetlistDetailScreen({
    required this.setlist,
    required this.onSongTap,
  });

  @override
  Widget build(BuildContext context) {
    final formattedDate =
        '${setlist.serviceDate.year}-${setlist.serviceDate.month.toString().padLeft(2, '0')}-${setlist.serviceDate.day.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: Text(setlist.title),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.primaryContainer.withAlpha(50),
            child: Row(
              children: [
                const Icon(Icons.event),
                const SizedBox(width: 8),
                Text(
                  'Service Date: $formattedDate',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${setlist.items.length} items',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          if (setlist.notes != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Notes: ${setlist.notes!}',
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.black87,
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Setlist Order',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: setlist.items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = setlist.items[index];
                return ListTile(
                  leading: CircleAvatar(
                    radius: 14,
                    child: Text('${item.order}'),
                  ),
                  title: Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    [
                      if (item.artist != null) item.artist,
                      if (item.notes != null) 'Note: ${item.notes}',
                    ].join(' • '),
                  ),
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Key ${item.effectiveKey}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  onTap: () {
                    onSongTap(
                      SongItem(
                        id: item.songId,
                        title: item.title,
                        artist: item.artist,
                        defaultKey: item.effectiveKey,
                        tempoBpm: item.tempoBpm,
                        lyrics: item.lyrics,
                        chords: item.chords,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
