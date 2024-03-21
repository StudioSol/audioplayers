import Foundation
import MediaPlayer

private let defaultPlaybackRate: Double = 1.0
private let defaultVolume: Double = 1.0
private let defaultLooping: Bool = false

typealias Completer = () -> Void
typealias CompleterError = () -> Void
typealias StateUpdateDelegate = (MPMusicPlayerController) -> Void

class WrappedMediaPlayer {
  private(set) var eventHandler: AudioPlayersStreamHandler
  private(set) var isPlaying: Bool
  var looping: Bool

  private var reference: SwiftAudioplayersDarwinPlugin
  private var player: MPMusicPlayerController
  private var playbackRate: Double
  private var volume: Double
  private var id: UInt64?

    var stateUpdateDelegate: StateUpdateDelegate?

  init(
    reference: SwiftAudioplayersDarwinPlugin,
    eventHandler: AudioPlayersStreamHandler,
    player: MPMusicPlayerController = MPMusicPlayerController.applicationMusicPlayer,
    playbackRate: Double = defaultPlaybackRate,
    volume: Double = defaultVolume,
    looping: Bool = defaultLooping,
    url: UInt64? = nil
  ) {
    self.reference = reference
    self.eventHandler = eventHandler
    self.player = player

    self.isPlaying = false
    self.playbackRate = playbackRate
    self.volume = volume
    self.looping = looping
    self.id = url

    self.startNotifications()
  }

  func setSourceUrl(
    url: String,
    isLocal: Bool,
    completer: Completer? = nil,
    completerError: CompleterError? = nil
  ) {
      let persistentId = UInt64(url)
      let playbackStatus = player.playbackState

      if self.id != persistentId || playbackStatus == .interrupted || playbackStatus == .stopped {
      reset()
      self.id = persistentId
      do {
        let playerItem = try createPlayerItem(persistentId!, isLocal)
        // Need to observe item status immediately after creating:
//        setUpPlayerItemStatusObservation(
//          player,
//          completer: completer,
//          completerError: completerError)
        // Replacing the player item triggers completion in setUpPlayerItemStatusObservation
        replaceItem(with: playerItem)
//        self.setUpSoundCompletedObserver(self.player, playerItem)
      } catch {
        completerError?()
      }
    } else {
        if player.isPreparedToPlay {
        completer?()
      }
    }
  }

  func getDuration() -> Int? {
    guard let duration = getDurationTimeInterval() else {
      return nil
    }
    return Int(duration)
  }

  func getCurrentPosition() -> Int? {
    guard let time = getCurrentTimeInterval() else {
      return nil
    }
    return Int(time)
  }

  func pause() {
    isPlaying = false
    player.pause()
  }

  func resume() {
    isPlaying = true
    configParameters(player: player)
      player.play()
    updateDuration()
  }

  func setVolume(volume: Double) {
    self.volume = volume
      let volumeView = MPVolumeView()
      let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider;             DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.01) {
    slider?.value = Float(volume)
    }
  }

  func setPlaybackRate(playbackRate: Double) {
    self.playbackRate = playbackRate
    if isPlaying {
      // Setting the rate causes the player to resume playing. So setting it only, when already playing.
      player.currentPlaybackRate = Float(playbackRate)
    }
  }

  func seek(time: Float, completer: Completer? = nil) {
      let currentTime = player.currentPlaybackTime
      let seekTime = currentTime + TimeInterval(time)

      if currentTime > TimeInterval(time) {
          while currentTime != seekTime {
              player.beginSeekingForward()
          }
          player.endSeeking()
          completer?()
          self.eventHandler.onSeekComplete()
          return
      } else {
          while currentTime != seekTime {
              player.beginSeekingBackward()
          }
          player.endSeeking()
          completer?()
          self.eventHandler.onSeekComplete()
          return
      }
  }

  func stop(completer: Completer? = nil) {
    pause()
    seek(time: Float(0), completer: completer)
  }

  func release(completer: Completer? = nil) {
    stop {
      self.reset()
      self.id = nil
      completer?()
    }
  }

  func dispose(completer: Completer? = nil) {
      player.endGeneratingPlaybackNotifications()
    release {
        self.stopNotifications()
      completer?()
    }
  }

  private func getDurationTimeInterval() -> TimeInterval? {
      return player.nowPlayingItem?.playbackDuration
  }

  private func getCurrentTimeInterval() -> TimeInterval? {
      return player.currentPlaybackTime
  }

  private func createPlayerItem(_ id: UInt64, _ isLocal: Bool) throws -> MPMediaItem {
      let songFilter = MPMediaPropertyPredicate(value: id, forProperty: MPMediaItemPropertyPersistentID, comparisonType: .equalTo)
    let query = MPMediaQuery(filterPredicates: Set([songFilter]))
      if let items = query.items, let song = items.first {
          return song
      } else {
          throw AudioPlayerError.error("ID not valid: \(id)")
      }
  }

    public func startNotifications() {
            player.beginGeneratingPlaybackNotifications()
            NotificationCenter.default.addObserver(self,
                selector: #selector(stateChanged),
                name: .MPMusicPlayerControllerPlaybackStateDidChange,
                object: player)
            NotificationCenter.default.addObserver(self,
                selector: #selector(stateChanged),
                name: .MPMusicPlayerControllerNowPlayingItemDidChange,
                object: player)
        }

    public func stopNotifications() {
            player.endGeneratingPlaybackNotifications()
            NotificationCenter.default.removeObserver(self,
                name: .MPMusicPlayerControllerPlaybackStateDidChange,
                object: player)
            NotificationCenter.default.removeObserver(self,
                name: .MPMusicPlayerControllerNowPlayingItemDidChange,
                object: player)
        }

  private func configParameters(player: MPMusicPlayerController) {
    if isPlaying {
        self.setVolume(volume: volume)
      player.currentPlaybackRate = Float(playbackRate)
    }
  }

  private func reset() {
    stopNotifications()
    replaceItem(with: nil)
  }

  private func updateDuration() {
      let current: Double = player.currentPlaybackTime
      let durationTotal: Double = player.nowPlayingItem!.playbackDuration
      let duration = current / durationTotal
        if duration > 0 {
            let millis = Int(duration) * 1000
          eventHandler.onDuration(millis: millis)
        }
  }

  private func onSoundComplete() {
    if !isPlaying {
      return
    }

    seek(time: 0) {
      if self.looping {
        self.resume()
      } else {
        self.isPlaying = false
      }
    }

    reference.controlAudioSession()
    eventHandler.onComplete()
  }

    private func replaceItem(with: MPMediaItem?) {
        setQueue(song: with)
    }

    private func setQueue(song: MPMediaItem?) {
        if song == nil {
            player.stop()
        } else {
            let descriptor = MPMusicPlayerMediaItemQueueDescriptor(itemCollection: MPMediaItemCollection(items: [song!]))
            player.setQueue(with: descriptor)
        }
    }

    @objc private func stateChanged(notification: NSNotification) {
        stateUpdateDelegate?(player)
    }
}
