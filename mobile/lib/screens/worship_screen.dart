import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/worship_models.dart';
import '../services/worship_api_client.dart';

class WorshipScreen extends StatefulWidget {
  final WorshipApiClient? apiClient;
  final bool canManageWorship;
  final List<SongItem>? initialSongs;
  final List<SetlistItemData>? initialSetlists;

  const WorshipScreen({
    super.key,
    this.apiClient,
    this.canManageWorship = false,
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

  bool _loadingSongs = false;
  bool _hasLoadedSongs = false;
  String? _songLoadError;
  bool _savingSong = false;

  bool _loadingSetlists = false;
  bool _hasLoadedSetlists = false;
  String? _setlistLoadError;
  bool _savingSetlist = false;

  int _sessionGeneration = 0;
  final ValueNotifier<int> _sessionVersion = ValueNotifier<int>(0);
  int _songsLoadGeneration = 0;
  int _setlistsLoadGeneration = 0;

  bool get _isPreviewMode =>
      widget.apiClient == null &&
      (widget.initialSongs != null || widget.initialSetlists != null);

  bool get _isUnauthenticated => widget.apiClient == null && !_isPreviewMode;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_handleTabChanged);

    _songs = List<SongItem>.from(widget.initialSongs ?? const []);
    _setlists = List<SetlistItemData>.from(widget.initialSetlists ?? const []);
    _hasLoadedSongs = widget.initialSongs != null;
    _hasLoadedSetlists = widget.initialSetlists != null;

    if (widget.apiClient != null) {
      if (widget.initialSongs == null) {
        _loadSongs();
      }
      if (widget.initialSetlists == null) {
        _loadSetlists();
      }
    }
  }

  @override
  void didUpdateWidget(covariant WorshipScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiClient != widget.apiClient) {
      _sessionGeneration++;
      _sessionVersion.value = _sessionGeneration;
      _songsLoadGeneration++;
      _setlistsLoadGeneration++;
      _songs = List<SongItem>.from(widget.initialSongs ?? const []);
      _setlists = List<SetlistItemData>.from(widget.initialSetlists ?? const []);
      _songLoadError = null;
      _setlistLoadError = null;
      _loadingSongs = false;
      _hasLoadedSongs = widget.initialSongs != null;
      _loadingSetlists = false;
      _hasLoadedSetlists = widget.initialSetlists != null;
      _savingSong = false;
      _savingSetlist = false;

      if (widget.apiClient != null) {
        if (widget.initialSongs == null) {
          _loadSongs();
        }
        if (widget.initialSetlists == null) {
          _loadSetlists();
        }
      }
    }
  }

  void _handleTabChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _sessionVersion.dispose();
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  String _formatError(Object error) {
    if (error is WorshipApiException) {
      return error.message;
    }
    return error.toString();
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadSongs() async {
    final client = widget.apiClient;
    if (client == null) return;

    final capturedSession = _sessionGeneration;
    final capturedLoad = ++_songsLoadGeneration;

    setState(() {
      _loadingSongs = true;
      _songLoadError = null;
    });

    try {
      final songs = await client.getSongs();
      if (!mounted ||
          capturedSession != _sessionGeneration ||
          capturedLoad != _songsLoadGeneration ||
          widget.apiClient != client) {
        return;
      }
      setState(() {
        _songs = songs;
        _hasLoadedSongs = true;
        _loadingSongs = false;
      });
    } catch (error) {
      if (!mounted ||
          capturedSession != _sessionGeneration ||
          capturedLoad != _songsLoadGeneration ||
          widget.apiClient != client) {
        return;
      }
      setState(() {
        _songLoadError = _formatError(error);
        _loadingSongs = false;
      });
    }
  }

  Future<void> _loadSetlists() async {
    final client = widget.apiClient;
    if (client == null) return;

    final capturedSession = _sessionGeneration;
    final capturedLoad = ++_setlistsLoadGeneration;

    setState(() {
      _loadingSetlists = true;
      _setlistLoadError = null;
    });

    try {
      final setlists = await client.getSetlists();
      if (!mounted ||
          capturedSession != _sessionGeneration ||
          capturedLoad != _setlistsLoadGeneration ||
          widget.apiClient != client) {
        return;
      }
      setState(() {
        _setlists = setlists;
        _hasLoadedSetlists = true;
        _loadingSetlists = false;
      });
    } catch (error) {
      if (!mounted ||
          capturedSession != _sessionGeneration ||
          capturedLoad != _setlistsLoadGeneration ||
          widget.apiClient != client) {
        return;
      }
      setState(() {
        _setlistLoadError = _formatError(error);
        _loadingSetlists = false;
      });
    }
  }

  Future<SongItem> _saveSong({
    SongItem? existingSong,
    required SongInput input,
    WorshipApiClient? expectedClient,
    int? expectedSession,
  }) async {
    final client = widget.apiClient;
    final capturedSession = _sessionGeneration;

    if ((expectedSession != null && expectedSession != _sessionGeneration) ||
        (expectedSession != null && !identical(expectedClient, client)) ||
        !widget.canManageWorship) {
      throw const WorshipApiException(
        'Session changed while editor was open. Please reopen and try again.',
        statusCode: 401,
      );
    }

    if (client == null) {
      throw const WorshipApiException(
        'Authentication required. Please sign in.',
        statusCode: 401,
      );
    }

    final saved = existingSong == null
        ? await client.createSong(input)
        : await client.updateSong(existingSong.id, input);

    if (!mounted ||
        capturedSession != _sessionGeneration ||
        widget.apiClient != client) {
      throw const WorshipApiException(
        'Session changed while saving song.',
        statusCode: 401,
      );
    }

    final shouldReloadSongs = !_hasLoadedSongs || _loadingSongs;
    _songsLoadGeneration++;
    setState(() {
      _loadingSongs = false;
      if (existingSong == null) {
        _songs = [..._songs, saved];
      } else {
        _songs = _songs.map((s) => s.id == saved.id ? saved : s).toList();
      }
    });
    if (shouldReloadSongs) {
      unawaited(_loadSongs());
    }
    return saved;
  }

  Future<void> _confirmAndDeleteSong(SongItem song, {VoidCallback? onDeleted}) async {
    final client = widget.apiClient;
    if (client == null || !widget.canManageWorship) return;
    final capturedSession = _sessionGeneration;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Song'),
        content: Text('Are you sure you want to delete "${song.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('confirmDeleteSongButton'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true ||
        !mounted ||
        capturedSession != _sessionGeneration ||
        !identical(widget.apiClient, client) ||
        !widget.canManageWorship) {
      return;
    }

    try {
      await client.deleteSong(song.id);
      if (!mounted ||
          capturedSession != _sessionGeneration ||
          widget.apiClient != client) {
        return;
      }
      _songsLoadGeneration++;
      setState(() {
        _songs = _songs.where((s) => s.id != song.id).toList();
      });
      onDeleted?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted "${song.title}".')),
      );
    } catch (error) {
      if (!mounted ||
          capturedSession != _sessionGeneration ||
          widget.apiClient != client) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_formatError(error))),
      );
    }
  }

  Future<SetlistItemData> _saveSetlist({
    SetlistItemData? existingSetlist,
    required SetlistInput input,
    WorshipApiClient? expectedClient,
    int? expectedSession,
  }) async {
    final client = widget.apiClient;
    final capturedSession = _sessionGeneration;

    if ((expectedSession != null && expectedSession != _sessionGeneration) ||
        (expectedSession != null && !identical(expectedClient, client)) ||
        !widget.canManageWorship) {
      throw const WorshipApiException(
        'Session changed while editor was open. Please reopen and try again.',
        statusCode: 401,
      );
    }

    if (client == null) {
      throw const WorshipApiException(
        'Authentication required. Please sign in.',
        statusCode: 401,
      );
    }

    final saved = existingSetlist == null
        ? await client.createSetlist(input)
        : await client.updateSetlist(existingSetlist.id, input);

    if (!mounted ||
        capturedSession != _sessionGeneration ||
        widget.apiClient != client) {
      throw const WorshipApiException(
        'Session changed while saving setlist.',
        statusCode: 401,
      );
    }

    final shouldReloadSetlists = !_hasLoadedSetlists || _loadingSetlists;
    _setlistsLoadGeneration++;
    setState(() {
      _loadingSetlists = false;
      if (existingSetlist == null) {
        _setlists = [saved, ..._setlists];
      } else {
        _setlists = _setlists.map((s) => s.id == saved.id ? saved : s).toList();
      }
    });
    if (shouldReloadSetlists) {
      unawaited(_loadSetlists());
    }
    return saved;
  }

  Future<void> _confirmAndDeleteSetlist(
    SetlistItemData setlist, {
    VoidCallback? onDeleted,
  }) async {
    final client = widget.apiClient;
    if (client == null || !widget.canManageWorship) return;
    final capturedSession = _sessionGeneration;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Setlist'),
        content: Text('Are you sure you want to delete "${setlist.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('confirmDeleteSetlistButton'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true ||
        !mounted ||
        capturedSession != _sessionGeneration ||
        !identical(widget.apiClient, client) ||
        !widget.canManageWorship) {
      return;
    }

    try {
      await client.deleteSetlist(setlist.id);
      if (!mounted ||
          capturedSession != _sessionGeneration ||
          widget.apiClient != client) {
        return;
      }
      _setlistsLoadGeneration++;
      setState(() {
        _setlists = _setlists.where((s) => s.id != setlist.id).toList();
      });
      onDeleted?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted "${setlist.title}".')),
      );
    } catch (error) {
      if (!mounted ||
          capturedSession != _sessionGeneration ||
          widget.apiClient != client) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_formatError(error))),
      );
    }
  }

  void _openSongDetail(SongItem song, {bool isSetlistPreview = false}) {
    final capturedClient = widget.apiClient;
    final capturedSession = _sessionGeneration;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => _SongDetailSheet(
        song: song,
        isSetlistPreview: isSetlistPreview,
        apiClient: capturedClient,
        sessionListenable: _sessionVersion,
        expectedSession: capturedSession,
        canManageWorship: widget.canManageWorship,
        onEdit: widget.canManageWorship
            ? (currentSong) {
                Navigator.of(sheetContext).pop();
                if (!mounted ||
                    capturedSession != _sessionGeneration ||
                    !identical(widget.apiClient, capturedClient)) {
                  return;
                }
                _openSongFormDialog(existingSong: currentSong);
              }
            : null,
        onDelete: widget.canManageWorship
            ? (currentSong) {
                if (!mounted ||
                    capturedSession != _sessionGeneration ||
                    !identical(widget.apiClient, capturedClient)) {
                  return;
                }
                _confirmAndDeleteSong(
                  currentSong,
                  onDeleted: () {
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                  },
                );
              }
            : null,
      ),
    );
  }

  void _openSetlistDetail(SetlistItemData setlist) {
    final capturedClient = widget.apiClient;
    final capturedSession = _sessionGeneration;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => _SetlistDetailScreen(
          setlist: setlist,
          apiClient: capturedClient,
          sessionListenable: _sessionVersion,
          expectedSession: capturedSession,
          canManageWorship: widget.canManageWorship,
          onSongTap: (songItem, {isSetlistPreview = true}) {
            if (!mounted ||
                capturedSession != _sessionGeneration ||
                !identical(widget.apiClient, capturedClient)) {
              return;
            }
            _openSongDetail(songItem, isSetlistPreview: isSetlistPreview);
          },
          onSetlistLoaded: (loadedSetlist) {
            if (!mounted ||
                capturedSession != _sessionGeneration ||
                !identical(widget.apiClient, capturedClient)) {
              return;
            }
            setState(() {
              _setlists = _setlists
                  .map((s) => s.id == loadedSetlist.id ? loadedSetlist : s)
                  .toList();
            });
          },
          onEditSetlist: widget.canManageWorship
              ? (currentSetlist, updateDetailState) {
                  if (!mounted ||
                      capturedSession != _sessionGeneration ||
                      !identical(widget.apiClient, capturedClient)) {
                    return;
                  }
                  _openSetlistFormDialog(
                    existingSetlist: currentSetlist,
                    onSaved: updateDetailState,
                  );
                }
              : null,
          onDeleteSetlist: widget.canManageWorship
              ? (currentSetlist) {
                  if (!mounted ||
                      capturedSession != _sessionGeneration ||
                      !identical(widget.apiClient, capturedClient)) {
                    return;
                  }
                  _confirmAndDeleteSetlist(
                    currentSetlist,
                    onDeleted: () {
                      if (routeContext.mounted) {
                        Navigator.of(routeContext).pop();
                      }
                    },
                  );
                }
              : null,
        ),
      ),
    );
  }

  void _openSongFormDialog({SongItem? existingSong}) {
    if (!widget.canManageWorship) return;
    final capturedClient = widget.apiClient;
    final capturedSession = _sessionGeneration;
    final titleController = TextEditingController(text: existingSong?.title ?? '');
    final artistController = TextEditingController(text: existingSong?.artist ?? '');
    final keyController = TextEditingController(
      text: existingSong == null ? 'G' : (existingSong.defaultKey ?? ''),
    );
    final tempoController = TextEditingController(
      text: existingSong == null
          ? '72'
          : (existingSong.tempoBpm?.toString() ?? ''),
    );
    final lyricsController = TextEditingController(text: existingSong?.lyrics ?? '');
    final chordsController = TextEditingController(text: existingSong?.chords ?? '');
    String? dialogError;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existingSong == null ? 'Add Song to Library' : 'Edit Song'),
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
                if (dialogError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    dialogError!,
                    key: const Key('songFormErrorText'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              key: const Key('saveSongButton'),
              onPressed: _savingSong
                  ? null
                  : () async {
                      if (titleController.text.trim().isEmpty) return;
                      setState(() => _savingSong = true);
                      setDialogState(() => dialogError = null);
                      try {
                        await _saveSong(
                          existingSong: existingSong,
                          expectedClient: capturedClient,
                          expectedSession: capturedSession,
                          input: SongInput(
                            title: titleController.text.trim(),
                            artist: artistController.text.trim().isEmpty
                                ? null
                                : artistController.text.trim(),
                            defaultKey: keyController.text.trim().isEmpty
                                ? null
                                : keyController.text.trim(),
                            tempoBpm: int.tryParse(tempoController.text.trim()),
                            lyrics: lyricsController.text.trim(),
                            chords: chordsController.text.trim(),
                          ),
                        );
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      } catch (error) {
                        final msg = _formatError(error);
                        if (dialogContext.mounted) {
                          setDialogState(() => dialogError = msg);
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(content: Text(msg)),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _savingSong = false);
                        if (dialogContext.mounted) setDialogState(() {});
                      }
                    },
              child: const Text('Save Song'),
            ),
          ],
        ),
      ),
    );
  }

  void _openSetlistFormDialog({
    SetlistItemData? existingSetlist,
    ValueChanged<SetlistItemData>? onSaved,
  }) {
    if (!widget.canManageWorship) return;
    final capturedClient = widget.apiClient;
    final capturedSession = _sessionGeneration;
    var activeExisting = existingSetlist;
    var defaultDate = existingSetlist?.serviceDate ??
        DateTime.now().toUtc().add(const Duration(days: 2));
    final titleController =
        TextEditingController(text: existingSetlist?.title ?? '');
    final dateController =
        TextEditingController(text: _formatDate(defaultDate));
    final notesController =
        TextEditingController(text: existingSetlist?.notes ?? '');

    final selectedItems = <SetlistSongInput>[
      if (existingSetlist != null)
        ...existingSetlist.items.map(
          (item) => SetlistSongInput(
            songId: item.songId,
            order: item.order,
            keyOverride: item.keyOverride,
            notes: item.notes,
          ),
        ),
    ];

    bool isLoadingDetail = existingSetlist != null && widget.apiClient != null;
    bool detailLoadStarted = false;
    String? detailLoadError;
    String? dialogError;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> loadSetlistDetail() async {
            final client = widget.apiClient;
            if (existingSetlist == null || client == null) return;
            if (capturedSession != _sessionGeneration ||
                !identical(client, capturedClient)) {
              if (dialogContext.mounted) {
                setDialogState(() {
                  isLoadingDetail = false;
                  detailLoadError =
                      'Session changed while editor was open. Please reopen and try again.';
                });
              }
              return;
            }
            if (dialogContext.mounted) {
              setDialogState(() {
                isLoadingDetail = true;
                detailLoadError = null;
              });
            }
            try {
              final fetched = await client.getSetlist(existingSetlist.id);
              if (!dialogContext.mounted ||
                  !mounted ||
                  capturedSession != _sessionGeneration ||
                  !identical(widget.apiClient, capturedClient)) {
                return;
              }
              activeExisting = fetched;
              defaultDate = fetched.serviceDate;
              titleController.text = fetched.title;
              dateController.text = _formatDate(fetched.serviceDate);
              notesController.text = fetched.notes ?? '';
              selectedItems
                ..clear()
                ..addAll(
                  fetched.items.map(
                    (item) => SetlistSongInput(
                      songId: item.songId,
                      order: item.order,
                      keyOverride: item.keyOverride,
                      notes: item.notes,
                    ),
                  ),
                );
              setDialogState(() {
                isLoadingDetail = false;
                detailLoadError = null;
              });
            } catch (error) {
              if (!dialogContext.mounted ||
                  !mounted ||
                  capturedSession != _sessionGeneration ||
                  !identical(widget.apiClient, capturedClient)) {
                return;
              }
              setDialogState(() {
                isLoadingDetail = false;
                detailLoadError = _formatError(error);
              });
            }
          }

          if (!detailLoadStarted && isLoadingDetail) {
            detailLoadStarted = true;
            Future.microtask(loadSetlistDetail);
          }

          final bool formBlocked = isLoadingDetail || detailLoadError != null;

          return AlertDialog(
            title: Text(
              existingSetlist == null ? 'Create Sunday Setlist' : 'Edit Setlist',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isLoadingDetail) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    const Text('Loading setlist songs...'),
                    const SizedBox(height: 12),
                  ],
                  if (detailLoadError != null) ...[
                    Text(
                      detailLoadError!,
                      key: const Key('setlistDetailErrorText'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      key: const Key('retrySetlistDetailButton'),
                      onPressed: loadSetlistDetail,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry loading setlist'),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    key: const Key('setlistTitleField'),
                    controller: titleController,
                    enabled: !formBlocked,
                    decoration:
                        const InputDecoration(labelText: 'Setlist Title *'),
                  ),
                  TextField(
                    key: const Key('setlistDateField'),
                    controller: dateController,
                    enabled: !formBlocked,
                    decoration: const InputDecoration(
                      labelText: 'Service Date (YYYY-MM-DD)',
                    ),
                  ),
                  TextField(
                    key: const Key('setlistNotesField'),
                    controller: notesController,
                    enabled: !formBlocked,
                    decoration:
                        const InputDecoration(labelText: 'Service Notes'),
                    maxLines: 2,
                  ),
                  if (_songs.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Select Songs for Setlist',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    for (final song in _songs)
                      CheckboxListTile(
                        key: Key('selectSetlistSong_${song.id}'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(song.title),
                        subtitle: song.defaultKey != null
                            ? Text('Key ${song.defaultKey}')
                            : null,
                        value: selectedItems.any((item) => item.songId == song.id),
                        onChanged: formBlocked
                            ? null
                            : (checked) {
                                setDialogState(() {
                                  if (checked == true) {
                                    if (!selectedItems.any((item) => item.songId == song.id)) {
                                      selectedItems.add(
                                        SetlistSongInput(
                                          songId: song.id,
                                          order: selectedItems.length + 1,
                                        ),
                                      );
                                    }
                                  } else {
                                    selectedItems.removeWhere((item) => item.songId == song.id);
                                  }
                                });
                              },
                      ),
                  ],
                  if (dialogError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      dialogError!,
                      key: const Key('setlistFormErrorText'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                key: const Key('saveSetlistButton'),
                onPressed: (_savingSetlist || formBlocked)
                    ? null
                    : () async {
                        if (titleController.text.trim().isEmpty) return;
                        final parsedDate = SetlistInput.parseUtcCalendarDate(
                          dateController.text,
                          defaultDate,
                        );
                        final items = <SetlistSongInput>[
                          for (var i = 0; i < selectedItems.length; i++)
                            SetlistSongInput(
                              songId: selectedItems[i].songId,
                              order: i + 1,
                              keyOverride: selectedItems[i].keyOverride,
                              notes: selectedItems[i].notes,
                            ),
                        ];

                        setState(() => _savingSetlist = true);
                        setDialogState(() => dialogError = null);
                        try {
                          final saved = await _saveSetlist(
                            existingSetlist: activeExisting,
                            expectedClient: capturedClient,
                            expectedSession: capturedSession,
                            input: SetlistInput(
                              title: titleController.text.trim(),
                              serviceDate: parsedDate,
                              notes: notesController.text.trim().isEmpty
                                  ? null
                                  : notesController.text.trim(),
                              items: items,
                            ),
                          );
                          onSaved?.call(saved);
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                        } catch (error) {
                          final msg = _formatError(error);
                          if (dialogContext.mounted) {
                            setDialogState(() => dialogError = msg);
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(content: Text(msg)),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _savingSetlist = false);
                          if (dialogContext.mounted) setDialogState(() {});
                        }
                      },
                child: const Text('Save Setlist'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUnauthenticatedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'Sign In Required',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please sign in to view the church worship library and service setlists.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildFloatingActionButton() {
    if (!widget.canManageWorship || _isUnauthenticated) {
      return null;
    }
    if (_tabController.index == 1) {
      return FloatingActionButton.extended(
        key: const Key('addSetlistFab'),
        onPressed: () => _openSetlistFormDialog(),
        icon: const Icon(Icons.playlist_add),
        label: const Text('Add Setlist'),
      );
    }
    return FloatingActionButton.extended(
      key: const Key('addSongFab'),
      onPressed: () => _openSongFormDialog(),
      icon: const Icon(Icons.add),
      label: const Text('Add Song'),
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
      body: _isUnauthenticated
          ? _buildUnauthenticatedState()
          : TabBarView(
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
                      child: _loadingSongs
                          ? const Center(child: CircularProgressIndicator())
                          : _songLoadError != null
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24.0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                          'Could not load the worship library.',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _songLoadError!,
                                          key: const Key('songLoadErrorText'),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        TextButton(
                                          key: const Key('retrySongsButton'),
                                          onPressed: _loadSongs,
                                          child: const Text('Retry'),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : filteredSongs.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No songs found.',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    )
                                  : ListView.separated(
                                      key: const Key('songsListView'),
                                      itemCount: filteredSongs.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final song = filteredSongs[index];
                                        return ListTile(
                                          key: Key('songItem_${song.id}'),
                                          title: Text(
                                            song.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          subtitle: Text(
                                            song.artist ?? 'Traditional',
                                            style:
                                                const TextStyle(fontSize: 13),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (song.defaultKey != null)
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.blue.shade50,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      6,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    'Key ${song.defaultKey}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color:
                                                          Colors.blue.shade800,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              if (song.tempoBpm != null) ...[
                                                const SizedBox(width: 6),
                                                Text(
                                                  '${song.tempoBpm} BPM',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ],
                                              if (widget.canManageWorship) ...[
                                                IconButton(
                                                  key: Key(
                                                    'editSongButton_${song.id}',
                                                  ),
                                                  icon: const Icon(
                                                    Icons.edit_outlined,
                                                    size: 20,
                                                  ),
                                                  tooltip: 'Edit Song',
                                                  onPressed: () =>
                                                      _openSongFormDialog(
                                                    existingSong: song,
                                                  ),
                                                ),
                                                IconButton(
                                                  key: Key(
                                                    'deleteSongButton_${song.id}',
                                                  ),
                                                  icon: const Icon(
                                                    Icons.delete_outline,
                                                    size: 20,
                                                  ),
                                                  tooltip: 'Delete Song',
                                                  onPressed: () =>
                                                      _confirmAndDeleteSong(
                                                    song,
                                                  ),
                                                ),
                                              ] else ...[
                                                const SizedBox(width: 8),
                                                const Icon(
                                                  Icons.chevron_right,
                                                  color: Colors.grey,
                                                ),
                                              ],
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
                _loadingSetlists
                    ? const Center(child: CircularProgressIndicator())
                    : _setlistLoadError != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Could not load service setlists.',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _setlistLoadError!,
                                    key: const Key('setlistLoadErrorText'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton(
                                    key: const Key('retrySetlistsButton'),
                                    onPressed: _loadSetlists,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _setlists.isEmpty
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
                                      _formatDate(setlist.serviceDate);
                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    child: ListTile(
                                      key: Key('setlistItem_${setlist.id}'),
                                      leading: CircleAvatar(
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer,
                                        child: Icon(
                                          Icons.calendar_month,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onPrimaryContainer,
                                        ),
                                      ),
                                      title: Text(
                                        setlist.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 2),
                                          Text('Service Date: $formattedDate'),
                                          if (setlist.notes != null)
                                            Text(
                                              setlist.notes!,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54,
                                              ),
                                            ),
                                        ],
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              '${setlist.effectiveItemCount} songs',
                                              style: TextStyle(
                                                color: Colors.green.shade800,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          if (widget.canManageWorship) ...[
                                            IconButton(
                                              key: Key(
                                                'editSetlistButton_${setlist.id}',
                                              ),
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                                size: 20,
                                              ),
                                              tooltip: 'Edit Setlist',
                                              onPressed: () =>
                                                  _openSetlistFormDialog(
                                                existingSetlist: setlist,
                                              ),
                                            ),
                                            IconButton(
                                              key: Key(
                                                'deleteSetlistButton_${setlist.id}',
                                              ),
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                size: 20,
                                              ),
                                              tooltip: 'Delete Setlist',
                                              onPressed: () =>
                                                  _confirmAndDeleteSetlist(
                                                setlist,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      onTap: () => _openSetlistDetail(setlist),
                                    ),
                                  );
                                },
                              ),
              ],
            ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }
}

class _SongDetailSheet extends StatefulWidget {
  final SongItem song;
  final bool isSetlistPreview;
  final WorshipApiClient? apiClient;
  final ValueListenable<int>? sessionListenable;
  final int? expectedSession;
  final bool canManageWorship;
  final ValueChanged<SongItem>? onEdit;
  final ValueChanged<SongItem>? onDelete;

  const _SongDetailSheet({
    required this.song,
    this.isSetlistPreview = false,
    this.apiClient,
    this.sessionListenable,
    this.expectedSession,
    this.canManageWorship = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<_SongDetailSheet> createState() => _SongDetailSheetState();
}

class _SongDetailSheetState extends State<_SongDetailSheet> {
  late SongItem _song;
  SongItem? _canonicalSong;
  bool _showChords = true;
  bool _loadingDetail = false;
  bool _loadingCanonicalForEdit = false;
  String? _editError;
  bool _sessionInvalidated = false;
  ModalRoute<dynamic>? _route;

  bool get _isSessionActive =>
      mounted &&
      !_sessionInvalidated &&
      (widget.expectedSession == null ||
          widget.sessionListenable?.value == widget.expectedSession);

  @override
  void initState() {
    super.initState();
    _song = widget.song;
    widget.sessionListenable?.addListener(_handleSessionChanged);
    if (_isSessionActive &&
        widget.apiClient != null &&
        ((_song.lyrics.isEmpty && _song.chords.isEmpty) ||
            widget.isSetlistPreview)) {
      _fetchSongDetail();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route ??= ModalRoute.of(context);
  }

  @override
  void didUpdateWidget(covariant _SongDetailSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionListenable != widget.sessionListenable) {
      oldWidget.sessionListenable?.removeListener(_handleSessionChanged);
      widget.sessionListenable?.addListener(_handleSessionChanged);
    }
    _handleSessionChanged();
  }

  @override
  void dispose() {
    widget.sessionListenable?.removeListener(_handleSessionChanged);
    super.dispose();
  }

  void _handleSessionChanged() {
    if (_sessionInvalidated) return;
    if (widget.expectedSession != null &&
        widget.sessionListenable?.value != widget.expectedSession) {
      _sessionInvalidated = true;
      final route = _route;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (route != null && route.isActive) {
          Navigator.of(context).removeRoute(route);
        } else {
          setState(() {});
        }
      });
    }
  }

  SongItem _mergeSetlistDisplay(SongItem fetched) {
    if (!widget.isSetlistPreview) {
      return fetched;
    }
    return SongItem(
      id: fetched.id,
      churchId: fetched.churchId,
      title: fetched.title,
      artist: fetched.artist,
      defaultKey: widget.song.defaultKey ?? fetched.defaultKey,
      tempoBpm: fetched.tempoBpm,
      lyrics: fetched.lyrics.isNotEmpty ? fetched.lyrics : _song.lyrics,
      chords: fetched.chords.isNotEmpty ? fetched.chords : _song.chords,
      createdAt: fetched.createdAt,
    );
  }

  Future<void> _fetchSongDetail() async {
    final client = widget.apiClient;
    if (client == null || !_isSessionActive) return;
    setState(() => _loadingDetail = true);
    try {
      final fetched = await client.getSong(_song.id);
      if (!_isSessionActive) return;
      _canonicalSong = fetched;
      setState(() {
        _song = _mergeSetlistDisplay(fetched);
        _loadingDetail = false;
      });
    } catch (_) {
      if (!_isSessionActive) return;
      setState(() => _loadingDetail = false);
    }
  }

  Future<void> _handleEditTap() async {
    final onEdit = widget.onEdit;
    if (onEdit == null) return;
    SongItem targetSong = _canonicalSong ?? _song;
    if (widget.isSetlistPreview && _canonicalSong == null) {
      final client = widget.apiClient;
      if (client == null) {
        setState(() => _editError = 'Unable to load library song defaults.');
        return;
      }
      setState(() {
        _loadingCanonicalForEdit = true;
        _editError = null;
      });
      try {
        final fetched = await client.getSong(_song.id);
        if (!_isSessionActive) return;
        _canonicalSong = fetched;
        targetSong = fetched;
      } catch (_) {
        if (!_isSessionActive) return;
        setState(() {
          _loadingCanonicalForEdit = false;
          _editError = 'Could not load library song defaults before editing.';
        });
        return;
      }
      setState(() => _loadingCanonicalForEdit = false);
    }
    if (!_isSessionActive) return;
    onEdit(targetSong);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSessionActive) {
      return const SizedBox.shrink();
    }
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
                          _song.title,
                          key: const Key('songDetailTitle'),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_song.artist != null)
                          Text(
                            _song.artist!,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.canManageWorship && widget.onEdit != null)
                    IconButton(
                      key: const Key('editSongDetailButton'),
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit Song',
                      onPressed: _loadingCanonicalForEdit ? null : _handleEditTap,
                    ),
                  if (widget.canManageWorship && widget.onDelete != null)
                    IconButton(
                      key: const Key('deleteSongDetailButton'),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete Song',
                      onPressed: () => widget.onDelete!(_song),
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
                  if (_song.defaultKey != null)
                    Chip(
                      label: Text('Key: ${_song.defaultKey}'),
                      backgroundColor: Colors.blue.shade50,
                    ),
                  const SizedBox(width: 8),
                  if (_song.tempoBpm != null)
                    Chip(
                      label: Text('${_song.tempoBpm} BPM'),
                      backgroundColor: Colors.orange.shade50,
                    ),
                  const Spacer(),
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
              if (_editError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _editError!,
                  key: const Key('songDetailEditErrorText'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ],
              const Divider(height: 24),
              Expanded(
                child: _loadingDetail
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
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
                                ? (_song.chords.isNotEmpty
                                    ? _song.chords
                                    : _song.lyrics)
                                : _song.lyrics,
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

class _SetlistDetailScreen extends StatefulWidget {
  final SetlistItemData setlist;
  final WorshipApiClient? apiClient;
  final ValueListenable<int>? sessionListenable;
  final int? expectedSession;
  final bool canManageWorship;
  final void Function(SongItem song, {bool isSetlistPreview}) onSongTap;
  final ValueChanged<SetlistItemData>? onSetlistLoaded;
  final void Function(
    SetlistItemData currentSetlist,
    ValueChanged<SetlistItemData> updateDetailState,
  )? onEditSetlist;
  final ValueChanged<SetlistItemData>? onDeleteSetlist;

  const _SetlistDetailScreen({
    required this.setlist,
    this.apiClient,
    this.sessionListenable,
    this.expectedSession,
    this.canManageWorship = false,
    required this.onSongTap,
    this.onSetlistLoaded,
    this.onEditSetlist,
    this.onDeleteSetlist,
  });

  @override
  State<_SetlistDetailScreen> createState() => _SetlistDetailScreenState();
}

class _SetlistDetailScreenState extends State<_SetlistDetailScreen> {
  late SetlistItemData _setlist;
  bool _loadingDetail = false;
  String? _detailError;
  bool _sessionInvalidated = false;
  ModalRoute<dynamic>? _route;

  bool get _isSessionActive =>
      mounted &&
      !_sessionInvalidated &&
      (widget.expectedSession == null ||
          widget.sessionListenable?.value == widget.expectedSession);

  @override
  void initState() {
    super.initState();
    _setlist = widget.setlist;
    widget.sessionListenable?.addListener(_handleSessionChanged);
    if (_isSessionActive && widget.apiClient != null) {
      _loadSetlistDetail();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route ??= ModalRoute.of(context);
  }

  @override
  void didUpdateWidget(covariant _SetlistDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionListenable != widget.sessionListenable) {
      oldWidget.sessionListenable?.removeListener(_handleSessionChanged);
      widget.sessionListenable?.addListener(_handleSessionChanged);
    }
    _handleSessionChanged();
  }

  @override
  void dispose() {
    widget.sessionListenable?.removeListener(_handleSessionChanged);
    super.dispose();
  }

  void _handleSessionChanged() {
    if (_sessionInvalidated) return;
    if (widget.expectedSession != null &&
        widget.sessionListenable?.value != widget.expectedSession) {
      _sessionInvalidated = true;
      final route = _route;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (route != null && route.isActive) {
          Navigator.of(context).removeRoute(route);
        } else {
          setState(() {});
        }
      });
    }
  }

  Future<void> _loadSetlistDetail() async {
    final client = widget.apiClient;
    if (client == null || !_isSessionActive) return;
    setState(() {
      _loadingDetail = true;
      _detailError = null;
    });
    try {
      final fetched = await client.getSetlist(_setlist.id);
      if (!_isSessionActive) return;
      setState(() {
        _setlist = fetched;
        _loadingDetail = false;
      });
      widget.onSetlistLoaded?.call(fetched);
    } catch (error) {
      if (!_isSessionActive) return;
      setState(() {
        _detailError = error is WorshipApiException
            ? error.message
            : error.toString();
        _loadingDetail = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSessionActive) {
      return const SizedBox.shrink();
    }
    final formattedDate =
        '${_setlist.serviceDate.year}-${_setlist.serviceDate.month.toString().padLeft(2, '0')}-${_setlist.serviceDate.day.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: Text(_setlist.title),
        actions: [
          if (widget.canManageWorship && widget.onEditSetlist != null)
            IconButton(
              key: const Key('editSetlistDetailButton'),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Setlist',
              onPressed: () => widget.onEditSetlist!(
                _setlist,
                (updated) {
                  if (mounted) {
                    setState(() => _setlist = updated);
                  }
                },
              ),
            ),
          if (widget.canManageWorship && widget.onDeleteSetlist != null)
            IconButton(
              key: const Key('deleteSetlistDetailButton'),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete Setlist',
              onPressed: () => widget.onDeleteSetlist!(_setlist),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color:
                Theme.of(context).colorScheme.primaryContainer.withAlpha(50),
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
                  '${_setlist.effectiveItemCount} items',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          if (_setlist.notes != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Notes: ${_setlist.notes!}',
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
            child: _loadingDetail && _setlist.items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _detailError != null && _setlist.items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _detailError!,
                              key: const Key('setlistDetailErrorText'),
                              textAlign: TextAlign.center,
                            ),
                            TextButton(
                              key: const Key('retrySetlistDetailButton'),
                              onPressed: _loadSetlistDetail,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _setlist.items.isEmpty
                        ? const Center(
                            child: Text(
                              'No songs in this setlist.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _setlist.items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = _setlist.items[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 14,
                                  child: Text('${item.order}'),
                                ),
                                title: Text(
                                  item.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  [
                                    if (item.artist != null) item.artist,
                                    if (item.notes != null) 'Note: ${item.notes}',
                                  ].join(' • '),
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
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
                                  widget.onSongTap(
                                    SongItem(
                                      id: item.songId,
                                      title: item.title,
                                      artist: item.artist,
                                      defaultKey: item.effectiveKey,
                                      tempoBpm: item.tempoBpm,
                                      lyrics: item.lyrics,
                                      chords: item.chords,
                                    ),
                                    isSetlistPreview: true,
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
