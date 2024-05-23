package xyz.luan.audioplayers.source

import android.content.Context
import android.media.MediaPlayer
import xyz.luan.audioplayers.player.SoundPoolPlayer

class ContentSource(
    private val contentPath: String,
    private val context: Context,
) : Source {
    override fun setForMediaPlayer(mediaPlayer: MediaPlayer) {
        val uri = android.net.Uri.parse(contentPath)
        mediaPlayer.setDataSource(context, uri)
    }

    override fun setForSoundPool(soundPoolPlayer: SoundPoolPlayer) {
        error("Not supported")
    }
}
