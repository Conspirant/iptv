package com.nk.live_tv

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode

class MainActivity: FlutterActivity() {
    override fun getRenderMode(): RenderMode {
        // Forces FlutterActivity to render via TextureView instead of SurfaceView.
        // This permanently fixes the Android TV compositor "white screen" glitch
        // caused by SurfaceView hole-punching on Android TV chipsets.
        return RenderMode.texture
    }
}
