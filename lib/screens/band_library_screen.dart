import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Color Palette
const Color smokyBlack = Color(0xFF110703);
const Color licorice = Color(0xFF230F08);
const Color blackBean = Color(0xFF34170D);
const Color kobicha = Color(0xFF6E3C19);
const Color chamoisee = Color(0xFFA7795E);
const Color highlightSuccess = Color(0xFF558B2F);
const Color highlightWarning = Color(0xFFD4A017);
const Color highlightError = Color(0xFFC62828);

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
      });
    }, onError: (error) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading songs: $error'), backgroundColor: highlightError),
      );
    });
  }

  void _applyFilters() {
    List<SongModel> filtered = List.from(_allSongs);
    
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((song) =>
          // Search by title
          song.title.toLowerCase().contains(query) ||
          // Search by artist
          song.artist.toLowerCase().contains(query) ||
          // Search by key
          song.key.toLowerCase().contains(query) ||
          // Search by creator name (user who added)
          song.createdByName.toLowerCase().contains(query) ||
          // Search by lyrics content
          song.lyrics.toLowerCase().contains(query) ||
          // Search by chords content
          song.chords.toLowerCase().contains(query)).toList();
    }
    
    // Sort by title alphabetically
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
        backgroundColor: licorice,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Song', style: TextStyle(color: chamoisee, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${song.title}"?', style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: chamoisee))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: highlightError, foregroundColor: Colors.white),
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
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/music.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Band Library'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: chamoisee,
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
                  color: licorice.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: kobicha),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search by title, artist, key, creator, lyrics, or chords...',
                    hintStyle: TextStyle(color: chamoisee),
                    prefixIcon: Icon(Icons.search, color: chamoisee),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: chamoisee),
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
                    style: TextStyle(color: chamoisee, fontSize: 12),
                  ),
                  if (_searchQuery.isNotEmpty)
                    Text(
                      'Search results',
                      style: TextStyle(color: chamoisee, fontSize: 10),
                    ),
                ],
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Songs List/Grid
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: chamoisee))
                  : _filteredSongs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.library_music, size: 64, color: chamoisee.withOpacity(0.5)),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isEmpty ? 'No songs yet' : 'No matching songs found',
                                style: TextStyle(color: chamoisee, fontSize: 16),
                              ),
                              if (_searchQuery.isEmpty)
                                const SizedBox(height: 8),
                              if (_searchQuery.isEmpty)
                                Text(
                                  'Tap the + button to add your first song',
                                  style: TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                            ],
                          ),
                        )
                      : _selectedView == 'list'
                          ? ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _filteredSongs.length,
                              itemBuilder: (context, index) => _buildSongCard(_filteredSongs[index]),
                            )
                          : GridView.builder(
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
          color: isCurrentUser ? kobicha.withOpacity(0.15) : licorice.withOpacity(0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isCurrentUser ? chamoisee : kobicha,
            width: isCurrentUser ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [kobicha, chamoisee]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.music_note, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    song.artist,
                    style: TextStyle(color: chamoisee, fontSize: 12),
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
                          color: kobicha.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Key: ${song.key}',
                          style: TextStyle(color: chamoisee, fontSize: 10),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: kobicha.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person, size: 10, color: chamoisee.withOpacity(0.7)),
                            const SizedBox(width: 4),
                            Text(
                              song.createdByName,
                              style: TextStyle(color: chamoisee.withOpacity(0.7), fontSize: 9),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: chamoisee, size: 22),
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
          color: isCurrentUser ? kobicha.withOpacity(0.15) : licorice.withOpacity(0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isCurrentUser ? chamoisee : kobicha,
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
                gradient: const LinearGradient(colors: [kobicha, chamoisee]),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Icon(Icons.music_note, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 10),
            Text(
              song.title,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              song.artist,
              style: TextStyle(color: chamoisee, fontSize: 11),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: kobicha.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Key: ${song.key}',
                style: TextStyle(color: chamoisee, fontSize: 9),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: kobicha.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person, size: 8, color: chamoisee.withOpacity(0.7)),
                  const SizedBox(width: 2),
                  Text(
                    song.createdByName.length > 10 
                        ? '${song.createdByName.substring(0, 10)}...' 
                        : song.createdByName,
                    style: TextStyle(color: chamoisee.withOpacity(0.7), fontSize: 8),
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
      backgroundColor: licorice,
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
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: chamoisee),
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
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Song Title *',
                          labelStyle: TextStyle(color: chamoisee),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: kobicha),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: chamoisee),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _artistController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Artist/Band *',
                          labelStyle: TextStyle(color: chamoisee),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: kobicha),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: chamoisee),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _youtubeUrlController,
                        onChanged: (_) => _validateYoutubeUrl(),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'YouTube URL (optional)',
                          labelStyle: TextStyle(color: chamoisee),
                          hintText: 'https://youtube.com/watch?v=...',
                          hintStyle: TextStyle(color: Colors.grey),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: kobicha),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: chamoisee),
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
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Key *',
                          labelStyle: TextStyle(color: chamoisee),
                          hintText: 'e.g., G, C, Dm, Eb',
                          hintStyle: TextStyle(color: Colors.grey),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: kobicha),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: chamoisee),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Lyrics',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: kobicha),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextFormField(
                          controller: _lyricsController,
                          maxLines: 8,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: const InputDecoration(
                            hintText: 'Paste lyrics here...',
                            hintStyle: TextStyle(color: Colors.grey, fontSize: 11),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Chords',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: kobicha),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextFormField(
                          controller: _chordsController,
                          maxLines: 8,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                          decoration: const InputDecoration(
                            hintText: 'Paste chords with lyrics here...',
                            hintStyle: TextStyle(color: Colors.grey, fontSize: 11),
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
                      side: BorderSide(color: kobicha),
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
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/music.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(widget.song.title),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: chamoisee,
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
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: licorice.withOpacity(0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kobicha),
              ),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [kobicha, chamoisee]),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Icon(Icons.music_note, color: Colors.white, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.song.title,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.song.artist,
                          style: TextStyle(color: chamoisee, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: kobicha.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Key: ${widget.song.key}',
                                style: TextStyle(color: chamoisee, fontSize: 11),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: kobicha.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.person, size: 12, color: chamoisee.withOpacity(0.7)),
                                  const SizedBox(width: 4),
                                  Text(
                                    widget.song.createdByName,
                                    style: TextStyle(color: chamoisee.withOpacity(0.7), fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            if (_isYouTubeReady && _youtubeController != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: YoutubePlayer(
                  controller: _youtubeController!,
                  showVideoProgressIndicator: true,
                  progressIndicatorColor: chamoisee,
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
                  color: smokyBlack.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kobicha),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _currentView == 'Lyrics'
                        ? (widget.song.lyrics.isEmpty ? 'No lyrics added yet.' : widget.song.lyrics)
                        : (widget.song.chords.isEmpty ? 'No chords added yet.' : widget.song.chords),
                    style: const TextStyle(
                      color: Colors.white,
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
          color: isSelected ? kobicha : licorice.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? chamoisee : kobicha),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? Colors.white : chamoisee, size: 18),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : chamoisee,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}