import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Professional Black/White/Smoke Palette
const Color primaryBlack = Color(0xFF000000);
const Color primaryWhite = Color(0xFFFFFFFF);
const Color smokeGrey = Color(0xFFF5F5F5);
const Color darkSmoke = Color(0xFF2C2C2C);
const Color mediumGrey = Color(0xFF757575);
const Color lightGrey = Color(0xFFBDBDBD);
const Color almostBlack = Color(0xFF1E1E1E);

// Functional highlights
const Color highlightSuccess = Color(0xFF4CAF50);
const Color highlightWarning = Color(0xFFFFA726);
const Color highlightError = Color(0xFFEF5350);
const Color highlightInfo = Color(0xFF78909C);

class BandLibraryScreen extends StatefulWidget {
  const BandLibraryScreen({super.key});

  @override
  State<BandLibraryScreen> createState() => _BandLibraryScreenState();
}

class _BandLibraryScreenState extends State<BandLibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedView = 'list';
  
  final CollectionReference _songsCollection = 
      FirebaseFirestore.instance.collection('band_songs');
  
  StreamSubscription<QuerySnapshot>? _songsSubscription;
  List<SongModel> _allSongs = [];
  List<SongModel> _filteredSongs = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _currentUserId;
  String _currentUserName = '';

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _loadCurrentUserName();
    _listenToSongs();
  }

  @override
  void dispose() {
    _songsSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      setState(() {
        _currentUserName = doc.data()?['name'] ?? 'User';
      });
    }
  }

  void _listenToSongs() {
    _songsSubscription = _songsCollection
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      setState(() {
        _allSongs = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return SongModel(
            id: doc.id,
            title: data['title'] ?? '',
            artist: data['artist'] ?? '',
            youtubeUrl: data['youtubeUrl'] ?? '',
            youtubeVideoId: data['youtubeVideoId'] ?? '',
            key: data['key'] ?? '',
            lyrics: data['lyrics'] ?? '',
            chords: data['chords'] ?? '',
            createdBy: data['createdBy'] ?? '',
            createdByName: data['createdByName'] ?? '',
            createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
            updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          );
        }).toList();
        _applyFilters();
        _isLoading = false;
        _isRefreshing = false;
      });
    }, onError: (error) {
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading songs: $error'), backgroundColor: highlightError),
      );
    });
  }

  // ✅ Pull to Refresh function
  Future<void> _onRefresh() async {
    setState(() {
      _isRefreshing = true;
    });
    
    // Manually trigger a refresh by re-listening
    _songsSubscription?.cancel();
    _listenToSongs();
    
    // Wait a bit to ensure refresh feels natural
    await Future.delayed(const Duration(milliseconds: 500));
  }

  void _applyFilters() {
    List<SongModel> filtered = List.from(_allSongs);
    
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((song) =>
          song.title.toLowerCase().contains(query) ||
          song.artist.toLowerCase().contains(query) ||
          song.key.toLowerCase().contains(query) ||
          song.createdByName.toLowerCase().contains(query) ||
          song.lyrics.toLowerCase().contains(query) ||
          song.chords.toLowerCase().contains(query)).toList();
    }
    
    filtered.sort((a, b) => a.title.compareTo(b.title));
    
    setState(() {
      _filteredSongs = filtered;
    });
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _applyFilters();
    });
  }

  Future<void> _addOrEditSong({SongModel? existingSong}) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AddEditSongDialog(
        existingSong: existingSong,
        currentUserId: _currentUserId,
        currentUserName: _currentUserName,
      ),
    );
    
    if (result != null) {
      setState(() {
        _isLoading = true;
      });
      
      try {
        if (existingSong == null) {
          await _songsCollection.add({
            ...result,
            'createdBy': _currentUserId,
            'createdByName': _currentUserName,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          await _songsCollection.doc(existingSong.id).update({
            ...result,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(existingSong == null ? 'Song added successfully!' : 'Song updated successfully!'),
              backgroundColor: highlightSuccess,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: highlightError),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _deleteSong(SongModel song) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: almostBlack,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Song', style: TextStyle(color: lightGrey, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${song.title}"?', style: const TextStyle(color: primaryWhite)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: mediumGrey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: highlightError, foregroundColor: primaryWhite),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      setState(() {
        _isLoading = true;
      });
      
      try {
        await _songsCollection.doc(song.id).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${song.title}" deleted'), backgroundColor: highlightWarning),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: highlightError),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  void _viewSongDetails(SongModel song) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SongDetailScreen(
          song: song,
          onEdit: () => _addOrEditSong(existingSong: song),
          onDelete: () => _deleteSong(song),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [primaryBlack, almostBlack, darkSmoke],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Band Library'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: lightGrey,
          actions: [
            IconButton(
              icon: Icon(_selectedView == 'list' ? Icons.grid_view : Icons.list),
              onPressed: () {
                setState(() {
                  _selectedView = _selectedView == 'list' ? 'grid' : 'list';
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _addOrEditSong(),
            ),
          ],
        ),
        body: Column(
          children: [
            // Search Bar
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Container(
                decoration: BoxDecoration(
                  color: almostBlack.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: mediumGrey),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(color: primaryWhite),
                  decoration: InputDecoration(
                    hintText: 'Search by title, artist, key, creator, lyrics, or chords...',
                    hintStyle: TextStyle(color: lightGrey),
                    prefixIcon: Icon(Icons.search, color: lightGrey),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: lightGrey),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Song count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_filteredSongs.length} songs',
                    style: TextStyle(color: lightGrey, fontSize: 12),
                  ),
                  if (_searchQuery.isNotEmpty)
                    Text(
                      'Search results',
                      style: TextStyle(color: lightGrey, fontSize: 10),
                    ),
                ],
              ),
            ),
            
            const SizedBox(height: 8),
            
            // ✅ Songs List/Grid with Pull to Refresh
            Expanded(
              child: _isLoading && !_isRefreshing
                  ? const Center(child: CircularProgressIndicator(color: lightGrey))
                  : _filteredSongs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.library_music, size: 64, color: lightGrey.withOpacity(0.5)),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isEmpty ? 'No songs yet' : 'No matching songs found',
                                style: TextStyle(color: lightGrey, fontSize: 16),
                              ),
                              if (_searchQuery.isEmpty)
                                const SizedBox(height: 8),
                              if (_searchQuery.isEmpty)
                                Text(
                                  'Tap the + button to add your first song',
                                  style: TextStyle(color: mediumGrey, fontSize: 12),
                                ),
                            ],
                          ),
                        )
                      : _selectedView == 'list'
                          ? RefreshIndicator(
                              onRefresh: _onRefresh,
                              color: lightGrey,
                              backgroundColor: almostBlack,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _filteredSongs.length,
                                itemBuilder: (context, index) => _buildSongCard(_filteredSongs[index]),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _onRefresh,
                              color: lightGrey,
                              backgroundColor: almostBlack,
                              child: GridView.builder(
                                padding: const EdgeInsets.all(12),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  childAspectRatio: 0.9,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                                itemCount: _filteredSongs.length,
                                itemBuilder: (context, index) => _buildGridSongCard(_filteredSongs[index]),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSongCard(SongModel song) {
    final isCurrentUser = song.createdBy == _currentUserId;
    
    return GestureDetector(
      onTap: () => _viewSongDetails(song),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isCurrentUser ? darkSmoke.withOpacity(0.6) : almostBlack,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isCurrentUser ? lightGrey : mediumGrey,
            width: isCurrentUser ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [mediumGrey, lightGrey]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.music_note, color: primaryWhite, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    style: const TextStyle(color: primaryWhite, fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    song.artist,
                    style: TextStyle(color: lightGrey, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: darkSmoke,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Key: ${song.key}',
                          style: TextStyle(color: lightGrey, fontSize: 10),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: darkSmoke,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person, size: 10, color: lightGrey.withOpacity(0.7)),
                            const SizedBox(width: 4),
                            Text(
                              song.createdByName,
                              style: TextStyle(color: lightGrey.withOpacity(0.7), fontSize: 9),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: lightGrey, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildGridSongCard(SongModel song) {
    final isCurrentUser = song.createdBy == _currentUserId;
    
    return GestureDetector(
      onTap: () => _viewSongDetails(song),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isCurrentUser ? darkSmoke.withOpacity(0.6) : almostBlack,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isCurrentUser ? lightGrey : mediumGrey,
            width: isCurrentUser ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [mediumGrey, lightGrey]),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Icon(Icons.music_note, color: primaryWhite, size: 32),
            ),
            const SizedBox(height: 10),
            Text(
              song.title,
              style: const TextStyle(color: primaryWhite, fontSize: 14, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              song.artist,
              style: TextStyle(color: lightGrey, fontSize: 11),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: darkSmoke,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Key: ${song.key}',
                style: TextStyle(color: lightGrey, fontSize: 9),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: darkSmoke,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person, size: 8, color: lightGrey.withOpacity(0.7)),
                  const SizedBox(width: 2),
                  Text(
                    song.createdByName.length > 10 
                        ? '${song.createdByName.substring(0, 10)}...' 
                        : song.createdByName,
                    style: TextStyle(color: lightGrey.withOpacity(0.7), fontSize: 8),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ========== SONG MODEL ==========
class SongModel {
  final String id;
  final String title;
  final String artist;
  final String youtubeUrl;
  final String youtubeVideoId;
  final String key;
  final String lyrics;
  final String chords;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  SongModel({
    required this.id,
    required this.title,
    required this.artist,
    required this.youtubeUrl,
    required this.youtubeVideoId,
    required this.key,
    required this.lyrics,
    required this.chords,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    required this.updatedAt,
  });
}

// ========== ADD/EDIT SONG DIALOG ==========
class AddEditSongDialog extends StatefulWidget {
  final SongModel? existingSong;
  final String? currentUserId;
  final String? currentUserName;
  
  const AddEditSongDialog({
    super.key,
    this.existingSong,
    this.currentUserId,
    this.currentUserName,
  });

  @override
  State<AddEditSongDialog> createState() => _AddEditSongDialogState();
}

class _AddEditSongDialogState extends State<AddEditSongDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _artistController = TextEditingController();
  final _youtubeUrlController = TextEditingController();
  final _keyController = TextEditingController();
  final _lyricsController = TextEditingController();
  final _chordsController = TextEditingController();
  
  String? _youtubeVideoId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingSong != null) {
      _titleController.text = widget.existingSong!.title;
      _artistController.text = widget.existingSong!.artist;
      _youtubeUrlController.text = widget.existingSong!.youtubeUrl;
      _youtubeVideoId = widget.existingSong!.youtubeVideoId;
      _keyController.text = widget.existingSong!.key;
      _lyricsController.text = widget.existingSong!.lyrics;
      _chordsController.text = widget.existingSong!.chords;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _youtubeUrlController.dispose();
    _keyController.dispose();
    _lyricsController.dispose();
    _chordsController.dispose();
    super.dispose();
  }

  String? _extractVideoId(String url) {
    final RegExp regex = RegExp(
      r'(?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?)\/|.*[?&]v=)|youtu\.be\/)([^"&?\/\s]{11})',
      caseSensitive: false,
    );
    final match = regex.firstMatch(url);
    return match?.group(1);
  }

  void _validateYoutubeUrl() {
    final url = _youtubeUrlController.text.trim();
    if (url.isNotEmpty) {
      final videoId = _extractVideoId(url);
      setState(() {
        _youtubeVideoId = videoId;
      });
      if (videoId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid YouTube URL'), backgroundColor: highlightError),
        );
      }
    } else {
      setState(() {
        _youtubeVideoId = null;
      });
    }
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });
      
      if (_youtubeUrlController.text.isNotEmpty && _youtubeVideoId == null) {
        _validateYoutubeUrl();
        if (_youtubeVideoId == null) {
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }
      
      final songData = {
        'title': _titleController.text.trim(),
        'artist': _artistController.text.trim(),
        'youtubeUrl': _youtubeUrlController.text.trim(),
        'youtubeVideoId': _youtubeVideoId ?? '',
        'key': _keyController.text.trim(),
        'lyrics': _lyricsController.text.trim(),
        'chords': _chordsController.text.trim(),
      };
      
      Navigator.pop(context, songData);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: almostBlack,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.existingSong == null ? 'Add New Song' : 'Edit Song',
                  style: const TextStyle(color: primaryWhite, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: lightGrey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _titleController,
                        style: const TextStyle(color: primaryWhite),
                        decoration: InputDecoration(
                          labelText: 'Song Title *',
                          labelStyle: TextStyle(color: lightGrey),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: mediumGrey),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: lightGrey),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _artistController,
                        style: const TextStyle(color: primaryWhite),
                        decoration: InputDecoration(
                          labelText: 'Artist/Band *',
                          labelStyle: TextStyle(color: lightGrey),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: mediumGrey),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: lightGrey),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _youtubeUrlController,
                        onChanged: (_) => _validateYoutubeUrl(),
                        style: const TextStyle(color: primaryWhite),
                        decoration: InputDecoration(
                          labelText: 'YouTube URL (optional)',
                          labelStyle: TextStyle(color: lightGrey),
                          hintText: 'https://youtube.com/watch?v=...',
                          hintStyle: TextStyle(color: mediumGrey),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: mediumGrey),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: lightGrey),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          suffixIcon: _youtubeVideoId != null
                              ? Icon(Icons.check_circle, color: highlightSuccess)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _keyController,
                        style: const TextStyle(color: primaryWhite),
                        decoration: InputDecoration(
                          labelText: 'Key *',
                          labelStyle: TextStyle(color: lightGrey),
                          hintText: 'e.g., G, C, Dm, Eb',
                          hintStyle: TextStyle(color: mediumGrey),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: mediumGrey),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: lightGrey),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Lyrics',
                        style: TextStyle(color: primaryWhite, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: mediumGrey),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextFormField(
                          controller: _lyricsController,
                          maxLines: 8,
                          style: const TextStyle(color: primaryWhite, fontSize: 12),
                          decoration: const InputDecoration(
                            hintText: 'Paste lyrics here...',
                            hintStyle: TextStyle(color: mediumGrey, fontSize: 11),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Chords',
                        style: TextStyle(color: primaryWhite, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: mediumGrey),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextFormField(
                          controller: _chordsController,
                          maxLines: 8,
                          style: const TextStyle(color: primaryWhite, fontSize: 12, fontFamily: 'monospace'),
                          decoration: const InputDecoration(
                            hintText: 'Paste chords with lyrics here...',
                            hintStyle: TextStyle(color: mediumGrey, fontSize: 11),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: mediumGrey),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: highlightSuccess,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: primaryWhite),
                          )
                        : const Text('Save Song'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ========== SONG DETAIL SCREEN ==========
class SongDetailScreen extends StatefulWidget {
  final SongModel song;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  
  const SongDetailScreen({
    super.key,
    required this.song,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<SongDetailScreen> createState() => _SongDetailScreenState();
}

class _SongDetailScreenState extends State<SongDetailScreen> {
  late String _currentView;
  YoutubePlayerController? _youtubeController;
  bool _isYouTubeReady = false;

  @override
  void initState() {
    super.initState();
    _currentView = 'Lyrics';
    
    if (widget.song.youtubeVideoId.isNotEmpty) {
      _initializeYouTubePlayer();
    }
  }

  void _initializeYouTubePlayer() {
    _youtubeController = YoutubePlayerController(
      initialVideoId: widget.song.youtubeVideoId,
      flags: const YoutubePlayerFlags(
        autoPlay: false,
        mute: false,
        loop: false,
        disableDragSeek: false,
      ),
    );
    setState(() {
      _isYouTubeReady = true;
    });
  }

  @override
  void dispose() {
    _youtubeController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [primaryBlack, almostBlack, darkSmoke],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(widget.song.title),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: lightGrey,
          actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: widget.onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: widget.onDelete,
            ),
          ],
        ),
        body: Column(
          children: [
            if (_isYouTubeReady && _youtubeController != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: YoutubePlayer(
                  controller: _youtubeController!,
                  showVideoProgressIndicator: true,
                  progressIndicatorColor: lightGrey,
                ),
              ),
            
            const SizedBox(height: 16),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildToggleButton('Lyrics', Icons.text_fields),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildToggleButton('Chords', Icons.queue_music),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 12),
            
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: primaryBlack.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: mediumGrey),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _currentView == 'Lyrics'
                        ? (widget.song.lyrics.isEmpty ? 'No lyrics added yet.' : widget.song.lyrics)
                        : (widget.song.chords.isEmpty ? 'No chords added yet.' : widget.song.chords),
                    style: const TextStyle(
                      color: primaryWhite,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleButton(String title, IconData icon) {
    final isSelected = _currentView == title;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentView = title;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? darkSmoke : almostBlack,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? lightGrey : mediumGrey),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? primaryWhite : lightGrey, size: 18),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? primaryWhite : lightGrey,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}