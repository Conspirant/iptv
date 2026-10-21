import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../model/channel.dart';

class Player extends StatefulWidget {
  const Player({super.key, required this.channel});

  final Channel channel;

  @override
  State<Player> createState() => _PlayerState();
}

class _PlayerState extends State<Player> {
  static Future<void> _previousPlayerRelease = Future.value();

  VideoPlayerController? _videoPlayerController;
  bool _isLoading = true;
  bool _channelNotFound = false;
  bool _showControls = false;
  bool _showPlaybackStatus = false;
  int _selectedControl = 0; // 0: Play/Pause, 1: Go Live
  Timer? _hideControlsTimer;
  Timer? _feedbackTimer;
  Timer? _stallRecoveryTimer;
  Duration _lastPosition = Duration.zero;
  int _stallCount = 0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleRemoteKey);
    WakelockPlus.enable();

    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      // Android TV devices often have a single hardware decoder.
      // Wait until any previous player releases decoder resources.
      await _previousPlayerRelease;
      if (!mounted) return;

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.channel.streamUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );
      _videoPlayerController = controller;

      await controller.initialize().timeout(const Duration(seconds: 15));
      if (!mounted) return;

      controller.addListener(_onPlayerStateChanged);
      await controller.play();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _channelNotFound = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _channelNotFound = true;
        });
      }
    }
  }

  void _onPlayerStateChanged() {
    final controller = _videoPlayerController;
    if (!mounted || controller == null) return;

    if (controller.value.isPlaying) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }

    if (controller.value.hasError && !_channelNotFound) {
      setState(() {
        _isLoading = false;
        _channelNotFound = true;
      });
      return;
    }

    // Auto-recovery for stream stalls
    if (controller.value.isPlaying && !controller.value.isBuffering) {
      if (_lastPosition != controller.value.position) {
        _lastPosition = controller.value.position;
        _stallCount = 0;
        _stallRecoveryTimer?.cancel();
      }
    } else if (controller.value.isPlaying && controller.value.isBuffering) {
      _stallRecoveryTimer ??= Timer(const Duration(seconds: 8), () {
        if (!mounted || _videoPlayerController == null) return;
        _stallRecovery();
      });
    }
  }

  Future<void> _stallRecovery() async {
    _stallRecoveryTimer = null;
    final controller = _videoPlayerController;
    if (controller == null || !mounted) return;

    _stallCount++;
    if (_stallCount > 3) {
      _retryChannel();
      return;
    }

    try {
      final duration = controller.value.duration;
      if (duration > Duration.zero) {
        await controller.seekTo(duration);
      }
      await controller.play();
    } catch (_) {}
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleRemoteKey);
    _hideControlsTimer?.cancel();
    _feedbackTimer?.cancel();
    _stallRecoveryTimer?.cancel();

    final controller = _videoPlayerController;
    if (controller != null) {
      controller.removeListener(_onPlayerStateChanged);
      _previousPlayerRelease = controller.dispose().catchError((_) {});
    }

    WakelockPlus.disable();
    super.dispose();
  }

  void _retryChannel() {
    setState(() {
      _isLoading = true;
      _channelNotFound = false;
      _showControls = false;
    });

    final controller = _videoPlayerController;
    if (controller != null) {
      controller.removeListener(_onPlayerStateChanged);
      _previousPlayerRelease = controller.dispose().catchError((_) {});
      _videoPlayerController = null;
    }

    _initializePlayer();
  }

  void _toggleControls() {
    if (_showControls) {
      _hideControlsTimer?.cancel();
      setState(() => _showControls = false);
    } else {
      _revealControls();
    }
  }

  void _revealControls() {
    _hideControlsTimer?.cancel();
    setState(() => _showControls = true);
    // Auto-hide controls after 4.5 seconds like Hotstar/JioCinema
    _hideControlsTimer = Timer(const Duration(milliseconds: 4500), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _showFeedbackIndicator() {
    _feedbackTimer?.cancel();
    setState(() => _showPlaybackStatus = true);
    _feedbackTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _showPlaybackStatus = false);
    });
  }

  bool _handleRemoteKey(KeyEvent event) {
    if (!mounted || _isLoading || _channelNotFound || event is! KeyDownEvent) {
      return false;
    }

    final key = event.logicalKey;
    final isSelect = key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;

    if (isSelect) {
      if (_showControls) {
        _activateSelectedControl();
      } else {
        _selectedControl = 0;
        _revealControls();
      }
      return true;
    }

    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      _togglePlayback();
      return true;
    }

    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      if (!_showControls) {
        _selectedControl = 0;
        _revealControls();
        return true;
      }

      _revealControls();

      if (key == LogicalKeyboardKey.arrowLeft) {
        setState(() => _selectedControl = (_selectedControl + 1) % 2);
      } else if (key == LogicalKeyboardKey.arrowRight) {
        setState(() => _selectedControl = (_selectedControl + 1) % 2);
      }
      return true;
    }

    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace) {
      if (_showControls) {
        _hideControlsTimer?.cancel();
        setState(() => _showControls = false);
        return true;
      }
      Navigator.of(context).maybePop();
      return true;
    }

    return false;
  }

  void _activateSelectedControl() {
    switch (_selectedControl) {
      case 0:
        _togglePlayback();
        break;
      case 1:
        _goLive();
        break;
    }
  }

  void _togglePlayback() {
    final controller = _videoPlayerController;
    if (controller == null) return;

    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
    _showFeedbackIndicator();
    _revealControls();
  }

  Future<void> _goLive() async {
    final controller = _videoPlayerController;
    if (controller == null) return;

    try {
      final duration = controller.value.duration;
      if (duration > Duration.zero) {
        await controller.seekTo(duration);
      }
    } catch (_) {}
    await controller.play();
    _showFeedbackIndicator();
    _revealControls();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _videoPlayerController;

    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? const _LoadingPlayer()
          : _channelNotFound
              ? _UnavailablePlayer(onRetry: _retryChannel)
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  child: Container(
                    color: Colors.black,
                    width: double.infinity,
                    height: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Direct VideoPlayer widget with aspect ratio preservation
                        if (controller != null && controller.value.isInitialized)
                          Center(
                            child: AspectRatio(
                              aspectRatio: controller.value.aspectRatio > 0
                                  ? controller.value.aspectRatio
                                  : 16 / 9,
                              child: VideoPlayer(controller),
                            ),
                          ),

                        // Top Bar (Channel title, red LIVE pill, back & refresh)
                        AnimatedOpacity(
                          opacity: _showControls ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 250),
                          child: IgnorePointer(
                            ignoring: !_showControls,
                            child: _buildTopBar(),
                          ),
                        ),

                        // Center Play/Pause feedback animation
                        if (_showPlaybackStatus)
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                color: const Color(0xB3000000),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0x995B8CFF),
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                (controller?.value.isPlaying ?? false)
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_rounded,
                                size: 52,
                                color: Colors.white,
                              ),
                            ),
                          ),

                        // Bottom Floating Controls Overlay
                        AnimatedOpacity(
                          opacity: _showControls ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 250),
                          child: IgnorePointer(
                            ignoring: !_showControls,
                            child: _buildBottomControls(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xCC000000),
              Color(0x80000000),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 22),
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 8),
              if (widget.channel.logoUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    color: Colors.white,
                    width: 34,
                    height: 34,
                    padding: const EdgeInsets.all(3),
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
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF2E56),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'LIVE STREAM • ${widget.channel.category}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.75),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded,
                    color: Colors.white, size: 24),
                tooltip: 'Reconnect stream',
                onPressed: _retryChannel,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final isPlaying = _videoPlayerController?.value.isPlaying ?? false;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 50, 28, 28),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Color(0xEE000000),
              Color(0x99000000),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PlayerControlButton(
                selected: _selectedControl == 0,
                icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                label: isPlaying ? 'Pause' : 'Play',
                onTap: () {
                  setState(() => _selectedControl = 0);
                  _togglePlayback();
                },
              ),
              const SizedBox(width: 14),
              _PlayerControlButton(
                selected: _selectedControl == 1,
                icon: Icons.skip_next_rounded,
                label: 'Go Live',
                badgeColor: const Color(0xFFFF2E56),
                onTap: () {
                  setState(() => _selectedControl = 1);
                  _goLive();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerControlButton extends StatelessWidget {
  const _PlayerControlButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeColor,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? const Color(0xFF386BF6)
          : const Color(0xFF1E2536).withValues(alpha: 0.85),
      elevation: selected ? 8 : 2,
      shadowColor: selected
          ? const Color(0xFF386BF6).withValues(alpha: 0.6)
          : Colors.black45,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? const Color(0xFF9AB5FF)
                  : Colors.white.withValues(alpha: 0.12),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badgeColor != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Icon(icon, size: 24, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingPlayer extends StatelessWidget {
  const _LoadingPlayer();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3.5,
                color: Color(0xFF5B8CFF),
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Connecting live stream…',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Optimizing buffer for smooth playback',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnavailablePlayer extends StatelessWidget {
  const _UnavailablePlayer({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 16,
              left: 16,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2536),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF5B8CFF).withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.live_tv_rounded,
                        size: 46,
                        color: Color(0xFF8EAEFF),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Stream currently unavailable',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'The broadcaster server may be temporarily offline or geo-restricted.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF386BF6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 26, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text(
                        'Retry Stream',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
