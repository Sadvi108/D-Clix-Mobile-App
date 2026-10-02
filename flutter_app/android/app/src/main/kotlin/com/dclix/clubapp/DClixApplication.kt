package com.dclix.clubapp

import android.app.Application
import com.onesignal.OneSignal

// onesignal:managed v1 — migrate saved installations before Flutter initializes.
class DClixApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.ONESIGNAL_APP_ID.isNotEmpty()) {
            OneSignal.initWithContext(this, BuildConfig.ONESIGNAL_APP_ID)
        }
    }
}
