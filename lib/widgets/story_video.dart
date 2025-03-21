import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:story_view/widgets/story_view.dart';
import 'package:video_player/video_player.dart';

import '../utils.dart';
import '../controller/story_controller.dart';

class VideoLoader {
  String url;

  File? videoFile;

  Map<String, dynamic>? requestHeaders;

  LoadState state = LoadState.loading;

  VideoLoader(this.url, {this.requestHeaders});

  void loadVideo(VoidCallback onComplete) {
    if (this.videoFile != null) {
      this.state = LoadState.success;
      onComplete();
      return; // Exit early if the video is already loaded
    }

    final fileStream = DefaultCacheManager().getFileStream(
      this.url,
      headers: this.requestHeaders as Map<String, String>?,
    );

    fileStream.listen((fileResponse) async {

      if (fileResponse is FileInfo) {
        if (this.videoFile == null) {
          File originalFile = fileResponse.file;

          // Ensure file has .mp4 extension
          String newPath = originalFile.path.replaceAll('.bin', '.${this.url.split(".").last}');
          File mp4File = await originalFile.rename(newPath);

          // Cache the renamed file
          await DefaultCacheManager().putFile(
            this.url,
            mp4File.readAsBytesSync(),
            fileExtension: this.url.split(".").last,
          );

          this.state = LoadState.success;
          this.videoFile = mp4File;
          onComplete();
        }
      }
    });
  }
}

class StoryVideo extends StatefulWidget {
  final StoryController? storyController;
  final VideoLoader videoLoader;
  final Widget? loadingWidget;
  final Widget? errorWidget;

  StoryVideo(this.videoLoader, {
    Key? key,
    this.storyController,
    this.loadingWidget,
    this.errorWidget,
  }) : super(key: key ?? UniqueKey());

  static StoryVideo url(String url, {
    StoryController? controller,
    Map<String, dynamic>? requestHeaders,
    Key? key,
    Widget? loadingWidget,
    Widget? errorWidget,
  }) {
    return StoryVideo(
      VideoLoader(url, requestHeaders: requestHeaders),
      storyController: controller,
      key: key,
      loadingWidget: loadingWidget,
      errorWidget: errorWidget,
    );
  }

  @override
  State<StatefulWidget> createState() {
    return StoryVideoState();
  }
}

class StoryVideoState extends State<StoryVideo> {
  Future<void>? playerLoader;

  StreamSubscription? _streamSubscription;

  VideoPlayerController? playerController;

  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();

    widget.storyController!.pause();

    widget.videoLoader.loadVideo(() {
      if(_isDisposed) return;
      if (widget.videoLoader.state == LoadState.success) {
        this.playerController =
            VideoPlayerController.file(widget.videoLoader.videoFile!);

        playerController!.initialize().then((v) {
          setState(() {});
          _updateDuration(playerController!.value.duration);
          widget.storyController!.play();
        });

        if (widget.storyController != null) {
          _streamSubscription =
              widget.storyController!.playbackNotifier.listen((playbackState) {
                if (playbackState == PlaybackState.pause) {
                  playerController!.pause();
                } else {
                  playerController!.play();
                }
              });
        }
      } else {
        setState(() {});
      }
    });
  }

  void _updateDuration(Duration duration) {
    final state = context.findAncestorStateOfType<StoryViewState>();
    state?.setCurrentStoryItemDuration(duration);
  }

  Widget getContentView() {
    if (widget.videoLoader.state == LoadState.success &&
        playerController!.value.isInitialized) {
      return Center(
        child: AspectRatio(
          aspectRatio: playerController!.value.aspectRatio,
          child: VideoPlayer(playerController!),
        ),
      );
    }

    return widget.videoLoader.state == LoadState.loading
        ? Center(
      child: widget.loadingWidget?? Container(
        width: 70,
        height: 70,
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          strokeWidth: 3,
        ),
      ),
    )
        : Center(
        child: widget.errorWidget?? Text(
          "Media failed to load.",
          style: TextStyle(
            color: Colors.white,
          ),
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      height: double.infinity,
      width: double.infinity,
      child: getContentView(),
    );
  }

  @override
  void dispose() {
    playerController?.dispose();
    _streamSubscription?.cancel();
    _isDisposed = true;
    super.dispose();
  }
}
