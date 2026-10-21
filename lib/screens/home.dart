import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '/screens/player.dart';
import '../model/channel.dart';
import '../model/stream_source.dart';
import '../provider/channels_provider.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> {
  List<Channel> channels = [];
  List<Channel> filteredChannels = [];
  List<StreamSource> streamSources = [];
  List<StreamSource> filteredStreamSources = [];
  StreamSource? selectedSource;
  TextEditingController searchController = TextEditingController();
  final ChannelsProvider channelsProvider = ChannelsProvider();
  bool _isLoading = true;
  Timer? _debounceTimer;
  final FocusNode _channelSearchFocusNode = FocusNode();
  final FocusNode _firstChannelFocusNode = FocusNode();
  String _channelQuery = '';
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _channelSearchFocusNode.onKeyEvent = (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _firstChannelFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
    fetchStreamSources();
  }

  Future<void> fetchStreamSources() async {
    try {
      final sources = await channelsProvider.fetchStreamSources();
      setState(() {
        streamSources = sources;
        filteredStreamSources = sources;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('There was a problem loading stream categories'),
          ),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> fetchChannels(StreamSource source) async {
    setState(() {
      _isLoading = true;
      selectedSource = source;
      searchController.clear();
      _channelQuery = '';
      _selectedCategory = 'All';
    });

    try {
      final data = await channelsProvider.fetchM3UFile(source.streamUrl);
      setState(() {
        channels = data;
        filteredChannels = data;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('There was a problem loading channels'),
          ),
        );
      }
      setState(() {
        selectedSource = null;
        _isLoading = false;
      });
    }
  }

  void backToCategories() {
    setState(() {
      selectedSource = null;
      channels = [];
      filteredChannels = [];
      filteredStreamSources = streamSources;
      searchController.clear();
      _channelQuery = '';
      _selectedCategory = 'All';
    });
  }

  void filterChannels(String query) {
    if (_debounceTimer != null) {
      _debounceTimer!.cancel();
    }
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _channelQuery = query;
        _applyChannelFilters();
      });
    });
  }

  void _applyChannelFilters() {
    final query = _channelQuery.trim().toLowerCase();
    filteredChannels = channels.where((channel) {
      final matchesSearch = channel.name.toLowerCase().contains(query);
      final matchesCategory = _selectedCategory == 'All' ||
          channel.category == _selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();
  }

  bool get _hasCategories {
    final categories = channels.map((c) => c.category).toSet();
    return categories.length > 1;
  }

  List<String> get _availableCategories {
    final categories =
        channels.map((channel) => channel.category).toSet().toList()..sort();
    return ['All', ...categories];
  }

  void filterStreamSources(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    setState(() {
      filteredStreamSources = streamSources
          .where(
              (source) => source.name.toLowerCase().contains(normalizedQuery))
          .toList();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    searchController.dispose();
    _channelSearchFocusNode.dispose();
    _firstChannelFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const _LoadingState();
    }

    if (selectedSource == null) {
      return _buildCategoryList();
    }

    return _buildChannelList();
  }

  Widget _buildCategoryList() {
    if (streamSources.isEmpty) {
      return const _EmptyState(
        icon: Icons.video_library_outlined,
        title: 'No categories available',
        message: 'Stream categories will appear here when they are available.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 32),
      children: [
        const Text('Browse channels',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Choose a category to start watching.',
            style: TextStyle(color: Colors.white.withOpacity(.7))),
        const SizedBox(height: 20),
        TextField(
          onChanged: filterStreamSources,
          style: const TextStyle(fontSize: 18),
          decoration: InputDecoration(
            hintText: 'Search categories',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: const Color(0xFF151A24),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF8EAEFF), width: 2),
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (filteredStreamSources.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: _EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No categories found',
              message: 'Try a different category name.',
            ),
          ),
        ...filteredStreamSources.asMap().entries.map((entry) {
          final index = entry.key;
          final source = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _FocusableCard(
              autofocus: index == 0,
              onTap: () => fetchChannels(source),
              child: Row(
                children: [
                  const _IconTile(icon: Icons.folder_copy_outlined),
                  const SizedBox(width: 20),
                  Expanded(
                      child: Text(source.name,
                          style: const TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w600))),
                  const Icon(Icons.chevron_right_rounded, size: 32),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildChannelList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
          child: Row(
            children: [
              IconButton.filledTonal(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: backToCategories,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  selectedSource!.name,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        if (_hasCategories)
          SizedBox(
            height: 54,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              scrollDirection: Axis.horizontal,
              itemCount: _availableCategories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final category = _availableCategories[index];
                return ChoiceChip(
                  label: Text(category),
                  selected: _selectedCategory == category,
                  onSelected: (_) => setState(() {
                    _selectedCategory = category;
                    _applyChannelFilters();
                  }),
                );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: TextField(
            controller: searchController,
            focusNode: _channelSearchFocusNode,
            onChanged: filterChannels,
            style: const TextStyle(fontSize: 18),
            decoration: InputDecoration(
              hintText: 'Search channels',
              prefixIcon: Icon(Icons.search),
              filled: true,
              fillColor: const Color(0xFF151A24),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: Color(0xFF8EAEFF), width: 2)),
            ),
          ),
        ),
        Expanded(
          child: filteredChannels.isEmpty
              ? const _EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No channels found',
                  message: 'Try another channel name or return to categories.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  itemCount: filteredChannels.length,
                  itemBuilder: (context, index) {
                    final channel = filteredChannels[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _FocusableCard(
                        autofocus: index == 0,
                        focusNode: index == 0 ? _firstChannelFocusNode : null,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => Player(channel: channel),
                            ),
                          );
                        },
                        child: Row(children: [
                          ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                  color: Colors.white,
                                  width: 64,
                                  height: 64,
                                  padding: const EdgeInsets.all(6),
                                  child: Image.network(channel.logoUrl,
                                      fit: BoxFit.contain,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              Image.asset(
                                                  'assets/images/tv-icon.png',
                                                  fit: BoxFit.contain)))),
                          const SizedBox(width: 18),
                          Expanded(
                              child: Text(channel.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w600))),
                          const Icon(Icons.play_circle_outline_rounded,
                              size: 30),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FocusableCard extends StatefulWidget {
  const _FocusableCard({
    required this.child,
    required this.onTap,
    this.autofocus = false,
    this.focusNode,
  });
  final Widget child;
  final VoidCallback onTap;
  final bool autofocus;
  final FocusNode? focusNode;
  @override
  State<_FocusableCard> createState() => _FocusableCardState();
}

class _FocusableCardState extends State<_FocusableCard> {
  bool focused = false;
  @override
  Widget build(BuildContext context) => Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onFocusChange: (value) => setState(() => focused = value),
        onKeyEvent: (_, event) {
          final isSelectKey = event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter;
          if (event is KeyDownEvent && isSelectKey) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          scale: focused ? 1.018 : 1,
          child: Material(
            color: focused ? const Color(0xFF263B67) : const Color(0xFF151A24),
            borderRadius: BorderRadius.circular(16),
            child: ExcludeFocus(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: widget.onTap,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: focused
                              ? const Color(0xFF9AB5FF)
                              : Colors.white.withOpacity(.06),
                          width: focused ? 2 : 1)),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      );
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon});
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
          color: const Color(0xFF263B67),
          borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: const Color(0xFFB8CAFF), size: 30));
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) => const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(),
        SizedBox(height: 18),
        Text('Loading your TV guide…', style: TextStyle(fontSize: 17))
      ]));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(
      {required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 54, color: const Color(0xFF8EAEFF)),
            const SizedBox(height: 16),
            Text(title,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 16, color: Colors.white.withOpacity(.7)))
          ])));
}
