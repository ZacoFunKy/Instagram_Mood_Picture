package com.moodpredictor.app

import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.LOLLIPOP)
class NotificationListener : NotificationListenerService() {
    
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        // Called when a notification is posted
        // Can be used to detect media changes
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // Called when a notification is removed
    }
}
