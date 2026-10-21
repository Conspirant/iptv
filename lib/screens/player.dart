import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:chewie/chewie.dart';
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
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  bool _channelNotFound = false;
  bool _showOverlay = false;
  Timer? _hideOverlayTimer;
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

      final chewie = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        isLive: true,
        showOptions: false,
        showControlsOnInitialize: false,
        allowFullScreen: true,
        allowMuting: false,
        zoomAndPan: false,
        materialProgressColors: ChewieProgressColors(
          playedColor: const Color(0xFFFF2E56),
          handleColor: const Color(0xFFFF2E56),
          bufferedColor: Colors.white24,
          backgroundColor: Colors.white10,
        ),
        errorBuilder: (context, errorMessage) {
          return _UnavailablePlayer(onRetry: _retryChannel);
        },
      );

      _chewieController = chewie;

      controller.addListener(_onPlayerStateChanged);

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
    _hideOverlayTimer?.cancel();
    _stallRecoveryTimer?.cancel();

    final chewie = _chewieController;
    final video = _videoPlayerController;

    if (video != null) {
      video.removeListener(_onPlayerStateChanged);
    }
    chewie?.dispose();
    video?.dispose();

    WakelockPlus.disable();
    super.dispose();
  }

  void _retryChannel() {
    setState(() {
      _isLoading = true;
      _channelNotFound = false;
      _showOverlay = false;
    });

    final chewie = _chewieController;
    final video = _videoPlayerController;

    if (video != null) {
      video.removeListener(_onPlayerStateChanged);
    }
    chewie?.dispose();
    video?.dispose();

    _chewieController = null;
    _videoPlayerController = null;

    _initializePlayer();
  }

  void _toggleOverlay() {
    if (_showOverlay) {
      _hideOverlayTimer?.cancel();
      setState(() => _showOverlay = false);
    } else {
      _revealOverlay();
    }
  }

  void _revealOverlay() {
    _hideOverlayTimer?.cancel();
    setState(() => _showOverlay = true);
    _hideOverlayTimer = Timer(const Duration(milliseconds: 5000), () {
      if (mounted) setState(() => _showOverlay = false);
    });
  }

  bool _handleRemoteKey(KeyEvent event) {
    if (!mounted || _isLoading || _channelNotFound || event is! KeyDownEvent) {
      return false;
    }

    final key = event.logicalKey;

    // Back button handling
    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace) {
      if (_showOverlay) {
        _hideOverlayTimer?.cancel();
        setState(() => _showOverlay = false);
        return true;
      }
      Navigator.of(context).maybePop();
      return true;
    }

    // Select/Enter shows overlay or toggles play
    final isSelect = key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;

    if (isSelect) {
      if (!_showOverlay) {
        _revealOverlay();
      } else {
        _togglePlayback();
      }
      return true;
    }

    // Play/Pause media keys
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      _togglePlayback();
      return true;
    }

    // Arrow keys reveal overlay
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      if (!_showOverlay) {
        _revealOverlay();
      } else {
        _revealOverlay(); // Reset timer
      }
      return true;
    }

    return false;
  }

  void _togglePlayback() {
    final controller = _videoPlayerController;
    if (controller == null) return;

    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
    _revealOverlay();
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
    _revealOverlay();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? const _LoadingPlayer()
          : _channelNotFound
              ? _UnavailablePlayer(onRetry: _retryChannel)
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleOverlay,
                  child: Container(
                    color: Colors.black,
                    width: double.infinity,
                    height: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Chewie player (handles surface lifecycle properly)
                        if (_chewieController != null)
                          Center(
                            child: Chewie(
                              controller: _chewieController!,
                            ),
                          ),

                        // Custom top overlay – channel info + back
                        AnimatedOpacity(
                          opacity: _showOverlay ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 250),
                          child: IgnorePointer(
                            ignoring: !_showOverlay,
                            child: _buildTopOverlay(),
                          ),
                        ),

                        // Custom bottom overlay – play, live, reconnect
                        AnimatedOpacity(
                          opacity: _showOverlay ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 250),
                          child: IgnorePointer(
                            ignoring: !_showOverlay,
                            child: _buildBottomOverlay(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildTopOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xDD000000),
              Color(0x88000000),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              _OverlayIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: () => Navigator.of(context).maybePop(),
                tooltip: 'Back',
              ),
              const SizedBox(width: 12),
              if (widget.channel.logoUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    color: Colors.white,
                    width: 36,
                    height: 36,
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
                        // Pulsing LIVE dot
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
                          'LIVE  •  ${widget.channel.category}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.7),
                            letterSpacing: 0.5,
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
      ),
    );
  }

  Widget _buildBottomOverlay() {
    final isPlaying = _videoPlayerController?.value.isPlaying ?? false;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
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
              _OverlayActionButton(
                icon: isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                label: isPlaying ? 'Pause' : 'Play',
                onTap: _togglePlayback,
                isPrimary: true,
              ),
              const SizedBox(width: 14),
              _OverlayActionButton(
                icon: Icons.skip_next_rounded,
                label: 'Go Live',
                onTap: _goLive,
                badgeColor: const Color(0xFFFF2E56),
              ),
              const SizedBox(width: 14),
              _OverlayActionButton(
                icon: Icons.refresh_rounded,
                label: 'Retry',
                onTap: _retryChannel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Helper Widgets ---

class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _OverlayActionButton extends StatelessWidget {
  const _OverlayActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isPrimary = false,
    this.badgeColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isPrimary
          ? const Color(0xFF386BF6)
          : const Color(0xFF1E2536).withValues(alpha: 0.85),
      elevation: isPrimary ? 8 : 2,
      shadowColor: isPrimary
          ? const Color(0xFF386BF6).withValues(alpha: 0.6)
          : Colors.black45,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isPrimary
                  ? const Color(0xFF9AB5FF)
                  : Colors.white.withValues(alpha: 0.1),
              width: isPrimary ? 1.5 : 1,
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
              Icon(icon, size: 22, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
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
              child: _OverlayIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: () => Navigator.of(context).maybePop(),
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
                          color:
                              const Color(0xFF5B8CFF).withValues(alpha: 0.3),
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
