import AVKit
import MediaPlayer

private let defaultPlaybackRate: Double = 1.0

private let defaultVolume: Double = 1.0

private let defaultReleaseMode: ReleaseMode = ReleaseMode.release

enum ReleaseMode: String {
  case stop
  case release
  case loop
}

// Plays media library items through MPMusicPlayerController instead of AVPlayer, so Apple Music
// songs without a local asset URL can play. The source url carries the item's persistent ID.
@MainActor class WrappedMediaPlayer {
  private(set) var eventHandler: AudioPlayersStreamHandler
  private(set) var isPlaying: Bool
  var releaseMode: ReleaseMode

  private var reference: AudioplayersDarwinPlugin
  private var player: MPMusicPlayerController
  private var playbackRate: Double
  private var volume: Double
  private var id: UInt64?

  private var nowPlayingItemObserver: NSObjectProtocol?

  init(
    reference: AudioplayersDarwinPlugin,
    eventHandler: AudioPlayersStreamHandler,
    player: MPMusicPlayerController = MPMusicPlayerController.applicationMusicPlayer,
    playbackRate: Double = defaultPlaybackRate,
    volume: Double = defaultVolume,
    releaseMode: ReleaseMode = defaultReleaseMode,
    id: UInt64? = nil
  ) {
    self.reference = reference
    self.eventHandler = eventHandler
    self.player = player

    self.isPlaying = false
    self.playbackRate = playbackRate
    self.volume = volume
    self.releaseMode = releaseMode
    self.id = id

    self.startNotifications()
  }

  func setSourceUrl(
    url: String,
    isLocal: Bool,
    mimeType: String? = nil
  ) async throws {
    guard let persistentId = UInt64(url) else {
      throw AudioPlayerError.error("ID not valid: \(url)")
    }
    self.id = persistentId
    let mediaItem = try createMediaItem(persistentId)
    setQueue(song: mediaItem)

    do {
      try await prepareToPlay()
    } catch {
      reset()
      throw error
    }
    updateDuration()
    eventHandler.onPrepared(isPrepared: true)
  }

  func getDuration() -> Int? {
    guard let duration = getDurationTimeInterval() else {
      return nil
    }
    return Int(duration) * 1000
  }

  func getCurrentPosition() -> Int? {
    guard let time = getCurrentTimeInterval() else {
      return nil
    }
    return Int(time) * 1000
  }

  func pause() {
    isPlaying = false
    player.pause()
  }

  func resume() {
    isPlaying = true
    player.play()
    updateDuration()
  }

  func setVolume(volume: Double) {
    self.volume = volume
  }

  func setPlaybackRate(playbackRate: Double) {
    self.playbackRate = playbackRate
    player.currentPlaybackRate = Float(playbackRate)
  }

  func seek(time: CMTime) async {
    player.currentPlaybackTime = CMTimeGetSeconds(time)
    eventHandler.onSeekComplete()
  }

  func stop() async {
    pause()
    if releaseMode == ReleaseMode.release {
      await release()
    } else {
      await seek(time: toCMTime(millis: 0))
    }
  }

  func release() async {
    if isPlaying {
      pause()
    }
    reset()
  }

  func dispose() async {
    await release()
    stopNotifications()
    eventHandler.dispose()
  }

  private func getDurationTimeInterval() -> TimeInterval? {
    return player.nowPlayingItem?.playbackDuration
  }

  private func getCurrentTimeInterval() -> TimeInterval? {
    return player.currentPlaybackTime
  }

  private func createMediaItem(_ id: UInt64) throws -> MPMediaItem {
    let songFilter = MPMediaPropertyPredicate(
      value: id, forProperty: MPMediaItemPropertyPersistentID, comparisonType: .equalTo)
    let query = MPMediaQuery(filterPredicates: Set([songFilter]))
    if let items = query.items, let song = items.first {
      return song
    } else {
      throw AudioPlayerError.error("ID not valid: \(id)")
    }
  }

  private func prepareToPlay() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      player.prepareToPlay { error in
        if let error = error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }

  // A finished queue changes the now playing item while the player is paused, which is how the
  // end of a song is detected.
  private func startNotifications() {
    player.beginGeneratingPlaybackNotifications()
    nowPlayingItemObserver = NotificationCenter.default.addObserver(
      forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
      object: player,
      queue: nil
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self = self, self.player.playbackState == .paused else {
          return
        }
        await self.onSoundComplete()
      }
    }
  }

  private func stopNotifications() {
    player.endGeneratingPlaybackNotifications()
    if let observer = nowPlayingItemObserver {
      NotificationCenter.default.removeObserver(observer)
      nowPlayingItemObserver = nil
    }
  }

  private func reset() {
    setQueue(song: nil)
    id = nil
  }

  private func updateDuration() {
    let duration = getDuration() ?? 0
    if duration > 0 {
      eventHandler.onDuration(millis: duration)
    }
  }

  private func onSoundComplete() async {
    if !isPlaying {
      return
    }

    await seek(time: toCMTime(millis: 0))
    if releaseMode == ReleaseMode.loop {
      resume()
    } else if releaseMode == ReleaseMode.release {
      await release()
    } else {
      isPlaying = false
    }

    reference.controlAudioSession()
    eventHandler.onComplete()
  }

  private func setQueue(song: MPMediaItem?) {
    if let song = song {
      let descriptor = MPMusicPlayerMediaItemQueueDescriptor(
        itemCollection: MPMediaItemCollection(items: [song]))
      player.setQueue(with: descriptor)
    } else {
      player.stop()
    }
  }
}
