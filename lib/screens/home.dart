import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'player.dart';
import '../model/channel.dart';
import '../model/stream_source.dart';
import '../provider/channels_provider.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> with TickerProviderStateMixin {
  final ChannelsProvider channelsProvider = ChannelsProvider();
  List<StreamSource> streamSources = [];
  // Preloaded channel data per source
  Map<String, List<Channel>> _sourceChannels = {};
  bool _isLoading = true;
  bool _hasError = false;

  // For the search overlay
  bool _showSearch = false;
  TextEditingController _searchController = TextEditingController();
  FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    try {
      final sources = await channelsProvider.fetchStreamSources();
      if (!mounted) return;

      // Load channels for each source in parallel
      final futures = <Future<void>>[];
      for (final source in sources) {
        futures.add(_loadChannelsForSource(source));
      }
      await Future.wait(futures);

      if (mounted) {
        setState(() {
          streamSources = sources;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _loadChannelsForSource(StreamSource source) async {
    try {
      final provider = ChannelsProvider();
      final channels = await provider.fetchM3UFile(source.streamUrl);
      _sourceChannels[source.name] = channels;
    } catch (_) {
      _sourceChannels[source.name] = [];
    }
  }

  List<Channel> get _allChannels {
    return _sourceChannels.values.expand((list) => list).toList();
  }

  List<Channel> get _searchResults {
    if (_searchQuery.isEmpty) return [];
    final query = _searchQuery.toLowerCase();
    return _allChannels
        .where((ch) => ch.name.toLowerCase().contains(query))
        .toList();
  }

  void _onSearch(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _searchQuery = query);
    });
  }

  void _openChannel(Channel channel) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => Player(channel: channel),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const _LoadingHome();
    if (_hasError) {
      return _ErrorHome(onRetry: () {
        setState(() {
          _isLoading = true;
          _hasError = false;
        });
        _loadAllData();
      });
    }

    if (_showSearch) return _buildSearchView();
    return _buildMainFeed();
  }

  Widget _buildMainFeed() {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      body: CustomScrollView(
        slivers: [
          // Immersive top bar (JioHotstar-style)
          SliverToBoxAdapter(child: _buildAppBar()),

          // Hero featured section
          SliverToBoxAdapter(child: _buildHeroSection()),

          // Channel rows per source
          ..._buildSourceSections(),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        MediaQuery.of(context).padding.top + 12,
        24,
        12,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0D1220),
            Color(0xFF0B0F17),
          ],
        ),
      ),
      child: Row(
        children: [
          // App branding
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF386BF6), Color(0xFF6C5BFF)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.live_tv_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Live TV',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Free Indian IPTV',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF8EAEFF),
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          // Search button
          _GlassButton(
            icon: Icons.search_rounded,
            onTap: () => setState(() => _showSearch = true),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    // Pick a few channels with logos for the hero
    final heroChannels = _allChannels.where((ch) {
      return ch.logoUrl.isNotEmpty &&
          ch.logoUrl.startsWith('http');
    }).take(5).toList();

    if (heroChannels.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 200,
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.88),
        itemCount: heroChannels.length,
        itemBuilder: (context, index) {
          final channel = heroChannels[index];
          return _HeroCard(
            channel: channel,
            onTap: () => _openChannel(channel),
          );
        },
      ),
    );
  }

  List<Widget> _buildSourceSections() {
    final sections = <Widget>[];

    for (final source in streamSources) {
      final channels = _sourceChannels[source.name] ?? [];
      if (channels.isEmpty) continue;

      // Section header
      sections.add(SliverToBoxAdapter(
        child: _SectionHeader(
          title: source.name,
          channelCount: channels.length,
          onViewAll: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _AllChannelsPage(
                  source: source,
                  channels: channels,
                  onChannelTap: _openChannel,
                ),
              ),
            );
          },
        ),
      ));

      // Horizontal channel row
      sections.add(SliverToBoxAdapter(
        child: SizedBox(
          height: 145,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            itemCount: channels.length > 20 ? 20 : channels.length,
            itemBuilder: (context, index) {
              final channel = channels[index];
              return _ChannelTile(
                channel: channel,
                onTap: () => _openChannel(channel),
                isFirst: index == 0,
              );
            },
          ),
        ),
      ));
    }

    return sections;
  }

  Widget _buildSearchView() {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.of(context).padding.top + 8,
              16,
              12,
            ),
            color: const Color(0xFF0D1220),
            child: Row(
              children: [
                _GlassButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () {
                    _searchController.clear();
                    setState(() {
                      _showSearch = false;
                      _searchQuery = '';
                    });
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    autofocus: true,
                    onChanged: _onSearch,
                    style: const TextStyle(
                        fontSize: 18, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search channels…',
                      hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4)),
                      prefixIcon: const Icon(Icons.search,
                          color: Color(0xFF5B8CFF)),
                      filled: true,
                      fillColor: const Color(0xFF151A24),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                            color: Color(0xFF5B8CFF), width: 1.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _searchQuery.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_rounded,
                            size: 56,
                            color: Colors.white.withValues(alpha: 0.15)),
                        const SizedBox(height: 14),
                        Text(
                          'Search across all channels',
                          style: TextStyle(
                            fontSize: 16,
                            color:
                                Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  )
                : _searchResults.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_off_rounded,
                                size: 56, color: Color(0xFF8EAEFF)),
                            const SizedBox(height: 14),
                            Text(
                              'No channels found for "$_searchQuery"',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding:
                            const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final channel = _searchResults[index];
                          return _SearchResultTile(
                            channel: channel,
                            onTap: () => _openChannel(channel),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ─── Widget Components ─────────────────────────────────────────

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.channel, required this.onTap});
  final Channel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1A2540),
              Color(0xFF0E1628),
            ],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Stack(
          children: [
            // Subtle glow accent
            Positioned(
              right: -30,
              top: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF386BF6).withValues(alpha: 0.15),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  // Channel logo
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 80,
                      height: 80,
                      color: Colors.white,
                      padding: const EdgeInsets.all(8),
                      child: Image.network(
                        channel.logoUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Image.asset(
                          'assets/images/tv-icon.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          channel.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF2E56),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '● LIVE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          channel.category,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF386BF6).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            const Color(0xFF386BF6).withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Color(0xFF8EAEFF),
                      size: 28,
                    ),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.channelCount,
    required this.onViewAll,
  });
  final String title;
  final int channelCount;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$channelCount channels',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onViewAll,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'View All',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5B8CFF),
                  ),
                ),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: Color(0xFF5B8CFF)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelTile extends StatefulWidget {
  const _ChannelTile({
    required this.channel,
    required this.onTap,
    this.isFirst = false,
  });
  final Channel channel;
  final VoidCallback onTap;
  final bool isFirst;

  @override
  State<_ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<_ChannelTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.isFirst,
      onFocusChange: (v) => setState(() => _focused = v),
      onKeyEvent: (_, event) {
        final isSelect = event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter;
        if (event is KeyDownEvent && isSelect) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 150),
        scale: _focused ? 1.06 : 1.0,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 110,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: _focused
                  ? const Color(0xFF1D2B4A)
                  : const Color(0xFF131824),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _focused
                    ? const Color(0xFF5B8CFF)
                    : Colors.white.withValues(alpha: 0.06),
                width: _focused ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 56,
                    height: 56,
                    color: Colors.white,
                    padding: const EdgeInsets.all(6),
                    child: Image.network(
                      widget.channel.logoUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Image.asset(
                        'assets/images/tv-icon.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    widget.channel.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile(
      {required this.channel, required this.onTap});
  final Channel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFF131824),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 52,
                    height: 52,
                    color: Colors.white,
                    padding: const EdgeInsets.all(5),
                    child: Image.network(
                      channel.logoUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Image.asset(
                        'assets/images/tv-icon.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        channel.category,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white
                              .withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.play_circle_outline_rounded,
                    size: 28, color: Color(0xFF5B8CFF)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── View All Channels Page ───────────────────────────────────

class _AllChannelsPage extends StatefulWidget {
  const _AllChannelsPage({
    required this.source,
    required this.channels,
    required this.onChannelTap,
  });
  final StreamSource source;
  final List<Channel> channels;
  final void Function(Channel) onChannelTap;

  @override
  State<_AllChannelsPage> createState() => _AllChannelsPageState();
}

class _AllChannelsPageState extends State<_AllChannelsPage> {
  String _selectedCategory = 'All';
  String _searchQuery = '';
  Timer? _debounceTimer;

  List<String> get _categories {
    final cats =
        widget.channels.map((c) => c.category).toSet().toList()..sort();
    return ['All', ...cats];
  }

  List<Channel> get _filtered {
    final query = _searchQuery.toLowerCase();
    return widget.channels.where((ch) {
      final matchesCategory =
          _selectedCategory == 'All' || ch.category == _selectedCategory;
      final matchesSearch = ch.name.toLowerCase().contains(query);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      body: Column(
        children: [
          // Top bar
          Container(
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.of(context).padding.top + 8,
              16,
              10,
            ),
            color: const Color(0xFF0D1220),
            child: Column(
              children: [
                Row(
                  children: [
                    _GlassButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.source.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '${widget.channels.length} channels',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Search bar
                TextField(
                  onChanged: (v) {
                    _debounceTimer?.cancel();
                    _debounceTimer =
                        Timer(const Duration(milliseconds: 250), () {
                      if (mounted) setState(() => _searchQuery = v);
                    });
                  },
                  style: const TextStyle(
                      fontSize: 16, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search ${widget.source.name}…',
                    hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35)),
                    prefixIcon: const Icon(Icons.search,
                        color: Color(0xFF5B8CFF), size: 22),
                    filled: true,
                    fillColor: const Color(0xFF151A24),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0xFF5B8CFF), width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Category chips
          if (_categories.length > 2)
            SizedBox(
              height: 50,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final selected = _selectedCategory == cat;
                  return ChoiceChip(
                    label: Text(cat),
                    selected: selected,
                    selectedColor: const Color(0xFF386BF6),
                    backgroundColor: const Color(0xFF151A24),
                    labelStyle: TextStyle(
                      color: selected
                          ? Colors.white
                          : Colors.white
                              .withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600,
                    ),
                    side: BorderSide(
                      color: selected
                          ? const Color(0xFF5B8CFF)
                          : Colors.white
                              .withValues(alpha: 0.08),
                    ),
                    onSelected: (_) =>
                        setState(() => _selectedCategory = cat),
                  );
                },
              ),
            ),
          // Channel grid
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(
                      'No channels found',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(
                        20, 12, 20, 32),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 140,
                      childAspectRatio: 0.8,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final channel = _filtered[index];
                      return _ChannelGridTile(
                        channel: channel,
                        onTap: () =>
                            widget.onChannelTap(channel),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ChannelGridTile extends StatelessWidget {
  const _ChannelGridTile(
      {required this.channel, required this.onTap});
  final Channel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF131824),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 50,
                  height: 50,
                  color: Colors.white,
                  padding: const EdgeInsets.all(5),
                  child: Image.network(
                    channel.logoUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Image.asset(
                      'assets/images/tv-icon.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                channel.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── State Widgets ─────────────────────────────────────────────

class _LoadingHome extends StatelessWidget {
  const _LoadingHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF386BF6), Color(0xFF6C5BFF)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.live_tv_rounded,
                  color: Colors.white, size: 36),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFF5B8CFF),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Loading your TV guide…',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Fetching channels from IPTV sources',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorHome extends StatelessWidget {
  const _ErrorHome({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 56, color: Color(0xFF8EAEFF)),
            const SizedBox(height: 18),
            const Text(
              'Couldn\'t load channels',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check your internet connection and try again.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF386BF6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(
                'Retry',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
