import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:youtube_player_flutter/src/fullscreen_youtube_player.dart';
import 'controls.dart';
import 'progress_bar.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'youtube_player_flags.dart';

part 'player.dart';

/// Quality of Thumbnail
enum ThumbnailQuality {
  DEFAULT,
  HIGH,
  MEDIUM,
  STANDARD,
  MAX,
}

/// Current state of the player. Find more about it [here](https://developers.google.com/youtube/iframe_api_reference#Playback_status)
enum PlayerState {
  UNKNOWN,
  UN_STARTED,
  ENDED,
  PLAYING,
  PAUSED,
  BUFFERING,
  CUED,
}

/// Playback Rate or Speed for the video.
enum PlaybackRate {
  QUARTER,
  HALF,
  NORMAL,
  ONE_AND_A_HALF,
  DOUBLE,
}

typedef YoutubePlayerControllerCallback(YoutubePlayerController controller);

class YoutubePlayer extends StatefulWidget {
  /// Current context of the player.
  final BuildContext context;

  /// The required videoId property specifies the YouTube Video ID of the video to be played.
  final String videoId;

  /// Defines the width of the player.
  /// Default = Devices's Width
  final double width;

  /// Defines the aspect ratio to be assigned to the player. This property along with [width] calculates the player size.
  /// Default = 16/9
  final double aspectRatio;

  /// The duration for which controls in the player will be visible.
  /// Default = 3 seconds
  final Duration controlsTimeOut;

  /// Overrides the default buffering indicator for the player.
  final Widget bufferIndicator;

  /// Overrides default colors of the progress bar, takes [ProgressColors].
  final ProgressColors progressColors;

  /// Overrides default color of progress indicator shown below the player(if enabled).
  final Color videoProgressIndicatorColor;

  /// Returns [YoutubePlayerController] after being initialized.
  final YoutubePlayerControllerCallback onPlayerInitialized;

  /// Overrides color of Live UI when enabled.
  final Color liveUIColor;

  /// Adds custom top bar widgets
  final List<Widget> actions;

  /// Thumbnail to show when player is loading
  final String thumbnailUrl;

  /// [YoutubePlayerFlags] composes all the flags required to control the player.
  final YoutubePlayerFlags flags;

  /// Video starts playing from the duration provided.
  final Duration startAt;

  final bool inFullScreen;

  YoutubePlayer({
    Key key,
    @required this.context,
    @required this.videoId,
    this.width,
    this.aspectRatio = 16 / 9,
    this.controlsTimeOut = const Duration(seconds: 3),
    this.bufferIndicator,
    this.videoProgressIndicatorColor = Colors.red,
    this.progressColors,
    this.onPlayerInitialized,
    this.liveUIColor = Colors.red,
    this.actions,
    this.thumbnailUrl,
    this.flags = const YoutubePlayerFlags(),
    this.startAt = const Duration(seconds: 0),
    this.inFullScreen = false,
  })  : assert(videoId.length == 11, "Invalid YouTube Video Id"),
        super(key: key);

  /// Converts fully qualified YouTube Url to video id.
  static String convertUrlToId(String url, [bool trimWhitespaces = true]) {
    if (!url.contains("http") && (url.length == 11)) return url;
    if (url == null || url.length == 0) return null;
    if (trimWhitespaces) url = url.trim();

    for (var exp in [
      RegExp(
          r"^https:\/\/(?:www\.|m\.)?youtube\.com\/watch\?v=([_\-a-zA-Z0-9]{11}).*$"),
      RegExp(
          r"^https:\/\/(?:www\.|m\.)?youtube(?:-nocookie)?\.com\/embed\/([_\-a-zA-Z0-9]{11}).*$"),
      RegExp(r"^https:\/\/youtu\.be\/([_\-a-zA-Z0-9]{11}).*$")
    ]) {
      Match match = exp.firstMatch(url);
      if (match != null && match.groupCount >= 1) return match.group(1);
    }

    return null;
  }

  /// Grabs YouTube video's thumbnail for provided video id.
  static String getThumbnail(
      {@required String videoId,
      ThumbnailQuality quality = ThumbnailQuality.STANDARD}) {
    String _thumbnailUrl = 'https://i3.ytimg.com/vi/$videoId/';
    switch (quality) {
      case ThumbnailQuality.DEFAULT:
        _thumbnailUrl += 'default.jpg';
        break;
      case ThumbnailQuality.HIGH:
        _thumbnailUrl += 'hqdefault.jpg';
        break;
      case ThumbnailQuality.MEDIUM:
        _thumbnailUrl += 'mqdefault.jpg';
        break;
      case ThumbnailQuality.STANDARD:
        _thumbnailUrl += 'sddefault.jpg';
        break;
      case ThumbnailQuality.MAX:
        _thumbnailUrl += 'maxresdefault.jpg';
        break;
    }
    return _thumbnailUrl;
  }

  @override
  _YoutubePlayerState createState() => _YoutubePlayerState();
}

class _YoutubePlayerState extends State<YoutubePlayer> {
  YoutubePlayerController ytController;

  YoutubePlayerController get controller => ytController;

  set controller(YoutubePlayerController c) => ytController = c;

  final _showControls = ValueNotifier<bool>(false);

  Timer _timer;

  String _currentVideoId;

  bool _inFullScreen = false;

  bool _firstLoad = true;

  @override
  void initState() {
    super.initState();
    _loadController();
    _currentVideoId = widget.videoId;
    _showControls.addListener(
      () {
        _timer?.cancel();
        if (_showControls.value)
          _timer = Timer(
            widget.controlsTimeOut,
            () => _showControls.value = false,
          );
      },
    );
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _inFullScreen = widget.inFullScreen;
      controller.value = controller.value.copyWith(
        isFullScreen: widget.inFullScreen ?? false,
      );
    });
  }

  _loadController({WebViewController webController}) {
    controller = YoutubePlayerController(widget.videoId);
    if (webController != null) {
      controller.value =
          controller.value.copyWith(webViewController: webController);
    }
    if (widget.onPlayerInitialized != null) {
      widget.onPlayerInitialized(controller);
    }
    controller.addListener(listener);
  }

  void listener() async {
    if (controller.value.isReady &&
        controller.value.isEvaluationReady &&
        _firstLoad) {
      _firstLoad = false;
      widget.flags.autoPlay
          ? controller.load(startAt: widget.startAt.inSeconds)
          : controller.cue(startAt: widget.startAt.inSeconds);
      if (widget.flags.mute) {
        controller.mute();
      }
    }
    if (controller.value.isFullScreen && !_inFullScreen) {
      _inFullScreen = true;
      Duration pos = await showFullScreenYoutubePlayer(
        context: context,
        videoId: widget.videoId,
        startAt: controller.value.position,
        width: widget.width,
        actions: widget.actions,
        aspectRatio: widget.aspectRatio,
        bufferIndicator: widget.bufferIndicator,
        controlsTimeOut: widget.controlsTimeOut,
        flags: YoutubePlayerFlags(
          disableDragSeek: widget.flags.disableDragSeek,
          hideFullScreenButton: widget.flags.hideFullScreenButton,
          showVideoProgressIndicator: false,
          autoPlay: widget.flags.autoPlay,
          forceHideAnnotation: widget.flags.forceHideAnnotation,
          mute: widget.flags.mute,
          hideControls: widget.flags.hideControls,
          hideThumbnail: widget.flags.hideThumbnail,
          isLive: widget.flags.isLive,
        ),
        liveUIColor: widget.liveUIColor,
        progressColors: widget.progressColors,
        thumbnailUrl: widget.thumbnailUrl,
        videoProgressIndicatorColor: widget.videoProgressIndicatorColor,
      );
      controller.seekTo(pos ?? Duration(seconds: 1));
      _inFullScreen = false;
      controller.exitFullScreen();
    }
    if (!controller.value.isFullScreen && _inFullScreen) {
      _inFullScreen = false;
      Navigator.pop<Duration>(context, controller.value.position);
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    controller.removeListener(listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentVideoId != widget.videoId) {
      _currentVideoId = widget.videoId;
      _loadController(webController: controller.value.webViewController);
      controller.load(startAt: widget.startAt.inSeconds);
    }
    return Container(
      width: widget.width ?? MediaQuery.of(widget.context).size.width,
      child: _buildPlayer(widget.aspectRatio),
    );
  }

  Widget _thumbWidget() {
    return CachedNetworkImage(
      imageUrl: widget.thumbnailUrl ??
          YoutubePlayer.getThumbnail(
            videoId: controller.initialSource,
          ),
      fit: BoxFit.cover,
      errorWidget: (context, url, _) {
        return Container(
          color: Colors.black,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text(
                  'Oops! Something went wrong!',
                  style: TextStyle(
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Might be an internet issue',
                  style: TextStyle(
                    fontWeight: FontWeight.w300,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      placeholder: (context, _) => Container(
        color: Colors.black,
      ),
    );
  }

  Widget _buildPlayer(double _aspectRatio) {
    return AspectRatio(
      aspectRatio: _aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        overflow: Overflow.visible,
        children: <Widget>[
          _Player(
            controller: controller,
            flags: widget.flags,
          ),
          if (!controller.value.hasPlayed &&
              controller.value.playerState == PlayerState.BUFFERING)
            Container(
              color: Colors.black,
            ),
          if (!controller.value.hasPlayed && !widget.flags.hideThumbnail)
            _thumbWidget(),
          if (!widget.flags.hideControls)
            TouchShutter(
              controller,
              _showControls,
              widget.flags.disableDragSeek,
            ),
          if (!widget.flags.hideControls)
            (controller.value.position > Duration(milliseconds: 100) &&
                    !_showControls.value &&
                    widget.flags.showVideoProgressIndicator &&
                    !widget.flags.isLive &&
                    !controller.value.isFullScreen)
                ? Positioned(
                    bottom: -27.9,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      ignoring: true,
                      child: ProgressBar(
                        controller,
                        colors: ProgressColors(
                          handleColor: Colors.transparent,
                          playedColor: widget.videoProgressIndicatorColor,
                        ),
                      ),
                    ),
                  )
                : Container(),
          if (!widget.flags.hideControls)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: widget.flags.isLive
                  ? LiveBottomBar(
                      controller,
                      _showControls,
                      widget.aspectRatio,
                      widget.liveUIColor,
                      widget.flags.hideFullScreenButton,
                    )
                  : BottomBar(
                      controller,
                      _showControls,
                      widget.aspectRatio,
                      widget.progressColors,
                      widget.flags.hideFullScreenButton,
                    ),
            ),
          if (!widget.flags.hideControls && _showControls.value)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity:
                    (!widget.flags.hideControls && _showControls.value) ? 1 : 0,
                duration: Duration(milliseconds: 300),
                child: Row(
                  children: widget.actions ?? [Container()],
                ),
              ),
            ),
          if (!widget.flags.hideControls)
            Center(
              child: PlayPauseButton(
                controller,
                _showControls,
                widget.bufferIndicator ??
                    Container(
                      width: 70.0,
                      height: 70.0,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

/// [ValueNotifier] for [YoutubePlayerController].
class YoutubePlayerValue {
  YoutubePlayerValue({
    this.isReady = false,
    this.isEvaluationReady = false,
    this.isLoaded = false,
    this.hasPlayed = false,
    this.duration = const Duration(),
    this.position = const Duration(),
    this.buffered = 0.0,
    this.isPlaying = false,
    this.isFullScreen = false,
    this.volume = 100,
    this.playerState = PlayerState.UNKNOWN,
    this.playbackRate = PlaybackRate.NORMAL,
    this.errorCode = 0,
    this.webViewController,
  });

  /// This is true when underlying web player reports ready.
  final bool isReady;

  /// This is true when JavaScript evaluation can be triggered.
  final bool isEvaluationReady;

  /// This is true once video loads.
  final bool isLoaded;

  /// This is true once the video start playing for the first time.
  final bool hasPlayed;

  /// The total length of the video.
  final Duration duration;

  /// The current position of the video.
  final Duration position;

  /// The position up to which the video is buffered.
  final double buffered;

  /// Reports true if video is playing.
  final bool isPlaying;

  /// Reports true if video is fullscreen.
  final bool isFullScreen;

  /// The current volume assigned for the player.
  final int volume;

  /// The current state of the player defined as [PlayerState].
  final PlayerState playerState;

  /// The current video playback rate defined as [PlaybackRate].
  final PlaybackRate playbackRate;

  /// Reports the error code as described [here](https://developers.google.com/youtube/iframe_api_reference#Events).
  /// See the onError Section.
  final int errorCode;

  /// Reports the [WebViewController].
  final WebViewController webViewController;

  /// Returns true is player has errors.
  bool get hasError => errorCode != 0;

  YoutubePlayerValue copyWith({
    bool isReady,
    bool isEvaluationReady,
    bool isLoaded,
    bool hasPlayed,
    Duration duration,
    Duration position,
    double buffered,
    bool isPlaying,
    bool isFullScreen,
    double volume,
    PlayerState playerState,
    PlaybackRate playbackRate,
    int errorCode,
    WebViewController webViewController,
  }) {
    return YoutubePlayerValue(
      isReady: isReady ?? this.isReady,
      isEvaluationReady: isEvaluationReady ?? this.isEvaluationReady,
      isLoaded: isLoaded ?? this.isLoaded,
      duration: duration ?? this.duration,
      hasPlayed: hasPlayed ?? this.hasPlayed,
      position: position ?? this.position,
      buffered: buffered ?? this.buffered,
      isPlaying: isPlaying ?? this.isPlaying,
      isFullScreen: isFullScreen ?? this.isFullScreen,
      volume: volume ?? this.volume,
      playerState: playerState ?? this.playerState,
      playbackRate: playbackRate ?? this.playbackRate,
      errorCode: errorCode ?? this.errorCode,
      webViewController: webViewController ?? this.webViewController,
    );
  }

  @override
  String toString() {
    return '$runtimeType('
        'isReady: $isReady, '
        'isEvaluationReady: $isEvaluationReady, '
        'isLoaded: $isLoaded, '
        'duration: $duration, '
        'position: $position, '
        'buffered: $buffered, '
        'isPlaying: $isPlaying, '
        'volume: $volume, '
        'playerState: $playerState, '
        'playbackRate: $playbackRate, '
        'errorCode: $errorCode)';
  }
}

class YoutubePlayerController extends ValueNotifier<YoutubePlayerValue> {
  final String initialSource;

  YoutubePlayerController([
    this.initialSource = "",
  ]) : super(YoutubePlayerValue(isReady: false));

  _evaluateJS(String javascriptString) {
    value.webViewController?.evaluateJavascript(javascriptString);
  }

  /// Hide YouTube Player annotations like title, share button and youtube logo.
  /// It's hidden by default for iOS.
  void forceHideAnnotation() {
    if (Platform.isAndroid) {
      _evaluateJS('hideAnnotations()');
    }
  }

  /// Plays the video.
  void play() => _evaluateJS('play()');

  /// Pauses the video.
  void pause() => _evaluateJS('pause()');

  /// Loads the video as per the [videoId] provided.
  void load({int startAt = 0}) =>
      _evaluateJS('loadById("$initialSource", $startAt)');

  /// Cues the video as per the [videoId] provided.
  void cue({int startAt = 0}) =>
      _evaluateJS('cueById("$initialSource", $startAt)');

  /// Mutes the player.
  void mute() => _evaluateJS('mute()');

  /// Un mutes the player.
  void unMute() => _evaluateJS('unMute()');

  /// Sets the volume of player.
  /// Max = 100 , Min = 0
  void setVolume(int volume) => volume >= 0 && volume <= 100
      ? _evaluateJS('setVolume($volume)')
      : throw Exception("Volume should be between 0 and 100");

  /// Seek to any position. Video auto plays after seeking.
  /// The optional allowSeekAhead parameter determines whether the player will make a new request to the server
  /// if the seconds parameter specifies a time outside of the currently buffered video data.
  /// Default allowSeekAhead = true
  void seekTo(Duration position, {bool allowSeekAhead = true}) {
    _evaluateJS('seekTo(${position.inSeconds},$allowSeekAhead)');
    play();
    value = value.copyWith(position: position);
  }

  /// Sets the size in pixels of the player.
  void setSize(Size size) =>
      _evaluateJS('setSize(${size.width * 100},${size.height * 100})');

  void setPlaybackRate(PlaybackRate rate) {
    switch (rate) {
      case PlaybackRate.QUARTER:
        _evaluateJS('setPlaybackRate(0.25)');
        break;
      case PlaybackRate.HALF:
        _evaluateJS('setPlaybackRate(0.5)');
        break;
      case PlaybackRate.NORMAL:
        _evaluateJS('setPlaybackRate(1)');
        break;
      case PlaybackRate.ONE_AND_A_HALF:
        _evaluateJS('setPlaybackRate(1.5)');
        break;
      case PlaybackRate.DOUBLE:
        _evaluateJS('setPlaybackRate(2)');
        break;
    }
  }

  void setPlaybackRateWithDouble(double rate) {
    double bracketedRate = math.max(0.25, math.min(2.0, rate));
    _evaluateJS('setPlaybackRate($bracketedRate)');
  }

  void enterFullScreen() => value = value.copyWith(isFullScreen: true);

  void exitFullScreen() => value = value.copyWith(isFullScreen: false);
}
