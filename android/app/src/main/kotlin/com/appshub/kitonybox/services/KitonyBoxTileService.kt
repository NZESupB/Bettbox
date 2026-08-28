package com.appshub.kitonybox.services

import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import com.appshub.kitonybox.GlobalState
import com.appshub.kitonybox.RunState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

@RequiresApi(Build.VERSION_CODES.N)
class KitonyBoxTileService : TileService() {

    private var scope: CoroutineScope? = null

    private fun updateTile(runState: RunState) {
        qsTile?.apply {
            state = when (runState) {
                RunState.START -> Tile.STATE_ACTIVE
                RunState.PENDING -> Tile.STATE_UNAVAILABLE
                RunState.STOP -> Tile.STATE_INACTIVE
            }
            if (GlobalState.isSpeedNotificationEnabled && GlobalState.currentProfileName.isNotEmpty()) {
                label = GlobalState.currentProfileName
            } else {
                label = "KitonyBox"
            }
            updateTile()
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        GlobalState.syncStatus()
        updateTile(GlobalState.currentRunState)
        scope?.launch {
            GlobalState.runState.onEach { updateTile(it) }.launchIn(this)
        }
    }

    override fun onStopListening() {
        if (GlobalState.currentRunState == RunState.PENDING) {
            GlobalState.syncStatus()
        }
        scope?.cancel()
        scope = null
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE && isLocked) {
            unlockAndRun { GlobalState.handleToggle() }
        } else {
            GlobalState.handleToggle()
        }
    }

    override fun onDestroy() {
        scope?.cancel()
        scope = null
        super.onDestroy()
    }
}